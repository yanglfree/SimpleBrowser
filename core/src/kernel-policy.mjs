import { DESKTOP_USER_AGENT } from './constants.mjs';

/** Keeps UI state in the same range as the web kernel progress callback. */
export function clampProgress(progress) {
  if (Number.isNaN(progress)) {
    return 0;
  }
  return Math.min(100, Math.max(0, progress));
}

/** Back-history navigation is expressed as a negative relative step. */
export function isBackwardStep(step) {
  return step < 0;
}

/** Subframe commits must not affect the tab-level back and forward controls. */
export function shouldRefreshNavigationState(isMainFrame) {
  return isMainFrame === true;
}

export function shouldReturnHomeOnBack(hasWebHistory, isHome) {
  return !hasWebHistory && !isHome;
}

/** Native home is outside kernel history, but remains a valid back destination. */
export function canNavigateBack(hasWebHistory, isHome) {
  return hasWebHistory || shouldReturnHomeOnBack(hasWebHistory, isHome);
}

export function userAgentFor(isDesktop, mobileUserAgent) {
  return isDesktop ? DESKTOP_USER_AGENT : mobileUserAgent;
}

/** Known mobile-only entry points that cannot negotiate a desktop page from UA alone. */
export function desktopUrlFor(url) {
  const match = url.match(/^(https?):\/\/([^/?#]+)(.*)$/i);
  if (match === null || match[2].split(':')[0].toLowerCase() !== 'm.weibo.cn') {
    return url;
  }
  return `https://weibo.com${match[3]}`;
}
