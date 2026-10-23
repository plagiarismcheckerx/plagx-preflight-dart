// Text structure helpers: words, lines, paragraphs, headings, sentences, syllables.
// All offsets are UTF-16 code-unit offsets into the original text, as in JavaScript.
import 'js.dart';

/// A piece of text with UTF-16 offsets.
class Span {
  const Span(this.text, this.start, this.end);
  final String text;
  final int start;
  final int end;
}

/// A paragraph: a run of non-blank lines.
class Paragraph extends Span {
  Paragraph(super.text, super.start, super.end) : heading = _isHeading(text);
  final bool heading;
}

/// A document split into body and reference list.
class Document {
  Document(this.paragraphs, this.body, this.bodyEnd, this.referenceHeading, this.entries);
  final List<Paragraph> paragraphs;
  final List<Paragraph> body;
  final int bodyEnd;
  final Paragraph? referenceHeading;
  final List<Span> entries;
}

final _wordRe = RegExp(r"[\p{L}\p{M}0-9]+(?:['\u2019-][\p{L}\p{M}0-9]+)*", unicode: true);

const _abbreviations = {
  'al', 'approx', 'cf', 'co', 'dept', 'dr', 'ed', 'eds', 'eg', 'et', 'etc', 'fig', 'figs', 'ie', //
  'inc', 'jr', 'ltd', 'mr', 'mrs', 'ms', 'no', 'nos', 'p', 'pp', 'prof', 'sr', 'st', 'vol', 'vols', 'vs',
};

const referenceHeadings = {
  'references',
  'reference list',
  'bibliography',
  'works cited',
  'work cited',
  'sources',
  'literature cited',
};

List<Span> words(String text) => [for (final m in _wordRe.allMatches(text)) Span(m.group(0)!, m.start, m.end)];

int countWords(String text) => _wordRe.allMatches(text).length;

List<int> lineStarts(String text) {
  final starts = [0];
  for (var i = 0; i < text.length; i += 1) {
    if (text.codeUnitAt(i) == 0x0A) starts.add(i + 1);
  }
  return starts;
}

int lineIndex(List<int> starts, int offset) {
  var lo = 0;
  var hi = starts.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (starts[mid] <= offset) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0D || c == 0x0A || c == 0x0C || c == 0x0B || c == 0xA0;

(int, int) _trimRange(String text, int s, int e) {
  while (s < e && _isSpace(text.codeUnitAt(s))) {
    s += 1;
  }
  while (e > s && _isSpace(text.codeUnitAt(e - 1))) {
    e -= 1;
  }
  return (s, e);
}

final _hashes = RegExp(r'^#+\s*');
final _numbering = RegExp(r'^(?:\d+(?:\.\d+)*\.?|[ivxlc]+\.)\s+', caseSensitive: false);
final _colon = RegExp(r'\s*:$');
final _spaces = RegExp(r'\s+');
final _headingEnd = RegExp('[.!?,;"\'\u201d\u2019)\\]]\$');
final _headingStart = RegExp(r'^[\p{Lu}0-9]', unicode: true);
final _blankLine = RegExp(r'^[ \t\r\f\v\u00a0]*$');

String normalizeHeading(String s) =>
    jsLower(jsTrim(s).replaceFirst(_hashes, '').replaceFirst(_numbering, '').replaceFirst(_colon, '').replaceAll(_spaces, ' '));

bool _isHeading(String t) {
  if (t.contains('\n')) return false;
  if (t.startsWith('#')) return true;
  if (referenceHeadings.contains(normalizeHeading(t))) return true;
  final n = countWords(t);
  if (n < 1 || n > 10) return false;
  if (_headingEnd.hasMatch(t)) return false;
  return _headingStart.hasMatch(t);
}

List<Paragraph> paragraphs(String text) {
  final out = <Paragraph>[];
  final starts = lineStarts(text);
  var blockStart = -1;
  var blockEnd = -1;
  void flush() {
    if (blockStart < 0) return;
    final (s, e) = _trimRange(text, blockStart, blockEnd);
    out.add(Paragraph(text.substring(s, e), s, e));
    blockStart = -1;
  }

  for (var i = 0; i < starts.length; i += 1) {
    final ls = starts[i];
    final le = i + 1 < starts.length ? starts[i + 1] - 1 : text.length;
    if (_blankLine.hasMatch(text.substring(ls, le))) {
      flush();
    } else {
      if (blockStart < 0) blockStart = ls;
      blockEnd = le;
    }
  }
  flush();
  return out;
}

Document structure(String text) {
  final paras = paragraphs(text);
  final idx = paras.indexWhere((p) => p.heading && referenceHeadings.contains(normalizeHeading(p.text)));
  final body = idx < 0 ? paras : paras.sublist(0, idx);
  final heading = idx < 0 ? null : paras[idx];
  final entries = <Span>[];
  if (heading != null) {
    final starts = lineStarts(text);
    for (var i = 0; i < starts.length; i += 1) {
      final ls = starts[i];
      if (ls <= heading.end) continue;
      final le = i + 1 < starts.length ? starts[i + 1] - 1 : text.length;
      final (s, e) = _trimRange(text, ls, le);
      if (e > s) entries.add(Span(text.substring(s, e), s, e));
    }
  }
  return Document(paras, body, heading == null ? text.length : heading.start, heading, entries);
}

final _terminator = RegExp('[.!?]+["\'\u201d\u2019)\\]]*(?=\\s|\$)');
final _closers = RegExp('["\'\u201d\u2019)\\]]+\$');
final _before = RegExp(r'(?:^|[\s(])([\p{L}.]+)$', unicode: true);
final _oneLetter = RegExp(r'^\p{L}$', unicode: true);

List<Span> _sentencesIn(String s, int base) {
  final out = <Span>[];
  var start = 0;
  void push(int end) {
    final (a, b) = _trimRange(s, start, end);
    if (b > a) out.add(Span(s.substring(a, b), base + a, base + b));
    start = end;
  }

  for (final m in _terminator.allMatches(s)) {
    final marks = m.group(0)!.replaceFirst(_closers, '');
    if (marks.startsWith('..')) continue; // an ellipsis
    if (marks == '.') {
      // A lone period after an abbreviation, an initial or a dotted form (U.S.) does not end a sentence.
      final b = _before.firstMatch(s.substring(0, m.start));
      if (b != null) {
        final w = jsLower(b.group(1)!);
        if (_abbreviations.contains(w) || _oneLetter.hasMatch(w) || w.contains('.')) continue;
      }
    }
    push(m.end);
  }
  push(s.length);
  return out;
}

List<Span> splitSentences(String text) => [
      for (final p in paragraphs(text))
        if (p.heading) Span(p.text, p.start, p.end) else ..._sentencesIn(p.text, p.start),
    ];

List<Span> paragraphSentences(Paragraph p) => _sentencesIn(p.text, p.start);

final _notAz = RegExp(r'[^a-z]');
final _ending = RegExp(r'(?:[^laeiouy]es|ed|[^laeiouy]e)$');
final _vowels = RegExp(r'[aeiouy]+');

int syllables(String word) {
  var w = jsLower(word).replaceAll(_notAz, '');
  if (w.isEmpty) return 0;
  if (w.length <= 3) return 1;
  w = w.replaceFirst(_ending, '');
  if (w.startsWith('y')) w = w.substring(1);
  final n = _vowels.allMatches(w).length;
  return n > 0 ? n : 1;
}
