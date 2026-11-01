import 'dart:io';

String pascalToSnake(String input) {
  final result = StringBuffer();
  for (final letter in input.codeUnits) {
    if (letter >= 65 && letter <= 90) {
      // Check if uppercase ASCII
      if (result.isNotEmpty) {
        // Add underscore if not first letter
        result.write('_');
      }
      result.write(String.fromCharCode(letter + 32)); // Add lowercase ASCII
    } else {
      result.write(String.fromCharCode(letter)); // Add original character
    }
  }
  String finalString = result.toString().replaceAll(RegExp('_+'), '_');
  finalString = finalString.endsWith('_')
      ? finalString.substring(0, finalString.length - 1)
      : finalString;
  return finalString;
}

/// The snake_case file name for a `make:*` name, or null when it is not safe.
///
/// [suffix] (eg. `controller`) is removed from the end. The result must be
/// a plain Dart name: lowercase letters, digits and `_`, starting with a
/// letter. So it is one path part, and names like `../x`, `/tmp/x` or
/// `a/b` can not write a file outside the target folder.
String? generatorName(String input, [String suffix = '']) {
  String name = pascalToSnake(input);
  if (suffix.isNotEmpty) name = name.replaceAll(RegExp('_?$suffix\$'), '');
  if (RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) return name;
  print(
    '\x1B[31m"$input" is not a valid name. '
    'Use letters, digits and _ only, and start with a letter.\x1B[0m',
  );
  exitCode = 1;
  return null;
}

String snakeToPascal(String input) {
  final parts = input.split('_');
  final result = StringBuffer();
  for (final part in parts) {
    if (part.isNotEmpty) {
      result.write('${part[0].toUpperCase()}${part.substring(1)}');
    }
  }
  return result.toString().isEmpty ? input : result.toString();
}

String toPascalWithFirstLetterLowerCase(String input) {
  String pascalString = snakeToPascal(input);
  return '${pascalString[0].toLowerCase()}${pascalString.substring(1)}';
}

String parseName(String name) {
  DateTime now = DateTime.now();
  String uuid =
      '${now.year}_${_formatNumber(now.month)}_${_formatNumber(now.day)}_${_formatNumber(now.hour)}${_formatNumber(now.minute)}${_formatNumber(now.second)}${now.microsecond}';

  return "${uuid}_$name".replaceAll(RegExp(r'[^\w]'), "");
}

String _formatNumber(int number) {
  return number.toString().padLeft(2, '0');
}

String fileGetContents(String path) {
  return File(path).readAsStringSync();
}
