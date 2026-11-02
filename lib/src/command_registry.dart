import 'dart:io';

import 'package:dox/src/tools/create_controller.dart';
import 'package:dox/src/tools/create_middleware.dart';
import 'package:dox/src/tools/create_migration.dart';
import 'package:dox/src/tools/create_model.dart';
import 'package:dox/src/tools/create_project.dart';
import 'package:dox/src/tools/app_scripts.dart';
import 'package:dox/src/tools/create_dto.dart';
import 'package:dox/src/tools/create_job.dart';
import 'package:dox/src/tools/create_factory.dart';
import 'package:dox/src/tools/create_seeder.dart';
import 'package:dox/src/tools/create_serializer.dart';
import 'package:dox/src/tools/env_tools.dart';
import 'package:dox/src/tools/generate_key.dart';
import 'package:dox/src/tools/help.dart';
import 'package:dox/src/tools/openapi_generate.dart';
import 'package:dox/src/tools/server_serve.dart';
import 'package:dox/src/tools/update_dox.dart';
import 'package:dox/src/utils/confirm_drop.dart';
import 'package:dox/src/utils/run_script.dart';
import 'package:dox/src/utils/utils.dart';
import 'package:dox/src/version.dart';
import 'package:dox_migration/dox_migration.dart';

import 'types.dart';

/// Example of how to add a new command:
///
/// ```dart
/// CommandRegistry.addCommand(
///   CommandDefinition(
///     command: 'new:command',
///     helpInfo: 'new:command <arg1> [arg2]',
///     description: 'Description of what this command does',
///     category: CommandCategory.generation,
///     minArgs: 1,
///     maxArgs: 2,
///     aliases: ['nc', 'new'],
///     function: (args) async {
///       // Your command implementation here
///       print('Executing new command with args: $args');
///     },
///   ),
/// );
/// ```
class CommandRegistry {
  static final List<CommandDefinition> _commands = [
    // Version commands
    CommandDefinition(
      command: 'version',
      helpInfo: 'version or v',
      description: 'Show Dox version',
      category: CommandCategory.system,
      aliases: ['--version', '-version', 'v', '-v', '--v'],
      function: (args) async {
        print('Dox version: $version');
      },
    ),

    // Create project
    CommandDefinition(
      command: 'create',
      helpInfo: 'create <project_name> [--version <version>]',
      description: 'Create a new Dox project',
      category: CommandCategory.project,
      minArgs: 1,
      maxArgs: 3,
      function: (args) async {
        final projectName = args[0];
        // `dox create blog` has no flag: args[1] would throw a RangeError
        final flag = args.length >= 2 ? args[1] : null;
        bool isVersionFlag = flag == '--version' || flag == '--v';
        final version = args.length >= 3 && isVersionFlag ? args[2] : null;
        await createProject(projectName, version);
      },
    ),

    // Create model
    CommandDefinition(
      command: 'make:model',
      helpInfo: 'make:model <model_name> [-m|--migration]',
      description:
          'Create a new model, and with -m a create_<table>_table migration',
      category: CommandCategory.generation,
      aliases: ['create:model'],
      minArgs: 1,
      maxArgs: 2,
      function: (args) async {
        if (args.length < 2) {
          createModel(args[0]);
          return;
        }
        if (args[1] != '-m' && args[1] != '--migration') {
          print('Invalid option ${args[1]}, use -m or --migration');
          exitCode = 1;
          return;
        }

        /// `BlogPost` => table `blog_posts`, same guess as `constrained()`
        String table = ForeignIdColumnDefinition.guessTable(
          pascalToSnake(args[0]),
        );
        if (createModel(args[0], table: table)) {
          createMigration('create_${table}_table');
        }
      },
    ),

    // Serve commands
    CommandDefinition(
      command: 'serve',
      helpInfo: 'serve or s [--ignore-build-runner]',
      description: 'Start the development server',
      category: CommandCategory.development,
      aliases: ['server', 's'],
      minArgs: 0,
      maxArgs: 1,
      function: (args) async {
        if (args.isNotEmpty && args[0] != '--ignore-build-runner') {
          print(serveOptionWarning(args[0]));
        }
        if (args.isNotEmpty && args[0] == '--ignore-build-runner') {
          serverServe();
        } else {
          watchBuilder();
          serverServe();
        }
      },
    ),

    // Build runner commands
    CommandDefinition(
      command: 'build_runner:watch',
      helpInfo: 'build_runner:watch',
      description: 'Watch and run build runner',
      category: CommandCategory.buildRunner,
      function: (args) async {
        watchBuilder();
      },
    ),

    CommandDefinition(
      command: 'build_runner:build',
      helpInfo: 'build_runner:build',
      description: 'Run build runner once',
      category: CommandCategory.buildRunner,
      function: (args) async {
        exitCode = await buildBuilder();
      },
    ),

    CommandDefinition(
      command: 'build',
      helpInfo: 'build',
      description: 'AOT compile the app for production into build/bundle (use this, not dart run, in production)',
      category: CommandCategory.build,
      function: (args) async {
        await buildServer();
      },
    ),

    // Update command
    CommandDefinition(
      command: 'update',
      helpInfo: 'update',
      description: 'Update Dox framework',
      category: CommandCategory.system,
      function: (args) async {
        await updateDox();
      },
    ),

    // Create controller commands
    CommandDefinition(
      command: 'make:controller',
      aliases: ['create:controller'],
      helpInfo: 'make:controller <controller_name> [-r]',
      description: 'Create a new controller',
      category: CommandCategory.development,
      minArgs: 1,
      maxArgs: 2,
      function: (args) async {
        final controllerName = args[0];
        final isResource = args.length >= 2 && args[1] == '-r';
        createController(controllerName, isResource);
      },
    ),

    // Create middleware command
    CommandDefinition(
      command: 'make:middleware',
      aliases: ['create:middleware'],
      helpInfo: 'make:middleware <middleware_name>',
      description: 'Create a new middleware',
      category: CommandCategory.development,
      minArgs: 1,
      maxArgs: 1,
      function: (args) async {
        createMiddleware(args[0]);
      },
    ),

    // Create DTO command
    CommandDefinition(
      command: 'make:dto',
      aliases: ['create:dto'],
      helpInfo: 'make:dto <dto_name>',
      description: 'Create a new DTO (typed, checked input)',
      category: CommandCategory.development,
      minArgs: 1,
      maxArgs: 1,
      function: (args) async {
        createDto(args[0]);
      },
    ),

    // Create serializer command
    CommandDefinition(
      command: 'make:serializer',
      aliases: ['create:serializer'],
      helpInfo: 'make:serializer <serializer_name>',
      description: 'Create a new serializer',
      category: CommandCategory.generation,
      minArgs: 1,
      maxArgs: 1,
      function: (args) async {
        createSerializer(args[0]);
      },
    ),

    // Key generation command
    CommandDefinition(
      command: 'key:generate',
      helpInfo: 'key:generate [--show] [--force]',
      description:
          'Generate application key (--show prints one and writes nothing)',
      category: CommandCategory.generation,
      function: (args) async {
        int code = generateKey(args);
        if (code != 0) exitCode = code;
      },
    ),

    // Typed env
    CommandDefinition(
      command: 'env:generate',
      helpInfo: 'env:generate',
      description:
          'Make lib/config/env.dart (typed env class) from .env.example',
      category: CommandCategory.generation,
      function: (args) async {
        envGenerate();
      },
    ),

    CommandDefinition(
      command: 'env:check',
      helpInfo: 'env:check',
      description: 'Check the env against lib/config/env.dart and print missing or bad keys',
      category: CommandCategory.system,
      function: (args) async {
        await envCheck();
      },
    ),

    // OpenAPI
    CommandDefinition(
      command: 'openapi:generate',
      helpInfo: 'openapi:generate [dir]',
      description: 'Write openapi.json and openapi.yaml (runs bin/openapi.dart, default dir storage/openapi)',
      category: CommandCategory.generation,
      maxArgs: 1,
      function: (args) async {
        await openApiGenerate(args);
      },
    ),

    // Help command
    CommandDefinition(
      command: 'help',
      helpInfo: 'help [command]',
      description: 'Show help information',
      category: CommandCategory.system,
      aliases: ['--help', '-h'],
      minArgs: 0,
      maxArgs: 1,
      function: (args) async {
        if (args.isNotEmpty) {
          await helpCommand(args[0]);
        } else {
          await help();
        }
      },
    ),

    // Migration commands
    CommandDefinition(
      command: 'migration:run',
      helpInfo: 'migration:run [--seed]',
      description: 'Run pending migrations, then the seeders with --seed',
      category: CommandCategory.database,
      aliases: ['migrate'],
      function: (args) async {
        await _migration('run', args, () => Migrator().migrate());
      },
    ),

    CommandDefinition(
      command: 'migration:rollback',
      helpInfo: 'migration:rollback [--step=<count>] [--force]',
      description:
          'Rollback the last batch, or the last <count> migrations with --step',
      category: CommandCategory.database,
      aliases: ['migrate:rollback'],
      maxArgs: 3,
      function: (args) async {
        int? step;
        for (int i = 0; i < args.length; i++) {
          String arg = args[i];
          if (arg == '--force') continue;
          String? value;
          if (arg.startsWith('--step=')) {
            value = arg.substring(7);
          } else if (arg == '--step' && i + 1 < args.length) {
            // `--step 2`, with a space
            value = args[++i];
          }
          int? count = value == null ? null : int.tryParse(value);
          if (count == null || count < 1) {
            print('Invalid option $arg, use --step=<count> or --force');
            exitCode = 1;
            return;
          }
          if (step != null) {
            print('--step is given more than once. Give it once.');
            exitCode = 1;
            return;
          }
          step = count;
        }
        await _migration(
          'rollback',
          <String>[
            if (args.contains('--force')) '--force',
            if (step != null) '--step=$step',
          ],
          () => Migrator().rollback(step: step),
          danger: 'This rolls back migrations, so it can drop tables and data.',
        );
      },
    ),

    CommandDefinition(
      command: 'migration:reset',
      helpInfo: 'migration:reset [--force]',
      description: 'Rollback all migrations',
      category: CommandCategory.database,
      aliases: ['migrate:reset'],
      function: (args) async {
        await _migration(
          'reset',
          args,
          () => Migrator().reset(),
          danger: 'This drops all tables.',
        );
      },
    ),

    CommandDefinition(
      command: 'migration:refresh',
      helpInfo: 'migration:refresh [--seed] [--force]',
      description: 'Rollback all migrations and run them again',
      category: CommandCategory.database,
      aliases: ['migrate:refresh'],
      function: (args) async {
        await _migration(
          'refresh',
          args,
          () => Migrator().refresh(),
          danger: 'This drops all tables.',
        );
      },
    ),

    CommandDefinition(
      command: 'migration:fresh',
      helpInfo: 'migration:fresh [--seed] [--force]',
      description: 'Drop all tables and run all migrations again',
      category: CommandCategory.database,
      aliases: ['migrate:fresh'],
      function: (args) async {
        await _migration(
          'fresh',
          args,
          () => Migrator().fresh(),
          danger: 'This drops all tables.',
        );
      },
    ),

    CommandDefinition(
      command: 'migration:status',
      helpInfo: 'migration:status',
      description: 'Show which migrations ran, and their batch',
      category: CommandCategory.database,
      aliases: ['migrate:status'],
      function: (args) async {
        await _migration(
          'status',
          args,
          () async => Migrator.printStatus(await Migrator().status()),
        );
      },
    ),

    CommandDefinition(
      command: 'make:migration',
      helpInfo: 'make:migration <name> [--sql]',
      description:
          'Create a Dart migration (or a .sql one with --sql) in db/migration',
      category: CommandCategory.database,
      aliases: ['create:migration'],
      minArgs: 1,
      maxArgs: 2,
      function: (args) async {
        createMigration(args[0], sql: args.length >= 2 && args[1] == '--sql');
      },
    ),

    CommandDefinition(
      command: 'make:factory',
      helpInfo: 'make:factory <model_name>',
      description: 'Create a model factory in db/factories',
      category: CommandCategory.database,
      aliases: ['create:factory'],
      minArgs: 1,
      maxArgs: 1,
      function: (args) async {
        createFactory(args[0]);
      },
    ),

    CommandDefinition(
      command: 'make:seeder',
      helpInfo: 'make:seeder <seeder_name>',
      description: 'Create a seeder in db/seeders (and bin/seed.dart)',
      category: CommandCategory.database,
      aliases: ['create:seeder'],
      minArgs: 1,
      maxArgs: 1,
      function: (args) async {
        createSeeder(args[0]);
      },
    ),

    CommandDefinition(
      command: 'db:seed',
      helpInfo: 'db:seed [--class=<name>]',
      description: 'Run DatabaseSeeder, or another seeder with --class',
      category: CommandCategory.database,
      // `--class=UserSeeder` is one argument, `--class UserSeeder` is two
      maxArgs: 2,
      function: (args) async {
        await _seed(args);
      },
    ),
    CommandDefinition(
      command: 'make:job',
      helpInfo: 'make:job <job_name>',
      description: 'Create a queue job in lib/app/jobs (and bin/queue.dart)',
      category: CommandCategory.queue,
      minArgs: 1,
      maxArgs: 1,
      function: (args) async {
        createJob(args[0]);
      },
    ),

    CommandDefinition(
      command: 'queue:work',
      helpInfo: 'queue:work [flags]',
      description:
          'Run the queue worker. Flags: --queue, --concurrency, --once, '
          '--tries, --timeout, --sleep, --stop-when-empty',
      category: CommandCategory.queue,
      function: (args) async {
        await runQueue('work', args);
      },
    ),

    CommandDefinition(
      command: 'queue:failed',
      helpInfo: 'queue:failed',
      description: 'List the failed jobs',
      category: CommandCategory.queue,
      maxArgs: 0,
      function: (args) async {
        await runQueue('failed', args);
      },
    ),

    CommandDefinition(
      command: 'queue:retry',
      helpInfo: 'queue:retry <id|all>',
      description: 'Put a failed job (or all of them) back on the queue',
      category: CommandCategory.queue,
      minArgs: 1,
      maxArgs: 1,
      function: (args) async {
        await runQueue('retry', args);
      },
    ),

    CommandDefinition(
      command: 'queue:forget',
      helpInfo: 'queue:forget <id>',
      description: 'Delete one failed job',
      category: CommandCategory.queue,
      minArgs: 1,
      maxArgs: 1,
      function: (args) async {
        await runQueue('forget', args);
      },
    ),

    CommandDefinition(
      command: 'queue:flush',
      helpInfo: 'queue:flush',
      description: 'Delete all failed jobs',
      category: CommandCategory.queue,
      maxArgs: 0,
      function: (args) async {
        await runQueue('flush', args);
      },
    ),

    CommandDefinition(
      command: 'schedule:work',
      helpInfo: 'schedule:work',
      description: 'Run the scheduler and keep it running',
      category: CommandCategory.schedule,
      maxArgs: 0,
      function: (args) async {
        await runSchedule('work', args);
      },
    ),

    CommandDefinition(
      command: 'schedule:run',
      helpInfo: 'schedule:run',
      description: 'Run the tasks that are due now, once',
      category: CommandCategory.schedule,
      maxArgs: 0,
      function: (args) async {
        await runSchedule('run', args);
      },
    ),

    CommandDefinition(
      command: 'schedule:list',
      helpInfo: 'schedule:list',
      description: 'List the scheduled tasks',
      category: CommandCategory.schedule,
      maxArgs: 0,
      function: (args) async {
        await runSchedule('list', args);
      },
    ),

    CommandDefinition(
      command: 'schedule:test',
      helpInfo: 'schedule:test <name>',
      description: 'Run one scheduled task now',
      category: CommandCategory.schedule,
      minArgs: 1,
      maxArgs: 1,
      function: (args) async {
        await runSchedule('test', args);
      },
    ),
  ];

  static CommandDefinition? findCommand(String command) {
    try {
      return _commands.firstWhere((cmd) => cmd.matches(command));
    } catch (e) {
      return null;
    }
  }

  static List<CommandDefinition> getAllCommands() {
    return _commands;
  }

  static void addCommand(CommandDefinition command) {
    _commands.add(command);
  }
}

/// The production check before a migration command that can drop data.
/// Tests replace it.
bool Function({required bool force, String danger}) confirmDrop =
    confirmDropAll;

/// run a migration command.
/// - with `bin/migrate.dart` (Dart migrations): make the registry again,
///   then run `dart run bin/migrate.dart <command>`, so the app code runs.
/// - without it: run the `.sql` migrations here with [direct].
/// `--seed` in [args] runs the seeders after it, see [_seed].
/// print the error and set exit code 1 when it fails,
/// so scripts and CI see the failure.
/// [danger]: the command can drop data, so check [confirmDrop] first.
/// `--force` skips the question. `--force` is never passed on, also not
/// for a command without [danger] (like `dox migrate --force`).
Future<void> _migration(
  String command,
  List<String> args,
  Future<void> Function() direct, {
  String? danger,
}) async {
  bool seed = args.contains('--seed');
  bool force = args.contains('--force');
  args = args.where((String a) => a != '--seed' && a != '--force').toList();
  if (danger != null && !confirmDrop(force: force, danger: danger)) {
    print('Stopped. No table was dropped.');
    exitCode = 1;
    return;
  }

  /// a package command (like `dox queue:table`) can add the first Dart
  /// migration with no bin/migrate.dart: make it, like make:migration
  if (!migrateEntryFile().existsSync() && hasDartMigrations()) {
    writeMigrateEntry();
  }
  if (migrateEntryFile().existsSync()) {
    writeMigrationRegistry();
    int code = await runScript('bin/migrate.dart', <String>[command, ...args]);
    if (code != 0) {
      exitCode = code;
      return;
    }
  } else {
    try {
      await direct();
    } catch (error) {
      print(error);
      exitCode = 1;
      return;
    }
  }
  if (seed) await _seed(<String>[]);
}

/// `dox db:seed`: make `db/seeders/seeders.dart` again, then run
/// `dart run bin/seed.dart [--class=<name>]`
Future<void> _seed(List<String> args) async {
  if (!seedEntryFile().existsSync()) {
    print(
      'bin/seed.dart is missing. '
      'Run `dox make:seeder DatabaseSeeder` once to make it, or see the docs.',
    );
    exitCode = 1;
    return;
  }
  writeSeederRegistry();
  int code = await runScript('bin/seed.dart', args);
  if (code != 0) exitCode = code;
}
