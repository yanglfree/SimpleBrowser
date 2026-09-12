(function() {
  var fields = document.querySelectorAll('input:not([type="password"]),textarea,select');
  var draft = [];
  for (var i = 0; i < fields.length && draft.length < 80; i++) {
    var field = fields[i];
    var key = field.id || field.name || ('field-' + i);
    var value = field.value || '';
    if (value.length > 0) draft.push({ key: key, value: value });
  }
  return JSON.stringify(draft);
})();
