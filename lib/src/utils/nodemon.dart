import 'dart:io';

installNodemonIfNotExist() {
  try {
    var result = Process.runSync('nodemon', ['--version']);
    if (result.exitCode == 0 &&
        RegExp(r'^\d+\.\d+\.\d+').hasMatch(result.stdout.toString())) {
    } else {
      Process.runSync('npm', ['install', '-g', 'nodemon']);
    }
  } catch (error) {
    Process.runSync('npm', ['install', '-g', 'nodemon']);
  }
}
