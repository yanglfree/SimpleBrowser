import Foundation

struct PageResumeRequest: Equatable {
    let tabID: String
    let position: Double
    let isReader: Bool
}

enum PageStatePolicy {
    static let messageHandlerName = "pageStateFormDraft"
    static let resumeWindow: TimeInterval = 30 * 24 * 60 * 60
    static let resumePromptDuration: TimeInterval = 7
    static let maximumDraftFields = 80
    static let maximumDraftBytes = 64 * 1024
    private static let maximumKeyLength = 256
    private static let maximumValueLength = 4_096
    private static let capturableFieldSelector =
        "input:not([type=\"password\"]):not([type=\"hidden\"]):not([type=\"file\"]),textarea,select"

    static func shouldOfferResume(
        position: Double,
        savedAt: TimeInterval,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        position > 0 && savedAt > 0 && now >= savedAt && now - savedAt <= resumeWindow
    }

    static func isSamePage(_ left: String, _ right: String) -> Bool {
        guard var leftComponents = URLComponents(string: left),
              var rightComponents = URLComponents(string: right) else {
            return left == right
        }
        leftComponents.fragment = nil
        rightComponents.fragment = nil
        leftComponents.scheme = leftComponents.scheme?.lowercased()
        rightComponents.scheme = rightComponents.scheme?.lowercased()
        leftComponents.host = leftComponents.host?.lowercased()
        rightComponents.host = rightComponents.host?.lowercased()
        if leftComponents.path.isEmpty {
            leftComponents.path = "/"
        }
        if rightComponents.path.isEmpty {
            rightComponents.path = "/"
        }
        return leftComponents == rightComponents
    }

    static func normalizedFormDraft(_ raw: String?) -> String {
        guard let raw,
              !raw.isEmpty,
              raw.utf8.count <= maximumDraftBytes,
              let data = raw.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return ""
        }
        let sanitized = values.prefix(maximumDraftFields).compactMap { item -> [String: String]? in
            guard let key = item["key"] as? String,
                  !key.isEmpty,
                  let value = item["value"] as? String,
                  !value.isEmpty else {
                return nil
            }
            return [
                "key": String(key.prefix(maximumKeyLength)),
                "value": String(value.prefix(maximumValueLength))
            ]
        }
        guard !sanitized.isEmpty,
              let encoded = try? JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys]),
              encoded.count <= maximumDraftBytes else {
            return ""
        }
        return String(decoding: encoded, as: UTF8.self)
    }

    static func restoreScrollScript(position: Double) -> String {
        let safePosition = max(0, Int(position.rounded()))
        return "window.scrollTo(0, \(safePosition)); 'restored';"
    }

    static func restoreFormDraftScript(_ draft: String) -> String? {
        let normalized = normalizedFormDraft(draft)
        guard !normalized.isEmpty,
              let argumentData = try? JSONEncoder().encode(normalized),
              let argument = String(data: argumentData, encoding: .utf8) else {
            return nil
        }
        return """
        (function(serialized) {
          var fields = document.querySelectorAll('\(capturableFieldSelector)');
          var draft = [];
          try { draft = JSON.parse(serialized || '[]'); } catch (error) { return 'invalid'; }
          for (var i = 0; i < fields.length; i++) {
            var field = fields[i];
            var autocomplete = (field.getAttribute('autocomplete') || '').toLowerCase();
            if (autocomplete === 'one-time-code' || autocomplete === 'current-password' ||
                autocomplete === 'new-password' || autocomplete.indexOf('cc-') === 0) continue;
            var key = field.id || field.name || ('field-' + i);
            for (var j = 0; j < draft.length; j++) {
              if (draft[j].key !== key) continue;
              field.value = draft[j].value || '';
              field.dispatchEvent(new Event('input', { bubbles: true }));
              field.dispatchEvent(new Event('change', { bubbles: true }));
              break;
            }
          }
          return 'restored';
        })(\(argument));
        """
    }

    static let captureFormDraftScript = """
    (function() {
      var fields = document.querySelectorAll('\(capturableFieldSelector)');
      var draft = [];
      for (var i = 0; i < fields.length && draft.length < 80; i++) {
        var field = fields[i];
        var autocomplete = (field.getAttribute('autocomplete') || '').toLowerCase();
        if (autocomplete === 'one-time-code' || autocomplete === 'current-password' ||
            autocomplete === 'new-password' || autocomplete.indexOf('cc-') === 0) continue;
        var key = field.id || field.name || ('field-' + i);
        var value = field.value || '';
        if (value.length > 0) draft.push({ key: key, value: value });
      }
      return JSON.stringify(draft);
    })();
    """

    static let formDraftWatcherScript = """
    (function() {
      if (window.__zhuoFormDraftWatcherInstalled) return;
      window.__zhuoFormDraftWatcherInstalled = true;
      var timer = 0;
      function publish() {
        var fields = document.querySelectorAll('\(capturableFieldSelector)');
        var draft = [];
        for (var i = 0; i < fields.length && draft.length < 80; i++) {
          var field = fields[i];
          var autocomplete = (field.getAttribute('autocomplete') || '').toLowerCase();
          if (autocomplete === 'one-time-code' || autocomplete === 'current-password' ||
              autocomplete === 'new-password' || autocomplete.indexOf('cc-') === 0) continue;
          var key = field.id || field.name || ('field-' + i);
          var value = field.value || '';
          if (value.length > 0) draft.push({ key: key, value: value });
        }
        try {
          window.webkit.messageHandlers.pageStateFormDraft.postMessage({
            url: window.location.href,
            draft: JSON.stringify(draft)
          });
        } catch (error) {}
      }
      function schedule() {
        window.clearTimeout(timer);
        timer = window.setTimeout(publish, 250);
      }
      document.addEventListener('input', schedule, true);
      document.addEventListener('change', schedule, true);
    })();
    """
}
