// lib/screens/customer_bulk_request_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/helpers.dart';
import 'map_picker_screen.dart';

class CustomerBulkRequestScreen extends StatefulWidget {
  const CustomerBulkRequestScreen({super.key});

  @override
  State<CustomerBulkRequestScreen> createState() => _CustomerBulkRequestScreenState();
}

class _CustomerBulkRequestScreenState extends State<CustomerBulkRequestScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _qtyController = TextEditingController(text: '10');
  final _budgetController = TextEditingController();
  final _addressController = TextEditingController();

  String _selectedServiceType = 'Delivery Partner';
  DateTime _targetDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _targetTime = const TimeOfDay(hour: 13, minute: 0);
  bool _isLoading = false;

  double? _latitude;
  double? _longitude;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _qtyController.dispose();
    _budgetController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _broadcastRequest() async {
    if (!_formKey.currentState!.validate()) return;

    if (_latitude == null || _longitude == null) {
      _showSnackBar('Please pin your delivery or event location on the map.', isError: true);
      return;
    }

    final quantity = int.tryParse(_qtyController.text.trim()) ?? 0;
    final budget = double.tryParse(_budgetController.text.trim()) ?? 0.0;

    if (quantity < 5) {
      _showSnackBar('Bulk pre-orders require a minimum of 5 portions.', isError: true);
      return;
    }

    if (budget <= 0) {
      _showSnackBar('Please enter a valid total budget for the order.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Authentication session expired. Please sign in.');

      final userData = await _supabase
          .from('users')
          .select('phone, name, full_name')
          .eq('id', user.id)
          .maybeSingle();

      final phone = userData?['phone']?.toString() ?? user.userMetadata?['phone']?.toString() ?? '';
      final customerName = userData?['name']?.toString() ??
          userData?['full_name']?.toString() ??
          user.userMetadata?['name']?.toString() ??
          user.email?.split('@')[0] ??
          'Customer';

      // Standardized ISO 8601 UTC timestamp generation
      final targetDateTime = DateTime(
        _targetDate.year,
        _targetDate.month,
        _targetDate.day,
        _targetTime.hour,
        _targetTime.minute,
      );

      if (targetDateTime.isBefore(DateTime.now())) {
        throw Exception('The requested event time must be set in the future.');
      }

      final payload = <String, dynamic>{
        'customer_id': user.id,
        'customer_name': customerName,
        'customer_email': user.email ?? '',
        'customer_phone': phone,
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'quantity': quantity,
        'remaining_quantity': quantity,
        'target_date_time': targetDateTime.toUtc().toIso8601String(),
        'budget': budget,
        'service_type': _selectedServiceType,
        'delivery_address': _addressController.text.trim(),
        'latitude': _latitude,
        'longitude': _longitude,
        'status': 'Open',
        'accepted_chefs': [],
        'created_at': DateTime.now().toIso8601String(),
      };

      await _insertCustomerRequest(payload);

      if (mounted) {
        _showSnackBar('Bulk request broadcasted successfully! Local chefs have been notified. 🎉');
        Navigator.pop(context);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Bulk Request Broadcast Failure');
      _showSnackBar(_broadcastError(e), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _insertCustomerRequest(Map<String, dynamic> payload) async {
    final body = Map<String, dynamic>.from(payload);
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        await _supabase.from('customer_requests').insert(body);
        return;
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST204') rethrow;
        final missing = _missingSchemaColumn(e.message);
        if (missing == null || !body.containsKey(missing)) rethrow;
        body.remove(missing);
      }
    }
    throw const PostgrestException(
      message: 'Could not find a matching customer_requests schema',
      code: 'PGRST204',
    );
  }

  String? _missingSchemaColumn(String? message) {
    final match = RegExp(r"Could not find the '([^']+)' column").firstMatch(message ?? '');
    return match?.group(1);
  }

  String _broadcastError(Object error) {
    if (error is Exception) {
      final text = error.toString().replaceFirst('Exception: ', '');
      if (text.contains('future') || text.contains('sign in') || text.contains('Authentication')) {
        return text;
      }
    }
    return 'Could not broadcast this request. Please try again.';
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
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.asset('assets/app_icon.png', height: 24, width: 24)),
            const SizedBox(width: 8),
            Text('Broadcast Bulk Pre-Order', style: TextStyle(color: AppTheme.onSurfaceOf(context), fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.primary),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Organizing catering, family gatherings, or office tiffins? Broadcast your requirement to all nearby home chefs. Multiple kitchens can coordinate to fulfill large orders together!',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),

            TextFormField(
              controller: _titleController,
              validator: (v) => v == null || v.trim().isEmpty ? 'Enter dish or event requirement' : null,
              decoration: _inputStyle('Dish / Requirement (e.g. 15x Puran Poli Thali)'),
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _descController,
              maxLines: 3,
              decoration: _inputStyle('Dietary notes, spice levels, or packaging preferences'),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _qtyController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      final val = int.tryParse(v ?? '') ?? 0;
                      if (val < 5) return 'Minimum 5 portions';
                      return null;
                    },
                    decoration: _inputStyle('Total Portions *'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _budgetController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                    validator: (v) => v == null || v.trim().isEmpty ? 'Enter budget' : null,
                    decoration: _inputStyle('Total Budget (₹) *'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Date & Time Selectors
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.calendar_month, size: 16, color: AppTheme.primary),
                    label: Text(formatFriendlyDate(_targetDate), style: TextStyle(fontSize: 13, color: AppTheme.onSurfaceOf(context))),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _targetDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                      );
                      if (picked != null) setState(() => _targetDate = picked);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.access_time, size: 16, color: AppTheme.primary),
                    label: Text(_targetTime.format(context), style: TextStyle(fontSize: 13, color: AppTheme.onSurfaceOf(context))),
                    onPressed: () async {
                      final picked = await showTimePicker(context: context, initialTime: _targetTime);
                      if (picked != null) setState(() => _targetTime = picked);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _selectedServiceType,
              dropdownColor: AppTheme.surfaceOf(context),
              style: TextStyle(fontSize: 14, color: AppTheme.onSurfaceOf(context)),
              decoration: _inputStyle('Fulfillment Type'),
              items: ['Delivery Partner', 'Chef-Self', 'Customer Pickup', 'Dine In']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 14))))
                  .toList(),
              onChanged: (val) => setState(() => _selectedServiceType = val!),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _addressController,
              validator: (v) => v == null || v.trim().isEmpty ? 'Delivery or venue address required' : null,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Delivery / Event Address *',
                labelStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surfaceOf(context),
                prefixIcon: const Icon(Icons.location_on, color: AppTheme.primary),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.map, color: AppTheme.primary),
                  tooltip: 'Pin on Map',
                  onPressed: () async {
                    final result = await Navigator.push<Map<String, dynamic>?>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapPickerScreen(initialLat: _latitude, initialLng: _longitude),
                      ),
                    );
                    if (result != null && mounted) {
                      setState(() {
                        _addressController.text = result['address']?.toString() ?? '';
                        _latitude = (result['latitude'] as num?)?.toDouble();
                        _longitude = (result['longitude'] as num?)?.toDouble();
                      });
                    }
                  },
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.hairlineOf(context))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
              ),
            ),
            const SizedBox(height: 32),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isLoading ? null : _broadcastRequest,
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Broadcast to Local Chefs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
      filled: true,
      fillColor: AppTheme.surfaceOf(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.hairlineOf(context))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
    );
  }
}