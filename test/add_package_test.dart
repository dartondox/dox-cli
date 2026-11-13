import 'dart:io';

import 'package:dox/src/tools/add_package.dart';
import 'package:test/test.dart';

void main() {
  test('the short name gets the dox_ prefix', () {
    expect(AddPackage.packageName('orm'), 'dox_orm');
    expect(AddPackage.packageName('dox_orm'), 'dox_orm');
    expect(AddPackage.packageName('dox-queue-database'), 'dox_queue_database');
    expect(AddPackage.packageName('Bad Name'), isNull);
    expect(AddPackage.packageName('../x'), isNull);
  });

  test('outside an app it stops with exit code 1', () async {
    Directory root = Directory.systemTemp.createTempSync('dox_add_');
    addTearDown(() => root.deleteSync(recursive: true));
    await AddPackage(root: root).run(<String>['orm']);
    expect(exitCode, 1);
    exitCode = 0;
  });
}
