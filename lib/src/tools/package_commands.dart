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

  File _findConfig() {
    Directory dir = root;
    while (true) {
      File file = File('${dir.path}/.dart_tool/package_config.json');
      if (file.existsSync()) return file;
      Directory parent = dir.parent;
      if (parent.path == dir.path) {
        return File('${root.path}/.dart_tool/package_config.json');
      }
      dir = parent;
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
  /// From the cache when package_config.json and pubspec.yaml did not
  /// change. Else found again, and the runner is written again.
  Map<String, String> libraries() {
    if (!inApp) return <String, String>{};
    String key = _key();
    Map<String, dynamic> cache = _readCache();
    if (cache['key'] == key &&
        cache['libraries'] is Map &&
        (runner.existsSync() || (cache['libraries'] as Map).isEmpty)) {
      for (dynamic warning in (cache['warnings'] as List?) ?? <dynamic>[]) {
        _warn('$warning');
      }
      return Map<String, String>.from(cache['libraries'] as Map);
    }
    Map<String, String> files = <String, String>{};
    Map<String, String> libs = discover(files: files);
    if (libs.isEmpty) {
      if (runner.existsSync()) runner.deleteSync();
    } else {
      runner.createSync(recursive: true);
      runner.writeAsStringSync(runnerSource(libs));
    }
    _writeCache(<String, dynamic>{
      'key': key,
      'libraries': libs,
      'files': files,
      'warnings': _warnings,
    });
    return libs;
  }

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
    for (dynamic entry in packages) {
      if (entry is! Map) continue;
      String name = '${entry['name']}';
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
  dynamic found;
  for (String package in packages.keys) {
    for (dynamic command in packages[package]!) {
      if (command.name == name) {
        owners.add(package);
        found = command;
      }
    }
  }
  if (owners.isEmpty) {
    print($notFound.replaceAll('{name}', name));
    return;
  }
  if (owners.length > 1) {
    print(
      'More than one package has a command named "\$name": '
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
    String listKey = _listKey(cache);
    dynamic commands = cache['listKey'] == listKey ? cache['commands'] : null;
    if (commands is! List) {
      commands = await _loadList();
      if (commands == null) return <PackageCommandInfo>[];
      cache['listKey'] = listKey;
      cache['commands'] = commands;
      _writeCache(cache);
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

  /// changes when package_config.json, the app pubspec.yaml or the
  /// pubspec.yaml of a path dependency change. A path dependency has a
  /// relative `rootUri`. Hosted and git packages are in the pub cache
  /// and do not change.
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
        if (Uri.parse(rootUri).hasScheme) continue;
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

  /// [_key], plus the text of each commands library, so `dox help` sees
  /// a new command in a library that changed
  String _listKey(Map<String, dynamic> cache) {
    List<int> bytes = <int>[...utf8.encode('${cache['key']}')];
    dynamic files = cache['files'];
    if (files is Map) {
      for (dynamic path in files.values) {
        File file = File('$path');
        if (file.existsSync()) bytes.addAll(file.readAsBytesSync());
        bytes.add(0);
      }
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
    _cache.createSync(recursive: true);
    _cache.writeAsStringSync(jsonEncode(cache));
  }

  /// the warnings of the last [discover], kept in the cache so they show
  /// on each run until the package is fixed
  final List<String> _warnings = <String>[];

  void _warn(String message) {
    _warnings.add(message);
    print('\x1B[33m$message\x1B[0m');
  }
}
