import 'dart:io' show Platform, sleep;

import "package:runtime_native_semaphores/runtime_native_semaphores.dart" show LatePropertyAssigned, NativeSemaphore, NativeSemaphores, UnixSemaphore, WindowsSemaphore;
import 'execution_call.dart' show ExecutionCall, ExecutionCallErrors;
import 'lock_counter.dart' show LockCount, LockCountDeletion, LockCountUpdate, LockCounter, LockCounters, LockCounts;
import 'lock_identity.dart' show LockIdentities, LockIdentity;

class NamedLocks<
    I extends LockIdentity,
    IS extends LockIdentities<I>,
    CU extends LockCountUpdate,
    CD extends LockCountDeletion,
    CT extends LockCount<CU, CD>,
    CTS extends LockCounts<CU, CD, CT>,
    CTR extends LockCounter<I, CU, CD, CT, CTS>,
    CTRS extends LockCounters<I, CU, CD, CT, CTS, CTR>,
    /* UnixLock and WindowsLock extend NativeSemaphore */
    NL extends NativeSemaphore<I, IS, CU, CD, CT, CTS, CTR, CTRS>
    /* formatting guard comment */
    > extends NativeSemaphores<I, IS, CU, CD, CT, CTS, CTR, CTRS, NL> {
  static final Map<String, dynamic> __instantiations = {};

  final Map<String, dynamic> _instantiations = NamedLocks.__instantiations;
}

class UnixLock<
    I extends LockIdentity,
    IS extends LockIdentities<I>,
    CU extends LockCountUpdate,
    CD extends LockCountDeletion,
    CT extends LockCount<CU, CD>,
    CTS extends LockCounts<CU, CD, CT>,
    CTR extends LockCounter<I, CU, CD, CT, CTS>,
    CTRS extends LockCounters<I, CU, CD, CT, CTS, CTR>> extends UnixSemaphore<I, IS, CU, CD, CT, CTS, CTR, CTRS> {
  @override
  late final String name;

  @override
  late final CTR counter;

  @override
  I get identity => counter.identity;

  static late final dynamic __instances;

  dynamic get _instances => UnixLock.__instances;

  UnixLock({required String super.name, required CTR super.counter, super.verbose = false}) : super() {
    this.name = super.name;
    this.counter = super.counter;
  }

  static UnixLock<I, IS, CU, CD, CT, CTS, CTR, CTRS> instantiate<
      I extends LockIdentity,
      IS extends LockIdentities<I>,
      CU extends LockCountUpdate,
      CD extends LockCountDeletion,
      CT extends LockCount<CU, CD>,
      CTS extends LockCounts<CU, CD, CT>,
      CTR extends LockCounter<I, CU, CD, CT, CTS>,
      CTRS extends LockCounters<I, CU, CD, CT, CTS, CTR>,
      UL extends UnixLock<I, IS, CU, CD, CT, CTS, CTR, CTRS>,
      NLS extends NamedLocks<I, IS, CU, CD, CT, CTS, CTR, CTRS, UL>
      /* formatting guard comment */
      >({required String name, I? identity, CTR? counter, bool verbose = false}) {
    if (!LatePropertyAssigned<NLS>(() => __instances)) {
      __instances = NamedLocks<I, IS, CU, CD, CT, CTS, CTR, CTRS, UL>();

      if (verbose) print('Setting UnixLock._instances: ${__instances}');
    }

    return (__instances as NLS).has<UL>(name: name)
        ? (__instances as NLS).get(name: name)
        : (__instances as NLS).register(
            name: name,
            semaphore: Platform.isMacOS || Platform.isLinux
                ? UnixLock(
                    name: name,
                    counter: counter ??
                        LockCounter.instantiate<I, CU, CD, CT, CTS, CTR, CTRS>(
                          identity: identity ??
                              LockIdentity.instantiate<I, IS>(
                                name: name,
                              ) as I,
                        ) as CTR,
                    verbose: verbose,
                  ) as UL
                : throw Exception('Platform is not Unix.'),
          );
  }
}

class WindowsLock<
    I extends LockIdentity,
    IS extends LockIdentities<I>,
    CU extends LockCountUpdate,
    CD extends LockCountDeletion,
    CT extends LockCount<CU, CD>,
    CTS extends LockCounts<CU, CD, CT>,
    CTR extends LockCounter<I, CU, CD, CT, CTS>,
    CTRS extends LockCounters<I, CU, CD, CT, CTS, CTR>> extends WindowsSemaphore<I, IS, CU, CD, CT, CTS, CTR, CTRS> {
  @override
  late final String name;

  @override
  late final CTR counter;

  static late final dynamic __instances;

  dynamic get _instances => WindowsLock.__instances;

  WindowsLock({required String super.name, required CTR super.counter, super.verbose}) : super() {
    this.name = super.name;
    this.counter = super.counter;
  }

  static WindowsLock<I, IS, CU, CD, CT, CTS, CTR, CTRS> instantiate<
      I extends LockIdentity,
      IS extends LockIdentities<I>,
      CU extends LockCountUpdate,
      CD extends LockCountDeletion,
      CT extends LockCount<CU, CD>,
      CTS extends LockCounts<CU, CD, CT>,
      CTR extends LockCounter<I, CU, CD, CT, CTS>,
      CTRS extends LockCounters<I, CU, CD, CT, CTS, CTR>,
      WL extends WindowsLock<I, IS, CU, CD, CT, CTS, CTR, CTRS>,
      NLS extends NamedLocks<I, IS, CU, CD, CT, CTS, CTR, CTRS, WL>
      /* formatting guard comment */
      >({required String name, I? identity, CTR? counter, bool verbose = false}) {
    if (!LatePropertyAssigned<NLS>(() => __instances)) {
      __instances = NamedLocks<I, IS, CU, CD, CT, CTS, CTR, CTRS, WL>();

      if (verbose) print('Setting WindowsLock._instances: ${__instances}');
    }

    return (__instances as NLS).has<WL>(name: name)
        ? (__instances as NLS).get(name: name)
        : (__instances as NLS).register(
            name: name,
            semaphore: Platform.isWindows
                ? WindowsLock(
                    name: name,
                    counter: counter ??
                        LockCounter.instantiate<I, CU, CD, CT, CTS, CTR, CTRS>(
                          identity: identity ??
                              LockIdentity.instantiate<I, IS>(
                                name: name,
                              ) as I,
                        ) as CTR,
                    verbose: verbose,
                  ) as WL
                : throw Exception('Platform is not Windows.'),
          );
  }
}

typedef LockType<I extends LockIdentity, IS extends LockIdentities<I>, CU extends LockCountUpdate, CD extends LockCountDeletion, CT extends LockCount<CU, CD>,
        CTS extends LockCounts<CU, CD, CT>, CTR extends LockCounter<I, CU, CD, CT, CTS>, CTRS extends LockCounters<I, CU, CD, CT, CTS, CTR>>
    = NativeSemaphore<I, IS, CU, CD, CT, CTS, CTR, CTRS>;

class NamedLock {
  // Guard will create a new lock fo you with the given lock name
  // Guard and execute some code with the lock held and released it the internal execution completes
  static ExecutionCall<R, E> guard<R, E extends Exception>(
      {required String name, required ExecutionCall<R, E> execution, Duration timeout = const Duration(seconds: 5), bool safe = false, bool verbose = false}) {
    execution.guarded = true;

    LockType lock = Platform.isWindows ? WindowsLock.instantiate(name: name) : UnixLock.instantiate(name: name);
    !lock.opened && lock.open() || lock.opened || (throw Exception('Failed to open semaphore before guarded code execution.'));

    DateTime now = DateTime.now();
    Duration _sleep = Duration(milliseconds: 2);

    int _attempt = 1;

    bool locked = false;

    while (!locked) {
      // TODO implement a backoff strategy
      // Exit if the timeout has been exceeded already or if the sleep time is greater than 40% of the timeout
      // TODO subtract sleep from timeout now.subtract(_sleep)
      if (DateTime.now().difference(now) > timeout) {
        // TODO try to clean up the lock here
        // TODO pass in a force option to close & unlink
        // TODO lock..close(force: true)..unlink(force: true);

        // execution.error = Exception('Failed to acquire lock within $timeout.');
        // This will throw because error sets successful to false
        // (execution.completer.isCompleted && execution.successful) || (throw Exception('Failed to execute execution code: ${execution.error}'));
        // TODO Poll the future here if we find one?
        throw Exception('NamedLock.guard has failed to acquire lock within $timeout.');
      }

      if (verbose) print('NamedLock is not locked: $locked within the NamedLock.guard execution loop and about to try to lock the lock.');
      locked = lock.lock();

      if (locked) {
        if (verbose) print('NamedLock is locked: $locked within the NamedLock.guard execution loop and about to execute ExecutionCall.callable()');
        execution.execute();

        if (verbose) print('NamedLock is locked: $locked within the NamedLock.guard execution loop and has executed ExecutionCall.callable()');

        if (verbose) print('NamedLock is locked: $locked within the NamedLock.guard execution loop and about to unlock the lock.');
        lock.unlock();

        if (verbose) print('NamedLock is unlocked: ${!locked} within the NamedLock.guard execution loop and about to close.');
        lock.close();

        if (verbose) print('NamedLock is closed: ${!lock.opened} within the NamedLock.guard execution loop and about to unlink the named lock.');
        lock.unlink();

        if (verbose) print('NamedLock is unlocked, closed, and unlinked within the NamedLock.guard execution loop and about to return the execution.');
      } else {
        if (verbose)
          print(
              'NamedLock is not locked: $locked within the NamedLock.guard execution loop and about to sleep for ${_sleep.inMilliseconds} milliseconds due to the lock not being acquired.');
        sleep(_sleep);
        _sleep = Duration(milliseconds: (_sleep.inMilliseconds + _attempt * 10).clamp(5, 500));
        if (verbose)
          print(
              'NamedLock is not locked: $locked within the NamedLock.guard execution loop and has slept for ${_sleep.inMilliseconds} milliseconds due to the lock not being acquired.');
        _attempt++;
        if (verbose)
          print(
              'NamedLock is not locked: $locked within the NamedLock.guard execution loop and about to try to lock the lock again. It is on attempt $_attempt and will sleep for ${_sleep.inMilliseconds} milliseconds if lock is not acquired this time.');
      }

      // If we are safe or there is no error, return the execution otherwise throw the error
      // This will only work if it was synchronous
      if (!safe && execution.completer.isCompleted && !execution.successful && execution.error is ExecutionCallErrors<E>)
        throw Error.throwWithStackTrace(execution.error.anticipated!, execution.error.trace!);
    }

    return execution;
  }
}
