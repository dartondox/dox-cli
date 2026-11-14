import 'dart:io';
import 'dart:math';

import 'package:dox/src/utils/confirm_drop.dart';

/// `dox key:generate [--show] [--force]`. Gives the exit code.
///
/// - `--show`: print a new key, write nothing.
/// - APP_ENV is `production`: a new `APP_KEY` logs out every user, so it
///   uses the same check as `migration:fresh` ([confirmDropAll]). In a
///   terminal it asks first. With no terminal (deploy scripts) it prints
///   a warning and goes on, like before. `--force` skips the check.
/// - else: write a new `APP_KEY` to `.env`, like before.
///
/// [env], [terminal], [ask] and [path] (the `.env` file) are for tests.
int generateKey(
  List<String> args, {
  Map<String, String>? env,
  bool? terminal,
  String? Function()? ask,
  String? path,
}) {
  for (String arg in args) {
    // 3.0.x ignored extra words, so scripts that pass one keep working
    if (arg != '--show' && arg != '--force') {
      // stderr, so `KEY=$(dox key:generate --show foo)` gets only the key
      stderr.writeln(
        'Warning: ignoring unknown option $arg (use --show or --force).',
      );
    }
  }
  String secret = newKey();
  if (args.contains('--show')) {
    print(secret);
    return 0;
  }
  bool go = confirmDropAll(
    force: args.contains('--force'),
    danger: 'A new APP_KEY logs out every user.',
    env: env,
    terminal: terminal,
    ask: ask,
  );
  if (!go) {
    print('Stopped. APP_KEY was not changed.');
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

/// An `APP_KEY` line: `APP_KEY=x`, `export APP_KEY=x`, `APP_KEY = x`.
final RegExp _keyLine = RegExp(r'^\s*(export\s+)?APP_KEY\s*=');

/// Sets `APP_KEY` in `.env` to [secret].
///
/// Only the `APP_KEY` lines change. Every other line (comments, blank
/// lines, quotes, values with more than one `=`) stays as it is, in order.
/// `export APP_KEY=x` keeps its `export`. When there are more `APP_KEY`
/// lines, each one gets the new key, so no old key is left to win.
/// When there is no `APP_KEY`, it is added as the first line.
void overrideKey(String secret, [String? path]) {
  final file = File(path ?? '${Directory.current.path}/.env');
  String text = file.readAsStringSync();
  List<String> lines = text.split('\n');
  bool found = false;
  for (int i = 0; i < lines.length; i++) {
    String line = lines[i];
    RegExpMatch? match = _keyLine.firstMatch(line);
    if (match == null) continue;
    // Keep a Windows line end (\r) when the file has one.
    String end = line.endsWith('\r') ? '\r' : '';
    lines[i] = '${match[1] ?? ''}APP_KEY=$secret$end';
    found = true;
  }
  // a new line gets the line end of the file
  String end = text.contains('\r\n') ? '\r' : '';
  if (!found) lines.insert(0, 'APP_KEY=$secret$end');
  file.writeAsStringSync(lines.join('\n'));
}
