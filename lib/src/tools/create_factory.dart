import 'dart:io';

import '../utils/utils.dart';

String _getSample(String package, String className, String filename) {
  String variable = toPascalWithFirstLetterLowerCase(filename);
  return '''
import 'package:dox_orm/factory.dart';
import 'package:$package/app/models/$filename/$filename.model.dart';

class ${className}Factory extends Factory<$className> {
  @override
  $className definition() {
    $className $variable = $className();
    // $variable.name = 'Jane';
    return $variable;
  }
}
''';
}

/// `dox make:factory User` makes `db/factories/user.factory.dart`
bool createFactory(String name) {
  String? filename = generatorName(name, 'factory');
  if (filename == null) return false;
  String className = snakeToPascal(filename);
  String? package = appPackageName();
  if (package == null) {
    print('pubspec.yaml has no name. Run this in the app folder.');
    exitCode = 1;
    return false;
  }
  String factoryName = '$filename.factory';
  File file = File('${Directory.current.path}/db/factories/$factoryName.dart');
  if (file.existsSync()) {
    print('\x1B[32m$factoryName already exists\x1B[0m');
    return false;
  }
  file.createSync(recursive: true);
  file.writeAsStringSync(_getSample(package, className, filename));
  print('\x1B[32m$factoryName created successfully.\x1B[0m');
  return true;
}
