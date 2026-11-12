import 'dart:io';

import 'package:yaml/yaml.dart';

import '../utils/args.dart';
import '../utils/utils.dart';

/// Write the new files [created] (path => text) and change the files
/// [changed] (path => new text). Paths are from the app folder.
///
/// It is all or nothing. When a new file is there already, it prints a
/// message, sets exit code 1 and writes nothing. When a write fails, it
/// deletes the files it made, puts back the files it changed, prints one
/// message (no stack trace) and sets exit code 1.
bool _writeAll(Map<String, String> created, [Map<String, String>? changed]) {
  String root = Directory.current.path;
  for (String path in created.keys) {
    if (File('$root/$path').existsSync()) {
      print('\x1B[31m$path already exists\x1B[0m');
      exitCode = 1;
      return false;
    }
  }
  List<File> made = <File>[];
  Map<File, String> old = <File, String>{};
  try {
    for (MapEntry<String, String> e in created.entries) {
      File file = File('$root/${e.key}');
      file.createSync(recursive: true);
      made.add(file);
      file.writeAsStringSync(e.value);
    }
    for (MapEntry<String, String> e
        in (changed ?? <String, String>{}).entries) {
      File file = File('$root/${e.key}');
      old[file] = file.readAsStringSync();
      file.writeAsStringSync(e.value);
    }
  } on FileSystemException catch (error) {
    for (File file in made) {
      try {
        file.deleteSync();
      } on FileSystemException {
        /// nothing more to do
      }
    }
    old.forEach((File file, String text) {
      try {
        file.writeAsStringSync(text);
      } on FileSystemException {
        /// nothing more to do
      }
    });
    print(
      '\x1B[31mCould not write ${error.path ?? 'a file'}: '
      '${error.osError?.message ?? error.message}. '
      'Nothing was made.\x1B[0m',
    );
    exitCode = 1;
    return false;
  }
  for (String path in created.keys) {
    print('\x1B[32m$path created successfully.\x1B[0m');
  }
  return true;
}

bool _write(String path, String content) {
  return _writeAll(<String, String>{path: content});
}

/// `dox make:provider Cache` makes `lib/providers/cache_provider.dart`.
bool createProvider(List<String> args) {
  ParsedArgs? parsed = parseArgs('make:provider', args);
  if (parsed == null) return false;
  String? name = generatorName(parsed.names.first, 'provider');
  if (name == null) return false;
  String className = '${snakeToPascal(name)}Provider';
  bool done = _write('lib/providers/${name}_provider.dart', '''
import 'package:dox_core/dox_core.dart';

/// Dox finds every DoxProvider class and runs it when the app starts.
/// Run `dox build_runner:build` so Dox finds this one.
class $className extends DoxProvider {
  @override
  Future<void> setup() async {
    /// set up your service here
  }

  @override
  Future<void> shutdown() async {
    /// close your connections here (optional)
  }
}
''');
  if (done) {
    print('Run `dox build_runner:build` to add it to the container.');
  }
  return done;
}

/// The library that holds the `commands` list of the app.
String _commandsLibrary(String package) {
  return 'package:$package/app/commands/commands.dart';
}

/// `dox make:command SendReport` makes
/// `lib/app/commands/send_report_command.dart`, adds it to the `commands`
/// list of `lib/app/commands/commands.dart`, and sets `dox: commands:` in
/// pubspec.yaml when it is missing.
bool createCommand(List<String> args) {
  ParsedArgs? parsed = parseArgs('make:command', args);
  if (parsed == null) return false;
  String? name = generatorName(parsed.names.first, 'command');
  if (name == null) return false;
  String? package = appPackageName();
  if (package == null) {
    print('pubspec.yaml has no name. Run this in the app folder.');
    exitCode = 1;
    return false;
  }
  String className = '${snakeToPascal(name)}Command';

  /// Check everything before we write anything. Fail with exit code 1
  /// and an "add it by hand" message when a file is not what we expect.
  String cmdName = name.replaceAll('_', '-');
  String library = _commandsLibrary(package);
  File pubspec = File('${Directory.current.path}/pubspec.yaml');
  String pubspecText = pubspec.readAsStringSync();
  dynamic dox;
  try {
    dynamic doc = loadYaml(pubspecText);
    dox = doc is Map ? doc['dox'] : null;
  } catch (error) {
    print('\x1B[31mpubspec.yaml is not valid YAML.\x1B[0m');
    exitCode = 1;
    return false;
  }
  dynamic existing = dox is Map ? dox['commands'] : null;
  if (dox != null && dox is! Map) {
    print('\x1B[31m`dox:` in pubspec.yaml must be a map.\x1B[0m');
    exitCode = 1;
    return false;
  }
  if (existing != null && existing != library) {
    print(
      '\x1B[31mpubspec.yaml has `dox: commands: $existing`. '
      'Add the command to that list by hand, or point it to '
      '$library.\x1B[0m',
    );
    exitCode = 1;
    return false;
  }
  RegExpMatch? key = RegExp(
    r'^dox:[ \t]*(#.*)?$',
    multiLine: true,
  ).firstMatch(pubspecText);
  bool hasDoxLine = RegExp(
    r'^\S*dox\S*:',
    multiLine: true,
  ).hasMatch(pubspecText);
  if (existing == null && hasDoxLine && key == null) {
    print(
      '\x1B[31mCould not edit `dox:` in pubspec.yaml. Add '
      '`commands: $library` under it by hand.\x1B[0m',
    );
    exitCode = 1;
    return false;
  }

  /// the list file must have the shape this command writes
  File list = File('${Directory.current.path}/lib/app/commands/commands.dart');
  String? listText = list.existsSync() ? list.readAsStringSync() : null;
  RegExpMatch? listMatch;
  if (listText != null) {
    listMatch = RegExp(
      r'^final List<Command> commands = <Command>\[\n((?:  \w+\(\),\n)*)\];',
      multiLine: true,
    ).firstMatch(listText);
    bool oneLineImports = RegExp(
      r'^import .*[^;\n]$',
      multiLine: true,
    ).hasMatch(listText);
    if (listMatch == null || oneLineImports) {
      print(
        '\x1B[31mlib/app/commands/commands.dart is not in the shape this '
        'command edits. Add $className() and its import by hand.\x1B[0m',
      );
      exitCode = 1;
      return false;
    }
  }

  String import =
      "import 'package:$package/app/commands/${name}_command.dart';";
  String? newList;
  if (listText == null) {
    newList =
        '''
import 'package:dox_core/command.dart';
$import

/// The `dox: commands:` key in pubspec.yaml points to this list.
final List<Command> commands = <Command>[
  $className(),
];
''';
  } else if (!listMatch!.group(1)!.contains('  $className(),\n')) {
    /// the entry goes at the end of the list, the import after the last one
    String text =
        '${listText.substring(0, listMatch.end - 2)}  $className(),\n'
        '${listText.substring(listMatch.end - 2)}';
    int lastImport = text.lastIndexOf(RegExp(r'^import .*;$', multiLine: true));
    int end = lastImport == -1 ? 0 : text.indexOf('\n', lastImport) + 1;
    newList = '${text.substring(0, end)}$import\n${text.substring(end)}';
  }

  String? newPubspec;
  if (existing == null) {
    String line = 'commands: $library';
    if (key != null) {
      /// use the indent of the first line under `dox:`, else 2 spaces
      String indent = '  ';
      RegExpMatch? child = RegExp(r'\n([ \t]*)(?!#)\S')
          .firstMatch(pubspecText.substring(key.end));
      if (child != null && child.group(1)!.isNotEmpty) {
        indent = child.group(1)!;
      }
      newPubspec =
          '${pubspecText.substring(0, key.end)}\n$indent$line${pubspecText.substring(key.end)}';
    } else {
      newPubspec =
          '$pubspecText${pubspecText.endsWith('\n') ? '' : '\n'}\ndox:\n  $line\n';
    }

    /// the result must be valid YAML with the right value
    bool ok = false;
    try {
      dynamic doc = loadYaml(newPubspec);
      ok = doc is Map && doc['dox'] is Map && doc['dox']['commands'] == library;
    } catch (error) {
      ok = false;
    }
    if (!ok) {
      print(
        '\x1B[31mCould not edit `dox:` in pubspec.yaml. Add '
        '`commands: $library` under it by hand.\x1B[0m',
      );
      exitCode = 1;
      return false;
    }
  }

  String commandPath = 'lib/app/commands/${name}_command.dart';
  String listPath = 'lib/app/commands/commands.dart';
  bool done = _writeAll(
    <String, String>{
      commandPath:
          '''
import 'package:dox_core/command.dart';

/// Run it with `dox app:$cmdName`.
class $className extends Command {
  @override
  String get name => 'app:$cmdName';

  @override
  String get description => 'Describe what this command does';

  @override
  Future<void> run(List<String> args) async {
    /// write your logic here
  }
}
''',
      if (listText == null) listPath: newList!,
    },
    <String, String>{
      if (listText != null && newList != null) listPath: newList,
      'pubspec.yaml': ?newPubspec,
    },
  );
  if (!done) return false;
  if (newPubspec != null) print('Added `dox: commands:` to pubspec.yaml.');
  print('Run `dart pub get`, then `dox app:$cmdName`.');
  return true;
}

/// the `.dox.html` file of a view [name] like `emails/welcome`
String _viewPath(List<String> parts) {
  return 'resources/views/${parts.join('/')}.dox.html';
}

/// each part of [name] as a snake_case name, or null (with an error)
List<String>? _viewParts(String name) {
  List<String> parts = <String>[];
  for (String part in name.split('/')) {
    String? clean = generatorName(part);
    if (clean == null) return null;
    parts.add(clean);
  }
  return parts;
}

const String _viewSample = '''
<h1>Hello, {{ name }}</h1>
''';

/// `dox make:view emails/welcome` makes
/// `resources/views/emails/welcome.dox.html`.
bool createView(List<String> args) {
  ParsedArgs? parsed = parseArgs('make:view', args);
  if (parsed == null) return false;
  List<String>? parts = _viewParts(parsed.names.first);
  if (parts == null) return false;
  return _write(_viewPath(parts), _viewSample);
}

/// `dox make:mail Welcome` makes `lib/app/mail/welcome_mail.dart` and the
/// view `resources/views/emails/welcome.dox.html`. `--no-view` makes a mail
/// with a plain text body and no view.
bool createMail(List<String> args) {
  ParsedArgs? parsed = parseArgs(
    'make:mail',
    args,
    flags: const <String>{'no-view'},
  );
  if (parsed == null) return false;
  String? name = generatorName(parsed.names.first, 'mail');
  if (name == null) return false;
  String className = '${snakeToPascal(name)}Mail';
  bool withView = !parsed.flags.contains('no-view');
  String viewName = 'emails/$name';
  String mailPath = 'lib/app/mail/${name}_mail.dart';

  /// make both files or none
  String viewPath = _viewPath(<String>['emails', name]);
  for (String path in <String>[mailPath, if (withView) viewPath]) {
    if (File('${Directory.current.path}/$path').existsSync()) {
      print('\x1B[31m$path already exists\x1B[0m');
      exitCode = 1;
      return false;
    }
  }
  String body = withView
      ? '''
  @override
  String? get view => '$viewName';

  @override
  Map<String, Object?> get data => <String, Object?>{'name': 'there'};
'''
      : '''
  @override
  String? get text => 'Write your message here.';
''';
  bool done = _writeAll(<String, String>{
    mailPath:
        '''
import 'package:dox_mailer/dox_mailer.dart';

/// Send: await $className(Address('ann@example.com')).send();
/// Queue: await $className(Address('ann@example.com')).queue();
class $className extends Mailable {
  $className(this.recipient);

  final Address recipient;

  @override
  List<Address> get to => <Address>[recipient];

  @override
  String get subject => '${snakeToPascal(name)}';

$body}
''',
    if (withView) viewPath: _viewSample,
  });
  if (done) {
    File pubspec = File('${Directory.current.path}/pubspec.yaml');
    String text = pubspec.existsSync() ? pubspec.readAsStringSync() : '';
    for (String package in <String>['dox_mailer', if (withView) 'dox_view']) {
      if (!RegExp('^\\s+$package:', multiLine: true).hasMatch(text)) {
        print('Add $package to pubspec.yaml: `dart pub add $package`');
      }
    }
    if (withView) {
      print(
        'The default view settings work (resources/views). Add a '
        'ViewProvider with a ViewConfig only to change them.',
      );
    }
  }
  return done;
}

/// `dox make:test Ping` makes `test/ping_test.dart`. It starts the app with
/// `DoxTestClient`. `--unit` makes a plain `package:test` test.
bool createTest(List<String> args) {
  ParsedArgs? parsed = parseArgs(
    'make:test',
    args,
    flags: const <String>{'unit'},
  );
  if (parsed == null) return false;
  String? name = generatorName(parsed.names.first, 'test');
  if (name == null) return false;
  String group = snakeToPascal(name);
  if (parsed.flags.contains('unit')) {
    return _write('test/${name}_test.dart', '''
import 'package:test/test.dart';

void main() {
  test('$group', () {
    expect(1 + 1, 2);
  });
}
''');
  }
  String? package = appPackageName();
  if (package == null) {
    print('pubspec.yaml has no name. Run this in the app folder.');
    exitCode = 1;
    return false;
  }
  return _write('test/${name}_test.dart', '''
import 'package:dox_core/testing.dart';
import 'package:$package/config/app.dart';
import 'package:test/test.dart';

void main() {
  late DoxTestClient client;

  setUpAll(() async {
    client = await DoxTestClient.start(appConfig);
  });

  tearDownAll(() async {
    await client.close();
  });

  /// change the path and the checks to match your route
  test('$group', () async {
    TestResponse res = await client.get('/ping');
    res.expectStatus(200);
  });
}
''');
}
