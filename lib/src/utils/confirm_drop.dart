import 'dart:io';

// same .env rules as the Migrator that runs next
import 'package:dox_migration/env.dart' show loadEnv;

/// Says if `migration:fresh`, `migration:reset` or `migration:refresh`
/// may drop all tables.
///
/// - APP_ENV is not `production`: yes, nothing changes.
/// - `--force`: yes, no question.
/// - stdin is a terminal: ask, and go on only when the answer is `y`.
/// - stdin is not a terminal (CI, deploy scripts): print a warning and go on,
///   so old scripts keep working.
///
/// [env], [terminal] and [ask] are for tests.
bool confirmDropAll({
  required bool force,
  Map<String, String>? env,
  bool? terminal,
  String? Function()? ask,
}) {
  env ??= loadEnv();
  if (env['APP_ENV']?.toLowerCase() != 'production' || force) return true;
  terminal ??= stdin.hasTerminal;
  if (!terminal) {
    print(
      'Warning: APP_ENV is production. This drops all tables. '
      'Use --force to hide this warning.',
    );
    return true;
  }
  stdout.write(
    'APP_ENV is production. This drops all tables. Continue? (y/N) ',
  );
  String? answer = ask == null ? stdin.readLineSync() : ask();
  return answer?.trim().toLowerCase() == 'y';
}
