# runtime_named_locks ⎹ By [Pieces for Developers](https://pieces.app)

[TODO Status Badge Here]()

## Overview
TODO

## Use Cases
- **Cross-Isolate Synchronization**: Use named semaphores to synchronize and coordinate atomic actions such as database writes, file access, or other shared resources across different Dart isolates within the same application.
- **Cross-Process Thread Synchronization**: In applications that span multiple processes i.e. cooperating AOTs, named semaphores can ensure that only one process accesses a critical resource/section of code at a time, preventing race conditions and ensuring data integrity.

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
  runtime_native_semaphores: ^1.0.0-beta.1
```

## Getting Started
TODO

### Using a NamedLock to Guard a Critical Section of Code Executed by Multiple Isolates or Processes
TODO 

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
- TODO NamedLock
- TODO ExecutionCall

### **Methods**:
#### **Guard**
- TODO NamedLock.guard

### **Properties**:
- TODO ExecutionCall.returned
- TODO ExecutionCall.error
- TODO ExecutionCall.completer
- TODO ExecutionCall.successful

--- 

## Native Implementation Details & References

### Unix Implementation
TODO Notes

### Windows Implementation
TODO Notes

--- 

## Motivation
TODO Notes 

## Contributing
We welcome any and all feedback and contributions to the `runtime_named_locks` package. If you encounter any issues, have feature requests, or would like to contribute to the
package, please feel free to open an issue or submit a pull request on the [GitHub repository](https://github.com/open-runtime/named_locks).

## License
This is an open-source package developed by the team at [Pieces for Developers](https://pieces.app) and is licensed under the [Apache License 2.0](./LICENSE).

