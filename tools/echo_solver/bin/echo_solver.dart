import 'dart:io';

import 'package:echo_solver/src/cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}
