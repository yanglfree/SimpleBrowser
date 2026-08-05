export const HOME_URL: string = 'https://www.example.com';
export const SEARCH_URL: string = 'https://www.bing.com/search?q=';
export const STORE_NAME: string = 'clear_browser_store';
export const MAX_HISTORY_COUNT: number = 100;
export const MAX_BOOKMARK_COUNT: number = 200;
export const DESKTOP_USER_AGENT: string =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

export const CONTENT_CLEANUP_SCRIPT: string = `
(function() {
  const selectors = [
    '[id*="ad"]', '[class*="ad-"]', '[class*="-ad"]',
    '[id*="banner"]', '[class*="banner"]', '[class*="recommend"]',
    '[class*="related"]', '[class*="sponsor"]', '[aria-label*="advert"]'
  ];
  selectors.forEach((selector) => {
    document.querySelectorAll(selector).forEach((node) => {
      if (node instanceof HTMLElement) node.style.setProperty('display', 'none', 'important');
    });
  });
  return 'cleaned';
})();`;

export const READER_MODE_SCRIPT: string = `
(function() {
  const candidates = Array.from(document.querySelectorAll('article, main, [role="main"]'));
  const target = candidates.sort((left, right) => right.innerText.length - left.innerText.length)[0];
  if (!target) return 'no-article';
  document.body.innerHTML = '';
  document.body.style.cssText = 'margin:0;background:#f7f4ee;color:#222;font-family:serif;';
  const article = document.createElement('article');
  article.innerHTML = target.innerHTML;
  article.style.cssText = 'max-width:760px;margin:0 auto;padding:32px 22px;font-size:20px;line-height:1.75;';
  document.body.appendChild(article);
  return 'reader';
})();`;

export const DARK_MODE_SCRIPT: string = `
(function() {
  const styleId = 'clear-browser-dark-mode';
  let style = document.getElementById(styleId);
  if (!style) {
    style = document.createElement('style');
    style.id = styleId;
    document.head.appendChild(style);
  }
  style.textContent = 'html{background:#0d1117!important;filter:none!important}' +
    'body{background:#0d1117!important;color:#c9d1d9!important}' +
    'body *{border-color:#30363d!important}' +
    'a{color:#58a6ff!important}img,video{opacity:.9}';
  return 'dark';
})();`;

export const LIGHT_MODE_SCRIPT: string = `
(function() {
  const style = document.getElementById('clear-browser-dark-mode');
  if (style) style.remove();
  return 'light';
})();`;
