import 'dart:io';

import '../utils/utils.dart';

String _getSample(String package, String className, String filename) {
  return '''
import 'package:dox_core/dox_core.dart';

import 'package:$package/app/models/$filename/$filename.model.dart';

class ${className}Serializer extends Serializer<$className> {
  ${className}Serializer(super.data);

  @override
  Map<String, dynamic> convert($className m) {
    return <String, dynamic>{};
  }
}
''';
}

bool createSerializer(String filename) {
  String? name = generatorName(filename, 'serializer');
  if (name == null) return false;
  filename = name;
  String className = snakeToPascal(filename);
  String? package = appPackageName();
  if (package == null) {
    print('pubspec.yaml has no name. Run this in the app folder.');
    exitCode = 1;
    return false;
  }
  String path = '${Directory.current.path}/lib/app/serializers/';
  String serializerName = '$filename.serializer';
  final file = File('$path$filename.serializer.dart');

  if (file.existsSync()) {
    print('\x1B[32m$serializerName already exists\x1B[0m');
    return false;
  }

  file.createSync(recursive: true);
  file.writeAsStringSync(
    _getSample(package, className, filename),
    mode: FileMode.write,
  );
  print('\x1B[32m$serializerName created successfully.\x1B[0m');
  return true;
}
