/// Plagx Preflight: a free draft checker with basic grammar suggestions, by Plagiarism Checker X.
///
/// Checks word count and structure, in-text citations against the reference list,
/// punctuation and basic grammar, and gives readability stats. Runs fully offline.
/// Results match the JavaScript version exactly.
library;

export 'src/citations.dart' show Citation, findCitations;
export 'src/preflight.dart'
    show DraftIssue, DraftResult, DraftStats, allChecks, checkDraft, countWords, defaultChecks, splitSentences, styles, version;
export 'src/text.dart' show Span;
