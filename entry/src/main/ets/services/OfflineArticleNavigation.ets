/** Authorizes exactly one native loadData navigation, never arbitrary page data links. */
export class OfflineArticleNavigation {
  private pendingDocument: boolean = false;

  beginDocument(): void {
    this.pendingDocument = true;
  }

  finishDocument(): void {
    this.pendingDocument = false;
  }

  allowInternal(url: string, isMainFrame: boolean): boolean {
    if (isMainFrame && this.pendingDocument && /^data:text\/html(?:;|,)/i.test(url)) {
      this.pendingDocument = false;
      return true;
    }
    return url === 'about:blank' || url === 'https://offline.invalid/';
  }
}
