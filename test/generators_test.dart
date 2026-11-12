import 'dart:async';
import 'dart:io';

import 'package:dox/src/command_registry.dart';
import 'package:dox/src/tools/create_controller.dart';
import 'package:dox/src/tools/create_middleware.dart';
import 'package:dox/src/tools/create_migration.dart';
import 'package:dox/src/tools/create_model.dart';
import 'package:dox/src/tools/create_dto.dart';
import 'package:dox/src/tools/create_factory.dart';
import 'package:dox/src/tools/create_job.dart';
import 'package:dox/src/tools/create_seeder.dart';
import 'package:dox/src/tools/create_serializer.dart';
import 'package:dox/src/types.dart';
import 'package:dox/src/utils/utils.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Generators write relative to the current directory,
/// so each test runs inside its own temp dir.
void main() {
  late Directory tempDir;
  late Directory originalCwd;

  setUp(() {
    originalCwd = Directory.current;
    tempDir = Directory.systemTemp.createTempSync('dox_gen_test_');
    Directory.current = tempDir;
  });

  tearDown(() {
    Directory.current = originalCwd;
    tempDir.deleteSync(recursive: true);
  });

  String read(String path) => File(path).readAsStringSync();

  group('generators | multi-word names', () {
    test('controller', () {
      expect(createController('BlogPostController', false), isTrue);
      String c = read('lib/app/http/controllers/blog_post.controller.dart');
      expect(c, contains('@Inject()\nclass BlogPostController {'));
      expect(c, isNot(contains('BlogPostController blogPostController =')));
      expect(
        c,
        contains(
          "Route.get('path', (BlogPostController c) => "
          'c.index);',
        ),
      );
    });

    test('model', () {
      expect(createModel('BlogPost'), isTrue);
      String c = read('lib/app/models/blog_post/blog_post.model.dart');
      expect(c, contains("part 'blog_post.model.g.dart';"));
      expect(c, contains('class BlogPost extends BlogPostGenerator {'));
    });

    test('model from snake case name', () {
      expect(createModel('blog_post'), isTrue);
      String c = read('lib/app/models/blog_post/blog_post.model.dart');
      expect(c, contains('class BlogPost extends BlogPostGenerator {'));
    });

    test('middleware', () {
      expect(createMiddleware('RateLimitMiddleware'), isTrue);
      String c = read('lib/app/http/middleware/rate_limit.middleware.dart');
      expect(
        c,
        contains('class RateLimitMiddleware implements IDoxMiddleware'),
      );
      expect(c, contains('return req;'));
    });

    test('dto', () {
      expect(createDto('CreateBlogPost'), isTrue);
      String c = read(
        'lib/app/dtos/create_blog_post/create_blog_post.dto.dart',
      );
      expect(c, contains('@Dto()'));
      expect(c, contains('class CreateBlogPost {'));
      expect(c, contains("part 'create_blog_post.dto.g.dart';"));
      expect(
        c,
        contains(
          r'static const DtoSchema<CreateBlogPost> schema = $CreateBlogPostDto;',
        ),
      );
    });

    test('serializer imports the matching model', () {
      File('pubspec.yaml').writeAsStringSync('name: my_app\n');
      expect(createSerializer('BlogPostSerializer'), isTrue);
      String c = read('lib/app/serializers/blog_post.serializer.dart');
      expect(
        c,
        contains('class BlogPostSerializer extends Serializer<BlogPost>'),
      );
      expect(
        c,
        contains("'package:my_app/app/models/blog_post/blog_post.model.dart'"),
      );
    });
  });

  group('generators | existing file is not overwritten', () {
    test('controller', () {
      createController('User', false);
      File f = File('lib/app/http/controllers/user.controller.dart');
      f.writeAsStringSync('// mine');
      expect(createController('User', true), isFalse);
      expect(f.readAsStringSync(), '// mine');
    });

    test('model', () {
      expect(createModel('User'), isTrue);
      expect(createModel('User'), isFalse);
    });

    test('middleware, dto, serializer', () {
      expect(createMiddleware('Auth'), isTrue);
      expect(createMiddleware('Auth'), isFalse);
      expect(createDto('User'), isTrue);
      expect(createDto('User'), isFalse);
      File('pubspec.yaml').writeAsStringSync('name: my_app\n');
      expect(createSerializer('User'), isTrue);
      expect(createSerializer('User'), isFalse);
    });
  });

  group('create:model -m', () {
    List<String> migrationFiles() =>
        Directory('db/migration')
            .listSync()
            .map((FileSystemEntity f) => f.uri.pathSegments.last)
            .toList()
          ..sort();

    test('-m makes the model and a create_<plural>_table migration', () async {
      await CommandRegistry.findCommand('create:model')!
          .function(<String>['BlogPost', '-m']);
      String model = read('lib/app/models/blog_post/blog_post.model.dart');
      expect(model, contains("@DoxModel(table: 'blog_posts')"));
      List<String> files = migrationFiles();
      expect(files, contains('migrations.dart'));
      String name = files.firstWhere(
        (String f) => f.endsWith('_create_blog_posts_table.dart'),
      );
      String c = read('db/migration/$name');
      expect(c, contains("await schema.create('blog_posts', (Table table) {"));
      expect(
        read('db/migration/migrations.dart'),
        contains('CreateBlogPostsTable()'),
      );
      expect(File('bin/migrate.dart').existsSync(), isTrue);
    });

    test('make:model and --migration work too', () async {
      expect(
        CommandRegistry.findCommand('create:model')?.command,
        'make:model',
      );
      await CommandRegistry.findCommand('make:model')!
          .function(<String>['Category', '--migration']);
      expect(
        migrationFiles().any(
          (String f) => f.endsWith('_create_categories_table.dart'),
        ),
        isTrue,
      );
    });

    test('without -m: no migration, same plural table', () async {
      await CommandRegistry.findCommand('create:model')!
          .function(<String>['User']);
      String model = read('lib/app/models/user/user.model.dart');
      expect(model, contains("@DoxModel(table: 'users')"));
      expect(model, contains('List<String> get fillable => <String>[];'));
      expect(Directory('db').existsSync(), isFalse);
    });

    test('unknown flag makes nothing', () async {
      await CommandRegistry.findCommand('create:model')!
          .function(<String>['User', '-x']);
      exitCode = 0;
      expect(Directory('lib').existsSync(), isFalse);
    });
  });

  group('make:model flags', () {
    Future<void> run(List<String> args) =>
        CommandRegistry.findCommand('make:model')!.function(args);

    const String controller = 'lib/app/http/controllers/post.controller.dart';
    const String factory = 'db/factories/post.factory.dart';
    const String seeder = 'db/seeders/post.seeder.dart';

    bool exists(String path) => File(path).existsSync();
    bool hasMigration() =>
        Directory('db/migration').existsSync() &&
        Directory('db/migration').listSync().any(
          (FileSystemEntity f) => f.path.endsWith('_create_posts_table.dart'),
        );

    /// what was made, besides the model
    Map<String, bool> made() => <String, bool>{
      'migration': hasMigration(),
      'controller': exists(controller),
      'factory': exists(factory),
      'seeder': exists(seeder),
    };

    setUp(() {
      File('pubspec.yaml').writeAsStringSync('name: my_app\n');
    });

    tearDown(() {
      exitCode = 0;
    });

    test('-c makes a plain controller', () async {
      await run(<String>['Post', '-c']);
      expect(made(), <String, bool>{
        'migration': false,
        'controller': true,
        'factory': false,
        'seeder': false,
      });
      String c = read(controller);
      expect(c, contains('class PostController {'));
      expect(c, contains("Route.get('path', (PostController c) => c.index);"));
    });

    test('-r makes a resource controller that uses the model', () async {
      await run(<String>['Post', '-r']);
      String c = read(controller);
      expect(c, contains("Route.resource('path', PostController);"));
      expect(c, contains('package:my_app/app/models/post/post.model.dart'));
      expect(c, contains('show(DoxRequest req, Post post)'));
      expect(c, contains('edit(DoxRequest req, Post post)'));
      expect(made()['migration'], isFalse);
    });

    test('--api makes a resource controller without create and edit', () async {
      await run(<String>['Post', '--api']);
      String c = read(controller);
      expect(c, contains('return Post().all();'));
      expect(c, isNot(contains('create(DoxRequest req)')));
      expect(c, isNot(contains('edit(DoxRequest')));
    });

    test('-f makes a factory, -s a seeder', () async {
      await run(<String>['Post', '-f']);
      expect(made(), <String, bool>{
        'migration': false,
        'controller': false,
        'factory': true,
        'seeder': false,
      });
      expect(
        read(factory),
        contains('class PostFactory extends Factory<Post>'),
      );
      Directory('lib').deleteSync(recursive: true);
      await run(<String>['Post', '-s']);
      expect(read(seeder), contains('class PostSeeder extends Seeder'));
      expect(File('bin/seed.dart').existsSync(), isTrue);
    });

    test('-mcr: migration and a resource controller', () async {
      await run(<String>['Post', '-mcr']);
      expect(made(), <String, bool>{
        'migration': true,
        'controller': true,
        'factory': false,
        'seeder': false,
      });
      expect(read(controller), contains('store(DoxRequest req)'));
      expect(read(controller), contains('Post().create(req.body)'));
    });

    test('-mfs: migration, factory and seeder', () async {
      await run(<String>['Post', '-mfs']);
      expect(made(), <String, bool>{
        'migration': true,
        'controller': false,
        'factory': true,
        'seeder': true,
      });
    });

    test('flags can be apart and in any order', () async {
      await run(<String>['-s', 'Post', '-f', '-m']);
      expect(made(), <String, bool>{
        'migration': true,
        'controller': false,
        'factory': true,
        'seeder': true,
      });
    });

    for (List<String> all in <List<String>>[
      <String>['-a'],
      <String>['--all'],
      <String>['--migration', '--factory', '--seed', '--resource'],
    ]) {
      test('$all makes everything', () async {
        await run(<String>['Post', ...all]);
        expect(made(), <String, bool>{
          'migration': true,
          'controller': true,
          'factory': true,
          'seeder': true,
        });
        expect(
          read(controller),
          contains('destroy(DoxRequest req, Post post)'),
        );
      });
    }

    test('--controller is -c', () async {
      await run(<String>['Post', '--controller']);
      expect(read(controller), contains('Future<dynamic> index(DoxRequest'));
      expect(read(controller), isNot(contains('store(')));
    });

    test('-a makes the same files as the single commands', () async {
      await run(<String>['Post', '-a']);
      Map<String, String> withFlags = <String, String>{
        for (String f in <String>[controller, factory, seeder]) f: read(f),
      };
      Directory('lib').deleteSync(recursive: true);
      Directory('db').deleteSync(recursive: true);
      await CommandRegistry.findCommand('make:factory')!
          .function(<String>['Post']);
      await CommandRegistry.findCommand('make:seeder')!
          .function(<String>['Post']);
      await CommandRegistry.findCommand('make:controller')!
          .function(<String>['Post', '-r', '--model=Post']);
      for (MapEntry<String, String> e in withFlags.entries) {
        expect(read(e.key), e.value, reason: e.key);
      }
    });

    test('an existing model: nothing else is made', () async {
      createModel('Post');
      await run(<String>['Post', '-a']);
      expect(made().values, everyElement(isFalse));
    });

    for (List<String> bad in <List<String>>[
      <String>['Post', '-mx'],
      <String>['Post', '-x'],
      <String>['Post', '--foo'],
      <String>['Post', '--migration=yes'],
      <String>['Post', '-'],
      <String>['Post', 'extra'],
    ]) {
      test('$bad: error, exit code 1, nothing made', () async {
        await run(bad);
        expect(exitCode, 1);
        expect(Directory('lib').existsSync(), isFalse);
        expect(Directory('db').existsSync(), isFalse);
      });
    }
  });

  group('make:controller flags', () {
    Future<void> run(List<String> args) =>
        CommandRegistry.findCommand('make:controller')!.function(args);

    const String file = 'lib/app/http/controllers/photo.controller.dart';

    /// the lines that `make:controller [args]` prints
    Future<List<String>> runPrinted(List<String> args) async {
      List<String> lines = <String>[];
      await runZoned(
        () => run(args),
        zoneSpecification: ZoneSpecification(
          print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
            lines.add(line);
          },
        ),
      );
      return lines;
    }

    setUp(() {
      File('pubspec.yaml').writeAsStringSync('name: my_app\n');
    });

    tearDown(() {
      exitCode = 0;
    });

    test('--resource is the same as -r', () async {
      await run(<String>['Photo', '-r']);
      String short = read(file);
      File(file).deleteSync();
      await run(<String>['Photo', '--resource']);
      expect(read(file), short);
      expect(short, contains('create(DoxRequest req)'));
      expect(short, contains('edit(DoxRequest req, int id)'));
      expect(short, isNot(contains('/app/models/')));
    });

    test('--api: resource actions without create and edit', () async {
      await run(<String>['Photo', '--api']);
      String c = read(file);
      for (String action in <String>[
        'index(DoxRequest req)',
        'store(DoxRequest req)',
        'show(DoxRequest req, int id)',
        'update(DoxRequest req, int id)',
        'destroy(DoxRequest req, int id)',
      ]) {
        expect(c, contains(action));
      }
      expect(c, isNot(contains('create(DoxRequest req)')));
      expect(c, isNot(contains('edit(DoxRequest')));
      expect(c, contains("Route.resource('path', PhotoController);"));
    });

    for (List<String> model in <List<String>>[
      <String>['--model=BlogPost'],
      <String>['--model', 'BlogPost'],
    ]) {
      test('$model: a resource controller that uses the model', () async {
        await run(<String>['Photo', ...model]);
        String c = read(file);
        expect(
          c,
          startsWith(
            "import 'package:dox_core/dox_core.dart';\n"
            "import 'package:my_app/app/models/blog_post/blog_post.model.dart';\n",
          ),
        );
        expect(c, contains('return BlogPost().all();'));
        expect(c, contains('return BlogPost().create(req.body);'));
        expect(
          c,
          contains(
            'show(DoxRequest req, BlogPost blogPost) async {\n    return blogPost;',
          ),
        );
        expect(c, contains('edit(DoxRequest req, BlogPost blogPost)'));
        expect(c, contains('update(DoxRequest req, BlogPost blogPost)'));
        expect(c, contains('await blogPost.update(req.body);'));
        expect(c, contains('await blogPost.delete();'));
        expect(
          c,
          contains(
            '/// Set fillable in the BlogPost model first. '
            'While it is empty, this throws.\n'
            '  Future<dynamic> store(',
          ),
        );
        expect(
          c,
          contains(
            '/// Set fillable in the BlogPost model first. '
            'While it is empty, this throws.\n'
            '  Future<dynamic> update(',
          ),
        );
      });
    }

    test('the name count error reads well', () async {
      List<String> extra = await runPrinted(<String>['Photo', 'Pen']);
      expect(
        extra.single,
        '\x1B[31mmake:controller takes 1 name, got 2: Photo Pen. '
        'Run `dox help make:controller` to see the options.\x1B[0m',
      );
      List<String> none = await runPrinted(<String>['-r']);
      expect(
        none.single,
        '\x1B[31mmake:controller takes 1 name, got 0. '
        'Run `dox help make:controller` to see the options.\x1B[0m',
      );
    });

    test('--model warns when the model file is missing', () async {
      List<String> lines = await runPrinted(<String>['Photo', '--model=Post']);
      expect(
        lines.any(
          (String l) =>
              l.contains('The Post model does not exist yet.') &&
              l.contains('Run `dox make:model Post`.') &&
              l.startsWith('\x1B[33m'),
        ),
        isTrue,
        reason: '$lines',
      );
    });

    test('--model does not warn when the model file exists', () async {
      Directory('lib/app/models/post').createSync(recursive: true);
      File('lib/app/models/post/post.model.dart').writeAsStringSync('');
      List<String> lines = await runPrinted(<String>['Photo', '--model=Post']);
      expect(lines.any((String l) => l.contains('does not exist')), isFalse);
    });

    test(
      'a plain resource controller names its own model in the hint',
      () async {
        await run(<String>['Blog', '-r']);
        expect(
          read('lib/app/http/controllers/blog.controller.dart'),
          contains("`if (await Blog().where('id', id).delete() == 0) "),
        );
      },
    );

    test('--api --model: no create and edit, uses the model', () async {
      await run(<String>['Photo', '--api', '--model=Post']);
      String c = read(file);
      expect(c, contains('show(DoxRequest req, Post post)'));
      expect(c, isNot(contains('edit(DoxRequest')));
    });

    test('--model needs the app name', () async {
      File('pubspec.yaml').deleteSync();
      await run(<String>['Photo', '--model=Post']);
      expect(exitCode, 1);
      expect(File(file).existsSync(), isFalse);
    });

    for (List<String> bad in <List<String>>[
      <String>['Photo', '--foo'],
      <String>['Photo', '-x'],
      <String>['Photo', '-rx'],
      <String>['Photo', '--model'],
      <String>['Photo', '--model='],
      <String>['Photo', '--model', '-r'],
      <String>['Photo', '--model=../x'],
      <String>['Photo', '--resource=yes'],
      <String>['Photo', 'Extra'],
    ]) {
      test('$bad: error, exit code 1, nothing made', () async {
        await run(bad);
        expect(exitCode, 1);
        expect(Directory('lib').existsSync(), isFalse);
      });
    }
  });

  group('cache:table', () {
    test('writes the migration and the registry, a second run fails', () async {
      exitCode = 0;
      await CommandRegistry.findCommand('cache:table')!.function(<String>[]);
      List<File> files = Directory('db/migration')
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('_create_cache_table.dart'))
          .toList();
      expect(files, hasLength(1));
      String c = files.single.readAsStringSync();
      expect(c, contains('class CreateCacheTable extends Migration {'));
      expect(c, contains("await schema.create('cache', (Table table) {"));
      expect(c, contains("table.string('key', 255).primary();"));
      expect(c, contains("table.longText('value');"));
      expect(c, contains("table.bigInteger('expires_at').nullable();"));
      expect(c, contains("await schema.dropIfExists('cache');"));
      expect(
        File('db/migration/migrations.dart').readAsStringSync(),
        contains('CreateCacheTable()'),
      );
      expect(exitCode, 0);

      await CommandRegistry.findCommand('cache:table')!.function(<String>[]);
      expect(exitCode, 1);
      expect(
        Directory('db/migration')
            .listSync()
            .where((FileSystemEntity f) => f.path.contains('cache_table')),
        hasLength(1),
      );
      exitCode = 0;
    });

    test('a file with a longer name does not block it', () async {
      exitCode = 0;
      File('db/migration/2026_01_01_000000_add_x_create_cache_table.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('');
      await CommandRegistry.findCommand('cache:table')!.function(<String>[]);
      expect(exitCode, 0);
      expect(
        Directory('db/migration')
            .listSync()
            .map((FileSystemEntity f) => f.path),
        anyElement(matches(RegExp(r'\d{6}_create_cache_table\.dart$'))),
      );
    });

    test('a .sql migration with the same name blocks it', () async {
      exitCode = 0;
      File('db/migration/2026_01_01_000000_create_cache_table.sql')
        ..createSync(recursive: true)
        ..writeAsStringSync('-- up\n\n-- down\n');
      await CommandRegistry.findCommand('cache:table')!.function(<String>[]);
      expect(exitCode, 1);
      exitCode = 0;
      expect(Directory('db/migration').listSync(), hasLength(1));
    });
  });

  group('make:migration', () {
    Future<List<File>> run(List<String> args) async {
      await CommandRegistry.findCommand('make:migration')!.function(args);
      return Directory('db/migration').listSync().whereType<File>().toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
    }

    String fileName(File f) => f.uri.pathSegments.last;

    test('create_x_table: a Dart migration that creates table x', () async {
      List<File> files = await run(<String>['create_users_table']);
      File migration = files.firstWhere(
        (File f) => fileName(f) != 'migrations.dart',
      );
      expect(
        fileName(migration),
        matches(RegExp(r'^\d{4}_\d{2}_\d{2}_\d{6}_create_users_table\.dart$')),
      );
      String c = migration.readAsStringSync();
      expect(c, contains('class CreateUsersTable extends Migration {'));
      expect(c, contains("await schema.create('users', (Table table) {"));
      expect(c, contains('table.id();'));
      expect(c, contains("await schema.dropIfExists('users');"));
    });

    test('add_y_to_x_table: a Dart migration that changes table x', () async {
      List<File> files = await run(<String>['add_avatar_to_users_table']);
      String c = files
          .firstWhere((File f) => fileName(f) != 'migrations.dart')
          .readAsStringSync();
      expect(c, contains('class AddAvatarToUsersTable extends Migration {'));
      expect(c, contains("await schema.table('users', (Table table) {"));
    });

    test('other names get an empty migration', () async {
      List<File> files = await run(<String>['SeedThings']);
      String c = files
          .firstWhere((File f) => fileName(f) != 'migrations.dart')
          .readAsStringSync();
      expect(c, contains('class SeedThings extends Migration {'));
    });

    test('registry lists the Dart migrations sorted by name', () async {
      Directory('db/migration').createSync(recursive: true);
      File('db/migration/2020_01_02_000000_b.dart')
          .writeAsStringSync('class B extends Migration {}');
      File('db/migration/2020_01_01_000000_a.dart')
          .writeAsStringSync('class A extends Migration {}');
      File('db/migration/2020_01_01_000000_skip.sql').writeAsStringSync('');
      await run(<String>['create_posts_table']);
      String registry = read('db/migration/migrations.dart');
      expect(registry, contains("import '2020_01_01_000000_a.dart' as m1;"));
      expect(registry, contains("import '2020_01_02_000000_b.dart' as m2;"));
      expect(
        registry,
        contains("  MigrationEntry('2020_01_01_000000_a', m1.A()),"),
      );
      expect(
        registry,
        contains("  MigrationEntry('2020_01_02_000000_b', m2.B()),"),
      );
      expect(registry, contains('m3.CreatePostsTable()'));
      expect(registry, isNot(contains('skip')));
      expect(registry, isNot(contains('migrations.dart')));
    });

    test('registry is already in `dart format` shape', () async {
      bool formatted() =>
          Process.runSync(Platform.resolvedExecutable, <String>[
            'format',
            '--output=none',
            '--set-exit-if-changed',
            'db/migration/migrations.dart',
          ]).exitCode ==
          0;

      /// no Dart migrations: an empty list
      Directory('db/migration').createSync(recursive: true);
      writeMigrationRegistry();
      expect(formatted(), isTrue);

      /// a short name fits on one line, a long one is split
      await run(<String>['create_posts_table']);
      await run(<String>['add_a_really_long_column_name_here_to_posts_table']);
      expect(formatted(), isTrue);

      /// names of every length around the 80-character limit, and more
      /// than 9 migrations (`m10` is one character longer than `m9`)
      for (int length = 20; length <= 70; length++) {
        File('db/migration/${'a' * length}.dart')
            .writeAsStringSync('class A extends Migration {}');
      }
      writeMigrationRegistry();
      expect(formatted(), isTrue);
    });

    test('makes bin/migrate.dart once', () async {
      await run(<String>['create_a_table']);
      expect(
        read('bin/migrate.dart'),
        contains('Migrator(migrations: migrations)'),
      );
      File('bin/migrate.dart').writeAsStringSync('// mine');
      await run(<String>['create_b_table']);
      expect(read('bin/migrate.dart'), '// mine');
    });

    test('migrate makes a missing bin/migrate.dart and goes on', () async {
      /// like a file from `dox queue:table`, with no bin/migrate.dart yet
      File('db/migration/2020_01_01_000000_create_queue_tables.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('class CreateQueueTables extends Migration {}');
      await CommandRegistry.findCommand('migration:status')!
          .function(<String>[]);
      expect(read('bin/migrate.dart'), contains('Migrator('));
      expect(
        read('db/migration/migrations.dart'),
        contains('CreateQueueTables'),
      );
      exitCode = 0;
    });

    test('--sql flag writes a sql file, no registry', () async {
      List<File> files = await run(<String>['add_index', '--sql']);
      expect(files.single.path, endsWith('add_index.sql'));
      String c = files.single.readAsStringSync();
      expect(c, contains('-- up'));
      expect(c, contains('-- down'));
      expect(File('bin/migrate.dart').existsSync(), isFalse);
    });

    test('create:migration is an alias', () {
      expect(
        CommandRegistry.findCommand('create:migration')?.command,
        'make:migration',
      );
    });

    test('three migrations in the same second sort in order', () async {
      await run(<String>['create_c_table']);
      await run(<String>['create_b_table']);
      List<File> files = await run(<String>['create_a_table', '--sql']);
      List<String> names = files
          .map(fileName)
          .where((String n) => n != 'migrations.dart')
          .toList();
      expect(names, hasLength(3));
      expect(names[0], endsWith('_create_c_table.dart'));
      expect(names[1], endsWith('_create_b_table.dart'));
      expect(names[2], endsWith('_create_a_table.sql'));
      Set<String> stamps = names.map((String n) => n.substring(0, 17)).toSet();
      expect(stamps, hasLength(3));
    });

    test('a future-dated file still gets a later one', () async {
      Directory('db/migration').createSync(recursive: true);
      File('db/migration/2999_12_31_235959_future.sql').writeAsStringSync('');
      List<File> files = await run(<String>['create_x_table']);
      List<String> names = files
          .map(fileName)
          .where((String n) => n != 'migrations.dart')
          .toList();
      expect(names, <String>[
        '2999_12_31_235959_future.sql',
        '3000_01_01_000000_create_x_table.dart',
      ]);
    });

    test('creates the db/migration folder when missing', () async {
      expect(Directory('db').existsSync(), isFalse);
      await run(<String>['first']);
      expect(Directory('db/migration').existsSync(), isTrue);
    });
  });

  group('make:factory and make:seeder', () {
    test('factory imports the model with the app package name', () {
      File('pubspec.yaml').writeAsStringSync('name: my_app\n');
      expect(createFactory('BlogPostFactory'), isTrue);
      String c = read('db/factories/blog_post.factory.dart');
      expect(c, contains("import 'package:dox_orm/factory.dart';"));
      expect(
        c,
        contains(
          "import 'package:my_app/app/models/blog_post/blog_post.model.dart';",
        ),
      );
      expect(c, contains('class BlogPostFactory extends Factory<BlogPost> {'));
      expect(c, contains('BlogPost definition() {'));
      expect(c, contains('BlogPost blogPost = BlogPost();'));
      expect(createFactory('BlogPost'), isFalse);
    });

    test('factory needs a pubspec name', () {
      expect(createFactory('User'), isFalse);
      exitCode = 0;
      expect(Directory('db').existsSync(), isFalse);
    });

    test('seeder, registry and bin/seed.dart', () {
      expect(createSeeder('DatabaseSeeder'), isTrue);
      expect(createSeeder('user'), isTrue);
      expect(createSeeder('UserSeeder'), isFalse);
      String c = read('db/seeders/user.seeder.dart');
      expect(c, contains("import 'package:dox_migration/dox_migration.dart';"));
      expect(c, contains('class UserSeeder extends Seeder {'));
      expect(c, contains('Future<void> run() async {'));

      String registry = read('db/seeders/seeders.dart');
      expect(registry, contains("import 'database.seeder.dart';"));
      expect(registry, contains("import 'user.seeder.dart';"));
      expect(registry, contains('<Seeder>[DatabaseSeeder(), UserSeeder()];'));
      expect(registry, isNot(contains("import 'seeders.dart'")));

      expect(
        read('bin/seed.dart'),
        contains('SeederRunner(seeders: seeders).run(args)'),
      );
      File('bin/seed.dart').writeAsStringSync('// mine');
      createSeeder('Post');
      expect(read('bin/seed.dart'), '// mine');
    });

    test('registry finds every seeder class of the folder', () {
      Directory('db/seeders').createSync(recursive: true);
      File('db/seeders/extra.dart').writeAsStringSync(
        'class A extends Seeder {}\nclass B extends Seeder {}\nclass C {}',
      );
      writeSeederRegistry();
      String registry = read('db/seeders/seeders.dart');
      expect(registry, contains("import 'extra.dart';"));
      expect(registry, contains('<Seeder>[A(), B()];'));
      expect(registry, isNot(contains('C()')));
    });

    test('a long registry list has one seeder per line', () {
      Directory('db/seeders').createSync(recursive: true);
      File('db/seeders/many.dart').writeAsStringSync(
        <String>[
          for (int i = 0; i < 6; i++)
            'class LongNameSeeder$i extends Seeder {}',
        ].join('\n'),
      );
      writeSeederRegistry();
      expect(
        read('db/seeders/seeders.dart'),
        contains('<Seeder>[\n  LongNameSeeder0(),\n  LongNameSeeder1(),\n'),
      );
    });

    test('db:seed without bin/seed.dart fails', () async {
      await CommandRegistry.findCommand('db:seed')!.function(<String>[]);
      expect(exitCode, 1);
      exitCode = 0;
    });

    test('aliases', () {
      expect(
        CommandRegistry.findCommand('create:factory')?.command,
        'make:factory',
      );
      expect(
        CommandRegistry.findCommand('create:seeder')?.command,
        'make:seeder',
      );
      expect(
        CommandRegistry.findCommand('migrate:fresh')?.command,
        'migration:fresh',
      );
      expect(
        CommandRegistry.findCommand('db:seed')!
            .validateArgs(<String>['--class=UserSeeder']),
        isTrue,
      );
    });

    test('db:seed takes --class with a space too', () {
      CommandDefinition seed = CommandRegistry.findCommand('db:seed')!;
      expect(seed.validateArgs(<String>['--class', 'UserSeeder']), isTrue);
      expect(seed.validateArgs(<String>['a', 'b', 'c']), isFalse);
    });
  });

  group('generators | doc comments', () {
    /// `<String>` in a doc comment, outside backticks, is the analyzer
    /// info unintended_html_in_doc_comment in the app
    test('no <...> outside backticks', () async {
      File('pubspec.yaml').writeAsStringSync('name: my_app\n');
      createController('PostController', true);
      createModel('Post');
      createMiddleware('AuthMiddleware');
      createDto('PostDto');
      createSerializer('PostSerializer');
      createFactory('PostFactory');
      createSeeder('PostSeeder');
      createJob('SendMailJob');
      await CommandRegistry.findCommand('make:migration')!
          .function(<String>['create_posts_table']);
      RegExp doc = RegExp(r'^\s*///(.*)$');
      RegExp code = RegExp(r'`[^`]*`');

      /// only a tag like `<String>` or `</p>`, not `a < b`
      RegExp tag = RegExp(r'<[A-Za-z/]');
      List<String> bad = <String>[];
      for (FileSystemEntity f in Directory.current.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (String line in f.readAsLinesSync()) {
          Match? m = doc.firstMatch(line);
          if (m != null && m.group(1)!.replaceAll(code, '').contains(tag)) {
            bad.add('${f.path}: $line');
          }
        }
      }
      expect(bad, isEmpty);
    });
  });

  group('dox binary', () {
    test('make files through the real cli in a temp dir', () async {
      String bin = '${originalCwd.path}/bin/dox.dart';
      ProcessResult r = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        bin,
        'make:model',
        'Post',
      ], workingDirectory: tempDir.path);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(
        File('${tempDir.path}/lib/app/models/post/post.model.dart')
            .existsSync(),
        isTrue,
      );
    });

    test('no command, unknown command and bad args exit with 1', () async {
      String bin = '${originalCwd.path}/bin/dox.dart';
      for (List<String> args in <List<String>>[
        <String>[],
        <String>['no:such:command'],
        <String>['make:model'],
      ]) {
        ProcessResult r = await Process.run(
          Platform.resolvedExecutable,
          <String>['run', bin, ...args],
          workingDirectory: tempDir.path,
        );
        expect(r.exitCode, 1, reason: '$args: ${r.stdout}${r.stderr}');
      }
    });

    test('a command that throws exits with 1', () async {
      // key:generate with no .env: reading the file throws
      String bin = '${originalCwd.path}/bin/dox.dart';
      ProcessResult r = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', bin, 'key:generate'],
        workingDirectory: tempDir.path,
        environment: <String, String>{'APP_ENV': 'development'},
      );
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('.env'));
      expect(File('${tempDir.path}/.env').existsSync(), isFalse);
    });
  });

  group('generators | unsafe names', () {
    Map<String, bool Function(String)> generators =
        <String, bool Function(String)>{
          'controller': (String n) => createController(n, false),
          'middleware': createMiddleware,
          'model': createModel,
          'dto': createDto,
          'serializer': createSerializer,
          'factory': createFactory,
          'seeder': createSeeder,
          'job': createJob,
        };
    List<String> names = <String>[
      '../../../../escape',
      '..',
      '/tmp/escape',
      'admin/User',
      r'a\b',
      'bad name',
      '1user',
      '',
    ];

    for (MapEntry<String, bool Function(String)> g in generators.entries) {
      test('${g.key} rejects names that are not plain Dart names', () {
        File('pubspec.yaml').writeAsStringSync('name: my_app\n');
        for (String name in names) {
          expect(g.value(name), isFalse, reason: name);
          expect(exitCode, 1, reason: name);
          exitCode = 0;
        }
        List<String> made = tempDir
            .listSync(recursive: true)
            .map((FileSystemEntity e) => e.path)
            .toList();
        expect(made, <String>['${tempDir.path}/pubspec.yaml']);
        // `../../../../escape` would land next to the temp dir
        expect(
          tempDir.parent.listSync().where(
            (FileSystemEntity e) => path.basename(e.path).startsWith('escape'),
          ),
          isEmpty,
        );
      });
    }

    test('generatorName keeps good names', () {
      expect(generatorName('BlogPostController', 'controller'), 'blog_post');
      expect(generatorName('user_2'), 'user_2');
      expect(generatorName('../x'), isNull);
      expect(generatorName('Controller', 'controller'), isNull);
      exitCode = 0;
    });
  });
}
