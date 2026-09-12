/** Internal URL for the native start page. It is never handed to a web kernel. */
export const HOME_URL = 'browser://home';

export const DESKTOP_USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

export const MAX_TAB_COUNT = 100;
export const MAX_HISTORY_COUNT = 300;
export const MAX_BOOKMARK_COUNT = 200;
export const MAX_SUGGESTION_COUNT = 6;
export const LIVE_WEBVIEW_LIMIT_DEFAULT = 4;

export const SearchEngine = Object.freeze({
  Bing: 0,
  Baidu: 1,
  Google: 2,
  DuckDuckGo: 3
});
