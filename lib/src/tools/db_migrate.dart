import 'dart:io';

import '../utils/utils.dart';

void dbMigrate() async {
  String path = '${Directory.current.path}/db/migration';
  final tempFolder = Directory('$path/tmp');
  try {
    final folder = Directory(path);
    final files = folder
        .listSync()
        .whereType<File>()
        .where((entity) => entity.path.endsWith('.dart'));

    for (var entity in files) {
      Uri uri = Platform.script.resolve(entity.path);
      String filename =
          snakeToPascal(uri.pathSegments.last.replaceAll('.dart', ''));

      File tempFile = _getTempFileContent(entity.path, filename, path);

      print('\x1B[32mMigrating: $filename\x1B[0m');

      ProcessResult result = Process.runSync('dart', [tempFile.path, filename]);

      if (result.stderr != '') {
        print('\x1B[34mFailed to migrate: $filename\x1B[0m');
        print('\x1B[31mError: ${result.stderr}\x1B[0m');
      } else {
        print('\x1B[32mMigrated: $filename\x1B[0m');
      }
    }

    tempFolder.delete(recursive: true);
  } catch (error) {
    print('\x1B[34mMigrations not found. Nothing to migrate!\x1B[0m');
    print(error);
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
    print('DB_HOST not found');
  }

  if (_isEmpty(env['DB_PORT'])) {
    print('DB_PORT not found');
  }

  if (_isEmpty(env['DB_NAME'])) {
    print('DB_NAME not found');
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
  await up();
  db.close();
}
""";
  String timestamp = DateTime.now().microsecondsSinceEpoch.toString();
  final tempFile = File('$basePath/tmp/$timestamp$filename.temp.dart');
  tempFile.createSync(recursive: true);
  tempFile.writeAsStringSync(content);
  return tempFile;
}
