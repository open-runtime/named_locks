# runtime_named_locks ⎹ By [Pieces for Developers](https://pieces.app)

[![Native Named Locks](https://github.com/open-runtime/named_locks/actions/workflows/workflow.yaml/badge.svg)](https://github.com/open-runtime/named_locks/actions/workflows/workflow.yaml)

## Overview
This Dart package provides a robust solution for managing execution flow in concurrent Dart applications through named locks, ensuring that critical sections of code are accessed in a controlled manner to prevent race conditions. Leveraging the [runtime_native_semaphore](https://pub.dev/packages/runtime_native_semaphores) package, it utilizes low-level native named semaphores, offering a reliable and efficient locking mechanism right from your Dart/Flutter Project. This approach allows for fine-grained control over resource access across multiple isolates, enhancing the safety and performance of your concurrent applications.

## Use Cases
- **Cross-Isolate Synchronization**: Use NamedLocks to synchronize and coordinate atomic actions such as database writes, file access, or other shared resources across different Dart isolates within the same application.
- **Cross-Process Thread Synchronization**: In applications that span multiple processes i.e. cooperating AOTs, NamedLocks can ensure that only one process accesses a critical resource/section of code at a time, preventing race conditions and ensuring data integrity.

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
  runtime_named_locks: ^1.0.0-beta.3
```

## Getting Started
To get started with this Dart package, you'll primarily work with two key components: `ExecutionCall` and the `NamedLock.guard` static function. `ExecutionCall` allows you to encapsulate the execution of a piece of code along with its expected return and exception types, providing a structured way to handle both success and failure scenarios.

### Using a NamedLock to Guard a Critical Section of Code Executed by Multiple Isolates or Processes
The following example demonstrates how to use a `NamedLock` to guard a "critical" section of code that is executed by multiple isolates or processes. The `NamedLock.guard` method ensures that the code block is executed in a 'ATOMIC' thread/process-safe manner and is robustly protected by a lower-level native named semaphores under the hood.  

```dart
import 'dart:isolate';
import 'package:runtime_native_semaphores/runtime_native_semaphores.dart' show NativeSemaphore;

void main() {
  // Create a unique identifier for the semaphore 
  // I's suggest using an safe integer identifier from 
  // [safe_int_id](https://pub.dev/packages/safe_int_id)
  final String name = 'my-named-lock-identifier';
  
  spawnIsolate(name, 1);
  spawnIsolate(name, 2);
  // Add more isolates as needed
}

Future<void> spawnIsolate(String name, int isolate) async {
  void isolateEntryPoint(SendPort sendPort) {
    String name = '${safeIntId.getId()}_named_lock';

    final ExecutionCall<bool, Exception> _execution = NamedLock.guard(
      name: name,
      execution: ExecutionCall<bool, Exception>(
        callable: () {
          sleep(Duration(milliseconds: Random().nextInt(5000)));
          return true;
        },
      ),
    );

    sendPort.send(_execution.returned);
  }

  final receivePort = ReceivePort();
  await Isolate.spawn(isolateEntryPoint, receivePort.sendPort);
  await receivePort.first;
  //...
  
  // Cleanup
  receivePort.close();
    
}
```

## **_API Reference:_**
### **Main Class**
- **NamedLock**: Manages named locks using low-level native named semaphores to ensure thread-safe execution of code blocks across multiple isolates.

### **Methods**:
#### **Guard**
- **static ExecutionCall<T, E> guard<T, E>({required String name, required ExecutionCall<T, E> execution})**: Ensures that the code block encapsulated by `ExecutionCall` is executed in a thread-safe manner, protected by a named lock to prevent race conditions.
    - **Parameters**:
        - **name**: A `String` representing the unique name of the lock.
        - **execution**: An `ExecutionCall<R, E extends Exception>` object that encapsulates the code block to be executed safely under the named lock.
            - **R**: The return type of the code block.
            - **E**: The type of exception that may be thrown during execution.
        - **callable**: A `ExecutionCallType<R, E extends Exception> = R Function()` callback that contains the code block to be executed within the named lock.
        - **safe** (optional): A `bool` flag indicating whether the execution should handle exceptions internally. If set to `true`, the `ExecutionCall` object will capture and store any exceptions thrown during execution otherwise the exception will be rethrown to the outer scope.
    - **Returns**: An `ExecutionCall<R, E extends Exception>` object containing the result or the caught exception of the execution. This method ensures thread-safe execution using the named lock mechanism.

### **Properties**:
- **ExecutionCall Properties**:
    - **successful**: A record `({bool isSet, bool? get})` indicating whether the execution within the guard was successful. The `successful.get` field indicates whether the execution was successful, while `successful.isSet` indicates whether the property has been set.
    - **error**: A record `({bool isSet, ExecutionCallErrors<R, E>? get})` that encapsulates detailed information about the execution failure, if any. This record includes:
        - **anticipated**: An optional record field `({bool isSet, E? get})` that holds the expected exception if the execution fails.
        - **unknown**: An optional record field `({bool isSet, E? get})` that may contain an unexpected exception, distinct from the anticipated type.
        - **trace**: A optional record field `({bool isSet, StackTrace? get})` providing the stack trace associated with the exception.
    - **returned**: The result of the execution if it completes successfully. This is of type `R`, as specified in the `ExecutionCall`.
    - **completer**: A `Completer<R>` object that can be used to manage the completion of the execution and await the result of asynchronous `callable` callbacks.

### **Error Handling**:
- The `error` property of `ExecutionCall` is a record type that provides a structured way to access information about exceptions that may occur during execution. It allows for differentiated handling of anticipated exceptions versus unexpected ones, and it includes the stack trace for in-depth debugging. The `rethrow_` method can be used to rethrow the caught exception, facilitating flexible error handling strategies.

--- 

## Motivation
The motivation behind this Dart package stems from the complexities and challenges associated with directly managing low-level native named semaphores, especially in a concurrent programming context. Native named semaphores offer powerful synchronization primitives but working with them directly can be cumbersome and error-prone due to the nuances of semaphore lifecycle management, cross-platform inconsistencies, and the intricacies of ensuring thread safety. Our package abstracts these complexities through a higher-level API, providing developers with an intuitive and easy-to-use interface for concurrency management. By encapsulating the low-level operations and handling the subtle nuances of working with native named semaphores, our package allows developers to focus on the logic of their applications, ensuring efficient and safe access to shared resources without getting bogged down by the underlying concurrency mechanisms. This approach not only enhances developer productivity but also improves the reliability and performance of concurrent Dart applications. Further, this `runtime_named_locks` package services the demand for efficient, reliable inter-process communication (IPC) mechanisms in high-performance software, specifically within the projects like the [DCLI](https://pub.dev/packages/dcli) framework and the [Pieces for Developers | Flutter Desktop App](https://pieces.app) while being easy to consume and integrate into existing codebases.

## Contributing
We welcome any and all feedback and contributions to the `runtime_named_locks` package. If you encounter any issues, have feature requests, or would like to contribute to the
package, please feel free to open an issue or submit a pull request on the [GitHub repository](https://github.com/open-runtime/named_locks).

## License
This is an open-source package developed by the team at [Pieces for Developers](https://pieces.app) and is licensed under the [Apache License 2.0](./LICENSE).

