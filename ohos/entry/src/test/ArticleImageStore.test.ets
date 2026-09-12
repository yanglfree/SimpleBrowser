import { describe, expect, it } from '@ohos/hypium';
import { ArticleImageAsset } from '../main/ets/models/ArticleLibraryModels';
import { isPersistableArticleImage } from '../main/ets/services/ArticleImageStore';

export default function articleImageStoreTest(): void {
  describe('Article image store', (): void => {
    it('persists only HTTP image assets with safe local names', 0, (): void => {
      const asset: ArticleImageAsset = {
        index: 0, url: 'https://example.com/image.webp', fileName: 'image-0.webp'
      };
      expect(isPersistableArticleImage(asset)).assertTrue();
      expect(isPersistableArticleImage({
        index: 1, url: 'data:image/png;base64,abc', fileName: 'image-1.png'
      })).assertFalse();
      expect(isPersistableArticleImage({
        index: 2, url: 'https://example.com/image', fileName: '../image.png'
      })).assertFalse();
    });
  });
}
