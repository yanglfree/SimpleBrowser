(function() {
  if (window.__zhuoReaderExtract) return;
  var SITE_SELECTOR = '#js_content,.rich_media_content';
  var CANDIDATE_SELECTOR =
    'article,main,[role="main"],[itemprop="articleBody"],.article,.article-body,.article-content,' +
    '.post,.post-body,.post-content,.entry-content,.story-body,.story-content,.content,#content';
  var STRUCTURAL_NOISE_SELECTOR =
    'script,style,iframe,noscript,form,button,nav,aside,header,footer,video,' +
    '[role="navigation"],[role="complementary"],[aria-label*="comment"]';
  var CHROME_TOKENS = [
    'comment', 'comments', 'comment-list', 'comment-section', 'comment-area', 'comment-container',
    'recommend', 'recommended', 'recommendations', 'recommend-list', 'recommend-section',
    'recommend-area', 'recommend-container', 'recommend-widget', 'related-post', 'related-posts',
    'related-article', 'related-articles', 'related-content', 'related-list', 'related-section',
    'breadcrumb', 'breadcrumbs', 'sidebar', 'advert', 'advertisement', 'advert-slot',
    'advert-container', 'advert-banner'
  ];

  function textOf(node) {
    return ((node && (node.innerText || node.textContent)) || '').trim();
  }

  function removeStructuralNoise(root) {
    var nodes = root.querySelectorAll(STRUCTURAL_NOISE_SELECTOR);
    for (var index = 0; index < nodes.length; index++) nodes[index].remove();
  }

  function hasChromeToken(node) {
    var value = ((node.getAttribute('class') || '') + ' ' + (node.getAttribute('id') || '')).toLowerCase();
    var tokens = value.split(' ');
    for (var tokenIndex = 0; tokenIndex < tokens.length; tokenIndex++) {
      if (CHROME_TOKENS.indexOf(tokens[tokenIndex].trim()) >= 0) return true;
    }
    return false;
  }

  function cleanCandidate(candidate) {
    var article = candidate.cloneNode(true);
    removeStructuralNoise(article);
    var elements = [article].concat(Array.prototype.slice.call(article.querySelectorAll('*')));
    for (var elementIndex = elements.length - 1; elementIndex >= 0; elementIndex--) {
      var element = elements[elementIndex];
      if (hasChromeToken(element)) {
        element.remove();
        continue;
      }
      var allowedTags = 'ARTICLE MAIN DIV SECTION P H1 H2 H3 H4 H5 H6 SPAN A IMG FIGURE FIGCAPTION ' +
        'STRONG B EM I U S DEL SMALL SUP SUB BR HR BLOCKQUOTE PRE CODE UL OL LI DL DT DD TABLE ' +
        'THEAD TBODY TFOOT TR TH TD';
      if (element !== article && allowedTags.split(' ').indexOf(element.tagName) < 0) {
        element.replaceWith.apply(element, Array.prototype.slice.call(element.childNodes));
        continue;
      }
      var attributes = Array.prototype.slice.call(element.attributes || []);
      for (var attributeIndex = 0; attributeIndex < attributes.length; attributeIndex++) {
        var attributeName = attributes[attributeIndex].name.toLowerCase();
        if (['href', 'src', 'data-src', 'data-original', 'alt', 'title', 'colspan', 'rowspan', 'dir', 'lang']
          .indexOf(attributeName) < 0) {
          element.removeAttribute(attributes[attributeIndex].name);
        }
      }
      var href = element.getAttribute('href') || '';
      if (href) {
        try {
          var resolved = new URL(href, document.baseURI);
          if (/^https?:$/.test(resolved.protocol)) element.setAttribute('href', resolved.href);
          else element.removeAttribute('href');
        } catch (error) { element.removeAttribute('href'); }
      }
    }
    var images = article.querySelectorAll('img');
    for (var imageIndex = 0; imageIndex < images.length; imageIndex++) {
      var image = images[imageIndex];
      var source = image.getAttribute('data-src') || image.getAttribute('data-original') ||
        image.getAttribute('src') || '';
      if (source && !/^(https?:|data:image\/)/i.test(source)) {
        try { source = new URL(source, document.baseURI).href; } catch (error) { source = ''; }
      }
      if (!/^(https?:|data:image\/)/i.test(source)) source = '';
      image.removeAttribute('src');
      if (source) image.setAttribute('src', source);
      image.removeAttribute('srcset');
      image.removeAttribute('data-src');
      image.removeAttribute('data-original');
    }
    return article;
  }

  function candidateScore(candidate) {
    var probe = candidate.cloneNode(true);
    removeStructuralNoise(probe);
    var text = textOf(probe);
    var minimum = /^(ARTICLE|MAIN)$/i.test(candidate.tagName) ||
      candidate.matches(SITE_SELECTOR) ? 40 : 240;
    if (text.length < minimum) return null;
    var paragraphs = candidate.querySelectorAll('p').length;
    var linkNodes = candidate.querySelectorAll('a');
    var linkText = 0;
    for (var linkIndex = 0; linkIndex < linkNodes.length; linkIndex++) linkText += textOf(linkNodes[linkIndex]).length;
    var punctuation = (text.match(/[。！？.!?]/g) || []).length;
    var paragraphDensity = paragraphs === 0 ? 0 : Math.min(1, punctuation / paragraphs / 2);
    var semanticBoost = /^(ARTICLE|MAIN)$/i.test(candidate.tagName) ? 240 : 0;
    return { length: text.length, score: text.length + Math.min(paragraphs, 80) * 70 + punctuation * 8 +
      paragraphDensity * 260 + semanticBoost - Math.min(linkText, text.length) * 0.6 };
  }

  function paragraphFallback(doc) {
    var paragraphNodes = doc.querySelectorAll('p');
    var fallback = doc.createElement('div');
    var length = 0;
    for (var index = 0; index < paragraphNodes.length; index++) {
      var paragraphText = textOf(paragraphNodes[index]);
      if (paragraphText.length < 24) continue;
      fallback.appendChild(paragraphNodes[index].cloneNode(true));
      length += paragraphText.length;
    }
    return length >= 240 ? { candidate: fallback, length: length } : null;
  }

  window.__zhuoReaderExtract = function(doc) {
    var startedAt = typeof performance !== 'undefined' ? performance.now() : Date.now();
    var best = null;
    var bestLength = 0;
    var bestScore = 0;
    var strategy = 'heuristic';
    var siteCandidate = doc.querySelector(SITE_SELECTOR);
    var siteScore = siteCandidate ? candidateScore(siteCandidate) : null;
    if (siteCandidate && siteScore) {
      best = siteCandidate;
      bestLength = siteScore.length;
      bestScore = siteScore.score;
      strategy = 'site_adapter';
    } else {
      var candidates = doc.querySelectorAll(CANDIDATE_SELECTOR);
      for (var candidateIndex = 0; candidateIndex < candidates.length; candidateIndex++) {
        var scored = candidateScore(candidates[candidateIndex]);
        if (scored && scored.score > bestScore) {
          best = candidates[candidateIndex];
          bestLength = scored.length;
          bestScore = scored.score;
        }
      }
    }
    if (!best) {
      var fallback = paragraphFallback(doc);
      if (fallback) {
        best = fallback.candidate;
        bestLength = fallback.length;
        strategy = 'paragraph_fallback';
      }
    }
    if (!best) {
      return { result: 'unavailable', strategy: 'none', candidateChars: 0, outputChars: 0,
        retainedRatio: 0, paragraphCount: 0, imageCount: 0, durationMs: 0, title: '', node: null };
    }
    var article = cleanCandidate(best);
    var outputChars = textOf(article).length;
    var retainedRatio = bestLength === 0 ? 0 : Math.min(1, outputChars / bestLength);
    var result = outputChars < 40 ? 'unavailable' :
      (strategy === 'paragraph_fallback' || retainedRatio < 0.72 ? 'partial' : 'complete');
    var heading = article.querySelector('h1');
    var ogTitle = doc.querySelector('meta[property="og:title"]');
    var title = heading ? textOf(heading) : (ogTitle ? ogTitle.getAttribute('content') || '' : doc.title || '');
    var finishedAt = typeof performance !== 'undefined' ? performance.now() : Date.now();
    return { result: result, strategy: strategy, candidateChars: bestLength, outputChars: outputChars,
      retainedRatio: retainedRatio, paragraphCount: article.querySelectorAll('p').length,
      imageCount: article.querySelectorAll('img').length,
      durationMs: Math.max(0, Math.round(finishedAt - startedAt)), title: title, node: article };
  };
})();

(function() {
  var extraction = window.__zhuoReaderExtract(document);
  var best = extraction.node;
  if (!best) {
    return JSON.stringify({ title: document.title || '', author: '', canonicalUrl: location.href, sourceUrl: location.href,
      html: '', text: '', markdown: '', images: [], readerMetrics: extraction });
  }

  var article = best.cloneNode(true);
  var originalImages = best.querySelectorAll('img');
  var copiedImages = article.querySelectorAll('img');
  var images = [];
  for (var imageIndex = 0; imageIndex < copiedImages.length && imageIndex < originalImages.length; imageIndex++) {
    var source = originalImages[imageIndex].currentSrc || originalImages[imageIndex].src || '';
    if (!/^https?:\/\//i.test(source)) continue;
    var path = source.split('?')[0].split('#')[0];
    var extension = (path.match(/\.([a-zA-Z0-9]+)$/) || [])[1] || 'jpg';
    extension = /^(jpg|jpeg|png|gif|webp|avif|svg)$/i.test(extension) ? extension.toLowerCase() : 'jpg';
    var fileName = 'image-' + imageIndex + '.' + extension;
    copiedImages[imageIndex].setAttribute('src', 'images/' + fileName);
    copiedImages[imageIndex].removeAttribute('srcset');
    copiedImages[imageIndex].removeAttribute('data-src');
    images.push({ index: imageIndex, url: source, fileName: fileName });
  }
  function normalizedText(node) {
    return (node.textContent || '').replace(/\s+/g, ' ').trim();
  }
  function markdownFor(node) {
    if (!node) return '';
    if (node.nodeType === 3) return (node.nodeValue || '').replace(/\s+/g, ' ');
    if (node.nodeType !== 1) return '';
    var tag = node.tagName.toLowerCase();
    if (tag === 'img') {
      var imageSource = node.getAttribute('src') || '';
      var imageAlt = (node.getAttribute('alt') || '').replace(/[\[\]]/g, '');
      return imageSource ? '![' + imageAlt + '](' + imageSource + ')' : '';
    }
    if (tag === 'pre') {
      var fence = String.fromCharCode(96, 96, 96);
      return '\n\n' + fence + '\n' + (node.textContent || '').trim() + '\n' + fence + '\n\n';
    }
    var childMarkdown = '';
    for (var childIndex = 0; childIndex < node.childNodes.length; childIndex++) {
      childMarkdown += markdownFor(node.childNodes[childIndex]);
    }
    childMarkdown = childMarkdown.trim();
    if (!childMarkdown) return '';
    if (/^h[1-6]$/.test(tag)) {
      return '\n\n' + new Array(Number(tag.substring(1)) + 1).join('#') + ' ' + childMarkdown + '\n\n';
    }
    if (tag === 'p' || tag === 'section' || tag === 'div') return '\n\n' + childMarkdown + '\n\n';
    if (tag === 'li') return '\n- ' + childMarkdown;
    if (tag === 'blockquote') return '\n\n> ' + childMarkdown.replace(/\n/g, '\n> ') + '\n\n';
    if (tag === 'br') return '\n';
    if (tag === 'strong' || tag === 'b') return '**' + childMarkdown + '**';
    if (tag === 'em' || tag === 'i') return '*' + childMarkdown + '*';
    if (tag === 'a') {
      var link = node.getAttribute('href') || '';
      return link ? '[' + childMarkdown + '](' + link + ')' : childMarkdown;
    }
    return childMarkdown;
  }
  var canonical = document.querySelector('link[rel="canonical"]');
  var authorMeta = document.querySelector(
    'meta[name="author"],meta[property="article:author"],[rel="author"],[itemprop="author"]'
  );
  var author = authorMeta ? (authorMeta.getAttribute('content') || normalizedText(authorMeta)) : '';
  var heading = best.querySelector('h1');
  var title = extraction.title || (heading ? normalizedText(heading) : (document.title || ''));
  var text = normalizedText(article);
  var markdown = markdownFor(article).replace(/\n{3,}/g, '\n\n').trim();
  return JSON.stringify({
    title: title,
    author: author,
    canonicalUrl: canonical && canonical.href ? canonical.href : location.href,
    sourceUrl: location.href,
    html: article.outerHTML || '',
    text: text,
    markdown: markdown,
    images: images,
    readerMetrics: {
      result: extraction.result,
      strategy: extraction.strategy,
      candidateChars: extraction.candidateChars,
      outputChars: extraction.outputChars,
      retainedRatio: extraction.retainedRatio,
      paragraphCount: extraction.paragraphCount,
      imageCount: extraction.imageCount,
      durationMs: extraction.durationMs
    }
  });
})();
