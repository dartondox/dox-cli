import 'dart:convert';
import 'dart:io';

serverServe() async {
  var process = await Process.start(
      'nodemon', ['-x', "dart run main.dart", '-e', 'dart']);

  // Listen for output from the process
  process.stdout.transform(utf8.decoder).listen((data) {
    List lines = data.split("\n");
    for (String line in lines) {
      if (line.isNotEmpty) {
        print(line);
      }
    }
  });

  var exitCode = await process.exitCode;
  print('Process exited with code $exitCode');
}
