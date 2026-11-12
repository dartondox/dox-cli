import 'dart:io';

import 'package:dox/src/tools/create_controller.dart';
import 'package:dox/src/tools/create_middleware.dart';
import 'package:dox/src/tools/create_migration.dart';
import 'package:dox/src/tools/create_model.dart';
import 'package:dox/src/tools/create_project.dart';
import 'package:dox/src/tools/app_scripts.dart';
import 'package:dox/src/tools/create_dto.dart';
import 'package:dox/src/tools/create_job.dart';
import 'package:dox/src/tools/make_files.dart';
import 'package:dox/src/tools/create_factory.dart';
import 'package:dox/src/tools/create_seeder.dart';
import 'package:dox/src/tools/create_serializer.dart';
import 'package:dox/src/tools/env_tools.dart';
import 'package:dox/src/tools/generate_key.dart';
import 'package:dox/src/tools/help.dart';
import 'package:dox/src/tools/openapi_generate.dart';
import 'package:dox/src/tools/route_list.dart';
import 'package:dox/src/tools/server_serve.dart';
import 'package:dox/src/tools/update_dox.dart';
import 'package:dox/src/utils/args.dart';
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
      helpInfo: 'make:model <model_name> [-m] [-c] [-r] [-f] [-s] [-a] [--api]',
      description:
          'Create a new model. -m migration, -c controller, -r resource '
          'controller, --api API resource controller, -f factory, -s seeder, '
          '-a all of them (-m -f -s -r). Join short flags: -mcr',
      category: CommandCategory.generation,
      aliases: ['create:model'],
      minArgs: 1,
      function: (args) async {
        ParsedArgs? parsed = parseArgs(
          'make:model',
          args,
          short: const <String, String>{
            'm': 'migration',
            'c': 'controller',
            'r': 'resource',
            'f': 'factory',
            's': 'seed',
            'a': 'all',
          },
          flags: const <String>{
            'migration',
            'controller',
            'resource',
            'api',
            'factory',
            'seed',
            'all',
          },
        );
        if (parsed == null) return;
        String name = parsed.names.first;
        Set<String> flags = parsed.flags;
        if (flags.contains('all')) {
          flags.addAll(<String>['migration', 'factory', 'seed', 'resource']);
        }

        /// `BlogPost` => table `blog_posts`, same guess as `constrained()`
        String table = ForeignIdColumnDefinition.guessTable(
          pascalToSnake(name),
        );

        /// like Laravel: when the model exists, nothing else is made
        if (!createModel(name, table: table)) return;

        /// the same files as the single commands make for this model:
        /// make:factory, make:migration, make:seeder and make:controller
        if (flags.contains('factory')) createFactory(name);
        if (flags.contains('migration')) {
          createMigration('create_${table}_table');
        }
        if (flags.contains('seed')) createSeeder(name);
        bool api = flags.contains('api');
        bool resource = api || flags.contains('resource');
        if (resource || flags.contains('controller')) {
          createController(
            name,
            resource,
            api: api,
            model: resource ? name : null,
          );
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
      helpInfo:
          'make:controller <controller_name> [-r|--resource] [--api] '
          '[--model=<model>]',
      description:
          'Create a new controller. -r or --resource: a resource controller. '
          '--api: a resource controller without create and edit. '
          '--model=Post: the actions use the Post model',
      category: CommandCategory.development,
      minArgs: 1,
      function: (args) async {
        ParsedArgs? parsed = parseArgs(
          'make:controller',
          args,
          short: const <String, String>{'r': 'resource'},
          flags: const <String>{'resource', 'api'},
          options: const <String>{'model'},
        );
        if (parsed == null) return;
        String? model = parsed.options['model'];

        /// like Laravel: --api and --model make a resource controller
        bool api = parsed.flags.contains('api');
        bool resource =
            api || model != null || parsed.flags.contains('resource');
        createController(parsed.names.first, resource, api: api, model: model);
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

    CommandDefinition(
      command: 'make:provider',
      helpInfo: 'make:provider <provider_name>',
      description: 'Create a provider in lib/providers',
      category: CommandCategory.development,
      minArgs: 1,
      function: (args) async {
        createProvider(args);
      },
    ),

    CommandDefinition(
      command: 'make:command',
      helpInfo: 'make:command <command_name>',
      description: 'Create a dox command in lib/app/commands and add it to the commands list',
      category: CommandCategory.development,
      minArgs: 1,
      function: (args) async {
        createCommand(args);
      },
    ),

    CommandDefinition(
      command: 'make:mail',
      helpInfo: 'make:mail <mail_name> [--no-view]',
      description: 'Create a Mailable in lib/app/mail and its view. --no-view: a plain text body, no view',
      category: CommandCategory.development,
      minArgs: 1,
      function: (args) async {
        createMail(args);
      },
    ),

    CommandDefinition(
      command: 'make:view',
      helpInfo: 'make:view <view_name>',
      description: 'Create a .dox.html view in resources/views (emails/welcome makes a folder)',
      category: CommandCategory.development,
      minArgs: 1,
      function: (args) async {
        createView(args);
      },
    ),

    CommandDefinition(
      command: 'make:test',
      helpInfo: 'make:test <test_name> [--unit]',
      description: 'Create a test in test/ that uses DoxTestClient. --unit: a plain test',
      category: CommandCategory.development,
      minArgs: 1,
      function: (args) async {
        createTest(args);
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

    // Route list
    CommandDefinition(
      command: 'route:list',
      helpInfo: 'route:list [--json]',
      description: 'List every route of the app (does not start the server)',
      category: CommandCategory.development,
      maxArgs: 1,
      function: (args) async {
        await RouteList().run(args);
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
      helpInfo:
          'migration:rollback [--step=<count>] [--batch=<number>] [--force]',
      description:
          'Rollback the last batch, the last <count> migrations with --step, '
          'or one batch with --batch',
      category: CommandCategory.database,
      aliases: ['migrate:rollback'],
      maxArgs: 3,
      function: (args) async {
        Map<String, int> options = <String, int>{};
        for (int i = 0; i < args.length; i++) {
          String arg = args[i];
          if (arg == '--force') continue;
          String? name;
          String? value;
          for (String option in <String>['step', 'batch']) {
            if (arg.startsWith('--$option=')) {
              name = option;
              value = arg.substring(option.length + 3);
            } else if (arg == '--$option' && i + 1 < args.length) {
              // `--step 2`, with a space
              name = option;
              value = args[++i];
            }
          }
          int? count = value == null ? null : int.tryParse(value);
          if (name == null || count == null || count < 1) {
            print(
              'Invalid option $arg, use --step=<count>, --batch=<number> '
              'or --force',
            );
            exitCode = 1;
            return;
          }
          if (options.containsKey(name)) {
            print('--$name is given more than once. Give it once.');
            exitCode = 1;
            return;
          }
          options[name] = count;
        }
        if (options.length > 1) {
          print('Give --step or --batch, not both.');
          exitCode = 1;
          return;
        }
        int? step = options['step'];
        int? batch = options['batch'];
        await _migration(
          'rollback',
          <String>[
            if (args.contains('--force')) '--force',
            if (step != null) '--step=$step',
            if (batch != null) '--batch=$batch',
          ],
          () => Migrator().rollback(step: step, batch: batch),
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
          '--tries, --timeout, --sleep, --stop-when-empty, --backoff, '
          '--max-jobs, --max-time, --memory',
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
      command: 'queue:clear',
      helpInfo: 'queue:clear [queue]',
      description: 'Delete the jobs of a queue (default queue: default)',
      category: CommandCategory.queue,
      maxArgs: 1,
      function: (args) async {
        await runQueue('clear', args);
      },
    ),

    CommandDefinition(
      command: 'queue:restart',
      helpInfo: 'queue:restart',
      description:
          'Tell the running workers to stop after their current job. '
          'Needs a shared cache store',
      category: CommandCategory.queue,
      maxArgs: 0,
      function: (args) async {
        await runQueue('restart', args);
      },
    ),

    CommandDefinition(
      command: 'queue:prune-failed',
      helpInfo: 'queue:prune-failed [--hours=N]',
      description: 'Delete failed jobs older than N hours (default 24)',
      category: CommandCategory.queue,
      maxArgs: 2,
      function: (args) async {
        // `--hours 48`, with a space, is sent as `--hours=48`
        if (args.length == 2 && args.first == '--hours') {
          args = <String>['--hours=${args[1]}'];
        }
        // maxArgs is 2 only for `--hours 48`; any other second word stops
        if (args.length > 1) {
          print('Invalid arguments for command "queue:prune-failed".');
          print('Usage: queue:prune-failed [--hours=N]');
          exitCode = 1;
          return;
        }
        await runQueue('prune-failed', args);
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

    CommandDefinition(
      command: 'schedule:clear-cache',
      helpInfo: 'schedule:clear-cache',
      description: 'Remove the withoutOverlapping() locks left by a crash',
      category: CommandCategory.schedule,
      maxArgs: 0,
      function: (args) async {
        await runSchedule('clear-cache', args);
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
