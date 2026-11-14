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
  'PWD',
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
  'SIGNATURE',
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

/// What `bin/server.dart` does with `Env.flags`, read from its text.
///
/// The real app reads `.env` once, with the `Env.flags` of that moment.
/// Only `main()` sets `Env.flags`. dox_core never takes it from
/// `AppConfig`, it only warns at start when they differ. So the check
/// reads `main()` and does the same.
///
/// What it can see: an `Env.flags = <value>;` line in `main()`, and if
/// code that can read the env (`appConfig`, `env.`, `Env`, `AppEnv`,
/// `Dox()`) comes before it. What it can not see: code in other files
/// that `main()` calls, and a value that is not a plain name or a
/// `CoreFlags(...)` call. For such a value it uses the config flags.
class ServerFlags {
  /// the value given to `Env.flags`, or null when main() does not set it
  /// in time
  final String? value;

  /// `Env.flags` is set, but after code that can read the env
  final bool late;

  /// `Env.flags` is set to a value that is not plain enough to copy
  final bool unknown;

  /// the imports of `bin/server.dart`, with relative paths made absolute
  final List<String> imports;

  const ServerFlags({
    this.value,
    this.late = false,
    this.unknown = false,
    this.imports = const <String>[],
  });

  static final RegExp _main = RegExp(r'\bmain\s*\(');

  static final RegExp _set = RegExp(r'\bEnv\.flags\s*=\s*([^;]+);');

  static final RegExp _readsEnv = RegExp(
    r'\b(appConfig|env\.|Env\.get|Env\(\)|AppEnv|Dox\(\))',
  );

  static final RegExp _plain = RegExp(
    r'^(const\s+)?[A-Za-z_$][\w$.]*(\([^;()?]*\))?$',
  );

  static final RegExp _import = RegExp(
    r'''^import\s+['"]([^'"]+)['"]([^;]*);''',
    multiLine: true,
  );

  /// reads `bin/server.dart` of the app [root]
  static ServerFlags read(String root) {
    File file = File('$root/bin/server.dart');
    if (!file.existsSync()) return const ServerFlags();
    String code = file.readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');
    Match? main = _main.firstMatch(code);
    if (main == null) return const ServerFlags();
    String body = code.substring(main.end);
    Match? set = _set.firstMatch(body);
    if (set == null) return const ServerFlags();
    if (_readsEnv.hasMatch(body.substring(0, set.start))) {
      return const ServerFlags(late: true);
    }
    String value = set[1]!.trim();
    if (!_plain.hasMatch(value)) return const ServerFlags(unknown: true);
    List<String> imports = <String>[];
    Uri bin = Directory('$root/bin').uri;
    for (Match line in _import.allMatches(code)) {
      String uri = line[1]!;
      if (!uri.startsWith('package:') && !uri.startsWith('dart:')) {
        uri = bin.resolve(uri).toString();
      }
      imports.add("import '$uri'${line[2]};");
    }
    return ServerFlags(value: value, imports: imports);
  }
}

/// The script that `dox env:check` runs in the app [root] of package
/// [package].
///
/// It sets `Env.flags` like `main()` of `bin/server.dart` does
/// ([ServerFlags]) and then loads `AppEnv`. So it lists the errors that
/// the real app has at start, no more. When the config turns on
/// `envExpand` but `.env` was read without it, it says so and fails:
/// Dox only warns, but the `${...}` values are then wrong.
String envCheckScript(String package, String root) {
  File config = File('$root/lib/config/app.dart');
  String configText = config.existsSync() ? config.readAsStringSync() : '';
  bool hasConfig = RegExp(r'\bappConfig\s*=').hasMatch(configText);
  // a guess from the text, for when appConfig can not be built
  bool configExpand = RegExp(r'envExpand\s*:\s*true|CoreFlags\.all\(')
      .hasMatch(configText);
  ServerFlags server = ServerFlags.read(root);

  StringBuffer imports = StringBuffer();
  for (String line in server.imports) {
    imports.writeln(line);
  }
  if (hasConfig) imports.writeln("import 'package:$package/config/app.dart';");

  String setFlags = '';
  String why = 'bin/server.dart sets Env.flags with envExpand off.';
  if (server.value != null) {
    setFlags = 'Env.flags = ${server.value};';
  } else if (server.unknown) {
    setFlags = 'Env.flags = const CoreFlags(envExpand: $configExpand);';
  } else if (server.late) {
    why = 'bin/server.dart sets Env.flags after the env is read.';
  } else {
    why = 'bin/server.dart does not set Env.flags.';
  }
  String mismatch =
      'lib/config/app.dart turns on CoreFlags.envExpand, but the app reads '
      r'.env without it, so ${...} values are not replaced. '
      '$why Fix: make `Env.flags = flags;` the first line of main() in '
      'bin/server.dart, with the same flags as AppConfig.';
  String readConfig = hasConfig
      ? '''

  if (valid) {
    try {
      configExpand = appConfig.flags.envExpand;
    } catch (_) {}
  }'''
      : '';

  return """
import 'dart:io';

${imports}import 'package:$package/config/env.dart';
import 'package:dox_core/dox_core.dart';

void main() {
  bool valid = false;
  try {
    $setFlags
    AppEnv.load();
    valid = true;
  } on EnvException catch (e) {
    print(e);
    exitCode = 1;
  }
  bool configExpand = $configExpand;$readConfig
  if (configExpand && !Env().expanded) {
    print(r'''$mismatch''');
    exitCode = 1;
  }
  if (exitCode == 0) print('The env is valid.');
}
""";
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
  if (ServerFlags.read(root).unknown) {
    print(
      'Note: bin/server.dart sets Env.flags to a value env:check can not '
      'read. The check uses envExpand from lib/config/app.dart.',
    );
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
