/// A deliberately small Valve KeyValue parser. It accepts comments, quoted
/// strings and nested braces used by libraryfolders, ACF and localconfig files.
class VdfNode {
  VdfNode(this.values);
  final Map<String, Object> values;
  String? string(String key) => values.entries
      .where((e) => e.key.toLowerCase() == key.toLowerCase())
      .map((e) => e.value is String ? e.value as String : null)
      .whereType<String>()
      .firstOrNull;
  VdfNode? child(String key) => values.entries
      .where((e) => e.key.toLowerCase() == key.toLowerCase())
      .map((e) => e.value is VdfNode ? e.value as VdfNode : null)
      .whereType<VdfNode>()
      .firstOrNull;
}

class VdfParser {
  VdfParser(String source) : _tokens = _tokenize(source);
  final List<String> _tokens;
  int _index = 0;
  VdfNode parse() => _readBlock(untilBrace: false);
  VdfNode _readBlock({required bool untilBrace}) {
    final values = <String, Object>{};
    while (_index < _tokens.length) {
      if (_tokens[_index] == '}') {
        _index++;
        break;
      }
      if (_tokens[_index] == '{') {
        _index++;
        continue;
      }
      final key = _tokens[_index++];
      if (_index >= _tokens.length) break;
      if (_tokens[_index] == '{') {
        _index++;
        values[key] = _readBlock(untilBrace: true);
      } else if (_tokens[_index] != '}')
        values[key] = _tokens[_index++];
      else if (untilBrace)
        break;
    }
    return VdfNode(values);
  }

  static List<String> _tokenize(String input) {
    final out = <String>[];
    var i = 0;
    while (i < input.length) {
      final c = input[i];
      if (c == '/' && i + 1 < input.length && input[i + 1] == '/') {
        while (i < input.length && input[i] != '\n') i++;
        continue;
      }
      if (c.trim().isEmpty) {
        i++;
        continue;
      }
      if (c == '{' || c == '}') {
        out.add(c);
        i++;
        continue;
      }
      if (c == '"') {
        i++;
        final b = StringBuffer();
        while (i < input.length && input[i] != '"') {
          if (input[i] == '\\' && i + 1 < input.length) {
            final n = input[++i];
            b.write(n == 'n' ? '\n' : n);
            i++;
          } else
            b.write(input[i++]);
        }
        if (i < input.length) i++;
        out.add(b.toString());
        continue;
      }
      final start = i;
      while (i < input.length &&
          !input[i].trim().isEmpty &&
          input[i] != '{' &&
          input[i] != '}')
        i++;
      out.add(input.substring(start, i));
    }
    return out;
  }
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
