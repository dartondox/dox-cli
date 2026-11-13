import 'dart:io';

import 'package:dox/src/tools/add_package.dart';
import 'package:dox/src/tools/package_commands.dart';
import 'package:test/test.dart';

/// records the `dart` commands. `pub add` gives [addCode].
class FakeDart extends DartRunner {
  FakeDart([this.addCode = 0]);

  final int addCode;
  final List<String> calls = <String>[];

  @override
  Future<int> run(List<String> args, String folder) async {
    calls.add(args.join(' '));
    return args[1] == 'add' ? addCode : 0;
  }
}

/// gives [infos] and records the command that runs
class FakeCommands extends PackageCommands {
  FakeCommands(Directory root, this.infos, {bool failed = false})
    : super(root: root) {
    loadFailed = failed;
  }

  final List<PackageCommandInfo> infos;
  List<String>? ran;

  @override
  Future<List<PackageCommandInfo>> list() async => infos;

  @override
  Future<int?> run(String name, List<String> args) async {
    ran = <String>[name, ...args];
    return 0;
  }
}

void main() {
  late Directory root;
  late FakeDart dart;

  PackageCommandInfo install(String package, String name) {
    return PackageCommandInfo(package, name, name, '');
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('dox_add_');
    File('${root.path}/pubspec.yaml')
        .writeAsStringSync('name: app\ndependencies:\n  dox_core: ^3.1.0\n');
    dart = FakeDart();
    exitCode = 0;
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    exitCode = 0;
  });

  Future<FakeCommands> add(
    List<String> args,
    List<PackageCommandInfo> infos, {
    bool failed = false,
  }) async {
    FakeCommands commands = FakeCommands(root, infos, failed: failed);
    await AddPackage(root: root, runner: dart, commands: commands).run(args);
    return commands;
  }

  test('the short name gets the dox_ prefix', () {
    expect(AddPackage.packageName('orm'), 'dox_orm');
    expect(AddPackage.packageName('dox_orm'), 'dox_orm');
    expect(AddPackage.packageName('dox-queue-database'), 'dox_queue_database');
    expect(AddPackage.packageName('Bad Name'), isNull);
    expect(AddPackage.packageName('../x'), isNull);
    expect(AddPackage.packageName('a__b'), isNull);
    expect(AddPackage.packageName('dox_'), isNull);
  });

  test('outside an app it stops with exit code 1', () async {
    File('${root.path}/pubspec.yaml').deleteSync();
    await add(<String>['orm'], <PackageCommandInfo>[]);
    expect(exitCode, 1);
    expect(dart.calls, isEmpty);
  });

  test(
    'adds the package, then runs its install command with the args',
    () async {
      FakeCommands commands = await add(
        <String>['orm', '--driver=postgres'],
        <PackageCommandInfo>[install('dox_orm', 'orm:install')],
      );
      expect(dart.calls, <String>['pub add dox_orm', 'pub get']);
      expect(commands.ran, <String>['orm:install', '--driver=postgres']);
      expect(exitCode, 0);
    },
  );

  test('--dev before or after the name goes to pub add only', () async {
    for (List<String> args in <List<String>>[
      <String>['--dev', 'orm', '--x'],
      <String>['orm', '--dev', '--x'],
    ]) {
      dart.calls.clear();
      FakeCommands commands = await add(args, <PackageCommandInfo>[
        install('dox_orm', 'orm:install'),
      ]);
      expect(dart.calls.first, 'pub add --dev dox_orm');
      expect(commands.ran, <String>['orm:install', '--x']);
    }
  });

  test('a flag alone is not a name', () async {
    await add(<String>['--dev'], <PackageCommandInfo>[]);
    expect(exitCode, 1);
    expect(dart.calls, isEmpty);
  });

  test('a package that is there is not added again', () async {
    await add(<String>['core'], <PackageCommandInfo>[]);
    expect(dart.calls, <String>['pub get']);
  });

  test('a failed pub add keeps its exit code and stops', () async {
    dart = FakeDart(65);
    FakeCommands commands = await add(
      <String>['orm'],
      <PackageCommandInfo>[install('dox_orm', 'orm:install')],
    );
    expect(exitCode, 65);
    expect(dart.calls, <String>['pub add dox_orm']);
    expect(commands.ran, isNull);
  });

  test('a package with no install command is only added', () async {
    FakeCommands commands = await add(
      <String>['cache'],
      <PackageCommandInfo>[
        install('dox_orm', 'orm:install'),
        install('dox_other', 'cache:install'),
      ],
    );
    expect(exitCode, 0);
    expect(commands.ran, isNull);
  });

  test('when the commands can not be loaded it fails', () async {
    FakeCommands commands = await add(
      <String>['orm'],
      <PackageCommandInfo>[],
      failed: true,
    );
    expect(exitCode, 1);
    expect(commands.ran, isNull);
  });
}
