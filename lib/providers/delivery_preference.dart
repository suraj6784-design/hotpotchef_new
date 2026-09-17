import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The delivery address the customer last picked on Home.
/// Checkout uses this so the feed pin and payment drop-off stay in sync.
final selectedDeliveryAddressProvider =
    NotifierProvider<SelectedDeliveryAddressNotifier, Map<String, dynamic>?>(
  SelectedDeliveryAddressNotifier.new,
);

class SelectedDeliveryAddressNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() => null;

  void setAddress(Map<String, dynamic>? address) {
    state = address;
  }
}
