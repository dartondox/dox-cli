import 'dart:io';

import '../utils/utils.dart';

String _sample = '''
import 'package:sql_query_builder/sql_query_builder.dart';

Future<void> up() async {
  await Schema.create('table_name', (Table table) {});
}

Future<void> down() async {
  await Schema.drop('table_name');
}
''';

createMigration(name) {
  String filename = parseName(name);
  filename = pascalToSnake(filename);
  String path = '${Directory.current.path}/db/migration/';
  final file = File('$path$filename.dart');
  file.createSync(recursive: true);
  file.writeAsStringSync(_sample, mode: FileMode.write);
}
