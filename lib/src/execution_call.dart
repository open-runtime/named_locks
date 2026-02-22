import 'dart:async' show Completer, Future, unawaited;

typedef ExecutionCallType<R, E extends Exception> = R Function();

class ExecutionCallErrors<R, E extends Exception> {
  final E? _anticipated;
  final Object? _unknown;
  final StackTrace? _trace;
  final bool _anticipatedIsSet;
  final bool _unknownIsSet;
  final bool _traceIsSet;
  final Completer<R> completer;

  ({bool isSet, E? get}) get anticipated => (isSet: _anticipatedIsSet, get: _anticipated);

  ({bool isSet, Object? get}) get unknown => (isSet: _unknownIsSet, get: _unknown);

  ({bool isSet, StackTrace? get}) get trace => (isSet: _traceIsSet, get: _trace);

  bool get caught => anticipated.isSet || unknown.isSet;

  ExecutionCallErrors({
    required this.completer,
    E? anticipated,
    Object? unknown,
    StackTrace? trace,
    bool anticipatedIsSet = false,
    bool unknownIsSet = false,
    bool traceIsSet = false,
  }) : _anticipated = anticipated,
       _unknown = unknown,
       _trace = trace,
       _anticipatedIsSet = anticipatedIsSet || anticipated != null,
       _unknownIsSet = unknownIsSet || unknown != null,
       _traceIsSet = traceIsSet || trace != null;

  @override
  String toString() => 'ExecutionCallErrors(anticipated: $anticipated, unknown: $unknown, trace: $trace)';

  Never rethrow_() {
    if (!caught) {
      throw StateError('Cannot rethrow because no error was captured.');
    }

    return _throwStoredError();
  }

  Never _throwStoredError() {
    final Object error = (anticipated.get ?? unknown.get)!;
    final StackTrace? stackTrace = trace.get;

    if (stackTrace != null) {
      Error.throwWithStackTrace(error, stackTrace);
    }

    if (error is Error) {
      throw error;
    }
    if (error is Exception) {
      throw error;
    }

    throw StateError(error.toString());
  }
}

class ExecutionCall<R, E extends Exception> {
  final ExecutionCallType<R, E> _callable;
  final Completer<R> completer = Completer<R>();
  R? _returned;
  bool _returnedIsSet = false;
  bool safe;
  ExecutionCallErrors<R, E>? _error;
  bool _errorIsSet = false;
  bool? _successful;
  bool _successfulIsSet = false;
  bool _guarding = false;
  bool _guardingIsSet = false;
  bool _completerErrorObserverAttached = false;
  bool verbose;

  ExecutionCall({required ExecutionCallType<R, E> callable, this.safe = false, this.verbose = false})
    : _callable = callable;

  R get returned {
    if (!_returnedIsSet) {
      throw StateError('[returned] value is not available. Await `completer.future` first.');
    }

    return _returned as R;
  }

  ({bool isSet, ExecutionCallErrors<R, E>? get}) get error => (isSet: _errorIsSet, get: _error);

  ({bool isSet, bool? get}) get successful => (isSet: _successfulIsSet, get: _successful);

  ({bool isSet, bool? get}) get guarded => (isSet: _guardingIsSet, get: _guarding);

  bool get guarding => _guarding;

  set guarding(bool value) {
    if (value && !_guardingIsSet) {
      _guarding = true;
      _guardingIsSet = true;
    }
  }

  void execute() {
    if (verbose) {
      print('Calling guarded ExecutionCall.execute()');
    }

    if (!_completerErrorObserverAttached) {
      _completerErrorObserverAttached = true;
      unawaited(
        completer.future.then<void>(
          (_) {},
          onError: (Object e, StackTrace trace) {
            if (!_errorIsSet) {
              _recordError(e, trace);
            }
          },
        ),
      );
    }

    if (!guarding) {
      throw StateError('Call to execute() can only be made internally from NamedLock.guard.');
    }

    try {
      if (verbose) {
        print('Attempting guarded ExecutionCall.callable()');
      }

      final R result = _callable();
      _returned = result;
      _returnedIsSet = true;

      if (!completer.isCompleted) {
        completer.complete(result);
      }

      _markSuccessful(true);

      if (result is Future<dynamic>) {
        unawaited(
          result.then<void>(
            (_) {},
            onError: (Object e, StackTrace trace) {
              _recordError(e, trace);
              _markSuccessful(false);
            },
          ),
        );
      }

      if (verbose) {
        print('Guarded ExecutionCall returned: $returned');
      }
    } on E catch (e, trace) {
      if (verbose) {
        print('Caught anticipated exception: $e');
      }

      _recordError(e, trace);
      _completeWithErrorIfPending(e, trace);
      _markSuccessful(false);
    } on Object catch (e, trace) {
      final unknownError = e;

      if (verbose) {
        print('Guarded ExecutionCall failed with unknown error: $unknownError');
      }

      _recordError(unknownError, trace);
      _completeWithErrorIfPending(unknownError, trace);
      _markSuccessful(false);
    }

    if (verbose && error.isSet) {
      print('Finished: guarded execution call failed with errors: $error');
    }
    if (verbose) {
      print('Finished: successful: $successful');
      print('Finished: completer.isCompleted: ${completer.isCompleted}');
    }
  }

  void _completeWithErrorIfPending(Object error, StackTrace trace) {
    if (!completer.isCompleted) {
      completer.completeError(error, trace);
    }
  }

  void _recordError(Object error, StackTrace trace) {
    _error = ExecutionCallErrors<R, E>(
      completer: completer,
      anticipated: error is E ? error : null,
      unknown: error is E ? null : error,
      trace: trace,
    );
    _errorIsSet = true;
  }

  void _markSuccessful(bool value) {
    _successful = value;
    _successfulIsSet = true;
  }
}
