import 'package:stack_trace/stack_trace.dart';

void logDebug(String message) {
  final frame = Trace.current().frames[1]; // Get caller frame
  print("[${frame.member}] $message");
}
