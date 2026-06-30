import 'dart:io';

void main() {
  try {
    final file = File('C:/Users/gagan/AppData/Local/Pub/Cache/hosted/pub.dev/file_picker-11.0.2/lib/src/file_picker.dart');
    if (!file.existsSync()) {
      print('File does not exist!');
      return;
    }
    final lines = file.readAsLinesSync();
    print('Total lines: ${lines.length}');
    
    bool insideClass = false;
    int linesPrinted = 0;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('abstract class FilePicker') || line.contains('class FilePicker')) {
        insideClass = true;
      }
      if (insideClass) {
        print('${i + 1}: $line');
        linesPrinted++;
        if (linesPrinted > 60) break;
      }
    }
  } catch (e) {
    print('Failed to read src: $e');
  }
}
