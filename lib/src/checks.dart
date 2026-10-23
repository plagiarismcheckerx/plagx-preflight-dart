// The individual check groups. Each reports issues through Context.add().
import 'citations.dart';
import 'js.dart';
import 'text.dart';

const longSentenceWords = 40;
const longParagraphWords = 250;

/// An issue before line and column are added.
class RawIssue {
  RawIssue(this.level, this.code, this.message, this.start, this.end, this.suggestion);
  final String level;
  final String code;
  final String message;
  final int start;
  final int end;
  final String? suggestion;
}

/// Normalised options.
class CheckOptions {
  CheckOptions(this.minWords, this.maxWords, this.style, this.checks, this.requiredHeadings);
  final int? minWords;
  final int? maxWords;
  final String style;
  final List<String> checks;
  final List<String> requiredHeadings;
}

// Codes inside URLs, email addresses and `code` are skipped.
final _masked = RegExp(
    r'^(?:unmatched-|double-space|space-before|missing-space|repeated-|mixed-quote|a-an|sentence-capital|lowercase-i|common-confusion|passive-voice)');
final _maskRe = RegExp(r'\bhttps?:\/\/[^\s<>()]+|\bwww\.[^\s<>()]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+|`[^`\n]*`');

/// State shared by the checks for one checkDraft() call.
class Context {
  Context(this.text, this.opts, this.doc, this.words)
      : bodyText = text.substring(0, doc.bodyEnd),
        _masks = [for (final m in _maskRe.allMatches(text)) (m.start, m.end)];

  final String text;
  final CheckOptions opts;
  final Document doc;
  final int words;
  final String bodyText;
  final List<(int, int)> _masks;
  final _seen = <String>{};
  final issues = <RawIssue>[];

  List<Paragraph> get body => doc.body;

  void add(String level, String code, int start, int end, String message, [String? suggestion]) {
    if (_masked.hasMatch(code) && _masks.any((m) => start < m.$2 && end > m.$1)) return;
    if (!_seen.add('$code:$start:$end:$message')) return;
    issues.add(RawIssue(level, code, message, start, end, suggestion));
  }

  void addDoc(String level, String code, String message) => add(level, code, 0, 0, message);
}

final _upperStart = RegExp(r'^\p{Lu}', unicode: true);

String _matchCase(String fix, String original) => _upperStart.hasMatch(original) ? upperFirst(fix) : fix;

bool _startsWithAny(String w, List<String> prefixes) => prefixes.any(w.startsWith);

// ---------------------------------------------------------------- length

final _listItem = RegExp(r'^(?:[-*+•]|\d+[.)])\s');

void length(Context ctx) {
  final w = ctx.words;
  final o = ctx.opts;
  if (o.minWords != null && w < o.minWords!) {
    ctx.addDoc('warning', 'word-count-low', 'Suggestion: the draft has $w words; the minimum is ${o.minWords}.');
  }
  if (o.maxWords != null && w > o.maxWords!) {
    ctx.addDoc('warning', 'word-count-high', 'Suggestion: the draft has $w words; the maximum is ${o.maxWords}.');
  }
  for (final p in ctx.body) {
    if (p.heading) continue;
    final sentences = paragraphSentences(p);
    for (final s in sentences) {
      final n = countWords(s.text);
      if (n > longSentenceWords) {
        ctx.add('warning', 'long-sentence', s.start, s.end,
            'Suggestion: this sentence has $n words; consider splitting it (over $longSentenceWords).');
      }
    }
    final n = countWords(p.text);
    if (n > longParagraphWords) {
      ctx.add('info', 'long-paragraph', p.start, p.end,
          'Suggestion: this paragraph has $n words; consider splitting it (over $longParagraphWords).');
    }
    if (sentences.length == 1 && !_listItem.hasMatch(p.text)) {
      ctx.add('info', 'single-sentence-paragraph', p.start, p.end, 'Suggestion: this paragraph has only one sentence.');
    }
  }
  final headings = {
    for (final p in ctx.doc.paragraphs)
      if (p.heading) normalizeHeading(p.text)
  };
  for (final h in o.requiredHeadings) {
    if (!headings.contains(normalizeHeading(h))) ctx.addDoc('warning', 'missing-heading', 'Suggestion: add a "$h" heading.');
  }
}

// ---------------------------------------------------------------- references

final _etAl = RegExp(r'\bet\.?\s*al\b\.*', caseSensitive: false);

void references(Context ctx) {
  final doc = ctx.doc;
  final cites = findCitations(ctx.bodyText, ctx.opts.style);
  if (cites.isNotEmpty && doc.referenceHeading == null) {
    ctx.addDoc('error', 'missing-reference-section',
        'Suggestion: the draft has citations but no reference list heading (References or Works Cited).');
  }
  final entries = doc.entries.map(parseEntry).toList();
  if (doc.referenceHeading != null) {
    for (final c in cites) {
      if (!entries.any((e) => citationMatches(c, e))) {
        ctx.add('error', 'citation-no-reference', c.start, c.end, 'Suggestion: "${c.text}" has no matching entry in the reference list.');
      }
    }
    for (final e in entries) {
      if (!cites.any((c) => citationMatches(c, e))) {
        ctx.add('warning', 'reference-not-cited', e.start, e.end, 'Suggestion: this reference is never cited in the text.');
      }
    }
  }
  for (final m in _etAl.allMatches(ctx.bodyText)) {
    if (jsLower(m.group(0)!) != 'et al.') {
      ctx.add('warning', 'et-al-format', m.start, m.end, 'Suggestion: write "et al." with one period.', 'et al.');
    }
  }
}

// ---------------------------------------------------------------- punctuation

const _pairs = {')': '(', ']': '[', '}': '{'};
final _listMarkerBefore = RegExp(r'(?:^|\s)[A-Za-z0-9]{1,3}$');
final _doubleSpace = RegExp(r'(?<=\S) {2,}(?=\S)');
final _spaceBefore = RegExp(r'(?<=[\p{L}0-9)\]"”]) +([,;:!?.])(?=\s|$)', unicode: true);
final _missingSpace = RegExp(r'[,;:!?](?=[A-Za-z])|(?<=[a-z]{2})\.(?=[A-Z][a-z])');
final _repeated = RegExp(r'([!?,;:])\1+|(?<!\.)\.\.(?!\.)');
const _unmatched = 'Suggestion: this quotation mark has no matching pair.';

void punctuation(Context ctx) {
  var straight = -1;
  var curly = -1;
  for (final p in ctx.body) {
    final t = p.text;
    final at = p.start;

    // Quotation marks
    final quotes = [
      for (var i = 0; i < t.length; i += 1)
        if (t[i] == '"') i
    ];
    if (quotes.isNotEmpty && straight < 0) straight = at + quotes.first;
    if (quotes.length.isOdd) {
      final i = quotes.last;
      ctx.add('warning', 'unmatched-quote', at + i, at + i + 1, _unmatched);
    }
    final open = <int>[];
    for (var i = 0; i < t.length; i += 1) {
      if ((t[i] == '“' || t[i] == '”') && curly < 0) curly = at + i;
      if (t[i] == '“') {
        open.add(i);
      } else if (t[i] == '”') {
        if (open.isNotEmpty) {
          open.removeLast();
        } else {
          ctx.add('warning', 'unmatched-quote', at + i, at + i + 1, _unmatched);
        }
      }
    }
    for (final i in open) {
      ctx.add('warning', 'unmatched-quote', at + i, at + i + 1, _unmatched);
    }

    // Brackets
    final stack = <int>[];
    for (var i = 0; i < t.length; i += 1) {
      final c = t[i];
      if (c == '(' || c == '[' || c == '{') {
        stack.add(i);
      } else if (_pairs.containsKey(c)) {
        if (stack.isNotEmpty && t[stack.last] == _pairs[c]) {
          stack.removeLast();
        } else {
          // List markers such as "a)", "ii)" or "1)".
          if (c == ')' && _listMarkerBefore.hasMatch(t.substring(0, i))) continue;
          ctx.add('warning', 'unmatched-bracket', at + i, at + i + 1, 'Suggestion: "$c" has no matching bracket.');
        }
      }
    }
    for (final i in stack) {
      ctx.add('warning', 'unmatched-bracket', at + i, at + i + 1, 'Suggestion: "${t[i]}" has no matching bracket.');
    }

    for (final m in _doubleSpace.allMatches(t)) {
      ctx.add('info', 'double-space', at + m.start, at + m.end, 'Suggestion: use a single space.', ' ');
    }
    for (final m in _spaceBefore.allMatches(t)) {
      ctx.add('warning', 'space-before-punctuation', at + m.start, at + m.end, 'Suggestion: remove the space before "${m.group(1)}".',
          m.group(1));
    }
    for (final m in _missingSpace.allMatches(t)) {
      ctx.add('warning', 'missing-space-after-punctuation', at + m.start, at + m.start + 1,
          'Suggestion: add a space after "${m.group(0)}".', '${m.group(0)} ');
    }
    for (final m in _repeated.allMatches(t)) {
      ctx.add(
          'warning', 'repeated-punctuation', at + m.start, at + m.end, 'Suggestion: "${m.group(0)}" repeats punctuation.', m.group(0)![0]);
    }
  }
  if (straight >= 0 && curly >= 0) {
    final i = straight > curly ? straight : curly;
    ctx.add('info', 'mixed-quote-styles', i, i + 1, 'Suggestion: the draft mixes straight and curly quotation marks.');
  }
}

// ---------------------------------------------------------------- grammar

const _silentH = ['hour', 'honest', 'honor', 'honour', 'heir'];
const _consonantSound = ['uni', 'use', 'usa', 'usu', 'uti', 'ure', 'uro', 'urani', 'eu', 'ewe', 'one', 'once', 'ubiq', 'unanim'];
const _uncertain = ['herb', 'histor', 'hotel', 'unin', 'unim', 'unid', 'oner'];

RegExp _ci(String pattern) => RegExp(pattern, caseSensitive: false);

final _confusions = <(RegExp, String Function(Match))>[
  (_ci(r'\b(could|would|should|must|might) of\b'), (m) => '${m.group(1)} have'),
  (_ci(r'\bits (a|an|been|not|going)\b'), (m) => "it's ${m.group(1)}"),
  (_ci(r"\bit['’]s own\b"), (m) => 'its own'),
  (
    _ci(r'\b(more|less|better|worse|rather|greater|fewer|larger|smaller|higher|lower|faster|slower|easier|harder) then\b'),
    (m) => '${m.group(1)} than'
  ),
  (_ci(r'\btheir (is|are|was|were)\b'), (m) => 'there ${m.group(1)}'),
  (_ci(r'\bthere own\b'), (m) => 'their own'),
  (_ci(r'\b(the|an) affect\b'), (m) => '${m.group(1)} effect'),
  (_ci(r'\b(may|might|will|can|could|would|should|negatively|positively|greatly|significantly) effect\b'), (m) => '${m.group(1)} affect'),
  (_ci(r'\bloose (weight|track|control)\b'), (m) => 'lose ${m.group(1)}'),
  (_ci(r'\balot\b'), (m) => 'a lot'),
];

final _passive = _ci(
    r'\b(?:am|is|are|was|were|be|been|being)\s+(?:[a-z]+ly\s+)?(?:[a-z]{3,}ed|written|done|made|given|taken|shown|seen|known|found|held|chosen|built|drawn|taught|thought|brought|said|told|sent|kept|paid|begun|broken|driven|eaten|forgotten|hidden|spoken|stolen|worn)\b');
final _iForm = RegExp(r"^i(['’](?:m|ve|ll|d))?$");
final _gap = RegExp(r'^\s+$');
final _hasLetter = RegExp(r'\p{L}', unicode: true);
final _lowerStart = RegExp(r'^\p{Ll}', unicode: true);
final _hasUpper = RegExp(r'\p{Lu}', unicode: true);
final _digit = RegExp(r'[0-9]');
final _asciiLowerStart = RegExp(r'^[a-z]');
final _vowelStart = RegExp(r'^[aeiou]');

void grammar(Context ctx) {
  for (final p in ctx.body) {
    final t = p.text;
    final toks = words(t);
    for (var i = 0; i < toks.length; i += 1) {
      final tok = toks[i];
      final low = jsLower(tok.text);
      final next = i + 1 < toks.length && _gap.hasMatch(t.substring(tok.end, toks[i + 1].start)) ? toks[i + 1] : null;

      if (next != null && jsLower(next.text) == low && _hasLetter.hasMatch(low) && low != 'had' && low != 'that') {
        ctx.add('warning', 'repeated-word', p.start + tok.start, p.start + next.end,
            'Suggestion: "${tok.text} ${next.text}" looks like a repeated word.', tok.text);
      }

      if (next != null && (low == 'a' || low == 'an')) {
        final nw = next.text.split('-').first;
        final nl = jsLower(nw);
        final acronym = nw.length > 1 && nw == jsUpper(nw);
        if (nw.length > 1 && !_digit.hasMatch(nw) && !acronym && _asciiLowerStart.hasMatch(nl) && !_startsWithAny(nl, _uncertain)) {
          final vowel = _startsWithAny(nl, _silentH) || (_vowelStart.hasMatch(nl) && !_startsWithAny(nl, _consonantSound));
          final expected = vowel ? 'an' : 'a';
          if (low != expected) {
            ctx.add('warning', 'a-an', p.start + tok.start, p.start + tok.end, 'Suggestion: use "$expected" before "${next.text}".',
                _matchCase(expected, tok.text));
          }
        }
      }

      final im = _iForm.firstMatch(tok.text);
      if (im != null) {
        final before = tok.start > 0 ? t[tok.start - 1] : '';
        final after = tok.end < t.length ? t[tok.end] : '';
        if (im.group(1) != null || (after != '.' && after != ')' && before != '.')) {
          final fix = upperFirst(tok.text);
          ctx.add(
              'warning', 'lowercase-i', p.start + tok.start, p.start + tok.end, 'Suggestion: use "$fix" instead of "${tok.text}".', fix);
        }
      }
    }

    if (!p.heading) {
      for (final s in paragraphSentences(p)) {
        final ws = words(s.text);
        if (ws.isEmpty) continue;
        final first = ws.first;
        if (first.start == 0 &&
            _lowerStart.hasMatch(first.text) &&
            !_hasUpper.hasMatch(first.text) &&
            !_iForm.hasMatch(first.text) &&
            (first.end >= s.text.length || s.text[first.end] != ')')) {
          ctx.add('warning', 'sentence-capital', s.start, s.start + first.end, 'Suggestion: start the sentence with a capital letter.',
              upperFirst(first.text));
        }
      }
    }

    for (final (re, fix) in _confusions) {
      for (final m in re.allMatches(t)) {
        final suggestion = _matchCase(fix(m), m.group(0)!);
        ctx.add('warning', 'common-confusion', p.start + m.start, p.start + m.end, 'Suggestion: "${m.group(0)}" may be "$suggestion".',
            suggestion);
      }
    }
  }
}

void passiveVoice(Context ctx) {
  for (final p in ctx.body) {
    for (final m in _passive.allMatches(p.text)) {
      ctx.add('info', 'passive-voice', p.start + m.start, p.start + m.end, 'Suggestion: "${m.group(0)}" may be passive voice.');
    }
  }
}
