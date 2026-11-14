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
    const String expandOn = '''
import 'package:dox_core/dox_core.dart';
import 'package:my_app/config/env.dart';

const CoreFlags flags = CoreFlags(envExpand: true);

AppConfig appConfig = AppConfig(flags: flags, serverPort: env.appPort);
''';
    const String expandOff = '''
import 'package:dox_core/dox_core.dart';
import 'package:my_app/config/env.dart';

AppConfig appConfig = AppConfig(serverPort: env.appPort);
''';
    const String dotEnv = 'PORT=3000\nAPP_PORT=\${PORT}\n';

    test('uses the envExpand flag of the app config', () async {
      ProcessResult r = await envCheckIn(dotEnv, appConfig: expandOn);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('The env is valid.'));
    });

    test('with the flag off, the same .env is not valid', () async {
      ProcessResult r = await envCheckIn(dotEnv, appConfig: expandOff);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('APP_PORT must be an int'));
    });

    test('works with no lib/config/app.dart', () async {
      ProcessResult r = await envCheckIn('APP_PORT=3000\n');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('The env is valid.'));
    });
  });
}

/// A small stand-in for dox_core: `.env` with `${X}` only when
/// `Env.flags.envExpand` is on. `dox env:check` runs against it.
const String fakeCore = r'''
import 'dart:io';

class CoreFlags {
  final bool envExpand;
  const CoreFlags({this.envExpand = false});
}

class AppConfig {
  final CoreFlags flags;
  AppConfig({this.flags = const CoreFlags(), int? serverPort});
}

class EnvException implements Exception {
  final String message;
  EnvException(this.message);
  @override
  String toString() => 'EnvException: $message';
}

class Env {
  static final Env _one = Env._();
  factory Env() => _one;
  Env._();
  static CoreFlags flags = const CoreFlags();
  Map<String, String> env = <String, String>{};

  void load() {
    if (env.isNotEmpty) return;
    for (String line in File('.env').readAsLinesSync()) {
      int eq = line.indexOf('=');
      if (eq < 1) continue;
      String value = line.substring(eq + 1);
      if (flags.envExpand) {
        value = value.replaceAllMapped(
          RegExp(r'\$\{(\w+)\}'),
          (Match m) => env[m[1]] ?? m[0]!,
        );
      }
      env[line.substring(0, eq)] = value;
    }
  }
}
''';

/// the app's `lib/config/env.dart`: APP_PORT must be an int
const String fakeAppEnv = r'''
import 'package:dox_core/dox_core.dart';

class AppEnv {
  final int appPort;
  AppEnv(this.appPort);

  static AppEnv load() {
    Env().load();
    String raw = Env().env['APP_PORT'] ?? '';
    int? port = int.tryParse(raw);
    if (port == null) throw EnvException('APP_PORT must be an int: $raw');
    return AppEnv(port);
  }
}

final AppEnv env = AppEnv.load();
''';

/// `dox env:check` in a temp app, from the source of this CLI
Future<ProcessResult> envCheckIn(String envFile, {String? appConfig}) async {
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
    if (appConfig != null) {
      File('$app/lib/config/app.dart').writeAsStringSync(appConfig);
    }
    File('$app/.env').writeAsStringSync(envFile);
    String dart = Platform.resolvedExecutable;
    ProcessResult get = await Process.run(dart, <String>[
      'pub',
      'get',
      '--offline',
    ], workingDirectory: app);
    expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');
    return await Process.run(dart, <String>[
      '--packages=$cli/.dart_tool/package_config.json',
      '$cli/bin/dox.dart',
      'env:check',
    ], workingDirectory: app);
  } finally {
    temp.deleteSync(recursive: true);
  }
}
