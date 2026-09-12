package com.youdroid.zhuobrowser.session

enum class ReaderPaper(val raw: Int) {
    White(0),
    Sepia(1),
    Night(2);

    companion object {
        fun fromRaw(raw: Int): ReaderPaper = entries.firstOrNull { it.raw == raw } ?: Sepia
    }
}

data class ReaderTheme(
    val background: String,
    val pillBackground: String,
    val pillBorder: String,
    val textPrimary: String,
    val textSecondary: String,
    val border: String,
    val isDark: Boolean,
    val body: String,
    val title: String,
    val accent: String = "#2E6B5C"
) {
    companion object {
        fun theme(paper: ReaderPaper): ReaderTheme = when (paper) {
            ReaderPaper.White -> ReaderTheme(
                background = "#FFFFFF",
                pillBackground = "#F4F3EF",
                pillBorder = "#E6E3DC",
                textPrimary = "#1A1A18",
                textSecondary = "#7A7870",
                border = "#EAE7E1",
                isDark = false,
                body = "#3A3934",
                title = "#1A1A18"
            )
            ReaderPaper.Night -> ReaderTheme(
                background = "#26251F",
                pillBackground = "#33322B",
                pillBorder = "#424037",
                textPrimary = "#F5F3EE",
                textSecondary = "#8E8B82",
                border = "#383630",
                isDark = true,
                body = "#C9C6BE",
                title = "#F5F3EE"
            )
            ReaderPaper.Sepia -> ReaderTheme(
                background = "#F1EFEA",
                pillBackground = "#E6E3DC",
                pillBorder = "#D8D4CA",
                textPrimary = "#1A1A18",
                textSecondary = "#7A7870",
                border = "#E2DDD5",
                isDark = false,
                body = "#3A3934",
                title = "#1A1A18"
            )
        }
    }
}

data class ReaderSettings(
    val fontSize: Int = 17,
    val lineHeightIndex: Int = 1,
    val paper: ReaderPaper = ReaderPaper.Sepia
) {
    val canShrink: Boolean
        get() = fontSize - FONT_STEP >= FONT_MIN
    val canGrow: Boolean
        get() = fontSize + FONT_STEP <= FONT_MAX
    val lineHeightCss: String
        get() {
            val value = LINE_HEIGHTS[lineHeightIndex.coerceIn(0, LINE_HEIGHTS.lastIndex)] / 100.0
            return String.format(java.util.Locale.US, "%.2f", value)
        }

    fun shrink(): ReaderSettings = if (canShrink) copy(fontSize = fontSize - FONT_STEP) else this
    fun grow(): ReaderSettings = if (canGrow) copy(fontSize = fontSize + FONT_STEP) else this
    fun cycleLineHeight(): ReaderSettings =
        copy(lineHeightIndex = (lineHeightIndex + 1) % LINE_HEIGHTS.size)

    companion object {
        const val FONT_MIN = 15
        const val FONT_MAX = 21
        const val FONT_STEP = 2
        val LINE_HEIGHTS: List<Int> = listOf(170, 205, 240)
    }
}
