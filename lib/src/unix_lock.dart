import 'dart:io' show Platform;
import 'package:runtime_named_locks/src/lock_counter.dart' show LockCountUpdate, LockCountDeletion, LockCount, LockCounts, LockCounter, LockCounters;
import 'package:runtime_named_locks/src/lock_identity.dart' show LockIdentity, LockIdentities;
import 'package:runtime_named_locks/src/named_lock.dart';
import 'package:runtime_native_semaphores/runtime_native_semaphores.dart' show UnixSemaphore, LatePropertyAssigned;

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
