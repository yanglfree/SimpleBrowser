package com.youdroid.zhuobrowser.ui

import androidx.compose.ui.graphics.Color

object Tokens {
    val pageBackground = Color(0xFFFAF9F7)
    val surfacePanel = Color(0xFFFFFFFF)
    val surfaceSubtle = Color(0xFFF1EFEA)
    val textPrimary = Color(0xFF1A1A18)
    val textSecondary = Color(0xFF8B877F)
    val border = Color(0xFFE5E2DB)
    val accent = Color(0xFF2E6B5C)
}

fun colorFromHex(hex: String): Color {
    val trimmed = hex.trim().removePrefix("#")
    val value = trimmed.toLongOrNull(16) ?: return textFallback
    val argb = if (trimmed.length <= 6) 0xFF000000L or value else value
    return Color(argb)
}

private val textFallback = Color(0xFF1A1A18)
