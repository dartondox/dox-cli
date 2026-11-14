## Unreleased

- Fix: `dox key:generate` did not see an `export APP_KEY=old` line. It added a new `APP_KEY` at the top, but the old line came later and won, so the app kept the old key. It still said the key was updated. Now it changes the `export APP_KEY` line in place and keeps the `export`. When `.env` has more than one `APP_KEY` line, each one gets the new key, so no old key is left to win. A new `APP_KEY` line in a file with Windows line ends (CRLF) now gets a CRLF end too.
- Fix: `dox env:check` always read `.env` with `envExpand` off. With `envExpand` on in the app, `APP_PORT=${PORT}` gave a false "must be an int" error, and `"..."` escapes were read in another way than the app reads them. Now the check has a mode. `dox env:check` checks with `envExpand` off, like an app that does not set `Env.flags`. `dox env:check --expand` checks with `envExpand` on. The result is what `AppEnv.load()` gives with those flags. The first line of the output says which mode was used. With `envExpand` off, when a value in `.env` has `${`, a note says to run `dox env:check --expand` if the app turns on `envExpand`. The note does not change the exit code. An unknown option now stops with exit code 1.
- Fix: `dox env:generate` made code that does not compile for `export APP_NAME=dox` (`String get export appName;`) and for a key like `CLASS` (a Dart reserved word). Now `export` is removed. A reserved word or a name that starts with a digit gets `env` in front (`CLASS` gives `envClass`) and an `@EnvKey('CLASS')`.
- Fix: `dox env:generate` made `ZIP=02134` an `int` and lost the leading zero. A number with a leading zero is now a `String`.
- Fix: `dox env:generate` wrote the example value of a secret into the code when it looked like a number or a bool (`DB_PASSWORD=123456` gave `int get dbPassword => 123456;`). Now a key that has `PASS`, `PWD`, `SECRET`, `KEY`, `TOKEN`, `SALT`, `CREDENTIAL`, `PRIVATE`, `AUTH`, `JWT`, `DSN`, `OTP`, `PIN`, `CERT`, `SIGN`, `CODE`, `CVV`, `CVC`, `HMAC`, `SEED`, `NONCE`, `SSN`, `HASH` or `LICENSE` anywhere in its name (`APIKEY`, `PASSCODE`, `PIN`) is always a `String` with no default. This is too safe on purpose: `TOKEN_TTL=3600` also gets no default. `.env.example` is in git, so never put a real secret in it. Read the made class before you commit it.
- Fix: `dox env:generate` wrote `@EnvKey('$key')` as it is. A key with `$`, `'` or `\` gave code that does not compile. The key is now escaped.
- Fix: `dox env:generate` made code that does not compile for a number over 64 bits (now a `String`), for two keys with the same getter name (`A_B` and `A__B`: the later one gets `aB2` and an `@EnvKey`), and for keys that clash with a member of the class or of the generated code (`LOAD`, `HASH_CODE`, `TO_STRING`, `R`, `INT`: they get `env` in front and an `@EnvKey`).
- `dox env:generate` adds `@EnvKey('KEY')` when the getter name could give another key, also under the acronym rule of dox_builder (`aBC` can be `A_B_C` or `A_BC`). So each getter reads the right key with an old and a new dox_builder.

## 3.2.1

- New: `dox serve` hot reloads code changes. When only files in `lib/app/` change (controllers, services, models and so on), dox reloads the new code into the running server, with no restart. It takes about 0.1 s. It works for all isolates of the server. A hot reload does not wait for build_runner. Changes in routes, providers, config, `lib/generated/`, `bin/`, `db/` and generated `.g.dart` files still restart the server, because that code or data is built only at start. A hot reload also does not re-run code that already ran in `lib/app/`, like a static value or an object made at start. When a change does not show, restart dox. When a reload fails (for example a compile error), the server restarts. The server now runs with the Dart VM service on a free localhost port, with DevTools. The server prints the VM service link at start. Open it in a browser to get DevTools. Use it for the debugger, the CPU profiler and memory snapshots. VS Code can also attach to the VM service address. `dox serve --no-reload` turns hot reload off.
- `dox serve` runs one reload or restart at a time, so quick saves never start a second server. A server or build_runner that ignores SIGTERM gets SIGKILL after 5 seconds, on a restart and when dox stops. A hot reload has a 10 second limit, so a stuck server can not hang dox. When build_runner prints nothing for 60 seconds during a build, dox stops waiting for it. dox now also stops when the terminal closes (SIGHUP), and a second Ctrl+C while it stops exits at once (other signals let the first stop finish). A server or build_runner that starts while dox stops is stopped too. A resident compiler left by a dox that was killed (SIGKILL) is stopped at the next `dox serve`. Errors and warnings of `build_runner watch` are now shown (progress lines are not). Each `dox serve` has its own resident compiler, so a second `dox serve` in the same project is not affected when the first one stops.
- Faster `dox serve` (`dox s`) restarts. The server now runs with `dart run --resident`, so a restart only compiles the changed files. The resident compiler uses an info file in `.dart_tool/dox/`, and dox stops it when dox exits. Changes in `build/` and in hidden folders like `.dart_tool/` no longer restart the server. The wait after a change is now 200 ms (was 500 ms). With build_runner, one save gives one restart: dox waits until build_runner has written the new generated files. Before, the server restarted on the save and again for each generated file. The server now starts first, and `build_runner watch` starts when the server says "Server started at" (or after 10 seconds). Before, both started at the same time and slowed down each other. When the first build writes new files, the server restarts once after it.

## 3.2.0

- New: `dox add <package>` adds a Dox package and sets it up. `orm` is short for `dox_orm`. It runs `dart pub add` (with `--dev` when given), `dart pub get`, then the `<package>:install` command of the package. The other words go to that command, like `dox add orm --driver=postgres`. A package with no install command is only added, and `dox add` says so. When the package commands can not be loaded (a broken commands library), it prints an error and exits with code 1. The name is the first word that is not a flag, so `dox add --dev orm` works. The CLI has no code of any package.
- The hints of `dox queue:*` (when `bin/queue.dart` is missing) and `dox make:job` (when dox_queue is not in pubspec.yaml) now say: for the database driver or batches, add `dox_queue_database` and make the queue provider extend `DatabaseQueueProvider`.
- New: `dox route:list` prints every route of the app: method, path, name, handler and middleware. It does not start the server. It writes a small script into `.dart_tool/dox/` and runs it. The script loads the routes of the app routers with `Dox().loadRoutes()`, so it needs a dox_core with that call. Providers do not run, so a route that a provider adds in `setup()` (like the Socket.IO mount) is not listed. Fallback routes show as `FALLBACK`, `Route.mount` handlers as `MOUNT` (with the global middleware for `middleware: true`). A `Route.websocket` route shows `WebSocket` as its handler (from `RouteData.isWebSocket`). Errors go to stderr, so `--json` output stays clean. `dox route:list --json` prints the same data as JSON.
- New: five `make:` commands. `dox make:provider <name>` makes `lib/providers/<name>_provider.dart` (a `DoxProvider` with `setup()`). `dox make:command <name>` makes `lib/app/commands/<name>_command.dart`, adds it to `lib/app/commands/commands.dart`, and sets `dox: commands:` in pubspec.yaml when it is missing. `dox make:mail <name>` makes a `Mailable` in `lib/app/mail/` and its view `resources/views/emails/<name>.dox.html`. `--no-view` makes a mail with a plain text body and no view. `dox make:view <name>` makes a `.dox.html` file in `resources/views` (`emails/welcome` makes a folder). `dox make:test <name>` makes `test/<name>_test.dart` with a `DoxTestClient`. `--unit` makes a plain `package:test` test. None of them overwrites a file. A bad name, an extra word or an unknown flag prints an error and exits with code 1.
- New: `dox schedule:clear-cache` runs `bin/schedule.dart clear-cache`. A crash can leave the `withoutOverlapping()` lock of a task in the cache, so the task is skipped for up to 24 hours. The command removes these locks. It needs a dox_scheduler with `clear-cache`. Do not run it while a task really runs on another process.
- New: `dox make:model` takes Laravel style flags. `-m` (`--migration`) makes the migration, `-c` (`--controller`) a controller, `-r` (`--resource`) a resource controller, `--api` a resource controller without `create` and `edit`, `-f` (`--factory`) a factory, `-s` (`--seed`) a seeder, and `-a` (`--all`) the migration, factory, seeder and resource controller. Short flags can be joined, like `-mcr`. Each file is the same as the one the single command makes, like `dox make:factory Post`. A resource controller from `make:model` uses the model. When the model exists, nothing is made, as before with `-m`.
- New: `dox make:controller` takes `--resource` (the same as `-r`), `--api` (a resource controller without `create` and `edit`) and `--model=Post` or `--model Post` (a resource controller whose actions use the `Post` model). It prints a warning when the model file does not exist yet.
- Fix: `dox make:controller Photo --resource` made a plain controller and gave no error. `dox make:model Post -mc` failed. Now an unknown flag of `make:model` or `make:controller` prints an error and exits with code 1, and nothing is made. An extra word, like `dox make:controller Photo junk`, does the same. Before, it made a plain controller.
- New: `dox migration:rollback --batch=3` (or `--batch 3`) rolls back only the migrations of batch 3. It is passed on to `bin/migrate.dart`, like `--step`. It needs a dox_migration with `rollback --batch`. Give `--step` or `--batch`, not both.
- Fix: `dox queue:prune-failed --hours 48` (with a space) now works, like `--hours=48`. Before, it was refused. Any other second word still prints the usage and stops with exit code 1.
- Fix: `dox make:migration` wrote `db/migration/migrations.dart` in a shape that `dart format` changed later. Now the file is written in `dart format` shape. Short entries are on one line, and long imports are split.
- Fix: the help of `dox queue:clear` now says "Delete the jobs of a queue". With Redis it also deletes the delayed and reserved jobs, not only the waiting ones. The help of `dox queue:restart` now says it needs a shared cache store.

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
