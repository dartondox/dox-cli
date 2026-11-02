import '../command_registry.dart';
import '../types.dart';
import 'package_commands.dart';

Future<void> help() async {
  print("Usage: dox <command> [arguments] \n");
  print('Available commands: \n');

  final commands = CommandRegistry.getAllCommands();

  // Group commands by category
  final Map<CommandCategory, List<CommandDefinition>> categories = {};
  for (final command in commands) {
    final category = command.category;
    categories.putIfAbsent(category, () => []).add(command);
  }

  // Sort categories by their order property
  final sortedCategories = categories.keys.toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  for (final category in sortedCategories) {
    final displayName = category.displayName;
    print('\x1B[1m$displayName:\x1B[0m');

    // Sort commands alphabetically within each category
    final sortedCommands = categories[category]!
      ..sort((a, b) => a.command.compareTo(b.command));
    for (final command in sortedCommands) {
      final padding = ' ' * (30 - command.helpInfo.length);
      print('  ${command.helpInfo}$padding ${command.description}');
    }
    print('');
  }
  _printPackageCommands(await PackageCommands().list());
}

/// the commands of the packages and of the app, one group per package.
/// A built-in command with the same name always wins, so that one is
/// marked as not used.
void _printPackageCommands(List<PackageCommandInfo> commands) {
  Map<String, List<PackageCommandInfo>> packages = {};
  Map<String, int> count = {};
  for (PackageCommandInfo command in commands) {
    packages.putIfAbsent(command.package, () => []).add(command);
    count[command.name] = (count[command.name] ?? 0) + 1;
  }
  for (String package in packages.keys.toList()..sort()) {
    print('\x1B[1m$package:\x1B[0m');
    List<PackageCommandInfo> list = packages[package]!
      ..sort((a, b) => a.name.compareTo(b.name));
    for (PackageCommandInfo command in list) {
      String note = '';
      if (CommandRegistry.findCommand(command.name) != null) {
        note = ' (not used: a built-in command has this name)';
      } else if (count[command.name]! > 1) {
        note = ' (not used: more than one command has this name)';
      }
      final padding = ' ' * (30 - command.usage.length).clamp(1, 30);
      print('  ${command.usage}$padding ${command.description}$note');
    }
    print('');
  }
}

Future<void> helpCommand(String commandName) async {
  final command = CommandRegistry.findCommand(commandName);

  if (command == null) {
    for (PackageCommandInfo info in await PackageCommands().list()) {
      if (info.name != commandName) continue;
      print('\x1B[1mCommand:\x1B[0m ${info.name}');
      print('\x1B[1mUsage:\x1B[0m dox ${info.usage}');
      print('\x1B[1mDescription:\x1B[0m ${info.description}');
      print('\x1B[1mPackage:\x1B[0m ${info.package}');
      print('');
      return;
    }
    print('Command "$commandName" not found.');
    print('Run "dox help" to see all available commands.');
    return;
  }

  print('\x1B[1mCommand:\x1B[0m ${command.command}');
  print('\x1B[1mUsage:\x1B[0m dox ${command.helpInfo}');
  print('\x1B[1mDescription:\x1B[0m ${command.description}');
  print('\x1B[1mCategory:\x1B[0m ${command.category.displayName}');

  if (command.aliases.isNotEmpty) {
    print('\x1B[1mAliases:\x1B[0m ${command.aliases.join(', ')}');
  }

  if (command.minArgs > 0 || command.maxArgs != -1) {
    String argsInfo = '';
    if (command.minArgs == command.maxArgs) {
      argsInfo =
          '${command.minArgs} argument${command.minArgs == 1 ? '' : 's'}';
    } else if (command.maxArgs == -1) {
      argsInfo =
          'at least ${command.minArgs} argument${command.minArgs == 1 ? '' : 's'}';
    } else {
      argsInfo = '${command.minArgs} to ${command.maxArgs} arguments';
    }
    print('\x1B[1mArguments:\x1B[0m $argsInfo');
  }

  print('');
}
