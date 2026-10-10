package org.buetow.turbomon

import android.content.Context
import android.content.pm.PackageManager
import rikka.shizuku.Shizuku
import java.util.concurrent.TimeUnit

/** Output of a privileged command. */
data class ExecResult(val exitCode: Int, val stdout: String, val stderr: String)

/**
 * Runs shell commands with Shizuku's shell rights or with root. Shizuku is
 * preferred: it needs no su prompt and works on unrooted phones.
 */
object Privileged {
    private const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"

    fun shizukuState(context: Context): String {
        val alive =
            try {
                Shizuku.pingBinder() && !Shizuku.isPreV11()
            } catch (e: Throwable) {
                false
            }
        if (!alive) {
            val installed =
                try {
                    context.packageManager.getPackageInfo(SHIZUKU_PACKAGE, 0)
                    true
                } catch (e: PackageManager.NameNotFoundException) {
                    false
                }
            return if (installed) "not_running" else "missing"
        }
        return if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) "granted" else "denied"
    }

    /**
     * Shizuku.newProcess is hidden in API 13 in favour of bound user services,
     * but it is still there and is by far the simplest way to run `cat` or
     * `dumpsys` as the shell user; it is called reflectively for that reason.
     */
    fun shizukuExec(command: String, timeoutSeconds: Long = 10): ExecResult {
        return try {
            val m =
                Shizuku::class.java.getDeclaredMethod(
                    "newProcess",
                    Array<String>::class.java,
                    Array<String>::class.java,
                    String::class.java,
                )
            m.isAccessible = true
            val p = m.invoke(null, arrayOf("sh", "-c", command), null, null) as Process
            collect(p, timeoutSeconds)
        } catch (e: Throwable) {
            ExecResult(-1, "", e.toString())
        }
    }

    fun rootExec(command: String, timeoutSeconds: Long = 10): ExecResult =
        try {
            collect(ProcessBuilder("su", "-c", command).start(), timeoutSeconds)
        } catch (e: Throwable) {
            ExecResult(-1, "", e.toString())
        }

    fun rootAvailable(): Boolean = rootExec("id", 15).let { it.exitCode == 0 && it.stdout.contains("uid=0") }

    private fun collect(p: Process, timeoutSeconds: Long): ExecResult {
        var out = ""
        var err = ""
        val tOut = Thread { out = p.inputStream.bufferedReader().readText() }
        val tErr = Thread { err = p.errorStream.bufferedReader().readText() }
        tOut.start()
        tErr.start()
        val done = p.waitFor(timeoutSeconds, TimeUnit.SECONDS)
        if (!done) p.destroy()
        tOut.join(1000)
        tErr.join(1000)
        return ExecResult(if (done) p.exitValue() else -1, out, err)
    }

    /**
     * The runner for an access mode ("auto", "normal", "shizuku", "root"),
     * or null when that access is not available right now.
     */
    fun runnerFor(context: Context, mode: String): ((String) -> ExecResult)? {
        val shizuku = { cmd: String -> shizukuExec(cmd) }
        val root = { cmd: String -> rootExec(cmd) }
        return when (mode) {
            "normal" -> null
            "shizuku" -> if (shizukuState(context) == "granted") shizuku else null
            "root" -> if (rootAvailable()) root else null
            else ->
                when {
                    shizukuState(context) == "granted" -> shizuku
                    rootAvailable() -> root
                    else -> null
                }
        }
    }
}
