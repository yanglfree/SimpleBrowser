import AppKit
import SwiftUI
import XCTest
@testable import ZhuoBrowserMac

final class OmniboxSuggestionTests: XCTestCase {

    // MARK: - Priority Order: Host First, Full Link Second

    func testHostSuggestionsStrictlyPrecedeFullLinkSuggestions() {
        let history = [
            HistoryEntry(
                id: "h-1",
                title: "apple/swift: The Swift Programming Language",
                url: "https://github.com/apple/swift",
                visitedAt: 1_730_000_200,
                visitCount: 5
            ),
            HistoryEntry(
                id: "h-2",
                title: "Pull requests · apple/swift",
                url: "https://github.com/apple/swift/pulls",
                visitedAt: 1_730_000_100,
                visitCount: 2
            )
        ]

        let bookmarks = [
            BookmarkEntry(
                id: "bm-1",
                title: "GitHub Android",
                url: "https://github.com/topics/android",
                createdAt: 1_730_000_000
            ),
            BookmarkEntry(
                id: "bm-2",
                title: "GitMind",
                url: "https://gitmind.cn",
                createdAt: 1_730_000_050
            )
        ]

        let results = OmniboxSuggestionPolicy.suggestions(
            for: "git",
            history: history,
            bookmarks: bookmarks,
            searchEngine: .bing,
            includeSearchSuggestion: true
        )

        // All .host items must come before any .history / .bookmark full link items
        let kinds = results.map(\.kind)
        let firstNonHostIdx = kinds.firstIndex(where: { $0 != .host }) ?? kinds.count
        let hostPrefix = Array(results[..<firstNonHostIdx])
        let remaining = Array(results[firstNonHostIdx...])

        XCTAssertEqual(hostPrefix.count, 2, "Expected both github.com and gitmind.cn hosts in Tier 1")
        XCTAssertTrue(hostPrefix.allSatisfy { $0.kind == .host })
        XCTAssertFalse(remaining.contains(where: { $0.kind == .host }))

        // Verify github.com and gitmind.cn are the Tier 1 hosts
        let hostTitles = hostPrefix.map(\.title)
        XCTAssertTrue(hostTitles.contains("github.com"))
        XCTAssertTrue(hostTitles.contains("gitmind.cn"))
        XCTAssertEqual(hostPrefix.first?.title, "github.com")
        XCTAssertEqual(hostPrefix.first?.url, "https://github.com")
        XCTAssertEqual(hostPrefix.first?.source, .historyAndBookmark)

        // Verify Tier 2 full links follow immediately after Tier 1 hosts
        let fullLinkItems = remaining.filter { $0.kind == .history || $0.kind == .bookmark }
        XCTAssertEqual(fullLinkItems.count, 3)
        let fullLinkURLs = fullLinkItems.map(\.url)
        XCTAssertTrue(fullLinkURLs.contains("https://github.com/apple/swift"))
        XCTAssertTrue(fullLinkURLs.contains("https://github.com/apple/swift/pulls"))
        XCTAssertTrue(fullLinkURLs.contains("https://github.com/topics/android"))
        // Bare root bookmark https://gitmind.cn is already represented in Tier 1, so not duplicated in Tier 2
        XCTAssertFalse(fullLinkURLs.contains("https://gitmind.cn"))
    }

    func testExtractsHostFromDeepHistoryOrBookmarkLinksEvenWithoutRootEntry() {
        let history = [
            HistoryEntry(
                id: "h-deep",
                title: "28 个 Unix/Linux 的命令行神器",
                url: "https://coolshell.cn/articles/1079.html",
                visitedAt: 1_730_000_500,
                visitCount: 3
            )
        ]
        let bookmarks = [
            BookmarkEntry(
                id: "bm-deep",
                title: "MVVM 介绍",
                url: "https://objccn.io/issue-13-1/",
                createdAt: 1_730_000_400
            )
        ]

        let coolResults = OmniboxSuggestionPolicy.suggestions(
            for: "cool",
            history: history,
            bookmarks: bookmarks,
            includeSearchSuggestion: false
        )
        XCTAssertEqual(coolResults.count, 2)
        XCTAssertEqual(coolResults[0].kind, .host)
        XCTAssertEqual(coolResults[0].title, "coolshell.cn")
        XCTAssertEqual(coolResults[0].url, "https://coolshell.cn")
        XCTAssertEqual(coolResults[1].kind, .history)
        XCTAssertEqual(coolResults[1].url, "https://coolshell.cn/articles/1079.html")

        let objcResults = OmniboxSuggestionPolicy.suggestions(
            for: "objc",
            history: history,
            bookmarks: bookmarks,
            includeSearchSuggestion: false
        )
        XCTAssertEqual(objcResults.count, 2)
        XCTAssertEqual(objcResults[0].kind, .host)
        XCTAssertEqual(objcResults[0].title, "objccn.io")
        XCTAssertEqual(objcResults[0].url, "https://objccn.io")
        XCTAssertEqual(objcResults[1].kind, .bookmark)
        XCTAssertEqual(objcResults[1].url, "https://objccn.io/issue-13-1/")
    }

    func testWWWHostAndSchemePrefixMatching() {
        let bookmarks = [
            BookmarkEntry(
                id: "bm-v2-root",
                title: "V2EX",
                url: "https://www.v2ex.com",
                createdAt: 1_730_000_100
            ),
            BookmarkEntry(
                id: "bm-v2-share",
                title: "V2EX 资源分享",
                url: "https://www.v2ex.com/go/share",
                createdAt: 1_730_000_200
            )
        ]

        // Typing "v2" without "www." matches www.v2ex.com host first, then full link
        let bareQueryResults = OmniboxSuggestionPolicy.suggestions(
            for: "v2",
            history: [],
            bookmarks: bookmarks,
            includeSearchSuggestion: false
        )
        XCTAssertEqual(bareQueryResults.count, 2)
        XCTAssertEqual(bareQueryResults[0].kind, .host)
        XCTAssertEqual(bareQueryResults[0].url, "https://www.v2ex.com")
        XCTAssertEqual(bareQueryResults[0].completionText, "v2ex.com")
        XCTAssertEqual(bareQueryResults[1].kind, .bookmark)
        XCTAssertEqual(bareQueryResults[1].url, "https://www.v2ex.com/go/share")

        // Typing "www.v2" preserves "www." in completionText
        let wwwQueryResults = OmniboxSuggestionPolicy.suggestions(
            for: "www.v2",
            history: [],
            bookmarks: bookmarks,
            includeSearchSuggestion: false
        )
        XCTAssertEqual(wwwQueryResults.first?.kind, .host)
        XCTAssertEqual(wwwQueryResults.first?.completionText, "www.v2ex.com")

        // Typing "https://www.v2" preserves scheme + www.
        let schemeQueryResults = OmniboxSuggestionPolicy.suggestions(
            for: "https://www.v2",
            history: [],
            bookmarks: bookmarks,
            includeSearchSuggestion: false
        )
        XCTAssertEqual(schemeQueryResults.first?.kind, .host)
        XCTAssertEqual(schemeQueryResults.first?.completionText, "https://www.v2ex.com")
    }

    func testPathInputTransitionsToFullLinkSuggestionsAndInlineCompletion() {
        let history = [
            HistoryEntry(
                id: "h-compose",
                title: "Jetpack Compose",
                url: "https://developer.android.com/jetpack/compose",
                visitedAt: 1_730_000_300,
                visitCount: 4
            ),
            HistoryEntry(
                id: "h-androidx",
                title: "AndroidX",
                url: "https://developer.android.com/jetpack/androidx",
                visitedAt: 1_730_000_100,
                visitCount: 1
            )
        ]
        let bookmarks = [
            BookmarkEntry(
                id: "bm-android-root",
                title: "Android Developers",
                url: "https://developer.android.com",
                createdAt: 1_730_000_000
            )
        ]

        // 1. Before typing '/', inline completion completes only the host
        let hostInline = OmniboxSuggestionPolicy.inlineCompletion(
            for: "developer.and",
            history: history,
            bookmarks: bookmarks
        )
        XCTAssertEqual(hostInline, "developer.android.com")

        // 2. When user has typed the exact host "developer.android.com" (without '/'),
        //    inline completion does not jump to a deep subpage unsolicited
        let exactHostInline = OmniboxSuggestionPolicy.inlineCompletion(
            for: "developer.android.com",
            history: history,
            bookmarks: bookmarks
        )
        XCTAssertNil(exactHostInline)

        // 3. Once user types '/' ("developer.android.com/"), suggestions & inline completion switch to Full Links
        let slashSuggestions = OmniboxSuggestionPolicy.suggestions(
            for: "developer.android.com/",
            history: history,
            bookmarks: bookmarks,
            includeSearchSuggestion: false
        )
        XCTAssertEqual(slashSuggestions.count, 2)
        XCTAssertTrue(slashSuggestions.allSatisfy { $0.kind != .host })
        XCTAssertEqual(slashSuggestions.first?.url, "https://developer.android.com/jetpack/compose")

        let pathInline = OmniboxSuggestionPolicy.inlineCompletion(
            for: "developer.android.com/",
            history: history,
            bookmarks: bookmarks
        )
        XCTAssertEqual(pathInline, "developer.android.com/jetpack/compose")

        let subPathInline = OmniboxSuggestionPolicy.inlineCompletion(
            for: "developer.android.com/jetpack/a",
            history: history,
            bookmarks: bookmarks
        )
        XCTAssertEqual(subPathInline, "developer.android.com/jetpack/androidx")
    }

    // MARK: - Session Integration & View Hosting

    @MainActor
    func testSessionOmniboxSuggestionsAndCommitFlow() {
        let session = BrowserSession()
        session.recordHistory(
            url: "https://swift.org/documentation/api-design-guidelines/",
            title: "Swift API Design Guidelines"
        )

        session.updateOmniboxSuggestions(for: "swift")
        XCTAssertTrue(session.isShowingOmniboxSuggestions)
        XCTAssertFalse(session.omniboxSuggestions.isEmpty)
        XCTAssertEqual(session.selectedOmniboxSuggestionIndex, -1)

        // Top suggestion must be a .host suggestion
        let first = session.omniboxSuggestions.first
        XCTAssertEqual(first?.kind, .host)
        XCTAssertTrue(first?.title.contains("swift") == true)

        // Full link suggestion must also be present after the host suggestions
        XCTAssertTrue(
            session.omniboxSuggestions.contains(where: {
                $0.kind == .history && $0.url == "https://swift.org/documentation/api-design-guidelines/"
            })
        )

        // Inline completion for "swi" completes the host first
        let inlineHost = session.inlineCompletion(for: "swi")
        XCTAssertNotNil(inlineHost)
        XCTAssertFalse(inlineHost?.contains("/documentation") ?? true)

        // Committing a suggestion navigates the active tab and dismisses the dropdown
        if let target = session.omniboxSuggestions.first(where: {
            $0.url == "https://swift.org/documentation/api-design-guidelines/"
        }) {
            session.commitOmniboxSuggestion(target)
            XCTAssertFalse(session.isShowingOmniboxSuggestions)
            XCTAssertEqual(session.activeTab?.url, "https://swift.org/documentation/api-design-guidelines/")
        }

        // Verify OmniboxSuggestionsDropdownView hosts cleanly
        let sampleSuggestions = session.suggestions(for: "git")
        let dropdown = OmniboxSuggestionsDropdownView(
            session: session,
            suggestions: sampleSuggestions,
            selectedIndex: 0,
            onSelect: { _ in }
        )
        let dropdownHost = NSHostingView(rootView: dropdown)
        dropdownHost.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        XCTAssertNotNil(dropdownHost)
    }

    @MainActor
    func testEnteringURLNavigatesDirectlyInsteadOfSearching() {
        let session = BrowserSession()
        session.settings.searchEngine = .google

        // User types an unvisited domain "wpx.youdroid.top" and presses Enter
        session.updateOmniboxSuggestions(for: "wpx.youdroid.top")
        XCTAssertFalse(
            session.omniboxSuggestions.contains(where: { $0.kind == .search }),
            "Autocomplete dropdown must not inject a search item that hijacks URL submission"
        )
        session.submitOmniboxInput("wpx.youdroid.top")
        XCTAssertEqual(
            LibraryPolicy.normalizeComparableURL(session.activeTab?.url ?? ""),
            "https://wpx.youdroid.top"
        )
        XCTAssertFalse(session.activeTab?.url.contains("google.com") ?? true)

        // Even if a .search suggestion were present at index 0, resolveSubmissionTarget must never
        // hijack a URL input to a search engine query URL
        let fallbackSuggestions = OmniboxSuggestionPolicy.suggestions(
            for: "wpx.youdroid.top",
            history: [],
            bookmarks: [],
            searchEngine: .google,
            includeSearchSuggestion: true
        )
        let resolvedTarget = OmniboxSuggestionPolicy.resolveSubmissionTarget(
            for: "wpx.youdroid.top",
            suggestions: fallbackSuggestions,
            selectedIndex: 0
        )
        XCTAssertEqual(resolvedTarget, "wpx.youdroid.top")
        XCTAssertEqual(
            URLPolicy.normalizeAddress(resolvedTarget, searchEngine: .google),
            "https://wpx.youdroid.top"
        )
    }

    @MainActor
    func testPublicHostWithLegacyHTTPHistoryUpgradesToHTTPSWhileLocalhostPreservesHTTP() {
        let session = BrowserSession()
        session.recordHistory(
            url: "http://wpx.youdroid.top/",
            title: "卓乐云文档"
        )
        session.recordHistory(
            url: "http://localhost:5173/",
            title: "Local Dev"
        )

        // 1. Public domain host candidate upgrades to https:// even if history had http://
        session.updateOmniboxSuggestions(for: "wpx.youdroid.top")
        XCTAssertEqual(session.omniboxSuggestions.first?.kind, .host)
        XCTAssertEqual(session.omniboxSuggestions.first?.url, "https://wpx.youdroid.top")

        session.submitOmniboxInput("wpx.youdroid.top")
        XCTAssertEqual(
            LibraryPolicy.normalizeComparableURL(session.activeTab?.url ?? ""),
            "https://wpx.youdroid.top"
        )

        // 2. Localhost preserves http:// when recorded as http://
        session.updateOmniboxSuggestions(for: "localhost")
        XCTAssertEqual(session.omniboxSuggestions.first?.kind, .host)
        XCTAssertEqual(session.omniboxSuggestions.first?.url, "http://localhost:5173")
    }

    @MainActor
    func testSuggestionPanelPositionsDirectlyBelowOmniboxAnchor() {
        let session = BrowserSession()
        session.recordHistory(url: "https://github.com/apple/swift", title: "Swift")

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 300, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        window.contentView = contentView

        let anchorView = OmniboxAnchorNSView(frame: NSRect(x: 180, y: 556, width: 540, height: 28))
        contentView.addSubview(anchorView)
        contentView.layoutSubtreeIfNeeded()

        let controller = OmniboxSuggestionPanelController()
        let suggestions = session.suggestions(for: "git")
        XCTAssertFalse(suggestions.isEmpty)

        controller.update(
            anchorView: anchorView,
            session: session,
            suggestions: suggestions,
            selectedIndex: -1,
            isPresented: true,
            onSelect: { _ in }
        )

        let anchorScreenRect = window.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
        guard let panelFrame = controller.currentPanelFrame else {
            XCTFail("Expected suggestion child panel frame to be created")
            return
        }

        XCTAssertTrue(controller.isPanelVisible)
        XCTAssertEqual(panelFrame.minX, round(anchorScreenRect.minX), accuracy: 1.0)
        XCTAssertEqual(panelFrame.width, round(anchorScreenRect.width), accuracy: 1.0)
        XCTAssertEqual(
            panelFrame.maxY,
            round(anchorScreenRect.minY - OmniboxSuggestionPanelController.verticalGap),
            accuracy: 1.0,
            "Top edge of suggestion panel must sit directly below the bottom edge of the omnibox"
        )

        controller.hide()
        XCTAssertFalse(controller.isPanelVisible)
    }
}
