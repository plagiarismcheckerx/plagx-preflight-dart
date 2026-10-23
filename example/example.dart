import 'package:plagx_preflight/plagx_preflight.dart';

void main() {
  const draft = '''
# Introduction

Social media has changed how students learn (Smith, 2020). this is a important point.

## References

Smith, J. (2020). Learning online. Journal of Tests, 4(2), 1-10.
''';

  final result = checkDraft(draft, minWords: 10, requiredHeadings: ['Introduction', 'Conclusion']);
  print('${result.stats.words} words, Flesch ${result.stats.fleschReadingEase}');
  for (final issue in result.issues) {
    print('${issue.line}:${issue.column} ${issue.level} ${issue.message}');
  }
}
