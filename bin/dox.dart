import 'dart:io';

import 'package:dox/src/command_registry.dart';
import 'package:dox/src/tools/package_commands.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Could not find a command. Run `dox help` for more information.');
    exitCode = 1;
    return;
  }

  final command = args[0];
  final commandArgs = args.skip(1).toList();

  try {
    await _executeCommand(command, commandArgs);
  } catch (e) {
    print(e);
    exitCode = 1;
  }
}

Future<void> _executeCommand(String command, List<String> args) async {
  final commandDefinition = CommandRegistry.findCommand(command);

  /// not built in: a command of a package or of the app
  if (commandDefinition == null) {
    int? code = await PackageCommands().run(command, args);
    if (code == null) {
      print(notFoundMessage(command));
      exitCode = 1;
    } else if (code != 0) {
      exitCode = code;
    }
    return;
  }

  if (!commandDefinition.validateArgs(args)) {
    print('Invalid number of arguments for command "$command".');
    print(
      'Expected: ${commandDefinition.minArgs}${commandDefinition.maxArgs != -1 ? ' to ${commandDefinition.maxArgs}' : '+'} arguments',
    );
    print('Received: ${args.length} arguments');
    exitCode = 1;
    return;
  }

  try {
    await commandDefinition.function(args);
  } catch (e) {
    print(e);
    exitCode = 1;
  }
}
