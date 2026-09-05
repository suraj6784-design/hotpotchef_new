// lib/screens/packaging_store_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/helpers.dart';
import '../utils/support.dart';
import '../widgets/app_widgets.dart';

class PackagingStoreScreen extends StatefulWidget {
  const PackagingStoreScreen({super.key});

  @override
  State<PackagingStoreScreen> createState() => _PackagingStoreScreenState();
}

class _PackagingStoreScreenState extends State<PackagingStoreScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoadingChef = false;
  String? _busyItemKey;

  final List<Map<String, dynamic>> _catalog = const [
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

  Future<void> _requestSupply(Map<String, dynamic> item) async {
    if (_isLoadingChef) return;
    final itemKey = item['id']?.toString() ?? item['title']?.toString() ?? '';
    setState(() {
      _isLoadingChef = true;
      _busyItemKey = itemKey;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Session expired. Please sign in again.');

      final userData = await _supabase
          .from('users')
          .select('name, phone, address, house_no, street, city, state, pincode')
          .eq('id', user.id)
          .maybeSingle();

      final kitchen = formatSavedAddress(userData);
      if (kitchen.isEmpty) {
        throw Exception('Add your kitchen pickup address in profile before requesting supplies.');
      }

      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppTheme.surfaceOf(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => SupplyRequestSheet(
          item: item,
          chefName: userData?['name']?.toString() ?? user.userMetadata?['name']?.toString() ?? '',
          chefEmail: user.email ?? '',
          chefPhone: userData?['phone']?.toString() ?? user.userMetadata?['phone']?.toString() ?? '',
          chefUserId: user.id,
          kitchenAddress: kitchen,
        ),
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Packaging supply request failed');
      final text = e.toString().replaceFirst('Exception: ', '');
      _showSnackBar(
        text.contains('kitchen') || text.contains('sign in') || text.contains('Session')
            ? text
            : 'Could not start this supply request. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingChef = false;
          _busyItemKey = null;
        });
      }
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
            const AppLogo(size: 24),
            const SizedBox(width: 8),
            Text('Packaging Store', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
          ],
        ),
        backgroundColor: AppTheme.surfaceOf(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.onSurfaceOf(context)),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase.from('packaging_inventory').stream(primaryKey: ['id']),
        builder: (context, snapshot) {
          final remoteItems = snapshot.hasError ? const <Map<String, dynamic>>[] : (snapshot.data ?? []);
          final items = remoteItems.isNotEmpty ? remoteItems : _catalog;

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
                  child: const Column(
                    children: [
                      Icon(Icons.inventory_2_rounded, color: AppTheme.primary, size: 40),
                      SizedBox(height: 10),
                      Text('HotPotChef Supply Store',
                          style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text(
                        'Request branded packaging for your kitchen. We confirm price and delivery on email or WhatsApp.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      ),
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
              final itemKey = item['id']?.toString() ?? title;
              final busy = _isLoadingChef && _busyItemKey == itemKey;

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
                                  onPressed: _isLoadingChef ? null : () => _requestSupply(item),
                                  child: busy
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : const Text('Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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

class SupplyRequestSheet extends StatefulWidget {
  const SupplyRequestSheet({
    super.key,
    required this.item,
    required this.chefName,
    required this.chefEmail,
    required this.chefPhone,
    required this.chefUserId,
    required this.kitchenAddress,
  });

  final Map<String, dynamic> item;
  final String chefName;
  final String chefEmail;
  final String chefPhone;
  final String chefUserId;
  final String kitchenAddress;

  @override
  State<SupplyRequestSheet> createState() => _SupplyRequestSheetState();
}

class _SupplyRequestSheetState extends State<SupplyRequestSheet> {
  late final String _requestId = newSupplyRequestId();
  int _quantity = 1;

  String get _itemTitle => widget.item['title']?.toString() ?? 'Packaging supply';
  String get _itemSku => widget.item['sku']?.toString() ?? widget.item['id']?.toString() ?? '';
  String get _itemDescription => widget.item['description']?.toString() ?? '';
  double? get _unitPrice => (widget.item['price'] as num?)?.toDouble();

  String get _message => supportSupplyRequestMessage(
        requestId: _requestId,
        chefName: widget.chefName,
        chefEmail: widget.chefEmail,
        chefPhone: widget.chefPhone,
        chefUserId: widget.chefUserId,
        kitchenAddress: widget.kitchenAddress,
        itemTitle: _itemTitle,
        itemSku: _itemSku,
        quantity: _quantity,
        itemDescription: _itemDescription,
        unitPrice: _unitPrice,
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Request supplies', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Send request $_requestId to HotPotChef support. Include quantity, then email or WhatsApp.',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            Text(_itemTitle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_quantity', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                IconButton(
                  onPressed: _quantity < 20 ? () => setState(() => _quantity++) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0x1AF4511E),
                child: Icon(Icons.email_outlined, color: Color(0xFFF4511E)),
              ),
              title: const Text('Email us', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(SupportConfig.email),
              onTap: () async {
                await launchSupportEmail(
                  subject: supportSupplyRequestSubject(_requestId),
                  body: _message,
                );
              },
            ),
            if (SupportConfig.hasWhatsApp)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0x1A2E9E5B),
                  child: Icon(Icons.chat_outlined, color: Color(0xFF2E9E5B)),
                ),
                title: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Message the support line'),
                onTap: () => launchSupportWhatsApp(message: _message),
              ),
          ],
        ),
      ),
    );
  }
}
