import 'dart:io';

import '../utils/utils.dart';

String _getSample(String className, String filename) {
  return '''
import 'package:dox_core/dox_core.dart';

/// Route: Route.get('path', (${className}Controller c) => c.index);
@Inject()
class ${className}Controller {
  Future<dynamic> index(DoxRequest req) async {
    /// write your logic here
  }
}
''';
}

/// A resource controller. [api] leaves out the form pages `create` and
/// `edit`. With [model] (the snake name, like `blog_post`) the actions use
/// that model, imported from [package].
String _getResourceSample(
  String className, {
  bool api = false,
  String? model,
  String? package,
}) {
  String m = model == null ? '' : snakeToPascal(model);
  String v = model == null ? '' : toPascalWithFirstLetterLowerCase(model);
  List<String> imports = <String>[
    "import 'package:dox_core/dox_core.dart';",
    if (model != null)
      "import 'package:$package/app/models/$model/$model.model.dart';",
  ]..sort();
  List<String> methods = <String>[
    _method('GET /resource', 'index(DoxRequest req)', <String>[
      if (model != null) 'return $m().all();',
    ]),
    if (!api) _method('GET /resource/create', 'create(DoxRequest req)'),
    _method(
      model == null
          ? 'POST /resource'
          : 'POST /resource\n  /// create() takes only the fillable columns of $m.',
      'store(DoxRequest req)',
      <String>[if (model != null) 'return $m().create(req.body);'],
    ),
    _method(
      model == null ? 'GET /resource/{id}' : 'GET /resource/{id}\n  /// findOrFail() answers 404 when there is no row.',
      'show(DoxRequest req, int id)',
      <String>[if (model != null) 'return $m().findOrFail(id);'],
    ),
    if (!api)
      _method(
        'GET /resource/{id}/edit',
        'edit(DoxRequest req, int id)',
        <String>[if (model != null) 'return $m().findOrFail(id);'],
      ),
    _method(
      'PUT|PATCH /resource/{id}',
      'update(DoxRequest req, int id)',
      <String>[
        if (model != null) ...<String>[
          '$m $v = await $m().findOrFail(id);',
          'await $v.update(req.body);',
          'return $v;',
        ],
      ],
    ),
    _method(
      model == null
          ? 'DELETE /resource/{id}\n'
                '  /// delete() gives the number of rows it deleted, so 0 is a 404:\n'
                "  /// `if (await Post().where('id', id).delete() == 0) throw NotFoundHttpException();`"
          : 'DELETE /resource/{id}',
      'destroy(DoxRequest req, int id)',
      <String>[
        if (model != null) ...<String>[
          '$m $v = await $m().findOrFail(id);',
          'await $v.delete();',
        ],
      ],
    ),
  ];
  return '''
${imports.join('\n')}

/// Route: Route.resource('path', ${className}Controller);
@Inject()
class ${className}Controller {
${methods.join('\n\n')}
}
''';
}

/// one action: `/// doc`, then the method with [body] lines
String _method(String doc, String signature, [List<String> body = const []]) {
  String head = '  /// $doc\n  Future<dynamic> $signature async {';
  if (body.isEmpty) return '$head}';
  return '$head\n${body.map((String l) => '    $l\n').join()}  }';
}

/// [api] (only with [resource]) leaves out `create` and `edit`.
/// [model] (only with [resource]) is a model name, like `Post`: the
/// actions use it. It needs the app name from `pubspec.yaml`.
bool createController(
  String filename,
  bool resource, {
  bool api = false,
  String? model,
}) {
  String? name = generatorName(filename, 'controller');
  if (name == null) return false;
  String? package;
  if (model != null) {
    model = generatorName(model);
    if (model == null) return false;
    package = appPackageName();
    if (package == null) {
      print('pubspec.yaml has no name. Run this in the app folder.');
      exitCode = 1;
      return false;
    }
  }
  filename = name;
  String className = snakeToPascal(filename);
  String path = '${Directory.current.path}/lib/app/http/controllers/';
  String controllerName = '$filename.controller';
  final file = File('$path$filename.controller.dart');

  if (file.existsSync()) {
    print('\x1B[32m$controllerName already exists\x1B[0m');
    return false;
  }

  String sample = resource
      ? _getResourceSample(className, api: api, model: model, package: package)
      : _getSample(className, filename);

  file.createSync(recursive: true);
  file.writeAsStringSync(sample, mode: FileMode.write);
  print('\x1B[32m$controllerName created successfully.\x1B[0m');
  if (model != null &&
      !File('${Directory.current.path}/lib/app/models/$model/$model.model.dart')
          .existsSync()) {
    print(
      '\x1B[33mThe ${snakeToPascal(model)} model does not exist yet. '
      'Run `dox make:model ${snakeToPascal(model)}`.\x1B[0m',
    );
  }
  print('Run `dart run build_runner build` to add it to the container.');
  return true;
}
