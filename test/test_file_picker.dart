import 'package:file_picker/file_picker.dart';

void main() {
  try {
    print('Testing FilePicker class... ');
    final platformInstance = FilePicker.platform;
    print('Successfully resolved FilePicker.platform: $platformInstance');
  } catch (e) {
    print('Failed to resolve FilePicker.platform: $e');
  }
}
