import 'dart:io';

import '../utils/utils.dart';

String _getSample(className, filename) {
  return '''
import 'package:dox_core/dox_core.dart';

part '$filename.model.g.dart';

@IsModel()
class $className extends Model {
  @override
  List<String> get hidden => [];

  @Column()
  int? id;

  @Column(name: 'created_at')
  DateTime? createdAt;

  @Column(name: 'updated_at')
  DateTime? updatedAt;

  @override
  fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);

  @override
  toMap() => _\$${className}ToJson(this);
}
''';
}

bool createModel(filename) {
  filename = pascalToSnake(filename);
  String className = snakeToPascal(filename);
  String path = '${Directory.current.path}/lib/models/';
  final file = File('$path$filename.model.dart');

  if (file.existsSync()) {
    print('\x1B[32m$className model already exists\x1B[0m');
    return false;
  }

  file.createSync(recursive: true);
  file.writeAsStringSync(_getSample(className, filename), mode: FileMode.write);
  print('\x1B[32m$className model created successfully.\x1B[0m');
  return true;
}
