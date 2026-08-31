// lib/screens/driver_id_card_screen.dart

import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/app_theme.dart';

class DriverIdCardScreen extends StatefulWidget {
  final String driverName;
  final String driverPhone;
  final String? avatarUrl;

  const DriverIdCardScreen({
    super.key,
    required this.driverName,
    required this.driverPhone,
    this.avatarUrl,
  });

  @override
  State<DriverIdCardScreen> createState() => _DriverIdCardScreenState();
}

class _DriverIdCardScreenState extends State<DriverIdCardScreen> {
  final GlobalKey _cardKey = GlobalKey();
  bool _isSaving = false;

  Future<void> _downloadAndShareId() async {
    final contextRef = _cardKey.currentContext;
    if (contextRef == null) {
      _showSnackBar('Card layout not ready. Please try again.', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Safely acquire render object boundary
      final boundary = contextRef.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Could not resolve card render boundary.');
      }

      // Dynamic pixel ratio based on device screen density
      final pixelRatio = MediaQuery.of(context).devicePixelRatio.clamp(2.0, 3.5);
      ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();

      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to encode card image data.');
      }

      final directory = await getTemporaryDirectory();
      final imagePath = File('${directory.path}/HotPotChef_Driver_ID_${DateTime.now().millisecondsSinceEpoch}.png');
      await imagePath.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(imagePath.path)],
        text: 'My HotPotChef Verified Delivery Partner ID',
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Driver ID Card export failure');
      _showSnackBar('Failed to save ID: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Digital ID Card', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // RepaintBoundary wrapper for clean canvas export
              RepaintBoundary(
                key: _cardKey,
                child: Container(
                  width: 300,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Column(
                          children: [
                            Image.asset(
                              'assets/app_icon.png',
                              height: 40,
                              width: 40,
                              errorBuilder: (c, e, s) => const Icon(Icons.delivery_dining, color: Colors.white, size: 40),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'HOTPOTCHEF',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                                fontSize: 16,
                              ),
                            ),
                            const Text(
                              'VERIFIED DELIVERY PARTNER',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Avatar Photo with network caching & error fallback
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.primary, width: 3),
                        ),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey.shade300,
                          backgroundImage: widget.avatarUrl != null ? NetworkImage(widget.avatarUrl!) : null,
                          child: widget.avatarUrl == null
                              ? const Icon(Icons.person, size: 50, color: Colors.grey)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Driver Details
                      Text(
                        widget.driverName.toUpperCase(),
                        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 22),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PH: ${widget.driverPhone}',
                        style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 24),

                      // Footer Bar
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                        ),
                        child: const Center(
                          child: Text(
                            'Valid only for authorized deliveries',
                            style: TextStyle(color: Colors.black38, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Download & Share Action Button
              SizedBox(
                width: 300,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.download, color: Colors.white),
                  label: Text(
                    _isSaving ? 'Processing...' : 'Download & Share ID',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  onPressed: _isSaving ? null : _downloadAndShareId,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}