// ignore_for_file: avoid_print

import 'dart:io';

/// Autodoc: QUICKSTART.md generator for a Dart source module.
///
/// Usage:
///   dart run scripts/prompts/autodoc_quickstart_prompt.dart <module_name> <source_dir> [lib_dir]

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: autodoc_quickstart_prompt.dart <module_name> <source_dir> [lib_dir]',
    );
    exit(1);
  }

  final moduleName = args[0];
  final sourceDir = args[1];
  final libDir = args.length > 2 ? args[2] : '';

  final sourceTree = _runSync(
    'tree $sourceDir -L 3 --dirsfirst 2>/dev/null || find $sourceDir -name "*.dart" | head -30',
  );
  final dartFiles = _runSync('find $sourceDir -name "*.dart" -type f 2>/dev/null');
  final dartCount = _runSync('find $sourceDir -name "*.dart" -type f 2>/dev/null | wc -l');

  final firstDart = _runSync(
    'find $sourceDir -name "*.dart" -not -name "*.g.dart" -not -name "*.pb.dart" -not -name "*.pbenum.dart" -not -name "*.pbjson.dart" -not -name "*.pbgrpc.dart" -type f 2>/dev/null | head -1',
  );
  final dartPreview = firstDart.isNotEmpty
      ? _truncate(_runSync('cat "$firstDart"'), 15000)
      : '(no Dart files)';

  final classes = _runSync(
    'grep -rn "^class\\|^abstract class\\|^mixin\\|^extension" $sourceDir 2>/dev/null | head -30',
  );
  final exports = _runSync(
    'grep -rn "^export" $sourceDir 2>/dev/null | head -20',
  );

  String libTree = '(same as source)';
  if (libDir.isNotEmpty && libDir != sourceDir && Directory(libDir).existsSync()) {
    libTree = _runSync(
      'tree $libDir -L 2 --dirsfirst -I "*.g.dart" 2>/dev/null || echo "(no tree)"',
    );
  }

  print('''
You are a documentation writer for the **$moduleName** module.

Your job is to write a QUICKSTART.md that helps a developer get started
with this module in under 5 minutes.

## Module Structure

### Source Files ($dartCount files)
```
$sourceTree
```

### File List
```
$dartFiles
```

### Library Structure
```
$libTree
```

### Classes and Extensions
```
$classes
```

### Exports
```
$exports
```

## Source Preview (first file)
```dart
$dartPreview
```

## Instructions

Write a QUICKSTART.md with these sections:

### 1. Overview
- What this module does (2-3 sentences)
- What APIs or utilities it provides

### 2. Import
Show the REAL import paths based on the lib directory structure.

### 3. Setup
Show how to instantiate key classes or configure the module.
Use REAL class names from the source code.

### 4. Common Operations
3-5 code examples showing the most useful operations.

### 5. Configuration
Any configuration files, environment variables, or options.

### 6. Related Modules
List any related modules if applicable.

## Rules
- Use ONLY real class/method/field names from the source code
- Do NOT fabricate API names or import paths
- Code examples must be valid Dart that would compile
- Keep it concise -- this is a QUICKSTART, not a full reference

Generate the complete QUICKSTART.md content.
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
    return '(command failed)';
  } catch (_) {
    return '(unavailable)';
  }
}

String _truncate(String input, int maxChars) {
  if (input.length <= maxChars) return input;
  return '${input.substring(0, maxChars)}\n\n... [TRUNCATED: ${input.length - maxChars} chars omitted]\n';
}
