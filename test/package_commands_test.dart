import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dox/src/tools/package_commands.dart';
import 'package:test/test.dart';

/// Discovery and generation of package commands. These tests write
/// package_config.json by hand, so no `dart pub get` runs.
void main() {
  late Directory temp;
  late Directory app;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('dox_pkg_cmd_');
    app = Directory('${temp.path}/app')..createSync();
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  /// a package folder with [pubspecExtra] at the end of its pubspec.yaml
  /// and the files in [lib]
  void package(
    String name,
    String pubspecExtra, {
    Map<String, String> lib = const <String, String>{},
    Directory? dir,
  }) {
    Directory root = dir ?? Directory('${temp.path}/$name');
    File('${root.path}/pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: $name\n$pubspecExtra');
    for (String path in lib.keys) {
      File('${root.path}/lib/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(lib[path]!);
    }
  }

  /// package_config.json of the app with the app and [packages].
  /// [relative] packages are path dependencies (a relative `rootUri`),
  /// the others look like hosted packages (an absolute `file:` uri).
  void packageConfig(
    List<String> packages, {
    List<String> relative = const <String>[],
  }) {
    List<Map<String, String>> entries = <Map<String, String>>[
      <String, String>{'name': 'app', 'rootUri': '../', 'packageUri': 'lib/'},
    ];
    for (String name in packages) {
      entries.add(<String, String>{
        'name': name,
        'rootUri': Directory('${temp.path}/$name').uri.toString(),
        'packageUri': 'lib/',
      });
    }
    for (String name in relative) {
      entries.add(<String, String>{
        'name': name,
        'rootUri': '../../$name',
        'packageUri': 'lib/',
      });
    }
    File('${app.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode(<String, dynamic>{'configVersion': 2, 'packages': entries}),
      );
  }

  /// run [body] and return what it printed
  T capture<T>(T Function() body, StringBuffer out) {
    return runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          out.writeln(line);
        },
      ),
    );
  }

  const String withKey = 'dox:\n  commands: package:pkg/commands.dart\n';

  test('outside an app there are no commands', () async {
    PackageCommands commands = PackageCommands(root: temp);
    expect(commands.inApp, isFalse);
    expect(commands.libraries(), isEmpty);
    expect(await commands.list(), isEmpty);
  });

  test('finds the commands of a package and of the app', () {
    package(
      'pkg',
      withKey,
      lib: <String, String>{'commands.dart': 'var commands = [];'},
    );
    package('plain', '');
    package(
      'app',
      'dox:\n  commands: package:app/commands.dart\n',
      lib: <String, String>{'commands.dart': 'var commands = [];'},
      dir: app,
    );
    packageConfig(<String>['pkg', 'plain']);

    PackageCommands commands = PackageCommands(root: app);
    expect(commands.libraries(), <String, String>{
      'app': 'package:app/commands.dart',
      'pkg': 'package:pkg/commands.dart',
    });
    String runner = commands.runner.readAsStringSync();
    expect(runner, contains("import 'package:pkg/commands.dart' as p"));
    expect(runner, contains("import 'package:app/commands.dart' as p"));
    expect(runner, contains("'pkg': p"));
  });

  test('a package without the key has no commands and no runner', () {
    package('pkg', 'dependencies:\n  path: any\n');
    package('app', '', dir: app);
    packageConfig(<String>['pkg']);

    PackageCommands commands = PackageCommands(root: app);
    expect(commands.libraries(), isEmpty);
    expect(commands.runner.existsSync(), isFalse);
  });

  test('a bad library is skipped with a warning', () {
    package(
      'other',
      'dox:\n  commands: package:pkg/commands.dart\n',
      lib: <String, String>{'commands.dart': ''},
    );
    package('missing', 'dox:\n  commands: package:missing/nope.dart\n');
    package('list', 'dox:\n  commands:\n    - a\n');
    package('broken', 'dox: [\n');
    package(
      'pkg',
      withKey,
      lib: <String, String>{'commands.dart': 'var commands = [];'},
    );
    package('app', '', dir: app);
    packageConfig(<String>['other', 'missing', 'list', 'broken', 'pkg']);

    StringBuffer out = StringBuffer();
    Map<String, String> libs = capture(
      () => PackageCommands(root: app).libraries(),
      out,
    );
    expect(libs.keys, <String>['pkg']);
    expect(out.toString(), contains('Skip other'));
    expect(out.toString(), contains('Skip missing'));
    expect(out.toString(), contains('Skip list'));
    expect(out.toString(), contains('Skip broken'));

    /// not cached: the warning shows again on the next run
    expect(
      File('${app.path}/.dart_tool/dox/commands.json').existsSync(),
      isFalse,
    );
    StringBuffer again = StringBuffer();
    capture(() => PackageCommands(root: app).libraries(), again);
    expect(again.toString(), contains('Skip other'));
  });

  test('uses the cache until package_config.json or pubspec.yaml change', () {
    package(
      'pkg',
      withKey,
      lib: <String, String>{'commands.dart': 'var commands = [];'},
    );
    package('app', '', dir: app);
    packageConfig(<String>['pkg']);
    expect(PackageCommands(root: app).libraries().keys, <String>['pkg']);

    /// no change: the cache is used, even when a library file is gone
    File('${temp.path}/pkg/lib/commands.dart')
        .renameSync('${temp.path}/pkg/commands.bak');
    expect(PackageCommands(root: app).libraries().keys, <String>['pkg']);
    File('${temp.path}/pkg/commands.bak')
        .renameSync('${temp.path}/pkg/lib/commands.dart');

    /// a change in a package pubspec.yaml (also an absolute path
    /// dependency) is read again
    package('pkg', '');
    expect(PackageCommands(root: app).libraries(), isEmpty);
    package('pkg', withKey);
    expect(PackageCommands(root: app).libraries().keys, <String>['pkg']);

    /// `dart pub get` writes package_config.json again
    packageConfig(<String>[]);
    expect(PackageCommands(root: app).libraries(), isEmpty);
    expect(PackageCommands(root: app).runner.existsSync(), isFalse);

    /// a change in the app pubspec.yaml counts too
    package(
      'app',
      'dox:\n  commands: package:app/commands.dart\n',
      lib: <String, String>{'commands.dart': 'var commands = [];'},
      dir: app,
    );
    expect(PackageCommands(root: app).libraries().keys, <String>['app']);
  });

  test('a path dependency that changes its key is read again', () {
    package('pkg', '');
    package('app', '', dir: app);
    packageConfig(<String>[], relative: <String>['pkg']);
    expect(PackageCommands(root: app).libraries(), isEmpty);

    /// no `dart pub get`: package_config.json is the same
    package(
      'pkg',
      withKey,
      lib: <String, String>{'commands.dart': 'var commands = [];'},
    );
    expect(PackageCommands(root: app).libraries().keys, <String>['pkg']);
  });

  test('a value that is not a plain library path is skipped', () {
    package(
      'pkg',
      "dox:\n  commands: \"package:pkg/a'b.dart\"\n",
      lib: <String, String>{"a'b.dart": ''},
    );
    package(
      'up',
      'dox:\n  commands: package:up/../up/lib/commands.dart\n',
      lib: <String, String>{'commands.dart': ''},
    );
    package('app', '', dir: app);
    packageConfig(<String>['pkg', 'up']);

    StringBuffer out = StringBuffer();
    expect(capture(() => PackageCommands(root: app).libraries(), out), isEmpty);
    expect(out.toString(), contains('Skip pkg'));
    expect(out.toString(), contains('Skip up'));
  });

  test('finds package_config.json of a pub workspace above the app', () {
    package(
      'pkg',
      withKey,
      lib: <String, String>{'commands.dart': 'var commands = [];'},
    );
    package('app', 'workspace:\n  - member\n', dir: app);
    Directory member = Directory('${app.path}/member')..createSync();
    package('member', 'resolution: workspace\n', dir: member);
    packageConfig(<String>['pkg']);

    PackageCommands commands = PackageCommands(root: member);
    expect(commands.inApp, isTrue);
    expect(commands.libraries().keys, <String>['pkg']);
    expect(commands.runner.path, startsWith(member.path));
  });

  test('an app that is not a workspace member does not look up', () {
    package(
      'pkg',
      withKey,
      lib: <String, String>{'commands.dart': 'var commands = [];'},
    );
    package('app', 'workspace:\n  - member\n', dir: app);
    packageConfig(<String>['pkg']);

    /// no `resolution: workspace`
    Directory plain = Directory('${app.path}/plain')..createSync();
    package('plain', '', dir: plain);
    expect(PackageCommands(root: plain).inApp, isFalse);

    /// `resolution: workspace`, but not in the `workspace:` list
    Directory other = Directory('${app.path}/other')..createSync();
    package('other', 'resolution: workspace\n', dir: other);
    expect(PackageCommands(root: other).inApp, isFalse);
  });

  test('a commands library added after the key is found', () {
    package('app', 'dox:\n  commands: package:app/commands.dart\n', dir: app);
    packageConfig(<String>[]);

    StringBuffer out = StringBuffer();
    expect(capture(() => PackageCommands(root: app).libraries(), out), isEmpty);
    expect(out.toString(), contains('Skip app'));

    File('${app.path}/lib/commands.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('var commands = [];');
    expect(PackageCommands(root: app).libraries().keys, <String>['app']);
  });

  test('the not found message has a hint', () {
    String message = notFoundMessage('nope');
    expect(message, contains('Could not find a command named "nope"'));
    expect(message, contains('`dox: commands:`'));
  });
}
