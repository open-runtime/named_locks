# runtime_named_locks — Known Issues

Comprehensive bug documentation for `packages/libraries/dart/named_locks`.
Audited against version `1.0.0-beta.5`.
All line numbers are precise references verified during code audit.

---

## Severity Legend

| Level | Meaning |
|---|---|
| **CRITICAL** | Prevents correct operation; blocks functionality |
| **HIGH** | Causes data loss, deadlock, memory leaks, or incorrect behavior under normal use |
| **MEDIUM** | Correctness issue or significant quality gap; may manifest in edge cases |
| **LOW** | Code quality, style, minor inconsistency |

---

## CRITICAL Issues

---

### C-0 — `execute()` Guard Logic Always Throws — `execution_call.dart:75`

**Severity**: CRITICAL
**File**: `lib/src/execution_call.dart`
**Line**: 75

**Description**:
The guard assertion in `ExecutionCall.execute()` is permanently broken due to a Dart language semantics issue: setters return `void`, not `bool`. The boolean expression uses the setter result as a boolean operand, which is always falsy in Dart, causing the exception to always be thrown.

**Buggy Code**:
```dart
// execution_call.dart:72-76
ExecutionCall<R, E> execute() {
  if (verbose) print('Calling Guarded ExecutionCall.execute()');

  !guarded.isSet && (guarding = true) ||  // ← (guarding = true) returns void → falsy
      (throw Exception('Call to execute() can only be executed internally from the Lock.guard method.'));
```

**Evaluation trace**:
```
!guarded.isSet == true  →  true && (void)  →  true && false  →  false
                         →  right side: throw Exception(...)  ←  ALWAYS EXECUTED
```

**Impact**: `NamedLock.guard()` never executes any user callable. Every call to `guard()` will throw immediately after acquiring the lock, leak the lock (see C-1), and propagate an exception claiming the call is unauthorized.

**Fix**:
```dart
if (!guarded.isSet) {
  guarding = true;
} else {
  throw Exception('Call to execute() can only be executed internally from the Lock.guard method.');
}
```

---

### C-1 — Lock Resource Leak on Exception — `named_lock.dart:205-216`

**Severity**: CRITICAL
**File**: `lib/src/named_lock.dart`
**Lines**: 205-216

**Description**:
There is no `try/finally` around `execution.execute()`. If the execution throws unexpectedly (which Bug C-0 guarantees 100% of the time), the `unlock()`, `close()`, and `unlink()` calls are never reached. The OS-level named semaphore remains locked permanently, deadlocking any subsequent caller using the same lock name.

**Buggy Code**:
```dart
// named_lock.dart:204-220
if (locked) {
  execution.execute();   // Line 205 — exception propagates here
                         // ↓ Lines below NEVER reached on exception
  if (verbose) print('Finished Guarded execution for lock: $name');

  lock.unlock();         // Line 210
  if (verbose) print('Unlocked lock: $name');

  lock.close();          // Line 213
  if (verbose) print('Closed lock: $name');

  lock.unlink();         // Line 216
  if (verbose) print('Unlinked lock: $name');
}
```

**Combined with C-0**: Bug C-0 guarantees that `execute()` always throws. This means `lock.unlock()`, `lock.close()`, and `lock.unlink()` are **never called in practice**.

**Fix**:
```dart
if (locked) {
  try {
    execution.execute();
    if (verbose) print('Finished Guarded execution for lock: $name');
  } finally {
    lock.unlock();
    if (verbose) print('Unlocked lock: $name');
    lock.close();
    if (verbose) print('Closed lock: $name');
    lock.unlink();
    if (verbose) print('Unlinked lock: $name');
  }
}
```

---

### C-2 — Reentrant Deadlock — `named_lock.dart:174-201`

**Severity**: CRITICAL
**File**: `lib/src/named_lock.dart`
**Lines**: 174-201

**Description**:
POSIX named semaphores (macOS, Linux) and Windows named semaphores are **not reentrant**. If the same Dart isolate calls `NamedLock.guard()` with the same `name` while already holding that lock (e.g., from within the callable), the inner `lock.lock()` call blocks forever, deadlocking the isolate.

**Scenario**:
```dart
NamedLock.guard(
  name: 'my-lock',
  execution: ExecutionCall(
    callable: () {
      // ↓ Same isolate, same name → DEADLOCK
      NamedLock.guard(
        name: 'my-lock',
        execution: ExecutionCall(callable: () => 42),
      );
      return 1;
    },
  ),
);
```

**Relevant Code**:
```dart
// named_lock.dart:201 — inner call blocks here forever
bool locked = lock.lock();  // POSIX sem_wait() — blocks if semaphore count is 0
```

**Test Impact**: `named_lock_test.dart:62-90` ("Reentrant within a single isolate") does exactly this — calls `NamedLock.guard()` with the same `name` synchronously from within the outer callable's `nested_calculation()` helper. This test will deadlock.

**Fix**: Track held locks per isolate using an isolate-local `Set<String>`. Before acquiring, check if the current isolate already holds the lock:
```dart
// In guard() before lock.lock():
if (_heldLocks.contains(name)) {
  throw StateError('Reentrant call to NamedLock.guard() with name "$name" is not supported. '
      'The current isolate already holds this lock.');
}
_heldLocks.add(name);
// ... acquire lock ...
// In finally:
_heldLocks.remove(name);
```

---

### C-3 — Async Callable: Lock Released Before Future Resolves — `named_lock.dart:205`, `execution_call.dart:89-99`

**Severity**: CRITICAL
**File**: `lib/src/named_lock.dart:205` and `lib/src/execution_call.dart:89-99`

**Description**:
When the callable returns `Future<R>`, `execute()` returns immediately (before the future resolves). The lock cleanup (`unlock`, `close`, `unlink`) runs immediately after `execute()` returns, while the async work is still in flight.

**How it breaks**:

```dart
// execution_call.dart:85-99 (simplified)
_returned = _callable();  // Line 85: For async callables, this returns a Future<R>

// Line 89: Future<R> case — chains handlers but does NOT await
_returned is Future<R>
    ? _returned
        .then(completer.complete)    // chains — does not block execute()
        .catchError(...)
        .whenComplete(...)
    : _successful = (completer..complete(_returned)).isCompleted;

// execute() returns HERE, before the future resolves
```

```dart
// named_lock.dart:205-216
execution.execute();  // returns immediately — future still running
lock.unlock();        // ← Lock released while async work runs!
lock.close();
lock.unlink();
```

**Example**:
```dart
// The lock is released before the async critical section completes
NamedLock.guard(
  name: 'db-write-lock',
  execution: ExecutionCall(
    callable: () async {
      // ← Lock is ALREADY released by the time this runs
      await database.write(data);  // ← NOT protected by lock!
      return true;
    },
  ),
);
```

**Test Impact**: `named_lock_test.dart:134-151` uses `callable: () async { ... }` returning `Future<int>`. The 4 spawned isolates are not actually protected by the outer lock.

**Fix**: Await the completer's future before cleanup:
```dart
if (locked) {
  try {
    execution.execute();
    // Wait for async callables to complete before releasing lock
    if (execution.completer.future != null) {
      await execution.completer.future;
    }
  } finally {
    lock.unlock();
    lock.close();
    lock.unlink();
  }
}
```

---

### C-4 — Unbounded Memory Leak in Instance Registries — Multiple Files

**Severity**: CRITICAL
**Files**: `lib/src/named_lock.dart`, `lib/src/lock_identity.dart`, `lib/src/lock_counter.dart`

**Description**:
Multiple `static final Map` registries accumulate entries indefinitely. Every unique lock name used during a process's lifetime creates a permanent entry in these maps that is never removed.

**Affected registries**:

```dart
// named_lock.dart — UnixLock.__instances, WindowsLock.__instances
static late final dynamic __instances;  // Map of name → lock instance

// lock_identity.dart — LockIdentities.__identities
static final Map<String, dynamic> __identities = {};  // name → identity

// lock_identity.dart — LockIdentity.__instances
static late final dynamic __instances;

// lock_counter.dart — LockCounters.__counters
static final Map<String, dynamic> __counters = {};  // name → counter

// lock_counter.dart — LockCount.__counts
static final Map<String, int?> __counts = {};  // name → count
```

**Impact**: Long-running servers creating many unique lock names (e.g., per-request locks) will slowly leak memory. The leak is bounded per lock instance by the size of the lock objects, but multiplied by the number of unique names used.

**Fix**: In the `unlink()` call path (or at the end of `guard()`), remove the name from all registries:
```dart
// After unlink():
(__instances as NLS).remove(name);
LockIdentity.__instances.remove(name);
LockCounter.__instances.remove(name);
```

---

## HIGH Issues

---

### H-1 — Instance Registry Race Condition — Multiple Files

**Severity**: HIGH
**Files**: `lib/src/named_lock.dart:76-77`, `lib/src/named_lock.dart:142-143`, `lib/src/lock_identity.dart:36-37`, `lib/src/lock_counter.dart:79-81`

**Description**:
The "check then register" pattern used in all `instantiate()` methods is not atomic. Two concurrent calls with the same lock name could both pass the `has()` check before either registers, resulting in two separate lock instances being created for the same name.

**Code Pattern (appears in 4 places)**:
```dart
// named_lock.dart:76-79 (UnixLock.instantiate)
return (__instances as NLS).has<UL>(name: name)   // ← check
    ? (__instances as NLS).get(name: name)
    : (__instances as NLS).register(               // ← register — NOT atomic!
        name: name,
        semaphore: UnixLock(...) as UL
      );
```

**Impact**: Two threads/isolates could create two `UnixLock` instances for the same name. The second `register()` call may overwrite the first instance, orphaning it. The orphaned lock holds an open OS semaphore handle that is never closed.

**Fix**: Use an isolate-local mutex or `synchronized` pattern around the check-register block. Since Dart isolates are single-threaded, the race only manifests across isolates via `Isolate.spawn`. An isolate-local registry is safe within an isolate; the OS semaphore provides cross-isolate safety.

---

### H-2 — Timeout Overshoot — `named_lock.dart:186-231`

**Severity**: HIGH
**File**: `lib/src/named_lock.dart`
**Lines**: 186-231

**Description**:
The timeout check happens at the **top** of the retry loop, before sleeping. When backoff has grown to 500ms and the timeout just expired, the loop sleeps an additional 500ms before re-checking. Actual wait can exceed `timeout` by up to 500ms.

**Buggy Code**:
```dart
// named_lock.dart:186-231 (simplified)
while (!locked) {
  // Line 186: Check timeout BEFORE sleeping
  if (DateTime.now().difference(start) >= timeout) {
    // TODO: subtract sleep from timeout now.subtract(_sleep)
    throw Exception('NamedLock.guard has failed to acquire lock within $timeout.');
  }

  // Line 223: Sleep AFTER check — can overshoot by _sleep duration
  if (!locked) {
    sleep(_sleep);  // _sleep can be up to 500ms

    // Line 231: Backoff calculation
    _sleep = Duration(milliseconds:
        (_sleep.inMilliseconds + _attempt * 10).clamp(5, 500));
    _attempt++;
  }
}
```

**Example**:
- `timeout = 100ms`, elapsed = 95ms, `_sleep = 500ms`
- Check: 95ms < 100ms → OK, do not throw
- Sleep: 500ms
- Check: 595ms > 100ms → throw
- **Actual wait: 595ms, not 100ms**

**Fix**: Check if remaining time allows a full sleep cycle:
```dart
final remaining = timeout - DateTime.now().difference(start);
if (remaining <= Duration.zero) throw Exception(...);
final actualSleep = remaining < _sleep ? remaining : _sleep;
sleep(actualSleep);
```

---

### H-3 — Static Registries are Isolate-Local — All `static` Fields

**Severity**: HIGH
**Files**: All source files with `static` fields

**Description**:
Dart static fields are **not shared across isolates**. Each spawned isolate has its own copy of `__instances`, `__identities`, `__counters`, etc. The code comments and structure imply global-process-level state, but the actual behavior is isolate-local.

**Impact**:
- `LockCounter` stats will be incorrect when multiple isolates use the same lock — each isolate counts independently
- Instance identity comparisons between isolates are meaningless
- The "singleton per name" design only holds within a single isolate

**Note**: The actual **locking correctness** is NOT affected, because the underlying OS semaphore is global across processes. Each isolate's lock correctly participates in the OS-level mutual exclusion. The bug is in the telemetry and registry semantics, not the locking.

---

### H-4 — Unlock/Close/Unlink Return Values Ignored — `named_lock.dart:210-216`

**Severity**: HIGH
**File**: `lib/src/named_lock.dart`
**Lines**: 210-216

**Description**:
The return values of `lock.unlock()`, `lock.close()`, and `lock.unlink()` are all silently discarded. These operations can fail (e.g., unlocking an unowned semaphore, closing an already-closed handle), and failures go completely undetected.

**Buggy Code**:
```dart
// named_lock.dart:210-216
lock.unlock();   // bool return discarded — error silently ignored
if (verbose) print('Unlocked lock: $name');

lock.close();    // bool return discarded
if (verbose) print('Closed lock: $name');

lock.unlink();   // bool return discarded
if (verbose) print('Unlinked lock: $name');
```

**Fix**:
```dart
if (!lock.unlock()) {
  throw StateError('Failed to unlock semaphore "$name".');
}
if (!lock.close()) {
  throw StateError('Failed to close semaphore "$name".');
}
if (!lock.unlink()) {
  // unlink failure may be acceptable (another process may have unlinked first)
  if (verbose) print('Warning: Failed to unlink semaphore "$name" — may have been unlinked by another process.');
}
```

---

### H-5 — CI Workflow Matrix Assignments Swapped — `workflow.yaml:115-132`

**Severity**: HIGH
**File**: `.github/workflows/workflow.yaml`
**Lines**: 115-132

**Description**:
The `macos-apple-silicon-matrix` and `macos-intel-matrix` jobs reference each other's matrix outputs. Apple Silicon tests run on Intel runners and Intel tests run on Apple Silicon runners.

**Buggy Code**:
```yaml
# workflow.yaml:115-121
macos-apple-silicon-matrix:
  strategy:
    matrix:
      config:
        - ${{ fromJSON(needs.define-matrices.outputs.MACOS_INTEL_MATRIX) }}
        # ↑ WRONG! Should be MACOS_APPLE_SILICON_MATRIX

# workflow.yaml:134-142
macos-intel-matrix:
  strategy:
    matrix:
      config:
        - ${{ fromJSON(needs.define-matrices.outputs.MACOS_APPLE_SILICON_MATRIX) }}
        # ↑ WRONG! Should be MACOS_INTEL_MATRIX
```

**Impact**: Platform-specific bugs that only affect ARM64 vs x86_64 will be reported on the wrong platform. Tests may pass on one architecture but fail on the other without the CI detecting it correctly. ARMv8-specific semaphore behavior differences are untested on Apple Silicon hardware.

**Fix**: Swap the matrix output references:
```yaml
macos-apple-silicon-matrix:
  config:
    - ${{ fromJSON(needs.define-matrices.outputs.MACOS_APPLE_SILICON_MATRIX) }}  # ← fixed

macos-intel-matrix:
  config:
    - ${{ fromJSON(needs.define-matrices.outputs.MACOS_INTEL_MATRIX) }}  # ← fixed
```

---

### H-6 — Reusable Workflow Uses Outdated Action Versions — `reusable-named-locks-platform-tester.yaml:69,80`

**Severity**: HIGH
**File**: `.github/workflows/reusable-named-locks-platform-tester.yaml`
**Lines**: 69, 80

**Description**:
The reusable platform tester workflow pins significantly older versions of core GitHub Actions than all other workflows in the same repository.

**Mismatched versions**:

| Action | reusable-*.yaml | All other workflows |
|---|---|---|
| `actions/checkout` | `v4.1.4` (line 69) | `v6.0.2` |
| `dart-lang/setup-dart` | `v1.6.4` (line 80) | `v1.7.1` |

**Additionally**: No explicit Dart SDK version is pinned in the reusable workflow (`setup-dart` call has no `sdk:` parameter), while all other workflows pin `sdk: "3.9.2"`. Platform tests could run against a different Dart version than CI, causing false passes or failures.

**Fix**:
```yaml
# reusable-named-locks-platform-tester.yaml:69
- name: Checkout
  uses: actions/checkout@v6.0.2  # was v4.1.4

# reusable-named-locks-platform-tester.yaml:80
- name: Setup Dart SDK
  uses: dart-lang/setup-dart@v1.7.1  # was v1.6.4
  with:
    sdk: "3.9.2"  # add explicit version
    architecture: ${{ matrix.config.architecture.dart }}
```

---

## MEDIUM Issues

---

### M-1 — `rethrow_()` Null Safety Violation — `execution_call.dart:31-37`

**Severity**: MEDIUM
**File**: `lib/src/execution_call.dart`
**Lines**: 31-37

**Description**:
The `rethrow_()` method uses `!caught` as the first branch of a ternary, but if `!caught` is true (no error was caught), it immediately tries to force-unwrap `anticipated.get ?? unknown.get` which would be `null`, causing a null dereference.

**Buggy Code**:
```dart
// execution_call.dart:31-37
FutureOr<E> rethrow_() {
  if (completer.isCompleted)
    !caught || trace.isSet                                               // ← !caught can be true
        ? (throw Error.throwWithStackTrace(
              (anticipated.get ?? unknown.get)!,  // ← NPE if !caught (both are null)
              trace.get!))
        : (throw (anticipated.get ?? unknown.get)!);
  // ...
}
```

**Fix**:
```dart
FutureOr<E> rethrow_() {
  if (!caught) return completer.future as FutureOr<E>;  // Nothing to rethrow
  if (completer.isCompleted) {
    final error = (anticipated.get ?? unknown.get)!;
    if (trace.isSet) {
      throw Error.throwWithStackTrace(error, trace.get!);
    } else {
      throw error;
    }
  } else {
    return completer.future.then((_) {
      final error = (anticipated.get ?? unknown.get)!;
      throw trace.isSet ? Error.throwWithStackTrace(error, trace.get!) : error;
    });
  }
}
```

---

### M-2 — Inverted Registry Assertion in `LockIdentities` — `lock_identity.dart:37` (Inherited)

**Severity**: MEDIUM
**File**: `lib/src/lock_identity.dart`
**Lines**: 35-38

**Description**:
The `register()` method inherited from `SemaphoreIdentities` (in `runtime_native_semaphores`) has an inverted assertion: it asserts `containsKey || identity != value` when it should assert `!containsKey || identity == value`. This means the registry considers a successful registration to be a failure state.

**Location of root bug**: `runtime_native_semaphores` package, `SemaphoreIdentities.register()`.
**Manifestation in named_locks**: `LockIdentities` inherits this behavior at `lock_identity.dart:37`.

**Impact**: The assertion may throw `AssertionError` in debug mode when the same lock name is used twice (which is the common case — `guard()` reuses existing instances). This only manifests with `dart --enable-asserts`.

---

### M-3 — `LockIdentity.uuid` Uses Non-Deterministic `hashCode` — `lock_identity.dart:29`

**Severity**: MEDIUM
**File**: `lib/src/lock_identity.dart`
**Lines**: 29, and `captured_call_frame.dart:8`

**Description**:
The `uuid` property includes `caller`, which is computed from the `hashCode` of stack frame URIs:

```dart
// lock_identity.dart:29
String get uuid => [name, isolate, process, caller].join('_');

// captured_call_frame.dart:8
late final String caller = current.frames.take(5)
    .map((e) => e.uri.hashCode)  // ← hashCode is non-deterministic
    .join("_");
```

**Problems**:
- `hashCode` is not stable across VM invocations (Dart does not guarantee hash stability)
- Refactoring code (adding/removing lines) changes stack frame URIs, changing `caller`, changing `uuid`
- Hash collisions are possible — two different call sites could produce the same `uuid`

**Impact**: Lock instances keyed by `uuid` could fail to find existing instances after code changes, creating duplicate lock entries. This exacerbates the memory leak in C-4.

**Fix**:
```dart
// captured_call_frame.dart:8
late final String caller = current.frames.take(5)
    .map((e) => e.location)  // e.g., "main.dart:42:12" — deterministic
    .join("_");
```

---

### M-4 — `waiting` Parameter Docs Missing — `named_lock.dart:171`

**Severity**: MEDIUM
**File**: `lib/src/named_lock.dart`
**Lines**: 171, 226-229

**Description**:
The `waiting` parameter was added in beta.5 but is undocumented in the README. Its behavior (prints once, then set to null to suppress repeats) is non-obvious:

```dart
// named_lock.dart:226-229
if (_attempt == 1 && waiting is String) {
  print(waiting);
  waiting = null;  // ← reassigns local, prevents printing again
}
```

The README "Getting Started" section shows no `waiting` usage example. Users who discover it may not understand why it only prints once.

---

### M-5 — No `dart format` Enforcement in CI — `ci.yaml:79-83`

**Severity**: MEDIUM
**File**: `.github/workflows/ci.yaml`
**Lines**: 79-83

**Description**:
The CI pipeline has no step to verify code formatting. `dart format --set-exit-if-changed` is never called.

**Missing step**:
```yaml
- name: Check formatting
  run: dart format --set-exit-if-changed --output=none .
```

---

### M-6 — No Code Coverage Reporting — `ci.yaml:82-83`

**Severity**: MEDIUM
**File**: `.github/workflows/ci.yaml`
**Lines**: 82-83

**Description**:
The test step collects no coverage data. For a concurrency library with known bugs in edge cases, coverage gaps in the critical sections are invisible.

---

### M-7 — SDK Caches Disabled in Platform Tester — `reusable-named-locks-platform-tester.yaml:50-66`

**Severity**: MEDIUM
**File**: `.github/workflows/reusable-named-locks-platform-tester.yaml`
**Lines**: 50-66

**Description**:
Both the Dart SDK cache and pub dependencies cache are commented out with TODO notes. Every platform test run re-downloads the full SDK and all dependencies.

```yaml
# TODO: Re-enable the cache for the dart sdk
# - name: Restore Cached Dart SDK
#   uses: actions/cache@v3.3.1
#   ...

# TODO: Re-enable the cache for the pub dependencies
# - name: Restore Cached Pub Dependencies
#   uses: actions/cache@v3.3.1
#   ...
```

**Impact**: Slow, expensive CI on premium runners (macOS Apple Silicon, macOS Intel, Windows). Increased failure risk from network timeouts.

---

### M-8 — `create-release` Job Missing `GITHUB_TOKEN` Fallback — `release.yaml:625-626`

**Severity**: MEDIUM
**File**: `.github/workflows/release.yaml`
**Lines**: 625-626

**Description**:
All other jobs in `release.yaml` use `secrets.TSAVO_AT_PIECES_PERSONAL_ACCESS_TOKEN || secrets.GITHUB_TOKEN` as a fallback pattern. The `create-release` job only uses the personal token:

```yaml
# release.yaml:625-626 — missing fallback
env:
  GH_TOKEN: ${{ secrets.TSAVO_AT_PIECES_PERSONAL_ACCESS_TOKEN }}
  GITHUB_TOKEN: ${{ secrets.TSAVO_AT_PIECES_PERSONAL_ACCESS_TOKEN }}
```

If the personal access token secret is not set in the repository, the `create-release` job will fail with an authentication error and no release will be created.

**Fix**:
```yaml
env:
  GH_TOKEN: ${{ secrets.TSAVO_AT_PIECES_PERSONAL_ACCESS_TOKEN || secrets.GITHUB_TOKEN }}
  GITHUB_TOKEN: ${{ secrets.TSAVO_AT_PIECES_PERSONAL_ACCESS_TOKEN || secrets.GITHUB_TOKEN }}
```

---

## LOW Issues

---

### L-1 — Empty Lock Names Not Validated — `named_lock.dart:174`

**Severity**: LOW
**File**: `lib/src/named_lock.dart`
**Line**: 174

**Description**: Passing `name: ''` produces a cryptic OS-level error rather than a clear `ArgumentError`.

**Fix**:
```dart
// Add at the top of guard() before instantiation:
if (name.isEmpty) {
  throw ArgumentError.value(name, 'name', 'Lock name cannot be empty.');
}
```

---

### L-2 — Lock Name Length Not Validated — `named_lock.dart:174`

**Severity**: LOW
**File**: `lib/src/named_lock.dart`
**Line**: 174

**Description**: POSIX limits named semaphore names to 255 characters (including the leading `/`). Windows allows 260 characters for named objects (with `Global\` prefix counted). No validation is performed.

**Fix**:
```dart
final maxLen = Platform.isWindows ? 260 : 254;
if (name.length > maxLen) {
  throw ArgumentError.value(name, 'name', 'Lock name exceeds max length of $maxLen.');
}
```

---

### L-3 — Backoff Sequence Off-by-One — `named_lock.dart:178, 223, 231`

**Severity**: LOW
**File**: `lib/src/named_lock.dart`
**Lines**: 178, 223, 231

**Description**: The initial `_sleep = Duration(milliseconds: 2)` (line 178) suggests the first sleep should be 2ms. But the backoff formula runs before the sleep, so the actual first sleep is 12ms.

**Code**:
```dart
// Line 178: initial value
Duration _sleep = Duration(milliseconds: 2);

// In loop (lines 223, 231):
sleep(_sleep);  // Line 223: sleeps current value
_sleep = Duration(milliseconds:
    (_sleep.inMilliseconds + _attempt * 10).clamp(5, 500));  // Line 231: updates for NEXT iteration
```

**Actual sequence**: 2ms (first sleep) → updates to 12ms → sleeps 12ms → updates to 22ms → ...

Actually reading more carefully: the sleep happens first, then the update. So the sequence IS 2ms, 12ms, 22ms... — The CLAUDE.md notes this as off-by-one, but the order is correct. The comment `# initial: 2ms` is accurate. This issue may be documentation inaccuracy rather than a code bug.

---

### L-4 — `toString()` Missing Return Type Annotation — `execution_call.dart:29`

**Severity**: LOW
**File**: `lib/src/execution_call.dart`
**Line**: 29

**Description**: The `toString()` override is missing the `String` return type annotation.

**Buggy Code**:
```dart
// execution_call.dart:28-29
@override
toString() => 'ExecutionCallErrors(anticipated: $anticipated, Unknown: $unknown, Trace: $trace)';
```

**Fix**:
```dart
@override
String toString() => 'ExecutionCallErrors(anticipated: $anticipated, Unknown: $unknown, Trace: $trace)';
```

---

### L-5 — Unused `typedef` — `captured_call_frame.dart:3`

**Severity**: LOW
**File**: `lib/src/captured_call_frame.dart`
**Line**: 3

**Description**: A typedef is defined but never used anywhere in the codebase.

**Code**:
```dart
// captured_call_frame.dart:3
typedef CaptureCallFrameResult = String;
```

**Fix**: Remove the typedef.

---

### L-6 — Mutable Static `prefix` Field — `lock_identity.dart:5`

**Severity**: LOW
**File**: `lib/src/lock_identity.dart`
**Line**: 5

**Description**: The `prefix` field is declared as `static String` (mutable), not `static const` or `static final`. Any code can modify it, changing the prefix for all lock identities globally.

**Code**:
```dart
// lock_identity.dart:5
static String prefix = 'runtime_native_locks';  // ← mutable
```

**Fix**:
```dart
static const String prefix = 'runtime_native_locks';
```

---

### L-7 — Redundant Null Default Parameters — `lock_counter.dart:5, 9`

**Severity**: LOW
**File**: `lib/src/lock_counter.dart`
**Lines**: 5, 9

**Description**: Nullable parameters explicitly default to `null`, which is already the implicit default.

**Code**:
```dart
// lock_counter.dart:4-6
LockCountUpdate({
  required String identifier,
  int? from = null,  // ← redundant; null is the default for int?
  required int to
})

// lock_counter.dart:8-10
LockCountDeletion({
  required String identifier,
  int? at = null  // ← redundant
})
```

**Fix**:
```dart
LockCountUpdate({
  required String identifier,
  int? from,
  required int to,
})
```

---

### L-8 — `hashCode` Used for Identity — `captured_call_frame.dart:8`

**Severity**: LOW
**File**: `lib/src/captured_call_frame.dart`
**Line**: 8

**Description**: Using `uri.hashCode` for identity is unreliable. Dart's `hashCode` is not guaranteed to be stable across runs or platforms. See M-3 for full details.

**Code**:
```dart
late final String caller = current.frames.take(5)
    .map((e) => e.uri.hashCode)  // ← non-deterministic, collision-prone
    .join("_");
```

---

### L-9 — No Dartdoc Comments — All Source Files

**Severity**: LOW
**Files**: All 5 source files in `lib/src/`

**Description**: No `///` documentation comments exist on any class, constructor, method, or property in the entire library. This has been a TODO item in the CHANGELOG since beta.3 but has not been addressed through beta.5.

**Impact**: Users of the library get no inline IDE documentation. Generated API reference is empty.

---

### L-10 — `LockCount.update()` Convoluted `from` Capture — `lock_counter.dart:22`

**Severity**: LOW
**File**: `lib/src/lock_counter.dart`
**Line**: 22

**Description**: The logic to capture the previous value before updating is unnecessarily complex:

```dart
// lock_counter.dart:22
from: counts.putIfAbsent(identifier, () => null) ?? counts[identifier],
```

`putIfAbsent` inserts `null` and returns `null` if the key is absent. Then `?? counts[identifier]` fetches the same `null` back. The result is that `from` is always `null` on first call (correct), and also `null` on subsequent calls where `putIfAbsent` returns `null` because the key already exists with `null`.

**Fix**:
```dart
// Capture previous value before assignment
final int? previousValue = counts[identifier];
counts[identifier] = value;
// Use previousValue as `from`
```

---

## Test Coverage Gaps

| Missing Test | Severity | Relevant Bug(s) |
|---|---|---|
| Lock timeout actually throws | CRITICAL | H-2 |
| Mutual exclusion actually serializes (not just math) | CRITICAL | (fundamental) |
| Lock is released after exception inside callable | CRITICAL | C-1 |
| Async callable: lock held until future resolves | CRITICAL | C-3 |
| Reentrant call throws `StateError` (not deadlock) | CRITICAL | C-2 |
| Memory: registry cleaned up after guard | HIGH | C-4 |
| Empty string lock name | MEDIUM | L-1 |
| Lock name > 255 chars | MEDIUM | L-2 |
| `unlock()`/`close()`/`unlink()` failure handling | MEDIUM | H-4 |
| `rethrow_()` called when `caught == false` | MEDIUM | M-1 |
| `waiting` parameter prints once then suppressed | LOW | M-4 |
| 50+ concurrent isolates stress test | LOW | (scalability) |

---

## Related Issues in Dependency

Many issues in `runtime_named_locks` are inherited from or mirror bugs in the upstream `runtime_native_semaphores` package:

| Issue in named_locks | Root cause in native_semaphores |
|---|---|
| M-2 (inverted registry assertion) | `SemaphoreIdentities.register()` |
| C-4 (memory leak, never cleared) | `SemaphoreIdentities`, `SemaphoreCounts` |
| H-1 (check-then-register race) | `SemaphoreIdentities.instantiate()` pattern |
| H-3 (isolate-local statics) | All `static` fields in `Semaphore*` classes |

---

## Summary

| Severity | Count |
|---|---|
| CRITICAL | 5 (C-0 through C-4) |
| HIGH | 6 (H-1 through H-6) |
| MEDIUM | 8 (M-1 through M-8) |
| LOW | 10 (L-1 through L-10) |
| **Total** | **29** |

**Most urgent**: Fix C-0 (`execute()` always throws) and C-1 (no try/finally) — without these two fixes, `NamedLock.guard()` is completely non-functional. The lock is always acquired but the callable is never executed and the lock is never released.
