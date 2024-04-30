import 'package:stack_trace/stack_trace.dart' show Trace;

typedef CaptureCallFrameResult = String;

class CapturedCallFrame {
  final Trace current = Trace.current(0);

  late final String caller = current.frames.take(5).map((e) => e.uri.hashCode).join("_");

  CapturedCallFrame();
}
