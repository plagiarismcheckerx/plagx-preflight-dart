// Plagx Preflight command line. A free academic writing utility by Plagiarism Checker X.
import 'dart:convert';
import 'dart:io';

import '../plagx_preflight.dart';

final _help = '''Plagx Preflight $version: check a draft before you submit

Usage:
  plagx-preflight check <file> [...]   List suggestions for length, references,
                                       punctuation and basic grammar
  plagx-preflight stats <file> [...]   Print word count, sentences and readability

<file> is a .txt or .md file. Use - to read from stdin.

Options:
  --min-words <n>               Minimum word count
  --max-words <n>               Maximum word count
  --style apa|mla               Citation style (default: apa)
  --checks <list>               Comma-separated: ${allChecks.join(',')}
                                (default: all except passive-voice)
  --require-heading <name>      Required heading (repeatable)
  --strict                      check: treat warnings as errors
  --json                        Print the result as JSON
  -v, --version                 Show version
  -h, --help                    Show this help

Exit codes: 0 = no errors, 1 = errors found, 2 = usage or input error.

Automated suggestions only. A free academic writing utility by Plagiarism
Checker X, which checks originality and AI-generated text: https://plagiarismcheckerx.com/''';

class _UsageError implements Exception {
  _UsageError(this.message);
  final String message;
}

class _Options {
  int? minWords;
  int? maxWords;
  String style = 'apa';
  List<String> checks = List.of(defaultChecks);
  final requiredHeadings = <String>[];
  bool strict = false;
  bool json = false;
  bool help = false;
  bool version = false;
}

List<String> _csv(String s) => [
      for (final x in s.split(','))
        if (x.trim().isNotEmpty) x.trim()
    ];

(_Options, List<String>) _parseArgs(List<String> argv) {
  final opts = _Options();
  final args = <String>[];
  for (var i = 0; i < argv.length; i += 1) {
    var a = argv[i];
    String? inline;
    if (a.startsWith('--') && a.contains('=')) {
      inline = a.substring(a.indexOf('=') + 1);
      a = a.substring(0, a.indexOf('='));
    }
    String value() {
      if (inline != null) return inline;
      if (i + 1 >= argv.length) throw _UsageError('$a needs a value');
      return argv[++i];
    }

    int number() {
      final v = value();
      if (!RegExp(r'^[0-9]+$').hasMatch(v)) throw _UsageError('$a needs a whole number');
      return int.parse(v);
    }

    switch (a) {
      case '--min-words':
        opts.minWords = number();
      case '--max-words':
        opts.maxWords = number();
      case '--style':
        opts.style = value();
      case '--checks':
        opts.checks = _csv(value());
      case '--require-heading':
        opts.requiredHeadings.add(value());
      case '--strict':
        opts.strict = true;
      case '--json':
        opts.json = true;
      case '-h' || '--help':
        opts.help = true;
      case '-v' || '--version':
        opts.version = true;
      default:
        if (a.startsWith('-') && a != '-') throw _UsageError('Unknown option $a');
        args.add(a);
    }
  }
  if (!styles.contains(opts.style)) throw _UsageError('Unknown style "${opts.style}". Use: ${styles.join(', ')}');
  for (final c in opts.checks) {
    if (!allChecks.contains(c)) throw _UsageError('Unknown check "$c". Use: ${allChecks.join(', ')}');
  }
  return (opts, args);
}

Future<String> _loadText(String path, Stream<List<int>> stdinStream) async {
  final lower = path.toLowerCase();
  if (path != '-' && !lower.endsWith('.txt') && !lower.endsWith('.md')) {
    throw _UsageError('$path: only .txt and .md files are supported');
  }
  try {
    final bytes = path == '-' ? await stdinStream.expand((b) => b).toList() : await File(path).readAsBytes();
    final text = utf8.decode(bytes);
    return text.startsWith('﻿') ? text.substring(1) : text;
  } on PathNotFoundException {
    throw _UsageError('Cannot read $path: file not found');
  } on FormatException catch (e) {
    throw _UsageError('Cannot read $path: ${e.message}');
  } on FileSystemException catch (e) {
    throw _UsageError('Cannot read $path: ${e.message}');
  }
}

String _printStats(String file, DraftStats s) => [
      file,
      '  Words:               ${s.words}',
      '  Sentences:           ${s.sentences}',
      '  Paragraphs:          ${s.paragraphs}',
      '  Characters:          ${s.characters}',
      '  Reading time:        ${s.readingTimeMinutes} min',
      '  Flesch reading ease: ${s.fleschReadingEase}',
    ].join('\n');

String _printCheck(String file, DraftResult r) => [
      for (final x in r.issues) '$file:${x.line}:${x.column}  ${x.level.padRight(7)} ${x.code.padRight(32)} ${x.message}',
      '$file: ${r.stats.words} words, ${r.errors} error(s), ${r.warnings} warning(s), ${r.infos} info',
    ].join('\n');

/// Runs the command line and returns the exit code.
Future<int> runCli(List<String> argv, {StringSink? out, StringSink? err, Stream<List<int>>? stdinStream}) async {
  out ??= stdout;
  err ??= stderr;
  final _Options opts;
  final List<String> args;
  try {
    (opts, args) = _parseArgs(argv);
  } on _UsageError catch (e) {
    err.write('${e.message}\n\nRun plagx-preflight --help for usage.\n');
    return 2;
  }
  if (opts.version) {
    out.write('$version\n');
    return 0;
  }
  if (opts.help || args.isEmpty) {
    out.write('$_help\n');
    return opts.help || args.isNotEmpty ? 0 : 2;
  }
  final command = args.first;
  final files = args.sublist(1);
  final texts = <(String, String)>[];
  try {
    if (command != 'check' && command != 'stats') throw _UsageError('Unknown command "$command"');
    if (files.isEmpty) throw _UsageError('$command needs a file (.txt or .md, or - for stdin)');
    for (final f in files) {
      texts.add((f, await _loadText(f, stdinStream ?? stdin)));
    }
  } on _UsageError catch (e) {
    err.write('${e.message}\n\nRun plagx-preflight --help for usage.\n');
    return 2;
  }

  var failed = false;
  final reports = <(String, DraftResult)>[];
  for (final (file, text) in texts) {
    final r = command == 'stats'
        ? checkDraft(text, checks: const [])
        : checkDraft(text,
            minWords: opts.minWords,
            maxWords: opts.maxWords,
            style: opts.style,
            checks: opts.checks,
            requiredHeadings: opts.requiredHeadings);
    if (r.errors > 0 || (opts.strict && r.warnings > 0)) failed = true;
    reports.add((file, r));
  }
  const encoder = JsonEncoder.withIndent('  ');
  if (command == 'stats') {
    out.write(opts.json
        ? '${encoder.convert([
                for (final (f, r) in reports) {'file': f, 'stats': r.stats.toJson()}
              ])}\n'
        : '${reports.map((x) => _printStats(x.$1, x.$2.stats)).join('\n\n')}\n');
    return 0;
  }
  out.write(opts.json
      ? '${encoder.convert([
              for (final (f, r) in reports) {'file': f, ...r.toJson()}
            ])}\n'
      : '${reports.map((x) => _printCheck(x.$1, x.$2)).join('\n\n')}\n');
  return failed ? 1 : 0;
}
