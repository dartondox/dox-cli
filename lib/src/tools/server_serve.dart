import 'dart:convert';
import 'dart:io';

serverServe() async {
  var process = await Process.start(
      'nodemon', ['-x', "dart run bin/server.dart", '-e', 'dart']);

  // Listen for output from the process
  process.stdout.transform(utf8.decoder).listen((data) {
    List lines = data.split("\n");
    for (String line in lines) {
      if (line.isNotEmpty) {
        print(line.replaceAll('nodemon', 'dox'));
      }
    }
  });

  process.stderr.transform(utf8.decoder).listen((data) {
    List lines = data.split("\n");
    for (String line in lines) {
      if (line.isNotEmpty) {
        print(line.replaceAll('nodemon', 'dox'));
      }
    }
  });

  var exitCode = await process.exitCode;
  print('Process exited with code $exitCode');
}

watchBuilder() async {
  var process = await Process.start('dart', ['run', 'build_runner', 'watch']);

  process.stderr.transform(utf8.decoder).listen((data) {
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

buildBuilder() async {
  var process = await Process.start('dart', ['run', 'build_runner', 'build']);
  process.stdout.transform(utf8.decoder).listen((data) {
    List lines = data.split("\n");
    print(lines.first.toString().replaceAll('INFO', 'dox'));
  });

  process.stderr.transform(utf8.decoder).listen((data) {
    List lines = data.split("\n");
    for (String line in lines) {
      if (line.isNotEmpty) {
        print(line);
      }
    }
  });
}

buildServer() async {
  var process = await Process.start(
      'dart', ['compile', 'exe', 'bin/server.dart', '-o', 'bin/server']);

  process.stdout.transform(utf8.decoder).listen((data) {
    List lines = data.split("\n");
    print(lines.first.toString().replaceAll('INFO', 'dox'));
  });

  process.stderr.transform(utf8.decoder).listen((data) {
    List lines = data.split("\n");
    for (String line in lines) {
      if (line.isNotEmpty) {
        print(line);
      }
    }
  });
}
