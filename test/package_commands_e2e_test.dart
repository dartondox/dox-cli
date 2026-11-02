@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:dox/src/utils/run_script.dart';
import 'package:test/test.dart';

/// End to end: a temp app that depends on local packages with commands.
/// It runs `dox <cmd>` from this source, like a user would.
/// The packages do not use dox_core: the runner only needs `name`,
/// `description`, `usage` and `run`, so this works offline.
void main() {
  late Directory temp;
  late Directory app;
  String cli = Directory.current.path;

  /// a package with one command named [command]
  void package(String name, String command, String body) {
    Directory root = Directory('${temp.path}/$name');
    File('${root.path}/pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
name: $name
environment:
  sdk: ^3.0.0
dox:
  commands: package:$name/commands.dart
''');
    File('${root.path}/lib/commands.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
import 'dart:io';

class C {
  String get name => '$command';
  String get description => 'The $command command of $name';
  String get usage => '$command <who>';
  Future<void> run(List<String> args) async {
    $body
  }
}

final List<C> commands = <C>[C()];
''');
  }

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('dox_pkg_e2e_');
    app = Directory('${temp.path}/app')..createSync();
    package('hello_pkg', 'hello', r"print('Hello ${args.join(' ')}');");
    package('fail_pkg', 'fail', 'exitCode = 3;');
    package('throw_pkg', 'boom', "throw StateError('boom failed');");
    package('clash_a', 'same', "print('a');");
    package('clash_b', 'same', "print('b');");
    package('builtin_pkg', 'version', "print('package version');");
    File('${app.path}/pubspec.yaml').writeAsStringSync('''
name: app
environment:
  sdk: ^3.0.0
dependencies:
  hello_pkg: {path: ../hello_pkg}
  fail_pkg: {path: ../fail_pkg}
  throw_pkg: {path: ../throw_pkg}
  clash_a: {path: ../clash_a}
  clash_b: {path: ../clash_b}
  builtin_pkg: {path: ../builtin_pkg}
dox:
  commands: package:app/commands.dart
''');
    File('${app.path}/lib/commands.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
class AppCommand {
  String get name => 'app:hi';
  String get description => 'A command of the app';
  String get usage => 'app:hi';
  Future<void> run(List<String> args) async => print('hi from the app');
}

final List<AppCommand> commands = <AppCommand>[AppCommand()];
''');
    ProcessResult get = await Process.run(dartExecutable(), <String>[
      'pub',
      'get',
      '--offline',
    ], workingDirectory: app.path);
    expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');
  });

  tearDownAll(() {
    temp.deleteSync(recursive: true);
  });

  /// `dox <args>` in the app, from the source of this CLI
  Future<ProcessResult> dox(List<String> args) {
    return Process.run(dartExecutable(), <String>[
      '--packages=$cli/.dart_tool/package_config.json',
      '$cli/bin/dox.dart',
      ...args,
    ], workingDirectory: app.path);
  }

  test('runs a package command with its args', () async {
    ProcessResult r = await dox(<String>['hello', 'big', 'world']);
    expect(r.stdout, contains('Hello big world'));
    expect(r.exitCode, 0);
    expect(
      File('${app.path}/.dart_tool/dox/commands.dart').existsSync(),
      isTrue,
    );
  });

  test('runs a command of the app', () async {
    ProcessResult r = await dox(<String>['app:hi']);
    expect(r.stdout, contains('hi from the app'));
    expect(r.exitCode, 0);
  });

  test('passes the exit code through', () async {
    ProcessResult r = await dox(<String>['fail']);
    expect(r.exitCode, 3);
  });

  test('a thrown error prints the stack trace and exits 1', () async {
    ProcessResult r = await dox(<String>['boom']);
    expect(r.stdout, contains('boom failed'));
    expect(r.stdout, contains('package:throw_pkg/commands.dart'));
    expect(r.exitCode, 1);
  });

  test('a package command does not touch the migration files', () async {
    Directory db = Directory('${app.path}/db/migration')
      ..createSync(recursive: true);
    File('${db.path}/2020_01_01_000000_wip.dart').writeAsStringSync('// wip');
    ProcessResult r = await dox(<String>['hello']);
    expect(r.exitCode, 0);
    expect(File('${db.path}/migrations.dart').existsSync(), isFalse);
    expect(File('${app.path}/bin/migrate.dart').existsSync(), isFalse);
    Directory('${app.path}/db').deleteSync(recursive: true);
  });

  test('works in an app inside a pub workspace', () async {
    Directory ws = Directory('${temp.path}/ws')..createSync();
    File('${ws.path}/pubspec.yaml').writeAsStringSync('''
name: ws
environment:
  sdk: ^3.6.0
workspace:
  - member
''');
    Directory member = Directory('${ws.path}/member')..createSync();
    File('${member.path}/pubspec.yaml').writeAsStringSync('''
name: member
environment:
  sdk: ^3.6.0
resolution: workspace
dependencies:
  hello_pkg: {path: ../../hello_pkg}
''');
    ProcessResult get = await Process.run(dartExecutable(), <String>[
      'pub',
      'get',
      '--offline',
    ], workingDirectory: ws.path);
    expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');

    ProcessResult r = await Process.run(dartExecutable(), <String>[
      '--packages=$cli/.dart_tool/package_config.json',
      '$cli/bin/dox.dart',
      'hello',
      'ws',
    ], workingDirectory: member.path);
    expect(r.stdout, contains('Hello ws'), reason: '${r.stderr}');
    expect(r.exitCode, 0);
  });

  test('a commands library made after the key is found', () async {
    Directory late = Directory('${temp.path}/late_app')..createSync();
    File('${late.path}/pubspec.yaml').writeAsStringSync('''
name: late_app
environment:
  sdk: ^3.0.0
dox:
  commands: package:late_app/commands.dart
''');
    ProcessResult get = await Process.run(dartExecutable(), <String>[
      'pub',
      'get',
      '--offline',
    ], workingDirectory: late.path);
    expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');

    Future<ProcessResult> run() {
      return Process.run(dartExecutable(), <String>[
        '--packages=$cli/.dart_tool/package_config.json',
        '$cli/bin/dox.dart',
        'late:hi',
      ], workingDirectory: late.path);
    }

    ProcessResult before = await run();
    expect(before.stdout, contains('Skip late_app'));
    expect(before.stdout, contains('Could not find a command'));

    File('${late.path}/lib/commands.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
class Late {
  String get name => 'late:hi';
  String get description => 'late';
  String get usage => 'late:hi';
  Future<void> run(List<String> args) async => print('late hi');
}

final List<Late> commands = <Late>[Late()];
''');
    ProcessResult after = await run();
    expect(after.stdout, contains('late hi'));
    expect(after.stdout, isNot(contains('Skip late_app')));
    expect(after.exitCode, 0);
  });

  test('two packages with one name print an error', () async {
    ProcessResult r = await dox(<String>['same']);
    expect(r.stdout, contains('More than one command'));
    expect(r.stdout, contains('clash_a, clash_b'));
    expect(r.exitCode, 1);
  });

  test('a built-in command wins', () async {
    ProcessResult r = await dox(<String>['version']);
    expect(r.stdout, contains('Dox version'));
    expect(r.stdout, isNot(contains('package version')));
  });

  test('an unknown command prints not found with a hint', () async {
    ProcessResult r = await dox(<String>['nope']);
    expect(r.stdout, contains('Could not find a command named "nope"'));
    expect(r.stdout, contains('`dox: commands:`'));
  });

  test('help lists the package commands by package', () async {
    ProcessResult r = await dox(<String>['help']);
    String out = '${r.stdout}';
    expect(out, contains('hello_pkg:'));
    expect(out, contains('hello <who>'));
    expect(out, contains('The hello command of hello_pkg'));
    expect(out, contains('app:hi'));
    expect(out, contains('a built-in command has this name'));
    expect(out, contains('more than one command has this name'));

    ProcessResult one = await dox(<String>['help', 'hello']);
    expect(one.stdout, contains('Package:'));
    expect(one.stdout, contains('hello_pkg'));
  });

  test('help outside an app does not fail', () async {
    ProcessResult r = await Process.run(dartExecutable(), <String>[
      '--packages=$cli/.dart_tool/package_config.json',
      '$cli/bin/dox.dart',
      'help',
    ], workingDirectory: temp.path);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('Available commands'));
  });
}
