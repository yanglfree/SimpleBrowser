import AppKit
import Combine
import SwiftUI
import WebKit
import XCTest
@testable import ZhuoBrowserMac

@MainActor
final class ProfileTests: XCTestCase {
    private var createdPersistentStoreIDs: [UUID] = []

    override func tearDown() {
        WebPopupWindowManager.shared.closeAllPopups()
        let idsToRemove = createdPersistentStoreIDs
        createdPersistentStoreIDs.removeAll()
        for id in idsToRemove {
            let exp = expectation(description: "cleanup data store \(id)")
            WKWebsiteDataStore.remove(forIdentifier: id) { _ in
                exp.fulfill()
            }
            wait(for: [exp], timeout: 5.0)
        }
        super.tearDown()
    }

    private func makeTempDirectory(prefix: String = "ProfileTests") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeGoogleCookie(name: String, value: String, domain: String = ".google.com") -> HTTPCookie {
        HTTPCookie(properties: [
            .name: name,
            .value: value,
            .domain: domain,
            .path: "/",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(3600)
        ])!
    }

    // MARK: - 1. Model & Palette Tests

    func testBrowserProfileCodableAndDisplayHelpers() throws {
        let profile = BrowserProfile(
            name: "  工作账号  ",
            avatarSymbol: "briefcase.fill",
            colorHex: "#10B981",
            isDefault: false
        )

        XCTAssertEqual(profile.displayName, "工作账号")
        XCTAssertEqual(profile.shortInitial, "工")

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(BrowserProfile.self, from: data)
        XCTAssertEqual(decoded, profile)

        let blankProfile = BrowserProfile(name: "   ", isDefault: true)
        XCTAssertEqual(blankProfile.displayName, "个人")
    }

    // MARK: - 2. ProfileManager Persistence & CRUD Tests

    func testProfileManagerSeedsDefaultAndPersistsCreatedProfiles() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager1 = ProfileManager(
            rootDirectory: tempDir,
            isPersistenceEnabled: true,
            usesPersistentDataStores: false
        )
        XCTAssertEqual(manager1.profiles.count, 1)
        XCTAssertTrue(manager1.defaultProfile.isDefault)
        XCTAssertEqual(manager1.defaultProfile.displayName, "个人")

        let work = manager1.createProfile(name: "工作 Google", avatarSymbol: "briefcase.fill", colorHex: "#10B981")
        XCTAssertEqual(manager1.profiles.count, 2)
        XCTAssertFalse(work.isDefault)

        manager1.updateProfile(id: work.id, name: "工作账号", avatarSymbol: "star.fill", colorHex: "#8B5CF6")

        // Reload from disk in a fresh manager instance
        let manager2 = ProfileManager(
            rootDirectory: tempDir,
            isPersistenceEnabled: true,
            usesPersistentDataStores: false
        )
        XCTAssertEqual(manager2.profiles.count, 2)
        let reloadedWork = try XCTUnwrap(manager2.existingProfile(for: work.id))
        XCTAssertEqual(reloadedWork.displayName, "工作账号")
        XCTAssertEqual(reloadedWork.avatarSymbol, "star.fill")
        XCTAssertEqual(reloadedWork.colorHex, "#8B5CF6")
        XCTAssertFalse(reloadedWork.isDefault)
    }

    func testDefaultProfileCannotBeDeletedWhileCustomProfileDeletesCleanly() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ProfileManager(
            rootDirectory: tempDir,
            isPersistenceEnabled: true,
            usesPersistentDataStores: false
        )

        XCTAssertFalse(manager.deleteProfile(id: manager.defaultProfile.id))
        XCTAssertEqual(manager.profiles.count, 1)

        let second = manager.createProfile(name: "Google 账号 2")
        let session2 = manager.session(for: second.id)
        session2.navigate(to: "https://accounts.google.com")
        session2.recordHistory(url: "https://accounts.google.com", title: "Sign in")

        let secondDir = manager.storageDirectoryURL(for: second)
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondDir.path))

        XCTAssertTrue(manager.deleteProfile(id: second.id))
        XCTAssertEqual(manager.profiles.count, 1)
        XCTAssertNil(manager.loadedSession(for: second.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDir.path))
    }

    // MARK: - 3. Multi-Google-Account WebKit & Storage Isolation Tests

    func testWebKitDataStoresIsolateGoogleCookiesBetweenProfiles() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ProfileManager(
            rootDirectory: tempDir,
            isPersistenceEnabled: true,
            usesPersistentDataStores: true
        )
        let profileA = manager.createProfile(name: "Google A")
        let profileB = manager.createProfile(name: "Google B")
        createdPersistentStoreIDs.append(contentsOf: [profileA.id, profileB.id])

        let storeA = manager.websiteDataStore(for: profileA)
        let storeB = manager.websiteDataStore(for: profileB)

        XCTAssertFalse(storeA === storeB)
        XCTAssertFalse(storeA === WKWebsiteDataStore.default())
        XCTAssertFalse(storeB === WKWebsiteDataStore.default())
        XCTAssertTrue(storeA.isPersistent)
        XCTAssertTrue(storeB.isPersistent)

        let cookieA = makeGoogleCookie(name: "SID", value: "account_a_secret_token")
        let cookieB = makeGoogleCookie(name: "SID", value: "account_b_secret_token")

        let setGroup = DispatchGroup()
        setGroup.enter()
        storeA.httpCookieStore.setCookie(cookieA) { setGroup.leave() }
        setGroup.enter()
        storeB.httpCookieStore.setCookie(cookieB) { setGroup.leave() }

        let setExp = expectation(description: "set cookies")
        setGroup.notify(queue: .main) { setExp.fulfill() }
        wait(for: [setExp], timeout: 5.0)

        let readExpA = expectation(description: "read cookies A")
        var cookiesA: [HTTPCookie] = []
        storeA.httpCookieStore.getAllCookies { list in
            cookiesA = list
            readExpA.fulfill()
        }

        let readExpB = expectation(description: "read cookies B")
        var cookiesB: [HTTPCookie] = []
        storeB.httpCookieStore.getAllCookies { list in
            cookiesB = list
            readExpB.fulfill()
        }
        wait(for: [readExpA, readExpB], timeout: 5.0)

        XCTAssertEqual(cookiesA.first(where: { $0.name == "SID" })?.value, "account_a_secret_token")
        XCTAssertEqual(cookiesB.first(where: { $0.name == "SID" })?.value, "account_b_secret_token")

        // Clearing website data in Profile A must NOT remove Profile B's Google session
        let sessionA = manager.session(for: profileA.id)
        let sessionB = manager.session(for: profileB.id)
        sessionA.webSessionStorageStore.updateEntries(["user": "a@gmail.com"], forOrigin: "https://accounts.google.com")
        sessionB.webSessionStorageStore.updateEntries(["user": "b@gmail.com"], forOrigin: "https://accounts.google.com")

        let clearExp = expectation(description: "clear profile A data")
        sessionA.clearWebsiteData(clearCookies: true, clearCache: true) {
            clearExp.fulfill()
        }
        wait(for: [clearExp], timeout: 5.0)

        XCTAssertTrue(sessionA.webSessionStorageStore.entries(forOrigin: "https://accounts.google.com").isEmpty)
        XCTAssertEqual(
            sessionB.webSessionStorageStore.entries(forOrigin: "https://accounts.google.com")["user"],
            "b@gmail.com"
        )

        let verifyBExp = expectation(description: "verify cookies B intact")
        var postClearCookiesB: [HTTPCookie] = []
        storeB.httpCookieStore.getAllCookies { list in
            postClearCookiesB = list
            verifyBExp.fulfill()
        }
        wait(for: [verifyBExp], timeout: 5.0)
        XCTAssertEqual(postClearCookiesB.first(where: { $0.name == "SID" })?.value, "account_b_secret_token")
    }

    func testProfilesIsolateBookmarksHistorySessionStorageAndTabs() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ProfileManager(
            rootDirectory: tempDir,
            isPersistenceEnabled: true,
            usesPersistentDataStores: false
        )
        let defaultSession = manager.session(for: manager.defaultProfile.id)
        let workProfile = manager.createProfile(name: "工作")
        let workSession = manager.session(for: workProfile.id)

        defaultSession.addBookmark(url: "https://personal.example.com", title: "Personal Only")
        defaultSession.recordHistory(url: "https://mail.google.com/mail/u/0", title: "Personal Gmail")
        defaultSession.webSessionStorageStore.updateEntries(["uid": "personal"], forOrigin: "https://aistudio.google.com")

        workSession.addBookmark(url: "https://work.example.com", title: "Work Only")
        workSession.recordHistory(url: "https://mail.google.com/mail/u/1", title: "Work Gmail")
        workSession.webSessionStorageStore.updateEntries(["uid": "work"], forOrigin: "https://aistudio.google.com")

        XCTAssertTrue(defaultSession.isBookmarked(url: "https://personal.example.com"))
        XCTAssertFalse(defaultSession.isBookmarked(url: "https://work.example.com"))
        XCTAssertTrue(workSession.isBookmarked(url: "https://work.example.com"))
        XCTAssertFalse(workSession.isBookmarked(url: "https://personal.example.com"))

        XCTAssertEqual(
            defaultSession.webSessionStorageStore.entries(forOrigin: "https://aistudio.google.com")["uid"],
            "personal"
        )
        XCTAssertEqual(
            workSession.webSessionStorageStore.entries(forOrigin: "https://aistudio.google.com")["uid"],
            "work"
        )

        XCTAssertFalse(defaultSession.favoritesManager === workSession.favoritesManager)
    }

    // MARK: - 4. OAuth Popup Isolation Tests

    func testGoogleOAuthPopupInheritsProfileWebsiteDataStore() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ProfileManager(
            rootDirectory: tempDir,
            isPersistenceEnabled: true,
            usesPersistentDataStores: true
        )
        let profileA = manager.createProfile(name: "Account A")
        let profileB = manager.createProfile(name: "Account B")
        createdPersistentStoreIDs.append(contentsOf: [profileA.id, profileB.id])

        let sessionA = manager.session(for: profileA.id)
        let sessionB = manager.session(for: profileB.id)
        sessionB.createTab(url: "https://example.com/app", select: true)

        guard let controllerB = sessionB.activeController,
              let webViewB = controllerB.webView else {
            return XCTFail("Profile B active tab controller and WebView must exist")
        }

        XCTAssertTrue(webViewB.configuration.websiteDataStore === sessionB.websiteDataStore)
        XCTAssertFalse(webViewB.configuration.websiteDataStore === sessionA.websiteDataStore)

        let oauthURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=123")!
        let popupController = WebPopupWindowManager.shared.openPopup(
            url: oauthURL,
            parentWindow: nil,
            websiteDataStore: webViewB.configuration.websiteDataStore
        )
        XCTAssertTrue(popupController.webView.configuration.websiteDataStore === sessionB.websiteDataStore)
        XCTAssertFalse(popupController.webView.configuration.websiteDataStore === sessionA.websiteDataStore)

        class MockOAuthNavAction: WKNavigationAction {
            let req: URLRequest
            init(req: URLRequest) {
                self.req = req
                super.init()
            }
            override var request: URLRequest { req }
            override var targetFrame: WKFrameInfo? { nil }
        }

        let createdPopupWebView = controllerB.webView(
            webViewB,
            createWebViewWith: webViewB.configuration,
            for: MockOAuthNavAction(req: URLRequest(url: oauthURL)),
            windowFeatures: WKWindowFeatures()
        )
        XCTAssertNotNil(createdPopupWebView)
        XCTAssertTrue(createdPopupWebView?.configuration.websiteDataStore === sessionB.websiteDataStore)
    }

    func testRealWebViewsIsolateLocalStorageSessionStorageAndDocumentCookiesAcrossProfiles() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ProfileManager(
            rootDirectory: tempDir,
            isPersistenceEnabled: true,
            usesPersistentDataStores: true
        )
        let profileA = manager.createProfile(name: "Google 1")
        let profileB = manager.createProfile(name: "Google 2")
        createdPersistentStoreIDs.append(contentsOf: [profileA.id, profileB.id])

        let sessionA = manager.session(for: profileA.id)
        let sessionB = manager.session(for: profileB.id)

        sessionA.createTab(url: "https://accounts.google.com/signin", select: true)
        sessionB.createTab(url: "https://accounts.google.com/signin", select: true)

        let webViewA = try XCTUnwrap(sessionA.activeController?.webView)
        let webViewB = try XCTUnwrap(sessionB.activeController?.webView)
        let delegateA = ProfileWebViewDelegate()
        let delegateB = ProfileWebViewDelegate()
        webViewA.navigationDelegate = delegateA
        webViewB.navigationDelegate = delegateB

        let googleOrigin = URL(string: "https://accounts.google.com/ServiceLogin")!

        let loadA = expectation(description: "load html A")
        delegateA.onFinish = { loadA.fulfill() }
        webViewA.loadHTMLString("<html><body>Profile A</body></html>", baseURL: googleOrigin)

        let loadB = expectation(description: "load html B")
        delegateB.onFinish = { loadB.fulfill() }
        webViewB.loadHTMLString("<html><body>Profile B</body></html>", baseURL: googleOrigin)
        wait(for: [loadA, loadB], timeout: 5.0)

        let writeA = expectation(description: "write storage A")
        webViewA.evaluateJavaScript("""
            localStorage.setItem('google_user', 'alice@gmail.com');
            sessionStorage.setItem('oauth_state', 'state_alice');
            document.cookie = 'G_AUTHUSER_H=alice; path=/; Secure';
            'ok'
        """) { _, error in
            XCTAssertNil(error)
            writeA.fulfill()
        }

        let writeB = expectation(description: "write storage B")
        webViewB.evaluateJavaScript("""
            localStorage.setItem('google_user', 'bob@gmail.com');
            sessionStorage.setItem('oauth_state', 'state_bob');
            document.cookie = 'G_AUTHUSER_H=bob; path=/; Secure';
            'ok'
        """) { _, error in
            XCTAssertNil(error)
            writeB.fulfill()
        }
        wait(for: [writeA, writeB], timeout: 5.0)

        let readA = expectation(description: "read storage A")
        var snapshotA: [String: String] = [:]
        webViewA.evaluateJavaScript("""
            JSON.stringify({
                local: localStorage.getItem('google_user') || '',
                session: sessionStorage.getItem('oauth_state') || '',
                cookie: document.cookie || ''
            })
        """) { result, _ in
            if let str = result as? String,
               let data = str.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                snapshotA = dict
            }
            readA.fulfill()
        }

        let readB = expectation(description: "read storage B")
        var snapshotB: [String: String] = [:]
        webViewB.evaluateJavaScript("""
            JSON.stringify({
                local: localStorage.getItem('google_user') || '',
                session: sessionStorage.getItem('oauth_state') || '',
                cookie: document.cookie || ''
            })
        """) { result, _ in
            if let str = result as? String,
               let data = str.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                snapshotB = dict
            }
            readB.fulfill()
        }
        wait(for: [readA, readB], timeout: 5.0)

        XCTAssertEqual(snapshotA["local"], "alice@gmail.com")
        XCTAssertEqual(snapshotA["session"], "state_alice")
        XCTAssertTrue(snapshotA["cookie"]?.contains("G_AUTHUSER_H=alice") == true)
        XCTAssertFalse(snapshotA["cookie"]?.contains("bob") == true)

        XCTAssertEqual(snapshotB["local"], "bob@gmail.com")
        XCTAssertEqual(snapshotB["session"], "state_bob")
        XCTAssertTrue(snapshotB["cookie"]?.contains("G_AUTHUSER_H=bob") == true)
        XCTAssertFalse(snapshotB["cookie"]?.contains("alice") == true)
    }

    func testWindowRegistrationTracksFocusedAndOpenProfiles() {
        let manager = ProfileManager(isPersistenceEnabled: false)
        let profileB = manager.createProfile(name: "工作")

        let winA = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let winB = NSWindow(
            contentRect: NSRect(x: 50, y: 50, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        winA.isReleasedWhenClosed = false
        winB.isReleasedWhenClosed = false

        manager.registerWindow(winA, forProfileID: manager.defaultProfile.id)
        manager.registerWindow(winB, forProfileID: profileB.id)
        XCTAssertEqual(manager.openProfileIDs, Set([manager.defaultProfile.id, profileB.id]))

        manager.markProfileFocused(profileB.id)
        XCTAssertEqual(manager.focusedProfileID, profileB.id)
        XCTAssertTrue(manager.focusedSession === manager.session(for: profileB.id))

        let tabB = manager.session(for: profileB.id).createTab(url: "https://mail.google.com", select: true)
        XCTAssertTrue(manager.session(containingTabID: tabB.id) === manager.session(for: profileB.id))

        manager.handleWindowClosing(forProfileID: profileB.id)
        XCTAssertEqual(manager.openProfileIDs, Set([manager.defaultProfile.id]))
        XCTAssertEqual(manager.focusedProfileID, manager.defaultProfile.id)
    }

    // MARK: - 5. UI Hosting Smoke Tests

    func testProfileViewsHostCleanly() {
        let manager = ProfileManager(isPersistenceEnabled: false)
        _ = manager.createProfile(name: "工作")
        let session = manager.defaultSession

        let toolbarHost = NSHostingView(rootView: UnifiedToolbarView(session: session))
        toolbarHost.frame = NSRect(x: 0, y: 0, width: 1100, height: 38)
        toolbarHost.layoutSubtreeIfNeeded()
        XCTAssertEqual(toolbarHost.frame.height, 38)

        let popoverHost = NSHostingView(
            rootView: ProfileSwitcherPopoverView(
                session: session,
                profileManager: manager,
                isPresented: .constant(true),
                onOpenProfile: { _ in }
            )
        )
        popoverHost.frame = NSRect(x: 0, y: 0, width: 300, height: 360)
        popoverHost.layoutSubtreeIfNeeded()
        XCTAssertEqual(popoverHost.frame.width, 300)

        let editorHost = NSHostingView(
            rootView: ProfileEditorSheetView(
                profileManager: manager,
                mode: .create,
                isPresented: .constant(true)
            )
        )
        editorHost.frame = NSRect(x: 0, y: 0, width: 400, height: 420)
        editorHost.layoutSubtreeIfNeeded()
        XCTAssertEqual(editorHost.frame.width, 400)

        let managerHost = NSHostingView(
            rootView: ProfileManagerSheetView(
                session: session,
                profileManager: manager,
                isPresented: .constant(true),
                onOpenProfile: { _ in }
            )
        )
        managerHost.frame = NSRect(x: 0, y: 0, width: 520, height: 460)
        managerHost.layoutSubtreeIfNeeded()
        XCTAssertEqual(managerHost.frame.width, 520)
    }

    // MARK: - 6. FocusedMenuState Tests

    func testFocusedMenuStateSyncsHistoryRecordingBackfillRemovalAndClear() throws {
        let tempDir = try makeTempDirectory(prefix: "MenuStateHistory")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ProfileManager(
            rootDirectory: tempDir,
            isPersistenceEnabled: false,
            usesPersistentDataStores: false
        )
        let menuState = FocusedMenuState(profileManager: manager)
        let session = manager.defaultSession

        XCTAssertTrue(menuState.snapshot.recentHistory.isEmpty)
        XCTAssertTrue(menuState.snapshot.isHistoryEmpty)

        for i in 1...12 {
            session.recordHistory(url: "https://site\(i).example.com/page", title: "Site \(i)")
        }
        XCTAssertEqual(menuState.snapshot.recentHistory.count, 10)
        XCTAssertEqual(
            menuState.snapshot.recentHistory.map(\.entry),
            Array(session.history.prefix(10))
        )
        XCTAssertFalse(menuState.snapshot.isHistoryEmpty)

        // Placeholder title backfill updates menu item title in place
        session.recordHistory(url: "https://spa-app.example.com/home", title: "")
        XCTAssertEqual(menuState.snapshot.recentHistory.first?.displayTitle, "spa-app.example.com")
        session.updateHistoryTitleIfNeeded(url: "https://spa-app.example.com/home", title: "SPA Console")
        XCTAssertEqual(menuState.snapshot.recentHistory.first?.displayTitle, "SPA Console")

        // Removing the top history item immediately shifts the menu slice
        let topID = try XCTUnwrap(session.history.first?.id)
        session.removeHistoryItem(id: topID)
        XCTAssertEqual(
            menuState.snapshot.recentHistory.map(\.entry),
            Array(session.history.prefix(10))
        )
        XCTAssertEqual(menuState.snapshot.recentHistory.first?.displayTitle, "Site 12")

        // Clearing history updates both recentHistory and isHistoryEmpty
        session.clearHistory()
        XCTAssertTrue(menuState.snapshot.recentHistory.isEmpty)
        XCTAssertTrue(menuState.snapshot.isHistoryEmpty)
    }

    func testFocusedMenuStateIgnoresHighFrequencyNonMenuUpdates() throws {
        let tempDir = try makeTempDirectory(prefix: "MenuStateHighFreq")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ProfileManager(
            rootDirectory: tempDir,
            isPersistenceEnabled: false,
            usesPersistentDataStores: false
        )
        let menuState = FocusedMenuState(profileManager: manager)
        let session = manager.defaultSession

        // Navigate to a real page and mark it loading so initial menu state settles
        let tab = session.createTab(url: "https://example.com", select: true)
        session.updateTab(tab.id) { t in
            t.isLoading = true
            t.loadingProgress = 0.1
        }
        session.findQuery = "a"

        var emissionCount = 0
        let cancellable = menuState.objectWillChange.sink { _ in
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        // High-frequency typing in omnibox
        session.omniboxText = "h"
        session.omniboxText = "ht"
        session.omniboxText = "https://example.com"

        // Progress ticks while isLoading remains true
        session.updateTab(tab.id) { $0.loadingProgress = 0.35 }
        session.updateTab(tab.id) { $0.loadingProgress = 0.65 }
        session.updateTab(tab.id) { $0.loadingProgress = 0.90 }

        // Typing inside non-empty findQuery
        session.findQuery = "ab"
        session.findQuery = "abc"

        // Re-focusing the already-focused profile updates lastActiveAt only
        manager.markProfileFocused(manager.defaultProfile.id)

        XCTAssertEqual(emissionCount, 0)
    }

    func testFocusedMenuStateSwitchesSessionWhenFocusedProfileChanges() throws {
        let tempDir = try makeTempDirectory(prefix: "MenuStateProfileSwitch")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ProfileManager(
            rootDirectory: tempDir,
            isPersistenceEnabled: false,
            usesPersistentDataStores: false
        )
        let workProfile = manager.createProfile(name: "工作")
        let personalSession = manager.defaultSession
        let workSession = manager.session(for: workProfile.id)

        personalSession.recordHistory(url: "https://personal.example.com", title: "Personal Home")
        workSession.recordHistory(url: "https://work.example.com", title: "Work Console")

        let menuState = FocusedMenuState(profileManager: manager)
        XCTAssertEqual(menuState.snapshot.recentHistory.map(\.displayTitle), ["Personal Home"])
        XCTAssertEqual(menuState.snapshot.focusedProfileID, manager.defaultProfile.id)

        // Switching focus switches snapshot and stops observing the old session
        manager.markProfileFocused(workProfile.id)
        XCTAssertEqual(menuState.snapshot.focusedProfileID, workProfile.id)
        XCTAssertEqual(menuState.snapshot.recentHistory.map(\.displayTitle), ["Work Console"])
        XCTAssertTrue(menuState.currentSession === workSession)

        // Mutating old session does not alter focused menu state
        personalSession.recordHistory(url: "https://personal-2.example.com", title: "Personal 2")
        XCTAssertEqual(menuState.snapshot.recentHistory.map(\.displayTitle), ["Work Console"])

        // Mutating newly focused session updates menu state immediately
        workSession.recordHistory(url: "https://work-2.example.com", title: "Work Docs")
        XCTAssertEqual(menuState.snapshot.recentHistory.map(\.displayTitle), ["Work Docs", "Work Console"])
    }

    func testFocusedMenuStateUpdatesBookmarkFoldersAndUngroupedBookmarks() throws {
        defer { FavoritesManager.shared.resetToDefaults() }
        let tempDir = try makeTempDirectory(prefix: "MenuStateBookmarks")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ProfileManager(
            rootDirectory: tempDir,
            isPersistenceEnabled: false,
            usesPersistentDataStores: false
        )
        let menuState = FocusedMenuState(profileManager: manager)
        let session = manager.defaultSession

        let folder = try XCTUnwrap(session.createBookmarkFolder(name: "常用工具"))
        XCTAssertTrue(menuState.snapshot.bookmarkFolders.contains(where: { $0.folderID == folder.id && $0.name == "常用工具" }))

        _ = session.addBookmark(url: "https://docs.swift.org", title: "Swift Docs", folderID: folder.id)
        let updatedFolder = try XCTUnwrap(menuState.snapshot.bookmarkFolders.first(where: { $0.folderID == folder.id }))
        XCTAssertEqual(updatedFolder.items.map(\.displayTitle), ["Swift Docs"])

        _ = session.addBookmark(url: "https://news.ycombinator.com", title: "Hacker News", folderID: nil)
        XCTAssertTrue(menuState.snapshot.ungroupedBookmarks.contains(where: { $0.url == "https://news.ycombinator.com" && $0.displayTitle == "Hacker News" }))
    }
}

private final class ProfileWebViewDelegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }
}
