// lib/screens/packaging_store_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../services/auth_session.dart';
import '../utils/helpers.dart';
import '../utils/network.dart';
import '../utils/support.dart';
import '../widgets/app_widgets.dart';
import '../widgets/customer_ui_components.dart';

class PackagingStoreScreen extends StatefulWidget {
  const PackagingStoreScreen({super.key});

  @override
  State<PackagingStoreScreen> createState() => _PackagingStoreScreenState();
}

class _PackagingStoreScreenState extends State<PackagingStoreScreen> {
  final _supabase = Supabase.instance.client;
  bool _checkingAccess = true;
  bool _isChef = false;
  bool _isLoadingChef = false;
  String? _busyItemKey;

  @override
  void initState() {
    super.initState();
    unawaited(_verifyChefAccess());
  }

  Future<void> _verifyChefAccess() async {
    final role = await AuthSession.resolveRole();
    if (!mounted) return;
    setState(() {
      _isChef = role.canUsePackagingStore;
      _checkingAccess = false;
    });
  }

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
    if (_isLoadingChef || !_isChef) return;
    final itemKey = item['id']?.toString() ?? item['title']?.toString() ?? '';
    setState(() {
      _isLoadingChef = true;
      _busyItemKey = itemKey;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Session expired. Please sign in again.');

      var role = await AuthSession.resolveRole();
      if (!role.canUsePackagingStore) {
        role = AuthSession.roleFromSession();
      }
      if (!role.canUsePackagingStore) {
        throw Exception('Packaging supplies are for chefs only.');
      }

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
      final saved = await showModalBottomSheet<bool>(
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
      if (saved == true && mounted) {
        _showSnackBar('Request filed with the HotPotChef supply desk. Track status below.');
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Packaging supply request failed');
      final text = e.toString().replaceFirst('Exception: ', '');
      _showSnackBar(
        text.contains('kitchen') ||
            text.contains('sign in') ||
            text.contains('Session') ||
            text.contains('chefs only')
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
    if (_checkingAccess) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isChef) {
      return Scaffold(
        backgroundColor: AppTheme.canvasOf(context),
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Chefs only',
          message: 'The packaging store is for kitchen accounts. Sign in as a chef to request supplies.',
        ),
      );
    }
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
        stream: _supabase
            .from('customer_requests')
            .stream(primaryKey: ['id'])
            .eq('customer_id', _supabase.auth.currentUser?.id ?? ''),
        builder: (context, orderSnap) {
          final myOrders = (orderSnap.hasError ? const <Map<String, dynamic>>[] : (orderSnap.data ?? []))
              .where(isPackagingSupplyRequest)
              .toList()
            ..sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
          return StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase.from('packaging_inventory').stream(primaryKey: ['id']),
        builder: (context, snapshot) {
          final remoteItems = snapshot.hasError ? const <Map<String, dynamic>>[] : (snapshot.data ?? []);
          final items = remoteItems.isNotEmpty ? remoteItems : _catalog;
          final extra = myOrders.isEmpty ? 0 : myOrders.length + 1;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length + 1 + extra,
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
                        'Tap Request to place the order on your kitchen account. The HotPotChef supply desk confirms stock in-app; WhatsApp is optional backup.',
                        textAlign: TextAlign.center,
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                );
              }

              if (index == items.length + 1) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(4, 12, 4, 10),
                  child: Text('Your packaging requests', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                );
              }
              if (index > items.length + 1) {
                final order = myOrders[index - items.length - 2];
                return _PackagingOrderTile(order: order);
              }
              final item = items[index - 1];
              final title = item['title']?.toString() ?? 'Packaging Supply';
              final desc = item['description']?.toString() ?? 'Standard branded packaging supplies for home kitchens.';
              final price = (item['price'] as num?)?.toDouble() ?? 0.0;
              final imageUrl = item['image_url']?.toString();
              final iconData = _parseIcon(item['icon_code'] ?? item['icon']);
              final itemKey = item['id']?.toString() ?? title;
              final busy = _isLoadingChef && _busyItemKey == itemKey;
              final alreadyRequested = packagingCatalogItemRequested(myOrders, item);

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
                                style: AppTheme.caption,
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
                                    backgroundColor: alreadyRequested ? AppTheme.success : AppTheme.primary,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: alreadyRequested ? AppTheme.success : null,
                                    disabledForegroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  onPressed: (_isLoadingChef || alreadyRequested) ? null : () => _requestSupply(item),
                                  child: busy
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : Text(
                                          alreadyRequested ? 'Requested' : 'Request',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
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
      );
        },
      ),
    );
  }
}

class _PackagingOrderTile extends StatelessWidget {
  const _PackagingOrderTile({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final status = packagingRequestStatusLabel(order['status']?.toString());
    final qty = order['quantity'] ?? 1;
    final total = parseMoney(order['quoted_total'] ?? order['budget'] ?? order['total_price']);
    final requestId = packagingRequestDisplayId(order);
    final note = order['ops_note']?.toString().trim() ?? '';
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(order['title']?.toString() ?? 'Packaging', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          [
            if (requestId.isNotEmpty) requestId else 'Packaging request',
            'Qty $qty',
            status,
            if (note.isNotEmpty) note,
          ].join(' • '),
          style: AppTheme.caption,
        ),
        trailing: Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900)),
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
  bool _placing = false;
  bool _placed = false;
  bool _notified = false;
  String? _saveError;

  String get _itemTitle => widget.item['title']?.toString() ?? 'Packaging supply';
  String get _itemSku => widget.item['sku']?.toString() ?? widget.item['id']?.toString() ?? '';
  String get _itemDescription => widget.item['description']?.toString() ?? '';
  double? get _unitPrice => (widget.item['price'] as num?)?.toDouble();

  double get _total => packagingOrderTotal(_unitPrice ?? 0, _quantity);

  Future<void> _placeOrder() async {
    if (_placing || _placed) return;
    setState(() {
      _placing = true;
      _saveError = null;
    });
    try {
      final payload = packagingSupplyRequestPayload(
        chefId: widget.chefUserId,
        chefName: widget.chefName,
        chefEmail: widget.chefEmail,
        chefPhone: widget.chefPhone,
        kitchenAddress: widget.kitchenAddress,
        title: _itemTitle,
        requestId: _requestId,
        sku: _itemSku,
        description: _itemDescription,
        quantity: _quantity,
        unitPrice: _unitPrice ?? 0,
      );
      final extras = <String, dynamic>{};
      for (final key in const ['remaining_quantity', 'quoted_total', 'request_type']) {
        if (payload.containsKey(key)) extras[key] = payload.remove(key);
      }
      await _insertCustomerRequest(payload, extras).withTimeout(NetworkTimeouts.standard);
      if (!mounted) return;

      final notified = await notifySupplyStore(
        requestId: _requestId,
        message: _message,
      );

      if (!mounted) return;
      setState(() {
        _placed = true;
        _notified = notified;
        _placing = false;
      });
      if (notified) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to send packaging request');
      if (!mounted) return;
      setState(() {
        _placing = false;
        _saveError = (e is NetworkException)
            ? e.message
            : 'Could not send this packaging request. Try again.';
      });
    }
  }

  Future<void> _notifyAgain() async {
    final notified = await notifySupplyStore(
      requestId: _requestId,
      message: _message,
    );
    if (!mounted) return;
    setState(() => _notified = notified || _notified);
    if (notified) Navigator.pop(context, true);
  }

  Future<void> _insertCustomerRequest(
    Map<String, dynamic> payload,
    Map<String, dynamic> extras,
  ) async {
    final client = Supabase.instance.client;
    final inserted = await _insertKnownColumns(client, payload);
    if (extras.isEmpty) return;

    final requestId = inserted?['id']?.toString();
    var body = Map<String, dynamic>.from(extras);
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final query = client.from('customer_requests').update(body);
        if (requestId != null && requestId.isNotEmpty) {
          await query.eq('id', requestId);
        } else {
          await query
              .eq('customer_id', payload['customer_id'])
              .eq('title', payload['title'])
              .eq('created_at', payload['created_at']);
        }
        return;
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST204') return;
        final missing = _missingSchemaColumn(e.message);
        if (missing == null || !body.containsKey(missing)) return;
        body.remove(missing);
        if (body.isEmpty) return;
      }
    }
  }

  Future<Map<String, dynamic>?> _insertKnownColumns(
    SupabaseClient client,
    Map<String, dynamic> payload,
  ) async {
    final body = Map<String, dynamic>.from(payload);
    Object? lastError;
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        try {
          return await client.from('customer_requests').insert(body).select('id').maybeSingle();
        } on PostgrestException catch (e) {
          if (e.code == 'PGRST204') rethrow;
          if (e.code == '23514' || e.code == '23502') rethrow;
          await client.from('customer_requests').insert(body);
          return null;
        }
      } on PostgrestException catch (e) {
        lastError = e;
        if (e.code == 'PGRST204') {
          final missing = _missingSchemaColumn(e.message);
          if (missing == null || !body.containsKey(missing)) rethrow;
          body.remove(missing);
          continue;
        }
        if (e.code == '23514' && (body['status']?.toString().toLowerCase() ?? '') == 'pending') {
          body['status'] = 'Open';
          continue;
        }
        if (e.code == '23502' && !body.containsKey('target_date_time')) {
          body['target_date_time'] = DateTime.now().toUtc().add(const Duration(days: 3)).toIso8601String();
          continue;
        }
        rethrow;
      }
    }
    throw lastError ??
        const PostgrestException(
          message: 'Could not save this request',
          code: 'PGRST204',
        );
  }

  String? _missingSchemaColumn(String? message) {
    return RegExp(r"Could not find the '([^']+)' column").firstMatch(message ?? '')?.group(1);
  }

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
    final channel = SupportConfig.hasWhatsApp ? 'WhatsApp' : 'email';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
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
              _placed
                  ? (_notified
                      ? 'Request $_requestId is on your account and was sent to the supply store via $channel.'
                      : 'Request $_requestId is on your account. Open $channel below if the store message did not open.')
                  : 'One tap places request $_requestId on your kitchen account and opens $channel to notify the HotPotChef supply store.',
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
                  onPressed: (!_placed && _quantity > 1) ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_quantity', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                IconButton(
                  onPressed: (!_placed && _quantity < 20) ? () => setState(() => _quantity++) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            Text('Total ₹${_total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            if (_saveError != null) ...[
              const SizedBox(height: 10),
              Text(_saveError!, style: const TextStyle(color: AppTheme.error, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _placing || _placed ? null : _placeOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: _placed ? AppTheme.success : AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _placed ? AppTheme.success : null,
                disabledForegroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _placing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      _placed ? 'Requested' : 'Request',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
            ),
            if (_placed) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _notifyAgain,
                icon: Icon(
                  SupportConfig.hasWhatsApp ? Icons.chat_outlined : Icons.email_outlined,
                  size: 18,
                ),
                label: Text(
                  SupportConfig.hasWhatsApp ? 'Message store again' : 'Email store again',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}
