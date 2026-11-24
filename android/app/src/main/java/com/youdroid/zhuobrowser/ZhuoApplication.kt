package com.youdroid.zhuobrowser

import android.app.Application
import android.webkit.WebView
import com.youdroid.zhuobrowser.session.TelemetryService

class ZhuoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        TelemetryService.initialize(this)
        if (BuildConfig.DEBUG) {
            WebView.setWebContentsDebuggingEnabled(true)
        }
    }
}
