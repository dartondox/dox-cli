import 'dart:async';
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

  test('dox serve hot reloads only files in lib/app/', () {
    expect(canHotReload('lib/app/http/controllers/a.controller.dart'), isTrue);
    expect(canHotReload('lib/app/models/user/user.model.dart'), isTrue);
    expect(canHotReload('lib/routes/api.dart'), isFalse);
    expect(canHotReload('lib/providers/orm_provider.dart'), isFalse);
    expect(canHotReload('lib/config/app.dart'), isFalse);
    expect(canHotReload('lib/generated/container.g.dart'), isFalse);
    // generated data (like model columns) is built once, so it restarts
    expect(canHotReload('lib/app/models/user/user.model.g.dart'), isFalse);
    expect(canHotReload('lib/app.dart'), isFalse);
    expect(canHotReload('bin/server.dart'), isFalse);
  });

  test('dox serve knows the files build_runner writes', () {
    expect(isGeneratedFile('lib/app/models/user/user.model.g.dart'), isTrue);
    expect(isGeneratedFile('lib/generated/container.dart'), isTrue);
    expect(isGeneratedFile('lib/app/models/user/user.model.dart'), isFalse);
    expect(isGeneratedFile('lib/routes/api.dart'), isFalse);
    expect(isGeneratedFile('bin/server.dart'), isFalse);
  });

  test('dox serve reads the VM service address', () {
    expect(
      vmServiceUri(
        'The Dart VM service is listening on http://127.0.0.1:65010/9S0W=/',
      ),
      'http://127.0.0.1:65010/9S0W=/',
    );
    expect(vmServiceUri('Server started at http://[::]:3000'), isNull);
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

  test('dox serve shows build_runner errors, not progress lines', () {
    expect(
      showBuildRunnerLine('  0s dox_builder on 26 inputs: 26 skipped'),
      isFalse,
    );
    expect(
      showBuildRunnerLine('  12s source_gen on 3 inputs; a.dart'),
      isFalse,
    );
    expect(showBuildRunnerLine('Starting build #2.'), isFalse);
    expect(
      showBuildRunnerLine(
        'Built with build_runner/aot in 0s; wrote 0 outputs.',
      ),
      isFalse,
    );
    expect(showBuildRunnerLine('   '), isFalse);
    expect(
      showBuildRunnerLine('  E dox_builder on lib/a.dart: Bad annotation'),
      isTrue,
    );
    expect(showBuildRunnerLine('  W json_serializable: unused key'), isTrue);
  });

  test('SerialRunner never runs the job twice at the same time', () async {
    int running = 0;
    int most = 0;
    int runs = 0;
    Completer<void> gate = Completer<void>();
    SerialRunner runner = SerialRunner(() async {
      running++;
      runs++;
      if (running > most) most = running;
      await gate.future;
      running--;
    });
    Future<void> first = runner.run();
    // three saves while the first job still runs
    await runner.run();
    await runner.run();
    await runner.run();
    gate.complete();
    await first;
    expect(most, 1, reason: 'two jobs ran at the same time');
    // the saves during the first job give exactly one more run
    expect(runs, 2);
  });

  test('SerialRunner keeps going after a job throws', () async {
    int runs = 0;
    SerialRunner runner = SerialRunner(() async {
      runs++;
      throw StateError('boom');
    });
    await runner.run();
    await runner.run();
    expect(runs, 2);
  });

  test('stopProcess kills a process that ignores SIGTERM', () async {
    Process p = await Process.start('sh', <String>[
      '-c',
      // short sleeps, so no long `sleep` stays behind after SIGKILL
      'trap "" TERM; while true; do sleep 0.1; done',
    ]);
    addTearDown(() => p.kill(ProcessSignal.sigkill));
    // let sh set the trap first
    await Future<void>.delayed(const Duration(milliseconds: 300));
    Stopwatch watch = Stopwatch()..start();
    await stopProcess(p);
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
  }, testOn: '!windows');

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
      // dox stopped its resident compiler (no process names this app folder)
      ProcessResult compiler = Process.runSync('pgrep', <String>[
        '-f',
        // the temp folder name is unique to this test
        app.uri.pathSegments.lastWhere((String p) => p.isNotEmpty),
      ]);
      expect(
        (compiler.stdout as String).trim(),
        isEmpty,
        reason: 'the resident compiler still runs',
      );
      // and removed its info file
      Directory infoDir = Directory('${app.path}/.dart_tool/dox');
      List<String> left = infoDir.existsSync()
          ? infoDir
                .listSync()
                .map((FileSystemEntity e) => e.path)
                .where((String f) => f.contains('resident_compiler_info'))
                .toList()
          : <String>[];
      expect(left, isEmpty, reason: 'the info file is still there');
    },
    testOn: '!windows',
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
