import 'dart:async';
import 'dart:io';

import 'package:dox/src/command_registry.dart';
import 'package:dox/src/tools/route_list.dart';
import 'package:test/test.dart';

void main() {
  group('RouteRow labels |', () {
    test('a named function gives its name', () {
      expect(
        RouteRow.label("Closure: () => String from Function 'pong':."),
        'pong',
      );
      expect(
        RouteRow.label("Closure: (int) => String from Function 'top': static."),
        'top',
      );
    });

    test('a function with no name is Closure, a class name stays', () {
      expect(RouteRow.label('Closure: (DoxRequest) => String'), 'Closure');
      expect(RouteRow.label('AuthMiddleware'), 'AuthMiddleware');
    });

    test('(C c) => c.index gives C.index', () {
      expect(
        RouteRow.handlerLabel(
          'Closure: (WebController) => () => String',
          "Closure: () => String from Function 'pong':.",
          null,
        ),
        'WebController.pong',
      );
    });

    test('Route.get<C> gives C.index', () {
      expect(
        RouteRow.handlerLabel(
          'Closure: (UserController) => (DoxRequest) => dynamic',
          "Closure: (DoxRequest) => dynamic from Function 'index':.",
          'UserController',
        ),
        'UserController.index',
      );
    });

    test('a plain function handler', () {
      String fn = 'Closure: (DoxRequest) => String';
      expect(RouteRow.handlerLabel(fn, fn, null), 'Closure');
    });

    test('fromJson builds the row', () {
      RouteRow row = RouteRow.fromJson(<String, dynamic>{
        'method': 'GET',
        'path': '/api/ping',
        'name': 'api.ping',
        'handler': 'Closure: (ApiController) => () => String',
        'controller': null,
        'action': "Closure: () => String from Function 'pong':.",
        'middleware': <dynamic>['LogMiddleware', 'Closure: () => void'],
      });
      expect(row.handler, 'ApiController.pong');
      expect(row.middleware, <String>['LogMiddleware', 'Closure']);
    });
  });

  test('findData reads the line after the marker', () {
    String out = 'some log line\n${RouteList.marker}[{"a":1}]\n';
    expect(RouteList.findData(out), '[{"a":1}]');
    expect(RouteList.findData('no marker'), isNull);
  });

  test('table lines up the columns', () {
    String text = RouteList.table(<RouteRow>[
      RouteRow(
        method: 'GET',
        path: '/api/ping',
        name: 'api.ping',
        handler: 'ApiController.pong',
        middleware: <String>['LogMiddleware'],
      ),
      RouteRow(
        method: 'POST',
        path: '/users',
        name: null,
        handler: 'Closure',
        middleware: <String>[],
      ),
    ]);
    expect(
      text,
      'METHOD  PATH       NAME      HANDLER             MIDDLEWARE\n'
      'GET     /api/ping  api.ping  ApiController.pong  LogMiddleware\n'
      'POST    /users               Closure\n'
      '\n'
      '2 routes',
    );
    expect(RouteList.table(<RouteRow>[]), 'The app has no routes.');
  });

  test('the script uses the app package and loadRoutes', () {
    String source = RouteList.scriptSource('blog');
    expect(source, contains("import 'package:blog/config/app.dart';"));
    expect(source, contains('Dox().loadRoutes()'));
    expect(source, contains("'${RouteList.marker}\${jsonEncode(out)}'"));
  });

  group('route:list command |', () {
    late Directory tempDir;
    late Directory originalCwd;

    setUp(() {
      originalCwd = Directory.current;
      tempDir = Directory.systemTemp.createTempSync('dox_route_list_test_');
      Directory.current = tempDir;
    });

    tearDown(() {
      exitCode = 0;
      Directory.current = originalCwd;
      tempDir.deleteSync(recursive: true);
    });

    Future<String> run(List<String> args) async {
      StringBuffer out = StringBuffer();
      await runZoned(
        () => CommandRegistry.findCommand('route:list')!.function(args),
        zoneSpecification: ZoneSpecification(
          print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
            out.writeln(line);
          },
        ),
      );
      return out.toString();
    }

    test('no app: clear message and exit code 1', () async {
      expect(await run(<String>[]), contains('No Dox app found here'));
      expect(exitCode, 1);
    });

    test('an unknown option: exit code 1', () async {
      expect(await run(<String>['--yaml']), contains('Unknown option'));
      expect(exitCode, 1);
    });
  });
}
