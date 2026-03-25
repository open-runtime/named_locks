# Quickstart: Named Locks

## 1. Overview

The **Package Entry Points** module (`runtime_named_locks`) provides cross-platform, inter-process, and inter-isolate named synchronization locks (semaphores). It allows you to safely guard critical sections of code, ensuring that shared resources are protected across concurrent executions. The module automatically handles platform-specific backing implementations for Windows, macOS, and Linux.

Key APIs include `NamedLock`, `ExecutionCall`, `UnixLock`, and `WindowsLock`.

## 2. Import

Import the core runtime package to access all necessary classes and utilities:

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';
```

## 3. Setup

No global initialization is required. The library automatically provisions the correct underlying lock implementations (`UnixLock` or `WindowsLock`) based on the operating system. You interact with the module primarily by wrapping your target code in an `ExecutionCall` and passing it to `NamedLock.guard()`.

## 4. Common Operations

### Guarding a Critical Section
To protect a block of code with a system-wide named lock, wrap your logic inside an `ExecutionCall` and execute it using `NamedLock.guard`.

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() {
  // 1. Define the execution payload using cascade notation for optional configuration
  final execution = ExecutionCall<String, Exception>(
    callable: () {
      // Code inside here is protected by the named lock
      return 'Critical task completed';
    },
  )
    ..safe = false // Rethrow exceptions immediately (default)
    ..verbose = true; // Enable detailed console logging

  // 2. Guard the execution
  NamedLock.guard(
    name: 'my_shared_resource_lock',
    execution: execution,
    timeout: const Duration(seconds: 10), // Wait up to 10 seconds for the lock
    waiting: 'Waiting for lock...', // Message printed on the first retry attempt
  );

  // 3. Access the returned result
  if (execution.successful.get == true) {
    print(execution.returned); // Prints: Critical task completed
  }
}
```

### Safe Execution with Error Handling
By default, `NamedLock.guard` will rethrow exceptions encountered inside the `callable`. You can suppress this by setting `safe: true` on your `ExecutionCall`, allowing you to inspect the `ExecutionCallErrors` safely after the execution attempts.

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() {
  final safeExecution = ExecutionCall<void, FormatException>(
    callable: () {
      throw FormatException('Invalid data format encountered');
    },
    safe: true, // Prevents immediate rethrowing
  );

  NamedLock.guard(
    name: 'data_parser_lock',
    execution: safeExecution,
  );

  if (safeExecution.error.isSet) {
    final errorInfo = safeExecution.error.get;
    
    // Check if it was our expected exception type (FormatException)
    if (errorInfo?.anticipated.isSet == true) {
      print('Anticipated error caught safely: ${errorInfo?.anticipated.get}');
    }

    // Check for any other unexpected objects thrown
    if (errorInfo?.unknown.isSet == true) {
      print('An unknown error occurred: ${errorInfo?.unknown.get}');
    }

    // Access the stack trace if available
    if (errorInfo?.trace.isSet == true) {
      print('Stack trace: \n${errorInfo?.trace.get}');
    }

    // You can also manually rethrow the stored error if needed
    // safeExecution.error.get?.rethrow_();
  }
}
```

### Reentrant Locking
`NamedLock` supports reentrant locking within the same isolate. If a block of code already holding a lock attempts to acquire the same lock again, it will succeed without deadlocking.

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() {
  NamedLock.guard(
    name: 'reentrant_lock',
    execution: ExecutionCall(
      callable: () {
        print('Outer lock acquired');
        
        // Nested call to the same lock
        NamedLock.guard(
          name: 'reentrant_lock',
          execution: ExecutionCall(
            callable: () {
              print('Inner lock acquired (reentrant)');
            },
          ),
        );
      },
    ),
  );
}
```

### Manual Platform-Specific Lock Instantiation
In advanced scenarios where you need direct control over the native semaphore instance rather than using the high-level `guard` abstraction, you can instantiate the platform-specific lock directly:

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';
import 'dart:io';

void main() {
  if (Platform.isWindows) {
    final winLock = WindowsLock.instantiate(name: 'win_specific_lock');
    if (!winLock.opened) winLock.open();
    // Use the native WindowsSemaphore APIs
  } else if (Platform.isMacOS || Platform.isLinux) {
    final unixLock = UnixLock.instantiate(name: 'unix_specific_lock');
    if (!unixLock.opened) unixLock.open();
    // Use the native UnixSemaphore APIs
  }
}
```

### Advanced: Lock Identity and Call Tracing
Each lock is uniquely identified by its name, isolate, process, and the specific call frame where the identity was instantiated. This is managed via the `LockIdentity` class and its `CapturedCallFrame`.

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() {
  // Manual identity instantiation
  final identity = LockIdentity.instantiate(name: 'shared_lock');

  print('Lock Name: ${identity.name}');
  print('Isolate ID: ${identity.isolate}');
  print('Process ID: ${identity.process}');
  print('Caller Frame Hash: ${identity.caller}'); // Unique hash for the call site
  print('Combined UUID: ${identity.uuid}');

  // You can pass an identity directly to platform-specific locks
  final winLock = WindowsLock.instantiate(name: 'shared_lock', identity: identity);
}
```

### Introspection and Metrics
The module provides classes to track the number of locks being acquired and released. This can be useful for debugging or monitoring resource usage across your application.

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() {
  final name = 'monitored_lock';
  
  // Direct access to lock counting mechanisms
  final identity = LockIdentity.instantiate(name: name);
  final counter = LockCounter.instantiate(identity: identity);

  // Accessing counts for the current isolate and process
  print('Isolate lock count: ${counter.counts.isolate.counts[name]}');
  print('Process lock count: ${counter.counts.process.counts[name]}');
}
```

## 5. Configuration

There are no configuration files or environment variables required. Fine-tuning is handled directly via arguments to the APIs:
*   **`timeout`**: Configured via `NamedLock.guard(timeout: ...)`. Defaults to 5 seconds. Defines how long the system will poll to acquire the lock before throwing a timeout `Exception`.
*   **`verbose`**: Both `NamedLock.guard` and `ExecutionCall` accept a `verbose: true` argument. This enables detailed console prints detailing locking attempts, sleep intervals, and execution state transitions.
*   **`waiting`**: An optional string passed to `NamedLock.guard(waiting: '...')` that will be printed once if the lock cannot be acquired immediately on the first attempt.

## 6. Related Modules

*   **`runtime_native_semaphores`**: This foundational package provides the underlying `NativeSemaphore`, `UnixSemaphore`, and `WindowsSemaphore` abstractions and FFI bindings that power this module's locking capabilities.
