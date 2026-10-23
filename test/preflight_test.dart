import 'dart:convert';
import 'dart:io';

import 'package:plagx_preflight/plagx_preflight.dart';
import 'package:plagx_preflight/src/cli.dart';
import 'package:test/test.dart';

List<String> codes(DraftResult r) => [for (final i in r.issues) i.code];

Future<(int, String, String)> run(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(args, out: out, err: err, stdinStream: const Stream.empty());
  return (code, out.toString(), err.toString());
}

void main() {
  test('result shape', () {
    final r = checkDraft('The the cat sat.').toJson();
    expect(r.keys, ['stats', 'errors', 'warnings', 'infos', 'issues']);
    expect((r['stats'] as Map).keys, ['words', 'sentences', 'paragraphs', 'characters', 'readingTimeMinutes', 'fleschReadingEase']);
    final issue = (r['issues'] as List).first as Map;
    expect(issue.keys, ['level', 'code', 'message', 'start', 'end', 'line', 'column', 'text', 'suggestion']);
    expect(issue['message'], 'Suggestion: "The the" looks like a repeated word.');
  });

  test('UTF-16 offsets', () {
    final i = checkDraft('\u{1F600} the the end.').issues.firstWhere((x) => x.code == 'repeated-word');
    expect([i.start, i.end, i.column], [3, 10, 4]);
    expect(checkDraft('a\u{1F600}b').stats.characters, 3);
  });

  test('matches JavaScript on non-BMP letters and special casing', () {
    // Expected values produced by the JavaScript, Python, PHP and .NET versions.
    const text = '\u{1D400}lpha is fine. ßig news: an \u{1D401}eta test. The the \u{1D4B3}yz word. '
        'ΟΔΟΣ and ΣΟΦΙΑ. a apple, i think.';
    expect([
      for (final i in checkDraft(text).issues) '${i.code}@${i.start}-${i.end}=${i.suggestion}'
    ], [
      'sentence-capital@16-19=SSig', 'repeated-word@41-48=The', 'a-an@76-77=an', 'sentence-capital@76-77=A', 'lowercase-i@85-86=I', //
    ]);
  });

  test('helpers', () {
    expect(countWords("It's a well-known fact, 42 times."), 6);
    expect([for (final s in splitSentences('One. Two!')) s.text], ['One.', 'Two!']);
    final c = findCitations('é (Moore, 2011; Price, 2016, 2018)');
    expect([for (final x in c) '${x.key}:${x.year}'], ['moore:2011', 'price:2016', 'price:2018']);
    expect(c.first.start, 3);
    expect(findCitations('(Greenblatt 45)', 'mla').single.key, 'greenblatt');
  });

  test('options', () {
    expect(codes(checkDraft('One two. Three four.', minWords: 10, requiredHeadings: ['Introduction', 'Conclusion'], checks: ['length'])),
        ['missing-heading', 'missing-heading', 'word-count-low']);
    expect(codes(checkDraft('the the ,,', checks: [])), isEmpty);
    expect(codes(checkDraft('The data were collected.', checks: ['passive-voice'])), contains('passive-voice'));
    expect(() => checkDraft('x', style: 'chicago'), throwsArgumentError);
    expect(() => checkDraft('x', checks: ['magic']), throwsArgumentError);
    expect(() => checkDraft('x', minWords: -1), throwsArgumentError);
  });

  group('command line', () {
    late Directory dir;
    late String bad, clean;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('plagx_preflight_');
      bad = '${dir.path}/bad.txt';
      clean = '${dir.path}/clean.md';
      File(bad).writeAsStringSync('Shown (Smith, 2020). the the end.\n');
      File(clean).writeAsStringSync('A clean draft. It has two sentences.\n');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('check', () async {
      final (code, out, _) = await run(['check', bad]);
      expect(code, 1);
      expect(out, contains('missing-reference-section'));
      expect((await run(['check', clean])).$1, 0);
      expect((await run(['check', clean, '--min-words', '50', '--strict'])).$1, 1);
      final json = jsonDecode((await run(['check', clean, '--json', '--require-heading=Conclusion'])).$2) as List;
      expect([for (final i in json.first['issues'] as List) i['code']], ['missing-heading']);
    });

    test('stats', () async {
      final (code, out, _) = await run(['stats', clean]);
      expect(code, 0);
      expect(out, contains('Words:               7'));
    });

    test('usage errors', () async {
      for (final args in [
        ['check'],
        ['check', '${dir.path}/paper.docx'],
        ['check', '${dir.path}/missing.txt'],
        ['check', clean, '--style', 'x'],
        ['check', clean, '--min-words', 'ten'],
        ['lint', clean],
        <String>[],
      ]) {
        expect((await run(args)).$1, 2, reason: '$args');
      }
      expect((await run(['--version'])).$2, '$version\n');
    });
  });
}
