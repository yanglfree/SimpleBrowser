package com.youdroid.zhuobrowser.web

import android.content.res.AssetManager
import android.net.Uri
import org.json.JSONArray

class NetworkBlocker {
    @Volatile
    private var byHost: Map<String, List<String>> = emptyMap()

    fun load(assets: AssetManager) {
        val text = assets.open("rules/android-network.json").bufferedReader().use { it.readText() }
        val array = JSONArray(text)
        val map = HashMap<String, MutableList<String>>()
        for (index in 0 until array.length()) {
            val item = array.getJSONObject(index)
            val host = item.optString("host")
            if (host.isEmpty()) continue
            val path = item.optString("path")
            map.getOrPut(host) { mutableListOf() }.add(path)
        }
        byHost = map
    }

    fun shouldBlock(url: String): Boolean {
        val uri = Uri.parse(url)
        val host = uri.host?.lowercase() ?: return false
        val path = uri.encodedPath ?: "/"
        var candidate = host
        while (true) {
            val patterns = byHost[candidate]
            if (patterns != null) {
                for (pattern in patterns) {
                    if (pathMatches(path, pattern)) return true
                }
            }
            val dot = candidate.indexOf('.')
            if (dot <= 0) break
            candidate = candidate.substring(dot + 1)
        }
        return false
    }

    private fun pathMatches(path: String, pattern: String): Boolean {
        if (pattern.isEmpty()) return true
        val pieces = pattern.split('*')
        var cursor = 0
        for ((index, piece) in pieces.withIndex()) {
            if (piece.isEmpty()) continue
            val found = path.indexOf(piece, cursor)
            if (found < 0) return false
            if (index == 0 && piece.startsWith('/') && found != 0 && !path.startsWith(piece)) {
                // first literal may appear anywhere if the EasyList path is not rooted
            }
            cursor = found + piece.length
        }
        return true
    }
}
