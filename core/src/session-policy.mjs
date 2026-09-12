/**
 * Session persistence rules shared across platforms.
 * Private tabs never land in session, history, or site-stat writes.
 */

export function persistableTabs(tabs) {
  return tabs.filter((tab) => tab.isPrivate !== true);
}

export function shouldRecordHistory(isPrivate) {
  return isPrivate !== true;
}

export function shouldRecordSiteStats(isPrivate) {
  return isPrivate !== true;
}

export function shouldFetchFavicon(isPrivate) {
  return isPrivate !== true;
}

export function liveTabIds(tabs, activeTabId, limit) {
  const bounded = Math.max(1, Math.floor(limit));
  const ids = [];
  if (activeTabId) {
    ids.push(activeTabId);
  }
  for (const tab of tabs) {
    if (ids.length >= bounded) {
      break;
    }
    if (!ids.includes(tab.id)) {
      ids.push(tab.id);
    }
  }
  return ids;
}

export function isTabLive(liveIds, tabId) {
  return liveIds.includes(tabId);
}
