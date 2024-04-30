import 'dart:async' show Completer, Future;
import 'package:runtime_native_semaphores/runtime_native_semaphores.dart' show LatePropertyAssigned;

typedef ExecutionCallType<R> = R Function();

class ExecutionCall<R> {
  final completer = Completer<R>();

  final ExecutionCallType<R> _callable;

  late final R returned;

  bool? successful;

  dynamic _error;

  void set error(dynamic error) => error != null ? successful = !((_error = error) != null) : null;

  dynamic get error => _error;

  late final bool guarded;

  // Identifier is the name of the semaphore
  // Callable is the function to be executed
  ExecutionCall({required ExecutionCallType<R> callable}) : _callable = callable;

  ExecutionCall<R> execute() {
    bool _guarded = LatePropertyAssigned<bool>(() => guarded);
    _guarded || (throw Exception('Call to execute() can only be executed internally from the Lock.guard method.'));

    print("executing guarded code");

    try {
      print("trying to execute callable");
      final R returnable = _callable();
      print('Returnable: $returnable');

      returnable is Future
          ? (returned = returnable).then((_returnable) => successful = (completer..complete(_returnable)).isCompleted).catchError((e) => error = e)
          : successful = (completer..complete(returned = returnable)).isCompleted;
    } catch (e) {
      error = e;
      print('Error: $error');
      rethrow;
    }

    return this;
  }
}
