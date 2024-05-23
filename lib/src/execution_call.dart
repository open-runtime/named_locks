import 'dart:async' show Completer, Future, FutureOr;
import 'package:runtime_native_semaphores/runtime_native_semaphores.dart' show LatePropertyAssigned;

typedef ExecutionCallType<R, E extends Exception> = R Function();

class ExecutionCallErrors<R, E extends Exception> {
  late final E? _anticipated;

  late Completer<R> completer;

  ({bool isSet, E? get}) get anticipated => LatePropertyAssigned<E>(() => _anticipated) ? (isSet: true, get: _anticipated) : (isSet: false, get: null);

  late final Object? _unknown;

  ({bool isSet, Object? get}) get unknown => LatePropertyAssigned<Object>(() => _unknown) ? (isSet: true, get: _unknown) : (isSet: false, get: null);

  late final StackTrace? _trace;

  ({bool isSet, StackTrace? get}) get trace => LatePropertyAssigned<StackTrace?>(() => _trace) ? (isSet: true, get: _trace) : (isSet: false, get: null);

  bool get caught => anticipated.isSet || unknown.isSet;

  ExecutionCallErrors({E? anticipated = null, Object? unknown = null, StackTrace? trace = null, required Completer<R> this.completer})
      : _anticipated = anticipated,
        _unknown = unknown,
        _trace = trace;

  @override
  String toString() => 'ExecutionCallErrors(anticipated: $anticipated, Unknown: $unknown, Trace: $trace)';

  FutureOr<E> rethrow_() {
    if (completer.isCompleted)
      !caught || trace.isSet ? (throw Error.throwWithStackTrace((anticipated.get ?? unknown.get)!, trace.get!)) : (throw (anticipated.get ?? unknown.get)!);
    else
      return completer.future
          .then((_) => trace.isSet ? (throw Error.throwWithStackTrace((anticipated.get ?? unknown.get)!, trace.get!)) : (throw (anticipated.get ?? unknown.get)!));
  }
}

class ExecutionCall<R, E extends Exception> {
  final ExecutionCallType<R, E> _callable;

  final completer = Completer<R>();

  late final R _returned;

  bool safe;

  R get returned =>
      LatePropertyAssigned<R>(() => _returned) ? _returned : (throw Exception('[returned] value is not available. To ensure property availabilities [await completer.future]. '));

  late final ExecutionCallErrors<R, E> _error;

  ({bool isSet, ExecutionCallErrors<R, E>? get}) get error => LatePropertyAssigned(() => _error) ? (isSet: true, get: _error) : (isSet: false, get: null);

  late final bool _successful;

  ({bool isSet, bool? get}) get successful => LatePropertyAssigned<bool>(() => _successful) ? (isSet: true, get: _successful) : (isSet: false, get: null);

  late final bool _guarded;

  ({bool isSet, bool? get}) get guarded => LatePropertyAssigned<bool>(() => _guarded) ? (isSet: true, get: _guarded) : (isSet: false, get: null);

  set guarding(bool value) => value && LatePropertyAssigned<bool>(() => _guarded) ? _guarded = value : null;

  bool verbose;

  // TODO put lock on here?
  // Todo pass along lock instance?
  ExecutionCall({required ExecutionCallType<R, E> callable, bool this.safe = false, this.verbose = false}) : _callable = callable;

  ExecutionCall<R, E> execute() {
    if (verbose) print('Calling Guarded ExecutionCall.execute()');

    !guarded.isSet && (guarding = true) || (throw Exception('Call to execute() can only be executed internally from the Lock.guard method.'));

    // Catch itself here if we didnt catch it on the returnable itself the LatePropertyAssigned Late will tell us if the returnable caught it already or not
    completer.future.catchError((e, StackTrace trace) => LatePropertyAssigned<ExecutionCallErrors<R, E>>(() => _error)
        ? e
        : _error = ExecutionCallErrors<R, E>(anticipated: e is E ? e : null, unknown: e is! E && e is Object ? e : null, trace: trace, completer: completer));

    try {
      if (verbose) print('Attempting Guarded ExecutionCall.callable()');

      _returned = _callable();

      if (verbose) print('Guarded ExecutionCall Returned: $returned');

      _returned is Future<R>
          ? _returned
              .then(completer.complete)
              // catch the error on returnable
              .catchError((e, StackTrace trace) => (this
                    .._error = ExecutionCallErrors<R, E>(anticipated: e is E ? e : null, unknown: e is! E && e is Object ? e : null, trace: trace, completer: completer))
                  .completer)
              // when complete successful is true if _error is not set and completer is completed or the completer is completed with an error and successful is set to the opposite of isCompleted which is false
              .whenComplete(() => _successful = completer.isCompleted && !LatePropertyAssigned<ExecutionCallErrors<R, E>>(() => _error) ||
                  !(completer..completeError((_error.anticipated.get ?? _error.unknown.get)!, _error.trace.get)).isCompleted)
          : _successful = (completer..complete(_returned)).isCompleted;

      if (verbose && _returned is Future<R>)
        print('Guarded ExecutionCall has returned an asynchronous result and will complete when property completer.future is resolved.');
      else if (verbose) print('Guarded ExecutionCall returned a synchronous result and was successful: $_successful with return value: $returned');
    } on E catch (e, trace) {
      if (verbose) print('Caught anticipated exception: $e');
      // Set successful to false i.e. just use inverse of isCompleted
      _successful = !(completer
            ..completeError((
              ((_error = ExecutionCallErrors<R, E>(/* setting anticipated here */ anticipated: e, trace: trace, completer: completer)).anticipated.get ?? _error.unknown.get)!,
              _error.trace.get
            )))
          .isCompleted;
      // completer.completeError(error.anticipated ?? error.unknown, error.trace);
    } catch (e, trace) {
      if (verbose) print('Guarded ExecutionCall failed with unknown error: $e');
      // Set successful to false i.e. just use inverse of isCompleted
      _successful = !(completer
            ..completeError((
              ((_error = ExecutionCallErrors<R, E>(/*setting unknown here */ unknown: e, trace: trace, completer: completer)).anticipated.get ?? _error.unknown.get)!,
              _error.trace.get
            )))
          .isCompleted;
    }

    if (verbose && error.isSet) print('Finished: Guarded execution call failed with errors: $error');
    if (verbose) print('Finished: _successful: $_successful, successful: ${successful}');
    if (verbose) print('Finished: completer.isCompleted: ${completer.isCompleted}');

    return this;
  }
}
