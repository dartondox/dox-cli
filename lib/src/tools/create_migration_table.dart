import 'package:dox/dox.dart';
import 'package:dox_query_builder/dox_query_builder.dart';
import 'package:postgres/postgres.dart';

String migrationTableName = 'dox_db_migration';

Future<void> createMigrationTableIfNotExist() async {
  Map<String, String> env = loadEnv();
  PostgreSQLConnection db = PostgreSQLConnection(
    '${env['DB_HOST']}',
    int.parse('${env['DB_PORT']}'),
    '${env['DB_NAME']}',
    username: '${env['DB_USERNAME']}',
    password: '${env['DB_PASSWORD']}',
  );
  if (db.isClosed) {
    await db.open();
  }
  SqlQueryBuilder.initialize(database: db);
  await Schema.create(migrationTableName, (Table table) {
    table.id();
    table.string('migration');
    table.integer('batch');
  });
}
