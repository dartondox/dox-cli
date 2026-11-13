import 'dart:io';

import 'package:dox/src/tools/package_commands.dart';
import 'package:dox/src/utils/run_script.dart';
import 'package:yaml/yaml.dart';

/// Runs `dart <args>` in the app folder, with the output on this
/// terminal. Tests pass a fake one to [AddPackage].
class DartRunner {
  Future<int> run(List<String> args, String folder) async {
    Process process = await Process.start(
      dartExecutable(),
      args,
      workingDirectory: folder,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }
}

/// `dox add <name> [--dev] [args]`: add a Dox package, then run its
/// `<name>:install` command to set it up. `orm` is `dox_orm`. The other
/// args go to the install command, like `--driver=postgres`.
///
/// The CLI has no code of any package. Each package ships its own
/// `<name>:install` command (see the "Package commands" docs page).
class AddPackage {
  /// [root] is the app folder, the current folder by default. Tests pass
  /// a fake [runner] and [commands].
  AddPackage({Directory? root, DartRunner? runner, this.commands})
    : root = (root ?? Directory.current).absolute,
      _runner = runner ?? DartRunner();

  final Directory root;
  final DartRunner _runner;

  /// the package commands of the app, made from [root] when null
  final PackageCommands? commands;

  static final RegExp _package = RegExp(r'^dox_[a-z0-9]+(_[a-z0-9]+)*$');

  /// `orm`, `dox_orm` and `dox-orm` all give `dox_orm`. Null for a name
  /// that is not a valid package name.
  static String? packageName(String name) {
    String package = name.replaceAll('-', '_');
    if (!package.startsWith('dox_')) package = 'dox_$package';
    return _package.hasMatch(package) ? package : null;
  }

  Future<void> run(List<String> args) async {
    int index = args.indexWhere((String arg) => !arg.startsWith('-'));
    if (index == -1) {
      _fail('Give a package name, like `dox add orm`.');
      return;
    }
    String? package = packageName(args[index]);
    if (package == null) {
      _fail('"${args[index]}" is not a valid package name.');
      return;
    }
    if (!File('${root.path}/pubspec.yaml').existsSync()) {
      _fail('Run `dox add` in the folder of your app.');
      return;
    }
    bool dev = args.contains('--dev');
    List<String> rest = <String>[];
    for (int i = 0; i < args.length; i++) {
      if (i != index && args[i] != '--dev') rest.add(args[i]);
    }

    if (!_hasDependency(package)) {
      if (!await _dart(<String>['pub', 'add', if (dev) '--dev', package])) {
        print('\x1B[31m`dart pub add $package` failed.\x1B[0m');
        return;
      }
    }
    if (!await _dart(<String>['pub', 'get'])) return;

    String command = '${package.substring('dox_'.length)}:install';
    PackageCommands packages = commands ?? PackageCommands(root: root);
    bool found = false;
    for (PackageCommandInfo info in await packages.list()) {
      if (info.package == package && info.name == command) found = true;
    }
    bool broken = packages.warnings.any(
      (String warning) => warning.startsWith('Skip $package:'),
    );
    if (!found && (packages.loadFailed || broken)) {
      _fail(
        'Added $package, but could not load the package commands, so '
        '$command did not run. Fix the error above, then run '
        '`dox add ${args[index]}` again.',
      );
      return;
    }
    if (!found) {
      print(
        '\x1B[32mInstalled $package.\x1B[0m It has no setup command '
        '($command), so there is nothing more to do.',
      );
      return;
    }
    int? code = await packages.run(command, rest);
    if (code != null && code != 0) exitCode = code;
  }

  void _fail(String message) {
    print('\x1B[31m$message\x1B[0m');
    exitCode = 1;
  }

  /// true when [package] is in dependencies or dev_dependencies
  bool _hasDependency(String package) {
    dynamic doc = loadYaml(
      File('${root.path}/pubspec.yaml').readAsStringSync(),
    );
    if (doc is! Map) return false;
    for (String key in <String>['dependencies', 'dev_dependencies']) {
      dynamic section = doc[key];
      if (section is Map && section.containsKey(package)) return true;
    }
    return false;
  }

  /// `dart <args>` in the app folder. Sets the exit code when it fails.
  Future<bool> _dart(List<String> args) async {
    int code = await _runner.run(args, root.path);
    if (code != 0) exitCode = code;
    return code == 0;
  }
}
