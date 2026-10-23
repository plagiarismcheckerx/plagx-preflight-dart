import 'dart:io';

import 'package:plagx_preflight/src/cli.dart';

Future<void> main(List<String> arguments) async {
  final code = await runCli(arguments);
  await stdout.flush();
  exit(code);
}
