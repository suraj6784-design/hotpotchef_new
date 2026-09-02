// lib/screens/checkout_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/helpers.dart';
import '../utils/app_theme.dart';
import '../utils/network.dart';
import '../models/cart_enums.dart';
import '../widgets/app_widgets.dart';
import 'address_form_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final List<Map<String, dynamic>> cartItems;
  final VoidCallback onOrderPlacedSuccess;

  const CheckoutScreen({
    super.key,
    required this.cartItems,
    required this.onOrderPlacedSuccess,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isCalculatingFee = false;
  bool _isCheckingOut = false;

  List<Map<String, dynamic>> _savedAddresses = [];
  Map<String, dynamic>? _selectedAddressData;
  double _deliveryFee = 0.0;
  double _userCoinBalance = 0.0;
  bool _applyCoins = false;
  int _selectedTip = 0;

  Map<String, dynamic>? _serverPricing;
  String? _heldRazorpayOrderId;
  bool _orderRecorded = false;
  bool _placingOrder = false;

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _instructionsController = TextEditingController();
  late final Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    _initRazorpay();
    _loadUserCheckoutData();
  }

  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _releaseInventoryHold();
    _razorpay.clear();
    _phoneController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  void _releaseInventoryHold() {
    final orderId = _heldRazorpayOrderId;
    if (orderId == null || _orderRecorded || _placingOrder) return;
    _heldRazorpayOrderId = null;
    _supabase.rpc('release_checkout_inventory', params: {
      'p_razorpay_order_id': orderId,
    }).withTimeout(NetworkTimeouts.short);
  }

  // --- Initial Data Load ---

  Future<void> _loadUserCheckoutData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final futures = await Future.wait([
        _supabase.from('users').select().eq('id', user.id).maybeSingle(),
        _supabase
            .from('user_addresses')
            .select()
            .eq('user_id', user.id)
            .order('is_default', ascending: false),
        _supabase.rpc('calculate_cart_total', params: {'p_items': widget.cartItems}),
      ]).withTimeout(NetworkTimeouts.standard);

      final userData = futures[0] as Map<String, dynamic>?;
      final addressResponse = futures[1] as List<dynamic>;
      final pricingRes = futures[2] as Map<String, dynamic>?;

      if (!mounted) return;

      setState(() {
        _savedAddresses = List<Map<String, dynamic>>.from(addressResponse);
        if (_savedAddresses.isNotEmpty) {
          _selectedAddressData = _savedAddresses.first;
        }
        _phoneController.text = userData?['phone']?.toString() ??
            user.userMetadata?['phone']?.toString() ??
            '';
        _userCoinBalance =
            double.tryParse(userData?['hotpot_coins']?.toString() ?? '0') ?? 0.0;
        _serverPricing = pricingRes;
        _isLoading = false;
      });

      await _calculateDeliveryFee();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to load user checkout data');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _hasDelivery => widget.cartItems.any((item) {
        final raw = (item['selected_service_type'] ??
                item['selectedServiceType'] ??
                item['service_type'] ??
                item['serviceType'] ??
                '')
            .toString();
        return ServiceType.fromString(raw).isDelivery;
      });

  // --- Batch Distance & Delivery Calculation ---

  Future<void> _calculateDeliveryFee() async {
    if (!_hasDelivery) {
      setState(() => _deliveryFee = 0.0);
      return;
    }

    if (_selectedAddressData == null ||
        _selectedAddressData!['latitude'] == null ||
        _selectedAddressData!['longitude'] == null) {
      setState(() => _deliveryFee = 40.0);
      return;
    }

    setState(() => _isCalculatingFee = true);

    try {
      final custLat = double.parse(_selectedAddressData!['latitude'].toString());
      final custLng = double.parse(_selectedAddressData!['longitude'].toString());

      final chefIds = widget.cartItems
          .map((e) => e['chef_id']?.toString() ?? e['chefId']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      // Batch query all chef locations in a single round-trip
      final chefsData = await _supabase
          .from('users')
          .select('id, lat, lng')
          .inFilter('id', chefIds)
          .withTimeout(NetworkTimeouts.short);

      double calculatedTotal = 0.0;
      final chefLocations = {for (var c in chefsData) c['id'].toString(): c};

      for (final chefId in chefIds) {
        final chef = chefLocations[chefId];
        if (chef != null && chef['lat'] != null && chef['lng'] != null) {
          final chefLat = double.parse(chef['lat'].toString());
          final chefLng = double.parse(chef['lng'].toString());

          final distanceInKm = Geolocator.distanceBetween(
                chefLat,
                chefLng,
                custLat,
                custLng,
              ) /
              1000.0;

          double feeForChef = 30.0;
          if (distanceInKm > 3.0) {
            feeForChef += (distanceInKm - 3.0).ceil() * 10.0;
          }
          calculatedTotal += feeForChef;
        } else {
          calculatedTotal += 40.0;
        }
      }

      if (mounted) setState(() => _deliveryFee = calculatedTotal);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Delivery fee calculation error');
      if (mounted) setState(() => _deliveryFee = 40.0);
    } finally {
      if (mounted) setState(() => _isCalculatingFee = false);
    }
  }

  // --- Price Computations ---

  double get _foodTotal {
    final serverVal = double.tryParse(_serverPricing?['subtotal']?.toString() ?? 
                                     _serverPricing?['item_total']?.toString() ?? '');
    if (serverVal != null && serverVal > 0) {
      return serverVal;
    }

    // Robust client-side fallback calculation from cart items to prevent ₹0.00 bug
    double sum = 0.0;
    for (final item in widget.cartItems) {
      final price = double.tryParse(
            item['discounted_price']?.toString() ??
            item['discountedPrice']?.toString() ??
            item['price']?.toString() ??
            item['base_price']?.toString() ??
            item['basePrice']?.toString() ??
            '0',
          ) ?? 0.0;
      final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
      sum += price * qty;
    }
    return sum;
  }

  double get _packagingFee =>
      double.tryParse(_serverPricing?['packaging_fee']?.toString() ?? '20.0') ?? 20.0;

  double get _subTotalBeforeCoins =>
      _foodTotal + _packagingFee + _deliveryFee + _selectedTip;

  double get _coinDeduction =>
      _applyCoins ? min(_userCoinBalance, _subTotalBeforeCoins) : 0.0;

  double get _grandTotal => max(0.0, _subTotalBeforeCoins - _coinDeduction);

  // --- Razorpay Payment Pipeline ---

  Future<void> _startRazorpayPayment() async {
    final phone = _phoneController.text.trim();

    if (phone.length < 10) {
      _showSnackBar('Please enter a valid 10-digit contact number', isError: true);
      return;
    }
    if (_hasDelivery && _selectedAddressData == null) {
      _showSnackBar('Please select a delivery address', isError: true);
      return;
    }

    setState(() => _isCheckingOut = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Authentication session expired');
      if (widget.cartItems.isEmpty) throw Exception('Your cart is empty');

      // Edge function calculates canonical price server-side to prevent tampering
      final response = await _supabase.functions.invoke(
        'create-split-order',
        body: {
          'cart_items': _checkoutCartItems(),
          'customer_email': user.email,
          'customer_phone': phone,
          'delivery_address': _formattedDeliveryAddress(),
          'instructions': _instructionsController.text.trim(),
          'delivery_fee': _deliveryFee,
          'tip_amount': _selectedTip,
          'apply_coins': _applyCoins,
        },
      ).withTimeout(NetworkTimeouts.payment);

      if (response.status != 200 || response.data == null) {
        throw Exception('Could not initialize secure payment order');
      }

      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['success'] != true) {
        if (isSoldOutCheckoutError(data['error'], data)) {
          throw Exception(soldOutCheckoutMessage(charged: false));
        }
        throw Exception(data['error'] ?? 'Could not initialize secure payment order');
      }

      final razorpayOrderId = data['order_id'] as String;
      final amountInPaise = data['amount'];
      _heldRazorpayOrderId = razorpayOrderId;
      _orderRecorded = false;

      final razorpayKey = dotenv.env['RAZORPAY_KEY_ID'] ?? '';
      if (razorpayKey.isEmpty) {
        _releaseInventoryHold();
        throw Exception('Payment gateway configuration missing.');
      }

      final options = {
        'key': razorpayKey,
        'amount': amountInPaise,
        'name': 'HotPotChef',
        'description': 'Order Checkout',
        'order_id': razorpayOrderId,
        'retry': {'enabled': false, 'max_count': 0},
        'send_sms_hash': true,
        'prefill': {
          'contact': phone,
          'email': user.email ?? '',
        },
        'theme': {'color': '#F4511E'}
      };

      _razorpay.open(options);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Payment initialization failed');
      _releaseInventoryHold();
      setState(() => _isCheckingOut = false);
      _showSnackBar(
        isSoldOutCheckoutError(e)
            ? soldOutCheckoutMessage(charged: false)
            : 'Initialization Failed: ${networkErrorMessage(e)}',
        isError: true,
      );
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    _placingOrder = false;
    _releaseInventoryHold();
    setState(() => _isCheckingOut = false);
    _showSnackBar('Payment Cancelled or Failed: ${response.message ?? ''}', isError: true);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    setState(() => _isCheckingOut = false);
    _showSnackBar('Redirecting to wallet: ${response.walletName}');
  }

  String _formattedDeliveryAddress() {
    if (!_hasDelivery || _selectedAddressData == null) {
      return 'Store Pickup / Dine-In';
    }
    final a = _selectedAddressData!;
    return "${a['house_no']}, ${a['street']}, ${a['city']}, ${a['state']} - ${a['postal_code'] ?? a['pincode'] ?? ''}";
  }

  List<Map<String, dynamic>> _checkoutCartItems() {
    return widget.cartItems.map((item) {
      final rawDate = item['scheduledDate'] ??
          item['scheduled_date'] ??
          item['selected_date'] ??
          item['selectedDate'];
      String selectedDateStr = 'Today';

      if (rawDate != null) {
        try {
          final dt = DateTime.parse(rawDate.toString());
          selectedDateStr =
              "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
        } catch (_) {
          selectedDateStr = rawDate.toString();
        }
      }

      final rawDetails = item['rawMealDetails'] as Map<String, dynamic>?;
      final finalTimeSlot = item['timeSlot'] ??
          item['time_slot'] ??
          rawDetails?['exact_time'] ??
          item['exact_time'] ??
          'ASAP';

      return {
        ...item,
        'source_meal_id': item['source_meal_id'] ?? item['meal_id'] ?? item['mealId'] ?? item['id'],
        'selected_date': selectedDateStr,
        'time_slot': finalTimeSlot,
      };
    }).toList();
  }

  Map<String, dynamic> _placeOrderParams({
    required String paymentId,
    required String? razorpayOrderId,
    required String? signature,
  }) {
    final user = _supabase.auth.currentUser!;
    return {
      'p_customer_email': user.email!,
      'p_customer_phone': _phoneController.text.trim(),
      'p_delivery_address': _formattedDeliveryAddress(),
      'p_instructions': _instructionsController.text.trim(),
      'p_cart_items': _checkoutCartItems(),
      'p_apply_coins': _applyCoins,
      'p_tip_amount': _selectedTip,
      'p_delivery_fee': _deliveryFee,
      'p_payment_id': paymentId,
      'p_razorpay_order_id': razorpayOrderId,
      'p_razorpay_signature': signature,
      'p_idempotency_key': paymentId,
      'p_user_id': user.id,
    };
  }

  Future<Map<String, dynamic>?> _placeOrderWithRetries({
    required String paymentId,
    required String? razorpayOrderId,
    required String? signature,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final rpcResponse = await _supabase.rpc(
          'place_customer_order',
          params: _placeOrderParams(
            paymentId: paymentId,
            razorpayOrderId: razorpayOrderId,
            signature: signature,
          ),
        ).withTimeout(NetworkTimeouts.payment);
        if (rpcResponse is Map && rpcResponse['success'] == true) {
          return Map<String, dynamic>.from(rpcResponse);
        }
        lastError = rpcResponse is Map ? rpcResponse['error'] : rpcResponse;
        if (rpcResponse is Map && isSoldOutCheckoutError(rpcResponse['error'], Map<String, dynamic>.from(rpcResponse))) {
          break;
        }
      } catch (e) {
        lastError = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }

    try {
      final recover = await _supabase.functions.invoke(
        'recover-payment',
        body: {
          'payment_id': paymentId,
          'razorpay_order_id': razorpayOrderId,
          'razorpay_signature': signature,
          'customer_phone': _phoneController.text.trim(),
          'delivery_address': _formattedDeliveryAddress(),
          'instructions': _instructionsController.text.trim(),
          'cart_items': _checkoutCartItems(),
          'apply_coins': _applyCoins,
          'tip_amount': _selectedTip,
          'delivery_fee': _deliveryFee,
        },
      ).withTimeout(NetworkTimeouts.payment);
      final data = recover.data is Map ? Map<String, dynamic>.from(recover.data as Map) : null;
      if (data != null && data['success'] == true) return data;
      if (isSoldOutCheckoutError(data?['error'], data)) {
        throw Exception(soldOutCheckoutMessage(
          charged: true,
          refunded: data?['refunded'] == true,
        ));
      }
      if (data != null && data['refunded'] == true) {
        throw Exception(
          'We could not record this order, so the payment was refunded. It should return in 5–7 business days.',
        );
      }
      throw Exception(data?['error'] ?? lastError ?? 'Could not record paid order');
    } on FunctionException catch (e) {
      final details = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : null;
      if (isSoldOutCheckoutError(details?['error'] ?? e, details)) {
        throw Exception(soldOutCheckoutMessage(
          charged: true,
          refunded: details?['refunded'] == true,
        ));
      }
      if (details?['refunded'] == true) {
        throw Exception(
          'We could not record this order, so the payment was refunded. It should return in 5–7 business days.',
        );
      }
      throw Exception(details?['error'] ?? lastError ?? e.reasonPhrase ?? 'Could not record paid order');
    }
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    setState(() => _isCheckingOut = true);
    _placingOrder = true;

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Authentication expired');
      if (response.paymentId == null || response.paymentId!.isEmpty) {
        throw Exception('Payment succeeded without a payment id');
      }

      final placed = await _placeOrderWithRetries(
        paymentId: response.paymentId!,
        razorpayOrderId: response.orderId ?? _heldRazorpayOrderId,
        signature: response.signature,
      );

      if (placed == null || placed['success'] != true) {
        throw Exception(placed?['error'] ?? 'Server failed to record verified order.');
      }

      _orderRecorded = true;
      _heldRazorpayOrderId = null;

      if (mounted) {
        widget.onOrderPlacedSuccess();
        Navigator.pop(context);
        _showSnackBar('Payment Verified! Order placed successfully.', isError: false);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Order recording failed post-payment');
      if (mounted) {
        final soldOut = isSoldOutCheckoutError(e);
        _showSnackBar(
          soldOut
              ? '$e'
              : '${networkErrorMessage(e)}\nReference: ${response.paymentId}',
          isError: true,
          duration: const Duration(seconds: 8),
        );
      }
    } finally {
      _placingOrder = false;
      if (mounted) setState(() => _isCheckingOut = false);
    }
  }

  void _showSnackBar(String text, {bool isError = false, Duration duration = const Duration(seconds: 4)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- Modals & Widgets ---

  void _showAddressSelectorModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Select Delivery Address',
                    style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                if (_savedAddresses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('No saved addresses yet.', style: TextStyle(color: Colors.grey)),
                  ),
                ..._savedAddresses.map((addr) {
                  final isSelected = _selectedAddressData?['id'] == addr['id'];
                  final displayStr = "${addr['house_no']}, ${addr['street']}, ${addr['city'] ?? ''}";

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.deepOrange.withValues(alpha: 0.05) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? Colors.deepOrange : Colors.grey.shade300),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.location_on, color: isSelected ? Colors.deepOrange : Colors.grey),
                      title: Text(
                        displayStr,
                        style: TextStyle(
                          color: isSelected ? Colors.deepOrange : Colors.black87,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      onTap: () {
                        setState(() => _selectedAddressData = addr);
                        Navigator.pop(context);
                        _calculateDeliveryFee();
                      },
                    ),
                  );
                }),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.add_location_alt, color: Colors.deepOrange),
                  label: const Text('Add New Address',
                      style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddressFormScreen()),
                    ).then((_) => _loadUserCheckoutData());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTipChip(int amount, {String? label}) {
    final isSelected = _selectedTip == amount;
    return GestureDetector(
      onTap: () => setState(() => _selectedTip = amount),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.green : Colors.grey.shade300),
          boxShadow: [if (!isSelected) const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Text(
          label ?? '₹$amount',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Checkout & Payment'),
      ),
      bottomNavigationBar: _buildPayBar(),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Delivery Schedule Details
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.deepOrange, size: 20),
                    SizedBox(width: 8),
                    Text('Selected Delivery Schedule',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                  ],
                ),
                const Divider(height: 16, color: Colors.black12),
                ...widget.cartItems.map((item) {
                  final title = item['title'] ?? 'Meal';
                  
                  final rawDate = item['scheduledDate'] ??
            item['scheduled_date'] ??
            item['selected_date'] ??
            item['selectedDate'];
                  String dateStr = 'Today';
                  if (rawDate != null) {
                    try {
                      final dt = DateTime.parse(rawDate.toString());
                      dateStr = "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
                    } catch (_) {
                      dateStr = rawDate.toString();
                    }
                  }

                  final rawDetails = item['rawMealDetails'] as Map<String, dynamic>?;
                  final timeSlot = item['timeSlot'] ?? item['time_slot'] ?? rawDetails?['exact_time'] ?? item['exact_time'] ?? 'ASAP';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '• $title\n  🗓️ Date: $dateStr  ⏰ Slot: $timeSlot',
                      style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.3),
                    ),
                  );
                }),
              ],
            ),
          ),

          // Address Card
          if (_hasDelivery)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(children: [
                        Icon(Icons.location_pin, color: Colors.deepOrange, size: 20),
                        SizedBox(width: 8),
                        Text('Delivery Address',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ]),
                      TextButton(
                        onPressed: _showAddressSelectorModal,
                        child: const Text('Change',
                            style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedAddressData != null
                        ? "${_selectedAddressData!['house_no']}, ${_selectedAddressData!['street']}, ${_selectedAddressData!['city']}"
                        : 'Please add a delivery address',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),

          // Contact Details & Instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Contact & Instructions',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Contact Number',
                    prefixIcon: Icon(Icons.phone, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _instructionsController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Special Instructions (e.g. Ring the bell twice)',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Driver Tip Option
          if (_hasDelivery)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade200),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Reward your delivery hero',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.black87)),
                          SizedBox(height: 2),
                          Text('100% of the tip amount goes directly to them',
                              style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.green.shade100, shape: BoxShape.circle),
                        child: const Icon(Icons.delivery_dining, color: Colors.green, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildTipChip(10),
                      _buildTipChip(20),
                      _buildTipChip(30),
                      _buildTipChip(50),
                      _buildTipChip(0, label: 'None'),
                    ],
                  ),
                ],
              ),
            ),
          if (_hasDelivery) const SizedBox(height: 16),

          // Bill Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bill Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Items Total'),
                    Text('₹${_foodTotal.toStringAsFixed(2)}'),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Packaging Fee'),
                    Text('₹${_packagingFee.toStringAsFixed(2)}'),
                  ],
                ),
                if (_hasDelivery) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Delivery Fee'),
                      _isCalculatingFee
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text('₹${_deliveryFee.toStringAsFixed(2)}'),
                    ],
                  ),
                ],
                if (_hasDelivery && _selectedTip > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Delivery Tip'),
                      Text('₹${_selectedTip.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
                if (_userCoinBalance > 0) ...[
                  const Divider(height: 20),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppTheme.primary,
                    title: Text(
                      'Use HotPot Coins (Balance: ₹${_userCoinBalance.toStringAsFixed(2)})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    value: _applyCoins,
                    onChanged: (val) => setState(() => _applyCoins = val),
                  ),
                  if (_applyCoins && _coinDeduction > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Coins Discount',
                            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                        Text('-₹${_coinDeduction.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                      ],
                    ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: AppTheme.radiusMd,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Grand Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(
                        '₹${_grandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPayBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 16,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        boxShadow: AppTheme.heavyShadow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.rXl)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('You pay',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text('₹${_grandTotal.toStringAsFixed(0)}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GradientButton(
              label: 'Pay & Place Order',
              icon: Icons.lock_rounded,
              loading: _isCheckingOut,
              onPressed: _isCheckingOut ? null : _startRazorpayPayment,
            ),
          ),
        ],
      ),
    );
  }
}