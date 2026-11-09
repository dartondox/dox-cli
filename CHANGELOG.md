## Unreleased

- New: `dox migration:rollback --batch=3` (or `--batch 3`) rolls back only the migrations of batch 3. It is passed on to `bin/migrate.dart`, like `--step`. It needs a dox_migration with `rollback --batch`. Give `--step` or `--batch`, not both.

## 3.1.1

- Change: `dox make:serializer` now makes the file in `lib/app/serializers/` (before: `lib/app/http/serializers/`). Serializers are used by more than HTTP (MCP, websocket). The model import in the file is now a package import: `package:<app>/app/models/<name>/<name>.model.dart`. The app name comes from `pubspec.yaml`. Without a name, the command prints a message and stops (same as `dox make:factory`).

## 3.1.0

- New: `dox queue:clear [queue]`, `dox queue:restart` and `dox queue:prune-failed [--hours=N]`. They run `bin/queue.dart clear|restart|prune-failed`. They need a dox_queue that has these commands. `dox help queue:work` now also lists `--backoff`, `--max-jobs`, `--max-time` and `--memory`.
- Fix: another `dox` can delete `.dart_tool/dox/commands.dart` while this run reads it. This run crashed then. Now it writes the file again from the cache and goes on.
- Fix: an unknown command in an app with package commands (like an app with dox_queue) now exits with code 1. Before, it printed "Could not find a command" and exited with 0. An app that already has `.dart_tool/dox/commands.dart` gets the new file on the next run.
- Fix: the model from `dox make:model` has no `unintended_html_in_doc_comment` info any more. The `<String>[...]` example in its doc comment is now in backticks.
- New: package commands. A package (or the app) adds `dox` commands with the `dox: commands:` key in its pubspec.yaml, like `dox: {commands: package:dox_queue/commands.dart}`. `dox <name>` finds them when the name is not a built-in command. It reads `.dart_tool/package_config.json`, writes `.dart_tool/dox/commands.dart`, and runs it with `dart run`. The exit code of the command is the exit code of `dox`. The file is written again only when package_config.json or a pubspec.yaml change.
- A built-in command always wins. Two packages with the same command name print an error (exit code 1). A bad `dox: commands:` key prints a warning, and the other packages still work.
- `dox help` lists the package commands, one group per package. `dox help <name>` shows one package command. Outside an app, or when no package has commands, it does not start Dart.
- An unknown command now also prints a hint about the `dox: commands:` key.
- `dox migrate` (and the other `migration:*` commands) now makes `bin/migrate.dart` when it is missing and `db/migration` has Dart migrations, then goes on. Before, it stopped with "bin/migrate.dart is missing". So a migration that a package command wrote (like `dox queue:table`) runs with `dox migrate`.
- The commands are found in an app inside a pub workspace too. A member finds the workspace root from `.dart_tool/pub/workspace_ref.json` (so a glob like `apps/*` works).
- The file is also written again when the pubspec.yaml of any package changes (like a path dependency), with no `dart pub get`. A run with warnings (like a commands library that is not there yet) is not cached, so a fix counts on the next run. The files are written with write-then-rename.
- A `dox: commands:` value must be a plain path like `package:<name>/<path>.dart` (no `..`, no quotes). Else the package is skipped with a warning.
- Only the packages that the app uses count (from `.dart_tool/package_graph.json`). In a pub workspace, an app does not see the commands of other members.
- A commands library that is removed after the cache was made is skipped with a warning on the next run. The other packages still work.
- `dox help <name>` says when more than one command has that name.
- When a package command throws, `dox` prints the error and its stack trace, and exits with code 1.
- Now depends on `crypto` and `yaml` directly (they were already used through other packages).
- Safety: `dox migration:fresh`, `migration:reset` and `migration:refresh` drop all tables. When `APP_ENV=production` and stdin is a terminal, they now ask first. Any answer other than `y` stops with exit code 1. `--force` skips the question. Without a terminal (CI, deploy scripts) they print a warning and run as before.
- Fix: `dox` exited with code 0 when there was no command, the command was unknown, the arguments were wrong, or the command threw. Now it exits with code 1, so scripts and CI see the failure.
- Fix: `dox make:model Post` wrote `@DoxModel()`, so the ORM read the table `post`. But `make:model Post -m` makes the table `posts`. Now the model always gets the same plural table: `@DoxModel(table: 'posts')`.
- The `make:model` stub now has an empty `fillable` list with a comment. A model is guarded by default, so `create(req.body)` throws `MassAssignmentException` until you list the columns there.
- `dox serve --port=8080` (or any other unknown option) was ignored with no message. Now it prints a warning that says to set `APP_PORT` in `.env` (or run `APP_PORT=8080 dox serve`). The server still starts, as before.
- Safety: `dox migration:rollback` now has the same production check as `migration:fresh`. When `APP_ENV=production` and stdin is a terminal, it asks first. `--force` skips the question, like `migration:rollback --step=2 --force`.
- `dox migrate --force` (and the other `migration:*` commands without the check) still takes `--force` with no error. It does nothing there and is not passed on to `bin/migrate.dart`.
- Safety: `dox key:generate` changes `APP_KEY`, which logs out every user. When `APP_ENV=production` and stdin is a terminal, it now asks first, like `migration:fresh`. Any answer other than `y` stops with exit code 1 and changes nothing. `--force` skips the question. Without a terminal (CI, deploy scripts) it prints a warning and changes the key as before. Outside production it works as before.
- New: `dox key:generate --show` prints a new key and writes nothing. An unknown option is still ignored, as before, but now it prints a warning to stderr, so `KEY=$(dox key:generate --show)` holds only the key.
- Fix: `dox migration:rollback --step 2` (with a space) was rejected. Now it works, like `--step=2`. `--step` given twice (like `--step=2 --step=3`) used the last value with no message. Now it prints an error and exits with code 1.
- Fix: the `dox serve` warning for an unknown option always said `APP_PORT=8080`. Now it shows the port of `--port=<number>`, like `APP_PORT=3000` for `--port=3000`. Any other option still shows 8080.

## 3.0.1

- Fix: when only `dox serve` got SIGTERM or SIGINT (eg. `kill <pid>` from a script), the server and `build_runner watch` it started kept running and held the port. Now dox stops them first, waits up to 5 seconds, then exits. Ctrl+C in a terminal already worked.

## 3.0.0

- The CLI moved to its own repo: [dartondox/dox-cli](https://github.com/dartondox/dox-cli). It is the same code.

## 3.0.0-rc.2

- Fix: `dox create` and `dox update` sorted pre-releases only by their number, so `3.0.0-alpha.17` looked newer than `3.0.0-rc.1`. `dox create` then cloned the alpha.17 template. Now the label counts first: alpha < beta < rc < stable.
- Only the CLI has this version. The other Dox packages stay at 3.0.0-rc.1.

## 3.0.0-rc.1

- Fix: `dox make:job` wrote a `bin/queue.dart` that did not compile. It called `QueueWorker(jobs: ...)`, but `QueueWorker` has no `jobs` parameter. It now writes the same file as the app template: `QueueWorker(app: appConfig)`.
- Fix: the job that `dox make:job` writes showed `X(userId: 1).dispatch()` in its comment. The class has no `userId`. The comment now shows `X().dispatch()`.
- Fix: `dox db:seed --class UserSeeder` (with a space) was refused. Both `--class=UserSeeder` and `--class UserSeeder` work now.
- Fix: `dox make:middleware` wrote `extends IDoxMiddleware`. It now writes `implements IDoxMiddleware`, like the docs and the built-in middleware.
- `dox build` also leaves the SQLite lock files of dox_migration (`*.sqlite.lock`, `*.sqlite3.lock`, `*.db.lock`) out of `build/bundle/db`.

## 3.0.0-alpha.17

- Uses dox_migration 3.0.0-alpha.12.
- `dox make:controller -r`: the `destroy` stub shows how to give a 404 when `delete()` deletes 0 rows.

## 3.0.0-alpha.16

- Version bump only, to match the other packages.

## 3.0.0-alpha.15

- `dox make:dto CreateBlog` now writes `lib/app/http/dtos/create_blog/create_blog.dto.dart`. Each DTO has its own folder, like models. The `.dto.g.dart` file is made next to it.

## 3.0.0-alpha.14

- Fix: `dox make:migration` run more than once in the same second gave files with the same timestamp. Then the run order depended only on the name, which could break foreign keys. Now each new migration (`.dart` or `.sql`) sorts after every file already in `db/migration`. When needed, it uses the newest time plus 1 second.

## 3.0.0-alpha.13

- Version bump only, to match the other packages.

## 3.0.0-alpha.12

- Version bump only, to match the other packages.

## 3.0.0-alpha.11

- `dox build` also builds `bin/queue.dart` and `bin/schedule.dart` when they exist, to `build/bundle/bin/queue` and `build/bundle/bin/schedule`. Before, the worker and the scheduler had no production binary.
- Fix: `dox build` copied the local SQLite database (`db/dox.sqlite`, with its `-wal` and `-shm` files) into `build/bundle/db`, so dev data went to production. SQLite files are now left out.
- `dox --help` and `dox -h` show the help, like `dox help`.

## 3.0.0-alpha.10

- `make:*` is now the main name of every generator: `make:controller`, `make:middleware`, `make:dto`, `make:serializer` and `make:model`, like `make:migration`, `make:factory` and `make:seeder`. The `create:*` names still work as aliases.
- New `dox make:job <name>`: makes `lib/app/jobs/<name>.job.dart` and `bin/queue.dart` when it is missing. It prints a hint to add `dox_queue` and to run `build_runner`.
- New `dox queue:work`, `queue:failed`, `queue:retry`, `queue:forget` and `queue:flush`: run `bin/queue.dart` with the same flags.
- New `dox schedule:work`, `schedule:run`, `schedule:list` and `schedule:test <name>`: run `bin/schedule.dart`.
- These commands pass the terminal through, send SIGINT and SIGTERM to the app script so a worker can stop by itself, and return its exit code. When the script is missing they print how to set it up.

## 3.0.0-alpha.9

- `dox make:controller` (`create:controller`) writes `@Inject()` above the class, and no global controller instance. The file shows the typed route to use. The command says to run `build_runner`.
- New `dox make:factory <model>`: makes `db/factories/<model>.factory.dart`.
- New `dox make:seeder <name>`: makes `db/seeders/<name>.seeder.dart`, writes the seeder list `db/seeders/seeders.dart` and makes `bin/seed.dart` when it is missing.
- New `dox db:seed [--class=<name>]`: runs `bin/seed.dart`. The default seeder is `DatabaseSeeder`.
- New `dox migration:fresh` (or `migrate:fresh`): drops all tables, then runs all migrations.
- `--seed` after `migration:run`, `migration:refresh` or `migration:fresh` runs the seeders when the migrations end well.

## 3.0.0-alpha.8

- Version bump only, to match the other packages.

## 3.0.0-alpha.7

- Breaking: `create:controller` no longer takes `-ws`. Dox uses Socket.IO for realtime now. See the Socket.IO docs for a namespace class.
- Security: `dox create` now copies `.env.example` to `.env` and writes a new random `APP_KEY`. Before, every new app used the same public key from the template. You no longer run `cp .env.example .env`.
- The `.env.example` of the CLI has an empty `APP_KEY`. Run `dox key:generate` to set one.

## 3.0.0-alpha.6

- Fix: `dox key:generate` dropped `.env` lines with more than one `=` (like `DATABASE_URL=postgres://u:p@h/db?sslmode=require`). It also dropped comment lines. Now it only changes the `APP_KEY` line. Every other line stays as it is.
- Fix: `dox create` crashed with `Failed to decode data using encoding 'utf-8'` when the template had a binary file (for example `db/dox.sqlite-shm`). It now skips files that are not UTF-8 text. It only writes a file when its content changes.

## 3.0.0-alpha.5

- Fix: `dox create my_app` without `--version` crashed with a `RangeError`.
- Fix: `dox create` picked the GitHub "latest" template release, which skips pre-releases. During the 3.x alpha that gave the old 2.x template. It now takes the newest template with the same major version as the CLI.
- Fix: `dox env:generate` read `KEY=3000 # note` as text, not as an `int`. A `#` after a space is now a comment.
- Fix: `dox update` ran a plain `dart pub global activate dox`, which skips pre-releases. During the 3.x alpha it installed the old 2.x CLI. It now installs the newest version with the same major version as the CLI, from the pub.dev version list.

## 3.0.0-alpha.4

- Version bump only, to match the other packages.

## 3.0.0-alpha.3

- Version bump only, to match the other packages.

## 3.0.0-alpha.2

- Fix: `dox build` no longer passes `--delete-conflicting-outputs` to build_runner (it was removed and printed a warning).
- Needs Dart 3.13 or newer.
- All dependencies updated to their latest versions.
- `dox build` now runs `dart build cli` (AOT, with build hooks). The output is `build/bundle/`. Start it with `cd build/bundle && ./bin/server`.
- New `dox create:dto <name>`: makes `lib/app/http/dtos/<name>.dto.dart`. `dox create:request` is removed.
- `dox create:controller -r` uses `int id` for the resource methods.
- New `dox openapi:generate [dir]`. It runs the app's `bin/openapi.dart` and writes `openapi.json` and `openapi.yaml` (default `storage/openapi`).
- New `dox env:generate`: makes `lib/config/env.dart` (the typed env class) from `.env.example`.
- New `dox env:check`: loads the typed env and prints every missing or bad key (exit code 1).


## 3.0.0-alpha.1

- Version 3 of Dox. All Dox packages now share one version.
- Needs Dart 3.6 or newer.
- See the [release notes](https://github.com/dartondox/dox/pull/112) for all main changes.
- Generated models import `package:dox_orm/dox_orm.dart`.

## 2.0.1

- bug fix on dox create command

## 2.0.0

- Release stable version v2.0

## 2.0.0-alpha.3

- Fix migration issue

## 2.0.0-alpha.2

- Add option to create project with specific version

## 2.0.0-alpha.1

- Compatible with core version 2

## 1.1.1

- handle migration with dox_migration
- set default migration file with .sql

## 1.0.55

- Add command to create serializer
- Add help option

## 1.0.54

- update request template
- Add help option

## 1.0.53

- Added command to create form request `dox create:request Blog`

## 1.0.52

- Added command to create websocket controller

## 1.0.51

- Initial version.
