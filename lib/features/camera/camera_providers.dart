import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

final imagePickerProvider = Provider<ImagePicker>((ref) => ImagePicker());

class PickedImageNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? path) => state = path;
}

final pickedImagePathProvider = NotifierProvider<PickedImageNotifier, String?>(
    PickedImageNotifier.new);