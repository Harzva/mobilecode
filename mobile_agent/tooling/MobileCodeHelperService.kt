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
import java.net.URLDecoder
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

    private val taskDatabaseFile: File
        get() = File(defaultWorkspaceRoot, "helper_tasks.json")

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
        val rawPath = parts[1]
        val path = rawPath.substringBefore("?")
        val query = rawPath.substringAfter("?", "")
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
                method == "GET" && path == "/v1/tasks" -> writeJson(socket, 200, taskHistoryJson(queryLimit(query, 20)))
                method == "GET" && path.startsWith("/v1/tasks/") && path.endsWith("/logs") -> {
                    val taskId = path.removePrefix("/v1/tasks/").removeSuffix("/logs").trim('/')
                    writeJson(socket, 200, taskLogsJson(taskId, queryLimit(query, 200)))
                }
                method == "POST" && path == "/v1/execute" -> handleExecute(socket, body)
                method == "POST" && path == "/v1/execute/stream" -> handleExecuteStream(socket, body)
                method == "POST" && path == "/v1/project/preflight" -> handleProjectPreflight(socket, body)
                method == "POST" && path == "/v1/task/stop" -> {
                    writeJson(socket, 200, stopTask(null))
                }
                method == "POST" && path.startsWith("/v1/tasks/") && path.endsWith("/stop") -> {
                    val taskId = decodePathSegment(path.removePrefix("/v1/tasks/").removeSuffix("/stop").trim('/'))
                    val result = stopTask(taskId)
                    writeJson(socket, if (result.optBoolean("success", false)) 200 else 404, result)
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
        recordLog(taskId, "task $taskId: $command")

        val started = System.nanoTime()
        val process = ProcessBuilder(args)
            .directory(cwd)
            .redirectErrorStream(false)
            .apply { environment().putAll(env) }
            .start()

        registerTaskProcess(taskId, process)
        val stdout = StringBuilder()
        val stderr = StringBuilder()
        val stdoutThread = thread(isDaemon = true) {
            process.inputStream.bufferedReader().forEachLine {
                stdout.appendLine(it)
                recordLog(taskId, "stdout: $it")
            }
        }
        val stderrThread = thread(isDaemon = true) {
            process.errorStream.bufferedReader().forEachLine {
                stderr.appendLine(it)
                recordLog(taskId, "stderr: $it")
            }
        }

        val finished = process.waitFor(timeoutMs.coerceAtLeast(1), TimeUnit.MILLISECONDS)
        if (!finished) {
            process.destroyForcibly()
            stderr.appendLine("Command timed out after ${timeoutMs}ms.")
            recordLog(taskId, "task timed out after ${timeoutMs}ms")
        }
        stdoutThread.join(500)
        stderrThread.join(500)
        val exitCode = if (finished) process.exitValue() else 124
        val durationMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started)
        clearTaskProcess(taskId, process)
        val finalStatus = when {
            isTaskCancelled(taskId) -> "cancelled"
            !finished -> "timedOut"
            exitCode == 0 -> "succeeded"
            else -> "failed"
        }
        val stderrText = stderr.toString().trim()
        finishTask(taskId, finalStatus, exitCode, durationMs, if (stderrText.isBlank()) null else stderrText)

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
                .put("failureKind", taskFailureKind(taskId))
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
        recordLog(taskId, "task $taskId stream: $command")

        val output = socket.getOutputStream()
        writeHeaders(output, 200, "application/x-ndjson", null)
        val started = System.nanoTime()
        val process = ProcessBuilder(args)
            .directory(cwd)
            .redirectErrorStream(false)
            .apply { environment().putAll(env) }
            .start()

        registerTaskProcess(taskId, process)
        val writeLock = Any()
        val stdoutThread = thread(isDaemon = true) {
            process.inputStream.bufferedReader().forEachLine { line ->
                writeNdjson(output, writeLock, JSONObject().put("type", "stdout").put("data", line))
                recordLog(taskId, "stdout: $line")
            }
        }
        val stderrThread = thread(isDaemon = true) {
            process.errorStream.bufferedReader().forEachLine { line ->
                writeNdjson(output, writeLock, JSONObject().put("type", "stderr").put("data", line))
                recordLog(taskId, "stderr: $line")
            }
        }
        val exitCode = process.waitFor()
        stdoutThread.join(500)
        stderrThread.join(500)
        val durationMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started)
        clearTaskProcess(taskId, process)
        val finalStatus = if (isTaskCancelled(taskId)) {
            "cancelled"
        } else if (exitCode == 0) {
            "succeeded"
        } else {
            "failed"
        }
        finishTask(taskId, finalStatus, exitCode, durationMs, null)
        writeNdjson(
            output,
            writeLock,
            JSONObject().put("type", "exit").put("exitCode", exitCode).put("durationMs", durationMs).put("taskId", taskId)
        )
    }

    private fun handleProjectPreflight(socket: Socket, body: String) {
        val payload = if (body.isBlank()) JSONObject() else JSONObject(body)
        val cwd = validateCwd(payload.optString("cwd", ""))
        writeJson(
            socket,
            200,
            JSONObject()
                .put("success", true)
                .put("cwd", cwd.path)
                .put("detectedFiles", inspectProjectFiles(cwd))
        )
    }

    private fun healthJson(): JSONObject {
        return JSONObject()
            .put("name", "MobileCode Helper Service")
            .put("available", true)
            .put("ready", running)
            .put("status", if (lastError.isBlank()) "Android foreground service is running." else lastError)
            .put("protocolVersion", 1)
            .put("authRequired", false)
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
            .put(
                "taskRegistry",
                JSONObject()
                    .put("runningCount", runningTaskCount())
                    .put("maxTasks", MAX_TASKS)
            )
            .put("missingDependencies", JSONArray())
            .put("recoveryActions", JSONArray())
    }

    private fun taskJson(): JSONObject {
        val snapshot = synchronized(taskLock) {
            syncCurrentTaskLocked()
            taskSnapshotJson()
        }
        return JSONObject()
            .put("running", snapshot.optString("status") == "running")
            .put("runningCount", runningTaskCount())
            .put("taskId", snapshot.optString("id", ""))
            .put("command", snapshot.optString("command", ""))
            .put("logs", snapshot.optJSONArray("logs") ?: JSONArray())
            .put("task", snapshot)
    }

    private fun taskHistoryJson(limit: Int): JSONObject {
        val tasks = JSONArray()
        synchronized(taskLock) {
            taskHistory.take(limit.coerceAtLeast(1)).forEach { tasks.put(JSONObject(it.toString())) }
        }
        return JSONObject()
            .put("tasks", tasks)
            .put("count", tasks.length())
    }

    private fun taskLogsJson(taskId: String, limit: Int): JSONObject {
        val logs = JSONArray()
        synchronized(taskLock) {
            val task = taskHistory.firstOrNull { it.optString("id") == taskId || it.optString("taskId") == taskId }
            val source = task?.optJSONArray("logs") ?: JSONArray()
            val start = (source.length() - limit.coerceAtLeast(1)).coerceAtLeast(0)
            for (index in start until source.length()) {
                logs.put(source.optString(index))
            }
        }
        return JSONObject()
            .put("taskId", taskId)
            .put("logs", logs)
    }

    private fun findTaskLocked(taskId: String): JSONObject? {
        return taskHistory.firstOrNull { it.optString("id") == taskId || it.optString("taskId") == taskId }
    }

    private fun taskIdentity(task: JSONObject): String = task.optString("id", task.optString("taskId", ""))

    private fun appendLogToTaskLocked(task: JSONObject, line: String) {
        val logs = task.optJSONArray("logs") ?: JSONArray().also { task.put("logs", it) }
        logs.put(line)
        while (logs.length() > MAX_LOG_LINES) {
            logs.remove(0)
        }
    }

    private fun syncCurrentTaskLocked() {
        val runningTask = taskHistory.firstOrNull { task ->
            val taskId = taskIdentity(task)
            task.optString("status") == "running" && taskProcesses.containsKey(taskId)
        }
        val nextTask = runningTask ?: taskHistory.firstOrNull()
        if (nextTask == null) {
            currentTaskId = ""
            currentCommand = ""
            currentTaskCwd = ""
            currentTaskStatus = "unknown"
            currentTaskStartedAtMs = 0L
            currentTaskFinishedAtMs = 0L
            currentTaskExitCode = null
            currentTaskDurationMs = 0L
            currentTaskError = ""
            currentTaskFailureKind = "none"
            currentProcess = null
            synchronized(recentLogs) { recentLogs.clear() }
            return
        }
        applyTaskJsonLocked(nextTask)
        currentProcess = taskProcesses[currentTaskId]
    }

    private fun isTaskCancelled(taskId: String): Boolean {
        synchronized(taskLock) {
            return findTaskLocked(taskId)?.optString("status") == "cancelled"
        }
    }

    private fun taskFailureKind(taskId: String): String {
        synchronized(taskLock) {
            return findTaskLocked(taskId)?.optString("failureKind", "none") ?: "none"
        }
    }

    private fun runningTaskCount(): Int {
        synchronized(taskLock) {
            return taskHistory.count { task ->
                task.optString("status") == "running" && taskProcesses.containsKey(taskIdentity(task))
            }
        }
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
            currentTaskFailureKind = "none"
            synchronized(recentLogs) {
                recentLogs.clear()
            }
            persistTaskStateLocked()
        }
    }

    private fun registerTaskProcess(taskId: String, process: Process) {
        synchronized(taskLock) {
            taskProcesses[taskId] = process
            if (taskId == currentTaskId) currentProcess = process
            persistTaskStateLocked()
        }
    }

    private fun clearTaskProcess(taskId: String, process: Process) {
        synchronized(taskLock) {
            if (taskProcesses[taskId] == process) {
                taskProcesses.remove(taskId)
            }
            if (currentProcess == process) {
                currentProcess = null
            }
            syncCurrentTaskLocked()
            persistTaskStateLocked()
        }
    }

    private fun finishTask(taskId: String, status: String, exitCode: Int, durationMs: Long, error: String?) {
        synchronized(taskLock) {
            val task = findTaskLocked(taskId) ?: return
            val finalStatus = if (task.optString("status") == "cancelled") "cancelled" else status
            val finalError = if (finalStatus == "cancelled" && error.isNullOrBlank() && task.optString("error").isNotBlank()) {
                task.optString("error")
            } else {
                error ?: ""
            }
            task.put("status", finalStatus)
            task.put("finishedAtMs", System.currentTimeMillis())
            task.put("exitCode", exitCode)
            task.put("durationMs", durationMs)
            if (finalError.isNotBlank()) task.put("error", finalError)
            task.put("failureKind", classifyFailure(finalStatus, exitCode, finalError.ifBlank { null }))
            syncCurrentTaskLocked()
            persistTaskStateLocked()
        }
    }

    private fun recordLog(taskId: String, line: String) {
        synchronized(taskLock) {
            val task = findTaskLocked(taskId) ?: return
            appendLogToTaskLocked(task, line)
            if (taskId == currentTaskId) appendLog(line)
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
            try {
                taskHistory.clear()
                val database = taskDatabaseFile
                if (database.exists()) {
                    val decoded = JSONObject(database.readText()).optJSONArray("tasks") ?: JSONArray()
                    for (index in 0 until decoded.length()) {
                        val task = decoded.optJSONObject(index) ?: continue
                        taskHistory.add(task)
                    }
                }
                if (taskHistory.isEmpty() && taskStateFile.exists()) {
                    taskHistory.add(JSONObject(taskStateFile.readText()))
                }
                val now = System.currentTimeMillis()
                taskHistory.forEach { task ->
                    if (task.optString("status") == "running") {
                        task.put("status", "lost")
                        task.put("finishedAtMs", now)
                        task.put("error", "Helper service restarted before this task completed.")
                        task.put("failureKind", "runtimeLost")
                        appendLogToTaskLocked(task, "task lost after helper restart")
                    }
                }
                syncCurrentTaskLocked()
                persistTaskStateLocked()
            } catch (error: Throwable) {
                lastError = "failed to load task state: ${error.message ?: error.javaClass.simpleName}"
            }
        }
    }

    private fun persistTaskStateLocked() {
        if (currentTaskId.isBlank() && currentCommand.isBlank() && taskHistory.isEmpty()) return
        try {
            upsertTaskHistoryLocked()
            syncCurrentTaskLocked()
            val file = taskStateFile
            file.parentFile?.mkdirs()
            file.writeText(taskSnapshotJson().toString())
            val tasks = JSONArray()
            taskHistory.take(MAX_TASKS).forEach { tasks.put(it) }
            taskDatabaseFile.writeText(JSONObject().put("tasks", tasks).toString())
        } catch (error: Throwable) {
            lastError = "failed to persist task state: ${error.message ?: error.javaClass.simpleName}"
        }
    }

    private fun applyTaskJsonLocked(json: JSONObject) {
        currentTaskId = json.optString("id", "")
        currentCommand = json.optString("command", "")
        currentTaskCwd = json.optString("cwd", "")
        currentTaskStatus = json.optString("status", "unknown")
        currentTaskStartedAtMs = json.optLong("startedAtMs", 0L)
        currentTaskFinishedAtMs = json.optLong("finishedAtMs", 0L)
        currentTaskExitCode = if (json.has("exitCode") && !json.isNull("exitCode")) json.optInt("exitCode") else null
        currentTaskDurationMs = json.optLong("durationMs", 0L)
        currentTaskError = json.optString("error", "")
        currentTaskFailureKind = json.optString("failureKind", classifyFailure(currentTaskStatus, currentTaskExitCode, currentTaskError))
        synchronized(recentLogs) {
            recentLogs.clear()
            val logs = json.optJSONArray("logs") ?: JSONArray()
            for (index in 0 until logs.length()) {
                recentLogs.add(logs.optString(index))
            }
        }
    }

    private fun upsertTaskHistoryLocked() {
        val snapshot = taskSnapshotJson()
        val existing = taskHistory.indexOfFirst { it.optString("id") == currentTaskId || it.optString("taskId") == currentTaskId }
        if (existing >= 0) {
            taskHistory[existing] = snapshot
        } else {
            taskHistory.add(0, snapshot)
        }
        while (taskHistory.size > MAX_TASKS) {
            taskHistory.removeAt(taskHistory.size - 1)
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
            .put("failureKind", currentTaskFailureKind)
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

    private fun inspectProjectFiles(cwd: File): JSONArray {
        val files = JSONArray()
        cwd.walkTopDown()
            .maxDepth(2)
            .filter { projectMarkers.contains(it.name) }
            .map { file ->
                val relative = cwd.toPath().relativize(file.toPath()).toString().replace(File.separatorChar, '/')
                "./$relative"
            }
            .distinct()
            .sorted()
            .forEach { files.put(it) }
        return files
    }

    private fun hasBinary(name: String): Boolean {
        val path = System.getenv("PATH") ?: return false
        return path.split(File.pathSeparator).any { directory ->
            val candidate = File(directory, name)
            candidate.exists() && candidate.canExecute()
        }
    }

    private fun stopCurrentProcess(): Boolean = stopTask(null).optBoolean("stopped", false)

    private fun stopTask(taskId: String?): JSONObject {
        val requestedTaskId = taskId?.trim().orEmpty()
        var stoppingTaskId = ""
        val process = synchronized(taskLock) {
            val task = if (requestedTaskId.isNotEmpty()) {
                findTaskLocked(requestedTaskId) ?: return JSONObject()
                    .put("success", false)
                    .put("stopped", false)
                    .put("taskId", requestedTaskId)
                    .put("failureKind", "unknown")
                    .put("error", "Task not found: $requestedTaskId")
            } else {
                taskHistory.firstOrNull { candidate ->
                    candidate.optString("status") == "running" && taskProcesses.containsKey(taskIdentity(candidate))
                } ?: return JSONObject().put("success", true).put("stopped", false)
            }
            stoppingTaskId = taskIdentity(task)
            val process = taskProcesses.remove(stoppingTaskId)
            if (process == null) {
                return JSONObject()
                    .put("success", true)
                    .put("stopped", false)
                    .put("taskId", stoppingTaskId)
                    .put("task", JSONObject(task.toString()))
            }
            appendLogToTaskLocked(task, "task stopped")
            val finishedAtMs = System.currentTimeMillis()
            val startedAtMs = task.optLong("startedAtMs", finishedAtMs)
            task.put("status", "cancelled")
            task.put("finishedAtMs", finishedAtMs)
            task.put("durationMs", (finishedAtMs - startedAtMs).coerceAtLeast(0L))
            task.put("error", "Task cancelled by MobileCode.")
            task.put("failureKind", "cancelled")
            if (currentProcess == process) currentProcess = null
            syncCurrentTaskLocked()
            persistTaskStateLocked()
            process
        }

        return try {
            process.destroy()
            if (!process.waitFor(2, TimeUnit.SECONDS)) {
                process.destroyForcibly()
            }
            synchronized(taskLock) {
                val task = findTaskLocked(stoppingTaskId)
                JSONObject()
                    .put("success", true)
                    .put("stopped", true)
                    .put("taskId", stoppingTaskId)
                    .put("task", if (task == null) JSONObject() else JSONObject(task.toString()))
            }
        } catch (error: Throwable) {
            JSONObject()
                .put("success", false)
                .put("stopped", false)
                .put("taskId", requestedTaskId.ifEmpty { stoppingTaskId })
                .put("failureKind", "unknown")
                .put("error", error.message ?: error.javaClass.simpleName)
        }
    }

    private fun decodePathSegment(value: String): String = URLDecoder.decode(value, StandardCharsets.UTF_8.name())

    private fun queryLimit(query: String, fallback: Int): Int {
        return query.split("&")
            .firstOrNull { it.substringBefore("=") == "limit" }
            ?.substringAfter("=", "")
            ?.toIntOrNull()
            ?.coerceIn(1, MAX_TASKS)
            ?: fallback
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
        private const val MAX_TASKS = 50

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
        @Volatile private var currentTaskFailureKind = "none"
        private val taskLock = Any()
        private val recentLogs = Collections.synchronizedList(mutableListOf<String>())
        private val taskHistory = Collections.synchronizedList(mutableListOf<JSONObject>())
        private val taskProcesses = Collections.synchronizedMap(mutableMapOf<String, Process>())

        fun status(): Map<String, Any> {
            return mapOf(
                "running" to running,
                "port" to PORT,
                "lastError" to lastError,
                "taskId" to currentTaskId,
                "command" to currentCommand,
                "taskRunning" to (taskProcesses.isNotEmpty()),
                "taskRunningCount" to taskProcesses.size,
                "taskStatus" to currentTaskStatus,
                "taskStartedAtMs" to currentTaskStartedAtMs,
                "taskFinishedAtMs" to currentTaskFinishedAtMs,
                "taskFailureKind" to currentTaskFailureKind,
                "taskHistoryCount" to taskHistory.size
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

        private val projectMarkers = setOf(
            "package.json",
            "pubspec.yaml",
            "requirements.txt",
            "pyproject.toml",
            ".git"
        )

        private fun classifyFailure(status: String, exitCode: Int?, error: String?): String {
            val message = (error ?: "").lowercase(Locale.US)
            return when {
                status == "succeeded" -> "none"
                status == "cancelled" -> "cancelled"
                status == "timedOut" -> "timeout"
                status == "lost" -> "runtimeLost"
                message.contains("outside mobilecode app data") -> "cwdOutsideWorkspace"
                message.contains("not allowed") || message.contains("dangerous command") -> "commandBlocked"
                listOf("command not found", "no such file or directory", "not found", "cannot find", "is not recognized").any { message.contains(it) } -> "dependencyMissing"
                exitCode != null && exitCode != 0 -> "processFailed"
                else -> "unknown"
            }
        }
    }
}
