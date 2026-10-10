package org.buetow.turbomon.platform

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Foreground service for background scanning. It hosts a headless Flutter
 * engine running the Dart `backgroundMain` entry point, so sampling, history,
 * alerts and auto-stop share the app's Dart code. The service itself only owns
 * the notification and the floating overlay.
 */
class MonitorService : Service() {
    private var engine: FlutterEngine? = null
    private var overlay: OverlayController? = null
    private var statusText = "Starting…"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Notifications.ensureChannels(this)
        overlay = OverlayController(this)
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        intent?.getStringExtra(EXTRA_CONFIG)?.let { saveConfig(this, it) }
        startInForeground()
        if (engine == null) startEngine()
        // Not sticky: after a crash or kill the user restarts it, so it can
        // never come back on its own and drain the battery unnoticed.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        instance = null
        overlay?.hide()
        engine?.destroy()
        engine = null
        super.onDestroy()
    }

    fun updateStatus(text: String) {
        statusText = text
        getSystemService(NotificationManager::class.java).notify(Notifications.MONITOR_ID, buildNotification())
    }

    fun updateOverlay(text: String?) {
        if (text == null) overlay?.hide() else overlay?.show(text)
    }

    private fun startInForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(Notifications.MONITOR_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(Notifications.MONITOR_ID, notification)
        }
    }

    private fun startEngine() {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        // The constructor registers every plugin, this one included, so the
        // Dart side reaches the service through the usual method channel.
        engine = FlutterEngine(applicationContext).also {
            it.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), BACKGROUND_ENTRYPOINT),
            )
        }
    }

    private fun buildNotification(): Notification {
        val stop = PendingIntent.getService(
            this,
            0,
            Intent(this, MonitorService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return Notifications.builder(this, Notifications.MONITOR_CHANNEL)
            .setSmallIcon(R.drawable.turbomon_notification)
            .setContentTitle("TurboMon background scan")
            .setContentText(statusText)
            .setStyle(Notification.BigTextStyle().bigText(statusText))
            .setContentIntent(Notifications.openAppIntent(this))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
    }

    companion object {
        const val ACTION_STOP = "org.buetow.turbomon.STOP"
        const val EXTRA_CONFIG = "config"
        private const val BACKGROUND_ENTRYPOINT = "backgroundMain"
        private const val PREFS = "turbomon_service"
        private const val KEY_CONFIG = "config"

        /** The running service, if any; only touched on the main thread. */
        var instance: MonitorService? = null
            private set

        val isRunning: Boolean get() = instance != null

        fun start(context: Context, config: String?) {
            val intent = Intent(context, MonitorService::class.java)
            if (config != null) intent.putExtra(EXTRA_CONFIG, config)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MonitorService::class.java))
        }

        /** The last configuration started, reused by the quick-settings tile. */
        fun savedConfig(context: Context): String? =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_CONFIG, null)

        private fun saveConfig(context: Context, config: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_CONFIG, config).apply()
        }
    }
}
