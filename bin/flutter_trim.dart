import 'dart:io';

import 'package:flutter_trim/flutter_trim.dart';

Future<void> main(List<String> arguments) async {
  final exitStatus = await TrimCommandRunner().run(arguments);
  await Future.wait<void>([stdout.close(), stderr.close()]);
  exit(exitStatus);
}
