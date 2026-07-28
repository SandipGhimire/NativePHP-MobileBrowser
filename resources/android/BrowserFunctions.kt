package com.sandip.plugins.browser

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.net.Uri
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.fragment.app.FragmentActivity
import com.nativephp.mobile.bridge.BridgeFunction
import com.nativephp.mobile.bridge.BridgeResponse
import com.nativephp.mobile.utils.NativeActionCoordinator
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONObject

object BrowserFunctions {

    private const val TAG = "BrowserFunctions"
    private const val OPENED_EVENT = "Sandip\\Browser\\Native\\Events\\Browser\\Opened"
    private const val CLOSED_EVENT = "Sandip\\Browser\\Native\\Events\\Browser\\Closed"

    private const val VALID_MODES = "webview, external"

    @Volatile private var activeOverlay: BrowserOverlay? = null

    private fun dispatchOpened(activity: FragmentActivity, url: String, mode: String, id: String?) {
        val payload = JSONObject()
        payload.put("url", url)
        payload.put("mode", mode)
        if (id != null) payload.put("id", id)
        NativeActionCoordinator.dispatchEvent(activity, OPENED_EVENT, payload.toString())
    }

    private fun dispatchClosed(activity: FragmentActivity, reason: String, id: String?) {
        val payload = JSONObject()
        payload.put("reason", reason)
        if (id != null) payload.put("id", id)
        NativeActionCoordinator.dispatchEvent(activity, CLOSED_EVENT, payload.toString())
    }

    class Open(private val activity: FragmentActivity) : BridgeFunction {
        override fun execute(parameters: Map<String, Any>): Map<String, Any> {
            val url = parameters["url"] as? String
            if (url.isNullOrBlank()) {
                return BridgeResponse.error("INVALID_URL", "A URL must be provided.")
            }

            val mode = parameters["mode"] as? String ?: "webview"
            if (mode != "webview" && mode != "external") {
                return BridgeResponse.error(
                        "INVALID_MODE",
                        "Invalid browser mode: $mode. Valid modes are: $VALID_MODES."
                )
            }

            val id = parameters["id"] as? String

            if (mode == "external") {
                return openExternal(url, id)
            }

            val title = parameters["title"] as? String
            val showToolbar = parameters["showToolbar"] as? Boolean ?: true
            val showNavigationButtons = parameters["showNavigationButtons"] as? Boolean ?: true
            val shareButton = parameters["shareButton"] as? Boolean ?: true
            val desktopMode = parameters["desktopMode"] as? Boolean ?: false

            activity.runOnUiThread {
                activeOverlay?.finish(reason = "replaced")
                val overlay =
                        BrowserOverlay(
                                activity,
                                url,
                                title,
                                showToolbar,
                                showNavigationButtons,
                                shareButton,
                                desktopMode,
                                id
                        )
                activeOverlay = overlay
                overlay.show()
            }

            return BridgeResponse.success(mapOf("started" to true))
        }

        private fun openExternal(url: String, id: String?): Map<String, Any> {
            val uri =
                    try {
                        Uri.parse(url)
                    } catch (e: Exception) {
                        return BridgeResponse.error("INVALID_URL", "Could not parse URL: $url")
                    }

            val intent = Intent(Intent.ACTION_VIEW, uri)

            if (intent.resolveActivity(activity.packageManager) == null) {
                return BridgeResponse.error(
                        "NO_BROWSER_AVAILABLE",
                        "No application is available to open this URL."
                )
            }

            try {
                activity.startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch external browser", e)
                return BridgeResponse.error("LAUNCH_FAILED", "Failed to open the external browser.")
            }

            dispatchOpened(activity, url, "external", id)

            return BridgeResponse.success(mapOf("started" to true))
        }
    }

    class Close(private val activity: FragmentActivity) : BridgeFunction {
        override fun execute(parameters: Map<String, Any>): Map<String, Any> {
            val id = parameters["id"] as? String
            val overlay = activeOverlay

            if (overlay == null || (id != null && overlay.id != id)) {
                return BridgeResponse.success(mapOf("closed" to false))
            }

            activity.runOnUiThread { overlay.finish(reason = "closed_by_app") }

            return BridgeResponse.success(mapOf("closed" to true))
        }
    }

    private class IconButtonView(
            context: android.content.Context,
            initialGlyph: (Canvas, Float, Float, Float) -> Unit,
    ) : View(context) {
        var glyph: (Canvas, Float, Float, Float) -> Unit = initialGlyph
            set(value) {
                field = value
                invalidate()
            }

        var disabled: Boolean = false
            set(value) {
                field = value
                alpha = if (value) 0.35f else 1f
                isClickable = !value
            }

        private val circlePaint =
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.WHITE
                    style = Paint.Style.FILL
                }

        init {
            isClickable = true
            isFocusable = true
        }

        override fun onDraw(canvas: Canvas) {
            val cx = width / 2f
            val cy = height / 2f
            val radius = minOf(width, height) / 2f
            canvas.drawCircle(cx, cy, radius, circlePaint)
            glyph(canvas, cx, cy, radius * 0.5f)
        }
    }

    private fun drawCloseIcon(canvas: Canvas, cx: Float, cy: Float, r: Float) {
        val paint =
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.BLACK
                    style = Paint.Style.STROKE
                    strokeWidth = r * 0.24f
                    strokeCap = Paint.Cap.ROUND
                }
        val d = r * 0.72f
        canvas.drawLine(cx - d, cy - d, cx + d, cy + d, paint)
        canvas.drawLine(cx - d, cy + d, cx + d, cy - d, paint)
    }

    private fun drawBackIcon(canvas: Canvas, cx: Float, cy: Float, r: Float) {
        val paint =
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.BLACK
                    style = Paint.Style.STROKE
                    strokeWidth = r * 0.24f
                    strokeCap = Paint.Cap.ROUND
                    strokeJoin = Paint.Join.ROUND
                }
        val d = r * 0.6f
        val path =
                Path().apply {
                    moveTo(cx + d, cy - d)
                    lineTo(cx - d, cy)
                    lineTo(cx + d, cy + d)
                }
        canvas.drawPath(path, paint)
    }

    private fun drawForwardIcon(canvas: Canvas, cx: Float, cy: Float, r: Float) {
        val paint =
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.BLACK
                    style = Paint.Style.STROKE
                    strokeWidth = r * 0.24f
                    strokeCap = Paint.Cap.ROUND
                    strokeJoin = Paint.Join.ROUND
                }
        val d = r * 0.6f
        val path =
                Path().apply {
                    moveTo(cx - d, cy - d)
                    lineTo(cx + d, cy)
                    lineTo(cx - d, cy + d)
                }
        canvas.drawPath(path, paint)
    }

    private fun drawReloadIcon(canvas: Canvas, cx: Float, cy: Float, r: Float) {
        val paint =
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.BLACK
                    style = Paint.Style.STROKE
                    strokeWidth = r * 0.22f
                    strokeCap = Paint.Cap.ROUND
                }
        val radius = r * 0.62f
        val oval = android.graphics.RectF(cx - radius, cy - radius, cx + radius, cy + radius)
        canvas.drawArc(oval, -60f, 260f, false, paint)

        val arrowPaint =
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.BLACK
                    style = Paint.Style.FILL
                }
        val angleRad = Math.toRadians(-60.0)
        val tipX = (cx + radius * Math.cos(angleRad)).toFloat()
        val tipY = (cy + radius * Math.sin(angleRad)).toFloat()
        val arrow =
                Path().apply {
                    moveTo(tipX, tipY - r * 0.28f)
                    lineTo(tipX + r * 0.3f, tipY)
                    lineTo(tipX - r * 0.05f, tipY + r * 0.28f)
                    close()
                }
        canvas.drawPath(arrow, arrowPaint)
    }

    private fun drawShareIcon(canvas: Canvas, cx: Float, cy: Float, r: Float) {
        val paint =
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.BLACK
                    style = Paint.Style.STROKE
                    strokeWidth = r * 0.2f
                    strokeCap = Paint.Cap.ROUND
                    strokeJoin = Paint.Join.ROUND
                }
        val s = r * 0.55f
        canvas.drawLine(cx, cy - s, cx, cy + s * 0.5f, paint)
        val arrow =
                Path().apply {
                    moveTo(cx - s * 0.55f, cy - s * 0.45f)
                    lineTo(cx, cy - s)
                    lineTo(cx + s * 0.55f, cy - s * 0.45f)
                }
        canvas.drawPath(arrow, paint)

        val boxPaint =
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.BLACK
                    style = Paint.Style.STROKE
                    strokeWidth = r * 0.2f
                    strokeCap = Paint.Cap.ROUND
                    strokeJoin = Paint.Join.ROUND
                }
        val box =
                Path().apply {
                    moveTo(cx - s, cy)
                    lineTo(cx - s, cy + s)
                    lineTo(cx + s, cy + s)
                    lineTo(cx + s, cy)
                }
        canvas.drawPath(box, boxPaint)
    }

    private class BrowserOverlay(
            private val activity: FragmentActivity,
            private val url: String,
            private val titleOverride: String?,
            private val showToolbar: Boolean,
            private val showNavigationButtons: Boolean,
            private val shareButtonEnabled: Boolean,
            private val desktopMode: Boolean,
            val id: String?,
    ) {
        private val root = activity.findViewById<ViewGroup>(android.R.id.content)
        private val finished = AtomicBoolean(false)
        private val openedFired = AtomicBoolean(false)

        private var overlayView: FrameLayout? = null
        private var webView: WebView? = null
        private var titleLabel: TextView? = null
        private var progressBar: ProgressBar? = null
        private var backButton: IconButtonView? = null
        private var forwardButton: IconButtonView? = null

        private fun dp(value: Int): Int =
                (value * activity.resources.displayMetrics.density).toInt()

        fun show() {
            val toolbarHeight = if (showToolbar) dp(56) else 0
            val navBarHeight = if (showNavigationButtons) dp(56) else 0

            val webView =
                    WebView(activity).apply {
                        layoutParams =
                                FrameLayout.LayoutParams(
                                                FrameLayout.LayoutParams.MATCH_PARENT,
                                                FrameLayout.LayoutParams.MATCH_PARENT
                                        )
                                        .apply {
                                            topMargin = toolbarHeight
                                            bottomMargin = navBarHeight
                                        }
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        if (desktopMode) {
                            settings.useWideViewPort = true
                            settings.loadWithOverviewMode = true
                            settings.userAgentString =
                                    settings.userAgentString
                                            ?.replace("Mobile", "")
                                            ?.plus(" Desktop")
                        }
                        webViewClient =
                                object : WebViewClient() {
                                    override fun onPageFinished(view: WebView, finishedUrl: String) {
                                        super.onPageFinished(view, finishedUrl)
                                        progressBar?.visibility = View.GONE
                                        backButton?.disabled = !view.canGoBack()
                                        forwardButton?.disabled = !view.canGoForward()
                                        if (titleOverride == null) {
                                            titleLabel?.text = view.title ?: finishedUrl
                                        }
                                        if (openedFired.compareAndSet(false, true)) {
                                            dispatchOpened(activity, url, "webview", id)
                                        }
                                    }

                                    override fun onReceivedError(
                                            view: WebView,
                                            errorCode: Int,
                                            description: String?,
                                            failingUrl: String?
                                    ) {
                                        super.onReceivedError(view, errorCode, description, failingUrl)
                                        Log.w(TAG, "WebView load error $errorCode: $description")
                                    }
                                }
                        webChromeClient =
                                object : WebChromeClient() {
                                    override fun onProgressChanged(view: WebView, newProgress: Int) {
                                        super.onProgressChanged(view, newProgress)
                                        progressBar?.apply {
                                            visibility = if (newProgress >= 100) View.GONE else View.VISIBLE
                                            progress = newProgress
                                        }
                                    }
                                }
                    }
            this.webView = webView

            val overlay =
                    FrameLayout(activity).apply {
                        setBackgroundColor(Color.WHITE)
                        addView(webView)
                        layoutParams =
                                FrameLayout.LayoutParams(
                                        FrameLayout.LayoutParams.MATCH_PARENT,
                                        FrameLayout.LayoutParams.MATCH_PARENT
                                )
                    }

            if (showToolbar) {
                overlay.addView(buildToolbar(toolbarHeight))
            }

            if (showNavigationButtons) {
                overlay.addView(buildNavigationBar(navBarHeight))
            }

            overlayView = overlay
            root.addView(overlay)

            webView.loadUrl(url)
        }

        private fun buildToolbar(height: Int): View {
            val bar =
                    FrameLayout(activity).apply {
                        setBackgroundColor(Color.WHITE)
                        layoutParams =
                                FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, height)
                                        .apply { gravity = Gravity.TOP }
                        elevation = dp(4).toFloat()
                    }

            val closeButton =
                    IconButtonView(activity) { canvas, cx, cy, r -> drawCloseIcon(canvas, cx, cy, r) }
                            .apply {
                                layoutParams =
                                        FrameLayout.LayoutParams(
                                                        dp(40),
                                                        dp(40),
                                                        Gravity.CENTER_VERTICAL or Gravity.START
                                                )
                                                .apply { leftMargin = dp(8) }
                                setOnClickListener { finish(reason = "user_closed") }
                            }
            bar.addView(closeButton)

            val label =
                    TextView(activity).apply {
                        text = titleOverride ?: url
                        setTextColor(Color.BLACK)
                        textSize = 15f
                        maxLines = 1
                        ellipsize = android.text.TextUtils.TruncateAt.MIDDLE
                        gravity = Gravity.CENTER
                        layoutParams =
                                FrameLayout.LayoutParams(
                                                FrameLayout.LayoutParams.MATCH_PARENT,
                                                FrameLayout.LayoutParams.WRAP_CONTENT,
                                                Gravity.CENTER
                                        )
                                        .apply {
                                            leftMargin = dp(56)
                                            rightMargin = dp(56)
                                        }
                    }
            titleLabel = label
            bar.addView(label)

            if (shareButtonEnabled) {
                val shareButton =
                        IconButtonView(activity) { canvas, cx, cy, r ->
                            drawShareIcon(canvas, cx, cy, r)
                        }
                                .apply {
                                    layoutParams =
                                            FrameLayout.LayoutParams(
                                                            dp(40),
                                                            dp(40),
                                                            Gravity.CENTER_VERTICAL or Gravity.END
                                                    )
                                                    .apply { rightMargin = dp(8) }
                                    setOnClickListener { shareCurrentUrl() }
                                }
                bar.addView(shareButton)
            }

            val progress =
                    ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal).apply {
                        max = 100
                        layoutParams =
                                FrameLayout.LayoutParams(
                                                FrameLayout.LayoutParams.MATCH_PARENT,
                                                dp(2),
                                                Gravity.BOTTOM
                                        )
                    }
            progressBar = progress
            bar.addView(progress)

            return bar
        }

        private fun buildNavigationBar(height: Int): View {
            val bar =
                    FrameLayout(activity).apply {
                        setBackgroundColor(Color.WHITE)
                        layoutParams =
                                FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, height)
                                        .apply { gravity = Gravity.BOTTOM }
                        elevation = dp(4).toFloat()
                    }

            val back =
                    IconButtonView(activity) { canvas, cx, cy, r -> drawBackIcon(canvas, cx, cy, r) }
                            .apply {
                                disabled = true
                                layoutParams =
                                        FrameLayout.LayoutParams(dp(40), dp(40), Gravity.CENTER)
                                                .apply { rightMargin = dp(72) }
                                setOnClickListener { webView?.goBack() }
                            }
            backButton = back
            bar.addView(back)

            val reload =
                    IconButtonView(activity) { canvas, cx, cy, r -> drawReloadIcon(canvas, cx, cy, r) }
                            .apply {
                                layoutParams = FrameLayout.LayoutParams(dp(40), dp(40), Gravity.CENTER)
                                setOnClickListener { webView?.reload() }
                            }
            bar.addView(reload)

            val forward =
                    IconButtonView(activity) { canvas, cx, cy, r ->
                        drawForwardIcon(canvas, cx, cy, r)
                    }
                            .apply {
                                disabled = true
                                layoutParams =
                                        FrameLayout.LayoutParams(dp(40), dp(40), Gravity.CENTER)
                                                .apply { leftMargin = dp(72) }
                                setOnClickListener { webView?.goForward() }
                            }
            forwardButton = forward
            bar.addView(forward)

            return bar
        }

        private fun shareCurrentUrl() {
            val shareUrl = webView?.url ?: url
            val intent =
                    Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, shareUrl)
                    }
            try {
                activity.startActivity(Intent.createChooser(intent, null))
            } catch (e: Exception) {
                Log.w(TAG, "Failed to open share sheet", e)
            }
        }

        fun finish(reason: String) {
            if (!finished.compareAndSet(false, true)) {
                return
            }

            if (activeOverlay === this) {
                activeOverlay = null
            }

            activity.runOnUiThread {
                webView?.stopLoading()
                webView?.destroy()
                overlayView?.let { root.removeView(it) }

                dispatchClosed(activity, reason, id)
            }
        }
    }
}
