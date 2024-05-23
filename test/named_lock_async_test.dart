import 'dart:async';

import 'package:runtime_named_locks/runtime_named_locks.dart'
    show ExecutionCall, NamedLock;
import 'package:test/test.dart';

class IntentionalTestException implements Exception {
  final String message;
  // ignore: unreachable_from_main
  IntentionalTestException(
      {this.message = "Intentional test exception message."});
  @override
  String toString() => message;
}

void main() {
  test('check guard implements async callbacks correctly', () async {
    final results = <String>[];

    final execution = ExecutionCall<FutureOr<void>, IntentionalTestException>(
      callable: () async {
        results.add('line 1');
        await Future.delayed(Duration(milliseconds: 100), () {
          results.add('line 2');
        });
      },
      safe: true,
    );

    await NamedLock.guard<void, IntentionalTestException>(
        name: 'async test', execution: execution);

    results.add('line 3');

    await Future.delayed(Duration(milliseconds: 500), () {});

    expect(results.length, 3);
    expect(results[0], 'line 1');
    expect(results[1], 'line 2');
    expect(results[2], 'line 3');
  });
}
