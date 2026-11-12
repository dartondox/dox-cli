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

    Map<String, dynamic> wsJson(bool websocket) => <String, dynamic>{
      'method': 'GET',
      'path': '/ws',
      'name': null,
      'handler':
          "Closure: (DoxRequest) => Future<WebSocket> from Function 'call':.",
      'controller': null,
      'action':
          "Closure: (DoxRequest) => Future<WebSocket> from Function 'call':.",
      'websocket': websocket,
      'middleware': <dynamic>[],
    };

    test('a websocket route shows WebSocket', () {
      expect(RouteRow.fromJson(wsJson(true)).handler, 'WebSocket');
    });

    test('a user callable that gives Future<WebSocket> is not WebSocket', () {
      expect(RouteRow.fromJson(wsJson(false)).handler, 'call');
    });

    test('the script sends isWebSocket', () {
      expect(
        RouteList.scriptSource('blog'),
        contains("'websocket': r.isWebSocket"),
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

  test('findData works when app output has no newline before the marker', () {
    String out = 'log without newline${RouteList.marker}[1]\nlater line\n';
    expect(RouteList.findData(out), '[1]');
    expect(RouteList.findData('x${RouteList.marker}[2]'), '[2]');
  });

  test('the script lists global middleware for a middleware mount', () {
    String source = RouteList.scriptSource('blog');
    expect(source, contains('loaded.mountsWithMiddleware.contains(m.key)'));
    expect(source, contains('Dox().config.globalMiddleware'));
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

    test('route:list is registered', () {
      expect(CommandRegistry.findCommand('route:list'), isNotNull);
    });

    /// run the command, give what went to stdout and to stderr
    Future<(String, String)> run(List<String> args) async {
      StringBuffer out = StringBuffer();
      StringBuffer err = StringBuffer();
      await runZoned(
        () => RouteList(err: err).run(args),
        zoneSpecification: ZoneSpecification(
          print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
            out.writeln(line);
          },
        ),
      );
      return (out.toString(), err.toString());
    }

    test('no app: clear message on stderr and exit code 1', () async {
      var (String out, String err) = await run(<String>['--json']);
      expect(out, isEmpty);
      expect(err, contains('No Dox app found here'));
      expect(exitCode, 1);
    });

    test('a failing script: message on stderr, stdout stays empty', () async {
      File('pubspec.yaml').writeAsStringSync('name: broken_app\n');
      File('lib/config/app.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('this is not dart');
      var (String out, String err) = await run(<String>['--json']);
      expect(out, isEmpty);
      expect(err, contains('Could not load the routes'));
      expect(exitCode, 1);
    });

    test('an unknown option: exit code 1', () async {
      var (String out, String err) = await run(<String>['--yaml']);
      expect(out, isEmpty);
      expect(err, contains('Unknown option'));
      expect(exitCode, 1);
    });
  });
}
