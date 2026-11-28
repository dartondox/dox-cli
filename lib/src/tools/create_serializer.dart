import 'dart:io';

import '../utils/args.dart';
import '../utils/utils.dart';
import 'package_commands.dart';

String _getSample(
  String package,
  String className,
  String filename, {
  required bool fast,
}) {
  String model = 'package:$package/app/models/$filename/$filename.model.dart';
  if (!fast) {
    return '''
import 'package:dox_core/dox_core.dart';

import '$model';

class ${className}Serializer extends Serializer<$className> {
  ${className}Serializer(super.data);

  @override
  Map<String, dynamic> convert($className m) {
    return <String, dynamic>{};
  }
}
''';
  }
  return '''
import 'package:dox_core/dox_core.dart';

import '$model';

part '$filename.serializer.g.dart';

/// `@Serialize()` writes the JSON of [convert] with no `Map` in between.
/// Run `dart run build_runner build` to make the `.g.dart` file.
@Serialize()
class ${className}Serializer extends Serializer<$className> {
  ${className}Serializer(super.data);

  @override
  Map<String, dynamic> convert($className m) {
    return <String, dynamic>{};
  }
}
''';
}

/// `true` when the dox_annotation of the app in [root] has `@Serialize()`.
/// An app with an older dox_core gets the serializer without it, so the
/// new file compiles.
bool appHasSerialize({Directory? root}) {
  Directory? lib = PackageCommands(root: root).packageLib('dox_annotation');
  if (lib == null || !lib.existsSync()) return false;
  // a line that starts a class, so a comment that names it does not count
  RegExp annotation = RegExp(
    r'^\s*(abstract\s+|final\s+)?class Serialize\b',
    multiLine: true,
  );
  try {
    for (FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          annotation.hasMatch(entity.readAsStringSync())) {
        return true;
      }
    }
  } on FileSystemException {
    return false;
  }
  return false;
}

/// `dox make:serializer Post [--folder]`. `--folder` puts the file in
/// `lib/app/serializers/post/`, else it goes in `lib/app/serializers/`.
bool makeSerializer(List<String> args) {
  ParsedArgs? parsed = parseArgs(
    'make:serializer',
    args,
    flags: const <String>{'folder'},
  );
  if (parsed == null) return false;
  return createSerializer(
    parsed.names.first,
    folder: parsed.flags.contains('folder'),
  );
}

bool createSerializer(String filename, {bool folder = false, bool? fast}) {
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
  String path =
      '${Directory.current.path}/lib/app/serializers/'
      '${folder ? '$filename/' : ''}';
  String serializerName = '$filename.serializer';
  final file = File('$path$filename.serializer.dart');

  // the flat file and the one in a folder are the same serializer
  String base = '${Directory.current.path}/lib/app/serializers/';
  File other = File(
    folder
        ? '$base$filename.serializer.dart'
        : '$base$filename/$filename.serializer.dart',
  );
  if (file.existsSync() || other.existsSync()) {
    print('\x1B[32m$serializerName already exists\x1B[0m');
    return false;
  }

  bool withSerialize = fast ?? appHasSerialize();
  file.createSync(recursive: true);
  file.writeAsStringSync(
    _getSample(package, className, filename, fast: withSerialize),
    mode: FileMode.write,
  );
  print('\x1B[32m$serializerName created successfully.\x1B[0m');
  if (withSerialize) {
    print('Run `dox build_runner:build` to make $serializerName.g.dart.');
  }
  return true;
}
