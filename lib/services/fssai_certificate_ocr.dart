import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../utils/fssai_certificate_scan.dart';

/// On-device OCR of an FSSAI licence photo. Returns an empty scan if the plugin fails.
Future<FssaiCertificateScan> scanFssaiCertificateImage(String imagePath) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
    return parseFssaiCertificateText(result.text);
  } catch (e, stack) {
    FirebaseCrashlytics.instance.recordError(e, stack, reason: 'FSSAI certificate OCR failed');
    return const FssaiCertificateScan();
  } finally {
    await recognizer.close();
  }
}
