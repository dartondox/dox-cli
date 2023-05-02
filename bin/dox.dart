import 'package:dox/dox.dart';
import 'package:dox/src/tools/db_migrate_rollback.dart';
import 'package:dox/src/tools/server_serve.dart';
import 'package:dox/src/tools/update_dox.dart';
import 'package:dox/src/utils/nodemon.dart';

void main(List<String> args) async {
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

  if (args.length == 1 && args[0] == 'serve') {
    installNodemonIfNotExist();
    serverServe();
    watchBuilder();
  }

  if (args.length == 1 && args[0] == 'build') {
    buildBuilder();
    buildServer();
  }

  if (args.length == 1 && args[0] == 'update') {
    updateDox();
  }

  List<String> versionKeys = [
    '--version',
    'version',
    '-version',
    'v',
    '-v',
    '--v'
  ];

  if (args.length == 1 && versionKeys.contains(args[0])) {
    print('Dox version: 1.0.22');
  }
}
