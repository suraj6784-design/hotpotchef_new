import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

Future<ImageSource?> pickKitchenImageSource(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a kitchen photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}

Future<String?> capturePackedBoxPhoto({required String orderId}) {
  return uploadKitchenImage(
    source: ImageSource.camera,
    folder: 'dispatch',
    fileKey: orderId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), ''),
  );
}

Future<String?> uploadKitchenImage({
  ImageSource source = ImageSource.camera,
  String folder = 'kitchen',
  String? fileKey,
}) async {
  final picker = ImagePicker();
  final image = await picker.pickImage(
    source: source,
    imageQuality: 72,
    maxWidth: 1200,
  );
  if (image == null) return null;

  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) throw Exception('Sign in as the kitchen to post a photo.');

  final ext = image.path.split('.').last.toLowerCase();
  final name = (fileKey == null || fileKey.isEmpty)
      ? DateTime.now().millisecondsSinceEpoch.toString()
      : '$fileKey-${DateTime.now().millisecondsSinceEpoch}';
  final path = '$folder/${user.id}/$name.$ext';
  final file = File(image.path);

  try {
    await Supabase.instance.client.storage.from('meal_images').upload(
          path,
          file,
          fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
        );
    return Supabase.instance.client.storage.from('meal_images').getPublicUrl(path);
  } catch (e, stack) {
    FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Kitchen photo upload failed on meal_images');
    await Supabase.instance.client.storage.from('avatars').upload(
          path.replaceAll('/', '_'),
          file,
          fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
        );
    return Supabase.instance.client.storage.from('avatars').getPublicUrl(path.replaceAll('/', '_'));
  }
}
