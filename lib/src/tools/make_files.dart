import 'dart:io';

import '../utils/args.dart';
import '../utils/utils.dart';

/// Write [content] to [path] (from the app folder). It never overwrites:
/// when the file is there, it prints a message and sets exit code 1.
bool _write(String path, String content) {
  File file = File('${Directory.current.path}/$path');
  if (file.existsSync()) {
    print('\x1B[31m$path already exists\x1B[0m');
    exitCode = 1;
    return false;
  }
  file.createSync(recursive: true);
  file.writeAsStringSync(content);
  print('\x1B[32m$path created successfully.\x1B[0m');
  return true;
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

  /// check the pubspec before we write anything
  File pubspec = File('${Directory.current.path}/pubspec.yaml');
  String pubspecText = pubspec.readAsStringSync();
  RegExp keyPattern = RegExp(r'^dox:[ \t]*$', multiLine: true);
  RegExp valuePattern = RegExp(r'^[ \t]+commands:[ \t]*(\S+)', multiLine: true);
  RegExpMatch? existing = valuePattern.firstMatch(pubspecText);
  if (existing != null && existing.group(1) != _commandsLibrary(package)) {
    print(
      '\x1B[31mpubspec.yaml has `dox: commands: ${existing.group(1)}`. '
      'Add the command to that list by hand, or point it to '
      '${_commandsLibrary(package)}.\x1B[0m',
    );
    exitCode = 1;
    return false;
  }

  bool done = _write('lib/app/commands/${name}_command.dart', '''
import 'package:dox_core/command.dart';

/// Run it with `dox app:${name.replaceAll('_', '-')}`.
class $className extends Command {
  @override
  String get name => 'app:${name.replaceAll('_', '-')}';

  @override
  String get description => 'Describe what this command does';

  @override
  Future<void> run(List<String> args) async {
    /// write your logic here
  }
}
''');
  if (!done) return false;

  String import =
      "import 'package:$package/app/commands/${name}_command.dart';";
  File list = File('${Directory.current.path}/lib/app/commands/commands.dart');
  if (!list.existsSync()) {
    list.writeAsStringSync('''
import 'package:dox_core/command.dart';
$import

/// The `dox: commands:` key in pubspec.yaml points to this list.
final List<Command> commands = <Command>[
  $className(),
];
''');
  } else {
    String text = list.readAsStringSync();
    int close = text.lastIndexOf('];');
    if (close == -1) {
      print(
        'Add $className() to the commands list of '
        'lib/app/commands/commands.dart by hand.',
      );
    } else {
      /// the entry goes before `];`, the import after the last import
      text =
          '${text.substring(0, close)}  $className(),\n${text.substring(close)}';
      int lastImport = text.lastIndexOf(
        RegExp(r'^import .*$', multiLine: true),
      );
      int end = lastImport == -1 ? 0 : text.indexOf('\n', lastImport) + 1;
      text = '${text.substring(0, end)}$import\n${text.substring(end)}';
      list.writeAsStringSync(text);
    }
  }

  if (existing == null) {
    String line = '  commands: ${_commandsLibrary(package)}';
    RegExpMatch? key = keyPattern.firstMatch(pubspecText);
    if (key != null) {
      pubspecText =
          '${pubspecText.substring(0, key.end)}\n$line${pubspecText.substring(key.end)}';
    } else {
      if (!pubspecText.endsWith('\n')) pubspecText += '\n';
      pubspecText += '\ndox:\n$line\n';
    }
    pubspec.writeAsStringSync(pubspecText);
    print('Added `dox: commands:` to pubspec.yaml.');
  }
  print('Run `dart pub get`, then `dox app:${name.replaceAll('_', '-')}`.');
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
  bool done = _write(mailPath, '''
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
''');
  if (done && withView) _write(viewPath, _viewSample);
  if (done) {
    File pubspec = File('${Directory.current.path}/pubspec.yaml');
    String text = pubspec.existsSync() ? pubspec.readAsStringSync() : '';
    for (String package in <String>['dox_mailer', if (withView) 'dox_view']) {
      if (!RegExp('^\\s+$package:', multiLine: true).hasMatch(text)) {
        print('Add $package to pubspec.yaml: `dart pub add $package`');
      }
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
