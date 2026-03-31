# Named Locks Core - API Reference

The **Named Locks Core** module provides a robust, cross-platform synchronization layer for Dart applications. It enables mutually exclusive access to shared resources across different isolates or processes using native OS-level semaphores.

## 1. Classes

### **NamedLock**
The primary utility class for executing code guarded by a named semaphore. It handles the full lifecycle of the lock, including acquisition with timeout, execution, and automatic cleanup.

#### **Methods**
- `static ExecutionCall<R, E> guard<R, E extends Exception>({required String name, required ExecutionCall<R, E> execution, Duration timeout = const Duration(seconds: 5), bool verbose = false, String? waiting})`
  Creates or retrieves a named lock, attempts to acquire it within the specified `timeout`, executes the `execution` call, and ensures the lock is released, closed, and unlinked.

#### **Code Example**
```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() async {
  final execution = NamedLock.guard<String, Exception>(
    name: 'critical_resource_lock',
    execution: ExecutionCall<String, Exception>(
      callable: () => 'Resource accessed successfully',
    )..verbose = true,
    timeout: const Duration(seconds: 10),
    waiting: 'Waiting for access to critical_resource_lock...',
  );

  final result = await execution.completer.future;
  print(result);
}
```

---

### **ExecutionCall<R, E extends Exception>**
Wraps a functional unit of work to be executed within a guarded context. It manages completion state, return values, and error tracking.

#### **Fields**
- `completer` (`Completer<R>`): The completer used to signal the result or error of the execution.
- `safe` (`bool`): If `true`, the call will capture exceptions without rethrowing them automatically.
- `verbose` (`bool`): Enables detailed logging of the execution lifecycle.
- `returned` (`R`): The value returned by the callable. Accessing this before completion throws a `StateError`.
- `error` (`({bool isSet, ExecutionCallErrors<R, E>? get})`): Details of any captured errors.
- `successful` (`({bool isSet, bool? get})`): Indicates whether the execution finished without errors.
- `guarded` (`({bool isSet, bool? get})`): Status indicating if the call is currently being guarded.

#### **Constructors**
- `ExecutionCall({required ExecutionCallType<R, E> callable, bool safe = false, bool verbose = false})`

#### **Methods**
- `void execute()`: Internally triggered by `NamedLock.guard` to run the wrapped callable and manage its state.

#### **Code Example**
```dart
final call = ExecutionCall<int, FormatException>(
  callable: () => int.parse('42'),
)
  ..safe = true
  ..verbose = false;

// Accessing fields after execution
if (call.successful.get ?? false) {
  print('Result: ${call.returned}');
}
```

---

### **ExecutionCallErrors<R, E extends Exception>**
A container for errors captured during an `ExecutionCall`. It distinguishes between anticipated exceptions of type `E` and unknown errors.

#### **Fields**
- `anticipated` (`({bool isSet, E? get})`): The expected exception if one occurred.
- `unknown` (`({bool isSet, Object? get})`): Any other error caught during execution.
- `trace` (`({bool isSet, StackTrace? get})`): The stack trace associated with the error.
- `caught` (`bool`): Returns `true` if either an anticipated or unknown error is present.

#### **Methods**
- `Never rethrow_()`: Rethrows the captured error with its original stack trace.

#### **Code Example**
```dart
final errors = execution.error.get!;
if (errors.caught) {
  if (errors.anticipated.isSet) {
    print('Caught expected exception: ${errors.anticipated.get}');
  } else {
    errors.rethrow_();
  }
}
```

---

### **UnixLock** / **WindowsLock**
Platform-specific implementations of named semaphores. These are typically managed automatically by `NamedLock.guard` but can be used directly for manual control.

#### **Methods**
- `static instantiate({required String name, bool verbose = false})`: Retrieves an existing lock instance by name or creates a new one if it doesn't exist.
- `bool lock()`: Attempts to acquire the lock. Returns `true` if successful.
- `void unlock()`: Releases the lock.
- `void open()`: Opens the underlying native semaphore.
- `void close()`: Closes the semaphore handle.
- `void unlink()`: Removes the semaphore from the system.

#### **Code Example**
```dart
import 'dart:io';
import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() {
  final name = 'manual_lock';
  final lock = Platform.isWindows 
      ? WindowsLock.instantiate(name: name) 
      : UnixLock.instantiate(name: name);

  lock.open();
  if (lock.lock()) {
    try {
      print('Doing manual work...');
    } finally {
      lock.unlock();
      lock.close();
      lock.unlink();
    }
  }
}
```

---

### **LockIdentity**
Uniquely identifies a lock based on its name, the isolate it resides in, the process ID, and the caller's stack frame.

#### **Fields**
- `name` (`String`): The base name of the lock.
- `uuid` (`String`): A unique string identifying this specific lock instance across the system.
- `caller` (`String`): A hash representing the call site that instantiated the lock.

#### **Methods**
- `static LockIdentity instantiate({required String name})`: Retrieves or creates a `LockIdentity` for the given name.

#### **Code Example**
```dart
final identity = LockIdentity.instantiate(name: 'shared_lock');
print('Unique Lock ID: ${identity.uuid}');
```

---

### **LockIdentities**
A registry for managing `LockIdentity` instances.

#### **Fields**
- `static String prefix`: Global prefix used for lock names (defaults to `'runtime_native_locks'`).

---

### **LockCount**
Tracks numerical semaphore metrics for an identifier.

#### **Fields**
- `identifier` (`String`): The name of the lock being tracked.
- `forProperty` (`String`): The property being tracked (e.g., 'isolate' or 'process').

#### **Methods**
- `LockCountUpdate update({required int value})`: Updates the tracked count and returns an update descriptor.
- `LockCountDeletion delete()`: Removes the count from tracking.

#### **Code Example**
```dart
final counter = LockCount(identifier: 'my_lock', forProperty: 'process');
final update = counter.update(value: 1);
print('Updated count from ${update.from} to ${update.to}');
```

---

### **LockCountUpdate**
Represents a change in a lock count value.

#### **Fields**
- `identifier` (`String`): The lock identifier.
- `from` (`int?`): The previous count value.
- `to` (`int`): The new count value.

---

### **LockCountDeletion**
Represents the removal of a lock count from tracking.

#### **Fields**
- `identifier` (`String`): The lock identifier.
- `at` (`int?`): The final count value before deletion.

---

### **LockCounts**
Container for isolate and process-level lock counts.

#### **Fields**
- `isolate` (`LockCount`): Isolate-specific count.
- `process` (`LockCount`): Process-specific count.

---

### **LockCounter**
High-level tracker for aggregate lock metrics.

#### **Methods**
- `static LockCounter instantiate({required LockIdentity identity})`: Retrieves or creates a counter for the identity.

---

### **LockCounters**
Registry for managing `LockCounter` instances.

---

### **CapturedCallFrame**
Captures stack trace information to identify the origin of a lock request.

#### **Fields**
- `caller` (`String`): Hashed string representation of the caller based on stack frames.

#### **Code Example**
```dart
final frame = CapturedCallFrame();
print('Instantiated by: ${frame.caller}');
```

---

## 2. Enums

*No public enums are defined in this module.*

## 3. Extensions

*No public extensions are defined in this module.*

## 4. Top-Level Functions

*No public top-level functions are defined in this module.*

## 5. Typedefs

### **ExecutionCallType<R, E extends Exception>**
`typedef ExecutionCallType<R, E extends Exception> = R Function();`
Defines the signature for the callable function passed to an `ExecutionCall`.