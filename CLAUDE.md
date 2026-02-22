# runtime_named_locks — Claude AI Guide

## Project Overview

`runtime_named_locks` is a Dart library that provides named locks (mutual exclusion zones) for concurrent Dart applications. It wraps platform-native named semaphores (via `runtime_native_semaphores`) into an ergonomic `NamedLock.guard()` API that works across:

- Multiple Dart isolates within the same process
- Multiple independent Dart processes (AOTs sharing a lock name)
- macOS (x86_64, arm64), Linux (x86_64, arm64), Windows (x86_64)

**Standalone GitHub repo**: https://github.com/open-runtime/named_locks
**Source of truth is this monorepo** — edit here, then push to standalone.

---

## File Structure

```
lib/
  runtime_named_locks.dart          # Barrel export file (public API surface)
  src/
    named_lock.dart                 # NamedLock, UnixLock, WindowsLock (core — 249 lines)
    execution_call.dart             # ExecutionCall<R,E>, ExecutionCallErrors<R,E> (132 lines)
    lock_identity.dart              # LockIdentity, LockIdentities (45 lines)
    lock_counter.dart               # LockCounter, LockCount, LockCounts, LockCounters (95 lines)
    captured_call_frame.dart        # CapturedCallFrame (12 lines)

test/
  named_lock_test.dart              # Integration tests (154 lines, 4 tests)

.github/workflows/
  ci.yaml                           # analyze + test on push/PR (ubuntu-latest, 84 lines)
  workflow.yaml                     # Multi-platform matrix tester (triggered on main push, 227 lines)
  reusable-named-locks-platform-tester.yaml  # Reusable workflow called by workflow.yaml (89 lines)
  release.yaml                      # 8-stage AI-assisted release pipeline (697 lines)
  issue-triage.yaml                 # Gemini-powered issue triage (99 lines)

.runtime_ci/
  config.json                       # Release bot + cross-repo tracking config (107 lines)
  autodoc.json                      # AI documentation generation config (47 lines)

scripts/prompts/
  autodoc_quickstart_prompt.dart
  autodoc_api_reference_prompt.dart
  autodoc_examples_prompt.dart
```

---

## Architecture

### Lock Lifecycle (NamedLock.guard)

```
instantiate() → open() → [retry loop with backoff] → lock() → execute() → unlock() → close() → unlink()
```

1. `NamedLock.guard()` detects platform (Unix vs Windows) and gets/creates a singleton lock instance keyed by `name`
2. Opens the underlying OS semaphore
3. Retry loop: attempts `lock.lock()` with backoff (2ms initial, up to 500ms, 5s default timeout)
4. On acquire: runs `execution.execute()`, then `unlock()` → `close()` → `unlink()`
5. On timeout: throws `Exception('NamedLock.guard has failed to acquire lock within $timeout.')`

### Key Classes

| Class | Purpose |
|---|---|
| `NamedLock` | Public API. Single static method `guard<R,E>()`. |
| `UnixLock` | Platform impl for macOS/Linux. Extends `UnixSemaphore`. |
| `WindowsLock` | Platform impl for Windows. Extends `WindowsSemaphore`. |
| `ExecutionCall<R,E>` | Wraps a callable with return type R, expected exception E. Tracks completion, return value, errors. |
| `ExecutionCallErrors<R,E>` | Holds `anticipated` (typed E), `unknown` (Object), `trace` (StackTrace). Has `rethrow_()`. |
| `LockIdentity` | Unique identity per lock: combines name + isolate + process + call frame hash. |
| `LockCounter` | Tracks acquisition counts per lock per isolate. Telemetry. |
| `CapturedCallFrame` | Captures `Trace.current(0)` at instantiation; hashes first 5 frames for caller identity. |

### Generic Type Parameters

The codebase uses deeply nested generics (inherited from `native_semaphores`). The `NamedLock.guard<R, E>()` public API hides all of it. Full parameter list in `named_lock.dart`:

```
I  → LockIdentity
IS → LockIdentities<I>
CU → LockCountUpdate
CD → LockCountDeletion
CT → LockCount<CU, CD>
CTS→ LockCounts<CU, CD, CT>
CTR→ LockCounter<I, CU, CD, CT, CTS>
CTRS→LockCounters<I, CU, CD, CT, CTS, CTR>
```

### Backoff Strategy

```
initial: 2ms
formula: new_sleep = (old_sleep + attempt * 10).clamp(5, 500)  // milliseconds
result:  12 → 22 → 34 → 48 → ... → 500ms max
```

Note: First sleep is actually 12ms (not 2ms) — the initial `_sleep = 2ms` is set but the calculation `(2 + 1*10).clamp(5,500) = 12` runs before first sleep.

---

## Common Patterns

### Basic Critical Section

```dart
final ExecutionCall<String, Exception> result = NamedLock.guard(
  name: 'my-lock-name',
  execution: ExecutionCall(
    callable: () => 'result from critical section',
  ),
);
print(result.returned);
```

### Exception Handling (Unsafe — Default)

```dart
try {
  NamedLock.guard(
    name: 'my-lock',
    execution: ExecutionCall(
      callable: () => throw MyException('failure'),
    ),
  );
} on MyException catch (e) {
  // handle
}
```

### Exception Handling (Safe — Captured)

```dart
final result = NamedLock.guard(
  name: 'my-lock',
  execution: ExecutionCall(
    callable: () => throw MyException('failure'),
    safe: true,
  ),
);
if (result.error.isSet) {
  result.error.get?.rethrow_(); // re-throw with original stack
}
```

### Async Callable (⚠️ BROKEN — see Bug C3 below)

```dart
// WARNING: Lock is released before async work completes (Bug C3).
// Do NOT use async callables until Bug C3 is fixed.
final result = NamedLock.guard(
  name: 'my-lock',
  execution: ExecutionCall(
    callable: () async {
      await someOperation();
      return 42;
    },
  ),
);
// Lock is already released by the time this future resolves
final value = await result.returned;
```

### Custom Wait Message

```dart
NamedLock.guard(
  name: 'my-lock',
  execution: ExecutionCall(callable: () => doWork()),
  waiting: 'Waiting to acquire resource lock...',
  timeout: Duration(seconds: 30),
);
```

### Lock Name Best Practices

```dart
// Use safe_int_id (in dev_dependencies) for test-unique names
import 'package:safe_int_id/safe_int_id.dart' show safeIntId;
final name = '${safeIntId.getId()}_my_critical_section';

// For cross-process: use a FIXED, agreed-upon name
const name = 'myapp_shared_db_write_lock';
```

---

## Running Tests

```bash
cd packages/libraries/dart/named_locks
dart test test/named_lock_test.dart
```

**Do NOT run from monorepo root** — workspace resolution will cause "Couldn't resolve package" errors.

---

## Known Bugs

These are confirmed issues discovered during code audit. Organized by severity.

### CRITICAL — Blocks Functionality

**Bug C0: `execute()` guard logic ALWAYS throws** (`execution_call.dart:75`)

This is the most severe bug in the package. The `execute()` method guard assertion is permanently broken:

```dart
// execution_call.dart:75
!guarded.isSet && (guarding = true) ||
    (throw Exception('Call to execute() can only be executed internally from the Lock.guard method.'));
```

In Dart, a setter (`guarding = true`) returns `void`. `void` in a boolean context is falsy. So:
- `!guarded.isSet && (void)` → always evaluates to `false`
- The right side `throw` is always reached

**Result**: `execution.execute()` unconditionally throws `'Call to execute() can only be executed internally...'`. No callable is ever executed via `NamedLock.guard()`.

**Fix needed**: Use an explicit `if/else` instead of the boolean guard trick:
```dart
if (!guarded.isSet) {
  guarding = true;
} else {
  throw Exception('Call to execute()...');
}
```

---

**Bug C1: Lock resource leak on exception** (`named_lock.dart:205-216`)

No `try/finally` around `execution.execute()`:

```dart
if (locked) {
  execution.execute();   // Line 205 — exception here skips cleanup
  lock.unlock();         // Line 210 — NEVER REACHED on exception
  lock.close();          // Line 213 — NEVER REACHED
  lock.unlink();         // Line 216 — NEVER REACHED
}
```

**Fix needed**: Wrap in try/finally:
```dart
if (locked) {
  try {
    execution.execute();
  } finally {
    lock.unlock();
    lock.close();
    lock.unlink();
  }
}
```

---

**Bug C2: Reentrant deadlock** (`named_lock.dart:174-201`)

POSIX and Windows named semaphores are NOT reentrant. If the same Dart isolate calls `NamedLock.guard()` with the same `name` recursively (synchronously), the inner `lock.lock()` call will block forever.

**Fix needed**: Track held locks per isolate; throw `StateError` on reentrant attempt.

---

**Bug C3: Async callable — lock released before future resolves** (`named_lock.dart:205, execution_call.dart:89-99`)

When the callable returns `Future<R>`, `execution.execute()` returns immediately. The lock is unlocked before the async work completes:

```dart
// execution_call.dart:89-99 (simplified)
_returned is Future<R>
    ? _returned.then(completer.complete)  // chains async — does NOT block
    : _successful = completer.complete(_returned);

// named_lock.dart:205-216
execution.execute();   // returns immediately for async callables
lock.unlock();         // lock released while Future is still running!
```

**Fix needed**: Await `execution.completer.future` before cleanup when callable returns a `Future`.

---

**Bug C4: Unbounded memory leak in instance registries** (`named_lock.dart`, `lock_counter.dart`, `lock_identity.dart`)

Static `Map` registries (`__instances`, `__identities`, `__counters`, `__counts`) never remove entries:

```dart
// Multiple files — example from named_lock.dart
static late final dynamic __instances;  // never cleared

// lock_counter.dart
static final Map<String, int?> __counts = {};   // never cleared
static final Map<String, dynamic> __counters = {};  // never cleared
```

Every unique lock name permanently leaks memory for the process lifetime.

**Fix needed**: Remove registry entries after `unlink()`.

---

### HIGH — Likely to Cause Issues

**Bug H1: Instance registry race condition** (`named_lock.dart:76-77, 142-143`, `lock_identity.dart:36-37`, `lock_counter.dart:79-81`)

The "check then register" pattern is not atomic. Concurrent calls with the same name could both pass the `has()` check and create two different lock instances:

```dart
return (__instances as NLS).has<UL>(name: name)      // check
    ? (__instances as NLS).get(name: name)
    : (__instances as NLS).register(name: name, ...); // register — NOT atomic!
```

---

**Bug H2: Timeout overshoot** (`named_lock.dart:186-231`)

The timeout is checked BEFORE sleeping. If `_sleep` has grown to 500ms and the timeout has just expired, the loop sleeps another 500ms before detecting the timeout. Actual wait can overshoot timeout by up to 500ms.

---

**Bug H3: Static registries are isolate-local** (all `static` fields)

Dart static fields are NOT shared across isolates. Each isolate has its own copy of all `__instances` maps. Cross-isolate locking works at the OS semaphore level (correct), but `LockCounter` stats and instance identity checks are per-isolate (incorrect — each isolate counts independently).

---

**Bug H4: `unlock()`/`close()`/`unlink()` return values ignored** (`named_lock.dart:210-216`)

```dart
lock.unlock();   // bool return discarded — failure silently ignored
lock.close();    // bool return discarded
lock.unlink();   // bool return discarded
```

If unlock fails (e.g., the semaphore was already unlocked due to a bug), the failure goes undetected.

---

**Bug H5: workflow.yaml matrix assignments are SWAPPED** (`.github/workflows/workflow.yaml:115-132`)

The Apple Silicon and Intel matrix jobs reference each other's matrix outputs:

```yaml
macos-apple-silicon-matrix:
  matrix:
    config:
      - ${{ fromJSON(needs.define-matrices.outputs.MACOS_INTEL_MATRIX) }}  # ← WRONG!

macos-intel-matrix:
  matrix:
    config:
      - ${{ fromJSON(needs.define-matrices.outputs.MACOS_APPLE_SILICON_MATRIX) }}  # ← WRONG!
```

**Result**: Apple Silicon tests run on Intel runners and vice versa.

---

### LOW

**Bug L1: Empty lock names not validated** — `name: ''` causes cryptic OS-level errors.
**Bug L2: Lock name length not validated** — POSIX max 255 chars, Windows 260. No checks.
**Bug L3: Backoff sleep off-by-one** — First sleep uses 12ms (not 2ms as initial `_sleep = 2ms` implies). The sequence is 12ms, 22ms, 34ms... not 2ms, 12ms, 22ms...
**Bug L4: `rethrow_()` null safety issue** (`execution_call.dart:33`) — Condition `!caught || trace.isSet` will force-unwrap null if `caught == false`, causing NPE.
**Bug L5: `CapturedCallFrame.caller` uses `hashCode`** (`captured_call_frame.dart:8`) — `uri.hashCode` is non-deterministic across VM runs; collisions possible; refactoring code changes lock identity.
**Bug L6: Inverted registry assertion** (`lock_identity.dart:37`) — Inherited from `native_semaphores`; the underlying `register()` method has inverted assertion logic (`containsKey || identity != value` instead of `!containsKey || identity == value`).
**Bug L7: `toString()` missing return type** (`execution_call.dart:29`) — Returns `dynamic` instead of `String`.
**Bug L8: Unused typedef** (`captured_call_frame.dart:3`) — `typedef CaptureCallFrameResult = String;` defined but never used.
**Bug L9: Mutable static `prefix`** (`lock_identity.dart:5`) — `static String prefix` should be `static const` or `static final`.
**Bug L10: Redundant null defaults** (`lock_counter.dart:5,9`) — `int? from = null` explicitly sets what is already the default.

---

## Test Coverage Gaps

The test suite (`named_lock_test.dart`) is minimal — 154 lines, 4 tests. Critical scenarios not tested:

| Missing Test | Why It Matters |
|---|---|
| Lock timeout throws exception | Core feature, completely untested |
| Mutual exclusion actually serializes | Tests pass even if lock is broken |
| Lock is released after exception | Bug C1 above — not caught by tests |
| Async callable with exception | Bug C3 above — not caught |
| Memory: registry cleanup after guard | Bug C4 above — not caught |
| Same-isolate reentrant → deadlock | Bug C2 — test 2.1 WILL deadlock (same lock name used synchronously) |
| Empty string lock name | Bug L1 |
| 100+ concurrent isolates stress test | Scalability unknown |

The multi-isolate test (`'Reentrant Behavior Across Several Isolates'`) does NOT verify that locks actually serialize. It only verifies the math result (`4+4+4+4=16`) — the test would pass even if no locking occurred.

**Additionally**: Test 2.1 (`'Reentrant within a single isolate'`) uses the same lock `name` for both outer and inner `NamedLock.guard()` calls synchronously. This WILL deadlock on POSIX/Windows semaphores. The test only works if (a) the bug C0 causes it to throw first, or (b) the implementation handles reentrancy somehow.

---

## CI/CD Notes

### CI Pipeline (`ci.yaml`)
- Runs on push/PR to `main`
- Jobs: `pre-check` → `analyze-and-test` (ubuntu-latest only)
- Uses `dart run runtime_ci_tooling:manage_cicd analyze` and `test`
- Dart SDK: **3.9.2** (pinned)
- Missing: `dart format --set-exit-if-changed` check, no code coverage

### Platform Tester (`workflow.yaml`)
- Triggers on push to `main` or `aot_monorepo_compat`
- Tests on: macOS Apple Silicon, macOS Intel, Ubuntu, Windows
- ⚠️ **Matrix assignments SWAPPED** (Bug H5 above)
- ⚠️ SDK and pub caches are **commented out** (TODO to re-enable — slower builds)
- `reusable-named-locks-platform-tester.yaml` uses outdated `checkout@v4.1.4` (vs v6.0.2 elsewhere) and `setup-dart@v1.6.4` (vs v1.7.1 elsewhere)
- No explicit Dart SDK version in reusable workflow (will use latest, not pinned 3.9.2)

### Release Pipeline (`release.yaml`)
- 8-stage AI-assisted pipeline: pre-check → version → triage → explore → compose → release-notes → create-release → post-triage
- Uses Gemini AI for changelog generation and version detection
- Cross-repo tracking: upstream `native_semaphores`, downstream `aot_monorepo`
- ⚠️ `create-release` job missing `GITHUB_TOKEN` fallback

---

## Package Metadata

```yaml
name: runtime_named_locks
version: 1.0.0-beta.5
publish_to: none  # Internal — not on pub.dev
sdk: ^3.9.0
dependencies:
  stack_trace: ^1.11.1
  runtime_native_semaphores: ^1.0.0-beta.6
dev_dependencies:
  runtime_ci_tooling: ^0.7.0
  test: ^1.25.5
  safe_int_id: ^1.1.1  # Used for lock name generation in tests
```

---

## Documentation Status

- **README**: Good coverage of main API. Missing: `waiting` parameter docs, true async warnings (Bug C3), troubleshooting. The async example is misleading — it shows async callable protecting async work, but the lock is released before the future resolves.
- **CHANGELOG**: Complete version history but recurring TODOs clutter entries across beta.3/4/5 without resolution.
- **Dartdoc**: **None.** Source files have no `///` doc comments. Known TODO since beta.3.

---

## Unresolved TODOs (from CHANGELOG and source)

| TODO | Location | Since |
|---|---|---|
| Leverage NamedLocks directly (outside guard()) | CHANGELOG, code | beta.3 |
| Add explicit `guardAsync()` method | CHANGELOG | beta.3 |
| Add dartdoc `///` comments to all source files | CHANGELOG, code | beta.3 |
| Subtract sleep from remaining timeout | `named_lock.dart:187` | unknown |
| Re-enable SDK/pub cache in platform tester CI | `.github/workflows/reusable-*.yaml` | unknown |
| Force close option (`lock.close(force: true)`) | `named_lock.dart:190` | unknown |
| Fix workflow.yaml matrix swap | `.github/workflows/workflow.yaml:115-132` | unknown |
| Fix execute() guard logic | `execution_call.dart:75` | unknown |
