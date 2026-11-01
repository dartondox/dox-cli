import 'dart:async';
import 'dart:io';

/// `dart run <script> <args>` in the app, with the output on this terminal.
/// stdin, stdout and stderr go straight to the child.
/// SIGINT and SIGTERM are sent on to the child, so a long job like
/// `queue:work` can stop by itself. Returns the exit code of the child.
Future<int> runScript(String script, List<String> args) async {
  Process process = await Process.start(dartExecutable(), <String>[
    'run',
    script,
    ...args,
  ], mode: ProcessStartMode.inheritStdio);

  List<StreamSubscription<ProcessSignal>> subscriptions =
      <StreamSubscription<ProcessSignal>>[];
  subscriptions.add(
    ProcessSignal.sigint.watch().listen(
      (ProcessSignal signal) => process.kill(ProcessSignal.sigint),
    ),
  );
  // SIGTERM can not be watched on Windows
  if (!Platform.isWindows) {
    subscriptions.add(
      ProcessSignal.sigterm.watch().listen(
        (ProcessSignal signal) => process.kill(ProcessSignal.sigterm),
      ),
    );
  }
  int code = await process.exitCode;
  for (StreamSubscription<ProcessSignal> subscription in subscriptions) {
    await subscription.cancel();
  }
  return code;
}

/// the `dart` that runs this CLI, or `dart` from PATH when it runs as an
/// AOT snapshot
String dartExecutable() {
  String exe = Platform.resolvedExecutable;
  return exe.split(Platform.pathSeparator).last.startsWith('dart')
      ? exe
      : 'dart';
}
