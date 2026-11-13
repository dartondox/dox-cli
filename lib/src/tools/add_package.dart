import 'dart:io';

import 'package:dox/src/tools/package_commands.dart';
import 'package:dox/src/utils/run_script.dart';
import 'package:yaml/yaml.dart';

/// `dox add <name> [--dev] [args]`: add a Dox package, then run its
/// `<name>:install` command to set it up. `orm` is `dox_orm`. The other
/// args go to the install command, like `--driver=postgres`.
///
/// The CLI has no code of any package. Each package ships its own
/// `<name>:install` command (see the "Package commands" docs page).
class AddPackage {
  /// [root] is the app folder, the current folder by default
  AddPackage({Directory? root}) : root = (root ?? Directory.current).absolute;

  final Directory root;

  /// `orm`, `dox_orm` and `dox-orm` all give `dox_orm`. Null for a name
  /// that is not a valid package name.
  static String? packageName(String name) {
    String package = name.replaceAll('-', '_');
    if (!package.startsWith('dox_')) package = 'dox_$package';
    return RegExp(r'^dox_[a-z0-9_]+$').hasMatch(package) ? package : null;
  }

  Future<void> run(List<String> args) async {
    String? package = packageName(args.first);
    if (package == null) {
      print('\x1B[31m"${args.first}" is not a valid package name.\x1B[0m');
      exitCode = 1;
      return;
    }
    if (!File('${root.path}/pubspec.yaml').existsSync()) {
      print('\x1B[31mRun `dox add` in the folder of your app.\x1B[0m');
      exitCode = 1;
      return;
    }
    bool dev = args.contains('--dev');
    List<String> rest = args
        .skip(1)
        .where((String arg) => arg != '--dev')
        .toList();

    if (!_hasDependency(package)) {
      String flag = dev ? '--dev ' : '';
      if (!await _dart(<String>['pub', 'add', if (dev) '--dev', package])) {
        print('\x1B[31m`dart pub add $flag$package` failed.\x1B[0m');
        return;
      }
    }
    if (!await _dart(<String>['pub', 'get'])) return;

    String command = '${package.substring('dox_'.length)}:install';
    PackageCommands commands = PackageCommands(root: root);
    bool found = false;
    for (PackageCommandInfo info in await commands.list()) {
      if (info.package == package && info.name == command) found = true;
    }
    if (!found) {
      print(
        '\x1B[32mInstalled $package.\x1B[0m It has no setup command '
        '($command), so there is nothing more to do.',
      );
      return;
    }
    int? code = await commands.run(command, rest);
    if (code != null && code != 0) exitCode = code;
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

  /// `dart <args>` in the app folder, with the output on this terminal.
  /// Sets the exit code when it fails.
  Future<bool> _dart(List<String> args) async {
    Process process = await Process.start(
      dartExecutable(),
      args,
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
    );
    int code = await process.exitCode;
    if (code != 0) exitCode = code;
    return code == 0;
  }
}
