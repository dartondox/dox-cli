import 'dart:io';

import 'package:dox/src/tools/create_migration_table.dart';
import 'package:dox_query_builder/dox_query_builder.dart';

import '../utils/utils.dart';

void dbMigrate() async {
  await createMigrationTableIfNotExist();
  String path = '${Directory.current.path}/db/migration';
  final tempFolder = Directory('$path/tmp');
  try {
    final folder = Directory(path);
    final files = folder
        .listSync()
        .whereType<File>()
        .where((entity) => entity.path.endsWith('.dart'))
        .toList();

    files.sort((a, b) => a.path.compareTo(b.path));

    List latestBatch = await QueryBuilder.table(MIGRATION_TABLE_NAME)
        .select('batch')
        .orderBy('batch', 'desc')
        .limit(1)
        .get();

    int batchNumber = 1;

    List migrated = [];

    if (latestBatch.isNotEmpty) {
      batchNumber = int.parse(latestBatch.first['batch'].toString()) + 1;
    }

    for (var entity in files) {
      Uri uri = Platform.script.resolve(entity.path);
      String filename = uri.pathSegments.last.replaceAll('.dart', '');

      Map? migration = await QueryBuilder.table(MIGRATION_TABLE_NAME)
          .find('migration', filename);

      if (migration == null) {
        migrated.add(filename);
        File tempFile = _getTempFileContent(entity.path, filename, path);

        print('\x1B[32mMigrating: $filename\x1B[0m');

        ProcessResult result =
            Process.runSync('dart', [tempFile.path, filename]);

        if (result.stderr != '') {
          print('\x1B[34mFailed to migrate: $filename\x1B[0m');
          print('\x1B[31mError: ${result.stderr}\x1B[0m');
        } else {
          await QueryBuilder.table(MIGRATION_TABLE_NAME).insert({
            'migration': filename,
            'batch': batchNumber,
          });
          print('\x1B[32mMigrated: $filename\x1B[0m');
        }
      }
    }
    if (tempFolder.existsSync()) {
      tempFolder.delete(recursive: true);
    }
    if (migrated.isEmpty) {
      print("\x1B[34mMigrations not found. Nothing to migrate!\x1B[0m");
    }
    await SqlQueryBuilder().db.close();
  } catch (error) {
    print('\x1B[34mNothing to migrate!\x1B[0m');
    print(error);
    await SqlQueryBuilder().db.close();
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
  try {
  await up();
    if(!db.isClosed) {
      db.close();
    }
  } catch(error) {
    db.close();
  }
}
""";
  String timestamp = DateTime.now().microsecondsSinceEpoch.toString();
  final tempFile = File('$basePath/tmp/$timestamp$filename.temp.dart');
  tempFile.createSync(recursive: true);
  tempFile.writeAsStringSync(content);
  return tempFile;
}
