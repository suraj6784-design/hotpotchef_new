// lib/widgets/avatar_upload.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/app_theme.dart';

class AvatarUploadWidget extends StatefulWidget {
  final String? initialAvatarUrl;
  final Function(String) onUploadComplete;
  final bool isEditing;

  const AvatarUploadWidget({
    super.key,
    this.initialAvatarUrl,
    required this.onUploadComplete,
    this.isEditing = true,
  });

  @override
  State<AvatarUploadWidget> createState() => _AvatarUploadWidgetState();
}

class _AvatarUploadWidgetState extends State<AvatarUploadWidget> {
  final _supabase = Supabase.instance.client;
  bool _isUploading = false;
  String? _currentAvatarUrl;

  @override
  void initState() {
    super.initState();
    _currentAvatarUrl = widget.initialAvatarUrl;
  }

  @override
  void didUpdateWidget(AvatarUploadWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialAvatarUrl != widget.initialAvatarUrl) {
      _currentAvatarUrl = widget.initialAvatarUrl;
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 800,
    );
    if (image == null) return;

    if (!mounted) return;
    setState(() => _isUploading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('User session expired. Please log in again.');

      final file = File(image.path);
      final fileExt = image.path.split('.').last.toLowerCase();
      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      // 1. Upload new avatar to Supabase Storage
      await _supabase.storage.from('avatars').upload(
            fileName,
            file,
            fileOptions: const FileOptions(upsert: true),
          );

      // 2. Retrieve public URL
      final imageUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);

      // 3. Update user profile record
      await _supabase.from('users').update({
        'avatar_url': imageUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id);

      if (!mounted) return;

      setState(() => _currentAvatarUrl = imageUrl);
      widget.onUploadComplete(imageUrl);
      _showSnackBar('Profile photo updated successfully!', isError: false);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Avatar upload failure');
      if (kDebugMode) debugPrint('Avatar upload error: $e');
      _showSnackBar('Upload failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showSnackBar(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showFullScreenImageViewer() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _currentAvatarUrl != null && _currentAvatarUrl!.isNotEmpty
                ? Image.network(
                    _currentAvatarUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey.shade800,
                      width: 300,
                      height: 300,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image, size: 80, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('Failed to load image', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  )
                : Container(
                    color: Colors.grey.shade300,
                    width: 300,
                    height: 300,
                    child: const Icon(Icons.person, size: 150, color: Colors.grey),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (widget.isEditing) {
          if (!_isUploading) _pickAndUploadImage();
        } else {
          _showFullScreenImageViewer();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey.shade300,
            backgroundImage: _currentAvatarUrl != null && _currentAvatarUrl!.isNotEmpty
                ? NetworkImage(_currentAvatarUrl!)
                : null,
            child: (_currentAvatarUrl == null || _currentAvatarUrl!.isEmpty) && !_isUploading
                ? const Icon(Icons.person, size: 50, color: Colors.grey)
                : null,
          ),
          if (_isUploading)
            const CircularProgressIndicator(color: AppTheme.primary),
          if (widget.isEditing && !_isUploading)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
              ),
            ),
        ],
      ),
    );
  }
}