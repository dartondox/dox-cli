import 'package:dox/src/utils/confirm_drop.dart';
import 'package:test/test.dart';

void main() {
  Map<String, String> prod = <String, String>{'APP_ENV': 'production'};

  String? fail() => throw StateError('must not ask');

  test('not production: runs, no question', () {
    expect(
      confirmDropAll(
        force: false,
        env: <String, String>{'APP_ENV': 'local'},
        terminal: true,
        ask: fail,
      ),
      isTrue,
    );
    expect(
      confirmDropAll(force: false, env: {}, terminal: true, ask: fail),
      isTrue,
    );
  });

  test('production with --force: runs, no question', () {
    expect(
      confirmDropAll(force: true, env: prod, terminal: true, ask: fail),
      isTrue,
    );
  });

  test('production, no terminal: warns and runs', () {
    expect(
      confirmDropAll(force: false, env: prod, terminal: false, ask: fail),
      isTrue,
    );
  });

  test('production, terminal: runs only on y', () {
    for (String? answer in <String?>['y', 'Y', ' y ']) {
      expect(
        confirmDropAll(
          force: false,
          env: prod,
          terminal: true,
          ask: () => answer,
        ),
        isTrue,
      );
    }
    for (String? answer in <String?>['', 'n', 'yes', null]) {
      expect(
        confirmDropAll(
          force: false,
          env: prod,
          terminal: true,
          ask: () => answer,
        ),
        isFalse,
      );
    }
  });
}
