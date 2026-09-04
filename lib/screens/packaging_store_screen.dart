// lib/screens/packaging_store_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/app_theme.dart';

class PackagingStoreScreen extends StatefulWidget {
  const PackagingStoreScreen({super.key});

  @override
  State<PackagingStoreScreen> createState() => _PackagingStoreScreenState();
}

class _PackagingStoreScreenState extends State<PackagingStoreScreen> {
  final _supabase = Supabase.instance.client;
  bool _isProcessing = false;

  final List<Map<String, dynamic>> _mockSupplies = const [
    {
      'id': 'm1',
      'title': 'Eco-Friendly Meal Box (500ml)',
      'price': 250.0,
      'description': 'Pack of 50. High quality, leak-proof, microwave-safe boxes perfect for gravies and rice.',
      'icon_code': Icons.takeout_dining_rounded,
    },
    {
      'id': 'm2',
      'title': 'Spill-Proof Gravy Containers',
      'price': 180.0,
      'description': 'Pack of 100. Tight-seal lids ensure no spills during transit.',
      'icon_code': Icons.soup_kitchen_rounded,
    },
    {
      'id': 'm3',
      'title': 'Wooden Cutlery Set',
      'price': 120.0,
      'description': 'Pack of 50 sets. Includes Spoon, Fork, and Paper Napkin.',
      'icon_code': Icons.restaurant_rounded,
    },
    {
      'id': 'm4',
      'title': 'Branded Paper Carry Bags',
      'price': 300.0,
      'description': 'Pack of 50. Sturdy, eco-friendly paper bags with handle.',
      'icon_code': Icons.shopping_bag_rounded,
    },
  ];

  Future<void> _placePackagingOrder(Map<String, dynamic> item) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Session expired. Please sign in again.');

      final userData = await _supabase
          .from('users')
          .select('address, house_no, street, city, state, pincode')
          .eq('id', user.id)
          .maybeSingle();

      final address = userData?['address']?.toString() ?? '';
      if (address.isEmpty) {
        throw Exception('Please complete your Kitchen Pickup Address in your profile before ordering supplies.');
      }

      final price = (item['price'] as num?)?.toDouble() ?? 0.0;

      await _supabase.from('packaging_orders').insert({
        'chef_id': user.id,
        'item_id': item['id'],
        'quantity': 1,
        'total_price': price,
        'delivery_address': address,
        'status': 'Pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      _showSnackBar('Order placed successfully! Supplies will be delivered to your kitchen.');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Packaging supply order failure');
      _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSnackBar(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating ?? SnackBarBehavior.floating,
      ),
    );
  }

  IconData _parseIcon(dynamic iconValue) {
    if (iconValue is IconData) return iconValue;
    return Icons.inventory_2_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset('assets/app_icon.png', height: 24, width: 24),
            ),
            const SizedBox(width: 8),
            Text('Packaging Store', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
          ],
        ),
        backgroundColor: AppTheme.surfaceOf(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.onSurfaceOf(context)),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        // Scoped stream for remote inventory table if available
        stream: _supabase.from('packaging_inventory').stream(primaryKey: ['id']),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }

          final remoteItems = snapshot.data ?? [];
          final items = remoteItems.isNotEmpty ? remoteItems : _mockSupplies;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.14 : 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: const [
                      Icon(Icons.inventory_2_rounded, color: AppTheme.primary, size: 40),
                      SizedBox(height: 10),
                      Text('HotPotChef Supply Store',
                          style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Order premium branded packaging delivered directly to your kitchen.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    ],
                  ),
                );
              }

              final item = items[index - 1];
              final title = item['title']?.toString() ?? 'Packaging Supply';
              final desc = item['description']?.toString() ?? 'Standard branded packaging supplies for home kitchens.';
              final price = (item['price'] as num?)?.toDouble() ?? 0.0;
              final imageUrl = item['image_url']?.toString();
              final iconData = _parseIcon(item['icon_code'] ?? item['icon']);

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceOf(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.hairlineOf(context)),
                  boxShadow: AppTheme.softShadow,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 85,
                        width: 85,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.hairlineOf(context)),
                          image: imageUrl != null && imageUrl.isNotEmpty
                              ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
                              : null,
                        ),
                        child: (imageUrl == null || imageUrl.isEmpty)
                            ? Icon(iconData, color: AppTheme.primary, size: 34)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.onSurfaceOf(context))),
                            const SizedBox(height: 4),
                            Text(desc,
                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('₹${price.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppTheme.primary)),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  onPressed: _isProcessing ? null : () => _placePackagingOrder(item),
                                  child: _isProcessing
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : const Text('Buy Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}