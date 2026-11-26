package com.youdroid.zhuobrowser

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.youdroid.zhuobrowser.session.BrowserSession
import com.youdroid.zhuobrowser.session.TelemetryService
import com.youdroid.zhuobrowser.ui.BrowserScreen
import com.youdroid.zhuobrowser.ui.Tokens

class MainActivity : ComponentActivity() {
    private val session: BrowserSession by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingIntent(intent)
        enableEdgeToEdge()
        setContent {
            Surface(modifier = Modifier.fillMaxSize().systemBarsPadding(), color = Tokens.pageBackground) {
                BrowserScreen(session)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        val uriString = intent?.dataString ?: return
        if (uriString.startsWith("zhuobrowser-auth://oauth/callback")) {
            session.handleOAuthCallbackUri(uriString)
        }
    }

    override fun onStart() {
        super.onStart()
        TelemetryService.handleAppForegrounded(session.state.value.activeTab?.isPrivate == true)
    }

    override fun onStop() {
        TelemetryService.handleAppBackgrounded(session.state.value.activeTab?.isPrivate == true)
        super.onStop()
    }
}
