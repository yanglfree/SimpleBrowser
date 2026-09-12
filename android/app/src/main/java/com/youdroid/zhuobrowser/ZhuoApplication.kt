package com.youdroid.zhuobrowser

import android.app.Application
import android.webkit.WebView

class ZhuoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            WebView.setWebContentsDebuggingEnabled(true)
        }
    }
}
