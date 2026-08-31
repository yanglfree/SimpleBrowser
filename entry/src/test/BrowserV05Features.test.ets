import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserTab,
  SiteIcon,
  clampTabMoveTarget,
  presetSiteIconResource,
  siteIconPath,
  withSiteIcon
} from '../main/ets/models/BrowserModels';
import { BrowserViewModel } from '../main/ets/viewmodels/BrowserViewModel';
import { tabDragDropIndex, tabReorderShift } from '../main/ets/components/DesktopTabStrip';
import {
  SiteIconRequest,
  faviconCacheFileName,
  faviconFileUri,
  iconPixelSize,
  isCachedIconFresh,
  isShortcutIconLargeEnough,
  looksLikeIconData,
  siteIconSignature,
  siteIconTargets
} from '../main/ets/services/FaviconPolicy';
import {
  faviconCandidates,
  faviconMetadataCandidates
} from '../main/ets/services/FaviconMetadataPolicy';

const SLOT: number = 120;

function pngBytes(): Uint8Array {
  return new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
}

function icoBytes(): Uint8Array {
  return new Uint8Array([0x00, 0x00, 0x01, 0x00, 0x01, 0x00]);
}

function htmlBytes(): Uint8Array {
  return new Uint8Array([0x3c, 0x21, 0x44, 0x4f, 0x43, 0x54, 0x59, 0x50, 0x45]);
}

function pngBytesWithSize(width: number, height: number): Uint8Array {
  const bytes: Uint8Array = new Uint8Array(24);
  bytes.set(pngBytes(), 0);
  bytes[16] = (width >>> 24) & 0xff;
  bytes[17] = (width >>> 16) & 0xff;
  bytes[18] = (width >>> 8) & 0xff;
  bytes[19] = width & 0xff;
  bytes[20] = (height >>> 24) & 0xff;
  bytes[21] = (height >>> 16) & 0xff;
  bytes[22] = (height >>> 8) & 0xff;
  bytes[23] = height & 0xff;
  return bytes;
}

function icoBytesWithSize(size: number): Uint8Array {
  const bytes: Uint8Array = new Uint8Array(22);
  bytes.set(icoBytes(), 0);
  bytes[6] = size === 256 ? 0 : size;
  bytes[7] = size === 256 ? 0 : size;
  return bytes;
}

export default function browserV05FeaturesTest(): void {
  // YOU-259
  describe('Tab strip drag reordering', (): void => {
    it('lands on a whole slot and clamps at both ends of the strip', 0, (): void => {
      expect(tabDragDropIndex(1, 4, 0, SLOT)).assertEqual(1);
      expect(tabDragDropIndex(1, 4, SLOT, SLOT)).assertEqual(2);
      expect(tabDragDropIndex(1, 4, SLOT * 2.4, SLOT)).assertEqual(3);
      // Dragged well past the last tab, it still lands on the last index.
      expect(tabDragDropIndex(1, 4, SLOT * 9, SLOT)).assertEqual(3);
      expect(tabDragDropIndex(1, 4, -SLOT * 9, SLOT)).assertEqual(0);
    });

    it('only gives way once the tab is past the middle of its neighbour', 0, (): void => {
      expect(tabDragDropIndex(1, 4, SLOT * 0.4, SLOT)).assertEqual(1);
      expect(tabDragDropIndex(1, 4, SLOT * 0.6, SLOT)).assertEqual(2);
    });

    it('rejects a drag from an index the strip does not have', 0, (): void => {
      expect(tabDragDropIndex(-1, 4, SLOT, SLOT)).assertEqual(-1);
      expect(tabDragDropIndex(4, 4, SLOT, SLOT)).assertEqual(-1);
      expect(tabDragDropIndex(1, 4, SLOT, 0)).assertEqual(-1);
    });

    it('steps aside only the tabs between the old and the new position', 0, (): void => {
      // Dragging index 0 to index 2 pulls 1 and 2 left, and leaves 3 alone.
      expect(tabReorderShift(1, 0, 2, SLOT)).assertEqual(-SLOT);
      expect(tabReorderShift(2, 0, 2, SLOT)).assertEqual(-SLOT);
      expect(tabReorderShift(3, 0, 2, SLOT)).assertEqual(0);
      // Dragging index 3 to index 1 pushes 1 and 2 right.
      expect(tabReorderShift(1, 3, 1, SLOT)).assertEqual(SLOT);
      expect(tabReorderShift(2, 3, 1, SLOT)).assertEqual(SLOT);
      expect(tabReorderShift(0, 3, 1, SLOT)).assertEqual(0);
      // The dragged tab follows the finger, never the shift.
      expect(tabReorderShift(3, 3, 1, SLOT)).assertEqual(0);
      expect(tabReorderShift(1, -1, -1, SLOT)).assertEqual(0);
    });

    it('clamps a drop to the run of tabs sharing the dragged tab\'s group', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      const pinned: BrowserTab = viewModel.createTab('https://pinned.example', false);
      const first: BrowserTab = viewModel.createTab('https://first.example', false);
      const second: BrowserTab = viewModel.createTab('https://second.example', false);
      const secret: BrowserTab = viewModel.createTab('https://secret.example', true);
      pinned.isPinned = true;
      const tabs: BrowserTab[] = [pinned, first, second, secret];

      // A normal tab dragged onto the pinned lead stops at the first normal slot.
      expect(clampTabMoveTarget(tabs, 2, 0)).assertEqual(1);
      // And dragged onto the private tail stops at the last normal slot.
      expect(clampTabMoveTarget(tabs, 1, 3)).assertEqual(2);
      // A drop back on the tab's own index is not a move.
      expect(clampTabMoveTarget(tabs, 1, 1)).assertEqual(-1);
      expect(clampTabMoveTarget(tabs, 0, 2)).assertEqual(-1);
      expect(clampTabMoveTarget(tabs, 9, 0)).assertEqual(-1);
    });

    it('reinserts the dragged tab instead of swapping a pair', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      const first: BrowserTab = viewModel.createTab('https://first.example', false);
      const second: BrowserTab = viewModel.createTab('https://second.example', false);
      const third: BrowserTab = viewModel.createTab('https://third.example', false);
      viewModel.tabs = [first, second, third];

      expect(viewModel.moveTabTo(first.id, 2)).assertTrue();
      expect(viewModel.tabs[0].id).assertEqual(second.id);
      expect(viewModel.tabs[1].id).assertEqual(third.id);
      expect(viewModel.tabs[2].id).assertEqual(first.id);
      expect(viewModel.moveTabTo(first.id, 2)).assertFalse();
      expect(viewModel.moveTabTo('missing-tab', 0)).assertFalse();
    });
  });

  // YOU-260
  describe('Quick site icons', (): void => {
    it('never resolves artwork for a private tab', 0, (): void => {
      const requests: SiteIconRequest[] = [
        { url: 'https://zhihu.com/', isPrivate: false },
        { url: 'https://secret.example.com/', isPrivate: true },
        { url: 'browser://home', isPrivate: false }
      ];

      const targets: SiteIconRequest[] = siteIconTargets(requests);

      expect(targets.length).assertEqual(1);
      expect(siteIconSignature(targets)).assertEqual('zhihu.com');
    });

    it('resolves a host shared by a shortcut and a tab exactly once', 0, (): void => {
      const requests: SiteIconRequest[] = [
        { url: 'https://zhihu.com/', isPrivate: false },
        { url: 'https://zhihu.com/question/1', isPrivate: false },
        { url: 'https://weibo.com/', isPrivate: false }
      ];

      expect(siteIconSignature(siteIconTargets(requests))).assertEqual('zhihu.com|weibo.com');
      // The gate compares hosts, so a new path on a known host is not a new fetch.
      expect(siteIconSignature(siteIconTargets(requests.slice(1))))
        .assertEqual('zhihu.com|weibo.com');
    });

    it('reads an icon back by host and leaves unknown hosts to the letter tile', 0, (): void => {
      const icons: SiteIcon[] = [{ host: 'zhihu.com', path: '/cache/favicons/zhihu.com.icon' }];

      expect(siteIconPath(icons, 'zhihu.com')).assertEqual('/cache/favicons/zhihu.com.icon');
      expect(siteIconPath(icons, 'weibo.com')).assertEqual('');
      expect(siteIconPath(icons, '')).assertEqual('');
    });

    it('resolves preset icon resources for default sites', 0, (): void => {
      expect(presetSiteIconResource('zhihu.com')).assertDeepEquals($r('app.media.site_zhihu'));
      expect(presetSiteIconResource('https://www.bilibili.com/video/1')).assertDeepEquals($r('app.media.site_bilibili'));
      expect(presetSiteIconResource('sspai.com')).assertDeepEquals($r('app.media.site_sspai'));
      expect(presetSiteIconResource('m.weibo.cn')).assertDeepEquals($r('app.media.site_weibo'));
      expect(presetSiteIconResource('www.douban.com')).assertDeepEquals($r('app.media.site_douban'));
      expect(presetSiteIconResource('36kr.com')).assertDeepEquals($r('app.media.site_36kr'));
      expect(presetSiteIconResource('unknown-site.org')).assertUndefined();
    });

    it('replaces a host\'s icon rather than accumulating duplicates', 0, (): void => {
      let icons: SiteIcon[] = withSiteIcon([], 'zhihu.com', '/a.icon');
      icons = withSiteIcon(icons, 'weibo.com', '/b.icon');
      icons = withSiteIcon(icons, 'zhihu.com', '/c.icon');

      expect(icons.length).assertEqual(2);
      expect(siteIconPath(icons, 'zhihu.com')).assertEqual('/c.icon');
      // An empty path drops the entry, which is how a broken icon is forgotten.
      expect(withSiteIcon(icons, 'zhihu.com', '').length).assertEqual(1);
    });

    it('prefers high-resolution site icons before the legacy root favicon', 0, (): void => {
      const candidates: string[] = faviconCandidates('https://www.zhihu.com/question/1');

      expect(candidates.length).assertEqual(3);
      expect(candidates[0]).assertEqual('https://www.zhihu.com/apple-touch-icon.png');
      expect(candidates[1]).assertEqual('https://www.zhihu.com/apple-touch-icon-precomposed.png');
      expect(candidates[2]).assertEqual('https://www.zhihu.com/favicon.ico');
      expect(faviconCandidates('').length).assertEqual(0);
    });

    it('uses the largest page-declared icon and resolves relative URLs', 0, (): void => {
      const html: string = '<head>' +
        '<link rel="icon" href="/favicon-32.png" sizes="32x32">' +
        '<link rel="apple-touch-icon" href="//static.zhihu.com/icon-152.png" sizes="152x152">' +
        '<link rel="icon" href="assets/icon-96.png" sizes="96x96">' +
        '</head>';
      const candidates: string[] = faviconMetadataCandidates(html, 'https://www.zhihu.com/question/1');

      expect(candidates.length).assertEqual(3);
      expect(candidates[0]).assertEqual('https://static.zhihu.com/icon-152.png');
      expect(candidates[1]).assertEqual('https://www.zhihu.com/question/assets/icon-96.png');
      expect(candidates[2]).assertEqual('https://www.zhihu.com/favicon-32.png');
    });

    it('does not let touch-icon semantics outrank a larger declared icon', 0, (): void => {
      const html: string = '<head>' +
        '<link rel="apple-touch-icon" href="/touch-76.png" sizes="76x76">' +
        '<link rel="icon" href="/icon-512.png" sizes="512x512">' +
        '</head>';
      const candidates: string[] = faviconMetadataCandidates(html, 'https://example.com/');

      expect(candidates[0]).assertEqual('https://example.com/icon-512.png');
      expect(candidates[1]).assertEqual('https://example.com/touch-76.png');
    });

    it('keeps a cache file name a host can round-trip through the file system', 0, (): void => {
      expect(faviconCacheFileName('www.zhihu.com')).assertEqual('www.zhihu.com.icon');
      expect(faviconCacheFileName('WWW.Zhihu.COM')).assertEqual('www.zhihu.com.icon');
      expect(faviconCacheFileName('host:8080/path')).assertEqual('host_8080_path.icon');
      expect(faviconCacheFileName('')).assertEqual('');
    });

    it('accepts real icon bytes and rejects the 404 page sites return instead', 0, (): void => {
      expect(looksLikeIconData(pngBytes())).assertTrue();
      expect(looksLikeIconData(icoBytes())).assertTrue();
      expect(looksLikeIconData(htmlBytes())).assertFalse();
      expect(looksLikeIconData(new Uint8Array([0x89]))).assertFalse();
    });

    it('accepts standard resolution artwork (>= 16px) and rejects sub-16px data', 0, (): void => {
      expect(iconPixelSize(icoBytesWithSize(32))).assertEqual(32);
      expect(iconPixelSize(pngBytesWithSize(152, 152))).assertEqual(152);
      expect(isShortcutIconLargeEnough(icoBytesWithSize(32))).assertTrue();
      expect(isShortcutIconLargeEnough(icoBytesWithSize(8))).assertFalse();
      expect(isShortcutIconLargeEnough(pngBytesWithSize(152, 152))).assertTrue();
    });

    it('hands Image a file URI, which is the only form it loads a sandbox file from', 0, (): void => {
      expect(faviconFileUri('/data/cache/favicons/zhihu.com.icon'))
        .assertEqual('file:///data/cache/favicons/zhihu.com.icon');
      expect(faviconFileUri('')).assertEqual('');
    });

    it('re-fetches a cached icon only once it is out of date', 0, (): void => {
      const now: number = 1_700_000_000_000;
      const day: number = 24 * 60 * 60 * 1000;

      expect(isCachedIconFresh(now - day, now)).assertTrue();
      expect(isCachedIconFresh(now - 15 * day, now)).assertFalse();
      expect(isCachedIconFresh(0, now)).assertFalse();
    });
  });
}
