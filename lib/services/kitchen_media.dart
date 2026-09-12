import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/app_theme.dart';
import '../widgets/app_widgets.dart';

const kKitchenPhotoChecklist = <String>[
  'Bright natural light — avoid heavy filters',
  'Plated food or a clean kitchen counter',
  'No children’s faces or private papers in frame',
  'Fill the frame; one hero dish works best',
  'Fresh kitchen shots show as FRESH for 4 hours',
];

/// Brand photography tips before camera/gallery.
Future<void> showKitchenPhotoChecklist(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: AppTheme.bottomSheetDecoration(isDark: isDark),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Kitchen photo checklist',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.onSurfaceOf(context),
            ),
          ).popIn(),
          const SizedBox(height: 8),
          Text(
            'Good photos build diner trust. Use these before you shoot.',
            style: AppTheme.metaOf(context),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < kKitchenPhotoChecklist.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      kKitchenPhotoChecklist[i],
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurfaceOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ).entrance(index: i),
          const SizedBox(height: 8),
          Semantics(
            button: true,
            label: 'Got it',
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it'),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<ImageSource?> pickKitchenImageSource(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return Container(
        decoration: AppTheme.bottomSheetDecoration(isDark: isDark),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Good light, plated food or clean counter, no faces of kids. Fresh photos show as FRESH for 4 hours.',
                      style: TextStyle(fontSize: 12, height: 1.35, color: AppTheme.textMuted),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          showKitchenPhotoChecklist(context);
                        },
                        child: const Text('Full photo checklist'),
                      ),
                    ),
                  ],
                ),
              ),
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
    },
  );
}

class UploadedKitchenImage {
  const UploadedKitchenImage({required this.url, required this.localPath});

  final String url;
  final String localPath;
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
  return (await pickAndUploadKitchenImage(source: source, folder: folder, fileKey: fileKey))?.url;
}

Future<UploadedKitchenImage?> pickAndUploadKitchenImage({
  ImageSource source = ImageSource.camera,
  String folder = 'kitchen',
  String? fileKey,
}) async {
  final picker = ImagePicker();
  final image = await picker.pickImage(
    source: source,
    imageQuality: 72,
    maxWidth: 1600,
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
    return UploadedKitchenImage(
      url: Supabase.instance.client.storage.from('meal_images').getPublicUrl(path),
      localPath: image.path,
    );
  } catch (e, stack) {
    FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Kitchen photo upload failed on meal_images');
    await Supabase.instance.client.storage.from('avatars').upload(
          path.replaceAll('/', '_'),
          file,
          fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
        );
    return UploadedKitchenImage(
      url: Supabase.instance.client.storage.from('avatars').getPublicUrl(path.replaceAll('/', '_')),
      localPath: image.path,
    );
  }
}

const int kAdCampaignMaxAssetBytes = 15 * 1024 * 1024;

/// Ops upload for brand stills / short clips. Prefers the `ad_campaigns` bucket.
Future<String> uploadAdCampaignAsset({
  required String campaignId,
  required String filePath,
  required String contentType,
}) async {
  final file = File(filePath);
  final size = await file.length();
  if (size > kAdCampaignMaxAssetBytes) {
    throw Exception('Keep photos and clips under 15 MB (about 15–30 seconds of video).');
  }
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) throw Exception('Sign in as platform ops to upload ads.');

  final ext = filePath.split('.').last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final safeExt = ext.isEmpty ? 'bin' : ext;
  final name = DateTime.now().millisecondsSinceEpoch.toString();
  final path = '$campaignId/$name.$safeExt';

  try {
    await Supabase.instance.client.storage.from('ad_campaigns').upload(
          path,
          file,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return Supabase.instance.client.storage.from('ad_campaigns').getPublicUrl(path);
  } catch (e, stack) {
    FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Ad campaign upload failed on ad_campaigns');
    final fallback = 'ads/${user.id}/$path';
    await Supabase.instance.client.storage.from('meal_images').upload(
          fallback,
          file,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return Supabase.instance.client.storage.from('meal_images').getPublicUrl(fallback);
  }
}
