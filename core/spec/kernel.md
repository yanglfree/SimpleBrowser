# BrowserKernel

Cross-platform method table. Harmony implements this in
`entry/src/main/ets/services/WebKernelService.ets`. iOS and Android each
provide a native port. Policy helpers that do not touch a controller live in
`core/src/kernel-policy.mjs` and must stay behavior-identical.

Native home (`browser://home`) is never passed to the kernel.

| Method | Harmony | iOS | Android |
|---|---|---|---|
| `load(url)` | `controller.loadUrl` | `WKWebView.load` | `WebView.loadUrl` |
| `reload(force)` | `refresh` / `removeCache` | `reload` | `reload` |
| `stop()` | `stop` | `stopLoading` | `stopLoading` |
| `goBack()` | `backward` | `goBack` | `goBack` |
| `goForward()` | `forward` | `goForward` | `goForward` |
| `goBackBySteps(step)` | `backOrForward` | `go(to:)` | `copyBackForwardList` + load |
| `canGoBack` / `canGoForward` | `accessBackward` / `accessForward` | `canGoBack` / `canGoForward` | same |
| `findAll(query)` | `searchAllAsync` | `WKFindConfiguration` | `findAllAsync` |
| `findNext(forward)` | `searchNext` | `findNext` | `findNext` |
| `clearFind()` | `clearMatches` | `find(nil)` | `clearMatches` |
| `applyUserAgent(isDesktop)` | `setCustomUserAgent` | `customUserAgent` | `settings.userAgentString` |
| `runJavaScript(source)` | `runJavaScript` | `evaluateJavaScript` | `evaluateJavascript` |
| `injectDocumentStart(source)` | `javaScriptOnDocumentStart` | `WKUserScript(.atDocumentStart)` | `WebViewCompat.addDocumentStartJavaScript` |
| `setPrivate(isPrivate)` | `incognitoMode` | `WKWebsiteDataStore.nonPersistent()` | ephemeral profile |
| `setBlockAds(enabled)` | `AdsBlockManager` + `enableAdsBlock` | `WKContentRuleList` | `shouldInterceptRequest` |
| `setAllowedHosts(hosts)` | `addAdsBlockAllowedList` | remove matching content rules | skip intercept |
| `flushCookies()` | `saveCookieSync` | `WKHTTPCookieStore` | `CookieManager.flush` |
| `clearPrivateData()` | cookie/storage incognito clear | remove non-persistent store | clear profile |
| `downloadDelegate` | `WebDownloadManager` | `WKDownload` + `URLSession` | `DownloadManager` |

Pure helpers (no controller): `clampProgress`, `isBackwardStep`,
`shouldRefreshNavigationState`, `canNavigateBack`, `shouldReturnHomeOnBack`,
`userAgentFor`, `desktopUrlFor`.
