import 'dart:io';

import '../utils/utils.dart';

String getSample(className) {
  return '''
import 'package:sql_query_builder/sql_query_builder.dart';

class $className extends Model {
  @Column()
  int? id;

  @Column(name: 'created_at')
  DateTime? createdAt;

  @Column(name: 'updated_at')
  DateTime? updatedAt;
}
''';
}

createModel(filename) {
  filename = pascalToSnake(filename);
  String className = snakeToPascal(filename);
  String path = '${Directory.current.path}/app/models/';
  final file = File('$path$filename.model.dart');

  if (file.existsSync()) {
    // Do something with the file
    print('$className model already exists');
  }

  file.createSync(recursive: true);
  file.writeAsStringSync(getSample(className), mode: FileMode.write);
}
