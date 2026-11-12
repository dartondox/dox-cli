import 'dart:convert';
import 'dart:io';

import '../utils/run_script.dart';
import '../utils/utils.dart';

/// `dox route:list [--json]`: print every route of the app.
///
/// The CLI can not import the app, so it writes a small script into
/// `.dart_tool/dox/route_list.dart` and runs it with `dart run`. The
/// script calls `Dox().loadRoutes()` (dox_core), which registers the
/// routes of the app routers without a server and without providers.
/// It prints the routes as one JSON line after [RouteList.marker]. The
/// CLI reads that line and prints the table.
class RouteList {
  RouteList({StringSink? err}) : _err = err ?? stderr;

  /// error text goes here, not to stdout, so `--json` output stays clean
  final StringSink _err;

  /// the script prints the JSON of the routes after this text
  static const String marker = '__DOX_ROUTES__';

  /// run the command. Sets exit code 1 when there is no app or the
  /// script fails.
  Future<void> run(List<String> args) async {
    bool json = args.contains('--json');
    List<String> unknown = <String>[
      for (String arg in args)
        if (arg != '--json') arg,
    ];
    if (unknown.isNotEmpty) {
      _err.writeln(
        'Unknown option: ${unknown.join(' ')}. Usage: dox route:list [--json]',
      );
      exitCode = 1;
      return;
    }
    String root = Directory.current.path;
    String? name = appPackageName();
    if (name == null || !File('$root/lib/config/app.dart').existsSync()) {
      _err.writeln(
        'No Dox app found here. Run `dox route:list` in the app folder '
        '(it needs pubspec.yaml and lib/config/app.dart).',
      );
      exitCode = 1;
      return;
    }
    File script = File('$root/.dart_tool/dox/route_list.dart');
    script.createSync(recursive: true);
    script.writeAsStringSync(scriptSource(name));
    ProcessResult result = await Process.run(dartExecutable(), <String>[
      'run',
      script.path,
    ]);
    String out = result.stdout.toString();
    String? data = findData(out);
    if (result.exitCode != 0 || data == null) {
      String err = result.stderr.toString();
      _err.writeln('Could not load the routes. The route script failed:');
      _err.write(out);
      _err.write(err);
      if ('$out$err'.contains("'loadRoutes' isn't defined")) {
        _err.writeln(
          'Your dox_core is too old: it has no Dox().loadRoutes(). '
          'Run `dart pub upgrade dox_core`.',
        );
      }
      exitCode = 1;
      return;
    }
    List<Map<String, dynamic>> routes = <Map<String, dynamic>>[
      for (Object? item in jsonDecode(data) as List<dynamic>)
        Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
    ];
    List<RouteRow> rows = <RouteRow>[
      for (Map<String, dynamic> route in routes) RouteRow.fromJson(route),
    ];
    if (json) {
      print(
        jsonEncode(<Map<String, Object?>>[
          for (RouteRow row in rows) row.toJson(),
        ]),
      );
      return;
    }
    print(table(rows));
  }

  /// the JSON after the last [marker] in the script output, up to the
  /// end of that line, or null. App output before it may have no newline.
  static String? findData(String out) {
    int start = out.lastIndexOf(marker);
    if (start < 0) return null;
    start += marker.length;
    int end = out.indexOf('\n', start);
    return out.substring(start, end < 0 ? out.length : end).trim();
  }

  /// the routes as a text table, one route per line
  static String table(List<RouteRow> rows) {
    if (rows.isEmpty) return 'The app has no routes.';
    List<List<String>> cells = <List<String>>[
      <String>['METHOD', 'PATH', 'NAME', 'HANDLER', 'MIDDLEWARE'],
      for (RouteRow row in rows)
        <String>[
          row.method,
          row.path,
          row.name ?? '',
          row.handler,
          row.middleware.join(', '),
        ],
    ];
    List<int> widths = List<int>.filled(5, 0);
    for (List<String> line in cells) {
      for (int i = 0; i < line.length; i++) {
        if (line[i].length > widths[i]) widths[i] = line[i].length;
      }
    }
    StringBuffer out = StringBuffer();
    for (List<String> line in cells) {
      List<String> padded = <String>[
        for (int i = 0; i < line.length; i++)
          i == line.length - 1 ? line[i] : line[i].padRight(widths[i]),
      ];
      out.writeln(padded.join('  ').trimRight());
    }
    out.write('\n${rows.length} routes');
    return out.toString();
  }

  /// the script that runs inside the app. It only collects raw text.
  /// [RouteRow] turns that text into short labels.
  static String scriptSource(String package) {
    return '''
// Made by `dox route:list`. Do not edit, it is written again each time.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';

import 'package:dox_core/dox_core.dart';
import 'package:dox_core/router/route_data.dart';
import 'package:$package/config/app.dart';

Future<void> main() async {
  Dox().initialize(appConfig);
  AppRoutes loaded = Dox().loadRoutes();
  List<Map<String, Object?>> out = <Map<String, Object?>>[
    for (RouteData r in loaded.routes) _route(r, r.method),
    for (RouteData r in loaded.fallbacks) _route(r, 'FALLBACK'),
    for (MapEntry<String, Function> m in loaded.mounts.entries)
      <String, Object?>{
        'method': 'MOUNT',
        'path': m.key,
        'handler': m.value.toString(),
        // `Route.mount(..., middleware: true)` runs the global middleware
        'middleware': <String>[
          if (loaded.mountsWithMiddleware.contains(m.key))
            for (Object? g in Dox().config.globalMiddleware) _text(g),
        ],
      },
  ];
  stdout.writeln('$marker\${jsonEncode(out)}');
  await stdout.flush();
  // a config may open a connection that keeps the process alive
  exit(0);
}

Map<String, Object?> _route(RouteData r, String method) {
  Object? c = r.controllers;
  List<dynamic> list = c is List ? c : <dynamic>[c];
  Object? last = list.isEmpty ? null : list.last;
  String? action;
  try {
    action = r.action?.toString();
  } catch (_) {
    // the controller is not in the container: show the raw handler
  }
  return <String, Object?>{
    'method': method,
    'path': r.domain == null ? r.path : '\${r.domain}\${r.path}',
    'name': r.name,
    'handler': _text(last),
    'controller': last is ControllerAction ? '\${last.controller}' : null,
    'action': action,
    'middleware': <String>[
      for (int i = 0; i < list.length - 1; i++) _text(list[i]),
    ],
  };
}

String _text(Object? item) {
  return item is Function ? item.toString() : '\${item.runtimeType}';
}
''';
  }
}

/// one route for the table, with short labels
class RouteRow {
  RouteRow({
    required this.method,
    required this.path,
    required this.name,
    required this.handler,
    required this.middleware,
  });

  final String method;
  final String path;
  final String? name;
  final String handler;
  final List<String> middleware;

  /// from one item of the script JSON. The script sends the raw
  /// `toString()` of the functions, like
  /// `Closure: () => String from Function 'pong':.`
  factory RouteRow.fromJson(Map<String, dynamic> json) {
    String handler = json['handler'] as String? ?? '';
    String? action = json['action'] as String?;
    String? controller = json['controller'] as String?;
    return RouteRow(
      method: json['method'] as String,
      path: json['path'] as String,
      name: json['name'] as String?,
      handler: handlerLabel(handler, action, controller),
      middleware: <String>[
        for (Object? item in json['middleware'] as List<dynamic>)
          label(item as String),
      ],
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'method': method,
      'path': path,
      'name': name,
      'handler': handler,
      'middleware': middleware,
    };
  }

  /// `UserController.index` for a controller route, else the function
  /// name, or `Closure` for a function with no name.
  static String handlerLabel(
    String handler,
    String? action,
    String? controller,
  ) {
    // `Route.websocket`: its handler is `Future<WebSocket> call(DoxRequest)`
    if (_webSocket.hasMatch(handler)) return 'WebSocket';
    // `Route.get<C>(path, (C c) => c.index)`
    if (controller != null) {
      return action == null ? controller : '$controller.${label(action)}';
    }
    // `(C c) => c.index`: the action is the method that the function picks
    if (action != null && action != handler) {
      RegExpMatch? type = _firstParam.firstMatch(handler);
      String method = label(action);
      return type == null ? method : '${type.group(1)}.$method';
    }
    return label(handler);
  }

  /// the name of a function from its `toString()`, `Closure` when it has
  /// none. Any other text is a class name and stays.
  static String label(String text) {
    if (!text.startsWith('Closure:')) return text;
    return _functionName.firstMatch(text)?.group(1) ?? 'Closure';
  }

  static final RegExp _webSocket = RegExp(
    r"=> Future<WebSocket> from Function 'call'",
  );

  static final RegExp _functionName = RegExp(r"from Function '([^']+)'");

  static final RegExp _firstParam = RegExp(r'^Closure: \(([\w$]+)\)');
}
