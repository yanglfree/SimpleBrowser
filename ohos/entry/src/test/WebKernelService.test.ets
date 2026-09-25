import { describe, it, expect } from '@ohos/hypium';
import { WebKernelService } from '../main/ets/services/WebKernelService';

export default function webKernelServiceTest() {
  describe('WebKernelServiceTest', () => {
    it('progress_100_before_page_end', 0, () => {
      // shouldRunPageEnd should return true when not tracked yet
      expect(WebKernelService.shouldRunPageEnd(undefined, 'https://example.com/')).assertTrue();
    });

    it('page_end_before_progress', 0, () => {
      // shouldRunPageEnd should return false when same URL has completed
      expect(WebKernelService.shouldRunPageEnd('https://example.com/', 'https://example.com/')).assertFalse();
    });

    it('hash_only_navigation', 0, () => {
      // shouldRunPageEnd should return false for hash-only navigation on completed doc
      expect(WebKernelService.shouldRunPageEnd('https://example.com/', 'https://example.com/#anchor')).assertFalse();
    });

    it('reload_of_same_URL', 0, () => {
      // reload clears completed map, so lastCompletedUrl is undefined
      expect(WebKernelService.shouldRunPageEnd(undefined, 'https://example.com/')).assertTrue();
    });

    it('error_page_commit', 0, () => {
      // error page committing a different URL or the same
      expect(WebKernelService.shouldRunPageEnd('https://example.com/', 'https://error.com/')).assertTrue();
    });
  });
}
