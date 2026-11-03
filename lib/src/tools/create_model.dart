import 'dart:io';

import 'package:dox_migration/dox_migration.dart';

import '../utils/utils.dart';

String _getSample(String className, String filename, String table) {
  return '''
import 'package:dox_orm/dox_orm.dart';

part '$filename.model.g.dart';

@DoxModel(table: '$table')
class $className extends ${className}Generator {
  @override
  List<String> get hidden => <String>[];

  /// Columns that create(), insert() and update() may take from a map,
  /// like req.body. Add your columns here, eg. `<String>['title', 'body']`.
  /// While it is empty, create(req.body) throws MassAssignmentException.
  @override
  List<String> get fillable => <String>[];
}
''';
}

/// [table] sets `@DoxModel(table: ...)`. The default is the plural table
/// that `make:model X -m` makes (`BlogPost` => `blog_posts`), because the
/// ORM default is the singular name.
bool createModel(String filename, {String? table}) {
  String? name = generatorName(filename);
  if (name == null) return false;
  filename = name;
  table ??= ForeignIdColumnDefinition.guessTable(filename);
  String className = snakeToPascal(filename);
  String path = '${Directory.current.path}/lib/app/models/$filename/';
  final file = File('$path$filename.model.dart');

  if (file.existsSync()) {
    print('\x1B[32m$className model already exists\x1B[0m');
    return false;
  }

  file.createSync(recursive: true);
  file.writeAsStringSync(
    _getSample(className, filename, table),
    mode: FileMode.write,
  );
  print('\x1B[32m$className model created successfully.\x1B[0m');
  return true;
}
