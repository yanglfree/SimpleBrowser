import test from 'node:test';
import assert from 'node:assert/strict';
import {
  addSavedItem,
  getSuggestions,
  isSaved,
  recordHistory,
  removeSavedItem,
  SuggestionKind
} from '../src/library-policy.mjs';

test('re-visiting a URL bumps visitCount instead of duplicating', () => {
  const first = recordHistory([], {
    id: 'h1', title: 'Docs', url: 'https://docs.example/guide', visitedAt: 1, visitCount: 0
  });
  const second = recordHistory(first, {
    id: 'h2', title: 'Docs', url: 'https://docs.example/guide', visitedAt: 2, visitCount: 0
  });
  assert.equal(second.length, 1);
  assert.equal(second[0].visitCount, 2);
  assert.equal(second[0].id, 'h2');
});

test('saved items replace the same URL and stay capped', () => {
  const first = addSavedItem([], {
    id: 's1', title: 'One', url: 'https://a.example', host: 'a.example'
  }, 2);
  const second = addSavedItem(first, {
    id: 's2', title: 'Two', url: 'https://b.example', host: 'b.example'
  }, 2);
  const third = addSavedItem(second, {
    id: 's3', title: 'Three', url: 'https://c.example', host: 'c.example'
  }, 2);
  assert.equal(third.length, 2);
  assert.equal(third[0].url, 'https://c.example');
  assert.equal(isSaved(third, 'https://c.example', false), true);
  assert.equal(isSaved(third, 'https://c.example', true), false);
  assert.equal(removeSavedItem(third, 's3').length, 1);
});

test('empty query lists recent history then unused bookmarks', () => {
  const suggestions = getSuggestions({
    query: '  ',
    history: [{ id: 'h', title: 'News', url: 'https://news.example', host: 'news.example' }],
    savedItems: [
      { id: 'b1', title: 'News', url: 'https://news.example', host: 'news.example' },
      { id: 'b2', title: 'Docs', url: 'https://docs.example', host: 'docs.example' }
    ]
  });
  assert.deepEqual(suggestions.map((item) => item.kind), [SuggestionKind.History, SuggestionKind.Bookmark]);
  assert.equal(suggestions[1].url, 'https://docs.example');
});

test('typed query prefers matching history and can append a search shortcut', () => {
  const suggestions = getSuggestions({
    query: 'privacy browser',
    history: [],
    savedItems: [],
    searchSuggestionsEnabled: true,
    searchUrl: 'https://www.bing.com/search?q=privacy%20browser'
  });
  assert.equal(suggestions.length, 1);
  assert.equal(suggestions[0].kind, SuggestionKind.Search);
  assert.equal(suggestions[0].url, 'https://www.bing.com/search?q=privacy%20browser');
});
