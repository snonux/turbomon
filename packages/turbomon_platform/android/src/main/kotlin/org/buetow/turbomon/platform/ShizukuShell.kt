package org.buetow.turbomon.platform

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.IBinder
import rikka.shizuku.Shizuku
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Optional ADB-shell access through Shizuku. Everything here degrades to
 * "unavailable" when Shizuku is not installed or not running.
 */
class ShizukuShell(private val context: Context) {
    @Volatile private var service: IShellService? = null
    @Volatile private var connected = CountDownLatch(1)

    // Guards against binding again on every call while Shizuku is still
    // starting the shell process, which can take many seconds on slow phones.
    private var bindRequested = false

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder?) {
            if (binder != null && binder.pingBinder()) {
                service = IShellService.Stub.asInterface(binder)
                connected.countDown()
            }
        }

        override fun onServiceDisconnected(name: ComponentName) = reset()
    }

    // Shizuku restarted or stopped: the old shell binder is gone with it.
    private val binderDead = Shizuku.OnBinderDeadListener { reset() }

    init {
        Shizuku.addBinderDeadListener(binderDead)
    }

    @Synchronized
    private fun reset() {
        service = null
        bindRequested = false
        connected = CountDownLatch(1)
    }

    @Synchronized
    private fun bindOnce(): CountDownLatch {
        if (!bindRequested) {
            Shizuku.bindUserService(args, connection)
            bindRequested = true
        }
        return connected
    }

    private val args = Shizuku.UserServiceArgs(ComponentName(context.packageName, ShellService::class.java.name))
        .daemon(false)
        .processNameSuffix("shell")
        .version(1)

    fun status(): Map<String, Any?> {
        val running = runCatching { Shizuku.pingBinder() }.getOrDefault(false)
        val legacy = running && Shizuku.isPreV11()
        return mapOf(
            "running" to running,
            "granted" to (running && !legacy && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED),
            "legacy" to legacy,
            "uid" to if (running) runCatching { Shizuku.getUid() }.getOrNull() else null,
        )
    }

    /** Shows Shizuku's permission dialog; [onResult] gets whether it was granted. */
    fun requestPermission(onResult: (Boolean) -> Unit) {
        if (!Shizuku.pingBinder()) return onResult(false)
        if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) return onResult(true)
        val listener = object : Shizuku.OnRequestPermissionResultListener {
            override fun onRequestPermissionResult(requestCode: Int, grantResult: Int) {
                if (requestCode != REQUEST_CODE) return
                Shizuku.removeRequestPermissionResultListener(this)
                onResult(grantResult == PackageManager.PERMISSION_GRANTED)
            }
        }
        Shizuku.addRequestPermissionResultListener(listener)
        Shizuku.requestPermission(REQUEST_CODE)
    }

    /** Runs [script] with shell rights. Blocks, so call it off the main thread. */
    fun exec(script: String): String {
        check(Shizuku.pingBinder()) { "Shizuku is not running" }
        check(Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) { "Shizuku permission not granted" }
        val shell = service ?: run {
            check(bindOnce().await(BIND_TIMEOUT_S, TimeUnit.SECONDS)) { "Shizuku shell is still starting" }
            service ?: error("Shizuku shell disconnected")
        }
        return shell.exec(script)
    }

    fun dispose() {
        Shizuku.removeBinderDeadListener(binderDead)
        if (service != null) runCatching { Shizuku.unbindUserService(args, connection, true) }
        reset()
    }

    private companion object {
        const val REQUEST_CODE = 4711
        const val BIND_TIMEOUT_S = 30L
    }
}
