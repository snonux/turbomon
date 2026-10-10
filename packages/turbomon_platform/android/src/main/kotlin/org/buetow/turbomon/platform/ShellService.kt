package org.buetow.turbomon.platform

import java.io.File
import kotlin.system.exitProcess

/**
 * Shizuku user service: Shizuku starts this class in its own process with ADB
 * shell rights, so the scripts it runs can read /proc/stat, run top and
 * dumpsys, which a normal app cannot. Shizuku requires the no-arg constructor.
 */
class ShellService : IShellService.Stub() {
    override fun destroy() {
        exitProcess(0)
    }

    override fun exec(script: String): String {
        val process = ProcessBuilder("sh", "-c", script)
            // An undrained stderr pipe can fill up and block the script.
            .redirectError(File("/dev/null"))
            .start()
        val output = process.inputStream.bufferedReader().use { it.readText() }
        process.waitFor()
        return output
    }
}
