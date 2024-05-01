import 'dart:io' show sleep;
import 'dart:isolate' show Isolate, ReceivePort, SendPort;
import 'dart:math' show Random;
import 'package:runtime_named_locks/src/execution_call.dart' show ExecutionCall;
import 'package:runtime_named_locks/src/named_lock.dart' show NamedLock;
import 'package:safe_int_id/safe_int_id.dart' show safeIntId;
import 'package:test/test.dart' show equals, expect, group, test;

void main() {
  group('NativeLock calling [guard] from single and multiple isolates and measuring reentrant behavior.', () {
    test('Reentrant within a single isolate', () async {
      String name = '${safeIntId.getId()}_named_lock';

      int nested_calculation() {
        final ExecutionCall<int, Exception> _execution = NamedLock.guard(
          name: name,
          execution: ExecutionCall<int, Exception>(
            callable: () {
              sleep(Duration(milliseconds: Random().nextInt(5000)));
              return 3 + 4;
            },
          ),
        );

        return _execution.returned;
      }

      final ExecutionCall<int, Exception> execution = NamedLock.guard(
        name: name,
        execution: ExecutionCall<int, Exception>(
          callable: () {
            sleep(Duration(milliseconds: Random().nextInt(2000)));
            return (nested_calculation() * 2) + 5;
          },
        ),
      );

      expect(execution.returned, equals(19));
    });

    test('Reentrant Behavior Across Several Isolates', () async {
      Future<int> spawn_isolate(String name, int id) async {
        // The entry point for the isolate
        void isolate_entrypoint(SendPort sender) {
          final ExecutionCall<int, Exception> _returnable = NamedLock.guard<int, Exception>(
            name: name,
            execution: ExecutionCall<int, Exception>(
              callable: () {
                print("Isolate $id is executing with a guard.");
                sleep(Duration(milliseconds: Random().nextInt(2000)));

                return 2 *
                    (NamedLock.guard<int, Exception>(
                        name: name,
                        execution: ExecutionCall(
                          callable: () {
                            print("Isolate $id with nested guard is executing.");
                            sleep(Duration(milliseconds: Random().nextInt(2000)));
                            return 2;
                          },
                        )).returned);
              },
            ),
          );

          sender.send(_returnable.returned);
        }

        // Create a receive port to get messages from the isolate
        final ReceivePort receiver = ReceivePort();

        // Spawn the isolate
        await Isolate.spawn(isolate_entrypoint, receiver.sendPort);

        // Wait for the isolate to send its message
        return await receiver.first;
      }

      String name = '${safeIntId.getId()}_named_sem';

      final ExecutionCall<Future<int>, Exception> execution = NamedLock.guard(
        name: name,
        execution: ExecutionCall<Future<int>, Exception>(
          callable: () async {
            sleep(Duration(milliseconds: Random().nextInt(2000)));
            final result_one = spawn_isolate(name, 1);
            final result_two = spawn_isolate(name, 2);
            final result_three = spawn_isolate(name, 3);
            final result_four = spawn_isolate(name, 4);
            final outcomes = await Future.wait([result_one, result_two, result_three, result_four]);
            return outcomes.reduce((a, b) => a + b);
          },
        ),
      );

      final returned = await execution.returned;
      expect(returned, equals(16));
    });
  });
}
