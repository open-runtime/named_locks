import 'package:runtime_native_semaphores/runtime_native_semaphores.dart' show LatePropertyAssigned, SemaphoreIdentities, SemaphoreIdentity;
import 'captured_call_frame.dart' show CapturedCallFrame;

class LockIdentities<I extends LockIdentity> extends SemaphoreIdentities<I> {
  static String prefix = 'runtime_native_locks';

  static final Map<String, dynamic> __identities = {};

  Map<String, dynamic> get _identities => LockIdentities.__identities;
}

class LockIdentity extends SemaphoreIdentity {
  static late final dynamic __instances;

  dynamic get _instances => LockIdentity.__instances;

  late final CapturedCallFrame _frame;

  CapturedCallFrame get frame => _frame;

  late final String _caller = frame.caller;

  String get caller => _caller;

  String get identifier => [name, isolate, process, caller].join('_');

  LockIdentity({required String name}) : super(name: name) {
    _frame = CapturedCallFrame();
  }

  static LockIdentity instantiate<I extends LockIdentity, IS extends LockIdentities<I>>({required String name}) {
    if (!LatePropertyAssigned<IS>(() => __instances)) __instances = LockIdentities<I>();
    return (__instances as IS).has<I>(name: name) ? (__instances as IS).get(name: name) : (__instances as IS).register(name: name, identity: LockIdentity(name: name) as I);
  }

  @override
  String toString() {
    return 'LockIdentity(name: $name, isolate: $isolate, process: $process, caller: $_caller)';
  }
}
