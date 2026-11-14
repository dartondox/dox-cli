import 'dart:convert';
import 'dart:io';

import 'package:dox/src/tools/env_tools.dart';
import 'package:test/test.dart';

void main() {
  group('env:generate |', () {
    test('infers types, keeps comments, no secret defaults', () {
      String out = EnvScaffold().build('''
APP_NAME=dox
APP_KEY="secret"

# Server port
APP_PORT=3000
APP_DEBUG=true
# no value means optional
AWS_BUCKET=
S3__X=1
APP_TOTAL_ISOLATE=4 # one per core
APP_MOTTO="a # b"
''');
      expect(out, contains('String get appName;'));
      expect(out, contains('String get appKey;'));
      expect(out, isNot(contains('secret')));
      expect(out, contains('  /// Server port\n  int get appPort => 3000;'));
      expect(out, contains('bool get appDebug => true;'));
      expect(
        out,
        contains('  /// no value means optional\n  String? get awsBucket;'),
      );
      expect(out, contains("@EnvKey('S3__X')\n  int get s3X => 1;"));
      expect(out, contains('int get appTotalIsolate => 4;'));
      expect(out, contains('String get appMotto;'));
      expect(out, contains(r'return _$AppEnv.load(reader);'));
      expect(out, contains('final AppEnv env = AppEnv.load();'));
    });

    test('strips `export` from the key', () {
      String out = EnvScaffold().build('export APP_NAME=dox\n');
      expect(out, contains('  String get appName;'));
      expect(out, isNot(contains('export')));
    });

    test('a number with a leading zero is a String', () {
      String out = EnvScaffold().build('ZIP=02134\nZERO=0\nNEG=-012\n');
      expect(out, contains('String get zip;'));
      expect(out, isNot(contains('02134')));
      expect(out, contains('int get zero => 0;'));
      expect(out, contains('String get neg;'));
    });

    test('a secret key is a String with no default, whatever the value', () {
      String out = EnvScaffold().build('''
DB_PASSWORD=123456
JWT_SECRET=true
API_KEY=42
AUTH_TOKEN=false
APP_PORT=3000
''');
      expect(out, contains('String get dbPassword;'));
      expect(out, contains('String get jwtSecret;'));
      expect(out, contains('String get apiKey;'));
      expect(out, contains('String get authToken;'));
      expect(out, isNot(contains('123456')));
      expect(out, isNot(contains('=> 42')));
      expect(out, contains('int get appPort => 3000;'));
    });

    test('a reserved word or a leading digit gets a safe name', () {
      String out = EnvScaffold().build('CLASS=x\nIF=1\n1ST=a\nMY-KEY=b\n');
      expect(out, contains("@EnvKey('CLASS')\n  String get envClass;"));
      expect(out, contains("@EnvKey('IF')\n  int get envIf => 1;"));
      expect(out, contains("@EnvKey('1ST')\n  String get env1st;"));
      expect(out, contains("@EnvKey('MY-KEY')\n  String get mykey;"));
      expect(out, isNot(contains('get class')));
    });

    test('each getter reads its key under the old and the new name rule', () {
      List<String> keys = <String>[
        'APP_NAME',
        'DB_URL',
        'S3_BUCKET',
        'A_B_C',
        'X_Y',
        'AWS_S3_KEY_ID',
        'S3__X',
        '_LEAD',
        'CLASS',
        'V2_API',
      ];
      String out = EnvScaffold().build('${keys.join('=x\n')}=x');
      RegExp getter = RegExp(r"(?:@EnvKey\('([^']+)'\)\n  )?String get (\w+);");
      List<String> read = <String>[];
      for (RegExpMatch m in getter.allMatches(out)) {
        String name = m[2]!;
        if (m[1] != null) {
          read.add(m[1]!); // @EnvKey wins under both rules
          continue;
        }
        expect(upperSnake(name), acronymUpperSnake(name), reason: name);
        read.add(upperSnake(name));
      }
      expect(read, keys);
    });

    test('a key that holds a secret word anywhere has no default', () {
      List<String> keys = <String>[
        'APIKEY',
        'SECRETKEY',
        'APP_KEYS',
        'TOKENS',
        'PASSCODE',
        'PIN',
        'OTP',
        'AUTH',
        'JWT',
        'DSN',
        'PASSPHRASE',
      ];
      String out = EnvScaffold().build('${keys.join('=1234\n')}=1234');
      expect(out, isNot(contains('1234')));
      expect(out, isNot(contains('int get')));
    });

    test('a number over 64 bits is a String', () {
      String out = EnvScaffold().build(
        'BIG=99999999999999999999\nMAX=9223372036854775807\n',
      );
      expect(out, contains('String get big;'));
      expect(out, isNot(contains('99999999999999999999')));
      expect(out, contains('int get max => 9223372036854775807;'));
    });

    test('two keys with the same getter name get unique names', () {
      String out = EnvScaffold().build('A_B=x\nA__B=y\nCLASS=z\nENV_CLASS=w\n');
      expect(out, contains('  String get aB;'));
      expect(out, contains("@EnvKey('A__B')\n  String get aB2;"));
      expect(out, contains("@EnvKey('CLASS')\n  String get envClass;"));
      expect(out, contains("@EnvKey('ENV_CLASS')\n  String get envClass2;"));
    });

    test('a key that clashes with a member of the class is renamed', () {
      String out = EnvScaffold().build(
        'LOAD=x\nHASH_CODE=x\nTO_STRING=x\nR=x\nINT=x\n_STRING=x\n',
      );
      expect(out, contains("@EnvKey('LOAD')\n  String get envLoad;"));
      expect(out, contains("@EnvKey('HASH_CODE')\n  String get envHashCode;"));
      expect(out, contains("@EnvKey('TO_STRING')\n  String get envToString;"));
      expect(out, contains("@EnvKey('R')\n  String get envR;"));
      expect(out, contains("@EnvKey('INT')\n  String get envInt;"));
      expect(out, contains("@EnvKey('_STRING')\n  String get string;"));
    });

    test('more secret words give no default', () {
      List<String> keys = <String>[
        'ADMIN_PW',
        'DB_PWD',
        'VERIFY_CODE',
        'ADMIN_CODE',
        'CARD_CVV',
        'CARD_CVC',
        'HMAC',
        'RANDOM_SEED',
        'NONCE',
        'SSN',
        'PW_HASH',
        'SIGNING',
        'LICENSE',
      ];
      String out = EnvScaffold().build('${keys.join('=1234\n')}=1234');
      expect(out, isNot(contains('1234')));
      expect(out, isNot(contains('int get')));
    });

    test('@EnvKey is a valid Dart string for any key', () async {
      List<String> keys = <String>[r'A$B', "A'B", r'A\B', r'$X', 'A"B'];
      String out = EnvScaffold().build('${keys.join('=x\n')}=x');
      List<String> literals = <String>[];
      for (RegExpMatch m in RegExp(r'@EnvKey\((.*)\)').allMatches(out)) {
        literals.add(m[1]!);
      }
      expect(literals, hasLength(keys.length));
      // run the literals as Dart code: they must parse and give the keys
      Directory temp = Directory.systemTemp.createTempSync('dox_env_lit_');
      try {
        File script = File('${temp.path}/main.dart')
          ..writeAsStringSync(
            "import 'dart:convert';\n"
            'void main() {\n'
            '  print(jsonEncode(<String>[${literals.join(', ')}]));\n'
            '}\n',
          );
        ProcessResult r = await Process.run(
          Platform.resolvedExecutable,
          <String>[script.path],
        );
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(jsonDecode('${r.stdout}'), keys);
      } finally {
        temp.deleteSync(recursive: true);
      }
    });

    test('writes lib/config/env.dart once', () {
      Directory original = Directory.current;
      Directory temp = Directory.systemTemp.createTempSync('dox_env_test_');
      Directory.current = temp;
      try {
        expect(envGenerate(), isFalse); // no .env.example
        File('.env.example').writeAsStringSync('APP_NAME=dox\n');
        expect(envGenerate(), isTrue);
        expect(
          File('lib/config/env.dart').readAsStringSync(),
          contains('String get appName;'),
        );
        expect(envGenerate(), isFalse); // already there
        exitCode = 0;
      } finally {
        Directory.current = original;
        temp.deleteSync(recursive: true);
      }
    });
  });

  group('env:check |', () {
    const String dotEnv = 'APP_KEY=k\nPORT=3000\nAPP_PORT=\${PORT}\n';

    test('default mode: envExpand off, with a note for \${', () async {
      ProcessResult r = await envCheckIn(dotEnv);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      String out = '${r.stdout}';
      expect(out, contains('Checked with envExpand off.'));
      expect(out, contains('APP_PORT must be an int'));
      expect(out, contains('run `dox env:check --expand`'));
      expect(out, isNot(contains('The env is valid.')));
    });

    test('--expand: envExpand on, no note', () async {
      ProcessResult r = await envCheckIn(dotEnv, args: <String>['--expand']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      String out = '${r.stdout}';
      expect(out, contains('Checked with envExpand on.'));
      expect(out, contains('The env is valid.'));
      expect(out, isNot(contains('--expand`')));
    });

    test('no \${ in .env: no note, valid', () async {
      ProcessResult r = await envCheckIn('APP_KEY=k\nAPP_PORT=3000\n');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      String out = '${r.stdout}';
      expect(out, contains('Checked with envExpand off.'));
      expect(out, contains('The env is valid.'));
      expect(out, isNot(contains('Note:')));
    });

    // the note shows only when a value really changes with envExpand,
    // the same way dox_core reads it
    Map<String, bool> noteCases = <String, bool>{
      'A=\${HOST}': true,
      'A="x \${HOST}"': true,
      r'A="a\nb"': true, // an escape in "..." changes too
      'A=x # see \${HOST}': false, // a comment after the value
      "A='\${HOST}'": false, // single quotes stay raw
      'A=`\${HOST}`': false, // backticks stay raw
      'A=\${NOT_SET_ANYWHERE_X}': false, // an unknown name stays as it is
      '# A=\${HOST}': false, // a comment line
    };
    for (MapEntry<String, bool> c in noteCases.entries) {
      test('note for ${c.key}: ${c.value}', () async {
        ProcessResult r = await envCheckIn(
          'HOST=h\nAPP_KEY=k\nAPP_PORT=3000\n${c.key}\n',
        );
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect('${r.stdout}', contains('The env is valid.'));
        expect(
          '${r.stdout}',
          c.value ? contains('Note:') : isNot(contains('Note:')),
        );
      });
    }

    test('note for .env.testing only when APP_ENV=testing', () async {
      for (String appEnv in <String>['', 'testing']) {
        ProcessResult r = await envCheckIn(
          'HOST=h\nAPP_KEY=k\nAPP_PORT=3000\n',
          testing: 'B=\${HOST}\n',
          appEnv: appEnv,
        );
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(
          '${r.stdout}',
          appEnv == 'testing' ? contains('Note:') : isNot(contains('Note:')),
          reason: 'APP_ENV=$appEnv',
        );
      }
    });

    test('no env.g.dart: one plain line, exit 1', () async {
      ProcessResult r = await envCheckIn(
        'APP_KEY=k\nAPP_PORT=3000\n',
        generated: false,
      );
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect(
        '${r.stdout}',
        contains('Run `dart run build_runner build` first.'),
      );
      expect('${r.stdout}${r.stderr}', isNot(contains('Error:')));
    });

    test('--expand with a missing key lists only the real errors', () async {
      ProcessResult r = await envCheckIn(
        'PORT=3000\nAPP_PORT=\${PORT}\n',
        args: <String>['--expand'],
      );
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('APP_KEY is missing'));
      expect('${r.stdout}', isNot(contains('APP_PORT')));
    });

    test('an unknown option stops with exit code 1', () async {
      ProcessResult r = await envCheckIn(dotEnv, args: <String>['--foo']);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('Unknown option --foo'));
    });
  });
}

/// A small stand-in for dox_core. `Env.parse` and its helpers are copied
/// from dox_core 3.2.0 (lib/env/env.dart), so `.env` is read the same way.
/// `dox env:check` runs against it.
const String fakeCore = r'''
import 'dart:io';

class CoreFlags {
  final bool envExpand;
  const CoreFlags({this.envExpand = false});
}

class EnvException implements Exception {
  final List<String> errors;
  EnvException(this.errors);
  @override
  String toString() => 'EnvException: ${errors.join(', ')}';
}

class Env {
  static final Env _one = Env._();
  factory Env() => _one;
  Env._();
  static CoreFlags flags = const CoreFlags();
  Map<String, String> env = <String, String>{};
  bool expanded = false;

  static bool get isTesting => Platform.environment['APP_ENV'] == 'testing';

  void load() {
    if (env.isNotEmpty) return;
    expanded = flags.envExpand;
    env = parse(File('.env').readAsStringSync(), expand: flags.envExpand);
  }

  /// Reads the text of a `.env` file.
  /// - `KEY=value`, one per line. Lines that start with `#` are comments.
  ///   `export KEY=value` is read like `KEY=value`.
  /// - `KEY=value # note`: a `#` after a space starts a comment.
  /// - `KEY="a # b"`: quotes (`"`, `'` or `` ` ``) keep the value as it is,
  ///   also a `#`. The quotes are removed.
  /// - `KEY=abc#def` stays `abc#def` (no space before the `#`).
  ///
  /// With [expand] (`CoreFlags.envExpand`):
  /// - `${OTHER}` is the value of `OTHER`, in an unquoted or a `"` value.
  ///   A real environment variable wins, then a key above this line (or
  ///   in [known]). An unknown name stays as it is: `${OTHER}`.
  /// - In a `"` value, `\n`, `\t`, `\"`, `\\` and `\$` become a new line,
  ///   a tab, `"`, `\` and `$`. A `'` or `` ` `` value stays raw.
  static Map<String, String> parse(
    String contents, {
    Map<String, String> known = const <String, String>{},
    bool expand = false,
  }) {
    Map<String, String> data = <String, String>{};
    String? lookup(String name) =>
        Platform.environment[name] ?? data[name] ?? known[name];
    for (String line in contents.split('\n')) {
      String text = line.trim();
      if (text.isEmpty || text.startsWith('#')) continue;
      text = text.replaceFirst(_export, '');
      int equal = text.indexOf('=');
      if (equal < 1) continue;
      data[text.substring(0, equal).trim()] = _value(
        text.substring(equal + 1),
        expand ? lookup : null,
      );
    }
    return data;
  }

  static final RegExp _comment = RegExp(r'(^|\s)#');

  static final RegExp _export = RegExp(r'^export\s+');

  static final RegExp _variable = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');

  /// [lookup] is null when `envExpand` is off: the value is read as it
  /// is written.
  static String _value(String raw, String? Function(String)? lookup) {
    String value = raw.trim();
    if (lookup != null && value.startsWith('"')) {
      String? text = _doubleQuoted(value, lookup);
      if (text != null) return text;
    } else if (value.isNotEmpty && '"\'`'.contains(value[0])) {
      int end = value.indexOf(value[0], 1);
      if (end > 0) return value.substring(1, end);
    }
    Match? comment = _comment.firstMatch(value);
    if (comment != null) value = value.substring(0, comment.start);
    value = value.trim();
    if (lookup == null) return value;
    return value.replaceAllMapped(
      _variable,
      (Match match) => lookup(match[1]!) ?? match[0]!,
    );
  }

  /// the text inside the `"` quotes at the start of [value], with escapes
  /// and `${NAME}` done. null when the closing quote is missing.
  static String? _doubleQuoted(String value, String? Function(String) lookup) {
    StringBuffer out = StringBuffer();
    for (int i = 1; i < value.length; i++) {
      String char = value[i];
      if (char == '"') return out.toString();
      if (char == r'\' && i + 1 < value.length) {
        String next = value[++i];
        out.write(switch (next) {
          'n' => '\n',
          't' => '\t',
          '"' || r'\' || r'$' => next,
          _ => '\\$next',
        });
        continue;
      }
      Match? match = char == r'$' ? _variable.matchAsPrefix(value, i) : null;
      if (match != null) {
        out.write(lookup(match[1]!) ?? match[0]);
        i = match.end - 1;
        continue;
      }
      out.write(char);
    }
    return null;
  }
}
''';

/// the app's `lib/config/env.dart`: APP_KEY is needed, APP_PORT is an int
const String fakeAppEnv = r'''
import 'package:dox_core/dox_core.dart';

part 'env.g.dart';

class AppEnv {
  final int appPort;
  AppEnv(this.appPort);

  static AppEnv load() {
    Env().load();
    List<String> errors = <String>[];
    if ((Env().env['APP_KEY'] ?? '').isEmpty) errors.add('APP_KEY is missing');
    String raw = Env().env['APP_PORT'] ?? '';
    int? port = int.tryParse(raw);
    if (port == null) errors.add('APP_PORT must be an int: $raw');
    if (errors.isNotEmpty) throw EnvException(errors);
    return AppEnv(port!);
  }
}

final AppEnv env = AppEnv.load();
''';

/// `dox env:check` in a temp app, from the source of this CLI
Future<ProcessResult> envCheckIn(
  String envFile, {
  List<String> args = const <String>[],
  String? testing,
  String appEnv = '',
  bool generated = true,
}) async {
  String cli = Directory.current.path;
  Directory temp = Directory.systemTemp.createTempSync('dox_env_check_');
  try {
    File('${temp.path}/dox_core/pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: dox_core\nenvironment:\n  sdk: ^3.13.0\n');
    File('${temp.path}/dox_core/lib/dox_core.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(fakeCore);
    String app = '${temp.path}/app';
    File('$app/pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'name: my_app\nenvironment:\n  sdk: ^3.13.0\n'
        'dependencies:\n  dox_core:\n    path: ../dox_core\n',
      );
    File('$app/lib/config/env.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(fakeAppEnv);
    File('$app/.env').writeAsStringSync(envFile);
    if (testing != null) File('$app/.env.testing').writeAsStringSync(testing);
    if (generated) {
      // the real app has it from build_runner; the fake class needs none
      File('$app/lib/config/env.g.dart')
          .writeAsStringSync("part of 'env.dart';\n");
    }
    String dart = Platform.resolvedExecutable;
    ProcessResult get = await Process.run(dart, <String>[
      'pub',
      'get',
      '--offline',
    ], workingDirectory: app);
    expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');
    return await Process.run(
      dart,
      <String>[
        '--packages=$cli/.dart_tool/package_config.json',
        '$cli/bin/dox.dart',
        'env:check',
        ...args,
      ],
      workingDirectory: app,
      environment: <String, String>{'APP_ENV': appEnv},
    );
  } finally {
    temp.deleteSync(recursive: true);
  }
}
