import 'dart:io';

import 'package:dox/src/tools/create_migration.dart';

/// `dox cache:table`: write the `create_cache_table` migration, the table
/// of the database cache store. When it already exists, print a message and
/// set exit code 1.
void createCacheTableMigration() {
  Directory dir = migrationDirectory();
  bool exists =
      dir.existsSync() &&
      dir.listSync().whereType<File>().any(
        (File f) => _existing.hasMatch(f.uri.pathSegments.last),
      );
  if (exists) {
    print('A create_cache_table migration is already in db/migration.');
    exitCode = 1;
    return;
  }
  createMigration('create_cache_table', source: cacheTableMigrationSource);
  print('Run `dox migrate` to make the table.');
}

/// `2026_10_21_120000_create_cache_table.dart` (or `.sql`)
final RegExp _existing = RegExp(
  r'^\d{4}_\d{2}_\d{2}_\d+_create_cache_table\.(dart|sql)$',
);

/// the migration file
const String cacheTableMigrationSource = '''
// ignore_for_file: file_names
import 'package:dox_migration/dox_migration.dart';

/// The cache table of the database cache store.
class CreateCacheTable extends Migration {
  @override
  Future<void> up(Schema schema) async {
    await schema.create('cache', (Table table) {
      table.string('key', 255).primary();
      table.longText('value');
      // unix time in milliseconds (UTC)
      table.bigInteger('expires_at').nullable();
    });
  }

  @override
  Future<void> down(Schema schema) async {
    await schema.dropIfExists('cache');
  }
}
''';
