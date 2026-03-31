# API Reference

A comprehensive guide to the `named_locks` package API, providing detailed information on core execution guards, named semaphore management, and lock identity tracking.

## Table of Contents
1. [Core Execution](#1-core-execution)
   - [ExecutionCall](#executioncall)
   - [ExecutionCallErrors](#executioncallerrors)
   - [CapturedCallFrame](#capturedcallframe)
2. [Named Locks](#2-named-locks)
   - [NamedLock](#namedlock)
   - [UnixLock](#unixlock)
   - [WindowsLock](#windowslock)
3. [Identity & Tracking](#3-identity--tracking)
   - [LockIdentity](#lockidentity)
   - [LockCounter](#lockcounter)
   - [LockCount](#lockcount)
4. [Types & Typedefs](#4-types--typedefs)

---

## 1. Core Execution

### **ExecutionCall<R, E extends Exception>**
A container for a callable block of code that provides built-in mechanisms for error handling, completion tracking, and guarding.

**Fields:**
* `Completer<R> completer`: Tracks the asynchronous completion of the execution.
* `bool safe`: When set to `true`, errors are captured without immediately rethrowing.
* `bool verbose`: Enables detailed internal logging for debugging purposes.
* `R returned`: The value returned by the callable (accessible after completion).
* `({bool isSet, ExecutionCallErrors<R, E>? get}) error`: A record containing captured error details.
* `({bool isSet, bool? get}) successful`: Indicates if the execution finished without errors.
* `({bool isSet, bool? get}) guarded`: Indicates if the execution is currently being managed by a guard.
* `bool guarding`: Internal state flag for the guarding mechanism.

**Methods:**
* `void execute()`: Triggers the execution of the callable. Manages success/failure states and completes the internal `completer`.

**Constructor:**
```dart
ExecutionCall({
  required ExecutionCallType<R, E> callable, 
  bool safe = false, 
  bool verbose = false
})
```

**Example (Using Cascades):**
```dart
final execution = ExecutionCall<int, Exception>(
  callable: () => 42,
)
  ..safe = true
  ..verbose = true;
```

---

### **ExecutionCallErrors<R, E extends Exception>**
Handles the storage and reporting of both anticipated exceptions and unexpected errors caught during an `ExecutionCall`.

**Fields:**
* `({bool isSet, E? get}) anticipated`: The specific exception of type `E` if caught.
* `({bool isSet, Object? get}) unknown`: Any other caught object that does not match type `E`.
* `({bool isSet, StackTrace? get}) trace`: The stack trace associated with the caught error.
* `bool caught`: Returns `true` if any error was captured.

**Methods:**
* `Never rethrow_()`: Rethrows the stored error with its original stack trace.
* `String toString()`: Provides a human-readable summary of the captured errors.

---

### **CapturedCallFrame**
Captures the current stack trace and identifies the caller context.

**Fields:**
* `Trace current`: The `package:stack_trace` representation of the current call stack.
* `String caller`: A unique identifier string derived from the top frames of the stack.

---

## 2. Named Locks

### **NamedLock**
The primary entry point for implementing cross-process or cross-isolate synchronization.

**Methods:**
* `static ExecutionCall<R, E> guard<R, E extends Exception>({ ... })`:
  Wraps an `ExecutionCall` in a named lock. It handles opening, acquiring, releasing, closing, and unlinking the native semaphore.
  * `name`: The unique identifier for the lock.
  * `execution`: The `ExecutionCall` instance to run while the lock is held.
  * `timeout`: Maximum duration to wait for the lock (default: 5 seconds).
  * `waiting`: Optional message to print while waiting for a busy lock.

**Example Usage:**
```dart
final execution = ExecutionCall<void, Exception>(
  callable: () => print('Critical section active'),
);

NamedLock.guard(
  name: 'file_sync_lock',
  execution: execution,
  timeout: Duration(seconds: 10),
  waiting: 'Waiting for file_sync_lock...',
);
```

---

### **UnixLock / WindowsLock**
Platform-specific implementations of the `NativeSemaphore` interface.

**Methods:**
* `static instantiate({required String name, ...})`: Factory method that retrieves an existing lock instance or creates a new one for the respective platform.

---

## 3. Identity & Tracking

### **LockIdentity**
Defines the metadata used to uniquely identify a lock across isolates and processes.

**Fields:**
* `String uuid`: A composite identifier: `name_isolate_process_caller`.
* `String caller`: The resolved caller ID from the captured frame.
* `CapturedCallFrame frame`: The frame captured during identity instantiation.

---

### **LockCounter**
Maintains and groups semaphore counts (metrics) for a specific identity.

**Methods:**
* `static LockCounter instantiate({required I identity})`: Factory to manage shared counter instances.

---

### **LockCount**
Manages the numeric value of a specific semaphore property (e.g., isolate-level or process-level count).

**Methods:**
* `CU update({required int value})`: Updates the current count and returns a transition object.
* `CD delete()`: Clears the count from the registry.

---

## 4. Types & Typedefs

* `ExecutionCallType<R, E extends Exception>`: A function signature `R Function()`.
* `LockType<...>`: A generic alias for `NativeSemaphore` configured with the package's default identity and counter types.
