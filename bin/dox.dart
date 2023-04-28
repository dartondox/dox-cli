import 'package:dox/dox.dart';

void main(List<String> args) {
  if (args.length == 2 && args[0] == 'create:migration') {
    createMigration(args[1]);
  }

  if (args.length == 2 && args[0] == 'create:model') {
    createModel(args[1]);
  }

  if (args.length == 1 && args[0] == 'migrate') {
    dbMigrate();
  }
}
