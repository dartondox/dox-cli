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
  // dox is stopping: a server or build_runner that starts now must not stay
  if (_stopping) {
    process.kill();
    return;
  }
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
    signal.watch().listen(stopChildren);
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
Future<void> stopChildren([ProcessSignal? signal]) async {
  if (_stopping) {
    // a second Ctrl+C: the user wants out now. Other signals (eg. SIGHUP
    // then SIGTERM when a terminal closes) let the first stop finish.
    if (signal == ProcessSignal.sigint) exit(1);
    return;
  }
  _stopping = true;
  // a child that ignores SIGTERM gets SIGKILL after 5 seconds
  await Future.wait(_children.toList().map(stopProcess));
  if (_usesResidentCompiler) await _stopCompiler(_compilerInfoFile);
  exit(0);
}

/// Stops the resident compiler of [infoFile] and deletes the file.
Future<void> _stopCompiler(String infoFile) async {
  if (!File(infoFile).existsSync()) return;
  try {
    await Process.run('dart', <String>[
      'compilation-server',
      'shutdown',
      '--resident-compiler-info-file',
      infoFile,
    ]).timeout(const Duration(seconds: 5));
  } catch (_) {
    // dox goes on anyway
  }
  try {
    File(infoFile).deleteSync();
  } catch (_) {
    // already gone
  }
}

/// Stops the resident compilers of `dox serve` runs that died without
/// cleaning up (eg. SIGKILL or a crash), and deletes their info files.
Future<void> _stopStaleCompilers() async {
  // ponytail: no pid check on Windows, stale files there stay until the
  // next `dart pub get` clears .dart_tool
  if (Platform.isWindows) return;
  Directory dir = Directory(path.dirname(_compilerInfoFile));
  if (!dir.existsSync()) return;
  for (FileSystemEntity file in dir.listSync()) {
    int? owner = int.tryParse(
      path.basename(file.path).replaceFirst('resident_compiler_info_', ''),
    );
    if (owner == null || owner == pid) continue;
    // kill -0 only checks if the process still runs
    if (Process.runSync('kill', <String>['-0', '$owner']).exitCode == 0) {
      continue;
    }
    await _stopCompiler(file.path);
  }
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
  // the VM service of the running server, for hot reload
  String? vmService;
  await _stopStaleCompilers();

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
    if (_stopping) return;
    List<String> files = changed.toList();
    if (files.isEmpty) return;
    String? uri = vmService;
    bool reload = shouldHotReload(
      files,
      hotReload: hotReload,
      hasVmService: uri != null,
    );
    // the restart comes when the build ends. A hot reload does not wait:
    // it runs now, and the generated files of the build come after it.
    if (building && !reload) return;
    changed.removeAll(files);
    if (uri != null && reload) {
      Stopwatch watch = Stopwatch()..start();
      if (await reloadServer(uri)) {
        print(
          '\x1B[34m[Dox] Hot reloaded in '
          '${watch.elapsedMilliseconds}ms\x1B[0m',
        );
        return;
      }
      if (building) {
        // eg. a generated part file is half written. Restart once when the
        // build ends.
        changed.addAll(files);
        print(
          '\x1B[33m[Dox] Hot reload failed, restarting after the '
          'build..\x1B[0m',
        );
        return;
      }
      print('\x1B[33m[Dox] Hot reload failed, restarting..\x1B[0m');
    }
    Process? old = process;
    if (old != null) await stopProcess(old);
    // Ctrl+C came while the old server stopped: do not start a new one
    if (_stopping) return;
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
    Duration? wait = waitAfterChange(
      changed,
      reload: shouldHotReload(
        changed,
        hotReload: hotReload,
        hasVmService: vmService != null,
      ),
      building: building,
      withBuilder: withBuilder,
    );
    // null: the build that runs now restarts the server when it ends
    if (wait != null) restartAfter(wait);
  });

  if (!withBuilder) return;
  // the server says "Server started at" when it is up. When it never says
  // it (an old dox_core, or a crash), build_runner starts after 10 seconds
  // or when the server stops.
  await ready.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  if (_stopping) return;
  // the first build has no "Starting build" line
  setBuilding(true);
  Process builder;
  try {
    builder = await watchBuilder(
      // build_runner is still working: wait longer
      onOutput: () {
        if (building) setBuilding(true);
      },
      onBuild: (bool started) {
        setBuilding(started);
        if (started) return;
        // only when a file changed, eg. the first build wrote new files.
        // The file events of the build can come a bit late (macOS), so wait
        // a little longer: they then join this restart.
        if (changed.isNotEmpty) restartAfter(_afterBuild);
      },
    );
  } catch (e) {
    print('\x1B[31m[Dox] build_runner did not start: $e\x1B[0m');
    withBuilder = false;
    setBuilding(false);
    return;
  }
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

/// True when dox hot reloads [files] instead of a restart: hot reload is on
/// ([hotReload], no `--no-reload`), the server has its VM service up
/// ([hasVmService]), and every file can be hot reloaded.
bool shouldHotReload(
  Iterable<String> files, {
  required bool hotReload,
  required bool hasVmService,
}) {
  return hotReload &&
      hasVmService &&
      files.isNotEmpty &&
      files.every(canHotReload);
}

/// How long dox waits after a file change before it reloads or restarts.
/// [changed] are all files changed since the last reload or restart, and
/// [reload] is [shouldHotReload] for them. Returns null when a build runs
/// and a restart is needed: the restart then comes when the build ends.
Duration? waitAfterChange(
  Iterable<String> changed, {
  required bool reload,
  required bool building,
  required bool withBuilder,
}) {
  // a hot reload does not wait for build_runner
  if (reload) return _debounce;
  if (building) return null;
  // a generated file comes from a build, so no build follows it. Any other
  // change starts a build: wait for it, so the restart uses its output.
  if (withBuilder && !changed.every(isGeneratedFile)) return _buildStartWait;
  return _debounce;
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
///
/// The whole reload has a 10 second limit. A server that is stuck (a busy
/// loop, or paused at a breakpoint) can not hang dox: the reload fails and
/// dox restarts the server.
Future<bool> reloadServer(String uri) async {
  Future<VmService> connecting = vmServiceConnectUri(
    convertToWebSocketUrl(serviceProtocolUrl: Uri.parse(uri)).toString(),
  );
  try {
    return await _reload(connecting).timeout(const Duration(seconds: 10));
  } catch (_) {
    return false;
  } finally {
    // also closes a connection that opened after the time limit
    connecting.then(_dispose, onError: (_) {});
  }
}

Future<bool> _reload(Future<VmService> connecting) async {
  VmService vm = await connecting;
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
}

Future<void> _dispose(VmService vm) async {
  try {
    await vm.dispose();
  } catch (_) {
    // the reload result does not depend on it
  }
}

/// True when [file] (relative to the project) is written by build_runner:
/// a `.g.dart` file or a file in `lib/generated/`.
bool isGeneratedFile(String file) {
  List<String> parts = path.split(file);
  return file.endsWith('.g.dart') ||
      (parts.length > 2 && parts[0] == 'lib' && parts[1] == 'generated');
}

/// True for a server output line that dox does not show: the DevTools link.
/// The VM service link above it opens DevTools too, so it is the same link.
bool isHiddenServerLine(String line) {
  return line.startsWith(
    'The Dart DevTools debugger and profiler is available',
  );
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

/// Wait this long after a build ends before the restart.
const Duration _afterBuild = Duration(milliseconds: 500);

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
  // dox is stopping: a new server would only leave a compiler behind
  if (_stopping) throw StateError('dox is stopping, no new server');
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
    // port 0 = a free port. It listens on localhost only. DevTools is served
    // too (it does not slow the start): the VM service link opens it.
    if (hotReload) '--enable-vm-service=0',
    'bin/server.dart',
  ]);
  _track(process);
  void show(String line) {
    if (line.isEmpty || isHiddenServerLine(line)) return;
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
