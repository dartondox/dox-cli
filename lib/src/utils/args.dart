import 'dart:io';

/// The words of a command, split into names and flags.
class ParsedArgs {
  /// the words that are not flags, like the model name
  final List<String> names;

  /// the long names of the flags that are given, like `migration`
  final Set<String> flags;

  /// the flags with a value, like `{'model': 'Post'}`
  final Map<String, String> options;

  ParsedArgs(this.names, this.flags, this.options);
}

/// Read the [args] of [command], Laravel style.
///
/// - [short] maps one letter to a long name, like `m` to `migration`.
///   Letters can be joined: `-mcr` is the same as `-m -c -r`.
/// - [flags] are long names without a value: `--migration`.
/// - [options] are long names with a value: `--model=Post` or
///   `--model Post`.
/// - [names] is how many words that are not flags the command takes.
///
/// An unknown flag, a missing value or a wrong number of names prints an
/// error, sets exit code 1 and returns null.
ParsedArgs? parseArgs(
  String command,
  List<String> args, {
  Map<String, String> short = const <String, String>{},
  Set<String> flags = const <String>{},
  Set<String> options = const <String>{},
  int names = 1,
}) {
  List<String> words = <String>[];
  Set<String> given = <String>{};
  Map<String, String> values = <String, String>{};
  String? error;
  for (int i = 0; i < args.length && error == null; i++) {
    String arg = args[i];
    if (arg.startsWith('--')) {
      int eq = arg.indexOf('=');
      String name = arg.substring(2, eq == -1 ? null : eq);
      if (options.contains(name)) {
        String? value = eq != -1
            ? arg.substring(eq + 1)
            : (i + 1 < args.length ? args[++i] : null);
        if (value == null || value.isEmpty || value.startsWith('-')) {
          error = '--$name needs a value, like --$name=Post.';
        } else {
          values[name] = value;
        }
      } else if (flags.contains(name) && eq == -1) {
        given.add(name);
      } else {
        error = 'Unknown option $arg for $command.';
      }
    } else if (arg.startsWith('-') && arg.length > 1) {
      for (String letter in arg.substring(1).split('')) {
        String? name = short[letter];
        if (name == null) {
          error = 'Unknown option -$letter for $command.';
          break;
        }
        given.add(name);
      }
    } else if (arg == '-') {
      error = 'Unknown option - for $command.';
    } else {
      words.add(arg);
    }
  }
  if (error == null && words.length != names) {
    error =
        '$command takes $names name${names == 1 ? '' : 's'}, '
        'got ${words.length}: ${words.join(' ')}';
  }
  if (error != null) {
    print('\x1B[31m$error Run `dox help $command` to see the options.\x1B[0m');
    exitCode = 1;
    return null;
  }
  return ParsedArgs(words, given, values);
}
