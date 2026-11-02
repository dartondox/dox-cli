import 'dart:io';
import 'dart:math';

// same .env rules as the production check of the migration commands
import 'package:dox_migration/env.dart' show loadEnv;

/// `dox key:generate [--show] [--force]`. Gives the exit code.
///
/// - `--show`: print a new key, write nothing.
/// - APP_ENV is `production`: stop with exit code 1, because a new
///   `APP_KEY` logs out every user. `--force` writes the key anyway.
/// - else: write a new `APP_KEY` to `.env`, like before.
///
/// [env] and [path] (the `.env` file) are for tests.
int generateKey(List<String> args, {Map<String, String>? env, String? path}) {
  for (String arg in args) {
    if (arg != '--show' && arg != '--force') {
      print('Invalid option $arg, use --show or --force');
      return 1;
    }
  }
  String secret = newKey();
  if (args.contains('--show')) {
    print(secret);
    return 0;
  }
  env ??= loadEnv();
  if (env['APP_ENV']?.toLowerCase() == 'production' &&
      !args.contains('--force')) {
    print(
      'APP_ENV is production. A new APP_KEY logs out every user. '
      'Nothing was changed. Use --force to change it anyway, '
      'or --show to only print a new key.',
    );
    return 1;
  }
  overrideKey(secret, path);
  print("\x1B[34m$secret : Key have been updated successfully in .env!\x1B[0m");
  return 0;
}

/// A new random key of 32 characters (A-Z, a-z, 0-9).
String newKey() {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return String.fromCharCodes(
    Iterable.generate(
      32,
      (_) => chars.codeUnitAt(random.nextInt(chars.length)),
    ),
  );
}

/// Sets `APP_KEY` in `.env` to [secret].
///
/// Only the `APP_KEY` line changes. Every other line (comments, blank
/// lines, quotes, values with more than one `=`) stays as it is, in order.
/// When there is no `APP_KEY`, it is added as the first line.
void overrideKey(String secret, [String? path]) {
  final file = File(path ?? '${Directory.current.path}/.env');
  List<String> lines = file.readAsStringSync().split('\n');
  bool found = false;
  for (int i = 0; i < lines.length; i++) {
    String line = lines[i];
    int eq = line.indexOf('=');
    if (eq < 0 || line.substring(0, eq).trim() != 'APP_KEY') continue;
    // Keep a Windows line end (\r) when the file has one.
    String end = line.endsWith('\r') ? '\r' : '';
    lines[i] = 'APP_KEY=$secret$end';
    found = true;
  }
  if (!found) lines.insert(0, 'APP_KEY=$secret');
  file.writeAsStringSync(lines.join('\n'));
}
