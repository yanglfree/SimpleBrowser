import { webview } from '@kit.ArkWeb';
import { BrowserWebView } from '../components/BrowserWebView';
import {
  CONTENT_CLEANUP_SCRIPT,
  DARK_MODE_SCRIPT,
  HOME_URL,
  LIGHT_MODE_SCRIPT,
  READER_MODE_SCRIPT
} from '../constants/AppConstants';
import {
  Bookmark,
  BrowserSettings,
  BrowserTab,
  HistoryEntry,
  cloneBookmark,
  cloneHistoryEntry,
  cloneSettings,
  cloneTab
} from '../models/BrowserModels';
import { AppContext } from '../utils/AppContext';
import { displayHost, normalizeAddress } from '../utils/UrlUtils';
import { Logger } from '../utils/Logger';
import { BrowserViewModel } from '../viewmodels/BrowserViewModel';

const TAG: string = 'Index';
type LibrarySection = 'bookmarks' | 'history';

@Entry
@Component
struct Index {
  private viewModel: BrowserViewModel = new BrowserViewModel();
  private controllers: Map<string, webview.WebviewController> = new Map();
  @State private isReady: boolean = false;
  @State private errorMessage: string = '';
  @State private tabs: BrowserTab[] = [];
  @State private bookmarks: Bookmark[] = [];
  @State private history: HistoryEntry[] = [];
  @State private settings: BrowserSettings = {
    isAdsBlockingEnabled: true,
    isDarkModeEnabled: false,
    isDesktopModeEnabled: false
  };
  @State private activeTabId: string = '';
  @State private addressText: string = HOME_URL;
  @State private showLibrary: boolean = false;
  @State private showSettings: boolean = false;
  @State private librarySection: LibrarySection = 'bookmarks';
  @State private isReaderModeEnabled: boolean = false;

  async aboutToAppear(): Promise<void> {
    try {
      await this.viewModel.initialize(AppContext.getContext());
      this.syncState();
      this.isReady = true;
    } catch (error) {
      Logger.error(TAG, `Failed to initialize browser: ${String(error)}`);
      this.errorMessage = 'initialization_error';
    }
  }

  onBackPress(): boolean {
    if (this.showLibrary || this.showSettings) {
      this.showLibrary = false;
      this.showSettings = false;
      return true;
    }
    const controller: webview.WebviewController | undefined = this.activeController();
    try {
      if (controller !== undefined && controller.accessBackward()) {
        controller.backward();
        return true;
      }
    } catch (error) {
      Logger.warn(TAG, `Back navigation failed: ${String(error)}`);
    }
    return false;
  }

  build() {
    Column() {
      this.Header()
      this.TabStrip()
      this.AddressToolbar()
      if (!this.isReady) {
        this.LoadingView()
      } else if (this.errorMessage.length > 0) {
        this.ErrorView()
      } else if (this.showLibrary) {
        this.LibraryView()
      } else if (this.showSettings) {
        this.SettingsView()
      } else {
        this.WebContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private Header() {
    Row() {
      Column() {
        Text($r('app.string.brand_clear'))
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.accent'))
        Text($r('app.string.brand_browser'))
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.viewModel.getActiveTab()?.isPrivate === true) {
        Text($r('app.string.incognito'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ right: 12 })
      }
      Button('+')
        .fontSize(22)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_elevated'))
        .borderRadius(18)
        .width(38)
        .height(38)
        .onClick(() => this.createTab(false))
      Button('⋯')
        .fontSize(22)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor(Color.Transparent)
        .width(42)
        .height(38)
        .onClick(() => this.openSettings())
    }
    .width('100%')
    .padding({ left: 16, right: 10, top: 10, bottom: 8 })
  }

  @Builder
  private TabStrip() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.tabs, (tab: BrowserTab) => {
          Row() {
            Text(tab.isPrivate ? '◌' : '○')
              .fontSize(12)
              .fontColor(tab.id === this.activeTabId ? $r('app.color.accent') : $r('app.color.text_secondary'))
            Text(tab.title.length > 0 ? tab.title : displayHost(tab.url))
              .fontSize(13)
              .fontColor(tab.id === this.activeTabId ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text('×')
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
              .onClick(() => this.closeTab(tab.id))
          }
          .width(152)
          .height(34)
          .padding({ left: 10, right: 8 })
          .borderRadius(8)
          .backgroundColor(tab.id === this.activeTabId ? $r('app.color.surface_elevated') : Color.Transparent)
          .onClick(() => this.selectTab(tab.id))
        }, (tab: BrowserTab) => tab.id)
      }
      .padding({ left: 12, right: 12 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(42)
  }

  @Builder
  private AddressToolbar() {
    Row({ space: 5 }) {
      Button('‹')
        .fontSize(25)
        .fontColor(this.canGoBack() ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .backgroundColor(Color.Transparent)
        .width(34)
        .height(38)
        .enabled(this.canGoBack())
        .onClick(() => this.goBack())
      Button('›')
        .fontSize(25)
        .fontColor(this.canGoForward() ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .backgroundColor(Color.Transparent)
        .width(34)
        .height(38)
        .enabled(this.canGoForward())
        .onClick(() => this.goForward())
      TextInput({ text: this.addressText, placeholder: $r('app.string.address_placeholder') })
        .layoutWeight(1)
        .height(38)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.surface_background'))
        .borderRadius(19)
        .padding({ left: 15, right: 12 })
        .onChange((value: string) => this.addressText = value)
        .onSubmit(() => this.navigate())
      Button(this.viewModel.getActiveTab()?.isLoading === true ? '×' : '↻')
        .fontSize(19)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor(Color.Transparent)
        .width(36)
        .height(38)
        .onClick(() => this.reload())
      Button(this.isCurrentPageBookmarked() ? '★' : '☆')
        .fontSize(21)
        .fontColor(this.isCurrentPageBookmarked() ? $r('app.color.accent') : $r('app.color.text_primary'))
        .backgroundColor(Color.Transparent)
        .width(36)
        .height(38)
        .onClick(() => this.toggleBookmark())
    }
    .width('100%')
    .padding({ left: 8, right: 8, bottom: 8 })
  }

  @Builder
  private WebContent() {
    Column() {
      if (this.activeTabId.length > 0) {
        this.ActiveWebView(this.activeTab() as BrowserTab)
      }
      Row() {
        Text(`${this.activeTab()?.blockedCount ?? 0}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Text($r('app.string.blocked_requests'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Button(this.isReaderModeEnabled ? $r('app.string.reader_on') : $r('app.string.reader'))
          .fontSize(11)
          .fontColor(this.isReaderModeEnabled ? $r('app.color.accent') : $r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick(() => this.toggleReaderMode())
        Button($r('app.string.bookmarks'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick(() => this.openLibrary('bookmarks'))
      }
      .width('100%')
      .height(30)
      .padding({ left: 14, right: 10 })
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private ActiveWebView(activeTab: BrowserTab) {
    BrowserWebView({
      tab: activeTab,
      isAdsBlockingEnabled: this.settings.isAdsBlockingEnabled,
      isDarkModeEnabled: this.settings.isDarkModeEnabled,
      isDesktopModeEnabled: this.settings.isDesktopModeEnabled,
      controller: this.controllerFor(activeTab.id),
      onPageBegin: (url: string): void => this.handlePageBegin(activeTab.id, url),
      onPageEnd: (url: string): void => { this.handlePageEnd(activeTab.id, url); },
      onTitleReceive: (title: string): void => this.handleTitle(activeTab.id, title),
      onProgressChange: (progress: number): void => this.handleProgress(activeTab.id, progress),
      onAdsBlocked: (count: number): void => this.handleAdsBlocked(activeTab.id, count)
    })
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private LibraryView() {
    Column() {
      Row() {
        Text(this.librarySection === 'bookmarks' ? $r('app.string.bookmarks') : $r('app.string.history'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Button($r('app.string.done'))
          .fontColor($r('app.color.accent'))
          .backgroundColor(Color.Transparent)
          .onClick(() => this.showLibrary = false)
      }
      .width('100%')
      .padding({ left: 18, right: 12, top: 12, bottom: 8 })
      Row({ space: 8 }) {
        Button($r('app.string.bookmarks'))
          .layoutWeight(1)
          .backgroundColor(this.librarySection === 'bookmarks' ? $r('app.color.surface_elevated') : Color.Transparent)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.librarySection = 'bookmarks')
        Button($r('app.string.history'))
          .layoutWeight(1)
          .backgroundColor(this.librarySection === 'history' ? $r('app.color.surface_elevated') : Color.Transparent)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.librarySection = 'history')
      }
      .padding({ left: 14, right: 14, bottom: 10 })
      if (this.librarySection === 'bookmarks') {
        this.BookmarkList()
      } else {
        this.HistoryList()
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private BookmarkList() {
    if (this.bookmarks.length === 0) {
      Text($r('app.string.no_bookmarks'))
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 40 })
    } else {
      List({ space: 8 }) {
        ForEach(this.bookmarks, (item: Bookmark) => {
          ListItem() {
            Row({ space: 10 }) {
              Column() {
                Text(item.title.length > 0 ? item.title : item.url)
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.url)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Button('×')
                .fontSize(18)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor(Color.Transparent)
                .onClick(() => this.removeBookmark(item.id))
            }
            .width('100%')
            .padding(12)
            .backgroundColor($r('app.color.surface_background'))
            .borderRadius(10)
            .onClick(() => this.openUrl(item.url))
          }
        }, (item: Bookmark) => item.id)
      }
      .layoutWeight(1)
      .padding({ left: 14, right: 14, bottom: 12 })
    }
  }

  @Builder
  private HistoryList() {
    Column() {
      if (this.history.length === 0) {
        Text($r('app.string.no_history'))
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 40 })
      } else {
        List({ space: 8 }) {
          ForEach(this.history, (item: HistoryEntry) => {
            ListItem() {
              Column() {
                Text(item.title.length > 0 ? item.title : item.url)
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.url)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(12)
              .backgroundColor($r('app.color.surface_background'))
              .borderRadius(10)
              .onClick(() => this.openUrl(item.url))
            }
          }, (item: HistoryEntry) => item.id)
        }
        .layoutWeight(1)
        .padding({ left: 14, right: 14 })
      }
      if (this.history.length > 0) {
        Button($r('app.string.clear_history'))
          .fontColor($r('app.color.accent'))
          .backgroundColor(Color.Transparent)
          .margin({ bottom: 8 })
          .onClick(() => this.clearHistory())
      }
    }
    .layoutWeight(1)
  }

  @Builder
  private SettingsView() {
    Column() {
      Row() {
        Text($r('app.string.settings'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Button($r('app.string.done'))
          .fontColor($r('app.color.accent'))
          .backgroundColor(Color.Transparent)
          .onClick(() => this.showSettings = false)
      }
      .padding({ left: 18, right: 12, top: 12, bottom: 15 })
      this.ToggleRow($r('app.string.ads_blocking'), this.settings.isAdsBlockingEnabled,
        () => this.toggleAdsBlocking())
      this.ToggleRow($r('app.string.dark_mode'), this.settings.isDarkModeEnabled,
        () => this.toggleDarkMode())
      this.ToggleRow($r('app.string.desktop_mode'), this.settings.isDesktopModeEnabled,
        () => this.toggleDesktopMode())
      Button($r('app.string.private_tab'))
        .width('calc(100% - 28vp)')
        .margin({ left: 14, right: 14, top: 12 })
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_elevated'))
        .onClick(() => {
          this.createTab(true);
          this.showSettings = false;
        })
      Column() {
        Text($r('app.string.rules_ready'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.rules_description'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 5 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(14)
      .margin({ left: 14, right: 14, top: 12 })
      .backgroundColor($r('app.color.surface_background'))
      .borderRadius(10)
      Blank()
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private ToggleRow(title: Resource, enabled: boolean, onToggle: () => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Button(enabled ? $r('app.string.enabled') : $r('app.string.disabled'))
        .fontSize(12)
        .fontColor(enabled ? $r('app.color.positive') : $r('app.color.text_secondary'))
        .backgroundColor($r('app.color.surface_elevated'))
        .onClick(onToggle)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
  }

  @Builder
  private LoadingView() {
    Column() {
      LoadingProgress()
        .width(42)
        .height(42)
      Text($r('app.string.app_name'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 12 })
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ErrorView() {
    Column() {
      Text($r('app.string.initialization_error'))
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
      Button($r('app.string.home'))
        .margin({ top: 16 })
        .onClick(() => this.retry())
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  private syncState(): void {
    this.tabs = this.viewModel.tabs.map((tab: BrowserTab) => cloneTab(tab));
    this.bookmarks = this.viewModel.bookmarks.map((item: Bookmark) => cloneBookmark(item));
    this.history = this.viewModel.history.map((item: HistoryEntry) => cloneHistoryEntry(item));
    this.settings = cloneSettings(this.viewModel.settings);
    this.activeTabId = this.viewModel.activeTabId;
    const active: BrowserTab | undefined = this.activeTab();
    this.addressText = active?.url ?? HOME_URL;
  }

  private activeTab(): BrowserTab | undefined {
    return this.tabs.find((tab: BrowserTab) => tab.id === this.activeTabId);
  }

  private activeController(): webview.WebviewController | undefined {
    const active: BrowserTab | undefined = this.activeTab();
    return active === undefined ? undefined : this.controllerFor(active.id);
  }

  private controllerFor(id: string): webview.WebviewController {
    const existing: webview.WebviewController | undefined = this.controllers.get(id);
    if (existing !== undefined) {
      return existing;
    }
    const controller: webview.WebviewController = new webview.WebviewController();
    this.controllers.set(id, controller);
    return controller;
  }

  private canGoBack(): boolean {
    const controller: webview.WebviewController | undefined = this.activeController();
    try {
      return controller !== undefined && controller.accessBackward();
    } catch (_) {
      return false;
    }
  }

  private canGoForward(): boolean {
    const controller: webview.WebviewController | undefined = this.activeController();
    try {
      return controller !== undefined && controller.accessForward();
    } catch (_) {
      return false;
    }
  }

  private navigate(): void {
    const controller: webview.WebviewController | undefined = this.activeController();
    if (controller === undefined) {
      return;
    }
    const url: string = normalizeAddress(this.addressText);
    try {
      controller.loadUrl(url);
    } catch (error) {
      Logger.warn(TAG, `Navigation failed: ${String(error)}`);
    }
  }

  private openUrl(url: string): void {
    this.showLibrary = false;
    this.showSettings = false;
    this.addressText = url;
    const controller: webview.WebviewController | undefined = this.activeController();
    if (controller !== undefined) {
      try {
        controller.loadUrl(url);
      } catch (error) {
        Logger.warn(TAG, `Bookmark navigation failed: ${String(error)}`);
      }
    }
  }

  private goBack(): void {
    const controller: webview.WebviewController | undefined = this.activeController();
    if (controller !== undefined && this.canGoBack()) {
      try {
        controller.backward();
      } catch (error) {
        Logger.warn(TAG, `Back navigation failed: ${String(error)}`);
      }
    }
  }

  private goForward(): void {
    const controller: webview.WebviewController | undefined = this.activeController();
    if (controller !== undefined && this.canGoForward()) {
      try {
        controller.forward();
      } catch (error) {
        Logger.warn(TAG, `Forward navigation failed: ${String(error)}`);
      }
    }
  }

  private reload(): void {
    const controller: webview.WebviewController | undefined = this.activeController();
    if (controller !== undefined) {
      try {
        controller.refresh();
      } catch (error) {
        Logger.warn(TAG, `Reload failed: ${String(error)}`);
      }
    }
  }

  private createTab(isPrivate: boolean): void {
    this.viewModel.addTab(HOME_URL, isPrivate);
    this.syncState();
  }

  private selectTab(id: string): void {
    this.viewModel.selectTab(id);
    this.isReaderModeEnabled = false;
    this.syncState();
  }

  private closeTab(id: string): void {
    this.viewModel.closeTab(id);
    this.controllers.delete(id);
    this.syncState();
  }

  private handlePageBegin(id: string, url: string): void {
    this.viewModel.updateTab(id, { url: url, isLoading: true, progress: 0 });
    if (id === this.activeTabId) {
      this.addressText = url;
    }
    this.syncState();
  }

  private async handlePageEnd(id: string, url: string): Promise<void> {
    this.viewModel.updateTab(id, { url: url, isLoading: false, progress: 100 });
    const tab: BrowserTab | undefined = this.viewModel.tabs.find((item: BrowserTab) => item.id === id);
    if (tab !== undefined) {
      await this.viewModel.recordPageVisit(tab);
    }
    this.syncState();
  }

  private handleTitle(id: string, title: string): void {
    this.viewModel.updateTab(id, { title: title.length > 0 ? title : displayHost(this.activeTab()?.url ?? '') });
    this.syncState();
  }

  private handleProgress(id: string, progress: number): void {
    this.viewModel.updateTab(id, { progress: progress, isLoading: progress < 100 });
    this.syncState();
  }

  private handleAdsBlocked(id: string, count: number): void {
    const tab: BrowserTab | undefined = this.viewModel.tabs.find((item: BrowserTab) => item.id === id);
    if (tab !== undefined) {
      this.viewModel.updateTab(id, { blockedCount: tab.blockedCount + count });
      this.syncState();
    }
  }

  private isCurrentPageBookmarked(): boolean {
    return this.viewModel.isBookmarked(this.activeTab()?.url ?? '');
  }

  private async toggleBookmark(): Promise<void> {
    const tab: BrowserTab | undefined = this.activeTab();
    if (tab === undefined) {
      return;
    }
    await this.viewModel.toggleBookmark(tab);
    this.syncState();
  }

  private async removeBookmark(id: string): Promise<void> {
    await this.viewModel.repository.removeBookmark(id);
    this.viewModel.bookmarks = this.viewModel.repository.getBookmarks();
    this.syncState();
  }

  private async clearHistory(): Promise<void> {
    await this.viewModel.clearHistory();
    this.syncState();
  }

  private openLibrary(section: LibrarySection): void {
    this.librarySection = section;
    this.showLibrary = true;
    this.showSettings = false;
  }

  private openSettings(): void {
    this.showSettings = true;
    this.showLibrary = false;
  }

  private async toggleAdsBlocking(): Promise<void> {
    const settings: BrowserSettings = cloneSettings(this.settings);
    settings.isAdsBlockingEnabled = !settings.isAdsBlockingEnabled;
    await this.updateSettings(settings);
  }

  private async toggleDarkMode(): Promise<void> {
    const enabled: boolean = !this.settings.isDarkModeEnabled;
    const settings: BrowserSettings = cloneSettings(this.settings);
    settings.isDarkModeEnabled = enabled;
    await this.updateSettings(settings);
    const controller: webview.WebviewController | undefined = this.activeController();
    if (controller !== undefined) {
      await this.runScript(controller, enabled ? DARK_MODE_SCRIPT : LIGHT_MODE_SCRIPT);
    }
  }

  private async toggleDesktopMode(): Promise<void> {
    const settings: BrowserSettings = cloneSettings(this.settings);
    settings.isDesktopModeEnabled = !settings.isDesktopModeEnabled;
    await this.updateSettings(settings);
    this.reload();
  }

  private async toggleReaderMode(): Promise<void> {
    this.isReaderModeEnabled = !this.isReaderModeEnabled;
    const controller: webview.WebviewController | undefined = this.activeController();
    if (controller !== undefined) {
      await this.runScript(controller, this.isReaderModeEnabled ? READER_MODE_SCRIPT : CONTENT_CLEANUP_SCRIPT);
    }
  }

  private async updateSettings(settings: BrowserSettings): Promise<void> {
    await this.viewModel.updateSettings(settings);
    this.syncState();
  }

  private async runScript(controller: webview.WebviewController, script: string): Promise<void> {
    try {
      await controller.runJavaScript(script);
    } catch (error) {
      Logger.warn(TAG, `Script execution failed: ${String(error)}`);
    }
  }

  private retry(): void {
    this.errorMessage = '';
    this.aboutToAppear();
  }
}
