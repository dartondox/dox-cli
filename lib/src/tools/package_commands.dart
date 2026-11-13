import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

import '../utils/run_script.dart';

/// the message for a command that no one has
String notFoundMessage(String command) {
  return 'Could not find a command named "$command". '
      'Run `dox help` for more information.\n'
      'Packages and the app add commands with the `dox: commands:` key in '
      'pubspec.yaml. Run `dart pub get` after you add a package.';
}

/// one command that a package (or the app) adds, for `dox help`
class PackageCommandInfo {
  PackageCommandInfo(this.package, this.name, this.usage, this.description);

  final String package;
  final String name;
  final String usage;
  final String description;
}

/// The `dox` commands of the packages and of the app.
///
/// A package names a library in its pubspec.yaml:
/// ```yaml
/// dox:
///   commands: package:dox_queue/commands.dart
/// ```
/// That library has a top-level `commands` list. Each command has `name`,
/// `description`, `usage` and `Future<void> run(List<String> args)`
/// (the `Command` class of `package:dox_core/command.dart`).
///
/// This class reads `.dart_tool/package_config.json` and the pubspec.yaml
/// of each package, then writes `.dart_tool/dox/commands.dart`. That file
/// imports the libraries and runs one command. It is written again only
/// when package_config.json, the app pubspec.yaml or the pubspec.yaml of
/// a path dependency change.
class PackageCommands {
  PackageCommands({Directory? root})
    : root = (root ?? Directory.current).absolute {
    _config = _findConfig();
  }

  /// the app folder
  final Directory root;

  /// a valid `dox: commands:` value. It goes into Dart source, so only
  /// plain path characters, and no `..` (checked apart).
  static final RegExp _libraryValue = RegExp(
    r'^package:[a-z0-9_]+/[A-Za-z0-9_./-]+\.dart$',
  );

  /// the first line of `--dox-list` output, before the JSON
  static const String listMarker = 'DOX_COMMANDS:';

  /// `.dart_tool/package_config.json` of the app, or of the pub
  /// workspace the app is in (a folder above it)
  late final File _config;

  /// the app's own package_config.json, or for a pub workspace member
  /// the one of the workspace root. `dart pub get` writes the root in
  /// `.dart_tool/pub/workspace_ref.json` of each member (this also works
  /// for members listed by a glob, like `apps/*`).
  File _findConfig() {
    File own = File('${root.path}/.dart_tool/package_config.json');
    File ref = File('${root.path}/.dart_tool/pub/workspace_ref.json');
    if (own.existsSync() || !ref.existsSync()) return own;
    try {
      dynamic doc = jsonDecode(ref.readAsStringSync());
      String path = '${(doc as Map)['workspaceRoot']}';
      if (!path.endsWith('/')) path = '$path/';
      Uri wsRoot = ref.absolute.uri.resolve(path);
      return File.fromUri(wsRoot.resolve('.dart_tool/package_config.json'));
    } catch (error) {
      return own;
    }
  }

  /// the YAML map of [file], or null
  Map<dynamic, dynamic>? _yaml(File file) {
    try {
      if (!file.existsSync()) return null;
      dynamic doc = loadYaml(file.readAsStringSync());
      return doc is Map ? doc : null;
    } catch (error) {
      return null;
    }
  }

  File get _pubspec => File('${root.path}/pubspec.yaml');
  File get _cache => File('${root.path}/.dart_tool/dox/commands.json');

  /// the generated runner, `.dart_tool/dox/commands.dart`
  File get runner => File('${root.path}/.dart_tool/dox/commands.dart');

  /// true in an app folder after `dart pub get`
  bool get inApp => _pubspec.existsSync() && _config.existsSync();

  /// package name => its commands library, like
  /// `{'dox_queue': 'package:dox_queue/commands.dart'}`.
  /// From the cache when package_config.json and the pubspec.yaml files
  /// did not change. Else found again, and the runner is written again.
  /// A discovery with warnings is not cached, so a fix (like a commands
  /// library that is added later) counts on the next run.
  Map<String, String> libraries() {
    if (!inApp) return <String, String>{};
    String key = _key();
    Map<String, dynamic> cache = _readCache();
    if (cache['key'] == key &&
        cache['libraries'] is Map &&
        cache['files'] is Map &&
        _allExist(cache['files'] as Map)) {
      _files = Map<String, String>.from(cache['files'] as Map);
      _cacheKey = key;
      Map<String, String> libs = Map<String, String>.from(
        cache['libraries'] as Map,
      );

      /// a new dox CLI can make a different runner, so write it again
      /// when its text is old. Also write it when it is missing: another
      /// `dox` can delete it at any time, so do not check first.
      if (libs.isNotEmpty) {
        String source = runnerSource(libs);
        String? old;
        try {
          old = runner.readAsStringSync();
        } on FileSystemException {
          old = null;
        }
        if (old != source) _writeAtomic(runner, source);
      }
      return libs;
    }
    Map<String, String> files = <String, String>{};
    Map<String, String> libs = discover(files: files);
    _files = files;
    if (libs.isEmpty) {
      if (runner.existsSync()) runner.deleteSync();
    } else {
      _writeAtomic(runner, runnerSource(libs));
    }
    if (_warnings.isEmpty) {
      _cacheKey = key;
      _writeCache(<String, dynamic>{
        'key': key,
        'libraries': libs,
        'files': files,
      });
    } else if (_cache.existsSync()) {
      _cache.deleteSync();
    }
    return libs;
  }

  /// true when every commands library file is still there. A removed
  /// file would break the runner of every package, so then [libraries]
  /// looks again (and skips that package with a warning).
  bool _allExist(Map<dynamic, dynamic> files) {
    for (dynamic path in files.values) {
      if (!File('$path').existsSync()) return false;
    }
    return true;
  }

  /// the packages the app uses: the app, its dependencies and
  /// dev_dependencies, and the dependencies of those, from
  /// `.dart_tool/package_graph.json`. In a pub workspace this leaves out
  /// the other members. Null when there is no graph (use all packages).
  Set<String>? _reachable() {
    Map<dynamic, dynamic>? pubspec = _yaml(_pubspec);
    File file = File('${_config.parent.path}/package_graph.json');
    if (pubspec == null || !file.existsSync()) return null;
    Map<String, Map<dynamic, dynamic>> graph =
        <String, Map<dynamic, dynamic>>{};
    try {
      dynamic doc = jsonDecode(file.readAsStringSync());
      for (dynamic package in (doc as Map)['packages'] as List) {
        graph['${(package as Map)['name']}'] = package;
      }
    } catch (error) {
      return null;
    }
    String app = '${pubspec['name']}';
    Set<String> seen = <String>{app};
    List<String> todo = <String>[app];
    while (todo.isNotEmpty) {
      String name = todo.removeLast();
      Map<dynamic, dynamic>? node = graph[name];
      if (node == null) continue;
      List<dynamic> next = <dynamic>[
        ...(node['dependencies'] as List?) ?? <dynamic>[],
        if (name == app) ...(node['devDependencies'] as List?) ?? <dynamic>[],
      ];
      for (dynamic dep in next) {
        if (seen.add('$dep')) todo.add('$dep');
      }
    }
    return seen;
  }

  /// package name => commands library file, of the last [libraries]
  Map<String, String> _files = <String, String>{};

  /// the key of a cache that is valid, or null (do not cache the list)
  String? _cacheKey;

  /// read the `dox: commands:` key of every package in
  /// package_config.json (the app is one of them). A bad key prints a
  /// warning and is skipped, so one bad package does not stop the others.
  /// [files] gets package name => path of the library file.
  Map<String, String> discover({Map<String, String>? files}) {
    Map<String, String> libs = <String, String>{};
    List<dynamic> packages;
    try {
      dynamic config = jsonDecode(_config.readAsStringSync());
      packages = (config as Map<String, dynamic>)['packages'] as List<dynamic>;
    } catch (error) {
      _warn('Could not read .dart_tool/package_config.json: $error');
      return libs;
    }
    Uri configUri = _config.absolute.uri;
    Set<String>? reachable = _reachable();
    for (dynamic entry in packages) {
      if (entry is! Map) continue;
      String name = '${entry['name']}';
      if (reachable != null && !reachable.contains(name)) continue;
      String rootUri = '${entry['rootUri']}';
      if (!rootUri.endsWith('/')) rootUri = '$rootUri/';
      Uri packageRoot = configUri.resolve(rootUri);
      String? library = _commandsKey(
        name,
        File.fromUri(packageRoot.resolve('pubspec.yaml')),
      );
      if (library == null) continue;
      String packageUri = '${entry['packageUri'] ?? 'lib/'}';
      if (!packageUri.endsWith('/')) packageUri = '$packageUri/';
      String? file = _libraryFile(
        name,
        library,
        packageRoot.resolve(packageUri),
      );
      if (file == null) continue;
      libs[name] = library;
      files?[name] = file;
    }
    return libs;
  }

  /// the `dox: commands:` value of a pubspec.yaml, or null
  String? _commandsKey(String package, File pubspec) {
    if (!pubspec.existsSync()) return null;
    String text = pubspec.readAsStringSync();

    /// most packages have no `dox:` key, skip the YAML parse for them
    if (!RegExp(r'^dox:', multiLine: true).hasMatch(text)) return null;
    dynamic dox;
    try {
      dynamic doc = loadYaml(text);
      dox = doc is Map ? doc['dox'] : null;
    } catch (error) {
      _warn('Skip $package: its pubspec.yaml is not valid YAML.');
      return null;
    }
    if (dox is! Map || dox['commands'] == null) return null;
    dynamic value = dox['commands'];
    if (value is! String) {
      _warn(
        'Skip $package: `dox: commands:` must be a library, like '
        'package:$package/commands.dart.',
      );
      return null;
    }
    return value.trim();
  }

  /// the path of [library], or null (with a warning) when it is not a
  /// `package:<package>/....dart` library that is there
  String? _libraryFile(String package, String library, Uri libDir) {
    String prefix = 'package:$package/';
    if (!library.startsWith(prefix) ||
        !_libraryValue.hasMatch(library) ||
        library.split('/').contains('..')) {
      _warn(
        'Skip $package: `dox: commands: $library` must be a library of '
        'the package itself, like ${prefix}commands.dart.',
      );
      return null;
    }
    File file = File.fromUri(libDir.resolve(library.substring(prefix.length)));
    if (!file.existsSync()) {
      _warn('Skip $package: $library is not there (${file.path}).');
      return null;
    }
    return file.path;
  }

  /// source of `.dart_tool/dox/commands.dart`. It uses the commands by
  /// their members (dynamic), so it works with any dox_core version.
  String runnerSource(Map<String, String> libs) {
    StringBuffer imports = StringBuffer();
    StringBuffer entries = StringBuffer();
    int i = 0;
    for (String package in libs.keys) {
      imports.writeln("import '${libs[package]}' as p$i;");
      entries.writeln("  '$package': p$i.commands,");
      i++;
    }
    String notFound = jsonEncode(notFoundMessage('{name}'));
    return '''
// Made by the dox CLI from the `dox: commands:` keys in pubspec.yaml.
// Do not edit. It is made again when the packages change.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';

$imports
/// package name => its commands
final Map<String, List<dynamic>> packages = <String, List<dynamic>>{
$entries};

Future<void> main(List<String> args) async {
  if (args.first == '--dox-list') {
    List<Map<String, String>> list = <Map<String, String>>[];
    for (String package in packages.keys) {
      for (dynamic command in packages[package]!) {
        list.add(<String, String>{
          'package': package,
          'name': command.name as String,
          'usage': command.usage as String,
          'description': command.description as String,
        });
      }
    }
    print('$listMarker\${jsonEncode(list)}');
    return;
  }

  String name = args.first;
  List<String> owners = <String>[];
  int matches = 0;
  dynamic found;
  for (String package in packages.keys) {
    for (dynamic command in packages[package]!) {
      if (command.name == name) {
        matches++;
        if (!owners.contains(package)) owners.add(package);
        found = command;
      }
    }
  }
  if (matches == 0) {
    print($notFound.replaceAll('{name}', name));
    exitCode = 1;
    return;
  }
  if (matches > 1) {
    print(
      'More than one command is named "\$name", in: '
      '\${owners.join(', ')}. Remove one of these packages, '
      'or ask its author to rename the command.',
    );
    exit(1);
  }
  try {
    await found.run(args.sublist(1));
  } catch (error, stack) {
    print(error);
    print(stack);
    if (exitCode == 0) exitCode = 1;
  }
  await stdout.flush();
  exit(exitCode);
}
''';
  }

  /// run the package command [name]. Return its exit code, or null when
  /// no package has commands (the caller prints "not found").
  Future<int?> run(String name, List<String> args) async {
    if (libraries().isEmpty) return null;
    return runScript(runner.path, <String>[name, ...args]);
  }

  /// every package command, for `dox help`. Empty outside an app or when
  /// no package has commands, without starting Dart. Else it runs the
  /// runner once and keeps the list until a package or a commands
  /// library changes.
  Future<List<PackageCommandInfo>> list() async {
    Map<String, String> libs = libraries();
    if (libs.isEmpty) return <PackageCommandInfo>[];
    Map<String, dynamic> cache = _readCache();
    String listKey = _listKey();
    dynamic commands = _cacheKey != null && cache['listKey'] == listKey
        ? cache['commands']
        : null;
    if (commands is! List) {
      commands = await _loadList();
      if (commands == null) {
        loadFailed = true;
        return <PackageCommandInfo>[];
      }
      if (_cacheKey != null && cache['key'] == _cacheKey) {
        cache['listKey'] = listKey;
        cache['commands'] = commands;
        _writeCache(cache);
      }
    }
    List<PackageCommandInfo> infos = <PackageCommandInfo>[];
    for (dynamic c in commands) {
      infos.add(
        PackageCommandInfo(
          '${c['package']}',
          '${c['name']}',
          '${c['usage']}',
          '${c['description']}',
        ),
      );
    }
    return infos;
  }

  /// `dart run .dart_tool/dox/commands.dart --dox-list`
  Future<List<dynamic>?> _loadList() async {
    ProcessResult result = await Process.run(dartExecutable(), <String>[
      'run',
      runner.path,
      '--dox-list',
    ], workingDirectory: root.path);
    String out = '${result.stdout}';
    for (String line in LineSplitter.split(out)) {
      if (!line.startsWith(listMarker)) continue;
      try {
        return jsonDecode(line.substring(listMarker.length)) as List<dynamic>;
      } catch (error) {
        break;
      }
    }
    _warn(
      'Could not load the package commands:\n'
      '${'$out\n${result.stderr}'.trim()}',
    );
    return null;
  }

  /// changes when package_config.json or the pubspec.yaml of the app or
  /// of any package change. So a path dependency (relative or absolute)
  /// that changes its key counts with no `dart pub get`. Reading every
  /// pubspec.yaml takes a few ms.
  String _key() {
    List<int> bytes = <int>[
      ..._config.readAsBytesSync(),
      0,
      ..._pubspec.readAsBytesSync(),
    ];
    try {
      dynamic config = jsonDecode(_config.readAsStringSync());
      Uri configUri = _config.absolute.uri;
      for (dynamic entry in (config as Map)['packages'] as List) {
        String rootUri = '${(entry as Map)['rootUri']}';
        if (!rootUri.endsWith('/')) rootUri = '$rootUri/';
        File pubspec = File.fromUri(
          configUri.resolve(rootUri).resolve('pubspec.yaml'),
        );
        bytes.add(0);
        if (pubspec.existsSync()) bytes.addAll(pubspec.readAsBytesSync());
      }
    } catch (error) {
      /// discover() prints the problem
    }
    return sha1.convert(bytes).toString();
  }

  /// [_cacheKey], plus the text of each commands library, so `dox help`
  /// sees a new command in a library that changed
  String _listKey() {
    List<int> bytes = <int>[...utf8.encode('$_cacheKey')];
    for (String path in _files.values) {
      File file = File(path);
      if (file.existsSync()) bytes.addAll(file.readAsBytesSync());
      bytes.add(0);
    }
    return sha1.convert(bytes).toString();
  }

  Map<String, dynamic> _readCache() {
    try {
      if (!_cache.existsSync()) return <String, dynamic>{};
      return jsonDecode(_cache.readAsStringSync()) as Map<String, dynamic>;
    } catch (error) {
      return <String, dynamic>{};
    }
  }

  void _writeCache(Map<String, dynamic> cache) {
    _writeAtomic(_cache, jsonEncode(cache));
  }

  /// write a temp file, then rename it, so a second `dox` that runs at
  /// the same time never reads a half-written file
  void _writeAtomic(File file, String text) {
    file.parent.createSync(recursive: true);
    File temp = File('${file.path}.$pid.tmp');
    temp.writeAsStringSync(text);
    temp.renameSync(file.path);
  }

  /// the warnings of the last [discover]. A discovery with warnings is
  /// not cached, so they show on each run until the package is fixed.
  final List<String> _warnings = <String>[];

  /// the warnings of the last [discover], read only
  List<String> get warnings => List<String>.unmodifiable(_warnings);

  /// true when the last [list] could not load the commands (the runner
  /// did not compile, or a commands library is broken)
  bool loadFailed = false;

  void _warn(String message) {
    _warnings.add(message);
    print('\x1B[33m$message\x1B[0m');
  }
}
