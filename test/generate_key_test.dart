import 'dart:async';
import 'dart:io';

import 'package:dox/src/tools/generate_key.dart';
import 'package:test/test.dart';

void main() {
  final String root = Directory.current.path;
  late Directory dir;

  /// the lines that [body] prints
  List<String> printed(void Function() body) {
    List<String> lines = <String>[];
    runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          lines.add(line);
        },
      ),
    );
    return lines;
  }

  late File env;

  /// run `dox key:generate [args]` in the temp dir
  Future<ProcessResult> runDox(List<String> args) {
    return Process.run(
      Platform.resolvedExecutable,
      <String>['run', '$root/bin/dox.dart', 'key:generate', ...args],
      workingDirectory: dir.path,
      environment: <String, String>{'APP_ENV': 'development'},
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dox_key_');
    env = File('${dir.path}/.env');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('overrideKey keeps every other line as it is', () {
    env.writeAsStringSync(
      '# app\n'
      'APP_NAME="My App"\n'
      'APP_KEY=old\n'
      '\n'
      'DATABASE_URL=postgres://u:p@h/db?sslmode=require\n',
    );
    overrideKey('new', env.path);
    expect(
      env.readAsStringSync(),
      '# app\n'
      'APP_NAME="My App"\n'
      'APP_KEY=new\n'
      '\n'
      'DATABASE_URL=postgres://u:p@h/db?sslmode=require\n',
    );
  });

  test('overrideKey adds APP_KEY as the first line when missing', () {
    env.writeAsStringSync('A=b=c\n# note\n');
    overrideKey('new', env.path);
    expect(env.readAsStringSync(), 'APP_KEY=new\nA=b=c\n# note\n');
  });

  group('generateKey', () {
    const Map<String, String> prod = <String, String>{'APP_ENV': 'production'};

    setUp(() => env.writeAsStringSync('APP_KEY=old\n'));

    test('writes a new key outside production', () {
      expect(
        generateKey(<String>[], env: <String, String>{}, path: env.path),
        0,
      );
      expect(env.readAsStringSync(), isNot('APP_KEY=old\n'));
    });

    test('in production with a terminal, a "no" writes nothing', () {
      expect(
        generateKey(
          <String>[],
          env: prod,
          terminal: true,
          ask: () => 'n',
          path: env.path,
        ),
        1,
      );
      expect(env.readAsStringSync(), 'APP_KEY=old\n');
    });

    test('in production with a terminal, a "y" writes the key', () {
      expect(
        generateKey(
          <String>[],
          env: prod,
          terminal: true,
          ask: () => 'y',
          path: env.path,
        ),
        0,
      );
      expect(env.readAsStringSync(), isNot('APP_KEY=old\n'));
    });

    test('in production with no terminal, it warns and writes the key', () {
      int? code;
      List<String> lines = printed(() {
        code = generateKey(
          <String>[],
          env: prod,
          terminal: false,
          path: env.path,
        );
      });
      expect(code, 0);
      expect(lines, contains(contains('Warning: APP_ENV is production.')));
      expect(env.readAsStringSync(), isNot('APP_KEY=old\n'));
    });

    test('in production --force writes the key with no question', () {
      expect(
        generateKey(
          <String>['--force'],
          env: prod,
          terminal: true,
          ask: () => throw StateError('must not ask'),
          path: env.path,
        ),
        0,
      );
      expect(env.readAsStringSync(), isNot('APP_KEY=old\n'));
    });

    test('--show writes nothing', () {
      expect(generateKey(<String>['--show'], env: prod, path: env.path), 0);
      expect(
        generateKey(
          <String>['--show'],
          env: <String, String>{},
          path: env.path,
        ),
        0,
      );
      expect(env.readAsStringSync(), 'APP_KEY=old\n');
    });

    test('an unknown option is ignored with a warning on stderr', () async {
      env.writeAsStringSync('APP_KEY=old\n');
      ProcessResult r = await runDox(<String>['foo']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stderr}', contains('ignoring unknown option foo'));
      expect('${r.stdout}', isNot(contains('ignoring')));
      expect(env.readAsStringSync(), isNot('APP_KEY=old\n'));
    });

    test(
      '--show with an unknown option prints only the key on stdout',
      () async {
        ProcessResult r = await runDox(<String>['--show', 'foo']);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect('${r.stdout}', matches(RegExp(r'^[A-Za-z0-9]{32}\n$')));
        expect('${r.stderr}', contains('ignoring unknown option foo'));
      },
    );
  });
}
