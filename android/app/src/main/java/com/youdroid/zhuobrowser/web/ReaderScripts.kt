package com.youdroid.zhuobrowser.web

import android.content.res.AssetManager
import com.youdroid.zhuobrowser.session.ReaderSettings
import com.youdroid.zhuobrowser.session.ReaderTheme
import org.json.JSONObject
import org.json.JSONTokener

object ReaderScripts {
    fun apply(assets: AssetManager, settings: ReaderSettings): String {
        val core = WebKernel.loadScript(assets, "reader-extraction-core.js").orEmpty()
        val theme = ReaderTheme.theme(settings.paper)
        val fontSize = settings.fontSize
        return """
        $core
        (function(fontSize, lineHeight, paper, body, title, accent) {
          var S = window.__mbReader || (window.__mbReader = {});

          if (!S.active) {
            var extraction = window.__zhuoReaderExtract(document);
            if (!extraction.node || extraction.result === 'unavailable') {
              return JSON.stringify({ status: 'no-article', result: extraction.result, strategy: extraction.strategy });
            }

            S.body = document.body.innerHTML;
            S.bodyStyle = document.body.getAttribute('style') || '';
            S.scroll = window.scrollY;
            S.metrics = extraction;

            var viewport = document.querySelector('meta[name="viewport"]');
            S.viewportExisted = !!viewport;
            S.viewportContent = viewport ? viewport.getAttribute('content') : null;
            if (!viewport) {
              viewport = document.createElement('meta');
              viewport.setAttribute('name', 'viewport');
              document.head.appendChild(viewport);
            }
            viewport.setAttribute('content', 'width=device-width, initial-scale=1, user-scalable=yes, maximum-scale=5');

            document.body.innerHTML = '';
            var article = document.createElement('article');
            article.id = '__mb-reader';

            var titleNode = document.createElement('h1');
            titleNode.textContent = extraction.title;
            article.appendChild(titleNode);

            var wrapper = document.createElement('div');
            wrapper.className = '__mb-reader-body';
            wrapper.appendChild(extraction.node);
            article.appendChild(wrapper);

            document.body.appendChild(article);
            window.scrollTo(0, 0);
            S.active = true;
          }

          try {
            document.onselectstart = null;
            document.oncopy = null;
            document.oncontextmenu = null;
            if (document.body) {
              document.body.onselectstart = null;
              document.body.oncopy = null;
              document.body.oncontextmenu = null;
            }
          } catch (e) {}

          var sheet = document.getElementById('__mb-reader-css');
          if (!sheet) {
            sheet = document.createElement('style');
            sheet.id = '__mb-reader-css';
            document.head.appendChild(sheet);
          }
          sheet.textContent =
            'html,body{background:' + paper + ' !important;margin:0 !important;padding:0 !important;' +
              '-webkit-user-select:text !important;user-select:text !important;-webkit-touch-callout:default !important}' +
            '#__mb-reader, #__mb-reader *{-webkit-user-select:text !important;user-select:text !important;-webkit-touch-callout:default !important}' +
            '#__mb-reader{box-sizing:border-box;width:100%;max-width:680px;margin:0 auto;padding:26px 22px 64px;' +
              'font-family:"Noto Serif SC","Songti SC",Georgia,serif;color:' + body + '}' +
            '#__mb-reader h1{font-size:' + (fontSize + 8) + 'px;line-height:1.55;font-weight:600;' +
              'color:' + title + ';margin:0 0 22px;text-wrap:pretty}' +
            '#__mb-reader .__mb-reader-body{font-size:' + fontSize + 'px;line-height:' + lineHeight + ';' +
              'text-align:justify;color:' + body + '}' +
            '#__mb-reader p{margin:0 0 ' + Math.round(fontSize * 1.3) + 'px}' +
            '#__mb-reader h2,#__mb-reader h3{color:' + title + ';line-height:1.5;margin:1.6em 0 .6em}' +
            '#__mb-reader img{max-width:100%;height:auto;border-radius:10px;display:block;margin:22px auto}' +
            '#__mb-reader a{color:' + accent + ';text-decoration:none}' +
            '#__mb-reader pre,#__mb-reader code{font-family:ui-monospace,Menlo,monospace;font-size:' +
              (fontSize - 3) + 'px}' +
            '#__mb-reader pre{overflow-x:auto;padding:14px;border-radius:10px;background:rgba(128,128,128,.12)}' +
            '#__mb-reader blockquote{margin:1.4em 0;padding-left:16px;border-left:2px solid ' + accent + ';opacity:.85}';

          document.body.setAttribute('style', 'margin:0;background:' + paper + ';-webkit-user-select:text !important;user-select:text !important;');
          var metrics = S.metrics || {};
          return JSON.stringify({ status: 'reader', result: metrics.result || 'complete',
            strategy: metrics.strategy || 'unknown', candidateChars: metrics.candidateChars || 0,
            outputChars: metrics.outputChars || 0, retainedRatio: metrics.retainedRatio || 0,
            paragraphCount: metrics.paragraphCount || 0, imageCount: metrics.imageCount || 0,
            durationMs: metrics.durationMs || 0 });
        })($fontSize, '${settings.lineHeightCss}', '${theme.background}', '${theme.body}', '${theme.title}', '${theme.accent}');
        """.trimIndent()
    }

    fun exit(assets: AssetManager): String =
        WebKernel.loadScript(assets, "reader-exit.js") ?: "(function(){return 'not-reader'})();"

    fun isReaderStatus(raw: String?): Boolean {
        if (raw.isNullOrBlank() || raw == "null") return false
        val value = runCatching { JSONTokener(raw).nextValue() }.getOrNull() ?: return false
        val obj = when (value) {
            is JSONObject -> value
            is String -> runCatching { JSONObject(value) }.getOrNull() ?: return false
            else -> return false
        }
        return obj.optString("status") == "reader"
    }
}
