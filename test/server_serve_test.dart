import 'dart:io';

import 'package:dox/src/tools/server_serve.dart';
import 'package:test/test.dart';

void main() {
  test('build_runner runs without removed flags', () {
    expect(buildRunnerBuildArgs, <String>['run', 'build_runner', 'build']);
  });

  test(
    'dox build_runner:build exits with the build_runner exit code',
    () async {
      // no pubspec.yaml, so build_runner fails
      Directory app = Directory.systemTemp.createTempSync('dox_build_');
      addTearDown(() => app.deleteSync(recursive: true));
      ProcessResult r = await Process.run(Platform.resolvedExecutable, <String>[
        '${Directory.current.path}/bin/dox.dart',
        'build_runner:build',
      ], workingDirectory: app.path);
      expect(r.exitCode, isNot(0), reason: '${r.stdout}${r.stderr}');
    },
  );

  test('dox serve ignores changes in build/ and hidden folders', () {
    String root = '/app';
    expect(isIgnoredWatchPath('/app/.dart_tool/build/x.dart', root), isTrue);
    expect(isIgnoredWatchPath('/app/build/bundle/a.dart', root), isTrue);
    expect(isIgnoredWatchPath('/app/lib/.cache/a.dart', root), isTrue);
    expect(isIgnoredWatchPath('/app/lib/app/user.model.dart', root), isFalse);
    expect(isIgnoredWatchPath('/app/lib/build/a.dart', root), isFalse);
    expect(isIgnoredWatchPath('/app/bin/server.dart', root), isFalse);
  });

  test('dox serve reads the start and end of a build_runner build', () {
    expect(buildRunnerBuildState('Starting build #2.'), isTrue);
    expect(
      buildRunnerBuildState(
        'Built with build_runner/jit in 1s; wrote 2 outputs.',
      ),
      isFalse,
    );
    expect(
      buildRunnerBuildState(
        'Failed to build with build_runner/jit in 1s; wrote 0 outputs.',
      ),
      isFalse,
    );
    expect(buildRunnerBuildState('json_serializable on lib/a.dart'), isNull);
  });

  test('the serve option warning shows the port that was typed', () {
    expect(serveOptionWarning('--port=3000'), contains('APP_PORT=3000 dox'));
    expect(serveOptionWarning('3000'), contains('APP_PORT=8080 dox'));
    expect(
      serveOptionWarning('--host=127.0.0.1'),
      contains('APP_PORT=8080 dox'),
    );
    expect(serveOptionWarning('--watch'), contains('APP_PORT=8080 dox'));
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
      addTearDown(() => app.deleteSync(recursive: true));
      File pidFile = File('${app.path}/server.pid');
      File('${app.path}/bin/server.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
import 'dart:async';
import 'dart:io';
void main() {
  // write, then rename: the test must never see an empty file
  File('server.pid.tmp').writeAsStringSync('\$pid');
  File('server.pid.tmp').renameSync('server.pid');
  Timer.periodic(const Duration(seconds: 1), (_) {});
}
''');
      Process dox = await Process.start(Platform.resolvedExecutable, <String>[
        'run',
        '${Directory.current.path}/bin/dox.dart',
        'serve',
        '--ignore-build-runner',
      ], workingDirectory: app.path);
      // if the test fails, do not leave dox running
      addTearDown(() => dox.kill(ProcessSignal.sigkill));
      for (int i = 0; i < 300 && !pidFile.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      int server = int.parse(pidFile.readAsStringSync());
      // if the test fails, do not leave the server running
      addTearDown(() => Process.killPid(server, ProcessSignal.sigkill));

      dox.kill();
      await dox.exitCode.timeout(const Duration(seconds: 15));
      // kill -0 only checks if the process still runs
      ProcessResult alive = Process.runSync('kill', <String>['-0', '$server']);
      expect(alive.exitCode, isNot(0), reason: 'the server still runs');
    },
    testOn: '!windows',
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
