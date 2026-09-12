import { MAX_BOOKMARK_COUNT, MAX_HISTORY_COUNT, MAX_SUGGESTION_COUNT } from './constants.mjs';

export const SuggestionKind = Object.freeze({
  History: 0,
  Bookmark: 1,
  Search: 2
});

export function recordHistory(history, entry, max = MAX_HISTORY_COUNT) {
  const previous = history.find((item) => item.url === entry.url);
  const merged = {
    id: entry.id,
    title: entry.title,
    url: entry.url,
    visitedAt: entry.visitedAt,
    visitCount: (previous?.visitCount ?? 0) + 1
  };
  return [merged].concat(history.filter((item) => item.url !== entry.url)).slice(0, max);
}

export function addSavedItem(items, item, max = MAX_BOOKMARK_COUNT) {
  return [item].concat(items.filter((saved) => saved.url !== item.url)).slice(0, max);
}

export function removeSavedItem(items, id) {
  return items.filter((item) => item.id !== id);
}

export function isSaved(items, url, isHome) {
  return !isHome && items.some((item) => item.url === url);
}

export function getSuggestions(input) {
  const trimmed = input.query.trim();
  const results = [];
  const history = input.history ?? [];
  const savedItems = input.savedItems ?? [];
  const limit = input.limit ?? MAX_SUGGESTION_COUNT;

  if (trimmed.length === 0) {
    for (const entry of history) {
      if (results.length >= limit) {
        break;
      }
      results.push(historySuggestion(entry));
    }
    for (const bookmark of savedItems) {
      if (results.length >= limit) {
        break;
      }
      if (!results.some((item) => item.url === bookmark.url)) {
        results.push(bookmarkSuggestion(bookmark));
      }
    }
    return results;
  }

  const needle = trimmed.toLowerCase();
  const matches = (title, url) =>
    title.toLowerCase().includes(needle) || url.toLowerCase().includes(needle);

  for (const entry of history) {
    if (results.length >= limit) {
      break;
    }
    if (matches(entry.title, entry.url)) {
      results.push(historySuggestion(entry));
    }
  }
  for (const bookmark of savedItems) {
    if (results.length >= limit) {
      break;
    }
    if (matches(bookmark.title, bookmark.url) && !results.some((item) => item.url === bookmark.url)) {
      results.push(bookmarkSuggestion(bookmark));
    }
  }
  if (input.searchSuggestionsEnabled && results.length < limit && input.searchUrl) {
    results.push({
      id: `search-${trimmed}`,
      kind: SuggestionKind.Search,
      title: trimmed,
      subtitle: '',
      url: input.searchUrl
    });
  }
  return results;
}

function historySuggestion(entry) {
  return {
    id: `history-${entry.id}`,
    kind: SuggestionKind.History,
    title: entry.title,
    subtitle: entry.host ?? '',
    url: entry.url
  };
}

function bookmarkSuggestion(bookmark) {
  return {
    id: `bookmark-${bookmark.id}`,
    kind: SuggestionKind.Bookmark,
    title: bookmark.title,
    subtitle: bookmark.host ?? '',
    url: bookmark.url
  };
}
