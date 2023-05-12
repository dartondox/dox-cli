import 'package:dox/dox.dart';
import 'package:dox/src/tools/create_controller.dart';
import 'package:dox/src/tools/create_middleware.dart';
import 'package:dox/src/tools/create_project.dart';
import 'package:dox/src/tools/db_migrate_rollback.dart';
import 'package:dox/src/tools/generate_key.dart';
import 'package:dox/src/tools/server_serve.dart';
import 'package:dox/src/tools/update_dox.dart';

void main(List<String> args) async {
  List<String> versionKeys = [
    '--version',
    'version',
    '-version',
    'v',
    '-v',
    '--v'
  ];

  if (args.length == 1 && versionKeys.contains(args[0])) {
    print('Dox version: 1.0.46');
  }

  if (args.length == 2 && args[0] == 'create') {
    createProject(args[1]);
  }

  if (args.length == 2 && args[0] == 'create:migration') {
    createMigration(args[1]);
  }

  if (args.length == 2 && args[0] == 'create:model') {
    createModel(args[1]);
  }

  if (args.length == 3 && args[0] == 'create:model' && args[2] == '-m') {
    bool shouldCreateMigration = createModel(args[1]);
    if (shouldCreateMigration) {
      createMigration('Create${args[1]}Table');
    }
  }

  if (args.length == 1 && args[0] == 'migrate') {
    dbMigrate();
  }

  if (args.length == 1 && args[0] == 'migrate:rollback') {
    dbRollback();
  }

  List<String> serveKeys = [
    'serve',
    'server',
    's',
  ];

  if (args.length == 1 && serveKeys.contains(args[0])) {
    serverServe();
  }

  if (args.length == 2 &&
      serveKeys.contains(args[0]) &&
      args[1] == '--watch-build-runner') {
    watchBuilder();
    serverServe();
  }

  if (args.length == 1 && args[0] == 'build_runner:watch') {
    watchBuilder();
  }

  if (args.length == 1 && args[0] == 'build_runner:build') {
    buildBuilder();
  }

  if (args.length == 1 && args[0] == 'build') {
    buildBuilder();
    buildServer();
  }

  if (args.length == 1 && args[0] == 'update') {
    updateDox();
  }

  if (args.length == 2 && args[0] == 'create:controller') {
    createController(args[1], false);
  }

  if (args.length == 2 && args[0] == 'create:middleware') {
    createMiddleware(args[1]);
  }

  if (args.length == 3 && args[0] == 'create:controller' && args[2] == '-r') {
    createController(args[1], true);
  }

  if (args.length == 3 && args[0] == 'create:controller' && args[1] == '-r') {
    createController(args[2], true);
  }

  if (args.length == 1 && args[0] == 'key:generate') {
    generateKey();
  }
}
