import 'package:flutter/services.dart';

// Save-to-Photos bridge (1.20.9): the native side (AppDelegate,
// channel minix/media) writes a copy of a gallery file into the iOS
// photo library under add-only authorization. The original file in
// app storage is never touched.
class MediaSaveService {
  static const MethodChannel _channel = MethodChannel('minix/media');

  // Returns null on success, or a user-facing error line.
  static Future<String?> saveToPhotos(String path,
      {required bool isVideo}) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
          'saveToPhotos', {'path': path, 'isVideo': isVideo});
      return ok == true ? null : 'Could not save to Photos.';
    } on PlatformException catch (e) {
      if (e.code == 'denied') {
        return 'Photo access is off. Enable it in Settings to save.';
      }
      return 'Could not save to Photos.';
    } catch (_) {
      return 'Could not save to Photos.';
    }
  }
}
