import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:watcher/watcher.dart';

/// The server and build_runner that dox started. They stop with dox, also
/// when only dox gets the signal (eg. `kill <pid>`), not the whole group.
final Set<Process> _children = <Process>{};
bool _watchingSignals = false;

void _track(Process process) {
  _children.add(process);
  process.exitCode.then((_) => _children.remove(process));
  if (_watchingSignals) return;
  _watchingSignals = true;
  // Windows can not watch SIGTERM
  for (ProcessSignal signal in <ProcessSignal>[
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ]) {
    signal.watch().listen((_) => stopChildren());
  }
}

/// The info file of the resident compiler that `dox serve` starts. It lives
/// in this project, so dox only stops its own compiler, not the one of
/// another project.
final String _compilerInfoFile = path.join(
  Directory.current.path,
  '.dart_tool',
  'dox',
  'resident_compiler_info',
);
bool _usesResidentCompiler = false;

/// Stops the child processes, waits up to 5 seconds for them, then exits.
/// It also stops the resident compiler of `dox serve`, so it does not stay
/// alive in the background.
Future<void> stopChildren() async {
  List<Process> children = _children.toList();
  for (Process child in children) {
    child.kill();
  }
  await Future.wait(children.map((Process c) => c.exitCode))
      .timeout(const Duration(seconds: 5), onTimeout: () => <int>[]);
  if (_usesResidentCompiler && File(_compilerInfoFile).existsSync()) {
    try {
      await Process.run('dart', <String>[
        'compilation-server',
        'shutdown',
        '--resident-compiler-info-file',
        _compilerInfoFile,
      ]).timeout(const Duration(seconds: 5));
    } catch (_) {
      // dox exits anyway
    }
  }
  exit(0);
}

/// Runs the server and restarts it when a .dart file changes.
///
/// With [withBuilder], it also runs `build_runner watch`, but only after the
/// server is up, so the two do not slow down each other at the first start.
/// One save gives one restart: dox waits until build_runner has written the
/// new generated files. When no build starts after a save (the file is not
/// part of the build), the server restarts after a short wait.
Future<void> serverServe({bool withBuilder = false}) async {
  String root = Directory.current.path;
  DirectoryWatcher watcher = DirectoryWatcher(root);
  Timer? timer;
  Process? process;
  bool building = false;
  // a file changed and the server did not restart for it yet
  bool changed = false;
  DateTime lastBuildEnd = DateTime(0);

  void restartAfter(Duration wait) {
    timer?.cancel();
    timer = Timer(wait, () async {
      if (building) return; // the restart comes when the build ends
      changed = false;
      process?.kill();
      // start the new server only after the old one is gone, so the port
      // is free. The exit code does not matter.
      await process?.exitCode;
      process = await _startServer();
    });
  }

  Completer<void> ready = Completer<void>();
  process = await _startServer(ready: ready);

  watcher.events.listen((WatchEvent event) {
    if (path.extension(event.path) != '.dart' ||
        isIgnoredWatchPath(event.path, root)) {
      return;
    }
    print("\x1B[34m[Dox] File changed: ${path.basename(event.path)}\x1B[0m");
    changed = true;
    if (building) return;
    // a file event right after a build is a generated file of that build.
    // ponytail: 1 second guess, a slow disk may need more.
    bool fromLastBuild =
        DateTime.now().difference(lastBuildEnd) < const Duration(seconds: 1);
    restartAfter(withBuilder && !fromLastBuild ? _buildStartWait : _debounce);
  });

  if (!withBuilder) return;
  // the server says "Server started at" when it is up. When it never says
  // it (an old dox_core, or a crash), build_runner starts after 10 seconds
  // or when the server stops.
  await ready.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  // the first build has no "Starting build" line
  building = true;
  Process builder = await watchBuilder(
    onBuild: (bool started) {
      building = started;
      if (started) {
        timer?.cancel();
        return;
      }
      lastBuildEnd = DateTime.now();
      // only when a file changed, eg. the first build wrote new files
      if (changed) restartAfter(_debounce);
    },
  );
  // eg. the app has no build_runner: restart without waiting for builds
  builder.exitCode.then((_) {
    withBuilder = false;
    building = false;
    if (changed) restartAfter(_debounce);
  });
}

/// Wait this long after the last change before the restart.
const Duration _debounce = Duration(milliseconds: 200);

/// With build_runner, wait this long for a build to start after a save.
/// When no build starts, the server restarts anyway.
const Duration _buildStartWait = Duration(milliseconds: 1500);

/// True when a change of [file] must not restart the server: files in
/// `build/` of the project, or in a hidden folder like `.dart_tool/`.
bool isIgnoredWatchPath(String file, String root) {
  List<String> parts = path.split(path.relative(file, from: root));
  if (parts.first == 'build') return true;
  return parts.any((String part) => part.startsWith('.'));
}

/// Reads a line of `build_runner watch` output. Returns true when a build
/// starts, false when a build ends (passed or failed), and null for any
/// other line.
bool? buildRunnerBuildState(String line) {
  if (line.contains('Starting build #')) return true;
  if (line.contains('Built with build_runner') ||
      line.contains('Failed to build with build_runner')) {
    return false;
  }
  return null;
}

/// Starts `bin/server.dart`. [ready] completes when the server prints
/// "Server started at" or stops.
Future<Process> _startServer({Completer<void>? ready}) async {
  Directory(path.dirname(_compilerInfoFile)).createSync(recursive: true);
  _usesResidentCompiler = true;
  // the resident compiler keeps the compiled app in memory, so a restart
  // only compiles the changed files
  Process process = await Process.start('dart', <String>[
    'run',
    '--resident',
    // no "compiler started" message, dox stops it on exit
    '--quiet',
    // `=` is needed: dart run passes the two-word form on as a VM flag
    '--resident-compiler-info-file=$_compilerInfoFile',
    'bin/server.dart',
  ]);
  _track(process);
  void show(String line) {
    if (line.isEmpty) return;
    print(line);
    if (line.contains('Server started at') && !(ready?.isCompleted ?? true)) {
      ready!.complete();
    }
  }

  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(show);
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(show);
  process.exitCode.then((_) {
    if (!(ready?.isCompleted ?? true)) ready!.complete();
  });
  return process;
}

/// Runs `build_runner watch`. [onBuild] gets true when a build starts and
/// false when it ends.
Future<Process> watchBuilder({void Function(bool started)? onBuild}) async {
  var process = await Process.start('dart', ['run', 'build_runner', 'watch']);
  _track(process);

  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (String line) {
      bool? started = buildRunnerBuildState(line);
      if (started != null) onBuild?.call(started);
    },
  );

  process.stderr.transform(utf8.decoder).listen((data) {
    List lines = data.split("\n");
    for (String line in lines) {
      if (line.isNotEmpty) {
        print(line);
      }
    }
  });
  return process;
}

/// The warning for an unknown `dox serve` option. The app reads the port
/// from APP_PORT, not from a dox flag. The hint shows the port of
/// `--port=<number>` in [arg], or 8080 for any other option.
String serveOptionWarning(String arg) {
  String port = RegExp(r'^--port=(\d+)$').firstMatch(arg)?.group(1) ?? '8080';
  return '\x1B[33mWarning: $arg is not a serve option, it is ignored. '
      'To set the port, set APP_PORT in .env '
      '(or run APP_PORT=$port dox serve).\x1B[0m';
}

/// `dart run build_runner build`. build_runner removed
/// `--delete-conflicting-outputs`, so it is not passed.
const List<String> buildRunnerBuildArgs = <String>[
  'run',
  'build_runner',
  'build',
];

/// `dox build_runner:build`. Shows all build_runner output and returns
/// its exit code.
Future<int> buildBuilder() => _run('dart', buildRunnerBuildArgs);

/// AOT compile the app for production.
///
/// output (a `dart build cli` bundle):
///   build/bundle/bin/server     native binary (no Dart SDK needed to run)
///   build/bundle/bin/queue      queue worker, when bin/queue.dart exists
///   build/bundle/bin/schedule   scheduler, when bin/schedule.dart exists
///   build/bundle/lib/           native libraries from build hooks (eg. SQLite)
///   build/bundle/db/            migrations, read at start (no SQLite files)
///   build/bundle/.env.example   copy it to .env or set env vars
///
/// `dart compile exe` can not build packages with build hooks (sqlite3 v3),
/// so this uses `dart build cli`. It is the same AOT compiler.
///
/// `dart run` (used by `dox serve`) is JIT: more memory and slower start.
/// never run production with it.
Future<void> buildServer() async {
  bool usesBuildRunner =
      File('pubspec.yaml').existsSync() &&
      File('pubspec.yaml').readAsStringSync().contains('build_runner');
  if (usesBuildRunner && await _run('dart', buildRunnerBuildArgs) != 0) {
    exitCode = 1;
    return;
  }

  if (await _run('dart', <String>[
        'build',
        'cli',
        '--target',
        'bin/server.dart',
        '--output',
        'build',
      ]) !=
      0) {
    exitCode = 1;
    return;
  }

  // the worker and the scheduler run as their own processes in production
  for (String name in <String>['queue', 'schedule']) {
    if (!File('bin/$name.dart').existsSync()) continue;
    if (await _run('dart', <String>[
          'build',
          'cli',
          '--target',
          'bin/$name.dart',
          '--output',
          'build/$name',
        ]) !=
        0) {
      exitCode = 1;
      return;
    }
    File('build/$name/bundle/bin/$name').copySync('build/bundle/bin/$name');
    Directory('build/$name').deleteSync(recursive: true);
  }

  Directory oldDb = Directory('build/bundle/db');
  if (oldDb.existsSync()) oldDb.deleteSync(recursive: true);
  if (Directory('db').existsSync()) {
    _copyDir(Directory('db'), 'build/bundle/db');
  }
  if (File('.env.example').existsSync()) {
    File('.env.example').copySync('build/bundle/.env.example');
  }
  print(
    '\x1B[32m[Dox] Built build/bundle. Run it with: '
    'cd build/bundle && ./bin/server\x1B[0m',
  );
}

/// run a command with its output shown, return the exit code
Future<int> _run(String command, List<String> args) async {
  Process process = await Process.start(
    command,
    args,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

void _copyDir(Directory from, String to) {
  for (FileSystemEntity entity in from.listSync(recursive: true)) {
    String target = path.join(to, path.relative(entity.path, from: from.path));
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      // never ship the local SQLite database (dev data) in the bundle
      if (isSqliteFile(entity.path)) continue;
      File(target).parent.createSync(recursive: true);
      entity.copySync(target);
    }
  }
}

/// `dox.sqlite`, `dox.sqlite-wal`, `dox.sqlite-shm`, `app.db`, ...
/// and `dox.sqlite.lock`, the lock file of dox_migration.
bool isSqliteFile(String file) {
  return RegExp(r'\.(sqlite3?|db)(-wal|-shm|-journal|\.lock)?$').hasMatch(file);
}
