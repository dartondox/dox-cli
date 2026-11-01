import 'dart:io';

import 'package:dox/src/tools/create_project.dart';
import 'package:test/test.dart';

void main() {
  test('replaceProjectName skips binary files and renames text files', () {
    Directory dir = Directory.systemTemp.createTempSync('dox_create_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File text = File('${dir.path}/pubspec.yaml')
      ..writeAsStringSync('name: dox_sample\n');
    File same = File('${dir.path}/README.md')..writeAsStringSync('hello\n');
    DateTime before = same.lastModifiedSync();
    Directory('${dir.path}/db').createSync();
    List<int> bytes = <int>[0xff, 0xfe, 0x00, 0x80, 0xc3];
    File binary = File('${dir.path}/db/dox.sqlite-shm')
      ..writeAsBytesSync(bytes);

    replaceProjectName(dir, 'my_app');

    expect(text.readAsStringSync(), 'name: my_app\n');
    expect(binary.readAsBytesSync(), bytes);
    expect(same.lastModifiedSync(), before);
  });

  test('createEnv copies .env.example to .env with a new APP_KEY', () {
    Directory dir = Directory.systemTemp.createTempSync('dox_create_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/.env.example')
        .writeAsStringSync('APP_NAME=dox\nAPP_KEY=\nAPP_PORT=3000\n');

    createEnv(dir);

    List<String> lines = File('${dir.path}/.env').readAsLinesSync();
    expect(lines[0], 'APP_NAME=dox');
    expect(lines[1], matches(RegExp(r'^APP_KEY=[A-Za-z0-9]{32}$')));
    expect(lines[2], 'APP_PORT=3000');
  });

  test('createProject rejects names that are not Dart package names', () async {
    Directory original = Directory.current;
    Directory dir = Directory.systemTemp.createTempSync('dox_create_');
    Directory.current = dir;
    addTearDown(() {
      Directory.current = original;
      dir.deleteSync(recursive: true);
    });
    // a version is given, so no network call happens before the check
    for (String name in <String>[
      '-x',
      '--upload-pack=touch pwned',
      '../app',
      '1app',
      'my-app',
    ]) {
      expect(await createProject(name, '3.0.0'), isFalse, reason: name);
      expect(exitCode, 1, reason: name);
      exitCode = 0;
    }
    expect(dir.listSync(), isEmpty);
  });

  group('dox create with a broken git', () {
    late Directory dir;
    late Directory bin;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('dox_create_');
      bin = Directory('${dir.path}/bin')..createSync();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    /// runs the real cli with only [bin] on PATH
    Future<ProcessResult> create() {
      return Process.run(
        Platform.resolvedExecutable,
        <String>[
          '${Directory.current.path}/bin/dox.dart',
          'create',
          'my_app',
          '--version',
          '3.0.0',
        ],
        workingDirectory: dir.path,
        environment: <String, String>{'PATH': bin.path},
      );
    }

    test('git is missing', () async {
      ProcessResult r = await create();
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout, contains('Could not run git'));
    });

    test('git clone fails', () async {
      File git = File('${bin.path}/git')
        ..writeAsStringSync('#!/bin/sh\necho "fatal: boom" >&2\nexit 128\n');
      Process.runSync('chmod', <String>['+x', git.path]);
      ProcessResult r = await create();
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout, contains('git clone failed'));
      expect(r.stdout, contains('fatal: boom'));
    }, testOn: '!windows');
  });
}
