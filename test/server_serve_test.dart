import 'dart:io';

import 'package:dox/src/tools/server_serve.dart';
import 'package:test/test.dart';

void main() {
  test('build_runner runs without removed flags', () {
    expect(buildRunnerBuildArgs, <String>['run', 'build_runner', 'build']);
  });

  test('dox build leaves SQLite files out of the bundle', () {
    expect(isSqliteFile('db/dox.sqlite'), isTrue);
    expect(isSqliteFile('db/dox.sqlite-wal'), isTrue);
    expect(isSqliteFile('db/dox.sqlite-shm'), isTrue);
    expect(isSqliteFile('db/app.db'), isTrue);
    expect(isSqliteFile('db/test.sqlite3'), isTrue);
    // the lock file of dox_migration
    expect(isSqliteFile('db/dox.sqlite.lock'), isTrue);
    expect(isSqliteFile('db/test.sqlite3.lock'), isTrue);
    expect(isSqliteFile('db/app.db.lock'), isTrue);
    expect(isSqliteFile('db/other.lock'), isFalse);
    expect(isSqliteFile('db/migration/2026_create_users_table.dart'), isFalse);
    expect(isSqliteFile('db/migration/create_users.sql'), isFalse);
  });

  test(
    'dox serve stops the server when only dox gets SIGTERM',
    () async {
      // an app whose server writes its pid, then waits forever
      Directory app = Directory.systemTemp.createTempSync('dox_serve_');
      File pidFile = File('${app.path}/server.pid');
      File('${app.path}/bin/server.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
import 'dart:async';
import 'dart:io';
void main() {
  File('server.pid').writeAsStringSync('\$pid');
  Timer.periodic(const Duration(seconds: 1), (_) {});
}
''');
      Process dox = await Process.start(Platform.resolvedExecutable, <String>[
        'run',
        '${Directory.current.path}/bin/dox.dart',
        'serve',
        '--ignore-build-runner',
      ], workingDirectory: app.path);
      for (int i = 0; i < 300 && !pidFile.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      int server = int.parse(pidFile.readAsStringSync());

      dox.kill();
      await dox.exitCode.timeout(const Duration(seconds: 15));
      // kill -0 only checks if the process still runs
      ProcessResult alive = Process.runSync('kill', <String>['-0', '$server']);
      if (alive.exitCode == 0) Process.killPid(server, ProcessSignal.sigkill);
      app.deleteSync(recursive: true);
      expect(alive.exitCode, isNot(0), reason: 'the server still runs');
    },
    testOn: '!windows',
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
