import { BlockStats, BrowserTab, HistoryEntry, SavedItem, totalBlocked } from '../models/BrowserModels';
import { DownloadTask } from '../services/DownloadService';
import { displayHost } from '../utils/UrlUtils';
import { AppIcon, IconName } from './AppIcon';
import { DownloadSheet } from './DownloadSheet';
import { HistorySheet } from './HistorySheet';

export enum SidebarPanel {
  None = 0,
  Tabs = 1,
  Favorites = 2,
  History = 3,
  Downloads = 4,
  Block = 5
}

@Component
export struct BrowserSidebar {
  @Prop panel: SidebarPanel = SidebarPanel.None;
  @Prop tabs: BrowserTab[] = [];
  @Prop activeTabId: string = '';
  @Prop history: HistoryEntry[] = [];
  @Prop savedItems: SavedItem[] = [];
  @Prop downloads: DownloadTask[] = [];
  @Prop host: string = '';
  @Prop blockStats: BlockStats = { ads: 0, trackers: 0, malicious: 0, popups: 0, cookieBanners: 0 };
  @Prop cumulativeBlocked: number = 0;
  @Prop topInset: number = 0;
  onPanelChange: (panel: SidebarPanel) => void = (_panel: SidebarPanel): void => {};
  onDismiss: () => void = (): void => {};
  onSelectTab: (id: string) => void = (_id: string): void => {};
  onCloseTab: (id: string) => void = (_id: string): void => {};
  onNavigate: (url: string) => void = (_url: string): void => {};
  onDeleteHistory: (id: string) => void = (_id: string): void => {};
  onDeleteHistorySite: (host: string) => void = (_host: string): void => {};
  onDeleteFavorite: (id: string) => void = (_id: string): void => {};
  onPauseDownload: (id: string) => void = (_id: string): void => {};
  onResumeDownload: (id: string) => void = (_id: string): void => {};
  onRetryDownload: (id: string) => void = (_id: string): void => {};
  onOpenDownload: (task: DownloadTask) => void = (_task: DownloadTask): void => {};
  onShareDownload: (task: DownloadTask) => void = (_task: DownloadTask): void => {};
  onDeleteDownloadFile: (id: string) => void = (_id: string): void => {};
  onDeleteDownloadRecord: (id: string) => void = (_id: string): void => {};

  build() {
    Column() {
      Row({ space: 4 }) {
        this.NavButton(SidebarPanel.Tabs, IconName.Tabs)
        this.NavButton(SidebarPanel.Favorites, IconName.Bookmark)
        this.NavButton(SidebarPanel.History, IconName.Clock)
        this.NavButton(SidebarPanel.Downloads, IconName.Download)
        this.NavButton(SidebarPanel.Block, IconName.ShieldCheck)
        Row().layoutWeight(1)
        Row() {
          AppIcon({ name: IconName.Close, glyphSize: 16, color: $r('app.color.text_secondary') })
        }
        .id('browser-sidebar-close')
        .accessibilityText($r('app.string.close'))
        .width(34)
        .height(34)
        .justifyContent(FlexAlign.Center)
        .borderRadius(10)
        .hoverEffect(HoverEffect.Auto)
        .onClick(() => this.onDismiss())
      }
      .width('100%')
      .height(52)
      .padding({ left: 10, right: 10 })
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })

      if (this.panel === SidebarPanel.Tabs) {
        this.TabsPanel()
      } else if (this.panel === SidebarPanel.Favorites) {
        HistorySheet({
          entries: [],
          savedItems: this.savedItems,
          favoritesOnly: true,
          onDismiss: (): void => this.onDismiss(),
          onSelect: (url: string): void => this.onNavigate(url),
          onDelete: (id: string): void => this.onDeleteFavorite(id)
        })
      } else if (this.panel === SidebarPanel.History) {
        HistorySheet({
          entries: this.history,
          savedItems: this.savedItems,
          onDismiss: (): void => this.onDismiss(),
          onSelect: (url: string): void => this.onNavigate(url),
          onDelete: (id: string): void => this.onDeleteHistory(id),
          onDeleteSite: (host: string): void => this.onDeleteHistorySite(host)
        })
      } else if (this.panel === SidebarPanel.Downloads) {
        DownloadSheet({
          tasks: this.downloads,
          onDismiss: (): void => this.onDismiss(),
          onPause: (id: string): void => this.onPauseDownload(id),
          onResume: (id: string): void => this.onResumeDownload(id),
          onRetry: (id: string): void => this.onRetryDownload(id),
          onOpen: (task: DownloadTask): void => this.onOpenDownload(task),
          onShare: (task: DownloadTask): void => this.onShareDownload(task),
          onDeleteFile: (id: string): void => this.onDeleteDownloadFile(id),
          onDeleteRecord: (id: string): void => this.onDeleteDownloadRecord(id)
        })
      } else {
        this.BlockPanel()
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: Math.max(0, this.topInset) })
    .backgroundColor($r('app.color.page_background'))
    .border({ width: { left: 1 }, color: $r('app.color.border') })
    .shadow({ radius: 14, color: $r('app.color.shadow_soft'), offsetX: -2 })
  }

  @Builder
  private NavButton(panel: SidebarPanel, icon: IconName) {
    Row() {
      AppIcon({
        name: icon,
        glyphSize: 17,
        color: panel === this.panel ? $r('app.color.accent') : $r('app.color.text_secondary')
      })
    }
    .width(34)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .borderRadius(10)
    .backgroundColor(panel === this.panel ? $r('app.color.surface_subtle') : Color.Transparent)
    .hoverEffect(HoverEffect.Auto)
    .onClick(() => this.onPanelChange(panel))
  }

  @Builder
  private TabsPanel() {
    List({ space: 6 }) {
      ForEach(this.tabs, (tab: BrowserTab) => {
        ListItem() {
          Row({ space: 8 }) {
            Text(this.tabTitle(tab))
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            AppIcon({ name: IconName.Close, glyphSize: 14, color: $r('app.color.text_secondary') })
              .width(28)
              .height(28)
              .onClick(() => this.onCloseTab(tab.id))
          }
          .width('100%')
          .height(46)
          .padding({ left: 12, right: 8 })
          .borderRadius(12)
          .backgroundColor(tab.id === this.activeTabId
            ? $r('app.color.surface_subtle')
            : Color.Transparent)
          .onClick(() => this.onSelectTab(tab.id))
        }
      }, (tab: BrowserTab): string => `${tab.id}-${tab.title}`)
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ top: 12, left: 10, right: 10, bottom: 12 })
    .scrollBar(BarState.Off)
  }

  @Builder
  private BlockPanel() {
    Column({ space: 16 }) {
      Text(this.host)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Text(`${totalBlocked(this.blockStats)}`)
        .fontSize(48)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text($r('app.string.blocked_on_site'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Divider().color($r('app.color.border'))
      Text(`${this.cumulativeBlocked}`)
        .fontSize(24)
        .fontColor($r('app.color.text_primary'))
      Text($r('app.string.blocked_cumulative_prefix'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ top: 42, left: 24, right: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  private tabTitle(tab: BrowserTab): ResourceStr {
    if (tab.title.length > 0) {
      return tab.title;
    }
    const host: string = displayHost(tab.url);
    return host.length > 0 ? host : $r('app.string.new_tab');
  }
}
