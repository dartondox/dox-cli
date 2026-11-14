import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
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
  // Windows can not watch SIGTERM and SIGHUP. SIGHUP comes when the
  // terminal window or tab closes.
  for (ProcessSignal signal in <ProcessSignal>[
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
    if (!Platform.isWindows) ProcessSignal.sighup,
  ]) {
    signal.watch().listen((_) => stopChildren());
  }
}

/// The info file of the resident compiler that `dox serve` starts. It lives
/// in this project and has the pid of dox in its name, so dox only stops its
/// own compiler: not the one of another project, and not the one of a
/// second `dox serve` in the same project.
final String _compilerInfoFile = path.join(
  Directory.current.path,
  '.dart_tool',
  'dox',
  'resident_compiler_info_$pid',
);
bool _usesResidentCompiler = false;
bool _stopping = false;

/// Stops the child processes, waits up to 5 seconds for them, then exits.
/// It also stops the resident compiler of `dox serve`, so it does not stay
/// alive in the background.
Future<void> stopChildren() async {
  // eg. Ctrl+C twice: the first call already stops everything
  if (_stopping) return;
  _stopping = true;
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
    try {
      File(_compilerInfoFile).deleteSync();
    } catch (_) {
      // already gone
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
///
/// With [hotReload], a change in `lib/app/` only reloads the changed code in
/// the running server (Dart VM hot reload), with no restart. Other files,
/// like routes, providers and config, run only at start, so they still
/// restart the server. A failed reload also restarts the server.
Future<void> serverServe({
  bool withBuilder = false,
  bool hotReload = true,
}) async {
  String root = Directory.current.path;
  DirectoryWatcher watcher = DirectoryWatcher(root);
  Timer? timer;
  Timer? buildTimeout;
  Process? process;
  bool building = false;
  // the files that changed since the last reload or restart
  Set<String> changed = <String>{};
  DateTime lastBuildEnd = DateTime(0);
  // the VM service of the running server, for hot reload
  String? vmService;

  Future<Process> start({Completer<void>? ready}) async {
    vmService = null;
    Process started = await _startServer(
      ready: ready,
      hotReload: hotReload,
      onVmService: (String uri) => vmService = uri,
    );
    // a crashed server has no VM service anymore
    started.exitCode.then((_) {
      if (identical(process, started)) vmService = null;
    });
    return started;
  }

  // reloads or restarts the server for the changed files
  Future<void> apply() async {
    List<String> files = changed.toList();
    if (files.isEmpty) return;
    bool reloadOnly = files.every(canHotReload);
    // the restart comes when the build ends. A hot reload does not wait:
    // it runs now, and the generated files of the build come after it.
    if (building && !reloadOnly) return;
    changed.removeAll(files);
    String? uri = vmService;
    if (uri != null && reloadOnly) {
      Stopwatch watch = Stopwatch()..start();
      if (await reloadServer(uri)) {
        print(
          '\x1B[34m[Dox] Hot reloaded in '
          '${watch.elapsedMilliseconds}ms\x1B[0m',
        );
        return;
      }
      print('\x1B[33m[Dox] Hot reload failed, restarting..\x1B[0m');
    }
    Process? old = process;
    if (old != null) await stopProcess(old);
    process = await start();
  }

  // one reload or restart at a time, so there is never a second server
  SerialRunner runner = SerialRunner(apply);

  void restartAfter(Duration wait) {
    timer?.cancel();
    timer = Timer(wait, runner.run);
  }

  void setBuilding(bool value) {
    building = value;
    buildTimeout?.cancel();
    if (!value) return;
    // build_runner may hang or wait for input and never say the build
    // ended. When it prints nothing for a while, dox stops waiting, so a
    // save still restarts the server. Each output line starts the wait again.
    buildTimeout = Timer(_buildTimeout, () {
      print(
        '\x1B[33m[Dox] build_runner printed nothing for '
        '${_buildTimeout.inSeconds}s, dox does not wait for it..\x1B[0m',
      );
      building = false;
      if (changed.isNotEmpty) restartAfter(_debounce);
    });
  }

  Completer<void> ready = Completer<void>();
  process = await start(ready: ready);

  watcher.events.listen((WatchEvent event) {
    if (path.extension(event.path) != '.dart' ||
        isIgnoredWatchPath(event.path, root)) {
      return;
    }
    print("\x1B[34m[Dox] File changed: ${path.basename(event.path)}\x1B[0m");
    changed.add(path.relative(event.path, from: root));
    bool reloadOnly = changed.every(canHotReload);
    if (building && !reloadOnly) return;
    // a file event right after a build is a generated file of that build.
    // ponytail: 1 second guess, a slow disk may need more.
    bool fromLastBuild =
        DateTime.now().difference(lastBuildEnd) < const Duration(seconds: 1);
    // a hot reload does not wait for build_runner
    bool waitForBuild = withBuilder && !fromLastBuild && !reloadOnly;
    restartAfter(waitForBuild ? _buildStartWait : _debounce);
  });

  if (!withBuilder) return;
  // the server says "Server started at" when it is up. When it never says
  // it (an old dox_core, or a crash), build_runner starts after 10 seconds
  // or when the server stops.
  await ready.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  // the first build has no "Starting build" line
  setBuilding(true);
  Process builder = await watchBuilder(
    // build_runner is still working: wait longer
    onOutput: () {
      if (building) setBuilding(true);
    },
    onBuild: (bool started) {
      setBuilding(started);
      if (started) return;
      lastBuildEnd = DateTime.now();
      // only when a file changed, eg. the first build wrote new files
      if (changed.isNotEmpty) restartAfter(_debounce);
    },
  );
  // eg. the app has no build_runner: restart without waiting for builds
  builder.exitCode.then((_) {
    withBuilder = false;
    setBuilding(false);
    if (changed.isNotEmpty) restartAfter(_debounce);
  });
}

/// Runs [job] one at a time. A [run] while the job runs does not start a
/// second job: the job runs once more after the current one ends.
class SerialRunner {
  SerialRunner(this.job);

  final Future<void> Function() job;
  bool _running = false;
  bool _again = false;

  Future<void> run() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        try {
          await job();
        } catch (e) {
          print('\x1B[31m[Dox] $e\x1B[0m');
        }
      } while (_again);
    } finally {
      _running = false;
    }
  }
}

/// Stops [process] and waits until it is gone, so its port is free. When it
/// does not stop in 5 seconds (it ignores SIGTERM), it gets SIGKILL.
Future<void> stopProcess(Process process) async {
  process.kill();
  await process.exitCode.timeout(
    const Duration(seconds: 5),
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return process.exitCode;
    },
  );
}

/// True when a change of [file] (relative to the project) can be hot
/// reloaded. Only code in `lib/app/` (controllers, services, models, ...).
/// Routes, providers, config, the generated DI container, `bin/` and `db/`
/// run only at start, so they need a restart. Generated `.g.dart` files
/// also need a restart: they hold data (like model columns) that is built
/// once, and a hot reload does not build it again.
bool canHotReload(String file) {
  List<String> parts = path.split(file);
  return parts.length > 2 &&
      parts[0] == 'lib' &&
      parts[1] == 'app' &&
      !file.endsWith('.g.dart');
}

/// Hot reloads the server behind the VM service [uri]. Isolates made with
/// `Isolate.spawn` share one isolate group, and a reload changes the whole
/// group, so it reloads one isolate of each group. Returns false when the
/// reload fails, eg. a compile error or a change the VM can not reload.
Future<bool> reloadServer(String uri) async {
  VmService? vm;
  try {
    vm = await vmServiceConnectUri(
      convertToWebSocketUrl(serviceProtocolUrl: Uri.parse(uri)).toString(),
    ).timeout(const Duration(seconds: 5));
    VM info = await vm.getVM();
    int reloaded = 0;
    for (IsolateGroupRef ref in info.isolateGroups ?? <IsolateGroupRef>[]) {
      IsolateGroup group = await vm.getIsolateGroup(ref.id!);
      List<IsolateRef> isolates = group.isolates ?? <IsolateRef>[];
      if (isolates.isEmpty) continue;
      ReloadReport report = await vm.reloadSources(isolates.first.id!);
      if (report.success != true) return false;
      reloaded++;
    }
    return reloaded > 0;
  } catch (_) {
    return false;
  } finally {
    await vm?.dispose();
  }
}

/// Reads the VM service address from the line the Dart VM prints at start.
/// Returns null for any other line.
String? vmServiceUri(String line) {
  return RegExp(r'The Dart VM service is listening on (\S+)')
      .firstMatch(line)
      ?.group(1);
}

/// Wait this long after the last change before the restart.
const Duration _debounce = Duration(milliseconds: 200);

/// With build_runner, wait this long for a build to start after a save.
/// When no build starts, the server restarts anyway.
/// ponytail: a fixed guess. A very slow build_runner start can still give
/// two restarts; then make it an option.
const Duration _buildStartWait = Duration(seconds: 3);

/// Stop waiting for a build when build_runner prints nothing for this long.
const Duration _buildTimeout = Duration(seconds: 60);

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

/// True when a `build_runner` stdout line is worth showing: not empty, not a
/// progress line like `  0s dox_builder on 26 inputs: 26 skipped`, and not
/// the start or end of a build.
bool showBuildRunnerLine(String line) {
  if (line.trim().isEmpty) return false;
  if (RegExp(r'^\s*\d+(\.\d+)?m?s ').hasMatch(line)) return false;
  return buildRunnerBuildState(line) == null;
}

/// Starts `bin/server.dart`. [ready] completes when the server prints
/// "Server started at" or stops. With [hotReload], the VM service runs on a
/// free local port and [onVmService] gets its address.
Future<Process> _startServer({
  Completer<void>? ready,
  bool hotReload = false,
  void Function(String uri)? onVmService,
}) async {
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
    // port 0 = a free port. It listens on localhost only.
    if (hotReload) ...<String>['--enable-vm-service=0', '--no-serve-devtools'],
    'bin/server.dart',
  ]);
  _track(process);
  void show(String line) {
    if (line.isEmpty) return;
    print(line);
    String? uri = vmServiceUri(line);
    if (uri != null) onVmService?.call(uri);
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
/// false when it ends. [onOutput] runs for each stdout line.
Future<Process> watchBuilder({
  void Function(bool started)? onBuild,
  void Function()? onOutput,
}) async {
  var process = await Process.start('dart', ['run', 'build_runner', 'watch']);
  _track(process);

  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (String line) {
      onOutput?.call();
      bool? started = buildRunnerBuildState(line);
      if (started != null) onBuild?.call(started);
      // errors and warnings of the build, without the progress lines
      if (started == null && showBuildRunnerLine(line)) print(line);
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
