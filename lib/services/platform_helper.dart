import 'dart:typed_data';
import 'platform_helper_factory.dart' as helper_factory;

/// Interface for platform-specific file operations (Web vs Mobile).
abstract class PlatformHelper {
  static final PlatformHelper instance = helper_factory.getPlatformHelper();

  /// Save and open/download a PDF file.
  Future<void> saveAndOpenPdf(Uint8List bytes, String fileName);

  /// Pick an image file as Base64.
  Future<String?> pickImageAsBase64();
}
