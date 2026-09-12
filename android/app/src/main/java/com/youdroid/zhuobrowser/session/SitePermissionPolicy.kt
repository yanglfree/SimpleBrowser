package com.youdroid.zhuobrowser.session

enum class SitePermissionDecision(val raw: Int) {
    Prompt(0),
    Allow(1),
    Deny(2);

    companion object {
        fun fromRaw(raw: Int): SitePermissionDecision =
            entries.firstOrNull { it.raw == raw } ?: Prompt
    }
}

enum class SitePermissionKind {
    Camera, Microphone, Location;

    val label: String
        get() = when (this) {
            Camera -> "相机"
            Microphone -> "麦克风"
            Location -> "位置"
        }

    val storageKey: String
        get() = when (this) {
            Camera -> "camera"
            Microphone -> "microphone"
            Location -> "location"
        }
}

data class SitePermission(
    val origin: String,
    val camera: SitePermissionDecision = SitePermissionDecision.Prompt,
    val microphone: SitePermissionDecision = SitePermissionDecision.Prompt,
    val location: SitePermissionDecision = SitePermissionDecision.Prompt
) {
    fun decision(kind: SitePermissionKind): SitePermissionDecision = when (kind) {
        SitePermissionKind.Camera -> camera
        SitePermissionKind.Microphone -> microphone
        SitePermissionKind.Location -> location
    }

    fun with(kind: SitePermissionKind, decision: SitePermissionDecision): SitePermission = when (kind) {
        SitePermissionKind.Camera -> copy(camera = decision)
        SitePermissionKind.Microphone -> copy(microphone = decision)
        SitePermissionKind.Location -> copy(location = decision)
    }

    companion object {
        fun empty(origin: String): SitePermission = SitePermission(origin = origin)
    }
}

data class PermissionPrompt(
    val origin: String,
    val kinds: List<SitePermissionKind>,
    val persist: Boolean
)

object SitePermissionPolicy {
    fun decision(stored: SitePermission?, kinds: List<SitePermissionKind>): SitePermissionDecision {
        if (stored == null) return SitePermissionDecision.Prompt
        var result = SitePermissionDecision.Allow
        for (kind in kinds) {
            when (stored.decision(kind)) {
                SitePermissionDecision.Deny -> return SitePermissionDecision.Deny
                SitePermissionDecision.Prompt -> result = SitePermissionDecision.Prompt
                SitePermissionDecision.Allow -> Unit
            }
        }
        return result
    }

    fun apply(
        list: List<SitePermission>,
        origin: String,
        kinds: List<SitePermissionKind>,
        decision: SitePermissionDecision
    ): List<SitePermission> {
        val next = list.toMutableList()
        val index = next.indexOfFirst { it.origin == origin }
        var stored = if (index >= 0) next[index] else SitePermission.empty(origin)
        for (kind in kinds) {
            stored = stored.with(kind, decision)
        }
        if (index >= 0) next[index] = stored else next.add(stored)
        return next
    }

    fun remove(list: List<SitePermission>, origin: String): List<SitePermission> =
        list.filter { it.origin != origin }

    fun origin(scheme: String, host: String, port: Int): String {
        if (scheme.isEmpty() || host.isEmpty()) return ""
        if (port <= 0 || port == 80 || port == 443) return "$scheme://$host"
        return "$scheme://$host:$port"
    }

    fun originFromUrl(url: String): String {
        val match = Regex("^([a-z][a-z0-9+.-]*)://([^/?#]+)", RegexOption.IGNORE_CASE).find(url)
            ?: return ""
        val scheme = match.groupValues[1].lowercase()
        val authority = match.groupValues[2]
        val host = authority.substringBefore(':').lowercase()
        val port = authority.substringAfter(':', "").toIntOrNull() ?: 0
        return origin(scheme, host, port)
    }

    fun summary(entry: SitePermission): String {
        return SitePermissionKind.entries.mapNotNull { kind ->
            when (entry.decision(kind)) {
                SitePermissionDecision.Allow -> "${kind.label}允许"
                SitePermissionDecision.Deny -> "${kind.label}拒绝"
                SitePermissionDecision.Prompt -> null
            }
        }.joinToString(" · ")
    }
}
