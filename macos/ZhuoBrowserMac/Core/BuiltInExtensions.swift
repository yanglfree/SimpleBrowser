import Foundation

/// Seeds and manages the 5 built-in Chrome-style extensions bundled with ZhuoBrowser Mac.
public enum BuiltInExtensions {
    public struct Template {
        public let id: String
        public let sfSymbol: String
        public let accentColorHex: String
        public let defaultPinned: Bool
        public let defaultEnabled: Bool
        public let manifest: ExtensionManifest
        public let files: [String: String]
    }

    public static let allTemplates: [Template] = [
        darkModeProTemplate,
        pageTranslatorTemplate,
        mediaSnifferTemplate,
        superCopyDevToolsTemplate,
        userScriptStudioTemplate
    ]

    /// Materializes all built-in extension files onto disk under `baseDirectory/BuiltIn/<id>/`
    /// and returns `InstalledExtension` models merged with any persisted user state.
    public static func materializeAll(in baseDirectory: URL) -> [InstalledExtension] {
        let fm = FileManager.default
        let builtInRoot = baseDirectory.appendingPathComponent("BuiltIn", isDirectory: true)
        try? fm.createDirectory(at: builtInRoot, withIntermediateDirectories: true)

        var results: [InstalledExtension] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        for tpl in allTemplates {
            let extDir = builtInRoot.appendingPathComponent(tpl.id, isDirectory: true)
            try? fm.createDirectory(at: extDir, withIntermediateDirectories: true)

            if let manifestData = try? encoder.encode(tpl.manifest) {
                let manifestURL = extDir.appendingPathComponent("manifest.json")
                try? manifestData.write(to: manifestURL, options: .atomic)
            }

            for (relativePath, content) in tpl.files {
                let fileURL = extDir.appendingPathComponent(relativePath)
                let parentDir = fileURL.deletingLastPathComponent()
                try? fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                try? content.write(to: fileURL, atomically: true, encoding: .utf8)
            }

            let item = InstalledExtension(
                id: tpl.id,
                manifest: tpl.manifest,
                sourceKind: .builtIn,
                directoryPath: extDir.path,
                isEnabled: tpl.defaultEnabled,
                isPinnedToToolbar: tpl.defaultPinned,
                allowInPrivateBrowsing: true,
                hostAccessMode: .onAllSites,
                sfSymbolFallback: tpl.sfSymbol,
                accentColorHex: tpl.accentColorHex
            )
            results.append(item)
        }
        return results
    }

    // MARK: - 1. Dark Mode Pro (智能暗黑护眼)

    public static let darkModeProID = "ext-dark-reader"

    private static var darkModeProTemplate: Template {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "智能暗黑护眼 (Dark Mode Pro)",
            shortName: "暗黑护眼",
            version: "1.2.0",
            description: "为任意网页提供智能反色暗黑模式与护眼色温调节，自动保护图片与视频原色，支持按站点独立记忆。",
            author: "ZhuoBrowser Team",
            permissions: ["storage", "tabs", "activeTab", "scripting"],
            hostPermissions: ["<all_urls>"],
            action: ExtensionActionSpec(
                defaultTitle: "智能暗黑护眼 (Dark Mode Pro)",
                defaultPopup: "popup.html"
            ),
            contentScripts: [
                ExtensionContentScriptSpec(
                    matches: ["<all_urls>"],
                    js: ["content.js"],
                    runAt: .documentStart,
                    allFrames: false
                )
            ]
        )

        let contentJS = """
        (function() {
            const STYLE_ID = "zhuo-ext-dark-reader-style";
            let currentConfig = {
                globalEnabled: false,
                brightness: 100,
                contrast: 95,
                sepia: 10,
                siteOverrides: {}
            };

            function isActiveForCurrentHost() {
                const host = (location.hostname || "").toLowerCase();
                if (host && Object.prototype.hasOwnProperty.call(currentConfig.siteOverrides || {}, host)) {
                    return Boolean(currentConfig.siteOverrides[host]);
                }
                return Boolean(currentConfig.globalEnabled);
            }

            function applyDarkTheme() {
                const active = isActiveForCurrentHost();
                let styleEl = document.getElementById(STYLE_ID);
                if (!active) {
                    if (styleEl) styleEl.remove();
                    chrome.action.setBadgeText({ text: "" });
                    return;
                }
                const b = Number(currentConfig.brightness) || 100;
                const c = Number(currentConfig.contrast) || 95;
                const s = Number(currentConfig.sepia) || 10;
                const css = `
                    html {
                        filter: invert(0.92) hue-rotate(180deg) brightness(${b}%) contrast(${c}%) sepia(${s}%) !important;
                        background-color: #111318 !important;
                        color-scheme: dark !important;
                    }
                    img, video, iframe, canvas, svg, picture, [style*="background-image"] {
                        filter: invert(1) hue-rotate(180deg) !important;
                    }
                `;
                if (!styleEl) {
                    styleEl = document.createElement("style");
                    styleEl.id = STYLE_ID;
                    styleEl.setAttribute("data-zhuo-extension", chrome.runtime.id);
                    (document.head || document.documentElement).appendChild(styleEl);
                }
                styleEl.textContent = css;
                chrome.action.setBadgeBackgroundColor({ color: "#6366F1" });
                chrome.action.setBadgeText({ text: "ON" });
            }

            chrome.storage.local.get(["darkConfig"], function(res) {
                if (res && res.darkConfig) {
                    Object.assign(currentConfig, res.darkConfig);
                }
                applyDarkTheme();
            });

            chrome.storage.onChanged.addListener(function(changes) {
                if (changes.darkConfig && changes.darkConfig.newValue) {
                    Object.assign(currentConfig, changes.darkConfig.newValue);
                    applyDarkTheme();
                }
            });

            chrome.runtime.onMessage.addListener(function(msg, sender, sendResponse) {
                if (!msg) return;
                if (msg.type === "DARK_GET_STATUS") {
                    sendResponse({
                        host: (location.hostname || "").toLowerCase(),
                        active: isActiveForCurrentHost(),
                        config: currentConfig
                    });
                } else if (msg.type === "DARK_APPLY_CONFIG") {
                    if (msg.config) {
                        Object.assign(currentConfig, msg.config);
                        chrome.storage.local.set({ darkConfig: currentConfig });
                        applyDarkTheme();
                    }
                    sendResponse({ ok: true, active: isActiveForCurrentHost() });
                }
            });
        })();
        """

        let popupHTML = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <title>智能暗黑护眼</title>
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
            body { width: 300px; padding: 14px; background: #18181B; color: #F4F4F5; user-select: none; }
            .header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; padding-bottom: 10px; border-bottom: 1px solid #27272A; }
            .title { font-size: 13.5px; font-weight: 700; display: flex; align-items: center; gap: 6px; }
            .badge { font-size: 10px; padding: 2px 6px; border-radius: 99px; background: #6366F1; color: #fff; font-weight: 600; }
            .card { background: #27272A; border-radius: 8px; padding: 10px 12px; margin-bottom: 10px; }
            .row { display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; }
            .row:last-child { margin-bottom: 0; }
            .label { font-size: 12px; color: #E4E4E7; font-weight: 500; }
            .sub { font-size: 10.5px; color: #A1A1AA; }
            .slider-row { margin-bottom: 10px; }
            .slider-row:last-child { margin-bottom: 0; }
            .slider-head { display: flex; justify-content: space-between; font-size: 11px; color: #D4D4D8; margin-bottom: 4px; }
            input[type="range"] { width: 100%; accent-color: #6366F1; cursor: pointer; }
            .btn-row { display: flex; gap: 8px; margin-top: 8px; }
            button { flex: 1; padding: 6px 10px; border-radius: 6px; border: none; font-size: 11.5px; font-weight: 600; cursor: pointer; transition: opacity 0.15s; }
            button:hover { opacity: 0.9; }
            .btn-primary { background: #6366F1; color: white; }
            .btn-secondary { background: #3F3F46; color: #E4E4E7; }
            .switch { position: relative; display: inline-block; width: 36px; height: 20px; }
            .switch input { opacity: 0; width: 0; height: 0; }
            .slider { position: absolute; cursor: pointer; inset: 0; background-color: #52525B; transition: .2s; border-radius: 20px; }
            .slider:before { position: absolute; content: ""; height: 14px; width: 14px; left: 3px; bottom: 3px; background-color: white; transition: .2s; border-radius: 50%; }
            input:checked + .slider { background-color: #6366F1; }
            input:checked + .slider:before { transform: translateX(16px); }
        </style>
        </head>
        <body>
            <div class="header">
                <div class="title">🌙 智能暗黑护眼</div>
                <span id="statusBadge" class="badge">待命</span>
            </div>
            <div class="card">
                <div class="row">
                    <div>
                        <div class="label">当前站点开启暗黑</div>
                        <div id="hostLabel" class="sub">检测当前标签页...</div>
                    </div>
                    <label class="switch">
                        <input type="checkbox" id="siteToggle">
                        <span class="slider"></span>
                    </label>
                </div>
                <div class="row" style="margin-top: 8px; padding-top: 8px; border-top: 1px solid #3F3F46;">
                    <div>
                        <div class="label">全局默认开启</div>
                        <div class="sub">所有新打开网页自动应用</div>
                    </div>
                    <label class="switch">
                        <input type="checkbox" id="globalToggle">
                        <span class="slider"></span>
                    </label>
                </div>
            </div>
            <div class="card">
                <div class="slider-row">
                    <div class="slider-head"><span>亮度 (Brightness)</span><span id="bVal">100%</span></div>
                    <input type="range" id="brightness" min="65" max="125" value="100">
                </div>
                <div class="slider-row">
                    <div class="slider-head"><span>对比度 (Contrast)</span><span id="cVal">95%</span></div>
                    <input type="range" id="contrast" min="70" max="125" value="95">
                </div>
                <div class="slider-row">
                    <div class="slider-head"><span>护眼暖色温 (Sepia)</span><span id="sVal">10%</span></div>
                    <input type="range" id="sepia" min="0" max="60" value="10">
                </div>
            </div>
            <div class="btn-row">
                <button id="resetBtn" class="btn-secondary">恢复默认参数</button>
            </div>
            <script src="popup.js"></script>
        </body>
        </html>
        """

        let popupJS = """
        (function() {
            const siteToggle = document.getElementById("siteToggle");
            const globalToggle = document.getElementById("globalToggle");
            const hostLabel = document.getElementById("hostLabel");
            const statusBadge = document.getElementById("statusBadge");
            const brightness = document.getElementById("brightness");
            const contrast = document.getElementById("contrast");
            const sepia = document.getElementById("sepia");
            const bVal = document.getElementById("bVal");
            const cVal = document.getElementById("cVal");
            const sVal = document.getElementById("sVal");
            const resetBtn = document.getElementById("resetBtn");

            let currentHost = "";
            let activeTabId = null;
            let config = {
                globalEnabled: false,
                brightness: 100,
                contrast: 95,
                sepia: 10,
                siteOverrides: {}
            };

            function renderUI() {
                const isSiteActive = currentHost && Object.prototype.hasOwnProperty.call(config.siteOverrides, currentHost)
                    ? Boolean(config.siteOverrides[currentHost])
                    : Boolean(config.globalEnabled);
                siteToggle.checked = isSiteActive;
                globalToggle.checked = Boolean(config.globalEnabled);
                brightness.value = config.brightness || 100;
                contrast.value = config.contrast || 95;
                sepia.value = config.sepia || 10;
                bVal.textContent = brightness.value + "%";
                cVal.textContent = contrast.value + "%";
                sVal.textContent = sepia.value + "%";
                statusBadge.textContent = isSiteActive ? "已启用" : "已关闭";
                statusBadge.style.background = isSiteActive ? "#6366F1" : "#52525B";
            }

            function pushConfig() {
                chrome.storage.local.set({ darkConfig: config });
                if (activeTabId !== null) {
                    chrome.tabs.sendMessage(activeTabId, { type: "DARK_APPLY_CONFIG", config: config });
                }
                const isSiteActive = currentHost && Object.prototype.hasOwnProperty.call(config.siteOverrides, currentHost)
                    ? Boolean(config.siteOverrides[currentHost])
                    : Boolean(config.globalEnabled);
                chrome.action.setBadgeText({ text: isSiteActive ? "ON" : "" });
                renderUI();
            }

            chrome.storage.local.get(["darkConfig"], function(res) {
                if (res && res.darkConfig) {
                    Object.assign(config, res.darkConfig);
                    config.siteOverrides = config.siteOverrides || {};
                }
                chrome.tabs.query({ active: true, currentWindow: true }, function(tabs) {
                    const tab = tabs && tabs[0];
                    if (tab && tab.url) {
                        activeTabId = tab.id;
                        try {
                            const u = new URL(tab.url);
                            currentHost = (u.hostname || "").toLowerCase();
                            hostLabel.textContent = currentHost || "当前标签页";
                        } catch (e) {
                            hostLabel.textContent = "内置页面";
                        }
                    } else {
                        hostLabel.textContent = "新标签页";
                    }
                    renderUI();
                });
            });

            siteToggle.addEventListener("change", function() {
                if (currentHost) {
                    config.siteOverrides[currentHost] = siteToggle.checked;
                } else {
                    config.globalEnabled = siteToggle.checked;
                }
                pushConfig();
            });

            globalToggle.addEventListener("change", function() {
                config.globalEnabled = globalToggle.checked;
                if (currentHost) {
                    delete config.siteOverrides[currentHost];
                }
                pushConfig();
            });

            [brightness, contrast, sepia].forEach(function(input) {
                input.addEventListener("input", function() {
                    config.brightness = Number(brightness.value);
                    config.contrast = Number(contrast.value);
                    config.sepia = Number(sepia.value);
                    pushConfig();
                });
            });

            resetBtn.addEventListener("click", function() {
                config.brightness = 100;
                config.contrast = 95;
                config.sepia = 10;
                pushConfig();
            });
        })();
        """

        return Template(
            id: darkModeProID,
            sfSymbol: "moon.stars.fill",
            accentColorHex: "#6366F1",
            defaultPinned: true,
            defaultEnabled: true,
            manifest: manifest,
            files: [
                "content.js": contentJS,
                "popup.html": popupHTML,
                "popup.js": popupJS
            ]
        )
    }

    // MARK: - 2. Immersive Page Translator (沉浸双语对照翻译)

    public static let pageTranslatorID = "ext-page-translator"

    private static var pageTranslatorTemplate: Template {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "沉浸式双语对照翻译 (Immersive Translator)",
            shortName: "沉浸翻译",
            version: "1.1.0",
            description: "一键开启网页段落双语对照翻译与划词速查，保持原网页排版结构，支持快捷键 Option+T 随时切换。",
            author: "ZhuoBrowser Team",
            permissions: ["storage", "tabs", "activeTab", "scripting", "contextMenus"],
            hostPermissions: ["<all_urls>"],
            action: ExtensionActionSpec(
                defaultTitle: "沉浸式双语对照翻译 (Option+T)",
                defaultPopup: "popup.html"
            ),
            contentScripts: [
                ExtensionContentScriptSpec(
                    matches: ["<all_urls>"],
                    js: ["content.js"],
                    css: ["content.css"],
                    runAt: .documentEnd,
                    allFrames: false
                )
            ]
        )

        let contentCSS = """
        .zhuo-bilingual-block {
            display: block;
            margin-top: 6px !important;
            margin-bottom: 6px !important;
            padding: 6px 10px !important;
            border-left: 3px solid #10B981 !important;
            background: rgba(16, 185, 129, 0.08) !important;
            border-radius: 0 6px 6px 0 !important;
            font-size: 0.95em !important;
            line-height: 1.55 !important;
            color: inherit !important;
        }
        .zhuo-bilingual-block[data-style="underline"] {
            border-left: none !important;
            background: transparent !important;
            padding: 2px 0 !important;
            border-bottom: 1px dashed rgba(16, 185, 129, 0.65) !important;
        }
        .zhuo-bilingual-block[data-style="blur"] {
            filter: blur(4px);
            transition: filter 0.2s ease;
        }
        .zhuo-bilingual-block[data-style="blur"]:hover {
            filter: none;
        }
        #zhuo-selection-tooltip {
            position: fixed;
            z-index: 2147483646;
            max-width: 320px;
            padding: 8px 12px;
            border-radius: 8px;
            background: #18181B;
            color: #F4F4F5;
            font-size: 12.5px;
            line-height: 1.45;
            box-shadow: 0 10px 25px rgba(0,0,0,0.35);
            border: 1px solid rgba(16,185,129,0.4);
            pointer-events: auto;
        }
        """

        let contentJS = """
        (function() {
            let isTranslated = false;
            let settings = {
                targetLang: "zh-CN",
                displayStyle: "quote",
                selectionTranslate: true
            };

            const COMMON_TERMS = {
                "documentation": "技术文档",
                "getting started": "快速上手",
                "introduction": "简介与概览",
                "overview": "总览",
                "search": "搜索",
                "settings": "设置",
                "sign in": "登录",
                "sign up": "注册",
                "download": "下载",
                "features": "核心特性",
                "performance": "性能表现",
                "security": "安全防护",
                "privacy": "隐私保护",
                "browser": "浏览器",
                "extension": "扩展程序",
                "extensions": "扩展程序",
                "memory": "内存",
                "welcome": "欢迎",
                "learn more": "了解更多"
            };

            async function translateText(text, targetLang) {
                const clean = String(text || "").trim();
                if (!clean) return "";
                const lower = clean.toLowerCase();
                if (COMMON_TERMS[lower] && targetLang === "zh-CN") {
                    return COMMON_TERMS[lower];
                }
                try {
                    const url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl="
                        + encodeURIComponent(targetLang || "zh-CN")
                        + "&dt=t&q=" + encodeURIComponent(clean.slice(0, 600));
                    const resp = await fetch(url);
                    if (resp.ok) {
                        const data = await resp.json();
                        if (Array.isArray(data) && Array.isArray(data[0])) {
                            return data[0].map(function(part) { return part[0]; }).join("");
                        }
                    }
                } catch (err) {}
                return "【对照译文】" + clean;
            }

            async function toggleBilingualPage(forceState) {
                const nextState = typeof forceState === "boolean" ? forceState : !isTranslated;
                if (!nextState) {
                    document.querySelectorAll(".zhuo-bilingual-block").forEach(function(el) { el.remove(); });
                    document.querySelectorAll("[data-zhuo-translated]").forEach(function(el) {
                        el.removeAttribute("data-zhuo-translated");
                    });
                    isTranslated = false;
                    chrome.action.setBadgeText({ text: "" });
                    return { active: false, count: 0 };
                }

                isTranslated = true;
                chrome.action.setBadgeBackgroundColor({ color: "#10B981" });
                chrome.action.setBadgeText({ text: "译" });

                const candidates = Array.from(document.querySelectorAll("p, h1, h2, h3, li, blockquote")).filter(function(el) {
                    if (el.getAttribute("data-zhuo-translated") === "1") return false;
                    if (el.closest(".zhuo-bilingual-block")) return false;
                    const txt = (el.innerText || "").trim();
                    return txt.length >= 8 && txt.length <= 800;
                }).slice(0, 36);

                let count = 0;
                for (let i = 0; i < candidates.length; i++) {
                    const node = candidates[i];
                    const rawText = (node.innerText || "").trim();
                    if (!rawText) continue;
                    node.setAttribute("data-zhuo-translated", "1");
                    const block = document.createElement("span");
                    block.className = "zhuo-bilingual-block";
                    block.setAttribute("data-style", settings.displayStyle || "quote");
                    block.textContent = "正在翻译...";
                    node.appendChild(block);
                    count++;
                    translateText(rawText, settings.targetLang).then(function(translated) {
                        block.textContent = translated;
                    });
                }
                return { active: true, count: count };
            }

            // Keyboard shortcut: Option+T (Alt+T)
            window.addEventListener("keydown", function(e) {
                if (e.altKey && (e.key === "t" || e.key === "T" || e.code === "KeyT")) {
                    e.preventDefault();
                    toggleBilingualPage();
                }
            });

            // Selection tooltip
            document.addEventListener("mouseup", function(e) {
                const existing = document.getElementById("zhuo-selection-tooltip");
                if (existing && !existing.contains(e.target)) {
                    existing.remove();
                }
                if (!settings.selectionTranslate) return;
                const sel = window.getSelection();
                const text = sel ? sel.toString().trim() : "";
                if (text.length < 2 || text.length > 240 || !/[A-Za-z]/.test(text)) return;

                const tip = document.createElement("div");
                tip.id = "zhuo-selection-tooltip";
                tip.style.left = Math.min(window.innerWidth - 330, Math.max(12, e.clientX)) + "px";
                tip.style.top = Math.min(window.innerHeight - 90, e.clientY + 14) + "px";
                tip.textContent = "翻译中...";
                document.body.appendChild(tip);

                translateText(text, settings.targetLang).then(function(result) {
                    if (tip.isConnected) {
                        tip.textContent = result;
                    }
                });
            });

            chrome.storage.local.get(["translatorSettings"], function(res) {
                if (res && res.translatorSettings) {
                    Object.assign(settings, res.translatorSettings);
                }
            });

            chrome.runtime.onMessage.addListener(function(msg, sender, sendResponse) {
                if (!msg) return;
                if (msg.type === "TRANSLATOR_TOGGLE") {
                    if (msg.settings) {
                        Object.assign(settings, msg.settings);
                        chrome.storage.local.set({ translatorSettings: settings });
                    }
                    toggleBilingualPage(msg.forceState);
                    sendResponse({ ok: true, active: isTranslated });
                } else if (msg.type === "TRANSLATOR_STATUS") {
                    sendResponse({ active: isTranslated, settings: settings });
                } else if (msg.type === "TRANSLATOR_UPDATE_SETTINGS") {
                    if (msg.settings) {
                        Object.assign(settings, msg.settings);
                        chrome.storage.local.set({ translatorSettings: settings });
                        document.querySelectorAll(".zhuo-bilingual-block").forEach(function(el) {
                            el.setAttribute("data-style", settings.displayStyle || "quote");
                        });
                    }
                    sendResponse({ ok: true });
                }
            });
        })();
        """

        let popupHTML = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <title>沉浸式双语对照翻译</title>
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            body { width: 300px; padding: 14px; background: #18181B; color: #F4F4F5; user-select: none; }
            .header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; padding-bottom: 10px; border-bottom: 1px solid #27272A; }
            .title { font-size: 13.5px; font-weight: 700; }
            .shortcut { font-size: 10.5px; color: #10B981; background: rgba(16,185,129,0.14); padding: 2px 6px; border-radius: 4px; }
            .hero-btn { width: 100%; padding: 10px; border-radius: 8px; border: none; background: #10B981; color: #fff; font-size: 13px; font-weight: 700; cursor: pointer; margin-bottom: 12px; }
            .hero-btn.active { background: #EF4444; }
            .card { background: #27272A; border-radius: 8px; padding: 10px 12px; margin-bottom: 10px; }
            .row { display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px; }
            .row:last-child { margin-bottom: 0; }
            .label { font-size: 12px; color: #E4E4E7; }
            select { background: #3F3F46; color: #fff; border: 1px solid #52525B; border-radius: 6px; padding: 4px 8px; font-size: 11.5px; }
        </style>
        </head>
        <body>
            <div class="header">
                <div class="title">🌐 沉浸式双语翻译</div>
                <span class="shortcut">Option + T</span>
            </div>
            <button id="toggleBtn" class="hero-btn">开启本页双语对照翻译</button>
            <div class="card">
                <div class="row">
                    <span class="label">目标语言</span>
                    <select id="targetLang">
                        <option value="zh-CN">简体中文 (zh-CN)</option>
                        <option value="en">English (en)</option>
                        <option value="ja">日本語 (ja)</option>
                    </select>
                </div>
                <div class="row">
                    <span class="label">对照样式</span>
                    <select id="displayStyle">
                        <option value="quote">翠绿引用块 (默认)</option>
                        <option value="underline">虚线下划线</option>
                        <option value="blur">模糊防剧透 (悬停显示)</option>
                    </select>
                </div>
                <div class="row">
                    <span class="label">选中文字自动划词翻译</span>
                    <input type="checkbox" id="selectionTranslate" checked>
                </div>
            </div>
            <script src="popup.js"></script>
        </body>
        </html>
        """

        let popupJS = """
        (function() {
            const toggleBtn = document.getElementById("toggleBtn");
            const targetLang = document.getElementById("targetLang");
            const displayStyle = document.getElementById("displayStyle");
            const selectionTranslate = document.getElementById("selectionTranslate");

            let activeTabId = null;
            let isTranslated = false;
            let settings = {
                targetLang: "zh-CN",
                displayStyle: "quote",
                selectionTranslate: true
            };

            function updateButton() {
                toggleBtn.textContent = isTranslated ? "关闭本页双语对照 (恢复原文)" : "开启本页双语对照翻译";
                toggleBtn.className = isTranslated ? "hero-btn active" : "hero-btn";
            }

            chrome.storage.local.get(["translatorSettings"], function(res) {
                if (res && res.translatorSettings) {
                    Object.assign(settings, res.translatorSettings);
                }
                targetLang.value = settings.targetLang || "zh-CN";
                displayStyle.value = settings.displayStyle || "quote";
                selectionTranslate.checked = settings.selectionTranslate !== false;
            });

            chrome.tabs.query({ active: true, currentWindow: true }, function(tabs) {
                const tab = tabs && tabs[0];
                if (!tab) return;
                activeTabId = tab.id;
                chrome.tabs.sendMessage(activeTabId, { type: "TRANSLATOR_STATUS" }, function(resp) {
                    if (resp) {
                        isTranslated = Boolean(resp.active);
                        updateButton();
                    }
                });
            });

            toggleBtn.addEventListener("click", function() {
                isTranslated = !isTranslated;
                updateButton();
                if (activeTabId !== null) {
                    chrome.tabs.sendMessage(activeTabId, {
                        type: "TRANSLATOR_TOGGLE",
                        forceState: isTranslated,
                        settings: settings
                    });
                }
            });

            [targetLang, displayStyle, selectionTranslate].forEach(function(el) {
                el.addEventListener("change", function() {
                    settings.targetLang = targetLang.value;
                    settings.displayStyle = displayStyle.value;
                    settings.selectionTranslate = selectionTranslate.checked;
                    chrome.storage.local.set({ translatorSettings: settings });
                    if (activeTabId !== null) {
                        chrome.tabs.sendMessage(activeTabId, {
                            type: "TRANSLATOR_UPDATE_SETTINGS",
                            settings: settings
                        });
                    }
                });
            });
        })();
        """

        return Template(
            id: pageTranslatorID,
            sfSymbol: "character.bubble.fill",
            accentColorHex: "#10B981",
            defaultPinned: true,
            defaultEnabled: true,
            manifest: manifest,
            files: [
                "content.js": contentJS,
                "content.css": contentCSS,
                "popup.html": popupHTML,
                "popup.js": popupJS
            ]
        )
    }

    // MARK: - 3. Media & Image Sniffer (媒体与图片资源嗅探)

    public static let mediaSnifferID = "ext-media-sniffer"

    private static var mediaSnifferTemplate: Template {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "媒体与图片资源嗅探 (Media Sniffer)",
            shortName: "资源嗅探",
            version: "1.1.0",
            description: "自动探测当前网页中的高清图片、SVG 矢量图标、背景图与音视频流，支持按尺寸筛选、一键复制链接或新标签下载。",
            author: "ZhuoBrowser Team",
            permissions: ["storage", "tabs", "activeTab", "scripting", "clipboardWrite"],
            hostPermissions: ["<all_urls>"],
            action: ExtensionActionSpec(
                defaultTitle: "媒体与图片资源嗅探",
                defaultPopup: "popup.html"
            ),
            contentScripts: [
                ExtensionContentScriptSpec(
                    matches: ["<all_urls>"],
                    js: ["content.js"],
                    runAt: .documentIdle,
                    allFrames: false
                )
            ]
        )

        let contentJS = """
        (function() {
            function scanPageMedia() {
                const seen = new Set();
                const items = [];

                function addItem(url, kind, width, height, alt) {
                    if (!url || typeof url !== "string") return;
                    if (url.startsWith("data:image/gif")) return;
                    let resolved = url;
                    try {
                        resolved = new URL(url, location.href).href;
                    } catch (e) {}
                    if (seen.has(resolved)) return;
                    seen.add(resolved);
                    items.push({
                        url: resolved,
                        kind: kind,
                        width: width || 0,
                        height: height || 0,
                        label: alt || resolved.split("/").pop().split("?")[0] || kind
                    });
                }

                document.querySelectorAll("img").forEach(function(img) {
                    const src = img.currentSrc || img.src || img.getAttribute("data-src");
                    addItem(src, "IMG", img.naturalWidth || img.width, img.naturalHeight || img.height, img.alt);
                });

                document.querySelectorAll("video, audio, video source, audio source").forEach(function(media) {
                    const src = media.currentSrc || media.src;
                    addItem(src, "MEDIA", media.videoWidth || 0, media.videoHeight || 0, media.tagName);
                });

                document.querySelectorAll("svg").forEach(function(svg, idx) {
                    const rect = svg.getBoundingClientRect();
                    if (rect.width >= 16 && rect.height >= 16 && items.length < 120) {
                        try {
                            const xml = new XMLSerializer().serializeToString(svg);
                            const dataUrl = "data:image/svg+xml;utf8," + encodeURIComponent(xml);
                            addItem(dataUrl, "SVG", Math.round(rect.width), Math.round(rect.height), "inline-svg-" + (idx + 1) + ".svg");
                        } catch (e) {}
                    }
                });

                if (items.length > 0) {
                    chrome.action.setBadgeBackgroundColor({ color: "#F59E0B" });
                    chrome.action.setBadgeText({ text: String(items.length > 99 ? "99+" : items.length) });
                } else {
                    chrome.action.setBadgeText({ text: "" });
                }
                return items;
            }

            scanPageMedia();

            chrome.runtime.onMessage.addListener(function(msg, sender, sendResponse) {
                if (msg && msg.type === "SNIFFER_SCAN") {
                    sendResponse({ items: scanPageMedia(), pageTitle: document.title });
                }
            });
        })();
        """

        let popupHTML = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <title>媒体与图片资源嗅探</title>
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            body { width: 340px; max-height: 440px; padding: 12px; background: #18181B; color: #F4F4F5; display: flex; flex-direction: column; }
            .header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px; }
            .title { font-size: 13px; font-weight: 700; }
            .header-right { display: flex; align-items: center; gap: 6px; }
            .count { font-size: 11px; color: #F59E0B; font-weight: 600; }
            .refresh-btn { background: #27272A; border: 1px solid #3F3F46; color: #D4D4D8; border-radius: 4px; padding: 2px 6px; font-size: 11px; cursor: pointer; }
            .refresh-btn:hover { background: #3F3F46; color: #FFF; }
            .filters { display: flex; gap: 6px; margin-bottom: 10px; }
            .filter-btn { flex: 1; padding: 4px 6px; font-size: 11px; border-radius: 6px; border: 1px solid #3F3F46; background: #27272A; color: #D4D4D8; cursor: pointer; }
            .filter-btn.active { background: #F59E0B; color: #18181B; border-color: #F59E0B; font-weight: 700; }
            .list { flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 6px; max-height: 330px; }
            .item { display: flex; align-items: center; gap: 8px; padding: 6px 8px; background: #27272A; border-radius: 6px; }
            .thumb { width: 36px; height: 36px; border-radius: 4px; background: #111; object-fit: contain; flex-shrink: 0; }
            .meta { flex: 1; min-width: 0; }
            .name { font-size: 11px; color: #E4E4E7; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
            .dims { font-size: 10px; color: #A1A1AA; }
            .actions { display: flex; gap: 4px; }
            .act-btn { padding: 4px 7px; font-size: 10.5px; border-radius: 4px; border: none; background: #3F3F46; color: #fff; cursor: pointer; }
            .act-btn:hover { background: #52525B; }
            .empty { text-align: center; padding: 28px 10px; font-size: 12px; color: #71717A; }
        </style>
        </head>
        <body>
            <div class="header">
                <span class="title">🖼️ 页面媒体与资源嗅探</span>
                <div class="header-right">
                    <span id="countLabel" class="count">扫描中...</span>
                    <button id="refreshBtn" class="refresh-btn" type="button" title="重新嗅探">刷新</button>
                </div>
            </div>
            <div class="filters">
                <button class="filter-btn active" data-kind="ALL">全部</button>
                <button class="filter-btn" data-kind="IMG">图片</button>
                <button class="filter-btn" data-kind="SVG">SVG</button>
                <button class="filter-btn" data-kind="MEDIA">音视频</button>
            </div>
            <div id="mediaList" class="list"></div>
            <script src="popup.js"></script>
        </body>
        </html>
        """

        let popupJS = """
        (function() {
            const mediaList = document.getElementById("mediaList");
            const countLabel = document.getElementById("countLabel");
            const filterBtns = document.querySelectorAll(".filter-btn");
            let allItems = [];
            let currentFilter = "ALL";

            function renderList() {
                const filtered = allItems.filter(function(item) {
                    return currentFilter === "ALL" || item.kind === currentFilter;
                });
                countLabel.textContent = "共 " + filtered.length + " 项";
                mediaList.innerHTML = "";
                if (filtered.length === 0) {
                    const empty = document.createElement("div");
                    empty.className = "empty";
                    empty.textContent = "当前页面未检测到匹配的媒体资源";
                    mediaList.appendChild(empty);
                    return;
                }
                filtered.slice(0, 60).forEach(function(item) {
                    const row = document.createElement("div");
                    row.className = "item";

                    const thumb = document.createElement("img");
                    thumb.className = "thumb";
                    if (item.kind !== "MEDIA") {
                        thumb.src = item.url;
                    }

                    const meta = document.createElement("div");
                    meta.className = "meta";
                    const name = document.createElement("div");
                    name.className = "name";
                    name.textContent = item.label || item.url;
                    const dims = document.createElement("div");
                    dims.className = "dims";
                    dims.textContent = item.kind + (item.width ? (" · " + item.width + "×" + item.height) : "");
                    meta.appendChild(name);
                    meta.appendChild(dims);

                    const actions = document.createElement("div");
                    actions.className = "actions";
                    const copyBtn = document.createElement("button");
                    copyBtn.className = "act-btn";
                    copyBtn.textContent = "复制";
                    copyBtn.addEventListener("click", function() {
                        window.GM_setClipboard(item.url);
                        copyBtn.textContent = "已复制";
                        setTimeout(function() { copyBtn.textContent = "复制"; }, 1200);
                    });

                    const openBtn = document.createElement("button");
                    openBtn.className = "act-btn";
                    openBtn.textContent = "打开";
                    openBtn.addEventListener("click", function() {
                        chrome.tabs.create({ url: item.url, active: true });
                    });

                    actions.appendChild(copyBtn);
                    actions.appendChild(openBtn);
                    row.appendChild(thumb);
                    row.appendChild(meta);
                    row.appendChild(actions);
                    mediaList.appendChild(row);
                });
            }

            filterBtns.forEach(function(btn) {
                btn.addEventListener("click", function() {
                    filterBtns.forEach(function(b) { b.classList.remove("active"); });
                    btn.classList.add("active");
                    currentFilter = btn.getAttribute("data-kind") || "ALL";
                    renderList();
                });
            });

            function performScan() {
                countLabel.textContent = "扫描中...";
                chrome.tabs.query({ active: true, currentWindow: true }, function(tabs) {
                    const tab = tabs && tabs[0];
                    if (!tab) {
                        renderList();
                        return;
                    }
                    chrome.tabs.sendMessage(tab.id, { type: "SNIFFER_SCAN" }, function(resp) {
                        if (resp && Array.isArray(resp.items)) {
                            allItems = resp.items;
                        }
                        renderList();
                    });
                });
            }

            const refreshBtn = document.getElementById("refreshBtn");
            if (refreshBtn) {
                refreshBtn.addEventListener("click", performScan);
            }

            performScan();
        })();
        """

        return Template(
            id: mediaSnifferID,
            sfSymbol: "photo.stack.fill",
            accentColorHex: "#F59E0B",
            defaultPinned: true,
            defaultEnabled: true,
            manifest: manifest,
            files: [
                "content.js": contentJS,
                "popup.html": popupHTML,
                "popup.js": popupJS
            ]
        )
    }

    // MARK: - 4. Super Copy & JSON DevTools (超级复制与开发者工具箱)

    public static let superCopyDevToolsID = "ext-super-copy-dev"

    private static var superCopyDevToolsTemplate: Template {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "超级复制与 JSON 工具箱 (Super Copy & DevTools)",
            shortName: "超级工具箱",
            version: "1.2.0",
            description: "一键解除网页禁止复制/禁止选中/右键限制，自动美化 JSON 响应树，并提供网页 DOM 与加载性能诊断。",
            author: "ZhuoBrowser Team",
            permissions: ["storage", "tabs", "activeTab", "scripting", "clipboardWrite"],
            hostPermissions: ["<all_urls>"],
            action: ExtensionActionSpec(
                defaultTitle: "超级复制与 JSON 工具箱",
                defaultPopup: "popup.html"
            ),
            contentScripts: [
                ExtensionContentScriptSpec(
                    matches: ["<all_urls>"],
                    js: ["content.js"],
                    runAt: .documentEnd,
                    allFrames: true
                )
            ]
        )

        let contentJS = """
        (function() {
            let copyUnlocked = false;

            function enableSuperCopy() {
                if (copyUnlocked) return;
                copyUnlocked = true;
                const style = document.createElement("style");
                style.id = "zhuo-super-copy-style";
                style.textContent = "* { -webkit-user-select: text !important; user-select: text !important; }";
                (document.head || document.documentElement).appendChild(style);

                ["copy", "cut", "contextmenu", "selectstart", "dragstart"].forEach(function(evt) {
                    window.addEventListener(evt, function(e) {
                        e.stopPropagation();
                    }, true);
                });
                document.oncopy = null;
                document.oncontextmenu = null;
                document.onselectstart = null;
                if (document.body) {
                    document.body.oncopy = null;
                    document.body.oncontextmenu = null;
                    document.body.onselectstart = null;
                }
            }

            function formatPageJSONIfRaw() {
                if (!document.body) return false;
                const pre = document.body.children.length === 1 && document.body.firstElementChild.tagName === "PRE"
                    ? document.body.firstElementChild
                    : null;
                const rawText = (pre ? pre.textContent : document.body.innerText || "").trim();
                if (!rawText || (rawText[0] !== "{" && rawText[0] !== "[")) return false;
                try {
                    const parsed = JSON.parse(rawText);
                    const pretty = JSON.stringify(parsed, null, 2);
                    document.body.innerHTML = "";
                    const toolbar = document.createElement("div");
                    toolbar.style.cssText = "position:sticky;top:0;padding:8px 14px;background:#18181B;color:#F4F4F5;font:12px -apple-system,sans-serif;display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid #27272A;";
                    toolbar.innerHTML = "<span>✨ <b>Zhuo JSON Formatter</b> · 已自动美化结构</span>";
                    const copyBtn = document.createElement("button");
                    copyBtn.textContent = "复制格式化 JSON";
                    copyBtn.style.cssText = "padding:4px 10px;border-radius:5px;border:none;background:#EC4899;color:#fff;cursor:pointer;font-size:11px;font-weight:600;";
                    copyBtn.onclick = function() {
                        window.GM_setClipboard(pretty);
                        copyBtn.textContent = "已复制 ✓";
                    };
                    toolbar.appendChild(copyBtn);
                    const codeBlock = document.createElement("pre");
                    codeBlock.style.cssText = "margin:0;padding:16px;background:#09090B;color:#A7F3D0;font:12.5px/1.55 'SF Mono',Menlo,monospace;overflow:auto;min-height:calc(100vh - 38px);";
                    codeBlock.textContent = pretty;
                    document.body.style.margin = "0";
                    document.body.appendChild(toolbar);
                    document.body.appendChild(codeBlock);
                    return true;
                } catch (e) {
                    return false;
                }
            }

            function collectMetrics() {
                const domCount = document.getElementsByTagName("*").length;
                const scriptCount = document.scripts ? document.scripts.length : 0;
                const imgCount = document.images ? document.images.length : 0;
                let storageKeys = 0;
                try { storageKeys = localStorage.length; } catch (e) {}
                return {
                    domCount: domCount,
                    scriptCount: scriptCount,
                    imgCount: imgCount,
                    storageKeys: storageKeys,
                    copyUnlocked: copyUnlocked,
                    url: location.href,
                    host: location.hostname
                };
            }

            chrome.storage.local.get(["unlockedHosts"], function(res) {
                const map = (res && res.unlockedHosts) || {};
                if (location.hostname && map[location.hostname]) {
                    enableSuperCopy();
                }
            });

            chrome.runtime.onMessage.addListener(function(msg, sender, sendResponse) {
                if (!msg) return;
                if (msg.type === "DEV_GET_METRICS") {
                    sendResponse(collectMetrics());
                } else if (msg.type === "DEV_UNLOCK_COPY") {
                    enableSuperCopy();
                    chrome.storage.local.get(["unlockedHosts"], function(res) {
                        const map = (res && res.unlockedHosts) || {};
                        if (location.hostname) map[location.hostname] = true;
                        chrome.storage.local.set({ unlockedHosts: map });
                    });
                    sendResponse({ ok: true, copyUnlocked: true });
                } else if (msg.type === "DEV_FORMAT_JSON") {
                    const ok = formatPageJSONIfRaw();
                    sendResponse({ ok: ok });
                }
            });
        })();
        """

        let popupHTML = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <title>超级复制与开发者工具箱</title>
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            body { width: 310px; padding: 14px; background: #18181B; color: #F4F4F5; user-select: none; }
            .header { font-size: 13.5px; font-weight: 700; margin-bottom: 12px; padding-bottom: 8px; border-bottom: 1px solid #27272A; }
            .btn { width: 100%; padding: 9px 12px; border-radius: 7px; border: none; font-size: 12px; font-weight: 600; cursor: pointer; margin-bottom: 8px; display: flex; align-items: center; justify-content: space-between; }
            .btn-pink { background: #EC4899; color: #fff; }
            .btn-dark { background: #27272A; color: #E4E4E7; border: 1px solid #3F3F46; }
            .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 6px; }
            .stat { background: #27272A; padding: 8px 10px; border-radius: 6px; }
            .stat-val { font-size: 15px; font-weight: 700; color: #F472B6; }
            .stat-lbl { font-size: 10.5px; color: #A1A1AA; margin-top: 2px; }
        </style>
        </head>
        <body>
            <div class="header">🛠️ 超级复制与开发者工具箱</div>
            <button id="unlockBtn" class="btn btn-pink">
                <span>🔓 解除本页复制与右键限制</span>
                <span id="unlockState">点击启用</span>
            </button>
            <button id="jsonBtn" class="btn btn-dark">
                <span>📋 格式化当前页面 JSON</span>
                <span>美化</span>
            </button>
            <div class="grid">
                <div class="stat"><div id="domCount" class="stat-val">-</div><div class="stat-lbl">DOM 节点数</div></div>
                <div class="stat"><div id="scriptCount" class="stat-val">-</div><div class="stat-lbl">脚本数量</div></div>
                <div class="stat"><div id="imgCount" class="stat-val">-</div><div class="stat-lbl">图片元素</div></div>
                <div class="stat"><div id="storageCount" class="stat-val">-</div><div class="stat-lbl">LocalStorage 键</div></div>
            </div>
            <script src="popup.js"></script>
        </body>
        </html>
        """

        let popupJS = """
        (function() {
            const unlockBtn = document.getElementById("unlockBtn");
            const unlockState = document.getElementById("unlockState");
            const jsonBtn = document.getElementById("jsonBtn");
            const domCount = document.getElementById("domCount");
            const scriptCount = document.getElementById("scriptCount");
            const imgCount = document.getElementById("imgCount");
            const storageCount = document.getElementById("storageCount");
            let activeTabId = null;

            chrome.tabs.query({ active: true, currentWindow: true }, function(tabs) {
                const tab = tabs && tabs[0];
                if (!tab) return;
                activeTabId = tab.id;
                chrome.tabs.sendMessage(activeTabId, { type: "DEV_GET_METRICS" }, function(m) {
                    if (!m) return;
                    domCount.textContent = m.domCount || 0;
                    scriptCount.textContent = m.scriptCount || 0;
                    imgCount.textContent = m.imgCount || 0;
                    storageCount.textContent = m.storageKeys || 0;
                    if (m.copyUnlocked) {
                        unlockState.textContent = "已生效 ✓";
                    }
                });
            });

            unlockBtn.addEventListener("click", function() {
                if (activeTabId === null) return;
                chrome.tabs.sendMessage(activeTabId, { type: "DEV_UNLOCK_COPY" }, function() {
                    unlockState.textContent = "已生效 ✓";
                });
            });

            jsonBtn.addEventListener("click", function() {
                if (activeTabId === null) return;
                chrome.tabs.sendMessage(activeTabId, { type: "DEV_FORMAT_JSON" });
            });
        })();
        """

        return Template(
            id: superCopyDevToolsID,
            sfSymbol: "wrench.and.screwdriver.fill",
            accentColorHex: "#EC4899",
            defaultPinned: true,
            defaultEnabled: true,
            manifest: manifest,
            files: [
                "content.js": contentJS,
                "popup.html": popupHTML,
                "popup.js": popupJS
            ]
        )
    }

    // MARK: - 5. UserScript & Custom CSS Studio (用户脚本与样式工作台)

    public static let userScriptStudioID = "ext-userscript-studio"

    private static var userScriptStudioTemplate: Template {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "用户脚本与自定义样式工作台 (UserScript Studio)",
            shortName: "脚本工作台",
            version: "1.0.0",
            description: "内置网页阅读辅助标尺、外链新标签打开与自定义 CSS/JS 实时注入工具，兼容 Tampermonkey GM_* 脚本 API。",
            author: "ZhuoBrowser Team",
            permissions: ["storage", "tabs", "activeTab", "scripting"],
            hostPermissions: ["<all_urls>"],
            action: ExtensionActionSpec(
                defaultTitle: "用户脚本与样式工作台",
                defaultPopup: "popup.html"
            ),
            contentScripts: [
                ExtensionContentScriptSpec(
                    matches: ["<all_urls>"],
                    js: ["content.js"],
                    runAt: .documentEnd,
                    allFrames: false
                )
            ],
            optionsPage: "options.html",
            optionsOpenInTab: true
        )

        let contentJS = """
        (function() {
            const CUSTOM_STYLE_ID = "zhuo-userscript-studio-css";
            let rulerEl = null;

            function applyRules(rules) {
                if (!rules) return;
                // 1. Custom CSS
                let styleEl = document.getElementById(CUSTOM_STYLE_ID);
                if (rules.customCSS && rules.customCSS.trim()) {
                    if (!styleEl) {
                        styleEl = document.createElement("style");
                        styleEl.id = CUSTOM_STYLE_ID;
                        (document.head || document.documentElement).appendChild(styleEl);
                    }
                    styleEl.textContent = rules.customCSS;
                } else if (styleEl) {
                    styleEl.remove();
                }

                // 2. External links open in new tab
                if (rules.externalLinksBlank) {
                    document.querySelectorAll("a[href^='http']").forEach(function(a) {
                        try {
                            const u = new URL(a.href);
                            if (u.hostname && u.hostname !== location.hostname) {
                                a.setAttribute("target", "_blank");
                                a.setAttribute("rel", "noopener noreferrer");
                            }
                        } catch (e) {}
                    });
                }

                // 3. Reading Focus Ruler
                if (rules.readingRuler) {
                    if (!rulerEl) {
                        rulerEl = document.createElement("div");
                        rulerEl.style.cssText = "position:fixed;left:0;right:0;height:28px;background:rgba(139,92,246,0.12);border-top:1px solid rgba(139,92,246,0.45);border-bottom:1px solid rgba(139,92,246,0.45);pointer-events:none;z-index:2147483645;top:200px;";
                        document.body.appendChild(rulerEl);
                        window.addEventListener("mousemove", function(e) {
                            if (rulerEl) rulerEl.style.top = (e.clientY - 14) + "px";
                        }, { passive: true });
                    }
                } else if (rulerEl) {
                    rulerEl.remove();
                    rulerEl = null;
                }
            }

            chrome.storage.local.get(["studioRules"], function(res) {
                if (res && res.studioRules) {
                    applyRules(res.studioRules);
                }
            });

            chrome.runtime.onMessage.addListener(function(msg, sender, sendResponse) {
                if (msg && msg.type === "STUDIO_APPLY_RULES") {
                    applyRules(msg.rules);
                    sendResponse({ ok: true });
                }
            });
        })();
        """

        let popupHTML = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <title>用户脚本与样式工作台</title>
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            body { width: 320px; padding: 14px; background: #18181B; color: #F4F4F5; }
            .header { font-size: 13.5px; font-weight: 700; margin-bottom: 10px; }
            .row { display: flex; justify-content: space-between; align-items: center; padding: 7px 0; font-size: 12px; border-bottom: 1px solid #27272A; }
            textarea { width: 100%; height: 90px; margin-top: 8px; padding: 8px; border-radius: 6px; background: #09090B; color: #C4B5FD; border: 1px solid #3F3F46; font: 11.5px 'SF Mono', Menlo, monospace; resize: none; }
            .btn-row { display: flex; gap: 8px; margin-top: 10px; }
            button { flex: 1; padding: 7px; border-radius: 6px; border: none; font-size: 11.5px; font-weight: 600; cursor: pointer; }
            .btn-primary { background: #8B5CF6; color: #fff; }
            .btn-secondary { background: #27272A; color: #D4D4D8; }
        </style>
        </head>
        <body>
            <div class="header">⚡ 脚本与自定义样式工作台</div>
            <div class="row">
                <span>外链自动在新标签页打开</span>
                <input type="checkbox" id="externalLinksBlank">
            </div>
            <div class="row">
                <span>启用沉浸阅读高亮标尺</span>
                <input type="checkbox" id="readingRuler">
            </div>
            <textarea id="customCSS" placeholder="在此输入全局自定义 CSS，例如：&#10;body { font-smoothing: antialiased; }"></textarea>
            <div class="btn-row">
                <button id="saveBtn" class="btn-primary">保存并立即应用</button>
                <button id="optionsBtn" class="btn-secondary">打开完整工作台</button>
            </div>
            <script src="popup.js"></script>
        </body>
        </html>
        """

        let popupJS = """
        (function() {
            const externalLinksBlank = document.getElementById("externalLinksBlank");
            const readingRuler = document.getElementById("readingRuler");
            const customCSS = document.getElementById("customCSS");
            const saveBtn = document.getElementById("saveBtn");
            const optionsBtn = document.getElementById("optionsBtn");

            let rules = { externalLinksBlank: false, readingRuler: false, customCSS: "" };

            chrome.storage.local.get(["studioRules"], function(res) {
                if (res && res.studioRules) {
                    Object.assign(rules, res.studioRules);
                }
                externalLinksBlank.checked = Boolean(rules.externalLinksBlank);
                readingRuler.checked = Boolean(rules.readingRuler);
                customCSS.value = rules.customCSS || "";
            });

            function saveAndApply() {
                rules.externalLinksBlank = externalLinksBlank.checked;
                rules.readingRuler = readingRuler.checked;
                rules.customCSS = customCSS.value;
                chrome.storage.local.set({ studioRules: rules });
                chrome.tabs.query({ active: true, currentWindow: true }, function(tabs) {
                    if (tabs && tabs[0]) {
                        chrome.tabs.sendMessage(tabs[0].id, { type: "STUDIO_APPLY_RULES", rules: rules });
                    }
                });
                saveBtn.textContent = "已应用 ✓";
                setTimeout(function() { saveBtn.textContent = "保存并立即应用"; }, 1000);
            }

            saveBtn.addEventListener("click", saveAndApply);
            externalLinksBlank.addEventListener("change", saveAndApply);
            readingRuler.addEventListener("change", saveAndApply);
            optionsBtn.addEventListener("click", function() {
                chrome.runtime.openOptionsPage();
            });
        })();
        """

        let optionsHTML = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <title>UserScript Studio 选项页</title>
        <style>
            body { max-width: 680px; margin: 40px auto; padding: 24px; background: #09090B; color: #F4F4F5; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            h1 { font-size: 20px; margin-bottom: 8px; }
            p { color: #A1A1AA; font-size: 13px; margin-bottom: 20px; }
            .card { background: #18181B; border: 1px solid #27272A; border-radius: 10px; padding: 18px; margin-bottom: 16px; }
            textarea { width: 100%; height: 220px; background: #09090B; color: #C4B5FD; border: 1px solid #3F3F46; border-radius: 8px; padding: 12px; font: 12.5px 'SF Mono', Menlo, monospace; margin-top: 8px; }
            button { margin-top: 12px; padding: 8px 18px; border-radius: 6px; border: none; background: #8B5CF6; color: white; font-weight: 600; cursor: pointer; }
        </style>
        </head>
        <body>
            <h1>⚡ UserScript & Custom CSS Studio</h1>
            <p>在此编写的自定义 CSS 将通过 Chrome Storage 持久化并自动注入所有匹配的标签页。</p>
            <div class="card">
                <label>全局自定义样式表 (Custom CSS)</label>
                <textarea id="cssEditor" placeholder="/* 输入自定义 CSS */"></textarea>
                <button id="saveOptionsBtn">保存设置</button>
            </div>
            <script>
                const editor = document.getElementById("cssEditor");
                const btn = document.getElementById("saveOptionsBtn");
                let rules = { externalLinksBlank: false, readingRuler: false, customCSS: "" };
                chrome.storage.local.get(["studioRules"], function(res) {
                    if (res && res.studioRules) {
                        Object.assign(rules, res.studioRules);
                        editor.value = rules.customCSS || "";
                    }
                });
                btn.addEventListener("click", function() {
                    rules.customCSS = editor.value;
                    chrome.storage.local.set({ studioRules: rules });
                    btn.textContent = "已保存 ✓";
                    setTimeout(function() { btn.textContent = "保存设置"; }, 1200);
                });
            </script>
        </body>
        </html>
        """

        return Template(
            id: userScriptStudioID,
            sfSymbol: "curlybraces.square.fill",
            accentColorHex: "#8B5CF6",
            defaultPinned: false,
            defaultEnabled: true,
            manifest: manifest,
            files: [
                "content.js": contentJS,
                "popup.html": popupHTML,
                "popup.js": popupJS,
                "options.html": optionsHTML
            ]
        )
    }
}
