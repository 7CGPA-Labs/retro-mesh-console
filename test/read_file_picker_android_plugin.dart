import 'dart:io';

void main() {
  try {
    final dir = Directory('C:/Users/gagan/AppData/Local/Pub/Cache/hosted/pub.dev/file_picker-11.0.2/android/src/main');
    if (!dir.existsSync()) {
      print('Android folder does not exist!');
      return;
    }
    print('Listing files in android folder... ');
    final files = dir.listSync(recursive: true);
    for (final f in files) {
      if (f is File && (f.path.endsWith('.kt') || f.path.endsWith('.java'))) {
        print('File: ${f.path}');
        // Print the first 20 lines of the file to see the package and class name
        final content = f.readAsLinesSync().take(20).join('\n');
        print('--- content ---\n$content\n--- end ---');
      }
    }
  } catch (e) {
    print('Failed to list files: $e');
  }
}
