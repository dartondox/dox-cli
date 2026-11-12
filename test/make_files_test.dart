import 'dart:async';
import 'dart:io';

import 'package:dox/src/command_registry.dart';
import 'package:dox/src/tools/make_files.dart';
import 'package:test/test.dart';

/// Commands write relative to the current directory,
/// so each test runs inside its own temp dir.
void main() {
  late Directory tempDir;
  late Directory originalCwd;

  setUp(() {
    originalCwd = Directory.current;
    tempDir = Directory.systemTemp.createTempSync('dox_make_test_');
    Directory.current = tempDir;
    File('pubspec.yaml').writeAsStringSync('name: my_app\n');
  });

  tearDown(() {
    exitCode = 0;
    Directory.current = originalCwd;
    tempDir.deleteSync(recursive: true);
  });

  String read(String path) => File(path).readAsStringSync();

  /// run [fn] and return what it printed
  String printed(void Function() fn) {
    StringBuffer out = StringBuffer();
    runZoned(
      fn,
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          out.writeln(line);
        },
      ),
    );
    return out.toString();
  }

  group('make:provider', () {
    test('writes a DoxProvider and hints build_runner', () {
      String out = printed(
        () => expect(createProvider(<String>['Cache']), isTrue),
      );
      String file = read('lib/providers/cache_provider.dart');
      expect(file, contains("import 'package:dox_core/dox_core.dart';"));
      expect(file, contains('class CacheProvider extends DoxProvider {'));
      expect(file, contains('Future<void> setup() async {'));
      expect(out, contains('dox build_runner:build'));
    });

    test('does not overwrite', () {
      createProvider(<String>['Cache']);
      printed(() => expect(createProvider(<String>['CacheProvider']), isFalse));
      expect(exitCode, 1);
    });
  });

  group('make:command', () {
    test('writes the command, the list and the pubspec key', () {
      expect(createCommand(<String>['SendReport']), isTrue);
      String file = read('lib/app/commands/send_report_command.dart');
      expect(file, contains("import 'package:dox_core/command.dart';"));
      expect(file, contains('class SendReportCommand extends Command {'));
      expect(file, contains("'app:send-report'"));
      String list = read('lib/app/commands/commands.dart');
      expect(list, contains('SendReportCommand(),'));
      expect(
        read('pubspec.yaml'),
        contains(
          'dox:\n  commands: package:my_app/app/commands/commands.dart\n',
        ),
      );
    });

    test('a second command joins the list, the pubspec key stays one', () {
      createCommand(<String>['SendReport']);
      createCommand(<String>['Cleanup']);
      String list = read('lib/app/commands/commands.dart');
      expect(list, contains("my_app/app/commands/cleanup_command.dart';"));
      expect(list, contains('SendReportCommand(),'));
      expect(list, contains('CleanupCommand(),'));
      expect('commands:'.allMatches(read('pubspec.yaml')).length, 1);
    });

    test('adds the key under an existing `dox:` map', () {
      File('pubspec.yaml').writeAsStringSync('name: my_app\ndox:\n  x: 1\n');
      createCommand(<String>['A']);
      expect(
        read('pubspec.yaml'),
        'name: my_app\ndox:\n'
        '  commands: package:my_app/app/commands/commands.dart\n  x: 1\n',
      );
    });

    test('another commands library in pubspec.yaml: error, no file', () {
      File('pubspec.yaml').writeAsStringSync(
        'name: my_app\ndox:\n  commands: package:my_app/other.dart\n',
      );
      printed(() => expect(createCommand(<String>['A']), isFalse));
      expect(exitCode, 1);
      expect(Directory('lib').existsSync(), isFalse);
    });

    test('a `commands:` key of another block does not matter', () {
      File('pubspec.yaml')
          .writeAsStringSync('name: my_app\nscripts:\n  commands: x\n');
      expect(createCommand(<String>['A']), isTrue);
    });

    test('a quoted value of the same library is accepted, no second key', () {
      File('pubspec.yaml').writeAsStringSync(
        'name: my_app\ndox:\n'
        '  commands: "package:my_app/app/commands/commands.dart"\n',
      );
      expect(createCommand(<String>['A']), isTrue);
      expect('commands:'.allMatches(read('pubspec.yaml')).length, 1);
    });

    test('`dox: # comment` gets the key under it, not a second dox:', () {
      File('pubspec.yaml')
          .writeAsStringSync('name: my_app\ndox: # mine\n  x: 1\n');
      expect(createCommand(<String>['A']), isTrue);
      expect('dox:'.allMatches(read('pubspec.yaml')).length, 1);
      expect(read('pubspec.yaml'), contains('commands: package:my_app'));
    });

    test('a list that is not in the made shape: error, nothing changes', () {
      File('lib/app/commands/commands.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          "import 'package:dox_core/command.dart';\n"
          'final commands = <Command>[A()];\n',
        );
      printed(() => expect(createCommand(<String>['Foo']), isFalse));
      expect(exitCode, 1);
      expect(File('lib/app/commands/foo_command.dart').existsSync(), isFalse);
      expect(read('pubspec.yaml'), 'name: my_app\n');
    });

    test('a multi line import stops it too', () {
      File('lib/app/commands/commands.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          "import 'package:dox_core/command.dart'\n    show Command;\n"
          'final List<Command> commands = <Command>[\n];\n',
        );
      printed(() => expect(createCommand(<String>['Foo']), isFalse));
      expect(exitCode, 1);
    });

    test('a command that is in the list already is not added again', () {
      createCommand(<String>['A']);
      File('lib/app/commands/a_command.dart').deleteSync();
      createCommand(<String>['A']);
      String list = read('lib/app/commands/commands.dart');
      expect('ACommand(),'.allMatches(list).length, 1);
      expect("a_command.dart';".allMatches(list).length, 1);
    });

    test('uses the indent of the children of `dox:`', () {
      File('pubspec.yaml').writeAsStringSync('name: my_app\ndox:\n    x: 1\n');
      expect(createCommand(<String>['A']), isTrue);
      expect(
        read('pubspec.yaml'),
        'name: my_app\ndox:\n'
        '    commands: package:my_app/app/commands/commands.dart\n    x: 1\n',
      );
    });

    test('`dox: ~` and `dox: null`: error, nothing written', () {
      for (String value in <String>['~', 'null']) {
        File('pubspec.yaml').writeAsStringSync('name: my_app\ndox: $value\n');
        printed(() => expect(createCommand(<String>['A']), isFalse));
        expect(exitCode, 1);
        exitCode = 0;
        expect(read('pubspec.yaml'), 'name: my_app\ndox: $value\n');
        expect(Directory('lib').existsSync(), isFalse);
      }
    });

    test('a write that fails removes the files this run made', () {
      Directory('lib/app/commands').createSync(recursive: true);
      File('lib/app/commands/commands.dart').writeAsStringSync(
        "import 'package:dox_core/command.dart';\n"
        'final List<Command> commands = <Command>[\n];\n',
      );
      Process.runSync('chmod', <String>[
        '444',
        'lib/app/commands/commands.dart',
      ]);
      String out = printed(() => expect(createCommand(<String>['A']), isFalse));
      Process.runSync('chmod', <String>[
        '644',
        'lib/app/commands/commands.dart',
      ]);
      expect(exitCode, 1);
      expect(out, contains('Nothing was made'));
      expect(File('lib/app/commands/a_command.dart').existsSync(), isFalse);
      expect(read('pubspec.yaml'), 'name: my_app\n');
    });

    test('does not overwrite', () {
      createCommand(<String>['A']);
      printed(() => expect(createCommand(<String>['A']), isFalse));
      expect(exitCode, 1);
    });
  });

  group('make:view', () {
    test('makes sub folders', () {
      expect(createView(<String>['emails/welcome']), isTrue);
      expect(
        File('resources/views/emails/welcome.dox.html').existsSync(),
        isTrue,
      );
    });

    test('does not overwrite', () {
      createView(<String>['home']);
      File('resources/views/home.dox.html').writeAsStringSync('mine');
      printed(() => expect(createView(<String>['home']), isFalse));
      expect(exitCode, 1);
      expect(read('resources/views/home.dox.html'), 'mine');
    });
  });

  group('make:mail', () {
    test('makes the mail and its view', () {
      expect(createMail(<String>['Welcome']), isTrue);
      String file = read('lib/app/mail/welcome_mail.dart');
      expect(file, contains("import 'package:dox_mailer/dox_mailer.dart';"));
      expect(file, contains('class WelcomeMail extends Mailable {'));
      expect(file, contains("String? get view => 'emails/welcome';"));
      expect(
        File('resources/views/emails/welcome.dox.html').existsSync(),
        isTrue,
      );
    });

    test('--no-view makes a plain text mail and no view', () {
      expect(createMail(<String>['WelcomeMail', '--no-view']), isTrue);
      String file = read('lib/app/mail/welcome_mail.dart');
      expect(file, contains('String? get text =>'));
      expect(file, isNot(contains('get view')));
      expect(Directory('resources').existsSync(), isFalse);
    });

    test('a write that fails removes the mail file too', () {
      Directory('resources/views').createSync(recursive: true);
      File('resources/views/emails').writeAsStringSync('a file');
      String out = printed(
        () => expect(createMail(<String>['Welcome']), isFalse),
      );
      expect(exitCode, 1);
      expect(out, contains('Nothing was made'));
      expect(File('lib/app/mail/welcome_mail.dart').existsSync(), isFalse);
    });

    test('an existing view stops it before any file is made', () {
      createView(<String>['emails/welcome']);
      printed(() => expect(createMail(<String>['Welcome']), isFalse));
      expect(exitCode, 1);
      expect(File('lib/app/mail/welcome_mail.dart').existsSync(), isFalse);
    });
  });

  group('make:test', () {
    test('uses DoxTestClient', () {
      expect(createTest(<String>['Ping']), isTrue);
      String file = read('test/ping_test.dart');
      expect(file, contains("import 'package:dox_core/testing.dart';"));
      expect(file, contains("import 'package:my_app/config/app.dart';"));
      expect(file, contains('DoxTestClient.start(appConfig)'));
    });

    test('--unit is a plain test', () {
      expect(createTest(<String>['--unit', 'Math']), isTrue);
      String file = read('test/math_test.dart');
      expect(file, isNot(contains('DoxTestClient')));
      expect(file, contains("import 'package:test/test.dart';"));
    });

    test('does not overwrite', () {
      createTest(<String>['Ping']);
      printed(() => expect(createTest(<String>['Ping']), isFalse));
      expect(exitCode, 1);
    });
  });

  test('a quoted package name is read without quotes', () {
    File('pubspec.yaml').writeAsStringSync('name: "my_app"\n');
    createTest(<String>['Ping']);
    expect(
      read('test/ping_test.dart'),
      contains("package:my_app/config/app.dart"),
    );
  });

  group('bad input', () {
    Map<String, bool Function(List<String>)> makers =
        <String, bool Function(List<String>)>{
          'provider': createProvider,
          'command': createCommand,
          'mail': createMail,
          'view': createView,
          'test': createTest,
        };
    for (MapEntry<String, bool Function(List<String>)> m in makers.entries) {
      test('${m.key}: bad name, extra word, unknown flag', () {
        for (List<String> args in <List<String>>[
          <String>['../escape'],
          <String>['/tmp/x'],
          <String>['1bad'],
          <String>['A', 'B'],
          <String>['A', '--nope'],
          <String>['A', '-x'],
        ]) {
          printed(() => expect(m.value(args), isFalse, reason: '$args'));
          expect(exitCode, 1, reason: '$args');
          exitCode = 0;
        }
        expect(Directory('lib').existsSync(), isFalse);
        expect(Directory('test').existsSync(), isFalse);
        expect(Directory('resources').existsSync(), isFalse);
      });
    }

    test('only mail takes --no-view, only test takes --unit', () {
      printed(() => expect(createView(<String>['a', '--no-view']), isFalse));
      printed(() => expect(createMail(<String>['a', '--unit']), isFalse));
    });
  });

  test('the commands are in the registry with help', () {
    for (String name in <String>[
      'make:provider',
      'make:command',
      'make:mail',
      'make:view',
      'make:test',
    ]) {
      expect(CommandRegistry.findCommand(name), isNotNull, reason: name);
    }
  });
}
