package com.youdroid.zhuobrowser.policy

enum class SearchEngine(val raw: Int) {
    Bing(0), Baidu(1), Google(2), DuckDuckGo(3);

    val label: String
        get() = when (this) {
            Bing -> "Bing"
            Baidu -> "百度"
            Google -> "Google"
            DuckDuckGo -> "DuckDuckGo"
        }

    companion object {
        fun fromRaw(raw: Int): SearchEngine = entries.firstOrNull { it.raw == raw } ?: Bing
    }
}

object UrlPolicy {
    const val HOME_URL = "browser://home"

    private val searchEndpoints = listOf(
        "https://www.bing.com/search?q=",
        "https://m.baidu.com/s?word=",
        "https://www.google.com/search?q=",
        "https://duckduckgo.com/?q="
    )

    fun isHomeUrl(url: String): Boolean = url.isEmpty() || url == HOME_URL

    fun looksLikeUrl(input: String): Boolean {
        val value = input.trim()
        if (value.isEmpty() || Regex("\\s").containsMatchIn(value)) return false
        if (hasExplicitScheme(value)) return true
        return isAddressHost(addressHost(value))
    }

    fun normalizeAddress(input: String, engine: SearchEngine = SearchEngine.Bing): String {
        val value = input.trim()
        if (value.isEmpty()) return HOME_URL
        val normalized = normalizeUrlInput(value)
        return normalized.ifEmpty { searchUrl(value, engine) }
    }

    fun desktopUrl(url: String): String {
        val match = Regex("^(https?)://([^/?#]+)(.*)$", RegexOption.IGNORE_CASE).find(url) ?: return url
        val host = match.groupValues[2].substringBefore(':').lowercase()
        if (host != "m.weibo.cn") return url
        return "https://weibo.com${match.groupValues[3]}"
    }

    fun searchUrl(query: String, engine: SearchEngine): String {
        val value = query.trim()
        val parts = value.split(Regex("\\s+"))
        var resolved = engine
        var terms = value
        if (parts.size > 1) {
            when (parts[0].lowercase()) {
                "g" -> { resolved = SearchEngine.Google; terms = value.substring(parts[0].length).trim() }
                "b" -> { resolved = SearchEngine.Baidu; terms = value.substring(parts[0].length).trim() }
                "ddg" -> { resolved = SearchEngine.DuckDuckGo; terms = value.substring(parts[0].length).trim() }
                "bing" -> { resolved = SearchEngine.Bing; terms = value.substring(parts[0].length).trim() }
            }
        }
        val index = resolved.raw.coerceIn(0, searchEndpoints.lastIndex)
        return searchEndpoints[index] + encodeURIComponent(terms)
    }

    fun displayHost(url: String): String {
        if (isHomeUrl(url)) return ""
        val host = hostOf(url) ?: url
        val withoutPort = host.substringBefore(':')
        return when {
            withoutPort.startsWith("www.") -> withoutPort.substring(4)
            withoutPort.startsWith("m.") -> withoutPort.substring(2)
            else -> withoutPort
        }
    }

    fun rawHost(url: String): String {
        val host = hostOf(url) ?: return ""
        return host.substringBefore(':').lowercase()
    }

    private fun normalizeUrlInput(input: String): String {
        val value = input.trim()
        if (!looksLikeUrl(value)) return ""
        if (hasExplicitScheme(value)) return value
        val host = addressHost(value).lowercase()
        val localOrIp = host == "localhost" || host.startsWith("[") || validIpv4(host)
        return "${if (localOrIp) "http" else "https"}://$value"
    }

    private fun hasExplicitScheme(value: String): Boolean =
        Regex("^[a-z][a-z0-9+.-]*://", RegexOption.IGNORE_CASE).containsMatchIn(value)

    private fun validPort(value: String): Boolean {
        val port = value.toIntOrNull() ?: return false
        return port in 1..65535
    }

    private fun validIpv4(host: String): Boolean {
        val parts = host.split('.')
        if (parts.size != 4) return false
        return parts.all { part ->
            part.matches(Regex("^\\d{1,3}$")) && part.toInt() in 0..255
        }
    }

    private fun validDomain(host: String): Boolean {
        if (host.length > 253 || host.startsWith('.') || host.endsWith('.')) return false
        val labels = host.split('.')
        if (labels.size < 2) return false
        return labels.all { label ->
            label.isNotEmpty() && label.length <= 63 && !label.startsWith('-') && !label.endsWith('-') &&
                label.matches(Regex("^[^\\s/:?#.]+$"))
        }
    }

    private fun addressHost(value: String): String {
        val boundary = Regex("[/?#]").find(value)?.range?.first ?: -1
        val authority = if (boundary < 0) value else value.substring(0, boundary)
        if (authority.startsWith('[')) {
            val close = authority.indexOf(']')
            if (close <= 1) return ""
            val host = authority.substring(0, close + 1)
            val suffix = authority.substring(close + 1)
            return if (suffix.isEmpty() || (suffix.startsWith(':') && validPort(suffix.substring(1)))) host else ""
        }
        val first = authority.indexOf(':')
        val last = authority.lastIndexOf(':')
        if (first >= 0) {
            if (first != last || !validPort(authority.substring(last + 1))) return ""
            return authority.substring(0, last)
        }
        return authority
    }

    private fun isAddressHost(host: String): Boolean {
        if (host.lowercase() == "localhost") return true
        if (host.startsWith('[') && host.endsWith(']')) return host.substring(1, host.length - 1).contains(':')
        val numericDotted = host.matches(Regex("^\\d+(\\.\\d+){3}$"))
        return if (numericDotted) validIpv4(host) else validDomain(host)
    }

    private fun hostOf(url: String): String? {
        val match = Regex("^[a-z][a-z0-9+.-]*://([^/?#]+)", RegexOption.IGNORE_CASE).find(url) ?: return null
        return match.groupValues.getOrNull(1)
    }

    private fun encodeURIComponent(value: String): String {
        return java.net.URLEncoder.encode(value, Charsets.UTF_8.name()).replace("+", "%20")
    }
}
