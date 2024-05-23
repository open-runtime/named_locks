import 'dart:io' show Platform, sleep;

import 'package:runtime_named_locks/src/unix_lock.dart';
import 'package:runtime_named_locks/src/windows_lock.dart';
import "package:runtime_native_semaphores/runtime_native_semaphores.dart"
    show NativeSemaphore, NativeSemaphores;

import 'execution_call.dart' show ExecutionCall;
import 'lock_counter.dart'
    show
        LockCount,
        LockCountDeletion,
        LockCountUpdate,
        LockCounter,
        LockCounters,
        LockCounts;
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

typedef LockType<
        I extends LockIdentity,
        IS extends LockIdentities<I>,
        CU extends LockCountUpdate,
        CD extends LockCountDeletion,
        CT extends LockCount<CU, CD>,
        CTS extends LockCounts<CU, CD, CT>,
        CTR extends LockCounter<I, CU, CD, CT, CTS>,
        CTRS extends LockCounters<I, CU, CD, CT, CTS, CTR>>
    = NativeSemaphore<I, IS, CU, CD, CT, CTS, CTR, CTRS>;

class NamedLock {
  // Guard will create a new lock fo you with the given lock name
  // Guard and execute some code with the lock held and released it the internal execution completes
  static ExecutionCall<R, E> guard<R, E extends Exception>(
      {required String name,
      required ExecutionCall<R, E> execution,
      Duration timeout = const Duration(seconds: 5),
      bool verbose = false,
      String? waiting}) {
    execution.guarding = true;

    LockType lock = Platform.isWindows
        ? WindowsLock.instantiate(name: name)
        : UnixLock.instantiate(name: name);
    !lock.opened && lock.open() ||
        lock.opened ||
        (throw Exception(
            'Failed to open semaphore before guarded code execution.'));

    DateTime now = DateTime.now();
    Duration _sleep = Duration(milliseconds: 2);

    int _attempt = 1;

    bool locked = false;

    while (!locked) {
      locked = lock.lock();

      if (locked) {
        _execute(verbose, locked, execution, lock);
      } else {
        _wait(verbose, locked, _sleep, _attempt, waiting, now, timeout);
        locked = lock.lock();
      }

      // If we are safe or there is no error, return the execution otherwise throw the error
      // This will only work if it was synchronous
      if (!execution.safe && execution.error.isSet)
        execution.error.get?.rethrow_();
    }

    return execution;
  }

  /// Wait a little while for the process holding the lock
  /// to release it.
  static void _wait(bool verbose, bool locked, Duration _sleep, int _attempt,
      String? waiting, DateTime now, Duration timeout) {
    if (verbose)
      print(
          'NamedLock is not locked: $locked within the NamedLock.guard execution loop and about to sleep for ${_sleep.inMilliseconds} milliseconds due to the lock not being acquired.');
    sleep(_sleep);

    // On first attempt if we are not locked we can print the waiting message
    if (_attempt == 1 && waiting is String) {
      print(waiting);
      waiting = null;
    }

    _sleep = Duration(
        milliseconds: (_sleep.inMilliseconds + _attempt * 10).clamp(5, 500));
    if (verbose)
      print(
          'NamedLock is not locked: $locked within the NamedLock.guard execution loop and has slept for ${_sleep.inMilliseconds} milliseconds due to the lock not being acquired.');
    _attempt++;
    if (verbose)
      print(
          'NamedLock is not locked: $locked within the NamedLock.guard execution loop and about to try to lock the lock again. It is on attempt $_attempt and will sleep for ${_sleep.inMilliseconds} milliseconds if lock is not acquired this time.');

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
      throw Exception(
          'NamedLock.guard has failed to acquire lock within $timeout.');
    }
  }

  static void _execute(
      bool verbose,
      bool locked,
      ExecutionCall<dynamic, dynamic> execution,
      LockType<
              LockIdentity,
              LockIdentities<LockIdentity>,
              LockCountUpdate,
              LockCountDeletion,
              LockCount<LockCountUpdate, LockCountDeletion>,
              LockCounts<LockCountUpdate, LockCountDeletion,
                  LockCount<LockCountUpdate, LockCountDeletion>>,
              LockCounter<
                  LockIdentity,
                  LockCountUpdate,
                  LockCountDeletion,
                  LockCount<LockCountUpdate, LockCountDeletion>,
                  LockCounts<LockCountUpdate, LockCountDeletion,
                      LockCount<LockCountUpdate, LockCountDeletion>>>,
              LockCounters<
                  LockIdentity,
                  LockCountUpdate,
                  LockCountDeletion,
                  LockCount<LockCountUpdate, LockCountDeletion>,
                  LockCounts<LockCountUpdate, LockCountDeletion,
                      LockCount<LockCountUpdate, LockCountDeletion>>,
                  LockCounter<
                      LockIdentity,
                      LockCountUpdate,
                      LockCountDeletion,
                      LockCount<LockCountUpdate, LockCountDeletion>,
                      LockCounts<LockCountUpdate, LockCountDeletion,
                          LockCount<LockCountUpdate, LockCountDeletion>>>>>
          lock) {
    if (verbose)
      print(
          'NamedLock is locked: $locked within the NamedLock.guard execution loop and about to execute ExecutionCall.callable()');
    execution.execute();

    if (verbose)
      print(
          'NamedLock is locked: $locked within the NamedLock.guard execution loop and has executed ExecutionCall.callable()');

    if (verbose)
      print(
          'NamedLock is locked: $locked within the NamedLock.guard execution loop and about to unlock the lock.');
    lock.unlock();

    if (verbose)
      print(
          'NamedLock is unlocked: ${!locked} within the NamedLock.guard execution loop and about to close.');
    lock.close();

    if (verbose)
      print(
          'NamedLock is closed: ${!lock.opened} within the NamedLock.guard execution loop and about to unlink the named lock.');
    lock.unlink();

    if (verbose)
      print(
          'NamedLock is unlocked, closed, and unlinked within the NamedLock.guard execution loop and about to return the execution.');
  }
}
