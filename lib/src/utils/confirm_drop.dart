import 'dart:io';

// same .env rules as the Migrator that runs next
import 'package:dox_migration/env.dart' show loadEnv;

/// Says if `migration:fresh`, `migration:reset`, `migration:refresh` or
/// `migration:rollback` may run. [danger] says what the command drops.
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
  String danger = 'This drops all tables.',
  Map<String, String>? env,
  bool? terminal,
  String? Function()? ask,
}) {
  env ??= loadEnv();
  if (env['APP_ENV']?.toLowerCase() != 'production' || force) return true;
  terminal ??= stdin.hasTerminal;
  if (!terminal) {
    print(
      'Warning: APP_ENV is production. $danger '
      'Use --force to hide this warning.',
    );
    return true;
  }
  stdout.write('APP_ENV is production. $danger Continue? (y/N) ');
  String? answer = ask == null ? stdin.readLineSync() : ask();
  return answer?.trim().toLowerCase() == 'y';
}
