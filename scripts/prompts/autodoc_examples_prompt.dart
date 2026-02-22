// ignore_for_file: avoid_print

import 'dart:io';

/// Autodoc: EXAMPLES.md generator for a Dart source module.
///
/// Usage:
///   dart run scripts/prompts/autodoc_examples_prompt.dart <module_name> <source_dir> [lib_dir]

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: autodoc_examples_prompt.dart <module_name> <source_dir> [lib_dir]',
    );
    exit(1);
  }

  final moduleName = args[0];
  final sourceDir = args[1];
  final libDir = args.length > 2 ? args[2] : '';

  final classes = _runSync(
    'grep -rn "^class\\|^abstract class\\|^mixin" $sourceDir 2>/dev/null | head -30',
  );
  final methods = _runSync(
    'grep -rn "Future<\\|Stream<\\|void " $sourceDir 2>/dev/null | grep -v "^\\/\\/" | head -30',
  );
  final enums = _runSync(
    'grep -rn "^enum" $sourceDir 2>/dev/null',
  );

  String testContent = '(no tests found)';
  final testDir = libDir.isNotEmpty ? libDir.replaceFirst('lib/', 'test/') : '';
  if (testDir.isNotEmpty && Directory(testDir).existsSync()) {
    testContent = _truncate(
      _runSync(
        'find $testDir -name "*_test.dart" -exec head -50 {} \\; 2>/dev/null',
      ),
      10000,
    );
  }

  final commands = _runSync(
    'grep -rn "extends Command" $sourceDir 2>/dev/null | head -20',
  );

  print('''
You are writing practical code examples for the **$moduleName** module.

## Classes
```
$classes
```

## Key Methods
```
$methods
```

## Enums
```
$enums
```

## CLI Commands
```
$commands
```

${testContent != '(no tests found)' ? '## Existing Test Patterns\n```dart\n$testContent\n```' : ''}

## Instructions

Generate an EXAMPLES.md with practical, copy-paste-ready examples:

### 1. Basic Usage
- Instantiate key classes
- Call important methods
- Show builder/configuration patterns

### 2. Common Workflows
- Typical end-to-end usage patterns
- Integration with other components

### 3. Error Handling
- Common error patterns and how to handle them

### 4. Advanced Usage
- Less common but powerful patterns

## Rules
- Use ONLY real class/method names from the source code
- Every code block must be valid, compilable Dart
- Show complete, runnable examples (not fragments)
- Include comments explaining what each step does

Generate the complete EXAMPLES.md content.
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
