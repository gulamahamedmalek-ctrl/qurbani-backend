import 'dart:convert';
import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'package:image_picker/image_picker.dart';
import 'platform_helper.dart';

class PlatformHelperImpl implements PlatformHelper {
  @override
  Future<void> saveAndOpenPdf(Uint8List bytes, String fileName) async {
    // On mobile, we use the printing package to share/save the PDF
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  @override
  Future<String?> pickImageAsBase64() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image == null) return null;
    
    final bytes = await image.readAsBytes();
    final String base64Image = base64Encode(bytes);
    final String extension = image.path.split('.').last.toLowerCase();
    
    return 'data:image/$extension;base64,$base64Image';
  }
}

PlatformHelper getPlatformHelper() => PlatformHelperImpl();
