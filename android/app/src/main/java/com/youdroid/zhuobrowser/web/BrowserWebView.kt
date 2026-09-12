package com.youdroid.zhuobrowser.web

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.youdroid.zhuobrowser.policy.UrlPolicy
import com.youdroid.zhuobrowser.session.BrowserSession
import com.youdroid.zhuobrowser.session.BrowserTab
import java.io.ByteArrayInputStream

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun BrowserWebView(
    tab: BrowserTab,
    session: BrowserSession,
    modifier: Modifier = Modifier
) {
    val webView = remember(tab.id) {
        createWebView(session, tab)
    }
    DisposableEffect(tab.id) {
        session.attachWebView(tab.id, webView)
        onDispose { session.detachWebView(tab.id, webView) }
    }
    DisposableEffect(tab.id, tab.url) {
        if (!UrlPolicy.isHomeUrl(tab.url) && webView.url != tab.url) {
            webView.loadUrl(tab.url)
        }
        onDispose { }
    }
    AndroidView(factory = { webView }, modifier = modifier)
}

@SuppressLint("SetJavaScriptEnabled")
private fun createWebView(session: BrowserSession, tab: BrowserTab): WebView {
    val context = session.getApplication<android.app.Application>()
    val assets = context.assets
    val webView = WebView(context)
    webView.settings.javaScriptEnabled = true
    webView.settings.domStorageEnabled = !tab.isPrivate
    webView.settings.cacheMode = if (tab.isPrivate) WebSettings.LOAD_NO_CACHE else WebSettings.LOAD_DEFAULT
    webView.settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
    WebKernel.applyUserAgent(webView, tab.isDesktop)
    injectDocumentStartScripts(webView, assets)
    webView.setFindListener { active, total, done ->
        if (done) session.onFindResult(active, total)
    }
    webView.setDownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
        session.beginDownload(url, userAgent.orEmpty(), contentDisposition.orEmpty(), mimeType.orEmpty())
    }
    webView.webViewClient = object : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val url = request.url.toString()
            if (UrlPolicy.isHomeUrl(url)) {
                session.updateTab(tab.id, url = UrlPolicy.HOME_URL, loading = false, isReader = false)
                return true
            }
            if (request.isForMainFrame && request.hasGesture()) {
                session.updateTab(tab.id, isReader = false)
            }
            return false
        }

        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
            val pageUrl = session.state.value.tabs.firstOrNull { it.id == tab.id }?.url ?: tab.url
            if (!session.adsBlockEnabled(pageUrl)) return null
            if (session.blocker.shouldBlock(request.url.toString())) {
                return WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(ByteArray(0)))
            }
            return null
        }

        override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
            if (url != null && !UrlPolicy.isHomeUrl(url)) {
                session.updateTab(tab.id, url = url, loading = true)
            }
        }

        override fun onPageFinished(view: WebView, url: String?) {
            if (url == null || UrlPolicy.isHomeUrl(url)) return
            if (url != view.url) return
            session.updateTab(tab.id, title = view.title, url = url, loading = false)
            session.recordVisit(tab.id)
            injectDocumentEndScripts(view, assets)
            val current = session.state.value.tabs.firstOrNull { it.id == tab.id } ?: return
            if (current.isDesktop) {
                WebKernel.loadScript(assets, "desktop-viewport.js")?.let { script ->
                    view.evaluateJavascript(script, null)
                }
            }
            if (current.isReader) {
                view.evaluateJavascript(ReaderScripts.apply(assets, session.state.value.readerSettings)) { raw ->
                    if (!ReaderScripts.isReaderStatus(raw)) {
                        session.updateTab(tab.id, isReader = false)
                    }
                }
            }
        }
    }
    webView.webChromeClient = object : WebChromeClient() {
        override fun onReceivedTitle(view: WebView?, title: String?) {
            if (!title.isNullOrEmpty()) session.updateTab(tab.id, title = title)
        }
    }
    if (!UrlPolicy.isHomeUrl(tab.url)) {
        webView.loadUrl(tab.url)
    }
    return webView
}

private fun injectDocumentStartScripts(webView: WebView, assets: android.content.res.AssetManager) {
    if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) return
    for (name in WebKernel.documentStartFiles) {
        val script = WebKernel.loadScript(assets, name) ?: continue
        WebViewCompat.addDocumentStartJavaScript(webView, script, setOf("*"))
    }
}

private fun injectDocumentEndScripts(webView: WebView, assets: android.content.res.AssetManager) {
    for (name in WebKernel.documentEndFiles) {
        val script = WebKernel.loadScript(assets, name) ?: continue
        webView.evaluateJavascript(script, null)
    }
}
