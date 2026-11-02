import 'dart:io';

import 'package:dox/src/tools/generate_key.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late File env;

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

    test('in production it writes nothing without --force', () {
      expect(generateKey(<String>[], env: prod, path: env.path), 1);
      expect(env.readAsStringSync(), 'APP_KEY=old\n');
    });

    test('in production --force writes the key', () {
      expect(generateKey(<String>['--force'], env: prod, path: env.path), 0);
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

    test('an unknown option writes nothing', () {
      expect(
        generateKey(
          <String>['--nope'],
          env: <String, String>{},
          path: env.path,
        ),
        1,
      );
      expect(env.readAsStringSync(), 'APP_KEY=old\n');
    });
  });
}
