package com.mobilecode.mobile_agent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.Collections
import java.util.Locale
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

class MobileCodeHelperService : Service() {
    private var serverSocket: ServerSocket? = null
    private var serverThread: Thread? = null

    private val appDataRoot: File
        get() = File(applicationInfo.dataDir).canonicalFile

    private val defaultWorkspaceRoot: File
        get() = File(filesDir, "mobilecode_runtime").apply { mkdirs() }.canonicalFile

    private val taskStateFile: File
        get() = File(defaultWorkspaceRoot, "helper_task_state.json")

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        loadPersistedTask()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopCurrentProcess()
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, buildNotification("Helper daemon listening on 127.0.0.1:$PORT"))
        startServer()
        return START_STICKY
    }

    override fun onDestroy() {
        stopServer()
        stopCurrentProcess()
        running = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startServer() {
        if (serverThread?.isAlive == true) return

        running = true
        lastError = ""
        serverThread = thread(name = "MobileCodeHelperServer", isDaemon = true) {
            try {
                val socket = ServerSocket().apply {
                    reuseAddress = true
                    bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), PORT))
                }
                serverSocket = socket
                recordLog("helper: listening on 127.0.0.1:$PORT")

                while (!socket.isClosed) {
                    val client = socket.accept()
                    thread(name = "MobileCodeHelperClient", isDaemon = true) {
                        client.use { handleClient(it) }
                    }
                }
            } catch (error: Throwable) {
                if (running) {
                    lastError = error.message ?: error.javaClass.simpleName
                    recordLog("helper error: $lastError")
                }
            }
        }
    }

    private fun stopServer() {
        running = false
        try {
            serverSocket?.close()
        } catch (_: Throwable) {
        }
        serverSocket = null
    }

    private fun handleClient(socket: Socket) {
        val reader = BufferedReader(InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8))
        val requestLine = reader.readLine() ?: return
        val parts = requestLine.split(" ")
        if (parts.size < 2) {
            writeJson(socket, 400, JSONObject().put("success", false).put("error", "Malformed request line"))
            return
        }

        val method = parts[0]
        val path = parts[1].substringBefore("?")
        val headers = mutableMapOf<String, String>()
        while (true) {
            val line = reader.readLine() ?: return
            if (line.isEmpty()) break
            val index = line.indexOf(":")
            if (index > 0) {
                headers[line.substring(0, index).trim().lowercase(Locale.US)] = line.substring(index + 1).trim()
            }
        }

        val body = readBody(reader, headers["content-length"]?.toIntOrNull() ?: 0)
        try {
            when {
                method == "GET" && path == "/v1/health" -> writeJson(socket, 200, healthJson())
                method == "GET" && path == "/v1/tasks/current" -> writeJson(socket, 200, taskJson())
                method == "POST" && path == "/v1/execute" -> handleExecute(socket, body)
                method == "POST" && path == "/v1/execute/stream" -> handleExecuteStream(socket, body)
                method == "POST" && path == "/v1/task/stop" -> {
                    val stopped = stopCurrentProcess()
                    writeJson(socket, 200, JSONObject().put("success", true).put("stopped", stopped))
                }
                else -> writeJson(socket, 404, JSONObject().put("success", false).put("error", "Unknown endpoint"))
            }
        } catch (error: Throwable) {
            writeJson(socket, 400, JSONObject().put("success", false).put("error", error.message ?: error.javaClass.simpleName))
        }
    }

    private fun handleExecute(socket: Socket, body: String) {
        val payload = if (body.isBlank()) JSONObject() else JSONObject(body)
        val command = payload.optString("command", "")
        val args = commandArgs(command)
        val cwd = validateCwd(payload.optString("cwd", ""))
        val timeoutMs = payload.optLong("timeoutMs", 120_000L)
        val env = envFromJson(payload)
        val taskId = UUID.randomUUID().toString()
        beginTask(taskId, command, cwd)
        recordLog("task $taskId: $command")

        val started = System.nanoTime()
        val process = ProcessBuilder(args)
            .directory(cwd)
            .redirectErrorStream(false)
            .apply { environment().putAll(env) }
            .start()

        currentProcess = process
        val stdout = StringBuilder()
        val stderr = StringBuilder()
        val stdoutThread = thread(isDaemon = true) {
            process.inputStream.bufferedReader().forEachLine {
                stdout.appendLine(it)
                recordLog("stdout: $it")
            }
        }
        val stderrThread = thread(isDaemon = true) {
            process.errorStream.bufferedReader().forEachLine {
                stderr.appendLine(it)
                recordLog("stderr: $it")
            }
        }

        val finished = process.waitFor(timeoutMs.coerceAtLeast(1), TimeUnit.MILLISECONDS)
        if (!finished) {
            process.destroyForcibly()
            stderr.appendLine("Command timed out after ${timeoutMs}ms.")
            recordLog("task timed out after ${timeoutMs}ms")
        }
        stdoutThread.join(500)
        stderrThread.join(500)
        val exitCode = if (finished) process.exitValue() else 124
        val durationMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started)
        if (currentProcess == process) currentProcess = null
        val finalStatus = when {
            currentTaskStatus == "cancelled" -> "cancelled"
            !finished -> "timedOut"
            exitCode == 0 -> "succeeded"
            else -> "failed"
        }
        val stderrText = stderr.toString().trim()
        finishTask(finalStatus, exitCode, durationMs, if (stderrText.isBlank()) null else stderrText)

        writeJson(
            socket,
            200,
            JSONObject()
                .put("command", command)
                .put("stdout", stdout.toString())
                .put("stderr", stderr.toString())
                .put("exitCode", exitCode)
                .put("durationMs", durationMs)
                .put("taskId", taskId)
        )
    }

    private fun handleExecuteStream(socket: Socket, body: String) {
        val payload = if (body.isBlank()) JSONObject() else JSONObject(body)
        val command = payload.optString("command", "")
        val args = commandArgs(command)
        val cwd = validateCwd(payload.optString("cwd", ""))
        val env = envFromJson(payload)
        val taskId = UUID.randomUUID().toString()
        beginTask(taskId, command, cwd)
        recordLog("task $taskId stream: $command")

        val output = socket.getOutputStream()
        writeHeaders(output, 200, "application/x-ndjson", null)
        val started = System.nanoTime()
        val process = ProcessBuilder(args)
            .directory(cwd)
            .redirectErrorStream(false)
            .apply { environment().putAll(env) }
            .start()

        currentProcess = process
        val writeLock = Any()
        val stdoutThread = thread(isDaemon = true) {
            process.inputStream.bufferedReader().forEachLine { line ->
                writeNdjson(output, writeLock, JSONObject().put("type", "stdout").put("data", line))
                recordLog("stdout: $line")
            }
        }
        val stderrThread = thread(isDaemon = true) {
            process.errorStream.bufferedReader().forEachLine { line ->
                writeNdjson(output, writeLock, JSONObject().put("type", "stderr").put("data", line))
                recordLog("stderr: $line")
            }
        }
        val exitCode = process.waitFor()
        stdoutThread.join(500)
        stderrThread.join(500)
        val durationMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started)
        val finalStatus = if (currentTaskStatus == "cancelled") {
            "cancelled"
        } else if (exitCode == 0) {
            "succeeded"
        } else {
            "failed"
        }
        finishTask(finalStatus, exitCode, durationMs, null)
        writeNdjson(
            output,
            writeLock,
            JSONObject().put("type", "exit").put("exitCode", exitCode).put("durationMs", durationMs).put("taskId", taskId)
        )
        if (currentProcess == process) currentProcess = null
    }

    private fun healthJson(): JSONObject {
        return JSONObject()
            .put("name", "MobileCode Helper Service")
            .put("available", true)
            .put("ready", running)
            .put("status", if (lastError.isBlank()) "Android foreground service is running." else lastError)
            .put(
                "capabilities",
                JSONObject()
                    .put("shell", true)
                    .put("git", hasBinary("git"))
                    .put("node", hasBinary("node") || hasBinary("npm"))
                    .put("python", hasBinary("python") || hasBinary("python3"))
                    .put("flutter", hasBinary("flutter"))
                    .put("androidBuild", hasBinary("flutter") && hasBinary("java"))
                    .put("pty", false)
                    .put("backgroundService", true)
                    .put("webViewPreview", true)
                    .put("cloudBuild", false)
            )
            .put("missingDependencies", JSONArray())
            .put("recoveryActions", JSONArray())
    }

    private fun taskJson(): JSONObject {
        val snapshot = taskSnapshotJson()
        return JSONObject()
            .put("running", currentProcess != null)
            .put("taskId", currentTaskId)
            .put("command", currentCommand)
            .put("logs", snapshot.optJSONArray("logs") ?: JSONArray())
            .put("task", snapshot)
    }

    private fun beginTask(taskId: String, command: String, cwd: File) {
        synchronized(taskLock) {
            currentTaskId = taskId
            currentCommand = command
            currentTaskCwd = cwd.path
            currentTaskStatus = "running"
            currentTaskStartedAtMs = System.currentTimeMillis()
            currentTaskFinishedAtMs = 0L
            currentTaskExitCode = null
            currentTaskDurationMs = 0L
            currentTaskError = ""
            synchronized(recentLogs) {
                recentLogs.clear()
            }
            persistTaskStateLocked()
        }
    }

    private fun finishTask(status: String, exitCode: Int, durationMs: Long, error: String?) {
        synchronized(taskLock) {
            currentTaskStatus = status
            currentTaskFinishedAtMs = System.currentTimeMillis()
            currentTaskExitCode = exitCode
            currentTaskDurationMs = durationMs
            currentTaskError = error ?: ""
            persistTaskStateLocked()
        }
    }

    private fun recordLog(line: String) {
        synchronized(taskLock) {
            appendLog(line)
            persistTaskStateLocked()
        }
    }

    private fun loadPersistedTask() {
        synchronized(taskLock) {
            val file = taskStateFile
            if (!file.exists()) return
            try {
                val json = JSONObject(file.readText())
                currentTaskId = json.optString("id", "")
                currentCommand = json.optString("command", "")
                currentTaskCwd = json.optString("cwd", "")
                currentTaskStatus = json.optString("status", "unknown")
                currentTaskStartedAtMs = json.optLong("startedAtMs", 0L)
                currentTaskFinishedAtMs = json.optLong("finishedAtMs", 0L)
                currentTaskExitCode = if (json.has("exitCode") && !json.isNull("exitCode")) json.optInt("exitCode") else null
                currentTaskDurationMs = json.optLong("durationMs", 0L)
                currentTaskError = json.optString("error", "")
                synchronized(recentLogs) {
                    recentLogs.clear()
                    val logs = json.optJSONArray("logs") ?: JSONArray()
                    for (index in 0 until logs.length()) {
                        recentLogs.add(logs.optString(index))
                    }
                }
                if (currentTaskStatus == "running" && currentProcess == null) {
                    currentTaskStatus = "lost"
                    currentTaskFinishedAtMs = System.currentTimeMillis()
                    currentTaskError = "Helper service restarted before this task completed."
                    appendLog("task lost after helper restart")
                    persistTaskStateLocked()
                }
            } catch (error: Throwable) {
                lastError = "failed to load task state: ${error.message ?: error.javaClass.simpleName}"
            }
        }
    }

    private fun persistTaskStateLocked() {
        if (currentTaskId.isBlank() && currentCommand.isBlank()) return
        try {
            val file = taskStateFile
            file.parentFile?.mkdirs()
            file.writeText(taskSnapshotJson().toString())
        } catch (error: Throwable) {
            lastError = "failed to persist task state: ${error.message ?: error.javaClass.simpleName}"
        }
    }

    private fun taskSnapshotJson(): JSONObject {
        val logs = JSONArray()
        synchronized(recentLogs) {
            recentLogs.forEach { logs.put(it) }
        }
        val json = JSONObject()
            .put("id", currentTaskId)
            .put("taskId", currentTaskId)
            .put("command", currentCommand)
            .put("cwd", currentTaskCwd)
            .put("status", if (currentTaskStatus.isBlank()) "unknown" else currentTaskStatus)
            .put("startedAtMs", currentTaskStartedAtMs)
            .put("finishedAtMs", currentTaskFinishedAtMs)
            .put("durationMs", currentTaskDurationMs)
            .put("logs", logs)
            .put("provider", "mobileCodeHelper")
        if (currentTaskExitCode != null) json.put("exitCode", currentTaskExitCode)
        if (currentTaskError.isNotBlank()) json.put("error", currentTaskError)
        return json
    }

    private fun validateCwd(rawCwd: String): File {
        val cwd = if (rawCwd.isBlank()) defaultWorkspaceRoot else File(rawCwd).canonicalFile
        val rootPath = appDataRoot.path
        if (cwd.path == rootPath || cwd.path.startsWith(rootPath + File.separator)) {
            if (!cwd.exists()) cwd.mkdirs()
            return cwd
        }
        throw IllegalArgumentException("cwd is outside MobileCode app data: ${cwd.path}")
    }

    private fun commandArgs(command: String): List<String> {
        if (command.isBlank()) throw IllegalArgumentException("command cannot be empty")
        val lowered = command.lowercase(Locale.US)
        dangerousFragments.forEach { fragment ->
            if (lowered.contains(fragment)) throw IllegalArgumentException("dangerous command fragment blocked: $fragment")
        }
        val parts = splitCommand(command)
        if (parts.isEmpty()) throw IllegalArgumentException("command cannot be empty")
        var executable = File(parts[0]).name.lowercase(Locale.US)
        if (executable.endsWith(".exe")) executable = executable.removeSuffix(".exe")
        if (!allowedCommands.contains(executable)) {
            throw IllegalArgumentException("command is not allowed: $executable")
        }
        return parts
    }

    private fun splitCommand(command: String): List<String> {
        val result = mutableListOf<String>()
        val current = StringBuilder()
        var quote: Char? = null
        var escaped = false
        for (char in command) {
            when {
                escaped -> {
                    current.append(char)
                    escaped = false
                }
                char == '\\' -> escaped = true
                quote != null && char == quote -> quote = null
                quote == null && (char == '"' || char == '\'') -> quote = char
                quote == null && char.isWhitespace() -> {
                    if (current.isNotEmpty()) {
                        result.add(current.toString())
                        current.clear()
                    }
                }
                else -> current.append(char)
            }
        }
        if (quote != null) throw IllegalArgumentException("unterminated quote in command")
        if (current.isNotEmpty()) result.add(current.toString())
        return result
    }

    private fun envFromJson(payload: JSONObject): Map<String, String> {
        val env = payload.optJSONObject("env") ?: return emptyMap()
        val result = mutableMapOf<String, String>()
        val keys = env.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            result[key] = env.optString(key)
        }
        return result
    }

    private fun hasBinary(name: String): Boolean {
        val path = System.getenv("PATH") ?: return false
        return path.split(File.pathSeparator).any { directory ->
            val candidate = File(directory, name)
            candidate.exists() && candidate.canExecute()
        }
    }

    private fun stopCurrentProcess(): Boolean {
        val process = currentProcess ?: return false
        return try {
            process.destroy()
            if (!process.waitFor(2, TimeUnit.SECONDS)) {
                process.destroyForcibly()
            }
            currentProcess = null
            currentTaskStatus = "cancelled"
            currentTaskFinishedAtMs = System.currentTimeMillis()
            currentTaskError = "Task cancelled by MobileCode."
            recordLog("task stopped")
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun readBody(reader: BufferedReader, contentLength: Int): String {
        if (contentLength <= 0) return ""
        val buffer = CharArray(contentLength)
        var read = 0
        while (read < contentLength) {
            val count = reader.read(buffer, read, contentLength - read)
            if (count < 0) break
            read += count
        }
        return String(buffer, 0, read)
    }

    private fun writeJson(socket: Socket, statusCode: Int, payload: JSONObject) {
        val body = payload.toString()
        val output = socket.getOutputStream()
        writeHeaders(output, statusCode, "application/json", body.toByteArray(StandardCharsets.UTF_8).size)
        output.write(body.toByteArray(StandardCharsets.UTF_8))
        output.flush()
    }

    private fun writeHeaders(output: java.io.OutputStream, statusCode: Int, contentType: String, contentLength: Int?) {
        val reason = when (statusCode) {
            200 -> "OK"
            400 -> "Bad Request"
            404 -> "Not Found"
            else -> "OK"
        }
        val headers = buildString {
            append("HTTP/1.1 $statusCode $reason\r\n")
            append("Content-Type: $contentType\r\n")
            append("Connection: close\r\n")
            if (contentLength != null) append("Content-Length: $contentLength\r\n")
            append("\r\n")
        }
        output.write(headers.toByteArray(StandardCharsets.UTF_8))
        output.flush()
    }

    private fun writeNdjson(output: java.io.OutputStream, lock: Any, payload: JSONObject) {
        synchronized(lock) {
            output.write((payload.toString() + "\n").toByteArray(StandardCharsets.UTF_8))
            output.flush()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "MobileCode Helper Runtime",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pendingIntent = launchIntent?.let { PendingIntent.getActivity(this, 0, it, flags) }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentTitle("MobileCode Helper")
            .setContentText(text)
            .setOngoing(true)
        if (pendingIntent != null) builder.setContentIntent(pendingIntent)
        return builder.build()
    }

    companion object {
        const val ACTION_STOP = "com.mobilecode.mobile_agent.action.STOP_HELPER"
        private const val CHANNEL_ID = "mobilecode_helper_runtime"
        private const val NOTIFICATION_ID = 8765
        private const val PORT = 8765
        private const val MAX_LOG_LINES = 200

        @Volatile private var running = false
        @Volatile private var lastError = ""
        @Volatile private var currentProcess: Process? = null
        @Volatile private var currentTaskId = ""
        @Volatile private var currentCommand = ""
        @Volatile private var currentTaskCwd = ""
        @Volatile private var currentTaskStatus = "unknown"
        @Volatile private var currentTaskStartedAtMs = 0L
        @Volatile private var currentTaskFinishedAtMs = 0L
        @Volatile private var currentTaskExitCode: Int? = null
        @Volatile private var currentTaskDurationMs = 0L
        @Volatile private var currentTaskError = ""
        private val taskLock = Any()
        private val recentLogs = Collections.synchronizedList(mutableListOf<String>())

        fun status(): Map<String, Any> {
            return mapOf(
                "running" to running,
                "port" to PORT,
                "lastError" to lastError,
                "taskId" to currentTaskId,
                "command" to currentCommand,
                "taskRunning" to (currentProcess != null),
                "taskStatus" to currentTaskStatus,
                "taskStartedAtMs" to currentTaskStartedAtMs,
                "taskFinishedAtMs" to currentTaskFinishedAtMs
            )
        }

        private fun appendLog(line: String) {
            synchronized(recentLogs) {
                recentLogs.add(line)
                while (recentLogs.size > MAX_LOG_LINES) {
                    recentLogs.removeAt(0)
                }
            }
        }

        private val allowedCommands = setOf(
            "pwd", "ls", "cat", "head", "tail", "grep", "find", "wc", "sort", "uniq",
            "sed", "awk", "mkdir", "touch", "cp", "mv", "rm", "git", "node", "npm",
            "npx", "python", "python3", "pip", "pip3", "dart", "flutter", "java",
            "javac", "gradle", "chmod", "tar", "zip", "unzip", "curl", "wget",
            "which", "whoami", "date", "echo"
        )

        private val dangerousFragments = listOf(
            "rm -rf /",
            "rm -rf /*",
            "mkfs",
            "dd if=",
            ":(){:|:&};:",
            "chmod -r 777 /",
            "chown -r",
            "reboot",
            "shutdown",
            "poweroff",
            "su "
        )
    }
}
