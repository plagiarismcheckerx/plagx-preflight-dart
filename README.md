# Plagx Preflight for Dart

*A free academic writing tool by Plagiarism Checker X.*

**Plagx Preflight for Dart is a free, open-source draft checker for Dart and Flutter apps.** Use it as an essay checker before students submit: it checks the word count and structure, matches in-text citations against the reference list, and gives punctuation and basic grammar suggestions plus readability stats.

- No dependencies, works offline: text never leaves the device
- Dart 3.4+, works in Flutter (mobile, web, desktop) and on the server
- APA and MLA citation checks
- Command line with JSON output and CI-friendly exit codes
- Results identical to the [JavaScript version](https://github.com/plagiarismcheckerx/plagx-preflight), offsets included

**[Try the live demo →](https://plagiarismcheckerx.github.io/plagx-preflight/)**

Developer downloads: [npm](https://www.npmjs.com/package/plagx-preflight) · [PyPI](https://pypi.org/project/plagx-preflight/) · [NuGet](https://www.nuget.org/packages/Plagx.Preflight) · [Packagist](https://packagist.org/packages/plagiarismcheckerx/plagx-preflight) · [GitHub](https://github.com/plagiarismcheckerx/plagx-preflight)

> Plagx Preflight is a free academic writing utility by Plagiarism Checker X. It checks length, structure, references, punctuation and basic grammar, and every result is a suggestion. Plagiarism checking and AI-generated text detection are available in Plagiarism Checker X, linked at the end of this page.

## Install

```bash
dart pub add plagx_preflight
# or, in a Flutter app
flutter pub add plagx_preflight
```

## Quick start

```dart
import 'package:plagx_preflight/plagx_preflight.dart';

final result = checkDraft(text,
    minWords: 1500, maxWords: 2000, style: 'apa', requiredHeadings: ['Introduction', 'Conclusion']);

print('${result.stats.words} words, Flesch ${result.stats.fleschReadingEase}');
for (final issue in result.issues) {
  print('${issue.line}:${issue.column} ${issue.level} ${issue.message}');
}
// 5:14 warning Suggestion: "the the" looks like a repeated word.
```

## Command line

```bash
dart pub global activate plagx_preflight
plagx-preflight check essay.txt --min-words 1500 --max-words 2000 --style apa
plagx-preflight check essay.md --json
plagx-preflight stats essay.txt
```

| Option | Meaning |
|---|---|
| `--min-words <n>`, `--max-words <n>` | Word limits (reference list excluded) |
| `--style apa\|mla` | Citation style (default `apa`) |
| `--checks <list>` | Comma-separated check groups |
| `--require-heading <name>` | Required heading, repeatable |
| `--strict` | Count warnings as failures |
| `--json` | JSON output |

Exit codes: `0` no errors, `1` errors found (with `--strict`, warnings too), `2` usage or input error. Accepts `.txt` and `.md`.

## API

`checkDraft(text, {minWords, maxWords, style = 'apa', checks, requiredHeadings = const []})` returns a `DraftResult` with `stats`, `errors`, `warnings`, `infos` and `issues`. Each `DraftIssue` has `level`, `code`, `message`, `start`, `end`, `line`, `column`, `text` and `suggestion`. Issues are sorted by position, and `toJson()` gives the same JSON as the other Plagx Preflight libraries.

`start`, `end` and `column` are UTF-16 offsets, so they index Dart strings directly (for example to highlight text in a Flutter `TextSpan`).

| Option | Default | |
|---|---|---|
| `minWords`, `maxWords` | `null` | Word limits (reference list excluded) |
| `style` | `'apa'` | `'apa'` or `'mla'` |
| `checks` | all except `'passive-voice'` | `length`, `references`, `punctuation`, `grammar`, `passive-voice` |
| `requiredHeadings` | `[]` | e.g. `['Introduction', 'Conclusion']` |

Helpers: `countWords(text)`, `splitSentences(text)`, `findCitations(text, style)`, `version`, `allChecks`. Invalid options throw `ArgumentError`.

## Checks

| Group | Codes | Level |
|---|---|---|
| Length & structure | `word-count-low`, `word-count-high`, `long-sentence` (over 40 words), `long-paragraph` (over 250 words), `single-sentence-paragraph`, `missing-heading` | warning / info |
| References | `citation-no-reference`, `missing-reference-section`, `reference-not-cited`, `et-al-format` | error / warning |
| Punctuation | `unmatched-quote`, `unmatched-bracket`, `double-space`, `space-before-punctuation`, `missing-space-after-punctuation`, `repeated-punctuation`, `mixed-quote-styles` | warning / info |
| Grammar | `repeated-word`, `a-an`, `sentence-capital`, `lowercase-i`, `common-confusion`, `passive-voice` (off by default) | warning / info |

## Good to know

- Every result is a suggestion. The grammar rules are deliberately conservative, so they miss some mistakes rather than flag correct text.
- The reference list starts at a heading such as References, Bibliography or Works Cited. It is excluded from the word count and from the punctuation and grammar checks.

## Development

```bash
dart pub get
dart test
```

`test/parity/expected.json` and `test/fixtures/` come from the JavaScript reference (`npm run parity` in plagx-preflight). Every case must match exactly. `lib/src/case_data.dart` holds the JavaScript case mappings (`node tool/build_case_data.mjs`), because Dart's own `toUpperCase()` differs for characters such as `ß`.

## Plagx Preflight - Free Draft & Grammar Checker

An open-source writing utility for students, researchers and developers. Check length, structure, citations, punctuation and basic grammar before you submit.

Developed by Plagiarism Checker X.

Plagx Preflight gives writing suggestions; it does not detect plagiarism or AI-generated text. For full document checks, explore [Plagiarism Checker X](https://plagiarismcheckerx.com/?utm_source=plagx-preflight-dart&utm_medium=readme&utm_campaign=plagx&utm_content=about-cta) and its [AI Content Detector](https://plagiarismcheckerx.com/ai-content-detector?utm_source=plagx-preflight-dart&utm_medium=readme&utm_campaign=plagx&utm_content=about-ai-detector).

## License

MIT © Plagiarism Checker X
