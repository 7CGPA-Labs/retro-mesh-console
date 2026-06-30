import 'dart:convert';
import 'dart:io';

void main() {
  try {
    final file = File('.dart_tool/package_config.json');
    final json = jsonDecode(file.readAsStringSync());
    final packages = json['packages'] as List;
    final filePicker = packages.firstWhere((p) => p['name'] == 'file_picker');
    print('FilePicker Package Path: ${filePicker['rootUri']}');
  } catch (e) {
    print('Failed to read config: $e');
  }
}
