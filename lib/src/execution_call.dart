import 'dart:async' show Completer, Future, FutureOr;
import 'package:runtime_native_semaphores/runtime_native_semaphores.dart' show LatePropertyAssigned;

typedef ExecutionCallType<R, E extends Exception> = R Function();

class ExecutionCallErrors<R, E extends Exception> {
  late final E? _anticipated;

  late Completer<R> completer;

  ({bool set, E? value}) get anticipated => LatePropertyAssigned<E>(() => _anticipated) ? (set: true, value: _anticipated) : (set: false, value: null);

  late final Object? _unknown;

  ({bool set, Object? value}) get unknown => LatePropertyAssigned<Object>(() => _unknown) ? (set: true, value: _unknown) : (set: false, value: null);

  late final StackTrace? _trace;

  ({bool set, StackTrace? value}) get trace => LatePropertyAssigned<StackTrace?>(() => _trace) ? (set: true, value: _trace) : (set: false, value: null);

  bool get caught => anticipated.set || unknown.set;

  ExecutionCallErrors({E? anticipated = null, Object? unknown = null, StackTrace? trace = null, required Completer<R> this.completer})
      : _anticipated = anticipated,
        _unknown = unknown,
        _trace = trace;

  @override
  toString() => 'ExecutionCallErrors(anticipated: $anticipated, Unknown: $unknown, Trace: $trace)';

  FutureOr<E> rethrow_() {
    if (completer.isCompleted)
      !caught || trace.set ? (throw Error.throwWithStackTrace((anticipated.value ?? unknown.value)!, trace.value!)) : (throw (anticipated.value ?? unknown.value)!);
    else
      return completer.future
          .then((_) => trace.set ? (throw Error.throwWithStackTrace((anticipated.value ?? unknown.value)!, trace.value!)) : (throw (anticipated.value ?? unknown.value)!));
  }
}

class ExecutionCall<R, E extends Exception> {
  final ExecutionCallType<R, E> _callable;

  final completer = Completer<R>();

  late final R _returned;

  bool safe;

  R get returned =>
      LatePropertyAssigned(() => _returned) ? _returned : (throw Exception('[returned] value is not available. To ensure property availabilities [await completer.future]. '));

  late final ExecutionCallErrors<R, E> _error;

  ExecutionCallErrors<R, E>? get error => LatePropertyAssigned(() => _error) ? _error : null;

  // Keeping this nullable for polling purposes
  late final bool _successful;

  bool get successful => LatePropertyAssigned(() => _successful)
      ? _successful
      : (throw Exception('[successful] value is not available yet. To ensure property availabilities [await completer.future].'));

  late final bool guarded;

  bool verbose;

  // TODO put lock on here?

  // Identifier is the name of the semaphore
  // Callable is the function to be executed
  // Todo pass along lock instance?
  ExecutionCall({required ExecutionCallType<R, E> callable, bool this.safe = false, this.verbose = false}) : _callable = callable;

  ExecutionCall<R, E> execute() {
    if (verbose) print('Calling Guarded ExecutionCall.execute()');
    bool _guarded = LatePropertyAssigned<bool>(() => guarded);
    _guarded || (throw Exception('Call to execute() can only be executed internally from the Lock.guard method.'));

    // Catch itself here if we didnt catch it on the returnable itself the LatePropertyAssigned Late will tell us if the returnable caught it already or not
    completer.future.catchError((e, trace) => LatePropertyAssigned<ExecutionCallErrors<R, E>>(() => _error)
        ? e
        : _error = ExecutionCallErrors<R, E>(anticipated: e is E ? e : null, unknown: e is! E && e is Object ? e : null, trace: trace, completer: completer));

    try {
      if (verbose) print('Attempting Guarded ExecutionCall.callable()');

      final R returnable = _callable();

      if (verbose) print('Guarded ExecutionCall Returnable: $returnable');

      returnable is Future
          ? returnable
              .then((_returnable) => completer..complete(_returned = _returnable))
              // catch the error on returnable
              .catchError((e, trace) => (this
                    .._error = ExecutionCallErrors<R, E>(anticipated: e is E ? e : null, unknown: e is! E && e is Object ? e : null, trace: trace, completer: completer))
                  .completer)
              // when complete successful is true if _error is not set and completer is completed or the completer is completed with an error and successful is set to the opposite of isCompleted which is false
              .whenComplete(() => _successful = completer.isCompleted && !LatePropertyAssigned<ExecutionCallErrors<R, E>>(() => _error) ||
                  !(completer..completeError((_error.anticipated.value ?? _error.unknown.value)!, _error.trace.value)).isCompleted)
          : _successful = (completer..complete(_returned = returnable)).isCompleted;

      if (verbose && returnable is Future)
        print('Guarded ExecutionCall has returned an asynchronous result and will complete when property completer.future is resolved.');
      else if (verbose) print('Guarded ExecutionCall returned a synchronous result and was successful: $_successful');
    } on E catch (e, trace) {
      if (verbose) print('Caught anticipated exception: $e');
      // Set successful to false i.e. just use inverse of isCompleted
      _successful = !(completer
            ..completeError((
              ((_error = ExecutionCallErrors<R, E>(/* setting anticipated here */ anticipated: e, trace: trace, completer: completer)).anticipated.value ?? _error.unknown.value)!,
              _error.trace.value
            )))
          .isCompleted;
      // completer.completeError(error.anticipated ?? error.unknown, error.trace);
    } catch (e, trace) {
      if (verbose) print('Guarded ExecutionCall failed with unknown error: $e');
      // Set successful to false i.e. just use inverse of isCompleted
      _successful = !(completer
            ..completeError((
              ((_error = ExecutionCallErrors<R, E>(/*setting unknown here */ unknown: e, trace: trace, completer: completer)).anticipated.value ?? _error.unknown.value)!,
              _error.trace.value
            )))
          .isCompleted;
    }

    if (verbose && !successful && completer.isCompleted) print('Finished: Guarded execution call failed with errors: $error');
    if (verbose) print('Finished: _successful: $_successful');
    if (verbose) print('Finished: completer.isCompleted: ${completer.isCompleted}');

    return this;
  }
}
