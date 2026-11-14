import 'dart:io';

/// Makes the typed env class (`lib/config/env.dart`) from `.env.example`.
///
/// - digits give `int` with the example value as default. A number with a
///   leading zero (`02134`) is a `String`, so the zero is not lost.
/// - true/false give `bool` with the example value as default
/// - an empty value gives an optional `String?`
/// - any other value gives a required `String` (no default)
/// - a key that looks like a secret ([secretKey]) is always a required
///   `String`, so a secret from the example never becomes a default
/// - `export KEY=value` is read like `KEY=value`
/// - `#` comment lines above a key become its doc comment
class EnvScaffold {
  static final RegExp _digits = RegExp(r'^-?(0|[1-9]\d*)$');

  static final RegExp _export = RegExp(r'^export\s+');

  String build(String example) {
    StringBuffer getters = StringBuffer();
    List<String> comments = <String>[];
    for (String line in example.split('\n')) {
      String text = line.trim();
      if (text.isEmpty) {
        comments.clear();
        continue;
      }
      if (text.startsWith('#')) {
        comments.add(text.substring(1).trim());
        continue;
      }
      text = text.replaceFirst(_export, '');
      int equal = text.indexOf('=');
      if (equal < 1) continue;
      String key = text.substring(0, equal).trim();
      String value = _value(text.substring(equal + 1).trim());
      getters.writeln();
      for (String comment in comments) {
        getters.writeln('  /// $comment');
      }
      comments.clear();
      String name = getterName(key);
      // the name must give the key under the old and the new rule of
      // dox_builder, else the key is written out
      if (upperSnake(name) != key || acronymUpperSnake(name) != key) {
        getters.writeln("  @EnvKey('$key')");
      }
      getters.writeln('  ${_getter(name, value, secretKey(key))}');
    }

    return '''
import 'package:dox_core/dox_core.dart';

part 'env.g.dart';

/// The env of the app, typed. Made by `dox env:generate`.
/// -------------------------------
/// Each getter reads one key: `appName` reads `APP_NAME`.
/// A getter body is the default. A nullable getter is optional.
/// Other getters are required: the app stops at startup when one is missing.
/// Run `dart run build_runner build` after you change this class.
@DoxEnv()
abstract class AppEnv {
  /// reads and checks every key once
  static AppEnv load([EnvReader? reader]) {
    return _\$AppEnv.load(reader);
  }
$getters}

/// The env of the app. Read and checked once, on first use.
final AppEnv env = AppEnv.load();
''';
  }

  String _getter(String name, String value, bool secret) {
    if (value.isEmpty) return 'String? get $name;';
    if (secret) return 'String get $name;';
    if (_digits.hasMatch(value)) return 'int get $name => $value;';
    String lower = value.toLowerCase();
    if (lower == 'true' || lower == 'false') {
      return 'bool get $name => $lower;';
    }
    return 'String get $name;';
  }

  static final RegExp _comment = RegExp(r'(^|\s)#');

  /// the value without quotes, or without a `# comment` after a space
  String _value(String value) {
    if (value.isNotEmpty && '"\'`'.contains(value[0])) {
      int end = value.indexOf(value[0], 1);
      if (end > 0) return value.substring(1, end);
    }
    Match? comment = _comment.firstMatch(value);
    if (comment != null) value = value.substring(0, comment.start);
    return value.trim();
  }
}

/// Parts of a key that mark a secret: `DB_PASSWORD`, `APP_KEY`.
const Set<String> _secretParts = <String>{
  'PASSWORD',
  'PASSWD',
  'PASS',
  'PWD',
  'SECRET',
  'KEY',
  'TOKEN',
  'SALT',
  'CREDENTIAL',
  'CREDENTIALS',
  'PRIVATE',
};

/// True when a part of [key] (split on `_`) marks a secret. Its value in
/// `.env.example` must never become a default in the code.
bool secretKey(String key) {
  for (String part in key.toUpperCase().split('_')) {
    if (_secretParts.contains(part)) return true;
  }
  return false;
}

/// Words that can not be a getter name.
const Set<String> _reserved = <String>{
  'assert',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'else',
  'enum',
  'extends',
  'false',
  'final',
  'finally',
  'for',
  'if',
  'in',
  'is',
  'new',
  'null',
  'rethrow',
  'return',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'var',
  'void',
  'when',
  'while',
  'with',
  'await',
  'yield',
};

/// A valid getter name for [key]: `APP_NAME` => `appName`.
/// A reserved word or a name that starts with a digit gets `env` in front:
/// `CLASS` => `envClass`, `1ST` => `env1st`. Other characters are dropped.
String getterName(String key) {
  String name = camelCase(key).replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
  if (name.isEmpty) return 'env';
  if (_reserved.contains(name) || RegExp(r'^\d').hasMatch(name)) {
    return 'env${name[0].toUpperCase()}${name.substring(1)}';
  }
  return name;
}

/// `APP_NAME` => `appName`
String camelCase(String key) {
  List<String> words = key.toLowerCase().split('_');
  StringBuffer out = StringBuffer(words.first);
  for (String word in words.skip(1)) {
    if (word.isEmpty) continue;
    out.write(word[0].toUpperCase() + word.substring(1));
  }
  return out.toString();
}

/// `appName` => `APP_NAME`, the same rule as the dox_builder generator
String upperSnake(String name) {
  StringBuffer out = StringBuffer();
  for (int i = 0; i < name.length; i++) {
    String char = name[i];
    if (char != char.toLowerCase() && i > 0) out.write('_');
    out.write(char.toUpperCase());
  }
  return out.toString();
}

/// `dbURL` => `DB_URL`, `s3Bucket` => `S3_BUCKET`. The rule for
/// acronyms: a run of capitals is one word.
String acronymUpperSnake(String name) {
  StringBuffer out = StringBuffer();
  for (int i = 0; i < name.length; i++) {
    if (i > 0 && _upper(name[i])) {
      bool afterUpper = _upper(name[i - 1]);
      bool beforeLower = i + 1 < name.length && _lower(name[i + 1]);
      if (!afterUpper || beforeLower) out.write('_');
    }
    out.write(name[i].toUpperCase());
  }
  return out.toString();
}

bool _upper(String char) {
  return char != char.toLowerCase();
}

bool _lower(String char) {
  return char != char.toUpperCase();
}

/// `dox env:generate`: writes `lib/config/env.dart` from `.env.example`.
/// Gives false (and exit code 1) when the example is missing or the file
/// is already there.
bool envGenerate() {
  String root = Directory.current.path;
  File example = File('$root/.env.example');
  File target = File('$root/lib/config/env.dart');
  if (!example.existsSync()) {
    print('.env.example is missing.');
    exitCode = 1;
    return false;
  }
  if (target.existsSync()) {
    print('lib/config/env.dart is already there. Delete it to make it again.');
    exitCode = 1;
    return false;
  }
  target.createSync(recursive: true);
  target.writeAsStringSync(EnvScaffold().build(example.readAsStringSync()));
  print(
    '\x1B[32mlib/config/env.dart created.\x1B[0m '
    'Run `dart run build_runner build` to make env.g.dart.',
  );
  return true;
}

/// The script that `dox env:check` runs in the app [root] of package
/// [package].
///
/// `.env` must be read with the same `Env.flags` as the app, or a value
/// like `${PORT}` gives a false error. The app sets `Env.flags` from the
/// flags of its `AppConfig`. So when `lib/config/app.dart` has an
/// `appConfig`, the script reads `appConfig.flags` first. The config often
/// reads the env itself, so a bad env can throw. Then it tries again with
/// `envExpand` on. When that also throws, it uses the default flags.
String envCheckScript(String package, String root) {
  File config = File('$root/lib/config/app.dart');
  bool hasConfig =
      config.existsSync() &&
      RegExp(r'\bappConfig\s*=').hasMatch(config.readAsStringSync());
  String import = hasConfig
      ? "import 'package:$package/config/app.dart';\n"
      : '';
  String read = hasConfig
      ? '''
      Env.flags = CoreFlags(envExpand: expand);
      Env().env = <String, String>{};
      return appConfig.flags;'''
      : '''
      return null;''';
  return '''
import 'dart:io';

${import}import 'package:$package/config/env.dart';
import 'package:dox_core/dox_core.dart';

/// the flags of the app config, or null when it throws
CoreFlags? appFlags(bool expand) {
  try {$read
  } catch (_) {
    return null;
  }
}

void main() {
  CoreFlags flags = appFlags(false) ?? appFlags(true) ?? const CoreFlags();
  // read .env again, with the flags of the app
  Env.flags = flags;
  Env().env = <String, String>{};
  try {
    AppEnv.load();
    print('The env is valid.');
  } on EnvException catch (e) {
    print(e);
    exitCode = 1;
  }
}
''';
}

/// `dox env:check`: loads `AppEnv` from `lib/config/env.dart` with the
/// current env and `.env`. Prints every missing or bad key (exit code 1).
Future<void> envCheck() async {
  String root = Directory.current.path;
  if (!File('$root/lib/config/env.dart').existsSync()) {
    print('lib/config/env.dart is missing. Run `dox env:generate` first.');
    exitCode = 1;
    return;
  }
  RegExpMatch? name = RegExp(
    r'^name:\s*(\S+)',
    multiLine: true,
  ).firstMatch(File('$root/pubspec.yaml').readAsStringSync());
  if (name == null) {
    print('pubspec.yaml has no name.');
    exitCode = 1;
    return;
  }
  File script = File('$root/.dart_tool/dox/env_check.dart');
  script.createSync(recursive: true);
  script.writeAsStringSync(envCheckScript(name.group(1)!, root));
  String exe = Platform.resolvedExecutable;
  String dart = exe.split(Platform.pathSeparator).last.startsWith('dart')
      ? exe
      : 'dart';
  Process process = await Process.start(dart, <String>[
    'run',
    script.path,
  ], mode: ProcessStartMode.inheritStdio);
  int code = await process.exitCode;
  if (code != 0) exitCode = code;
}
