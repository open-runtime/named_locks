// Generic names in this file intentionally mirror the semaphore abstractions.
// ignore_for_file: avoid_types_as_parameter_names

import 'package:runtime_native_semaphores/runtime_native_semaphores.dart';

import 'lock_identity.dart';

class LockCountUpdate extends SemaphoreCountUpdate {
  LockCountUpdate({required super.identifier, required super.to, super.from});
}

class LockCountDeletion extends SemaphoreCountDeletion {
  LockCountDeletion({required super.identifier, super.at});
}

class LockCount<CU extends LockCountUpdate, CD extends LockCountDeletion> extends SemaphoreCount<CU, CD> {
  static final Map<String, int?> __counts = {};

  @override
  Map<String, int?> get counts => LockCount.__counts;

  LockCount({required super.identifier, required super.forProperty});

  @override
  CU update({required int value}) {
    final update =
        LockCountUpdate(
              identifier: identifier,
              from: counts.putIfAbsent(identifier, () => null) ?? counts[identifier],
              to: counts[identifier] = value,
            )
            as CU;

    if (verbose)
      update.from == null
          ? print('Lock count for $identifier initialized to ${update.to}.')
          : print('Lock count for $identifier updated from ${update.from} to ${update.to}.');

    return update;
  }

  @override
  CD delete() {
    final deletion = LockCountDeletion(identifier: identifier, at: counts.remove(identifier)) as CD;

    if (verbose)
      deletion.at == null
          ? print('Lock count for $identifier does not exist.')
          : print('Lock count for $identifier deleted with final count at ${deletion.at}.');

    return deletion;
  }
}

class LockCounts<CU extends LockCountUpdate, CD extends LockCountDeletion, CT extends LockCount<CU, CD>>
    extends SemaphoreCounts<CU, CD, CT> {
  LockCounts({required super.isolate, required super.process});
}

class LockCounters<
  I extends LockIdentity,
  CU extends LockCountUpdate,
  CD extends LockCountDeletion,
  CT extends LockCount<CU, CD>,
  CTS extends LockCounts<CU, CD, CT>,
  CTR extends LockCounter<I, CU, CD, CT, CTS>
>
    extends SemaphoreCounters<I, CU, CD, CT, CTS, CTR> {
  static final Map<String, dynamic> __counters = {};

  // Instance registry for debugging and introspection.
  // ignore: unused_field
  final Map<String, dynamic> _counters = LockCounters.__counters;
}

// Enum to represent types of operations i.e. LOCK, UNLOCK, CREATE, DISPOSE
class LockCounter<
  I extends LockIdentity,
  CU extends LockCountUpdate,
  CD extends LockCountDeletion,
  CT extends LockCount<CU, CD>,
  CTS extends LockCounts<CU, CD, CT>
>
    extends SemaphoreCounter<I, CU, CD, CT, CTS> {
  static late final dynamic __instances;

  // Instance registry for debugging and introspection.
  // ignore: unused_element
  dynamic get _instances => LockCounter.__instances;

  LockCounter({required super.identifier, required super.identity, required super.counts});

  static LockCounter<I, CU, CD, CT, CTS> instantiate<
    /*  Identity */
    I extends LockIdentity,
    CU extends LockCountUpdate,
    CD extends LockCountDeletion,
    CT extends LockCount<CU, CD>,
    /* Semaphore Counts */
    CTS extends LockCounts<CU, CD, CT>,
    /* Semaphore Counter i.e. this class */
    CTR extends LockCounter<I, CU, CD, CT, CTS>,
    /* Semaphore Counters */
    CTRS extends LockCounters<I, CU, CD, CT, CTS, CTR>
    /* formatting guard comment */
  >({required I identity}) {
    if (!LatePropertyAssigned<CTRS>(() => __instances)) __instances = LockCounters<I, CU, CD, CT, CTS, CTR>();

    return (__instances as CTRS).has<CTR>(identifier: identity.name)
        ? (__instances as CTRS).get(identifier: identity.name)
        : (__instances as CTRS).register(
            identifier: identity.name,
            counter:
                LockCounter<I, CU, CD, CT, CTS>(
                      identity: identity,
                      counts:
                          (LockCounts<CU, CD, CT>(
                                // Super important to pass the forProperty as the name of the property that the counter is set on
                                isolate: LockCount(identifier: identity.name, forProperty: 'isolate') as CT,
                                process: LockCount(identifier: identity.name, forProperty: 'process') as CT,
                              )
                              as CTS),
                      identifier: identity.name,
                    )
                    as CTR,
          );
  }
}
