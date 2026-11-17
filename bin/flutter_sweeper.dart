import 'dart:io';

import 'package:flutter_sweeper/flutter_sweeper.dart';

Future<void> main(List<String> arguments) async {
  final exitStatus = await SweeperCommandRunner().run(arguments);
  await Future.wait<void>([stdout.close(), stderr.close()]);
  exit(exitStatus);
}
