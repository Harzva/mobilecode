package com.mobilecode.app

import android.content.Context
import android.os.Build
import java.io.BufferedInputStream
import java.io.BufferedReader
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.net.InetAddress
import java.net.HttpURLConnection
import java.net.Socket
import java.net.URL
import java.nio.file.Files
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.zip.GZIPInputStream

class LinuxSandboxRunner(private val context: Context) {
    private val sandboxDir: File
        get() = File(context.filesDir, "linux-sandbox").apply { mkdirs() }

    private val rootfsDir: File
        get() = File(sandboxDir, "rootfs")

    private val tmpDir: File
        get() = File(sandboxDir, "tmp").apply { mkdirs() }

    private val homeDir: File
        get() {
            val external = context.getExternalFilesDir(null)
            return File(external ?: sandboxDir, "sandbox-home").apply { mkdirs() }
        }

    private val prootPath: String
        get() = File(context.applicationInfo.nativeLibraryDir, "libproot.so").absolutePath

    private val loaderPath: String
        get() = File(context.applicationInfo.nativeLibraryDir, "libproot-loader.so").absolutePath

    private val tallocSource: File
        get() = File(context.applicationInfo.nativeLibraryDir, "libtalloc.so")

    private val tallocTarget: File
        get() = File(sandboxDir, "libtalloc.so.2")

    private var agentlyAuthProcess: Process? = null

    fun status(): Map<String, Any?> {
        val proot = File(prootPath)
        val rootfsReady = hasRootfsBootFiles()
        return mapOf(
            "installed" to rootfsReady,
            "ready" to (rootfsReady && proot.exists() && proot.canExecute()),
            "status" to if (rootfsReady) "ready" else "notInstalled",
            "arch" to linuxArch(),
            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
            "rootfsPath" to rootfsDir.absolutePath,
            "homePath" to homeDir.absolutePath,
            "tmpPath" to tmpDir.absolutePath,
            "nativeLibDir" to context.applicationInfo.nativeLibraryDir,
            "prootPath" to prootPath,
            "prootExists" to proot.exists(),
            "prootExecutable" to proot.canExecute(),
            "packages" to mapOf(
                "base" to true,
                "devBasic" to File(rootfsDir, "usr/bin/git").isFile,
                "pythonPack" to File(rootfsDir, "usr/bin/python3").isFile,
                "nodePack" to (File(rootfsDir, "usr/bin/node").isFile && File(rootfsDir, "usr/bin/npm").isFile),
                "larkCli" to (
                    File(rootfsDir, "usr/bin/node").isFile &&
                    File(rootfsDir, "usr/bin/npm").isFile &&
                    File(rootfsDir, "usr/bin/curl").isFile &&
                    hasLarkCliBinary()
                ),
                "agentMailCli" to (
                    File(rootfsDir, "usr/bin/node").isFile &&
                    File(rootfsDir, "usr/bin/npm").isFile &&
                    File(rootfsDir, "usr/bin/curl").isFile &&
                    hasAgentlyCliBinary()
                ),
                "googleWorkspaceCli" to (
                    File(rootfsDir, "usr/bin/node").isFile &&
                    File(rootfsDir, "usr/bin/npm").isFile &&
                    File(rootfsDir, "usr/bin/curl").isFile &&
                    hasGwsBinary()
                ),
                "hyperframesCli" to hasHyperFramesRuntime(),
                "githubCli" to (
                    File(rootfsDir, "usr/bin/gh").isFile ||
                    File(rootfsDir, "usr/local/bin/gh").isFile ||
                    File(homeDir, ".local/bin/gh").isFile
                ),
            ),
        )
    }

    fun setup(manifest: Map<String, Any?>): Map<String, Any?> {
        val startedAt = System.currentTimeMillis()
        return try {
            val proot = File(prootPath)
            if (!proot.exists()) {
                return failure(
                    "setup",
                    "dependencyMissing",
                    "PRoot binary not found in nativeLibraryDir",
                    startedAt,
                    metadata = status(),
                )
            }
            sandboxDir.mkdirs()
            tmpDir.mkdirs()
            copyLibtalloc()

            if (!hasRootfsBootFiles()) {
                val url = manifest["url"]?.toString().orEmpty()
                val sha256 = manifest["sha256"]?.toString().orEmpty()
                if (url.isBlank() || sha256.length != 64) {
                    return failure(
                        "setup",
                        "invalidManifest",
                        "Rootfs manifest url or sha256 is invalid",
                        startedAt,
                    )
                }
                val archive = File(sandboxDir, "rootfs.tar.gz")
                try {
                    val usedBundledRootfs = copyBundledRootfsArchive(manifest, archive)
                    if (!usedBundledRootfs) {
                        download(url, archive)
                    }
                    val digest = sha256(archive)
                    if (!digest.equals(sha256, ignoreCase = true)) {
                        archive.delete()
                        rootfsDir.deleteRecursively()
                        return failure(
                            "setup",
                            "checksum_mismatch",
                            "Expected $sha256 but got $digest",
                            startedAt,
                        )
                    }
                    rootfsDir.deleteRecursively()
                    extractTarGz(archive, rootfsDir)
                } finally {
                    archive.delete()
                }
            }

            makeWritable(rootfsDir)
            writeResolvConf(rootfsDir)
            val repositoryBaseUrl = manifest["repositoryBaseUrl"]?.toString().orEmpty()
            writeRepositoryHosts(rootfsDir, repositoryBaseUrl)
            writeRepositories(rootfsDir, manifest["version"]?.toString().orEmpty(), repositoryBaseUrl)
            val health = execute("apk --version", timeoutSeconds = 30)
            if (health["success"] != true) {
                return failure(
                    "setup",
                    "processFailed",
                    "apk health check failed: ${health["stderr"] ?: health["stdout"] ?: health["error"]}",
                    startedAt,
                    metadata = health,
                )
            }
            success("setup", "", "", 0, startedAt, metadata = status())
        } catch (error: Throwable) {
            failure("setup", "processFailed", error.message ?: error.javaClass.simpleName, startedAt)
        }
    }

    private fun copyBundledRootfsArchive(manifest: Map<String, Any?>, archive: File): Boolean {
        val id = manifest["id"]?.toString().orEmpty()
        if (id.isBlank()) return false
        val assetPaths = listOf("linux_sandbox/$id.tgz", "linux_sandbox/$id.tar.gz")
        for (assetPath in assetPaths) {
            try {
                context.assets.open(assetPath).use { input ->
                    FileOutputStream(archive).use { output ->
                        input.copyTo(output)
                    }
                }
                return true
            } catch (_: Throwable) {
                archive.delete()
            }
        }
        return false
    }

    fun reset(): Map<String, Any?> {
        val startedAt = System.currentTimeMillis()
        return try {
            sandboxDir.deleteRecursively()
            success("reset", "", "", 0, startedAt, metadata = status())
        } catch (error: Throwable) {
            failure("reset", "processFailed", error.message ?: error.javaClass.simpleName, startedAt)
        }
    }

    fun runTypedTask(taskKind: String, payload: Map<String, Any?>): Map<String, Any?> {
        val startedAt = System.currentTimeMillis()
        if (taskKind != "package_install" && !isReady()) {
            return failure(taskKind, "dependencyMissing", "Linux Sandbox rootfs or PRoot is not ready", startedAt)
        }
        return when (taskKind) {
            "apk_version" -> execute("apk --version", taskKind = taskKind)
            "git_version" -> execute("git --version", taskKind = taskKind)
            "node_version" -> execute("node --version && npm --version", taskKind = taskKind)
            "npm_version" -> execute("npm --version", taskKind = taskKind)
            "lark_cli_probe" -> runLarkCliProbe(startedAt)
            "lark_cli_auth_start" -> runLarkCliAuthStart(payload, startedAt)
            "lark_cli_auth_status" -> runLarkCliAuthStatus(startedAt)
            "lark_cli_execute" -> runLarkCliExecute(payload, startedAt)
            "agently_cli_probe" -> runAgentlyCliProbe(startedAt)
            "agently_cli_auth_start" -> runAgentlyCliAuthStart(payload, startedAt)
            "agently_cli_me" -> runAgentlyCliMe(startedAt)
            "agently_cli_execute" -> runAgentlyCliExecute(payload, startedAt)
            "gws_cli_probe" -> runGwsCliProbe(startedAt)
            "gws_cli_auth_setup" -> runGwsCliAuthSetup(payload, startedAt)
            "gws_cli_auth_login" -> runGwsCliAuthLogin(payload, startedAt)
            "gws_cli_auth_status" -> runGwsCliAuthStatus(startedAt)
            "gws_cli_execute" -> runGwsCliExecute(payload, startedAt)
            "github_cli_probe" -> runGitHubCliProbe(startedAt)
            "github_cli_auth_login" -> runGitHubCliAuthLogin(payload, startedAt)
            "github_cli_auth_status" -> runGitHubCliAuthStatus(startedAt)
            "github_cli_execute" -> runGitHubCliExecute(payload, startedAt)
            "hyperframes_cli_probe" -> runHyperFramesCliProbe(startedAt)
            "hyperframes_lint" -> runHyperFramesTask("hyperframes_lint", payload, startedAt)
            "hyperframes_check" -> runHyperFramesTask("hyperframes_check", payload, startedAt)
            "hyperframes_compositions" -> runHyperFramesTask("hyperframes_compositions", payload, startedAt)
            "hyperframes_render" -> runHyperFramesTask("hyperframes_render", payload, startedAt)
            "project_check" -> execute("pwd && ls -la /root | head -n 40", taskKind = taskKind)
            "package_install" -> installPackageProfile(payload, startedAt)
            "npm_build" -> runNpmBuild(payload, startedAt)
            else -> failure(taskKind, "commandBlocked", "Unsupported Linux Sandbox typed task", startedAt)
        }
    }

    private fun installPackageProfile(payload: Map<String, Any?>, startedAt: Long): Map<String, Any?> {
        if (payload["approved"] != true) {
            return failure("package_install", "approvalRequired", "Package install requires explicit approval", startedAt)
        }
        if (!isReady()) {
            return failure("package_install", "dependencyMissing", "Linux Sandbox rootfs or PRoot is not ready", startedAt)
        }
        prepareRootfsForPackageMutation()
        val profileId = payload["profileId"]?.toString() ?: payload["profile_id"]?.toString().orEmpty()
        val packages = when (profileId) {
            "base" -> listOf<String>()
            "devBasic" -> listOf("git", "curl", "ca-certificates")
            "pythonPack" -> listOf("python3", "py3-pip")
            "nodePack" -> listOf("nodejs", "npm")
            "larkCli" -> listOf("nodejs", "npm", "curl", "ca-certificates")
            "agentMailCli" -> listOf("nodejs", "npm", "curl", "ca-certificates")
            "googleWorkspaceCli" -> listOf("nodejs", "npm", "curl", "ca-certificates")
            "githubCli" -> listOf("github-cli", "git", "curl", "ca-certificates")
            "hyperframesCli" -> listOf("nodejs", "npm", "chromium", "ffmpeg", "ca-certificates", "hyperframes")
            else -> return failure(
                "package_install",
                "commandBlocked",
                "Unknown package profile: $profileId",
                startedAt,
                metadata = mapOf("profileId" to profileId),
            )
        }
        if (packages.isEmpty()) {
            return success(
                "package_install",
                "Base package profile is already provided by Alpine rootfs.",
                "",
                0,
                startedAt,
                metadata = mapOf("profileId" to profileId),
            )
        }
        val verifyCommand = packageProfileVerifyCommand(profileId)
        val preVerify = execute(verifyCommand, timeoutSeconds = 30, taskKind = "package_install_verify")
        if (preVerify["success"] == true) {
            return success(
                "package_install",
                "Package profile is already installed.\n${preVerify["stdout"]?.toString().orEmpty()}".trim(),
                preVerify["stderr"]?.toString().orEmpty(),
                0,
                startedAt,
                metadata = mapOf(
                    "profileId" to profileId,
                    "packages" to packages,
                    "verifyCommand" to verifyCommand,
                    "alreadyInstalled" to true,
                    "postconditionVerified" to true,
                ),
            )
        }
        val command = packageProfileInstallCommand(profileId, packages)
        val installTimeout = if (
            profileId == "larkCli" ||
            profileId == "agentMailCli" ||
            profileId == "googleWorkspaceCli"
        ) 300L else if (profileId == "hyperframesCli") 3600L else 180L
        val install = execute(command, timeoutSeconds = installTimeout, taskKind = "package_install")
        val verify = execute(verifyCommand, timeoutSeconds = 60, taskKind = "package_install_verify")
        val metadata = mapOf(
            "profileId" to profileId,
            "packages" to packages,
            "command" to command,
            "verifyCommand" to verifyCommand,
            "installExitCode" to install["exitCode"],
            "installFailureKind" to install["failureKind"],
            "postconditionVerified" to (verify["success"] == true),
        )
        if (install["success"] == true) {
            return install.toMutableMap().also { it["metadata"] = metadata }
        }
        if (verify["success"] == true) {
            return success(
                "package_install",
                "${install["stdout"]?.toString().orEmpty()}\n\nPostcondition verified:\n${verify["stdout"]?.toString().orEmpty()}".trim(),
                install["stderr"]?.toString().orEmpty(),
                0,
                startedAt,
                metadata = metadata,
            )
        }
        return install.toMutableMap().also {
            it["metadata"] = metadata + mapOf(
                "verifyExitCode" to verify["exitCode"],
                "verifyStdout" to verify["stdout"],
                "verifyStderr" to verify["stderr"],
            )
        }
    }

    private fun packageProfileVerifyCommand(profileId: String): String = when (profileId) {
        "devBasic" -> "git --version && curl --version | head -n 1"
        "pythonPack" -> "python3 --version && pip3 --version"
        "nodePack" -> "node --version && npm --version"
        "larkCli" -> "node --version && npm --version && lark-cli --version"
        "agentMailCli" -> "node --version && npm --version && agently-cli --version"
        "googleWorkspaceCli" -> "node --version && npm --version && gws --version"
        "githubCli" -> "gh --version"
        "hyperframesCli" -> "node --version && npm --version && hyperframes --version && ffmpeg -version | head -n 1 && (chromium-browser --version || chromium --version)"
        else -> "true"
    }

    private fun packageProfileInstallCommand(profileId: String, packages: List<String>): String {
        val apkPackages = packages.filterNot { it.startsWith("@") || it == "hyperframes" }
        val apkInstall = "apk add --no-cache ${apkPackages.joinToString(" ")}"
        return when (profileId) {
            "larkCli" -> "$apkInstall || true; node --version && npm --version && npm install -g --no-audit --no-fund @larksuite/cli && lark-cli --version"
            "agentMailCli" -> "$apkInstall || true; node --version && npm --version && npm install -g --no-audit --no-fund @tencent-qqmail/agently-cli && agently-cli --version"
            "googleWorkspaceCli" -> "$apkInstall || true; node --version && npm --version && npm install -g --no-audit --no-fund @googleworkspace/cli && gws --version"
            "githubCli" -> "$apkInstall && gh --version"
            "hyperframesCli" -> """
                apk add --no-cache nodejs npm ca-certificates || (test -x /usr/bin/node && test -x /usr/bin/npm)
                apk add --no-cache ffmpeg || test -x /usr/bin/ffmpeg
                apk add --no-cache chromium || (test -x /usr/bin/chromium || test -x /usr/bin/chromium-browser)
                node --version && npm --version && npm install -g --no-audit --no-fund hyperframes && hyperframes --version
            """.trimIndent().replace("\n", "; ")
            else -> apkInstall
        }
    }

    private fun runLarkCliProbe(startedAt: Long): Map<String, Any?> {
        if (!hasLarkCliRuntime()) {
            return failure(
                "lark_cli_probe",
                "dependencyMissing",
                "Install the Lark CLI extension profile before probing Lark CLI.",
                startedAt,
            )
        }
        return execute(
            "node --version && npm --version && lark-cli --version",
            timeoutSeconds = 90,
            taskKind = "lark_cli_probe",
        )
    }

    private fun runLarkCliAuthStart(payload: Map<String, Any?>, startedAt: Long): Map<String, Any?> {
        if (payload["approved"] != true) {
            return failure(
                "lark_cli_auth_start",
                "approvalRequired",
                "Starting Lark CLI login requires explicit user approval",
                startedAt,
            )
        }
        if (!hasLarkCliRuntime()) {
            return failure(
                "lark_cli_auth_start",
                "dependencyMissing",
                "Install the Lark CLI extension profile before starting auth.",
                startedAt,
            )
        }
        val result = execute(
            "lark-cli auth login --recommend --no-wait",
            timeoutSeconds = 90,
            taskKind = "lark_cli_auth_start",
        ).toMutableMap()
        result["metadata"] = mapOf(
            "authFlow" to "official_browser",
            "storesCredential" to false,
            "recoveryHint" to "Open the official Lark URL from stdout, finish login, then run auth status.",
        )
        return result
    }

    private fun runLarkCliAuthStatus(startedAt: Long): Map<String, Any?> {
        if (!hasLarkCliRuntime()) {
            return failure(
                "lark_cli_auth_status",
                "dependencyMissing",
                "Install the Lark CLI extension profile before checking auth status.",
                startedAt,
            )
        }
        return execute(
            "lark-cli auth status",
            timeoutSeconds = 60,
            taskKind = "lark_cli_auth_status",
        )
    }

    private fun runLarkCliExecute(payload: Map<String, Any?>, startedAt: Long): Map<String, Any?> {
        if (payload["approved"] != true) {
            return failure(
                "lark_cli_execute",
                "approvalRequired",
                "Running a Lark CLI command requires explicit user approval",
                startedAt,
            )
        }
        if (!hasLarkCliRuntime()) {
            return failure(
                "lark_cli_execute",
                "dependencyMissing",
                "Install the Lark CLI extension profile before executing a Lark command.",
                startedAt,
            )
        }
        val commandId = payload["commandId"]?.toString().orEmpty()
        val command = when (commandId) {
            "auth_status" -> "lark-cli auth status"
            "wiki_space_list" -> "lark-cli wiki +space-list --page-size 10 --format json"
            else -> return failure(
                "lark_cli_execute",
                "commandBlocked",
                "Unsupported Lark CLI command id: $commandId",
                startedAt,
                metadata = mapOf("commandId" to commandId),
            )
        }
        val result = execute(
            command,
            timeoutSeconds = 90,
            taskKind = "lark_cli_execute",
        ).toMutableMap()
        result["metadata"] = mapOf(
            "commandId" to commandId,
            "commandPolicy" to "builtin_readonly_allowlist",
        )
        return result
    }

    private fun runAgentlyCliProbe(startedAt: Long): Map<String, Any?> {
        if (!hasAgentlyCliRuntime()) {
            return failure(
                "agently_cli_probe",
                "dependencyMissing",
                "Install the Agent Mail CLI extension profile before probing Agent Mail CLI.",
                startedAt,
            )
        }
        return execute(
            "node --version && npm --version && agently-cli --version",
            timeoutSeconds = 90,
            taskKind = "agently_cli_probe",
        )
    }

    private fun runAgentlyCliAuthStart(payload: Map<String, Any?>, startedAt: Long): Map<String, Any?> {
        if (payload["approved"] != true) {
            return failure(
                "agently_cli_auth_start",
                "approvalRequired",
                "Starting Agent Mail CLI login requires explicit user approval",
                startedAt,
            )
        }
        if (!hasAgentlyCliRuntime()) {
            return failure(
                "agently_cli_auth_start",
                "dependencyMissing",
                "Install the Agent Mail CLI extension profile before starting auth.",
                startedAt,
            )
        }
        agentlyAuthProcess?.let { process ->
            if (process.isAlive) {
                return success(
                    "agently_cli_auth_start",
                    "Agent Mail CLI login is already waiting for browser authorization.",
                    "",
                    0,
                    startedAt,
                    metadata = mapOf(
                        "authFlow" to "official_browser",
                        "authUrlCaptured" to false,
                        "processState" to "running",
                    ),
                )
            }
        }
        return try {
            val processBuilder = ProcessBuilder(buildProcessArgs("agently-cli auth login", "/root"))
                .directory(rootfsDir.parentFile)
                .redirectErrorStream(true)
            processBuilder.environment().putAll(baseEnv())
            val process = processBuilder.start()
            agentlyAuthProcess = process
            val outputFuture = CompletableFuture.supplyAsync {
                readUntilFirstHttpsUrl(process.inputStream.bufferedReader())
            }
            val output = try {
                outputFuture.get(20, TimeUnit.SECONDS)
            } catch (timeout: TimeoutException) {
                process.destroyForcibly()
                return failure(
                    "agently_cli_auth_start",
                    "timeout",
                    "Agent Mail CLI did not print an authorization URL before timeout",
                    startedAt,
                    stdout = readFutureOrEmpty(outputFuture),
                    exitCode = -1,
                )
            }
            val url = firstHttpsUrl(output)
            if (url == null) {
                val exited = process.waitFor(1, TimeUnit.SECONDS)
                if (exited) agentlyAuthProcess = null
                return failure(
                    "agently_cli_auth_start",
                    "processFailed",
                    output.ifBlank { "Agent Mail CLI did not print an authorization URL." },
                    startedAt,
                    stdout = output,
                    exitCode = if (exited) process.exitValue() else 127,
                )
            }
            success(
                "agently_cli_auth_start",
                output,
                "",
                0,
                startedAt,
                metadata = mapOf(
                    "authFlow" to "official_browser",
                    "authUrlCaptured" to true,
                    "processState" to "running",
                    "storesCredential" to true,
                    "recoveryHint" to "Open the official Agent Mail URL from stdout, finish login, then run status.",
                ),
            )
        } catch (error: Throwable) {
            agentlyAuthProcess = null
            failure(
                "agently_cli_auth_start",
                "processFailed",
                error.message ?: error.javaClass.simpleName,
                startedAt,
            )
        }
    }

    private fun runAgentlyCliMe(startedAt: Long): Map<String, Any?> {
        if (!hasAgentlyCliRuntime()) {
            return failure(
                "agently_cli_me",
                "dependencyMissing",
                "Install the Agent Mail CLI extension profile before checking auth status.",
                startedAt,
            )
        }
        return execute("agently-cli +me", timeoutSeconds = 60, taskKind = "agently_cli_me")
    }

    private fun runAgentlyCliExecute(payload: Map<String, Any?>, startedAt: Long): Map<String, Any?> {
        if (payload["approved"] != true) {
            return failure(
                "agently_cli_execute",
                "approvalRequired",
                "Running an Agent Mail CLI command requires explicit user approval",
                startedAt,
            )
        }
        if (!hasAgentlyCliRuntime()) {
            return failure(
                "agently_cli_execute",
                "dependencyMissing",
                "Install the Agent Mail CLI extension profile before executing Agent Mail CLI.",
                startedAt,
            )
        }
        val commandId = payload["commandId"]?.toString().orEmpty()
        val limit = payload["limit"]?.toString()?.toIntOrNull()?.coerceIn(1, 20) ?: 10
        val command = when (commandId) {
            "message_list" -> "agently-cli message +list --limit $limit"
            else -> return failure(
                "agently_cli_execute",
                "commandBlocked",
                "Unsupported Agent Mail CLI command id: $commandId",
                startedAt,
                metadata = mapOf("commandId" to commandId),
            )
        }
        val result = execute(command, timeoutSeconds = 90, taskKind = "agently_cli_execute").toMutableMap()
        result["metadata"] = mapOf(
            "commandId" to commandId,
            "commandPolicy" to "builtin_readonly_allowlist",
            "limit" to limit,
        )
        return result
    }

    private fun runGwsCliProbe(startedAt: Long): Map<String, Any?> {
        if (!hasGwsRuntime()) {
            return failure(
                "gws_cli_probe",
                "dependencyMissing",
                "Install the Google Workspace CLI extension profile before probing gws.",
                startedAt,
            )
        }
        return execute(
            "node --version && npm --version && gws --version",
            timeoutSeconds = 90,
            taskKind = "gws_cli_probe",
        )
    }

    private fun runGwsCliAuthSetup(payload: Map<String, Any?>, startedAt: Long): Map<String, Any?> {
        if (payload["approved"] != true) {
            return failure(
                "gws_cli_auth_setup",
                "approvalRequired",
                "Starting Google Workspace CLI setup requires explicit user approval",
                startedAt,
            )
        }
        if (!hasGwsRuntime()) {
            return failure(
                "gws_cli_auth_setup",
                "dependencyMissing",
                "Install the Google Workspace CLI extension profile before auth setup.",
                startedAt,
            )
        }
        return execute(
            "gws auth setup",
            timeoutSeconds = 120,
            taskKind = "gws_cli_auth_setup",
        ).toMutableMap().also {
            it["metadata"] = mapOf(
                "authFlow" to "official_google_workspace_setup",
                "requiresGcloud" to true,
                "recoveryHint" to "If gcloud is unavailable, configure OAuth credentials manually and then run gws auth login.",
            )
        }
    }

    private fun runGwsCliAuthLogin(payload: Map<String, Any?>, startedAt: Long): Map<String, Any?> {
        if (payload["approved"] != true) {
            return failure(
                "gws_cli_auth_login",
                "approvalRequired",
                "Starting Google Workspace CLI login requires explicit user approval",
                startedAt,
            )
        }
        if (!hasGwsRuntime()) {
            return failure(
                "gws_cli_auth_login",
                "dependencyMissing",
                "Install the Google Workspace CLI extension profile before auth login.",
                startedAt,
            )
        }
        return execute(
            "gws auth login",
            timeoutSeconds = 120,
            taskKind = "gws_cli_auth_login",
        ).toMutableMap().also {
            it["metadata"] = mapOf(
                "authFlow" to "official_browser",
                "storesCredential" to true,
                "recoveryHint" to "Open the official Google OAuth URL from stdout, finish login, then run auth status.",
            )
        }
    }

    private fun runGwsCliAuthStatus(startedAt: Long): Map<String, Any?> {
        if (!hasGwsRuntime()) {
            return failure(
                "gws_cli_auth_status",
                "dependencyMissing",
                "Install the Google Workspace CLI extension profile before checking auth status.",
                startedAt,
            )
        }
        return execute("gws auth status", timeoutSeconds = 60, taskKind = "gws_cli_auth_status")
    }

    private fun runGwsCliExecute(payload: Map<String, Any?>, startedAt: Long): Map<String, Any?> {
        if (payload["approved"] != true) {
            return failure(
                "gws_cli_execute",
                "approvalRequired",
                "Running a Google Workspace CLI command requires explicit user approval",
                startedAt,
            )
        }
        if (!hasGwsRuntime()) {
            return failure(
                "gws_cli_execute",
                "dependencyMissing",
                "Install the Google Workspace CLI extension profile before executing gws.",
                startedAt,
            )
        }
        val commandId = payload["commandId"]?.toString().orEmpty()
        val pageSize = payload["pageSize"]?.toString()?.toIntOrNull()?.coerceIn(1, 20) ?: 5
        val command = when (commandId) {
            "drive_files_list" -> "gws drive files list --params '{\"pageSize\": $pageSize}'"
            else -> return failure(
                "gws_cli_execute",
                "commandBlocked",
                "Unsupported Google Workspace CLI command id: $commandId",
                startedAt,
                metadata = mapOf("commandId" to commandId),
            )
        }
        val result = execute(command, timeoutSeconds = 90, taskKind = "gws_cli_execute").toMutableMap()
        result["metadata"] = mapOf(
            "commandId" to commandId,
            "commandPolicy" to "builtin_readonly_allowlist",
            "pageSize" to pageSize,
        )
        return result
    }

    private fun runGitHubCliProbe(startedAt: Long): Map<String, Any?> {
        if (!hasGitHubCliRuntime()) {
            return failure(
                "github_cli_probe",
                "dependencyMissing",
                "Install the GitHub CLI extension profile before probing gh.",
                startedAt,
            )
        }
        return execute("gh --version", timeoutSeconds = 60, taskKind = "github_cli_probe")
    }

    private fun runGitHubCliAuthLogin(payload: Map<String, Any?>, startedAt: Long): Map<String, Any?> {
        if (payload["approved"] != true) {
            return failure(
                "github_cli_auth_login",
                "approvalRequired",
                "Starting GitHub CLI login requires explicit user approval",
                startedAt,
            )
        }
        if (!hasGitHubCliRuntime()) {
            return failure(
                "github_cli_auth_login",
                "dependencyMissing",
                "Install the GitHub CLI extension profile before auth login.",
                startedAt,
            )
        }
        return execute(
            "gh auth login --web --git-protocol https",
            timeoutSeconds = 120,
            taskKind = "github_cli_auth_login",
        ).toMutableMap().also {
            it["metadata"] = mapOf(
                "authFlow" to "official_browser",
                "storesCredential" to true,
                "blockedFlags" to listOf("--with-token", "--show-token", "--insecure-storage"),
                "recoveryHint" to "Open the official GitHub OAuth URL from stdout, finish login, then run auth status.",
            )
        }
    }

    private fun runGitHubCliAuthStatus(startedAt: Long): Map<String, Any?> {
        if (!hasGitHubCliRuntime()) {
            return failure(
                "github_cli_auth_status",
                "dependencyMissing",
                "Install the GitHub CLI extension profile before checking auth status.",
                startedAt,
            )
        }
        return execute(
            "gh auth status",
            timeoutSeconds = 60,
            taskKind = "github_cli_auth_status",
        )
    }

    private fun runGitHubCliExecute(payload: Map<String, Any?>, startedAt: Long): Map<String, Any?> {
        if (payload["approved"] != true) {
            return failure(
                "github_cli_execute",
                "approvalRequired",
                "Running a GitHub CLI command requires explicit user approval",
                startedAt,
            )
        }
        if (!hasGitHubCliRuntime()) {
            return failure(
                "github_cli_execute",
                "dependencyMissing",
                "Install the GitHub CLI extension profile before executing gh.",
                startedAt,
            )
        }
        val commandId = payload["commandId"]?.toString().orEmpty()
        val limit = payload["limit"]?.toString()?.toIntOrNull()?.coerceIn(1, 20) ?: 10
        val command = when (commandId) {
            "repo_list" -> "gh repo list --limit $limit --json nameWithOwner,description,url,isPrivate"
            else -> return failure(
                "github_cli_execute",
                "commandBlocked",
                "Unsupported GitHub CLI command id: $commandId",
                startedAt,
                metadata = mapOf("commandId" to commandId),
            )
        }
        val result = execute(command, timeoutSeconds = 90, taskKind = "github_cli_execute").toMutableMap()
        result["metadata"] = mapOf(
            "commandId" to commandId,
            "commandPolicy" to "builtin_readonly_allowlist",
            "limit" to limit,
        )
        return result
    }

    private fun runNpmBuild(payload: Map<String, Any?>, startedAt: Long): Map<String, Any?> {
        val workingDir = linuxWorkingDir(payload["cwd"]?.toString() ?: payload["workingDir"]?.toString())
            ?: return failure(
                "npm_build",
                "commandBlocked",
                "npm_build cwd must stay under /root",
                startedAt,
            )
        return execute(
            "npm run build",
            timeoutSeconds = 180,
            taskKind = "npm_build",
            workingDir = workingDir,
        )
    }

    private fun runHyperFramesCliProbe(startedAt: Long): Map<String, Any?> {
        if (!hasHyperFramesRuntime()) {
            return failure(
                "hyperframes_cli_probe",
                "dependencyMissing",
                "Install the HyperFrames CLI profile before probing HyperFrames.",
                startedAt,
            )
        }
        return execute(
            "node --version && npm --version && hyperframes --version",
            timeoutSeconds = 90,
            taskKind = "hyperframes_cli_probe",
        )
    }

    private fun runHyperFramesTask(
        taskKind: String,
        payload: Map<String, Any?>,
        startedAt: Long,
    ): Map<String, Any?> {
        if (!hasHyperFramesRuntime()) {
            return failure(
                taskKind,
                "dependencyMissing",
                "Install the HyperFrames CLI profile before running this task.",
                startedAt,
            )
        }
        if (taskKind == "hyperframes_render" && payload["approved"] != true) {
            return failure(
                taskKind,
                "approvalRequired",
                "HyperFrames render requires explicit user approval because it writes an MP4 artifact.",
                startedAt,
            )
        }
        val workingDir = linuxWorkingDir(
            payload["cwd"]?.toString() ?: payload["workingDir"]?.toString(),
        ) ?: return failure(
            taskKind,
            "commandBlocked",
            "HyperFrames project cwd must stay under /root.",
            startedAt,
        )
        val command = try {
            when (taskKind) {
                "hyperframes_lint" -> "hyperframes lint . --json"
                "hyperframes_check" -> buildHyperFramesCheckCommand(payload)
                "hyperframes_compositions" -> "hyperframes compositions . --json"
                "hyperframes_render" -> buildHyperFramesRenderCommand(payload)
                else -> throw IllegalArgumentException("Unsupported HyperFrames task: $taskKind")
            }
        } catch (error: IllegalArgumentException) {
            return failure(taskKind, "commandBlocked", error.message ?: "Invalid HyperFrames arguments", startedAt)
        }
        val result = execute(
            command,
            timeoutSeconds = if (taskKind == "hyperframes_render") 300 else 120,
            taskKind = taskKind,
            workingDir = workingDir,
        ).toMutableMap()
        result["metadata"] = mapOf(
            "commandPolicy" to "builtin_hyperframes_allowlist",
            "workingDir" to workingDir,
            "output" to (payload["output"]?.toString() ?: ""),
        )
        return result
    }

    private fun buildHyperFramesCheckCommand(payload: Map<String, Any?>): String {
        val flags = mutableListOf("--json")
        if (payload["snapshots"] == true) flags += "--snapshots"
        if (payload["strict"] == true) flags += "--strict"
        if (payload["noContrast"] == true) flags += "--no-contrast"
        if (payload["frameCheck"] == true) flags += "--frame-check"
        val samples = payload["samples"]?.toString()?.toIntOrNull()
        if (samples != null) flags += "--samples ${samples.coerceIn(1, 100)}"
        return "hyperframes check . ${flags.joinToString(" ")}"
    }

    private fun buildHyperFramesRenderCommand(payload: Map<String, Any?>): String {
        val output = safeHyperFramesRelativePath(
            payload["output"]?.toString().orEmpty().ifBlank { "output.mp4" },
            extension = "mp4",
        )
        val composition = payload["composition"]?.toString()?.trim().orEmpty()
        if (composition.isNotEmpty() && !Regex("^[A-Za-z0-9_.-]+$").matches(composition)) {
            throw IllegalArgumentException("HyperFrames composition must be a simple identifier.")
        }
        val command = StringBuilder("hyperframes render . -o ").append(output)
        if (composition.isNotEmpty()) command.append(" -c ").append(composition)
        return command.toString()
    }

    private fun safeHyperFramesRelativePath(value: String, extension: String): String {
        if (value.startsWith("/") || value.contains("..") ||
            !Regex("^[A-Za-z0-9._/-]+$").matches(value) ||
            !value.lowercase(Locale.US).endsWith(".$extension")
        ) {
            throw IllegalArgumentException(
                "HyperFrames output must be a workspace-relative .$extension path.",
            )
        }
        return value
    }

    private fun execute(
        command: String,
        timeoutSeconds: Long = 30,
        taskKind: String = command,
        workingDir: String = "/root",
    ): Map<String, Any?> {
        val startedAt = System.currentTimeMillis()
        return try {
            val processBuilder = ProcessBuilder(buildProcessArgs(command, workingDir))
                .directory(rootfsDir.parentFile)
            processBuilder.environment().putAll(baseEnv())
            val process = processBuilder.start()
            val stdoutFuture = java.util.concurrent.CompletableFuture.supplyAsync {
                readBounded(process.inputStream.bufferedReader())
            }
            val stderrFuture = java.util.concurrent.CompletableFuture.supplyAsync {
                readBounded(process.errorStream.bufferedReader())
            }
            // Chromium is a large aarch64 Alpine package and PRoot file extraction
            // is substantially slower than the network transfer on emulators.
            val maxTimeoutSeconds = if (taskKind == "package_install") 3600L else 300L
            val completed = process.waitFor(timeoutSeconds.coerceIn(1, maxTimeoutSeconds), TimeUnit.SECONDS)
            if (!completed) {
                process.destroyForcibly()
                return failure(
                    taskKind,
                    "timeout",
                    "Linux Sandbox task timed out",
                    startedAt,
                    stdout = readFutureOrEmpty(stdoutFuture),
                    stderr = readFutureOrEmpty(stderrFuture),
                    exitCode = -1,
                )
            }
            val stdout = stdoutFuture.get()
            val stderr = stderrFuture.get()
            val exitCode = process.exitValue()
            if (exitCode == 0) {
                success(taskKind, stdout, stderr, exitCode, startedAt)
            } else {
                failure(taskKind, "processFailed", stderr.ifBlank { stdout }, startedAt, stdout, stderr, exitCode)
            }
        } catch (error: Throwable) {
            failure(taskKind, "processFailed", error.message ?: error.javaClass.simpleName, startedAt)
        }
    }

    private fun readFutureOrEmpty(future: java.util.concurrent.CompletableFuture<String>): String =
        runCatching { future.get(1, TimeUnit.SECONDS) }.getOrDefault("")

    private fun buildProcessArgs(command: String, workingDir: String = "/root"): List<String> = listOf(
        prootPath,
        "--rootfs=${rootfsDir.absolutePath}",
        "--bind=/dev",
        "--bind=/proc",
        "--bind=/sys",
        "--bind=${homeDir.absolutePath}:/root",
        "--bind=${tmpDir.absolutePath}:/tmp",
        "-0",
        "-w",
        workingDir,
        "/bin/sh",
        "-c",
        command,
    )

    private fun baseEnv(): Map<String, String> = mapOf(
        "HOME" to "/root",
        "PATH" to "/root/.local/bin:/root/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "TERM" to "xterm-256color",
        "LANG" to "C.UTF-8",
        // Alpine already provides Chromium. Pin HyperFrames to it so Android
        // PRoot does not enter the managed-browser download/lock flow.
        "HYPERFRAMES_BROWSER_PATH" to "/usr/bin/chromium",
        "PRODUCER_BROWSER_GPU_MODE" to "software",
        "PRODUCER_FORCE_SCREENSHOT" to "true",
        "LD_LIBRARY_PATH" to sandboxDir.absolutePath,
        "PROOT_TMP_DIR" to tmpDir.absolutePath,
        "PROOT_LOADER" to loaderPath,
    )

    private fun isReady(): Boolean = hasRootfsBootFiles() &&
        File(prootPath).exists() &&
        File(prootPath).canExecute()

    private fun hasLarkCliRuntime(): Boolean =
        File(rootfsDir, "usr/bin/node").isFile &&
            File(rootfsDir, "usr/bin/npm").isFile &&
            hasLarkCliBinary()

    private fun hasLarkCliBinary(): Boolean =
        File(rootfsDir, "usr/bin/lark-cli").isFile ||
            File(rootfsDir, "usr/local/bin/lark-cli").isFile ||
            File(homeDir, ".local/bin/lark-cli").isFile ||
            File(homeDir, ".npm-global/bin/lark-cli").isFile

    private fun hasAgentlyCliRuntime(): Boolean =
        File(rootfsDir, "usr/bin/node").isFile &&
            File(rootfsDir, "usr/bin/npm").isFile &&
            hasAgentlyCliBinary()

    private fun hasAgentlyCliBinary(): Boolean =
        File(rootfsDir, "usr/bin/agently-cli").isFile ||
            File(rootfsDir, "usr/local/bin/agently-cli").isFile ||
            File(homeDir, ".local/bin/agently-cli").isFile ||
            File(homeDir, ".npm-global/bin/agently-cli").isFile

    private fun hasGwsRuntime(): Boolean =
        File(rootfsDir, "usr/bin/node").isFile &&
            File(rootfsDir, "usr/bin/npm").isFile &&
            hasGwsBinary()

    private fun hasGwsBinary(): Boolean =
        File(rootfsDir, "usr/bin/gws").isFile ||
            File(rootfsDir, "usr/local/bin/gws").isFile ||
            File(homeDir, ".local/bin/gws").isFile ||
            File(homeDir, ".npm-global/bin/gws").isFile

    private fun hasGitHubCliRuntime(): Boolean =
        File(rootfsDir, "usr/bin/gh").isFile ||
            File(rootfsDir, "usr/local/bin/gh").isFile ||
            File(homeDir, ".local/bin/gh").isFile ||
            File(homeDir, ".npm-global/bin/gh").isFile

    private fun hasHyperFramesRuntime(): Boolean =
        File(rootfsDir, "usr/bin/node").isFile &&
            File(rootfsDir, "usr/bin/npm").isFile &&
            hasHyperFramesBinary() &&
            hasFfmpegBinary() &&
            hasChromiumBinary()

    private fun hasHyperFramesBinary(): Boolean =
        File(rootfsDir, "usr/bin/hyperframes").isFile ||
            File(rootfsDir, "usr/local/bin/hyperframes").isFile ||
            File(homeDir, ".local/bin/hyperframes").isFile ||
            File(homeDir, ".npm-global/bin/hyperframes").isFile

    private fun hasFfmpegBinary(): Boolean =
        File(rootfsDir, "usr/bin/ffmpeg").isFile ||
            File(rootfsDir, "usr/local/bin/ffmpeg").isFile

    private fun hasChromiumBinary(): Boolean =
        File(rootfsDir, "usr/bin/chromium").isFile ||
            File(rootfsDir, "usr/bin/chromium-browser").isFile ||
            File(rootfsDir, "usr/bin/google-chrome").isFile

    private fun hasRootfsBootFiles(): Boolean {
        val shell = File(rootfsDir, "bin/sh")
        return rootfsDir.isDirectory &&
            (shell.isFile || Files.isSymbolicLink(shell.toPath())) &&
            File(rootfsDir, "bin/busybox").isFile &&
            File(rootfsDir, "sbin/apk").isFile
    }

    private fun linuxWorkingDir(raw: String?): String? {
        val value = raw?.trim().orEmpty().ifBlank { "/root" }
        if (!value.startsWith("/root")) return null
        if (value.split('/').any { it == ".." }) return null
        return value
    }

    private fun linuxArch(): String {
        val abi = Build.SUPPORTED_ABIS.firstOrNull().orEmpty()
        return when {
            abi.startsWith("arm64") -> "aarch64"
            abi.startsWith("x86_64") -> "x86_64"
            abi.startsWith("armeabi") -> "armhf"
            abi.startsWith("x86") -> "x86"
            else -> "aarch64"
        }
    }

    private fun copyLibtalloc() {
        if (!tallocTarget.exists() && tallocSource.exists()) {
            tallocSource.copyTo(tallocTarget, overwrite = true)
        }
    }

    private fun download(url: String, target: File) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 60_000
        }
        try {
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("HTTP ${connection.responseCode} while downloading rootfs")
            }
            connection.inputStream.use { input ->
                FileOutputStream(target).use { output -> input.copyTo(output) }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun extractTarGz(tarGzFile: File, targetDir: File) {
        targetDir.mkdirs()
        GZIPInputStream(BufferedInputStream(FileInputStream(tarGzFile))).use { gzipStream ->
            extractTar(gzipStream, targetDir)
        }
    }

    private fun extractTar(input: java.io.InputStream, targetDir: File) {
        val header = ByteArray(TAR_BLOCK_SIZE)
        val data = ByteArray(BUFFER_SIZE)
        while (true) {
            val headerRead = readFully(input, header)
            if (headerRead < TAR_BLOCK_SIZE) break
            val name = tarString(header, 0, 100)
            if (name.isEmpty()) break
            val prefix = tarString(header, 345, 155)
            val fullName = if (prefix.isNotEmpty()) "$prefix/$name" else name
            val size = tarString(header, 124, 12).ifEmpty { "0" }.toLong(8)
            val mode = tarString(header, 100, 8).ifEmpty { "0" }.toInt(8)
            val type = header[156].toInt().toChar()
            val linkName = tarString(header, 157, 100)
            val output = safeChild(targetDir, fullName)
            if (output == null) {
                skipBytes(input, paddedSize(size))
                continue
            }

            when (type) {
                '5', 'D' -> output.mkdirs()
                '2' -> {
                    output.parentFile?.mkdirs()
                    if (isSafeSymlinkTarget(linkName)) {
                        runCatching {
                            if (output.exists()) output.delete()
                            java.nio.file.Files.createSymbolicLink(output.toPath(), java.nio.file.Paths.get(linkName))
                        }
                    }
                }
                '1' -> {
                    val source = safeChild(targetDir, linkName)
                    output.parentFile?.mkdirs()
                    if (source?.exists() == true) source.copyTo(output, overwrite = true)
                }
                '0', '\u0000' -> {
                    output.parentFile?.mkdirs()
                    FileOutputStream(output).use { fileOut ->
                        var remaining = size
                        while (remaining > 0) {
                            val toRead = minOf(remaining, data.size.toLong()).toInt()
                            val read = input.read(data, 0, toRead)
                            if (read <= 0) break
                            fileOut.write(data, 0, read)
                            remaining -= read
                        }
                    }
                    if (mode and 0b001_001_001 != 0) output.setExecutable(true, false)
                    val padding = paddedSize(size) - size
                    if (padding > 0) skipBytes(input, padding)
                    continue
                }
            }
            if (size > 0 && type != '0' && type != '\u0000') skipBytes(input, paddedSize(size))
        }
    }

    private fun safeChild(root: File, childPath: String): File? {
        if (childPath.startsWith("/") || childPath.split('/').any { it == ".." }) return null
        val output = File(root, childPath)
        val rootPath = root.canonicalPath
        val outputPath = output.canonicalPath
        if (outputPath != rootPath && !outputPath.startsWith("$rootPath${File.separator}")) return null
        return output
    }

    private fun isSafeSymlinkTarget(linkName: String): Boolean {
        if (linkName.isBlank()) return false
        return !linkName.split('/').any { it == ".." }
    }

    private fun prepareRootfsForPackageMutation() {
        makeWritable(rootfsDir)
        listOf(
            "lib/apk/db",
            "var/cache/apk",
            "var/lib/apk",
            "tmp",
        ).forEach { relativePath ->
            safeChild(rootfsDir, relativePath)?.apply {
                mkdirs()
                setReadable(true, true)
                setWritable(true, true)
                setExecutable(true, true)
            }
        }
    }

    private fun makeWritable(root: File) {
        root.walkTopDown().forEach { file ->
            file.setReadable(true, true)
            file.setWritable(true, true)
            if (file.isDirectory) file.setExecutable(true, true)
        }
    }

    private fun writeResolvConf(root: File) {
        File(root, "etc").mkdirs()
        val isAndroidEmulator = Build.FINGERPRINT.startsWith("generic") ||
            Build.MODEL.contains("sdk_gphone", ignoreCase = true)
        val resolvers = if (isAndroidEmulator) {
            "nameserver 10.0.2.3\nnameserver 8.8.8.8\n"
        } else {
            "nameserver 8.8.8.8\nnameserver 1.1.1.1\n"
        }
        File(root, "etc/resolv.conf").writeText(resolvers)
    }

    private fun writeRepositories(root: File, version: String, repositoryBaseUrl: String = "") {
        val branch = if (version.matches(Regex("\\d+\\.\\d+\\.\\d+"))) {
            "v${version.substringBeforeLast('.')}"
        } else {
            "latest-stable"
        }
        val customMirror = repositoryBaseUrl.trim().trimEnd('/').ifBlank { null }
        // PRoot on the generic Android emulator can establish an HTTPS socket
        // but never completes the TLS exchange. Alpine still verifies APK
        // signatures, so use the mirror's plain HTTP transport only there;
        // physical Android devices keep the HTTPS repository boundary.
        val isAndroidEmulator = Build.FINGERPRINT.startsWith("generic") ||
            Build.MODEL.contains("sdk_gphone", ignoreCase = true)
        val scheme = if (isAndroidEmulator) "http" else "https"
        val apk = File(root, "etc/apk").apply { mkdirs() }
        File(apk, "repositories").writeText(
            "${customMirror ?: "$scheme://dl-cdn.alpinelinux.org"}/alpine/$branch/main\n" +
                "${customMirror ?: "$scheme://dl-cdn.alpinelinux.org"}/alpine/$branch/community\n",
        )
    }

    private fun writeRepositoryHosts(root: File, repositoryBaseUrl: String = "") {
        if (repositoryBaseUrl.isNotBlank()) return
        val isAndroidEmulator = Build.FINGERPRINT.startsWith("generic") ||
            Build.MODEL.contains("sdk_gphone", ignoreCase = true)
        if (!isAndroidEmulator) return

        // Android's DNS result can rotate across CDN edges. Probe the edges
        // from the native process, then pin one reachable IPv4 for PRoot's
        // apk HTTP client, whose resolver cannot reliably recover from a bad
        // edge. APK signatures still provide package integrity verification.
        val fallback = runCatching {
            // Stable Fastly edge used by the local Android emulator network.
            InetAddress.getByName("146.75.114.132")
        }.getOrNull()
        val candidates = listOfNotNull(fallback) + runCatching {
            InetAddress.getAllByName("dl-cdn.alpinelinux.org")
                .filter { it.address.size == 4 }
        }.getOrDefault(emptyList())
        val reachable = candidates.firstOrNull { address ->
            runCatching {
                Socket().use { socket ->
                    socket.connect(InetSocketAddress(address, 80), 2500)
                    socket.soTimeout = 3000
                    socket.getOutputStream().write(
                        (
                            "HEAD /alpine/v3.24/main/aarch64/APKINDEX.tar.gz HTTP/1.1\r\n" +
                                "Host: dl-cdn.alpinelinux.org\r\n" +
                                "Connection: close\r\n\r\n"
                        ).toByteArray(Charsets.US_ASCII)
                    )
                    socket.getOutputStream().flush()
                    socket.getInputStream().bufferedReader().readLine()?.contains(" 200 ") == true
                }
            }.getOrDefault(false)
        } ?: return

        val hosts = File(root, "etc/hosts")
        val existing = if (hosts.isFile) hosts.readText() else "127.0.0.1 localhost\n"
        if (!existing.contains("dl-cdn.alpinelinux.org")) {
            hosts.writeText(
                existing.trimEnd() +
                    "\n${reachable.hostAddress} dl-cdn.alpinelinux.org\n",
            )
        }
    }

    private fun readFully(input: java.io.InputStream, buffer: ByteArray): Int {
        var total = 0
        while (total < buffer.size) {
            val read = input.read(buffer, total, buffer.size - total)
            if (read <= 0) break
            total += read
        }
        return total
    }

    private fun skipBytes(input: java.io.InputStream, count: Long) {
        var remaining = count
        while (remaining > 0) {
            val skipped = input.skip(remaining)
            if (skipped <= 0) {
                if (input.read() < 0) break
                remaining--
            } else {
                remaining -= skipped
            }
        }
    }

    private fun paddedSize(size: Long): Long {
        val remainder = size % TAR_BLOCK_SIZE
        return if (remainder == 0L) size else size + TAR_BLOCK_SIZE - remainder
    }

    private fun tarString(buffer: ByteArray, offset: Int, length: Int): String {
        val end = minOf(offset + length, buffer.size)
        val nullIndex = (offset until end).firstOrNull { buffer[it] == 0.toByte() } ?: end
        return String(buffer, offset, nullIndex - offset, Charsets.US_ASCII).trim()
    }

    private fun readBounded(reader: BufferedReader): String {
        val builder = StringBuilder()
        val buffer = CharArray(8192)
        while (builder.length < MAX_OUTPUT_LENGTH) {
            val read = reader.read(buffer)
            if (read <= 0) break
            builder.append(buffer, 0, read)
        }
        return redact(builder.toString().take(MAX_OUTPUT_LENGTH))
    }

    private fun readUntilFirstHttpsUrl(reader: BufferedReader): String {
        val builder = StringBuilder()
        val buffer = CharArray(512)
        while (builder.length < MAX_OUTPUT_LENGTH) {
            val read = reader.read(buffer)
            if (read <= 0) break
            builder.append(buffer, 0, read)
            if (firstHttpsUrl(builder.toString()) != null) break
        }
        return redact(builder.toString().take(MAX_OUTPUT_LENGTH))
    }

    private fun firstHttpsUrl(value: String): String? =
        Regex("https://[^\\s<>\"）)]+").find(value)?.value

    private fun success(
        taskKind: String,
        stdout: String,
        stderr: String,
        exitCode: Int,
        startedAt: Long,
        metadata: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> = mapOf(
        "success" to true,
        "taskId" to "linux-sandbox-$startedAt",
        "taskKind" to taskKind,
        "status" to "succeeded",
        "stdout" to redact(stdout),
        "stderr" to redact(stderr),
        "exitCode" to exitCode,
        "durationMs" to (System.currentTimeMillis() - startedAt),
        "failureKind" to "none",
        "metadata" to metadata,
    )

    private fun failure(
        taskKind: String,
        failureKind: String,
        message: String,
        startedAt: Long,
        stdout: String = "",
        stderr: String = message,
        exitCode: Int = 127,
        metadata: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> = mapOf(
        "success" to false,
        "taskId" to "linux-sandbox-$startedAt",
        "taskKind" to taskKind,
        "status" to "failed",
        "stdout" to redact(stdout),
        "stderr" to redact(stderr),
        "exitCode" to exitCode,
        "durationMs" to (System.currentTimeMillis() - startedAt),
        "failureKind" to failureKind,
        "metadata" to metadata,
    )

    private fun redact(value: String): String = value
        .replace(Regex("(?i)(token|cookie|secret|password)=\\S+"), "$1=<redacted>")
        .replace(Regex("(?i)(bearer\\s+)[A-Za-z0-9._\\-]+"), "$1<redacted>")

    companion object {
        private const val TAR_BLOCK_SIZE = 512
        private const val BUFFER_SIZE = 8192
        private const val MAX_OUTPUT_LENGTH = 15000
    }
}
