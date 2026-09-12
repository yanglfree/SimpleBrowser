import { ArticleHighlight } from '../models/ArticleLibraryModels';

export const ARTICLE_SELECTION_SCRIPT: string = `(function() {
  var root = document.getElementById('article-content');
  var selection = window.getSelection();
  if (!root || !selection || !selection.rangeCount ||
    !root.contains(selection.anchorNode) || !root.contains(selection.focusNode)) return JSON.stringify({quote:'',text:''});
  return JSON.stringify({quote:selection.toString(),text:root.textContent || ''});
})();`;

export function articleHighlightScript(highlights: ArticleHighlight[], targetId: string = ''): string {
  return `(function(items, target) {
    var root = document.getElementById('article-content');
    if (!root) return false;
    root.querySelectorAll('mark[data-article-highlight]').forEach(function(mark) {
      mark.replaceWith(document.createTextNode(mark.textContent));
    });
    root.normalize();
    items.forEach(function(item) {
      var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      var nodes = [], text = '', node;
      while ((node = walker.nextNode())) { nodes.push({node:node,start:text.length}); text += node.textContent; }
      var escaped = item.textQuote.replace(/[.*+?^$\{\}()|[\]\\\\]/g, '\\\\$&').trim().split(/\\s+/).join('\\\\s+');
      if (!escaped) return;
      var pattern = new RegExp(escaped, 'g');
      var match;
      while ((match = pattern.exec(text))) {
        var before = text.substring(0, match.index).replace(/\\s+/g, ' ');
        var after = text.substring(match.index + match[0].length).replace(/\\s+/g, ' ');
        if ((!item.prefix || before.endsWith(item.prefix)) && (!item.suffix || after.startsWith(item.suffix))) break;
      }
      if (!match) return;
      var start = match.index, end = start + match[0].length;
      nodes.forEach(function(entry) {
        var left = Math.max(0, start-entry.start), right = Math.min(entry.node.length, end-entry.start);
        if (left >= right) return;
        var range = document.createRange(); range.setStart(entry.node,left); range.setEnd(entry.node,right);
        var mark = document.createElement('mark'); mark.setAttribute('data-article-highlight',item.id);
        range.surroundContents(mark);
      });
    });
    if (target) {
      var marks = root.querySelectorAll('mark[data-article-highlight]');
      for (var i=0;i<marks.length;i++) if (marks[i].getAttribute('data-article-highlight') === target) {
        marks[i].scrollIntoView({block:'center'}); return true;
      }
      return false;
    }
    return true;
  })(${JSON.stringify(highlights)}, ${JSON.stringify(targetId)});`;
}
