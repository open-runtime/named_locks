// ignore_for_file: avoid_print

import 'dart:io';

/// Autodoc: API_REFERENCE.md generator for a Dart source module.
///
/// Usage:
///   dart run scripts/prompts/autodoc_api_reference_prompt.dart <module_name> <source_dir> [lib_dir]

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: autodoc_api_reference_prompt.dart <module_name> <source_dir> [lib_dir]',
    );
    exit(1);
  }

  final moduleName = args[0];
  final sourceDir = args[1];

  final dartFiles = _runSync(
    'find $sourceDir -name "*.dart" -not -name "*.g.dart" -not -name "*.pb.dart" -not -name "*.pbenum.dart" -not -name "*.pbjson.dart" -not -name "*.pbgrpc.dart" -type f 2>/dev/null',
  );
  final allDartContent = StringBuffer();
  for (final file in dartFiles.split('\n').where((f) => f.isNotEmpty)) {
    allDartContent.writeln('// === $file ===');
    allDartContent.writeln(_truncate(_runSync('cat "$file"'), 20000));
    allDartContent.writeln();
  }

  final dartContent = _truncate(allDartContent.toString(), 60000);

  print('''
You are a documentation writer generating an API reference for the
**$moduleName** module.

## Source Code

```dart
$dartContent
```

## Instructions

Generate an API_REFERENCE.md with these sections:

### 1. Classes
For EACH public class:
- **ClassName** -- one-line description
  - List key fields with types and descriptions
  - List key methods with signatures and descriptions
  - Note any factory constructors or named constructors

### 2. Enums
For EACH public enum:
- **EnumName** -- what it represents
  - List all values with descriptions

### 3. Extensions
For EACH public extension:
- **ExtensionName** on **TargetType** -- what it adds
  - List methods/getters with descriptions

### 4. Top-Level Functions
For EACH public function:
- **functionName** -- signature and description
  - Parameters and return type

## Rules
- Use ONLY names that appear in the source code above
- Do NOT fabricate fields, methods, or class names
- Group related types together
- Keep descriptions concise but informative

Generate the complete API_REFERENCE.md content.
''');
}

String _runSync(String command) {
  try {
    final result = Process.runSync(
      'sh',
      ['-c', command],
      workingDirectory: Directory.current.path,
    );
    if (result.exitCode == 0) return (result.stdout as String).trim();
    return '';
  } catch (_) {
    return '';
  }
}

String _truncate(String input, int maxChars) {
  if (input.length <= maxChars) return input;
  return '${input.substring(0, maxChars)}\n\n... [TRUNCATED]\n';
}
