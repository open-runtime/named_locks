# Named Locks Core Examples

This document provides practical, copy-paste-ready examples for using the **Named Locks** package. It covers basic usage, common workflows, error handling, and advanced topics.

## 1. Basic Usage

### Using `NamedLock.guard`

The most common and safest way to synchronize execution using a named lock is via `NamedLock.guard`. It handles acquiring the lock, executing your code, and cleaning up the lock automatically.

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() {
  // 1. Define the execution call with your synchronized work
  final execution = ExecutionCall<String, Exception>(
    callable: () {
      // This block executes while the cross-process lock is safely held
      print('Lock acquired. Doing synchronized work...');
      return 'Success!';
    },
  );

  // 2. Guard the execution call with a unique lock name
  final resultCall = NamedLock.guard<String, Exception>(
    name: 'my_first_named_lock',
    execution: execution,
    timeout: const Duration(seconds: 5),
    waiting: 'Waiting for another process to release the lock...',
    verbose: true, // Optional: Enables detailed logging of the lock lifecycle
  );

  // 3. Retrieve the synchronous result
  // If an error occurred and safe was false, this line won't be reached
  print('Result: ${resultCall.returned}');
  
  // You can also check if the execution was successful
  if (resultCall.successful.isSet && resultCall.successful.get == true) {
    print('Execution completed successfully.');
  }
}
```

## 2. Common Workflows

### Asynchronous Operations within a Lock

If your synchronized work returns a `Future`, `ExecutionCall` transparently handles the execution. You can `await` the returned future inside `resultCall.returned`. 

> **Note:** When guarding a `Future`, `NamedLock.guard` will release the lock as soon as the synchronous part of the `callable` completes. If you need to hold the lock until the `Future` completes, ensure you are using a synchronous wrapper or that the work being performed doesn't require the lock to be held across the async gap.

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

Future<void> main() async {
  // Define an execution call that returns a Future
  final execution = ExecutionCall<Future<String>, Exception>(
    callable: () async {
      print('Doing async work...');
      await Future<void>.delayed(const Duration(seconds: 1));
      return 'Async Success!';
    },
  );

  // Guard handles the entire execution internally
  final resultCall = NamedLock.guard<Future<String>, Exception>(
    name: 'my_async_lock',
    execution: execution,
  );

  // Await the future returned by the execution call
  final value = await resultCall.returned;
  print('Async Result: $value');
}
```

## 3. Error Handling

### Catching and Inspecting Errors

By default, `NamedLock.guard` will automatically rethrow exceptions that occur inside the guarded block. If you want to handle them gracefully, you can set `safe: true` on your `ExecutionCall` and inspect the `ExecutionCallErrors`.

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() {
  final execution = ExecutionCall<void, FormatException>(
    callable: () {
      // Simulate an error occurring within the guarded block
      throw FormatException('Invalid data format!');
    },
    safe: true, // Prevents NamedLock.guard from automatically rethrowing
  );

  final resultCall = NamedLock.guard<void, FormatException>(
    name: 'safe_error_lock',
    execution: execution,
  );

  // Check if an error occurred during execution
  if (resultCall.error.isSet) {
    final ExecutionCallErrors<void, FormatException> errors = resultCall.error.get!;
    
    // Check if it's the anticipated exception type (FormatException)
    if (errors.anticipated.isSet) {
      print('Caught anticipated error: ${errors.anticipated.get}');
    } 
    // Check if it's an unknown error (any other Exception or Error)
    else if (errors.unknown.isSet) {
      print('Caught unknown error: ${errors.unknown.get}');
    }
    
    // You can also inspect the stack trace if it was captured
    if (errors.trace.isSet) {
      print('Stack trace: ${errors.trace.get}');
    }
    
    // You can manually rethrow the stored error if needed:
    // errors.rethrow_();
  }
}
```

## 4. Advanced Usage

### Working with Lock Identities and Call Frames

`LockIdentity` captures information about the caller, isolate, and process, providing detailed diagnostics. `CapturedCallFrame` maintains the stack trace of where the lock was initialized.

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() {
  // LockIdentities keeps a registry of all LockIdentity instances
  final identity = LockIdentity.instantiate<LockIdentity, LockIdentities<LockIdentity>>(
    name: 'shared_resource_identity'
  );
  
  print('Identity Name: ${identity.name}');
  print('Process ID: ${identity.process}');
  print('Isolate ID: ${identity.isolate}');
  print('Unique UUID: ${identity.uuid}');
  
  // A CapturedCallFrame is automatically created inside LockIdentity
  // which records the stack trace of the call
  final CapturedCallFrame frame = identity.frame;
  print('Call frame caller hash: ${frame.caller}');
  
  // You can also access the full stack trace via the current property
  print('Full stack trace at initialization: ${frame.current}');
}
```

### Manual Platform Lock Lifecycle

For highly specialized scenarios, you can manually instantiate `UnixLock` or `WindowsLock` and interact with `NamedLocks` as a type bound.

```dart
import 'dart:io';
import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() {
  final lockName = 'advanced_metrics_lock';
  
  // Manually build an identity
  final identity = LockIdentity.instantiate<LockIdentity, LockIdentities<LockIdentity>>(name: lockName);

  // Counters keep track of internal lock acquisition metrics.
  final counter = LockCounter.instantiate(identity: identity);
  
  // Platform specific lock with custom counters
  final lock = Platform.isWindows
    ? WindowsLock.instantiate(name: lockName, identity: identity, counter: counter, verbose: true)
    : UnixLock.instantiate(name: lockName, identity: identity, counter: counter, verbose: true);

  // 1. Open the semaphore
  if (!lock.opened) {
    lock.open();
  }

  // 2. Attempt to lock
  final locked = lock.lock();
  
  if (locked) {
    try {
      print('Lock manually acquired for manual lifecycle management.');
      // The overall generic NamedLocks type serves as the registry for both UnixLock and WindowsLock
    } finally {
      // 3. Always ensure the lock is unlocked, closed, and unlinked
      lock.unlock();
      lock.close();
      lock.unlink();
      print('Lock successfully cleaned up.');
    }
  } else {
    print('Failed to acquire the lock.');
  }
}
```

### Inspecting Counters and Metrics

You can inspect the deeply typed registry counters to manage advanced multi-isolate metrics. `LockCounters` serves as the registry for multiple `LockCounter` instances.

```dart
import 'package:runtime_named_locks/runtime_named_locks.dart';

void main() {
  final identity = LockIdentity.instantiate<LockIdentity, LockIdentities<LockIdentity>>(
    name: 'internal_counters'
  );
  
  final counter = LockCounter.instantiate(identity: identity);
  
  // Accessing the underlying LockCounts for this specific LockCounter
  final LockCounts counts = counter.counts;
  
  // Check the individual LockCount properties created for isolates and processes
  final LockCount isolateCount = counts.isolate;
  final LockCount processCount = counts.process;
  
  print('Tracking isolate count for property: ${isolateCount.forProperty}');
  print('Lock identifier: ${isolateCount.identifier}');
  
  // Manually updating and inspecting the metrics using LockCountUpdate and LockCountDeletion
  final LockCountUpdate update = isolateCount.update(value: 5);
  print('Updated count from: ${update.from} to: ${update.to}');
  
  final LockCountDeletion deletion = isolateCount.delete();
  print('Count deleted, final count was: ${deletion.at}');
}
```