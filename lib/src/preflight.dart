// Plagx Preflight: a draft checker with basic grammar suggestions.
// A free academic writing utility by Plagiarism Checker X. Runs fully offline.
import 'checks.dart' as chk;
import 'citations.dart' as citations;
import 'js.dart';
import 'text.dart' as text;

/// Library version.
const version = '0.1.2';

/// Check groups. 'passive-voice' is off by default.
const allChecks = ['length', 'references', 'punctuation', 'grammar', 'passive-voice'];

/// Checks run when no list is given.
const defaultChecks = ['length', 'references', 'punctuation', 'grammar'];

/// Citation styles.
const styles = citations.styles;

const _runners = <String, void Function(chk.Context)>{
  'length': chk.length,
  'references': chk.references,
  'punctuation': chk.punctuation,
  'grammar': chk.grammar,
  'passive-voice': chk.passiveVoice,
};

/// Word count and readability of a draft.
class DraftStats {
  const DraftStats(this.words, this.sentences, this.paragraphs, this.characters, this.readingTimeMinutes, this.fleschReadingEase);
  final int words;
  final int sentences;
  final int paragraphs;

  /// Unicode code points in the whole text.
  final int characters;
  final int readingTimeMinutes;
  final num fleschReadingEase;

  Map<String, Object?> toJson() => {
        'words': words,
        'sentences': sentences,
        'paragraphs': paragraphs,
        'characters': characters,
        'readingTimeMinutes': readingTimeMinutes,
        'fleschReadingEase': fleschReadingEase,
      };
}

/// One suggestion. [start], [end] and [column] are UTF-16 offsets, so they index Dart strings directly.
class DraftIssue {
  const DraftIssue(this.level, this.code, this.message, this.start, this.end, this.line, this.column, this.text, this.suggestion);

  /// 'error', 'warning' or 'info'.
  final String level;
  final String code;
  final String message;
  final int start;
  final int end;
  final int line;
  final int column;
  final String text;
  final String? suggestion;

  Map<String, Object?> toJson() => {
        'level': level,
        'code': code,
        'message': message,
        'start': start,
        'end': end,
        'line': line,
        'column': column,
        'text': text,
        'suggestion': suggestion,
      };
}

/// Result of [checkDraft].
class DraftResult {
  const DraftResult(this.stats, this.errors, this.warnings, this.infos, this.issues);
  final DraftStats stats;
  final int errors;
  final int warnings;
  final int infos;
  final List<DraftIssue> issues;

  Map<String, Object?> toJson() => {
        'stats': stats.toJson(),
        'errors': errors,
        'warnings': warnings,
        'infos': infos,
        'issues': [for (final i in issues) i.toJson()],
      };
}

/// JavaScript Math.round: halves round up, towards +infinity.
double _jsRound(double v) {
  final r = v.floorToDouble();
  return v - r >= 0.5 ? r + 1 : r;
}

DraftStats _stats(String t, text.Document doc) {
  final bodyWords = text.countWords(t.substring(0, doc.bodyEnd));
  var sentences = 0, sentenceWords = 0, syl = 0, paras = 0;
  for (final p in doc.body) {
    if (p.heading) continue;
    paras += 1;
    sentences += text.paragraphSentences(p).length;
    for (final w in text.words(p.text)) {
      sentenceWords += 1;
      syl += text.syllables(w.text);
    }
  }
  num flesch = 0;
  if (sentences > 0 && sentenceWords > 0) {
    final f = _jsRound((206.835 - 1.015 * (sentenceWords / sentences) - 84.6 * (syl / sentenceWords)) * 10) / 10;
    // Serialise like JavaScript: whole numbers without ".0", and no negative zero.
    flesch = f == f.truncateToDouble() ? f.toInt() : f;
  }
  return DraftStats(bodyWords, sentences, paras, t.runes.length, (bodyWords / 200).ceil(), flesch);
}

/// Checks a draft and returns stats plus a sorted list of suggestions.
///
/// Throws [ArgumentError] for an unknown [style] or check, or a negative word limit.
DraftResult checkDraft(
  String t, {
  int? minWords,
  int? maxWords,
  String style = 'apa',
  List<String>? checks,
  List<String> requiredHeadings = const [],
}) {
  if (!styles.contains(style)) throw ArgumentError('Unknown style "$style". Use: ${styles.join(', ')}');
  final wanted = checks ?? defaultChecks;
  for (final c in wanted) {
    if (!allChecks.contains(c)) throw ArgumentError('Unknown check "$c". Use: ${allChecks.join(', ')}');
  }
  if ((minWords ?? 0) < 0) throw ArgumentError('minWords must be a whole number');
  if ((maxWords ?? 0) < 0) throw ArgumentError('maxWords must be a whole number');
  final opts = chk.CheckOptions(
      minWords,
      maxWords,
      style,
      [
        for (final c in allChecks)
          if (wanted.contains(c)) c
      ],
      List.of(requiredHeadings));
  final doc = text.structure(t);
  final stats = _stats(t, doc);
  final ctx = chk.Context(t, opts, doc, stats.words);
  for (final c in opts.checks) {
    _runners[c]!(ctx);
  }

  final starts = text.lineStarts(t);
  final issues = [
    for (final x in ctx.issues)
      () {
        final line = text.lineIndex(starts, x.start);
        return DraftIssue(
            x.level, x.code, x.message, x.start, x.end, line + 1, x.start - starts[line] + 1, t.substring(x.start, x.end), x.suggestion);
      }(),
  ];
  stableSort<DraftIssue>(issues, (a, b) {
    if (a.start != b.start) return a.start - b.start;
    final c = a.code.compareTo(b.code);
    return c != 0 ? c : a.end - b.end;
  });
  int count(String level) => issues.where((i) => i.level == level).length;
  return DraftResult(stats, count('error'), count('warning'), count('info'), issues);
}

/// Number of words in the text.
int countWords(String t) => text.countWords(t);

/// Sentences with UTF-16 offsets. Headings count as one sentence each.
List<text.Span> splitSentences(String t) => text.splitSentences(t);
