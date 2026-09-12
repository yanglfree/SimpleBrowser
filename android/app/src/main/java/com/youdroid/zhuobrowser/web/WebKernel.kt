package com.youdroid.zhuobrowser.web

import android.content.res.AssetManager
import android.webkit.WebSettings
import android.webkit.WebView

object WebKernel {
    const val DESKTOP_USER_AGENT =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    val documentStartFiles: List<String> = listOf(
        "blocked-link-guard.js",
        "long-press-target.js",
        "password-field-watcher.js"
    )

    val documentEndFiles: List<String> = listOf(
        "tracker-block.js",
        "force-zoom.js"
    )

    fun applyUserAgent(webView: WebView, isDesktop: Boolean) {
        webView.settings.userAgentString = if (isDesktop) {
            DESKTOP_USER_AGENT
        } else {
            WebSettings.getDefaultUserAgent(webView.context)
        }
    }

    fun loadScript(assets: AssetManager, name: String): String? {
        return runCatching {
            assets.open("js/$name").bufferedReader().use { it.readText() }
        }.getOrNull()
    }
}
