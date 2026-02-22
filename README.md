# runtime_named_locks ⎹ By [Pieces for Developers](https://pieces.app)

[![Native Named Locks](https://github.com/open-runtime/named_locks/actions/workflows/workflow.yaml/badge.svg)](https://github.com/open-runtime/named_locks/actions/workflows/workflow.yaml)

## Overview
This Dart package provides a robust solution for managing execution flow in concurrent Dart applications through named locks, ensuring that critical sections of code are accessed in a controlled manner to prevent race conditions. Leveraging the [runtime_native_semaphores](https://pub.dev/packages/runtime_native_semaphores) package, it utilizes low-level native named semaphores, offering a reliable and efficient locking mechanism right from your Dart/Flutter project. This approach allows for fine-grained control over resource access across multiple isolates, enhancing the safety and performance of your concurrent applications.

## Use Cases
- **Cross-Isolate Synchronization**: Use `NamedLock` to synchronize and coordinate atomic actions such as database writes, file access, or other shared resources across different Dart isolates within the same application.
- **Cross-Process Thread Synchronization**: In applications that span multiple processes (e.g. cooperating AOTs), `NamedLock` can ensure that only one process accesses a critical resource or section of code at a time, preventing race conditions and ensuring data integrity.

## Platform Support
The `runtime_named_locks` package supports the following platforms:
- MacOS (x86_64, arm64)
- Linux (x86_64, arm64)
- Windows (x86_64)

---

## Installation
To add `runtime_named_locks` to your Dart package, include it in your `pubspec.yaml` file:

```yaml
dependencies:
  runtime_named_locks: ^1.0.0-beta.5
```

---

## Getting Started

You'll primarily work with two components: `ExecutionCall` and `NamedLock.guard`.

- **`ExecutionCall<R, E>`** encapsulates a piece of code with its expected return type `R` and anticipated exception type `E`.
- **`NamedLock.guard()`** runs the `ExecutionCall` inside a named lock, ensuring only one isolate or process executes that critical section at a time.

### Basic Example

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() {
  final ExecutionCall<bool, Exception> result = NamedLock.guard(
    name: 'my-shared-resource-lock',
    execution: ExecutionCall<bool, Exception>(
      callable: () {
        // Critical section — only one isolate/process enters at a time
        return true;
      },
    ),
  );

  print(result.returned); // true
}
```

### Multi-Isolate Example

```dart
import 'dart:io' show sleep;
import 'dart:isolate' show Isolate, ReceivePort, SendPort;
import 'dart:math' show Random;

import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() async {
  // Use a fixed, shared name so all isolates synchronize on the same lock
  const String lockName = 'my-shared-resource-lock';

  await Future.wait([
    spawnIsolate(lockName, 1),
    spawnIsolate(lockName, 2),
    spawnIsolate(lockName, 3),
  ]);
}

Future<bool> spawnIsolate(String name, int id) async {
  void isolateEntryPoint(SendPort sendPort) {
    final ExecutionCall<bool, Exception> result = NamedLock.guard(
      name: name,
      execution: ExecutionCall<bool, Exception>(
        callable: () {
          sleep(Duration(milliseconds: Random().nextInt(1000)));
          print('Isolate $id executing critical section');
          return true;
        },
      ),
      waiting: 'Isolate $id is waiting to acquire the lock...',
    );

    sendPort.send(result.returned);
  }

  final receivePort = ReceivePort();
  await Isolate.spawn(isolateEntryPoint, receivePort.sendPort);
  final result = await receivePort.first as bool;
  receivePort.close();
  return result;
}
```

> **Lock name tip**: For cross-process synchronization, use a fixed agreed-upon string. For session-isolated locks (e.g. in tests), generate a unique name with [`safe_int_id`](https://pub.dev/packages/safe_int_id):
> ```dart
> import 'package:safe_int_id/safe_int_id.dart' show safeIntId;
> final name = '${safeIntId.getId()}_my_critical_section';
> ```

---

## Exception Handling

### Unsafe (default) — Exception is rethrown

By default, any exception thrown inside the callable is captured, the lock is released, and then the exception is rethrown immediately:

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

try {
  NamedLock.guard(
    name: 'my-lock',
    execution: ExecutionCall<void, MyException>(
      callable: () => throw MyException('something went wrong'),
    ),
  );
} on MyException catch (e) {
  print('Caught: $e');
}
```

### Safe — Exception is captured for later inspection

Set `safe: true` to suppress the rethrow. Inspect or rethrow the exception later using `execution.error`:

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

final result = NamedLock.guard(
  name: 'my-lock',
  execution: ExecutionCall<void, MyException>(
    callable: () => throw MyException('something went wrong'),
    safe: true,
  ),
);

if (result.error.isSet) {
  print('Anticipated: ${result.error.get?.anticipated.get}');
  print('Trace: ${result.error.get?.trace.get}');

  // Re-throw with original stack trace if needed:
  result.error.get?.rethrow_();
}
```

### Unexpected Exceptions

If the callable throws a type other than `E`, it is captured in `error.get?.unknown`:

```dart
if (result.error.isSet) {
  final anticipated = result.error.get?.anticipated;   // typed E
  final unknown = result.error.get?.unknown;           // anything else
  final trace = result.error.get?.trace;
}
```

---

## Async Callables

The callable may return a `Future<R>`. Use `execution.completer.future` or `await execution.returned` to get the result:

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

Future<void> main() async {
  final result = NamedLock.guard(
    name: 'async-lock',
    execution: ExecutionCall<Future<String>, Exception>(
      callable: () async {
        await Future.delayed(Duration(milliseconds: 100));
        return 'async result';
      },
    ),
  );

  final value = await result.returned;
  print(value); // 'async result'
}
```

---

## API Reference

### `NamedLock.guard<R, E>()`

```dart
static ExecutionCall<R, E> guard<R, E extends Exception>({
  required String name,
  required ExecutionCall<R, E> execution,
  Duration timeout = const Duration(seconds: 5),
  bool verbose = false,
  String? waiting,
})
```

**Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | `String` | required | Unique identifier for the lock. Shared by all isolates/processes that should synchronize. |
| `execution` | `ExecutionCall<R, E>` | required | Encapsulates the callable to run under the lock. |
| `timeout` | `Duration` | 5 seconds | How long to wait for lock acquisition before throwing. |
| `verbose` | `bool` | `false` | Emit debug output during lock acquisition and execution. |
| `waiting` | `String?` | `null` | Message printed once when a lock acquisition attempt is delayed. |

**Returns**: The same `ExecutionCall<R, E>` object, with `returned`, `successful`, and `error` properties populated.

**Throws**: `Exception` if the lock cannot be acquired within `timeout`.

---

### `ExecutionCall<R, E>`

```dart
ExecutionCall<R, E>({
  required ExecutionCallType<R, E> callable,
  bool safe = false,
  bool verbose = false,
})
```

| Property | Type | Description |
|---|---|---|
| `returned` | `R` | The return value of the callable. Throws if accessed before execution completes. |
| `completer` | `Completer<R>` | Use `await completer.future` to wait for async callables. |
| `successful` | `({bool isSet, bool? get})` | Whether execution completed without error. |
| `guarded` | `({bool isSet, bool? get})` | Whether the callable was run inside a `guard()` call. |
| `error` | `({bool isSet, ExecutionCallErrors<R, E>? get})` | Error details if execution threw. |

---

### `ExecutionCallErrors<R, E>`

| Property | Type | Description |
|---|---|---|
| `anticipated` | `({bool isSet, E? get})` | Exception of the declared type `E`, if thrown. |
| `unknown` | `({bool isSet, Object? get})` | Exception of any other type, if thrown. |
| `trace` | `({bool isSet, StackTrace? get})` | Stack trace at the point of the exception. |
| `caught` | `bool` | `true` if any exception was captured. |
| `rethrow_()` | `Future<R>` | Rethrows the captured exception with its original stack trace. |

---

## Troubleshooting

**"NamedLock.guard has failed to acquire lock within..."**
Another isolate or process is holding the lock longer than the `timeout` duration. Either increase `timeout`, reduce critical section duration, or check for deadlocks.

**Application hangs indefinitely**
The same isolate may be trying to acquire a lock it already holds (reentrant deadlock). Named semaphores are not reentrant — do not call `NamedLock.guard()` with the same `name` from within an already-guarded section in the same isolate.

**Debug lock contention**
Pass `verbose: true` to `guard()` and/or a `waiting` message to see acquisition attempts in real time:
```dart
NamedLock.guard(
  name: 'my-lock',
  execution: ExecutionCall(callable: () => doWork()),
  verbose: true,
  waiting: 'Waiting for lock...',
);
```

---

## Motivation
The motivation behind this Dart package stems from the complexities and challenges associated with directly managing low-level native named semaphores, especially in a concurrent programming context. Native named semaphores offer powerful synchronization primitives but working with them directly can be cumbersome and error-prone due to the nuances of semaphore lifecycle management, cross-platform inconsistencies, and the intricacies of ensuring thread safety. This package abstracts these complexities through a higher-level API, providing developers with an intuitive and easy-to-use interface for concurrency management. By encapsulating the low-level operations and handling the subtle nuances of working with native named semaphores, this package allows developers to focus on the logic of their applications, ensuring efficient and safe access to shared resources without getting bogged down by the underlying concurrency mechanisms. This approach not only enhances developer productivity but also improves the reliability and performance of concurrent Dart applications.

## Contributing
We welcome any and all feedback and contributions to the `runtime_named_locks` package. If you encounter any issues, have feature requests, or would like to contribute to the package, please feel free to open an issue or submit a pull request on the [GitHub repository](https://github.com/open-runtime/named_locks).

## License
This is an open-source package developed by the team at [Pieces for Developers](https://pieces.app) and is licensed under the [Apache License 2.0](./LICENSE).
