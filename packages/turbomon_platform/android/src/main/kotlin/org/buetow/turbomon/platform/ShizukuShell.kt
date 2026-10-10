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
    private var connected = CountDownLatch(1)

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder?) {
            if (binder != null && binder.pingBinder()) {
                service = IShellService.Stub.asInterface(binder)
                connected.countDown()
            }
        }

        override fun onServiceDisconnected(name: ComponentName) {
            service = null
            connected = CountDownLatch(1)
        }
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
            Shizuku.bindUserService(args, connection)
            check(connected.await(BIND_TIMEOUT_S, TimeUnit.SECONDS)) { "Shizuku shell did not start" }
            service ?: error("Shizuku shell disconnected")
        }
        return shell.exec(script)
    }

    fun dispose() {
        if (service != null) runCatching { Shizuku.unbindUserService(args, connection, true) }
        service = null
    }

    private companion object {
        const val REQUEST_CODE = 4711
        const val BIND_TIMEOUT_S = 10L
    }
}
