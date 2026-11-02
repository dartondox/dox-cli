import 'dart:io';

import 'package:dox/src/command_registry.dart';
import 'package:dox/src/utils/confirm_drop.dart';
import 'package:test/test.dart';

void main() {
  Map<String, String> prod = <String, String>{'APP_ENV': 'production'};

  String? fail() => throw StateError('must not ask');

  test('not production: runs, no question', () {
    expect(
      confirmDropAll(
        force: false,
        env: <String, String>{'APP_ENV': 'local'},
        terminal: true,
        ask: fail,
      ),
      isTrue,
    );
    expect(
      confirmDropAll(force: false, env: {}, terminal: true, ask: fail),
      isTrue,
    );
  });

  test('production with --force: runs, no question', () {
    expect(
      confirmDropAll(force: true, env: prod, terminal: true, ask: fail),
      isTrue,
    );
  });

  test('production, no terminal: warns and runs', () {
    expect(
      confirmDropAll(force: false, env: prod, terminal: false, ask: fail),
      isTrue,
    );
  });

  test('production, terminal: runs only on y', () {
    for (String? answer in <String?>['y', 'Y', ' y ']) {
      expect(
        confirmDropAll(
          force: false,
          env: prod,
          terminal: true,
          ask: () => answer,
        ),
        isTrue,
      );
    }
    for (String? answer in <String?>['', 'n', 'yes', null]) {
      expect(
        confirmDropAll(
          force: false,
          env: prod,
          terminal: true,
          ask: () => answer,
        ),
        isFalse,
      );
    }
  });

  group('migration commands', () {
    late Directory tempDir;
    late Directory originalCwd;
    List<bool> forces = <bool>[];

    setUp(() {
      originalCwd = Directory.current;
      tempDir = Directory.systemTemp.createTempSync('dox_confirm_test_');
      Directory.current = tempDir;
      // a fake bin/migrate.dart that writes the args it got
      File('bin/migrate.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          "import 'dart:io';\n"
          "void main(List<String> a) => File('ran').writeAsStringSync(a.join(' '));\n",
        );
      forces.clear();
    });

    tearDown(() {
      confirmDrop = confirmDropAll;
      exitCode = 0;
      Directory.current = originalCwd;
      tempDir.deleteSync(recursive: true);
    });

    for (String command in <String>[
      'migration:rollback',
      'migration:reset',
      'migration:refresh',
      'migration:fresh',
    ]) {
      test('$command: a "no" stops before the migration runs', () async {
        confirmDrop = ({required bool force, String danger = ''}) {
          forces.add(force);
          return false;
        };
        await CommandRegistry.findCommand(command)!.function(<String>[]);
        expect(forces, <bool>[false]);
        expect(exitCode, 1);
        expect(File('ran').existsSync(), isFalse);
      });
    }

    test(
      'rollback --force: asks with force, does not pass --force on',
      () async {
        confirmDrop = ({required bool force, String danger = ''}) {
          forces.add(force);
          return true;
        };
        await CommandRegistry.findCommand('migration:rollback')!
            .function(<String>['--force', '--step=2']);
        expect(forces, <bool>[true]);
        expect(File('ran').readAsStringSync(), 'rollback --step=2');
      },
    );

    test('rollback --step 2 (with a space) works', () async {
      confirmDrop = ({required bool force, String danger = ''}) => true;
      await CommandRegistry.findCommand('migration:rollback')!
          .function(<String>['--step', '2', '--force']);
      expect(exitCode, 0);
      expect(File('ran').readAsStringSync(), 'rollback --step=2');
    });

    test('rollback with --step twice stops with an error', () async {
      confirmDrop = ({required bool force, String danger = ''}) => true;
      for (List<String> args in <List<String>>[
        <String>['--step=2', '--step=3'],
        <String>['--step', '2', '--step=3'],
        <String>['--step'],
        <String>['--step', 'x'],
      ]) {
        exitCode = 0;
        await CommandRegistry.findCommand('migration:rollback')!.function(args);
        expect(exitCode, 1, reason: '$args');
        expect(File('ran').existsSync(), isFalse, reason: '$args');
      }
    });

    test('migrate --force: no question, --force is not passed on', () async {
      confirmDrop = ({required bool force, String danger = ''}) =>
          throw StateError('must not ask');
      await CommandRegistry.findCommand('migrate')!
          .function(<String>['--force']);
      expect(File('ran').readAsStringSync(), 'run');
    });
  });
}
