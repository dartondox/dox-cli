import 'dart:io';

import 'package:dox/src/tools/create_migration_table.dart';
import 'package:dox_query_builder/dox_query_builder.dart';

import '../utils/utils.dart';

void dbRollback() async {
  await createMigrationTableIfNotExist();
  String path = '${Directory.current.path}/db/migration';
  final tempFolder = Directory('$path/tmp');
  try {
    List latestBatch = await QueryBuilder.table(migrationTableName)
        .select('batch')
        .orderBy('batch', 'desc')
        .limit(1)
        .get();

    int batchNumber = 0;

    if (latestBatch.isNotEmpty) {
      batchNumber = int.parse(latestBatch.first['batch'].toString());
    }

    List migrationsToRollback = [];

    if (batchNumber > 0) {
      migrationsToRollback = await QueryBuilder.table(migrationTableName)
          .select('migration')
          .where('batch', batchNumber)
          .get();
    }

    for (var migration in migrationsToRollback) {
      String filename = migration['migration'];
      Uri uri = Platform.script.resolve("$path/$filename.dart");

      File tempFile = _getTempFileContent(uri.toFilePath(), filename, path);

      print('\x1B[32mRolling back: $filename\x1B[0m');

      ProcessResult result = Process.runSync('dart', [tempFile.path, filename]);

      if (result.stderr != '') {
        print('\x1B[34mFailed to rollback: $filename\x1B[0m');
        print('\x1B[31mError: ${result.stderr}\x1B[0m');
      } else {
        print('\x1B[32mFinished: $filename\x1B[0m');
      }
    }
    if (tempFolder.existsSync()) {
      tempFolder.delete(recursive: true);
    }
    if (batchNumber > 0) {
      await QueryBuilder.table(migrationTableName)
          .where('batch', batchNumber)
          .delete();
    }
    SqlQueryBuilder().db.close();
  } catch (error) {
    print('\x1B[34mMigrations not found. Nothing to migrate!\x1B[0m');
    print(error);
    SqlQueryBuilder().db.close();
  }
}

_isEmpty(data) {
  return data.toString().isEmpty ||
      data.toString() == 'null' ||
      data.toString() == '';
}

_getTempFileContent(String filePath, String filename, String basePath) {
  Map<String, String> env = loadEnv();

  if (_isEmpty(env['DB_HOST'])) {
    print(
        'DB_HOST not found. Please make sure that you have created .env file.');
  }

  if (_isEmpty(env['DB_PORT'])) {
    print(
        'DB_PORT not found. Please make sure that you have created .env file.');
  }

  if (_isEmpty(env['DB_NAME'])) {
    print(
        'DB_NAME not found. Please make sure that you have created .env file.');
  }

  String content = fileGetContents(filePath);
  content = """
import 'package:postgres/postgres.dart';
$content

void main(args) async {
  PostgreSQLConnection db = PostgreSQLConnection(
    '${env['DB_HOST']}',
    int.parse('${env['DB_PORT']}'),
    '${env['DB_NAME']}',
    username: '${env['DB_USERNAME']}',
    password: '${env['DB_PASSWORD']}',
  );
  await db.open();
  SqlQueryBuilder.initialize(database: db);
  await down();
  await db.close();
}
""";
  String timestamp = DateTime.now().microsecondsSinceEpoch.toString();
  final tempFile = File('$basePath/tmp/$timestamp$filename.temp.dart');
  tempFile.createSync(recursive: true);
  tempFile.writeAsStringSync(content);
  return tempFile;
}
