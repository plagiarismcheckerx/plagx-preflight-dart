// JavaScript string semantics the port needs. Dart's RegExp follows JavaScript,
// but trim() and case mapping differ, so these helpers reproduce the JavaScript results.
import 'case_data.dart';

final _trimRe = RegExp(r'^\s+|\s+$');

/// String.prototype.trim() (Dart's trim() also removes U+0085).
String jsTrim(String s) => s.replaceAll(_trimRe, '');

bool _isCased(int cp) => upperMap.containsKey(cp) || lowerMap.containsKey(cp);

/// String.prototype.toLowerCase(), including the final-sigma rule.
String jsLower(String s) {
  final runes = s.runes.toList();
  final out = StringBuffer();
  for (var i = 0; i < runes.length; i += 1) {
    final cp = runes[i];
    if (cp == 0x3A3) {
      // Final sigma: after a cased letter and not before one.
      final before = i > 0 && _isCased(runes[i - 1]);
      final after = i + 1 < runes.length && _isCased(runes[i + 1]);
      out.writeCharCode(before && !after ? 0x3C2 : 0x3C3);
      continue;
    }
    final m = lowerMap[cp];
    if (m == null) {
      out.writeCharCode(cp);
    } else {
      m.forEach(out.writeCharCode);
    }
  }
  return out.toString();
}

/// String.prototype.toUpperCase().
String jsUpper(String s) {
  final out = StringBuffer();
  for (final cp in s.runes) {
    final m = upperMap[cp];
    if (m == null) {
      out.writeCharCode(cp);
    } else {
      m.forEach(out.writeCharCode);
    }
  }
  return out.toString();
}

/// s.charAt(0).toUpperCase() + s.slice(1): only the first UTF-16 unit changes.
String upperFirst(String s) {
  if (s.isEmpty) return s;
  final c = s.codeUnitAt(0);
  if (c >= 0xD800 && c <= 0xDFFF) return s;
  return jsUpper(s.substring(0, 1)) + s.substring(1);
}

/// A stable sort (Dart's List.sort is not stable; JavaScript's is).
void stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = List.generate(list.length, (i) => (i, list[i]));
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < list.length; i += 1) {
    list[i] = indexed[i].$2;
  }
}
