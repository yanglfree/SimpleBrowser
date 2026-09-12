package com.youdroid.zhuobrowser.session

import android.content.Context
import android.net.Uri
import android.webkit.CookieManager
import android.webkit.MimeTypeMap
import android.webkit.URLUtil
import androidx.core.content.FileProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

enum class DownloadStatus { Downloading, Completed, Failed }

data class DownloadTask(
    val id: String,
    val fileName: String,
    val url: String,
    val status: DownloadStatus,
    val error: String,
    val path: String
)

class DownloadStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("zhuo", Context.MODE_PRIVATE)
    private val job = SupervisorJob()
    private val scope = CoroutineScope(job + Dispatchers.IO)
    private val _tasks = MutableStateFlow(restore())
    val tasks: StateFlow<List<DownloadTask>> = _tasks

    fun start(url: String, userAgent: String, contentDisposition: String, mimeType: String): Boolean {
        if (!url.startsWith("http://") && !url.startsWith("https://")) return false
        val id = UUID.randomUUID().toString()
        val guessed = URLUtil.guessFileName(url, contentDisposition, mimeType)
        val name = sanitizedFileName(guessed)
        val destination = uniqueFile(name)
        val task = DownloadTask(
            id = id,
            fileName = name,
            url = url,
            status = DownloadStatus.Downloading,
            error = "",
            path = destination.absolutePath
        )
        _tasks.update { listOf(task) + it }
        scope.launch {
            try {
                downloadToFile(url, userAgent, destination)
                mutate(id) { it.copy(status = DownloadStatus.Completed, error = "") }
            } catch (error: Exception) {
                destination.delete()
                mutate(id) {
                    it.copy(
                        status = DownloadStatus.Failed,
                        error = error.message?.ifBlank { "失败" } ?: "失败"
                    )
                }
            }
            persist()
        }
        return true
    }

    fun fileUri(task: DownloadTask): Uri? {
        if (task.status != DownloadStatus.Completed || task.path.isEmpty()) return null
        val file = File(task.path)
        if (!file.exists()) return null
        return FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    }

    fun mimeType(task: DownloadTask): String {
        val extension = task.fileName.substringAfterLast('.', "")
        val guessed = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.lowercase())
        return guessed ?: "application/octet-stream"
    }

    fun close() {
        job.cancel()
    }

    private fun mutate(id: String, transform: (DownloadTask) -> DownloadTask) {
        _tasks.update { current ->
            current.map { if (it.id == id) transform(it) else it }
        }
    }

    private fun downloadsDirectory(): File {
        val folder = File(context.filesDir, "Downloads")
        if (!folder.exists()) folder.mkdirs()
        return folder
    }

    private fun sanitizedFileName(name: String): String {
        val cleaned = name.replace("/", "_").replace(":", "_").trim()
        return cleaned.ifEmpty { "download" }
    }

    private fun uniqueFile(name: String): File {
        val directory = downloadsDirectory()
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot + 1) else ""
        var candidate = File(directory, name)
        var index = 1
        while (candidate.exists()) {
            val suffix = if (ext.isEmpty()) "$base ($index)" else "$base ($index).$ext"
            candidate = File(directory, suffix)
            index += 1
        }
        return candidate
    }

    private fun downloadToFile(url: String, userAgent: String, destination: File) {
        var current = url
        repeat(8) {
            val connection = URL(current).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 30_000
            connection.readTimeout = 30_000
            connection.setRequestProperty("User-Agent", userAgent)
            CookieManager.getInstance().getCookie(current)?.let { cookie ->
                connection.setRequestProperty("Cookie", cookie)
            }
            val code = connection.responseCode
            if (code in 300..399) {
                val location = connection.getHeaderField("Location")
                    ?: throw IOException("redirect without location")
                current = URL(URL(current), location).toString()
                connection.disconnect()
                return@repeat
            }
            if (code !in 200..299) {
                connection.disconnect()
                throw IOException("HTTP $code")
            }
            connection.inputStream.use { input ->
                destination.outputStream().use { output -> input.copyTo(output) }
            }
            connection.disconnect()
            return
        }
        throw IOException("too many redirects")
    }

    private fun persist() {
        val stored = _tasks.value.filter { it.status != DownloadStatus.Downloading }
        val array = JSONArray()
        stored.forEach { task ->
            array.put(
                JSONObject()
                    .put("id", task.id)
                    .put("fileName", task.fileName)
                    .put("url", task.url)
                    .put("status", task.status.name)
                    .put("error", task.error)
                    .put("path", task.path)
            )
        }
        prefs.edit().putString(PREFS_KEY, array.toString()).apply()
    }

    private fun restore(): List<DownloadTask> {
        return runCatching {
            val array = JSONArray(prefs.getString(PREFS_KEY, "[]"))
            buildList {
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    var status = runCatching {
                        DownloadStatus.valueOf(obj.optString("status"))
                    }.getOrDefault(DownloadStatus.Failed)
                    var error = obj.optString("error")
                    val path = obj.optString("path")
                    if (status == DownloadStatus.Downloading) {
                        status = DownloadStatus.Failed
                        error = "interrupted"
                    }
                    if (status == DownloadStatus.Completed && (path.isEmpty() || !File(path).exists())) {
                        status = DownloadStatus.Failed
                        error = "missing"
                    }
                    add(
                        DownloadTask(
                            id = obj.getString("id"),
                            fileName = obj.optString("fileName"),
                            url = obj.optString("url"),
                            status = status,
                            error = error,
                            path = path
                        )
                    )
                }
            }
        }.getOrDefault(emptyList())
    }

    companion object {
        private const val PREFS_KEY = "download_tasks_v1"
    }
}
