import 'package:dox/dox.dart';
import 'package:postgres/postgres.dart';
import 'package:sql_query_builder/sql_query_builder.dart';

String MIGRATION_TABLE_NAME = 'dox_db_migration';

Future<void> createMigrationTableIfNotExist() async {
  Map<String, String> env = loadEnv();
  PostgreSQLConnection db = PostgreSQLConnection(
    '${env['DB_HOST']}',
    int.parse('${env['DB_PORT']}'),
    '${env['DB_NAME']}',
    username: '${env['DB_USERNAME']}',
    password: '${env['DB_PASSWORD']}',
  );
  await db.open();
  SqlQueryBuilder.initialize(database: db);
  await Schema.create(MIGRATION_TABLE_NAME, (Table table) {
    table.id();
    table.string('migration');
    table.integer('batch');
  });
}
