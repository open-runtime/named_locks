import 'package:runtime_named_locks/src/lock_identity.dart';
import 'package:runtime_native_semaphores/runtime_native_semaphores.dart';

class LockCountUpdate extends SemaphoreCountUpdate {
  LockCountUpdate({required String identifier, int? from = null, required int to}) : super(identifier: identifier, from: from, to: to);
}

class LockCountDeletion extends SemaphoreCountDeletion {
  LockCountDeletion({required String identifier, int? at = null}) : super(identifier: identifier, at: at);
}

class LockCount<CU extends LockCountUpdate, CD extends LockCountDeletion> extends SemaphoreCount<CU, CD> {
  static final Map<String, int?> __counts = {};

  @override
  Map<String, int?> get counts => LockCount.__counts;

  LockCount({required String identifier, required String forProperty}) : super(identifier: identifier, forProperty: forProperty);

  @override
  CU update({required int value}) {
    CU _update = LockCountUpdate(identifier: identifier, from: counts.putIfAbsent(identifier, () => null) ?? counts[identifier], to: counts[identifier] = value) as CU;

    if (verbose)
      _update.from == null ? print("Lock count for $identifier initialized to ${_update.to}.") : print("Lock count for $identifier updated from ${_update.from} to ${_update.to}.");

    return _update;
  }

  CD delete() {
    CD _deletion = LockCountDeletion(identifier: identifier, at: counts.remove(identifier)) as CD;

    if (verbose) _deletion.at == null ? print("Lock count for $identifier does not exist.") : print("Lock count for $identifier deleted with final count at ${_deletion.at}.");

    return _deletion;
  }
}

class LockCounts<CU extends LockCountUpdate, CD extends LockCountDeletion, CT extends LockCount<CU, CD>> extends SemaphoreCounts<CU, CD, CT> {
  LockCounts({required CT isolate, required CT process}) : super(isolate: isolate, process: process);
}

class LockCounters<I extends LockIdentity, CU extends LockCountUpdate, CD extends LockCountDeletion, CT extends LockCount<CU, CD>, CTS extends LockCounts<CU, CD, CT>,
    CTR extends LockCounter<I, CU, CD, CT, CTS>> extends SemaphoreCounters<I, CU, CD, CT, CTS, CTR> {
  static final Map<String, dynamic> __counters = {};

  final Map<String, dynamic> _counters = LockCounters.__counters;
}

// Enum to represent types of operations i.e. LOCK, UNLOCK, CREATE, DISPOSE
class LockCounter<I extends LockIdentity, CU extends LockCountUpdate, CD extends LockCountDeletion, CT extends LockCount<CU, CD>, CTS extends LockCounts<CU, CD, CT>>
    extends SemaphoreCounter<I, CU, CD, CT, CTS> {
  static late final dynamic __instances;

  dynamic get _instances => LockCounter.__instances;

  LockCounter({required String identifier, required I identity, required CTS counts}) : super(identifier: identifier, identity: identity, counts: counts);

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
            counter: LockCounter<I, CU, CD, CT, CTS>(
              identity: identity,
              counts: (LockCounts<CU, CD, CT>(
                // Super important to pass the forProperty as the name of the property that the counter is set on
                isolate: LockCount(identifier: identity.name, forProperty: 'isolate') as CT,
                process: LockCount(identifier: identity.name, forProperty: 'process') as CT,
              ) as CTS),
              identifier: identity.name,
            ) as CTR,
          );
  }
}
