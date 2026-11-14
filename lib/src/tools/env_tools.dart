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
    Set<String> used = <String>{};
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
      String unique = name;
      for (int n = 2; !used.add(unique); n++) {
        unique = '$name$n';
      }
      name = unique;
      // the name must give the key under the old and the new rule of
      // dox_builder, else the key is written out
      if (upperSnake(name) != key || acronymUpperSnake(name) != key) {
        getters.writeln('  @EnvKey(${dartString(key)})');
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
    // int.tryParse is null for a number over 64 bits
    if (_digits.hasMatch(value) && int.tryParse(value) != null) {
      return 'int get $name => $value;';
    }
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

/// Words that mark a secret: `DB_PASSWORD`, `APIKEY`, `PIN`.
const List<String> _secretWords = <String>[
  'PASS', // PASSWORD, PASSWD, PASSCODE, PASSPHRASE
  'PW', // PWD too
  'SECRET',
  'KEY',
  'TOKEN',
  'SALT',
  'CREDENTIAL',
  'PRIVATE',
  'AUTH',
  'JWT',
  'DSN',
  'OTP',
  'PIN',
  'CERT',
  'SIGN', // SIGNATURE, SIGNING
  'CODE', // VERIFY_CODE, ADMIN_CODE
  'CVV',
  'CVC',
  'HMAC',
  'SEED',
  'NONCE',
  'SSN',
  'HASH',
  'LICENSE',
];

/// True when [key] holds a word that marks a secret, anywhere in it. Its
/// value in `.env.example` must never become a default in the code.
/// ponytail: a plain substring check, so it is too safe on purpose:
/// `TOKEN_TTL` or `SHIPPING` (has `PIN`) also get no default.
bool secretKey(String key) {
  String upper = key.toUpperCase();
  for (String word in _secretWords) {
    if (upper.contains(word)) return true;
  }
  return false;
}

/// Words that can not be a getter name: Dart reserved words, type names
/// of the generated code, members of `Object`, and names in the class
/// and in the generated `load` (`load`, `r`, `d`, `reader`).
const Set<String> _reserved = <String>{
  'load',
  'r',
  'd',
  'reader',
  'hashCode',
  'runtimeType',
  'toString',
  'noSuchMethod',
  'int',
  'bool',
  'double',
  'num',
  'dynamic',
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
/// `CLASS` => `envClass`, `1ST` => `env1st`, `LOAD` => `envLoad`.
/// Other characters are dropped.
String getterName(String key) {
  String name = camelCase(key).replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
  if (name.isEmpty) return 'env';
  // `_STRING` gives `String`: a getter name starts lower case
  name = name[0].toLowerCase() + name.substring(1);
  if (_reserved.contains(name) || RegExp(r'^\d').hasMatch(name)) {
    return 'env${name[0].toUpperCase()}${name.substring(1)}';
  }
  return name;
}

/// [text] as a Dart string literal: `A'B` => `'A\'B'`, `A$B` => `'A\$B'`.
String dartString(String text) {
  String escaped = text
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$');
  return "'$escaped'";
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

/// The script that `dox env:check` runs in the app of package [package].
///
/// It sets `Env.flags` to the mode of the check ([expand] is
/// `envExpand`), then loads `AppEnv`. So the result is what
/// `AppEnv.load()` gives under those flags. `envExpand` is the only flag
/// that changes how dox_core reads `.env`. The script prints no env
/// value itself.
///
/// With [expand] off, it prints a note when a value of `.env` (and of
/// `.env.testing` in tests) would change with `envExpand` on. It asks
/// `Env.parse` of dox_core both ways, so the note follows the real rules
/// (no change in `'...'`, after ` #`, or for an unknown `${NAME}`).
String envCheckScript(String package, {required bool expand}) {
  return '''
import 'dart:io';

import 'package:$package/config/env.dart';
import 'package:dox_core/dox_core.dart';

/// true when [a] and [b] have the same keys and values
bool same(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (String key in a.keys) {
    if (a[key] != b[key]) return false;
  }
  return true;
}

/// true when a value of .env (or .env.testing in tests) changes with
/// envExpand on
bool expandChanges() {
  File file = File('.env');
  String text = file.existsSync() ? file.readAsStringSync() : '';
  Map<String, String> plain = Env.parse(text);
  Map<String, String> expanded = Env.parse(text, expand: true);
  if (!same(plain, expanded)) return true;
  File testing = File('.env.testing');
  if (!Env.isTesting || !testing.existsSync()) return false;
  text = testing.readAsStringSync();
  return !same(
    Env.parse(text, known: plain),
    Env.parse(text, known: expanded, expand: true),
  );
}

void main() {
  if (!$expand && expandChanges()) {
    print(
      'Note: some .env values change with envExpand on. If the app turns '
      'on envExpand (it sets Env.flags at the top of main()), run '
      '`dox env:check --expand`.',
    );
  }
  Env.flags = const CoreFlags(envExpand: $expand);
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

/// `dox env:check [--expand]`: loads `AppEnv` from `lib/config/env.dart`
/// with the current env and `.env`. Prints every missing or bad key
/// (exit code 1).
///
/// It checks with the default flags, like an app that sets no
/// `Env.flags`. `--expand` checks with `envExpand` on. It does not read
/// the app code to find the flags: that can not be done right without
/// running `main()`. It always says which mode it used.
Future<void> envCheck([List<String> args = const <String>[]]) async {
  for (String arg in args) {
    if (arg != '--expand') {
      print('Unknown option $arg. Use `dox env:check [--expand]`.');
      exitCode = 1;
      return;
    }
  }
  bool expand = args.contains('--expand');
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
  String env = File('$root/lib/config/env.dart').readAsStringSync();
  if (RegExp(r'''part\s+['"]env\.g\.dart['"]''').hasMatch(env) &&
      !File('$root/lib/config/env.g.dart').existsSync()) {
    print(
      'The env class is not generated yet. '
      'Run `dart run build_runner build` first.',
    );
    exitCode = 1;
    return;
  }
  print('Checked with envExpand ${expand ? 'on' : 'off'}.');
  File script = File('$root/.dart_tool/dox/env_check.dart');
  script.createSync(recursive: true);
  script.writeAsStringSync(envCheckScript(name.group(1)!, expand: expand));
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
