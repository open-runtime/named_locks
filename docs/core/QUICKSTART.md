# Quickstart: Named Locks Core

## 1. Overview
The Named Locks Core module provides robust, cross-platform named synchronization primitives for Dart applications. It ensures mutually exclusive access to shared resources across different isolates or processes using native OS-level semaphores. 

The module is designed with reentrancy in mind, allowing the same identity to re-acquire the same lock safely. It offers a high-level `NamedLock` utility for automatic guarded execution, as well as direct access to `UnixLock` and `WindowsLock` for fine-grained manual control.

## 2. Import
To use the named locks in your project, import the main library package. This provides access to all core synchronization and execution utilities.

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';
```

## 3. Core Concepts

### `NamedLock`
The primary interface for synchronization. The `NamedLock.guard` method will create a new lock for you with the given lock name, execute some code with the lock held, and release/cleanup the internal execution once complete.

### `ExecutionCall<R, E>`
A wrapper for logic to be executed within a lock. It captures the return value, manages the lifecycle of the call, and tracks any exceptions that occur.

### `LockIdentity`
Uniquely identifies a lock's owner across isolates and processes. It uses stack trace analysis to capture the caller's frame, ensuring that locks are correctly attributed and supporting reentrant behavior.

---

## 4. Basic Usage

### Guarding a Critical Section
Use `NamedLock.guard` to automatically handle the open/lock/unlock/close/unlink lifecycle of a native semaphore.

```dart
// Define the work to be performed
final execution = ExecutionCall<int, Exception>(
  callable: () {
    // Perform critical section logic
    return 42;
  },
);

// Execute the work within a named lock
NamedLock.guard(
  name: 'my_unique_lock_name',
  execution: execution,
  timeout: const Duration(seconds: 10), // Maximum time to wait for the lock
  waiting: 'Waiting for access to my_unique_lock_name...', // Optional message on first wait
);

print('Result: ${execution.returned}'); // Access the captured return value
```

### Using Cascade Notation for Configuration
You can use Dart's cascade notation to configure an `ExecutionCall` during or after construction.

```dart
final execution = ExecutionCall<void, Exception>(
  callable: () => print('Executing with verbose logging...'),
)
  ..safe = false
  ..verbose = true;

NamedLock.guard(
  name: 'config_example_lock',
  execution: execution,
);
```

---

## 5. Error Handling

### Safe vs. Unsafe Execution
By default, `NamedLock.guard` will rethrow any exception captured by an `ExecutionCall` if it is not marked as `safe`.

```dart
final execution = ExecutionCall<void, FormatException>(
  callable: () => throw FormatException('Invalid data'),
  safe: true, // Prevents automatic rethrow from guard()
);

NamedLock.guard(name: 'safe_lock', execution: execution);

if (execution.error.isSet) {
  final errors = execution.error.get!;
  if (errors.caught) {
    print('Error caught: ${errors.anticipated.get ?? errors.unknown.get}');
    print('Stack trace: ${errors.trace.get}');
  }
}
```

### The `ExecutionCallErrors` Object
When an execution fails, detailed error information is stored in an `ExecutionCallErrors` instance.

- **`anticipated`**: Returns a record `({bool isSet, E? get})` containing the expected exception type `E`.
- **`unknown`**: Returns a record `({bool isSet, Object? get})` for unexpected errors.
- **`trace`**: Returns the `StackTrace` associated with the failure.
- **`caught`**: A boolean indicating if any error (anticipated or unknown) was captured.
- **`rethrow_()`**: A helper method to manually rethrow the captured error with its original stack trace.

```dart
// Manually rethrowing a captured error
if (execution.error.isSet) {
  execution.error.get?.rethrow_();
}
```

---

## 6. Advanced Usage

### Reentrancy
Named locks support reentrant behavior within the same isolate and across isolates if the `LockIdentity` matches. This allows for nested calls to `NamedLock.guard` using the same lock name without deadlocking.

```dart
void nestedCall() {
  NamedLock.guard(
    name: 'reentrant_lock',
    execution: ExecutionCall(callable: () => print('Inner lock acquired')),
  );
}

NamedLock.guard(
  name: 'reentrant_lock',
  execution: ExecutionCall(
    callable: () {
      print('Outer lock acquired');
      nestedCall(); // Re-acquires the same lock safely
    },
  ),
);
```

### Manual Lock Management
For scenarios requiring manual control, you can use `UnixLock` or `WindowsLock` directly.

```dart
import 'dart:io';

final identity = LockIdentity.instantiate(name: 'manual_resource');
final lock = Platform.isWindows
    ? WindowsLock.instantiate(name: 'manual_resource', identity: identity)
    : UnixLock.instantiate(name: 'manual_resource', identity: identity);

try {
  if (lock.open() && lock.lock()) {
    // Perform operations
    print('Lock UUID: ${lock.identity.uuid}');
    print('Caller ID: ${lock.identity.caller}');
  }
} finally {
  lock.unlock();
  lock.close();
  lock.unlink();
}
```

### Introspection and Identity
Every lock is associated with a `LockIdentity` which captures:
- **`name`**: The base name of the lock.
- **`uuid`**: A unique identifier combining the name, isolate ID, process ID, and caller hash.
- **`caller`**: A unique string identifying the specific call site in the source code.
- **`frame`**: A `CapturedCallFrame` containing the full stack trace at the time of identity creation.

---

## 7. Configuration Reference

### `NamedLock.guard` Parameters
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `name` | `String` | (Required) | The unique name for the native semaphore. |
| `execution` | `ExecutionCall` | (Required) | The logic to execute while holding the lock. |
| `timeout` | `Duration` | `5s` | Time to poll for the lock before throwing an exception. |
| `verbose` | `bool` | `false` | Enables detailed logging of the locking lifecycle. |
| `waiting` | `String?` | `null` | A message printed once if the lock is already held by another process. |

### `ExecutionCall` Fields
| Field | Type | Description |
|-------|------|-------------|
| `returned` | `R` | The value returned by the `callable`. Throws if called before completion. |
| `successful` | `Record` | `({bool isSet, bool? get})` indicating if the call finished without errors. |
| `error` | `Record` | `({bool isSet, ExecutionCallErrors? get})` containing error details. |
| `guarded` | `Record` | `({bool isSet, bool? get})` indicating if the call was run via a `NamedLock.guard`. |
| `safe` | `bool` | If true, prevents `NamedLock.guard` from rethrowing errors. |
| `verbose` | `bool` | Enables debug logging for the execution lifecycle. |
