import { ArticleSaveFailure, SavedArticle } from '../models/ArticleLibraryModels';

export function articleFailureLabel(failure: ArticleSaveFailure): Resource {
  if (failure === ArticleSaveFailure.StorageUnavailable) {
    return $r('app.string.article_storage_failed');
  }
  if (failure === ArticleSaveFailure.PageChanged) {
    return $r('app.string.article_page_changed');
  }
  if (failure === ArticleSaveFailure.CaptureInvalid) {
    return $r('app.string.article_capture_failed');
  }
  return $r('app.string.article_extraction_failed');
}

export function articleStatusLabel(article: SavedArticle): Resource {
  if (article.failure !== ArticleSaveFailure.None) {
    return articleFailureLabel(article.failure);
  }
  if ((article.imageFailedCount ?? 0) > 0) {
    return $r('app.string.article_images_partial', article.imageSavedCount ?? 0, article.imageFailedCount ?? 0);
  }
  return article.quality === 'complete' ? $r('app.string.article_saved') : $r('app.string.article_saved_partial');
}
