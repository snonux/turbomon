package org.buetow.turbomon.platform

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.TextView
import kotlin.math.abs

/**
 * The small floating readout drawn over other apps while the monitor service
 * runs. Drag to move; tap to open TurboMon.
 */
class OverlayController(private val context: Context) {
    private val windowManager = context.getSystemService(WindowManager::class.java)
    private var view: TextView? = null

    fun canDraw(): Boolean = Settings.canDrawOverlays(context)

    fun show(text: String) {
        if (!canDraw()) return
        val existing = view
        if (existing != null) {
            existing.text = text
            return
        }
        val label = TextView(context).apply {
            this.text = text
            setTextColor(0xFFFFFFFF.toInt())
            typeface = Typeface.MONOSPACE
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            val pad = dp(6)
            setPadding(pad, pad / 2, pad, pad / 2)
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setColor(0xCC0B1E3F.toInt())
                setStroke(dp(1), 0xFFFF7A1A.toInt())
            }
        }
        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(8)
            y = dp(96)
        }
        label.setOnTouchListener(DragListener(params))
        runCatching { windowManager.addView(label, params) }.onSuccess { view = label }
    }

    fun hide() {
        view?.let { runCatching { windowManager.removeView(it) } }
        view = null
    }

    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()

    private inner class DragListener(private val params: WindowManager.LayoutParams) : android.view.View.OnTouchListener {
        private val slop = ViewConfiguration.get(context).scaledTouchSlop
        private var startX = 0
        private var startY = 0
        private var touchX = 0f
        private var touchY = 0f
        private var moved = false

        @SuppressLint("ClickableViewAccessibility") // A tap opens the app; there is no other action to expose.
        override fun onTouch(v: android.view.View, event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    moved = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - touchX
                    val dy = event.rawY - touchY
                    if (abs(dx) > slop || abs(dy) > slop) moved = true
                    if (moved) {
                        params.x = startX + dx.toInt()
                        params.y = startY + dy.toInt()
                        runCatching { windowManager.updateViewLayout(v, params) }
                    }
                }
                MotionEvent.ACTION_UP -> if (!moved) {
                    // Holding "display over other apps" exempts this from the
                    // background activity start limits.
                    context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                        runCatching { context.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                    }
                }
            }
            return true
        }
    }
}
