import Foundation
import WebKit

/// Generates the JavaScript `window.chrome` / `window.browser` / `GM_*` runtime polyfill
/// and coordinates message passing between WebKit frames and `ExtensionManager`.
public enum ExtensionRuntimeBridge {
    /// Name of the `WKScriptMessageHandler` registered on tab and popup `WKUserContentController`s.
    public static let messageHandlerName = "zhuoExtensionBridge"

    /// Execution context type where the bridge is injected.
    public enum ContextType: String, Sendable {
        case contentScript = "content_script"
        case popup = "popup"
        case options = "options"
        case background = "background"
    }

    /// Generates a self-contained JS bootstrap that defines `window.chrome`, `window.browser`,
    /// and UserScript `GM_*` APIs for a specific extension (or shared content script environment).
    public static func makePolyfillScript(
        extensionItem: InstalledExtension,
        contextType: ContextType,
        tabNumericID: Int = 1,
        initialLocalStore: [String: Any] = [:],
        initialSyncStore: [String: Any] = [:],
        i18nCatalog: ExtensionI18nCatalog = ExtensionI18nCatalog()
    ) -> String {
        let extID = extensionItem.id
        let manifestData = (try? JSONEncoder().encode(extensionItem.manifest)) ?? Data("{}".utf8)
        let manifestJSON = String(data: manifestData, encoding: .utf8) ?? "{}"
        let localJSON = serializeJSONDictionary(initialLocalStore)
        let syncJSON = serializeJSONDictionary(initialSyncStore)
        let i18nJSON = serializeJSONDictionary(i18nCatalog.messages)
        let badgeTextEscaped = escapeJSString(extensionItem.actionState.defaultBadgeText)
        let badgeColorEscaped = escapeJSString(extensionItem.actionState.defaultBadgeBackgroundColor)
        let defaultTitleEscaped = escapeJSString(extensionItem.displayTitle)
        let defaultPopupEscaped = escapeJSString(extensionItem.effectivePopupRelativePath ?? "")

        return """
        (function() {
            const EXT_ID = "\(escapeJSString(extID))";
            const CONTEXT_TYPE = "\(contextType.rawValue)";
            const CURRENT_TAB_ID = \(tabNumericID);
            const MANIFEST = \(manifestJSON);
            const I18N_MESSAGES = \(i18nJSON);

            window.__ZHUO_EXTENSIONS__ = window.__ZHUO_EXTENSIONS__ || {};
            if (window.__ZHUO_EXTENSIONS__[EXT_ID] && CONTEXT_TYPE === "content_script") {
                return;
            }

            const localStoreCache = Object.assign({}, \(localJSON));
            const syncStoreCache = Object.assign({}, \(syncJSON));
            const sessionStoreCache = {};
            let badgeTextCache = "\(badgeTextEscaped)";
            let badgeBgCache = "\(badgeColorEscaped)";
            let actionTitleCache = "\(defaultTitleEscaped)";
            let actionPopupCache = "\(defaultPopupEscaped)";

            const pendingCallbacks = new Map();
            let nextRequestId = 1;

            const listeners = {
                runtimeOnMessage: new Set(),
                runtimeOnInstalled: new Set(),
                storageOnChanged: new Set(),
                actionOnClicked: new Set(),
                contextMenusOnClicked: new Set(),
                tabsOnUpdated: new Set(),
                tabsOnActivated: new Set()
            };

            function makeEventTarget(listenerSet) {
                return {
                    addListener: function(fn) {
                        if (typeof fn === "function") listenerSet.add(fn);
                    },
                    removeListener: function(fn) {
                        listenerSet.delete(fn);
                    },
                    hasListener: function(fn) {
                        return listenerSet.has(fn);
                    },
                    hasListeners: function() {
                        return listenerSet.size > 0;
                    },
                    _emit: function() {
                        const args = Array.from(arguments);
                        let handledAsync = false;
                        listenerSet.forEach(function(fn) {
                            try {
                                const res = fn.apply(null, args);
                                if (res === true) handledAsync = true;
                            } catch (err) {
                                console.error("[ZhuoExtension " + EXT_ID + "] listener error:", err);
                            }
                        });
                        return handledAsync;
                    }
                };
            }

            function postNative(action, payload, callback) {
                const reqId = EXT_ID + "_" + (nextRequestId++) + "_" + Date.now();
                return new Promise(function(resolve, reject) {
                    pendingCallbacks.set(reqId, function(response) {
                        if (response && response.error) {
                            chromeObj.runtime.lastError = { message: String(response.error) };
                        } else {
                            chromeObj.runtime.lastError = null;
                        }
                        const result = response ? response.result : undefined;
                        if (typeof callback === "function") {
                            try { callback(result); } catch (e) {}
                        }
                        chromeObj.runtime.lastError = null;
                        resolve(result);
                    });

                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName)) {
                            window.webkit.messageHandlers.\(messageHandlerName).postMessage({
                                requestId: reqId,
                                extensionId: EXT_ID,
                                contextType: CONTEXT_TYPE,
                                tabId: CURRENT_TAB_ID,
                                action: action,
                                payload: payload || {}
                            });
                        } else {
                            const handler = pendingCallbacks.get(reqId);
                            pendingCallbacks.delete(reqId);
                            if (handler) handler({ result: null });
                        }
                    } catch (err) {
                        pendingCallbacks.delete(reqId);
                        if (typeof callback === "function") callback(undefined);
                        resolve(undefined);
                    }
                });
            }

            function createStorageArea(areaName, cacheObj) {
                return {
                    get: function(keys, callback) {
                        let resolvedKeys = keys;
                        let cb = callback;
                        if (typeof keys === "function") {
                            cb = keys;
                            resolvedKeys = null;
                        }
                        const computeResult = function() {
                            const out = {};
                            if (resolvedKeys === null || resolvedKeys === undefined) {
                                Object.assign(out, cacheObj);
                            } else if (typeof resolvedKeys === "string") {
                                if (Object.prototype.hasOwnProperty.call(cacheObj, resolvedKeys)) {
                                    out[resolvedKeys] = cacheObj[resolvedKeys];
                                }
                            } else if (Array.isArray(resolvedKeys)) {
                                for (let i = 0; i < resolvedKeys.length; i++) {
                                    const k = resolvedKeys[i];
                                    if (Object.prototype.hasOwnProperty.call(cacheObj, k)) {
                                        out[k] = cacheObj[k];
                                    }
                                }
                            } else if (typeof resolvedKeys === "object") {
                                for (const k of Object.keys(resolvedKeys)) {
                                    out[k] = Object.prototype.hasOwnProperty.call(cacheObj, k)
                                        ? cacheObj[k]
                                        : resolvedKeys[k];
                                }
                            }
                            return out;
                        };
                        const immediate = computeResult();
                        return postNative("storage.get", { area: areaName, keys: resolvedKeys }).then(function(remote) {
                            if (remote && typeof remote === "object") {
                                Object.assign(cacheObj, remote);
                            }
                            const finalOut = computeResult();
                            if (typeof cb === "function") {
                                try { cb(finalOut); } catch (e) {}
                            }
                            return finalOut;
                        });
                    },
                    set: function(items, callback) {
                        const changes = {};
                        if (items && typeof items === "object") {
                            for (const k of Object.keys(items)) {
                                changes[k] = { oldValue: cacheObj[k], newValue: items[k] };
                                cacheObj[k] = items[k];
                            }
                        }
                        if (Object.keys(changes).length > 0) {
                            listeners.storageOnChanged._emit(changes, areaName);
                        }
                        return postNative("storage.set", { area: areaName, items: items || {} }, callback);
                    },
                    remove: function(keys, callback) {
                        const keyList = Array.isArray(keys) ? keys : [String(keys)];
                        const changes = {};
                        for (let i = 0; i < keyList.length; i++) {
                            const k = keyList[i];
                            if (Object.prototype.hasOwnProperty.call(cacheObj, k)) {
                                changes[k] = { oldValue: cacheObj[k] };
                                delete cacheObj[k];
                            }
                        }
                        if (Object.keys(changes).length > 0) {
                            listeners.storageOnChanged._emit(changes, areaName);
                        }
                        return postNative("storage.remove", { area: areaName, keys: keyList }, callback);
                    },
                    clear: function(callback) {
                        const changes = {};
                        for (const k of Object.keys(cacheObj)) {
                            changes[k] = { oldValue: cacheObj[k] };
                            delete cacheObj[k];
                        }
                        if (Object.keys(changes).length > 0) {
                            listeners.storageOnChanged._emit(changes, areaName);
                        }
                        return postNative("storage.clear", { area: areaName }, callback);
                    },
                    getBytesInUse: function(keys, callback) {
                        const cb = typeof keys === "function" ? keys : callback;
                        const size = JSON.stringify(cacheObj).length;
                        if (typeof cb === "function") cb(size);
                        return Promise.resolve(size);
                    }
                };
            }

            const actionAPI = {
                setBadgeText: function(details, callback) {
                    const text = (details && details.text !== undefined) ? String(details.text) : "";
                    badgeTextCache = text;
                    return postNative("action.setBadgeText", details || {}, callback);
                },
                getBadgeText: function(details, callback) {
                    const cb = typeof details === "function" ? details : callback;
                    if (typeof cb === "function") cb(badgeTextCache);
                    return Promise.resolve(badgeTextCache);
                },
                setBadgeBackgroundColor: function(details, callback) {
                    if (details && details.color) {
                        badgeBgCache = Array.isArray(details.color)
                            ? "rgb(" + details.color.slice(0, 3).join(",") + ")"
                            : String(details.color);
                    }
                    return postNative("action.setBadgeBackgroundColor", details || {}, callback);
                },
                getBadgeBackgroundColor: function(details, callback) {
                    const cb = typeof details === "function" ? details : callback;
                    if (typeof cb === "function") cb(badgeBgCache);
                    return Promise.resolve(badgeBgCache);
                },
                setTitle: function(details, callback) {
                    if (details && details.title !== undefined) {
                        actionTitleCache = String(details.title);
                    }
                    return postNative("action.setTitle", details || {}, callback);
                },
                getTitle: function(details, callback) {
                    const cb = typeof details === "function" ? details : callback;
                    if (typeof cb === "function") cb(actionTitleCache);
                    return Promise.resolve(actionTitleCache);
                },
                setPopup: function(details, callback) {
                    if (details && details.popup !== undefined) {
                        actionPopupCache = String(details.popup);
                    }
                    return postNative("action.setPopup", details || {}, callback);
                },
                getPopup: function(details, callback) {
                    const cb = typeof details === "function" ? details : callback;
                    if (typeof cb === "function") cb(actionPopupCache);
                    return Promise.resolve(actionPopupCache);
                },
                setIcon: function(details, callback) {
                    if (typeof callback === "function") callback();
                    return Promise.resolve();
                },
                enable: function(tabId, callback) {
                    const cb = typeof tabId === "function" ? tabId : callback;
                    return postNative("action.setEnabled", { enabled: true }, cb);
                },
                disable: function(tabId, callback) {
                    const cb = typeof tabId === "function" ? tabId : callback;
                    return postNative("action.setEnabled", { enabled: false }, cb);
                },
                onClicked: makeEventTarget(listeners.actionOnClicked)
            };

            const chromeObj = {
                runtime: {
                    id: EXT_ID,
                    lastError: null,
                    getManifest: function() {
                        return MANIFEST;
                    },
                    getURL: function(path) {
                        const clean = String(path || "").replace(/^\\/+/, "");
                        return "zhuo-extension://" + EXT_ID + "/" + clean;
                    },
                    sendMessage: function(extIdOrMsg, maybeMsgOrOpts, maybeOptsOrCb, maybeCb) {
                        let targetExtId = EXT_ID;
                        let message = extIdOrMsg;
                        let callback = undefined;
                        if (typeof extIdOrMsg === "string" && maybeMsgOrOpts !== undefined && typeof maybeMsgOrOpts !== "function") {
                            targetExtId = extIdOrMsg;
                            message = maybeMsgOrOpts;
                            callback = typeof maybeOptsOrCb === "function" ? maybeOptsOrCb : maybeCb;
                        } else {
                            callback = typeof maybeMsgOrOpts === "function" ? maybeMsgOrOpts : (typeof maybeOptsOrCb === "function" ? maybeOptsOrCb : undefined);
                        }
                        return postNative("runtime.sendMessage", {
                            targetExtensionId: targetExtId,
                            message: message
                        }, callback);
                    },
                    openOptionsPage: function(callback) {
                        return postNative("runtime.openOptionsPage", {}, callback);
                    },
                    getPlatformInfo: function(callback) {
                        const info = { os: "mac", arch: "arm64", nacl_arch: "arm" };
                        if (typeof callback === "function") callback(info);
                        return Promise.resolve(info);
                    },
                    onMessage: makeEventTarget(listeners.runtimeOnMessage),
                    onInstalled: makeEventTarget(listeners.runtimeOnInstalled)
                },
                storage: {
                    local: createStorageArea("local", localStoreCache),
                    sync: createStorageArea("sync", syncStoreCache),
                    session: createStorageArea("session", sessionStoreCache),
                    onChanged: makeEventTarget(listeners.storageOnChanged)
                },
                action: actionAPI,
                browserAction: actionAPI,
                pageAction: actionAPI,
                tabs: {
                    query: function(queryInfo, callback) {
                        return postNative("tabs.query", queryInfo || {}, callback);
                    },
                    get: function(tabId, callback) {
                        return postNative("tabs.get", { tabId: tabId }, callback);
                    },
                    getCurrent: function(callback) {
                        return postNative("tabs.getCurrent", {}, callback);
                    },
                    create: function(createProperties, callback) {
                        return postNative("tabs.create", createProperties || {}, callback);
                    },
                    update: function(tabIdOrProps, maybePropsOrCb, maybeCb) {
                        let tabId = null;
                        let props = {};
                        let cb = undefined;
                        if (typeof tabIdOrProps === "number") {
                            tabId = tabIdOrProps;
                            props = maybePropsOrCb || {};
                            cb = maybeCb;
                        } else {
                            props = tabIdOrProps || {};
                            cb = typeof maybePropsOrCb === "function" ? maybePropsOrCb : undefined;
                        }
                        return postNative("tabs.update", { tabId: tabId, updateProperties: props }, cb);
                    },
                    reload: function(tabIdOrProps, maybePropsOrCb, maybeCb) {
                        let tabId = typeof tabIdOrProps === "number" ? tabIdOrProps : null;
                        let cb = typeof tabIdOrProps === "function" ? tabIdOrProps : (typeof maybePropsOrCb === "function" ? maybePropsOrCb : maybeCb);
                        return postNative("tabs.reload", { tabId: tabId }, cb);
                    },
                    remove: function(tabIds, callback) {
                        const list = Array.isArray(tabIds) ? tabIds : [tabIds];
                        return postNative("tabs.remove", { tabIds: list }, callback);
                    },
                    sendMessage: function(tabId, message, optionsOrCb, maybeCb) {
                        const cb = typeof optionsOrCb === "function" ? optionsOrCb : maybeCb;
                        return postNative("tabs.sendMessage", {
                            tabId: tabId,
                            message: message
                        }, cb);
                    },
                    executeScript: function(tabIdOrDetails, maybeDetailsOrCb, maybeCb) {
                        let tabId = typeof tabIdOrDetails === "number" ? tabIdOrDetails : null;
                        let details = typeof tabIdOrDetails === "number" ? (maybeDetailsOrCb || {}) : (tabIdOrDetails || {});
                        let cb = typeof maybeDetailsOrCb === "function" ? maybeDetailsOrCb : maybeCb;
                        return postNative("scripting.executeScript", {
                            tabId: tabId,
                            code: details.code || null,
                            files: details.file ? [details.file] : (details.files || [])
                        }, cb);
                    },
                    insertCSS: function(tabIdOrDetails, maybeDetailsOrCb, maybeCb) {
                        let tabId = typeof tabIdOrDetails === "number" ? tabIdOrDetails : null;
                        let details = typeof tabIdOrDetails === "number" ? (maybeDetailsOrCb || {}) : (tabIdOrDetails || {});
                        let cb = typeof maybeDetailsOrCb === "function" ? maybeDetailsOrCb : maybeCb;
                        return postNative("scripting.insertCSS", {
                            tabId: tabId,
                            css: details.code || null,
                            files: details.file ? [details.file] : (details.files || [])
                        }, cb);
                    },
                    onUpdated: makeEventTarget(listeners.tabsOnUpdated),
                    onActivated: makeEventTarget(listeners.tabsOnActivated)
                },
                scripting: {
                    executeScript: function(injection, callback) {
                        const targetTabId = (injection && injection.target && injection.target.tabId) ? injection.target.tabId : null;
                        let fnSource = null;
                        if (injection && typeof injection.func === "function") {
                            const serializedArgs = JSON.stringify(injection.args || []);
                            fnSource = "(" + injection.func.toString() + ").apply(null, " + serializedArgs + ")";
                        }
                        return postNative("scripting.executeScript", {
                            tabId: targetTabId,
                            code: fnSource || (injection && injection.code) || null,
                            files: (injection && injection.files) || []
                        }, callback);
                    },
                    insertCSS: function(injection, callback) {
                        const targetTabId = (injection && injection.target && injection.target.tabId) ? injection.target.tabId : null;
                        return postNative("scripting.insertCSS", {
                            tabId: targetTabId,
                            css: (injection && injection.css) || null,
                            files: (injection && injection.files) || []
                        }, callback);
                    },
                    removeCSS: function(injection, callback) {
                        const targetTabId = (injection && injection.target && injection.target.tabId) ? injection.target.tabId : null;
                        return postNative("scripting.removeCSS", {
                            tabId: targetTabId,
                            css: (injection && injection.css) || null,
                            files: (injection && injection.files) || []
                        }, callback);
                    }
                },
                i18n: {
                    getMessage: function(messageName, substitutions) {
                        if (!messageName) return "";
                        const key = String(messageName).toLowerCase();
                        if (key === "@@extension_id") return EXT_ID;
                        if (key === "@@ui_locale") return "zh_CN";
                        let tpl = I18N_MESSAGES[key];
                        if (!tpl) return "";
                        const subs = Array.isArray(substitutions) ? substitutions : (substitutions !== undefined ? [String(substitutions)] : []);
                        for (let i = 0; i < subs.length; i++) {
                            tpl = tpl.split("$" + (i + 1)).join(String(subs[i]));
                        }
                        return tpl;
                    },
                    getUILanguage: function() {
                        return navigator.language || "zh-CN";
                    },
                    getAcceptLanguages: function(callback) {
                        const langs = navigator.languages ? Array.from(navigator.languages) : ["zh-CN", "en-US"];
                        if (typeof callback === "function") callback(langs);
                        return Promise.resolve(langs);
                    }
                },
                contextMenus: {
                    create: function(createProperties, callback) {
                        const id = (createProperties && createProperties.id) ? String(createProperties.id) : ("menu_" + Date.now());
                        postNative("contextMenus.create", Object.assign({}, createProperties || {}, { id: id }), callback);
                        return id;
                    },
                    update: function(id, updateProperties, callback) {
                        return postNative("contextMenus.update", { id: String(id), updateProperties: updateProperties || {} }, callback);
                    },
                    remove: function(menuItemId, callback) {
                        return postNative("contextMenus.remove", { id: String(menuItemId) }, callback);
                    },
                    removeAll: function(callback) {
                        return postNative("contextMenus.removeAll", {}, callback);
                    },
                    onClicked: makeEventTarget(listeners.contextMenusOnClicked)
                },
                notifications: {
                    create: function(idOrOptions, maybeOptionsOrCb, maybeCb) {
                        let notifId = typeof idOrOptions === "string" ? idOrOptions : ("notif_" + Date.now());
                        let options = typeof idOrOptions === "string" ? (maybeOptionsOrCb || {}) : (idOrOptions || {});
                        let cb = typeof maybeOptionsOrCb === "function" ? maybeOptionsOrCb : maybeCb;
                        return postNative("notifications.create", { id: notifId, options: options }, cb);
                    },
                    clear: function(id, callback) {
                        if (typeof callback === "function") callback(true);
                        return Promise.resolve(true);
                    }
                },
                permissions: {
                    contains: function(permissions, callback) {
                        if (typeof callback === "function") callback(true);
                        return Promise.resolve(true);
                    },
                    getAll: function(callback) {
                        const res = {
                            permissions: MANIFEST.permissions || [],
                            origins: MANIFEST.host_permissions || ["<all_urls>"]
                        };
                        if (typeof callback === "function") callback(res);
                        return Promise.resolve(res);
                    },
                    request: function(permissions, callback) {
                        if (typeof callback === "function") callback(true);
                        return Promise.resolve(true);
                    },
                    remove: function(permissions, callback) {
                        if (typeof callback === "function") callback(true);
                        return Promise.resolve(true);
                    }
                }
            };

            const extBridgeHandle = {
                chrome: chromeObj,
                resolveNativeCallback: function(requestId, response) {
                    const cb = pendingCallbacks.get(requestId);
                    if (cb) {
                        pendingCallbacks.delete(requestId);
                        cb(response);
                    }
                },
                dispatchRuntimeMessage: function(message, sender) {
                    let asyncResponse = null;
                    let didRespond = false;
                    const sendResponse = function(reply) {
                        didRespond = true;
                        asyncResponse = reply;
                    };
                    listeners.runtimeOnMessage._emit(
                        message,
                        sender || { id: EXT_ID, tab: { id: CURRENT_TAB_ID, url: location.href, title: document.title } },
                        sendResponse
                    );
                    return didRespond ? asyncResponse : null;
                },
                dispatchStorageChanged: function(changes, areaName) {
                    if (areaName === "local" && changes) {
                        for (const k of Object.keys(changes)) {
                            if (changes[k] && "newValue" in changes[k]) {
                                localStoreCache[k] = changes[k].newValue;
                            } else {
                                delete localStoreCache[k];
                            }
                        }
                    }
                    listeners.storageOnChanged._emit(changes || {}, areaName || "local");
                },
                dispatchActionClicked: function(tabInfo) {
                    listeners.actionOnClicked._emit(tabInfo || { id: CURRENT_TAB_ID, url: location.href, title: document.title });
                },
                dispatchContextMenuClicked: function(info, tabInfo) {
                    listeners.contextMenusOnClicked._emit(info || {}, tabInfo || { id: CURRENT_TAB_ID, url: location.href });
                }
            };

            window.__ZHUO_EXTENSIONS__[EXT_ID] = extBridgeHandle;

            window.__zhuoExtensionResolveCallback = function(requestId, response) {
                for (const key of Object.keys(window.__ZHUO_EXTENSIONS__)) {
                    window.__ZHUO_EXTENSIONS__[key].resolveNativeCallback(requestId, response);
                }
            };

            window.__zhuoExtensionDispatchMessage = function(targetExtId, message, sender) {
                if (targetExtId && window.__ZHUO_EXTENSIONS__[targetExtId]) {
                    return window.__ZHUO_EXTENSIONS__[targetExtId].dispatchRuntimeMessage(message, sender);
                }
                let lastReply = null;
                for (const key of Object.keys(window.__ZHUO_EXTENSIONS__)) {
                    const reply = window.__ZHUO_EXTENSIONS__[key].dispatchRuntimeMessage(message, sender);
                    if (reply !== null && reply !== undefined) lastReply = reply;
                }
                return lastReply;
            };

            // Expose global window.chrome and window.browser
            if (!window.chrome || !window.chrome.runtime || CONTEXT_TYPE !== "content_script") {
                window.chrome = Object.assign(window.chrome || {}, chromeObj);
                window.browser = window.chrome;
            }

            // UserScript (Tampermonkey / Greasemonkey) Compatibility APIs
            window.GM_info = {
                script: {
                    name: MANIFEST.name || "UserScript",
                    version: MANIFEST.version || "1.0.0",
                    description: MANIFEST.description || ""
                },
                scriptHandler: "ZhuoBrowser Extensions",
                version: "1.0.0"
            };
            window.GM_getValue = function(key, defaultValue) {
                return Object.prototype.hasOwnProperty.call(localStoreCache, key) ? localStoreCache[key] : defaultValue;
            };
            window.GM_setValue = function(key, value) {
                const patch = {};
                patch[key] = value;
                return chromeObj.storage.local.set(patch);
            };
            window.GM_deleteValue = function(key) {
                return chromeObj.storage.local.remove(key);
            };
            window.GM_listValues = function() {
                return Object.keys(localStoreCache);
            };
            window.GM_addStyle = function(cssText) {
                const style = document.createElement("style");
                style.setAttribute("data-zhuo-extension", EXT_ID);
                style.textContent = String(cssText || "");
                (document.head || document.documentElement).appendChild(style);
                return style;
            };
            window.GM_openInTab = function(url, options) {
                const active = !(options && options.active === false);
                chromeObj.tabs.create({ url: String(url), active: active });
            };
            window.GM_setClipboard = function(text) {
                postNative("clipboard.writeText", { text: String(text || "") });
            };
            window.GM_notification = function(textOrOpts, title) {
                const opts = typeof textOrOpts === "string"
                    ? { title: title || MANIFEST.name, message: textOrOpts }
                    : (textOrOpts || {});
                chromeObj.notifications.create(opts);
            };
            window.GM_registerMenuCommand = function(caption, commandFunc) {
                const menuId = "gm_cmd_" + caption;
                chromeObj.contextMenus.create({ id: menuId, title: caption, contexts: ["all"] });
                chromeObj.contextMenus.onClicked.addListener(function(info) {
                    if (info && info.menuItemId === menuId && typeof commandFunc === "function") {
                        commandFunc();
                    }
                });
                return menuId;
            };
            window.GM_xmlhttpRequest = function(details) {
                if (!details || !details.url) return;
                fetch(details.url, {
                    method: details.method || "GET",
                    headers: details.headers || {},
                    body: details.data || undefined
                }).then(function(resp) {
                    return resp.text().then(function(text) {
                        if (typeof details.onload === "function") {
                            details.onload({
                                status: resp.status,
                                statusText: resp.statusText,
                                responseText: text,
                                response: text,
                                finalUrl: resp.url
                            });
                        }
                    });
                }).catch(function(err) {
                    if (typeof details.onerror === "function") {
                        details.onerror({ error: String(err) });
                    }
                });
            };
            window.GM = {
                info: window.GM_info,
                getValue: function(k, d) { return Promise.resolve(window.GM_getValue(k, d)); },
                setValue: function(k, v) { return window.GM_setValue(k, v); },
                deleteValue: function(k) { return window.GM_deleteValue(k); },
                listValues: function() { return Promise.resolve(window.GM_listValues()); },
                addStyle: function(css) { return Promise.resolve(window.GM_addStyle(css)); },
                openInTab: function(u, o) { window.GM_openInTab(u, o); return Promise.resolve(); },
                setClipboard: function(t) { window.GM_setClipboard(t); return Promise.resolve(); },
                notification: function(t, title) { window.GM_notification(t, title); return Promise.resolve(); },
                xmlHttpRequest: window.GM_xmlhttpRequest
            };
        })();
        """
    }

    /// Generates a self-contained JS snippet that injects a CSS stylesheet into the page DOM
    /// and tags it with `data-zhuo-extension` so it can be updated or removed cleanly when an extension is disabled.
    public static func makeCSSInjectionScript(extensionID: String, styleID: String, cssContent: String) -> String {
        let escapedCSS = escapeJSString(cssContent)
        let escapedExtID = escapeJSString(extensionID)
        let escapedStyleID = escapeJSString(styleID)
        return """
        (function() {
            const inject = function() {
                const root = document.head || document.documentElement;
                if (!root) return false;
                let styleEl = document.getElementById("\(escapedStyleID)");
                if (!styleEl) {
                    styleEl = document.createElement("style");
                    styleEl.id = "\(escapedStyleID)";
                    styleEl.setAttribute("data-zhuo-extension", "\(escapedExtID)");
                    root.appendChild(styleEl);
                }
                styleEl.textContent = "\(escapedCSS)";
                return true;
            };
            if (!inject()) {
                document.addEventListener("DOMContentLoaded", inject, { once: true });
            }
        })();
        """
    }

    /// Wraps a content script JS file in an isolated scope bound to its extension's `chrome` and `browser` objects,
    /// and restricts execution to URLs matching the `ExtensionContentScriptSpec`.
    public static func wrapContentScript(
        extensionItem: InstalledExtension,
        spec: ExtensionContentScriptSpec,
        jsSource: String,
        polyfillScript: String
    ) -> String {
        let matchesData = (try? JSONEncoder().encode(spec.matches)) ?? Data("[\"<all_urls>\"]".utf8)
        let matchesJSON = String(data: matchesData, encoding: .utf8) ?? "[\"<all_urls>\"]"
        let excludesData = (try? JSONEncoder().encode(spec.excludeMatches)) ?? Data("[]".utf8)
        let excludesJSON = String(data: excludesData, encoding: .utf8) ?? "[]"
        let blockedHostsData = (try? JSONEncoder().encode(extensionItem.blockedHosts)) ?? Data("[]".utf8)
        let blockedHostsJSON = String(data: blockedHostsData, encoding: .utf8) ?? "[]"
        let allowedHostsData = (try? JSONEncoder().encode(extensionItem.customAllowedHosts)) ?? Data("[]".utf8)
        let allowedHostsJSON = String(data: allowedHostsData, encoding: .utf8) ?? "[]"
        let accessMode = extensionItem.hostAccessMode.rawValue
        let extID = escapeJSString(extensionItem.id)

        return """
        \(polyfillScript)
        (function() {
            const href = String(location.href || "");
            if (!href || href.startsWith("zhuo://") || href.startsWith("chrome://")) return;

            const host = String(location.hostname || "").toLowerCase();
            const blockedHosts = \(blockedHostsJSON);
            for (let i = 0; i < blockedHosts.length; i++) {
                const b = String(blockedHosts[i] || "").toLowerCase();
                if (b && (host === b || host.endsWith("." + b))) return;
            }

            const accessMode = "\(accessMode)";
            if (accessMode === "on_click") return;
            if (accessMode === "on_specific_sites") {
                const allowed = \(allowedHostsJSON);
                let ok = false;
                for (let i = 0; i < allowed.length; i++) {
                    const a = String(allowed[i] || "").toLowerCase();
                    if (a && (host === a || host.endsWith("." + a))) { ok = true; break; }
                }
                if (!ok) return;
            }

            function matchPattern(pattern, urlStr) {
                if (pattern === "<all_urls>" || pattern === "*://*/*") return true;
                try {
                    const u = new URL(urlStr);
                    const parts = pattern.split("://");
                    if (parts.length !== 2) return false;
                    const pScheme = parts[0].toLowerCase();
                    const uScheme = u.protocol.replace(":", "").toLowerCase();
                    if (pScheme === "*") {
                        if (uScheme !== "http" && uScheme !== "https") return false;
                    } else if (pScheme !== uScheme) {
                        return false;
                    }
                    const slashIdx = parts[1].indexOf("/");
                    if (slashIdx < 0) return false;
                    const pHost = parts[1].slice(0, slashIdx).toLowerCase();
                    const pPath = parts[1].slice(slashIdx);
                    const uHost = u.hostname.toLowerCase();
                    if (pHost !== "*") {
                        if (pHost.startsWith("*.")) {
                            const base = pHost.slice(2);
                            if (uHost !== base && !uHost.endsWith("." + base)) return false;
                        } else if (uHost !== pHost) {
                            return false;
                        }
                    }
                    if (pPath === "/*" || pPath === "*") return true;
                    const regexStr = "^" + pPath.replace(/[.+?^${}()|[\\]\\\\]/g, "\\\\$&").replace(/\\*/g, ".*") + "$";
                    return new RegExp(regexStr).test(u.pathname + u.search) || new RegExp(regexStr).test(u.pathname);
                } catch (e) {
                    return false;
                }
            }

            const matches = \(matchesJSON);
            const excludes = \(excludesJSON);
            let matched = false;
            for (let i = 0; i < matches.length; i++) {
                if (matchPattern(matches[i], href)) { matched = true; break; }
            }
            if (!matched) return;
            for (let i = 0; i < excludes.length; i++) {
                if (matchPattern(excludes[i], href)) return;
            }

            const handle = window.__ZHUO_EXTENSIONS__ && window.__ZHUO_EXTENSIONS__["\(extID)"];
            const chrome = handle ? handle.chrome : window.chrome;
            const browser = chrome;
            try {
                \(jsSource)
            } catch (err) {
                console.error("[ZhuoExtension \(extID)] content script error:", err);
            }
        })();
        """
    }

    public static func serializeJSONDictionary(_ dict: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    public static func escapeJSString(_ input: String) -> String {
        var result = input
        result = result.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "\"", with: "\\\"")
        result = result.replacingOccurrences(of: "\r", with: "\\r")
        result = result.replacingOccurrences(of: "\n", with: "\\n")
        result = result.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        result = result.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return result
    }
}
