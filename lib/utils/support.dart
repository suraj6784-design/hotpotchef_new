import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/legal_document_screen.dart';
import 'helpers.dart';
import 'legal_content.dart';

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String? parseOrderUuid(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty || !_uuidPattern.hasMatch(value)) return null;
  return value;
}

class SupportConfig {
  static String? _env(String key) {
    try {
      return dotenv.env[key]?.trim();
    } catch (_) {
      return null;
    }
  }

  static String get email {
    final value = _env('SUPPORT_EMAIL');
    if (value != null && value.contains('@')) return value;
    return 'hello@hotpotchef.com';
  }

  static String get whatsappDigits {
    final fromEnv = (_env('SUPPORT_WHATSAPP') ?? '').replaceAll(RegExp(r'\D'), '');
    if (fromEnv.length >= 10) return fromEnv;
    // Fallback number when SUPPORT_WHATSAPP is unset (ops line, not a personal founder chat).
    return '918446609281';
  }

  static bool get hasWhatsApp => whatsappDigits.length >= 10;

  static String get playStoreUrl {
    final value = _env('PLAY_STORE_URL');
    if (value != null && value.isNotEmpty) return value;
    return 'https://play.google.com/store/apps/details?id=com.hotpotchef.app';
  }

  /// Kept for callers that treated Play URL as optional.
  static String? get playStoreUrlOrNull {
    final value = playStoreUrl.trim();
    return value.isEmpty ? null : value;
  }

  static String? urlFor(LegalDocumentType type) {
    final key = switch (type) {
      LegalDocumentType.terms => 'TERMS_URL',
      LegalDocumentType.privacy => 'PRIVACY_URL',
      LegalDocumentType.faq => 'FAQ_URL',
      LegalDocumentType.cancellation => 'CANCELLATION_POLICY_URL',
    };
    final value = _env(key);
    if (value == null || value.isEmpty) return null;
    return value;
  }
}

String supportContactSubject({String? orderNumber}) {
  final number = orderNumber?.trim() ?? '';
  if (number.isEmpty) return 'HotPotChef support';
  return 'HotPotChef support — Order $number';
}

String supportContactMessage({String? orderNumber, String? orderUuid}) {
  final number = orderNumber?.trim() ?? '';
  final uuid = orderUuid?.trim() ?? '';
  if (number.isEmpty && uuid.isEmpty) {
    return 'Hi HotPotChef support, I need help with my order.';
  }

  final label = number.isNotEmpty ? number : uuid;
  final buffer = StringBuffer('Hi HotPotChef support,\n\nI need help with order $label.');
  if (uuid.isNotEmpty && uuid.toUpperCase() != label.toUpperCase()) {
    buffer.write('\nInternal order id: $uuid');
  }
  buffer.write('\nPlease look up this order and follow up.');
  return buffer.toString();
}

String newSupplyRequestId([DateTime? now]) {
  final stamp = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
  final tail = stamp.length >= 6 ? stamp.substring(stamp.length - 6) : stamp.padLeft(6, '0');
  return 'SUP-$tail';
}

String supportSupplyRequestSubject(String requestId) {
  return 'HotPotChef supply request — $requestId';
}

String supportSupplyRequestMessage({
  required String requestId,
  required String chefName,
  required String chefEmail,
  required String chefPhone,
  required String chefUserId,
  required String kitchenAddress,
  required String itemTitle,
  required String itemSku,
  required int quantity,
  String? itemDescription,
  double? unitPrice,
}) {
  final buffer = StringBuffer()
    ..writeln('HotPotChef packaging supply request')
    ..writeln()
    ..writeln('Request ID: $requestId')
    ..writeln()
    ..writeln('Chef')
    ..writeln('Name: ${chefName.trim().isEmpty ? 'Not provided' : chefName.trim()}')
    ..writeln('Email: ${chefEmail.trim().isEmpty ? 'Not provided' : chefEmail.trim()}')
    ..writeln('Phone: ${chefPhone.trim().isEmpty ? 'Not provided' : chefPhone.trim()}');
  if (chefUserId.trim().isNotEmpty) {
    buffer.writeln('Chef ID: ${chefUserId.trim()}');
  }
  buffer
    ..writeln('Kitchen: ${kitchenAddress.trim().isEmpty ? 'Not provided' : kitchenAddress.trim()}')
    ..writeln()
    ..writeln('Requested item')
    ..writeln('Item: ${itemTitle.trim().isEmpty ? 'Packaging supply' : itemTitle.trim()}');
  if (itemSku.trim().isNotEmpty) {
    buffer.writeln('SKU: ${itemSku.trim()}');
  }
  if (itemDescription != null && itemDescription.trim().isNotEmpty) {
    buffer.writeln('Details: ${itemDescription.trim()}');
  }
  buffer.writeln('Quantity: $quantity');
  if (unitPrice != null && unitPrice > 0) {
    buffer.writeln('Listed price: ₹${unitPrice.toStringAsFixed(0)} each');
  }
  buffer
    ..writeln()
    ..write('Please confirm availability, total, and kitchen delivery.');
  return buffer.toString();
}

String supportLinkedOrderCopy({String? orderNumber}) {
  final number = orderNumber?.trim() ?? '';
  if (number.isEmpty) {
    return 'We typically reply within one business day.';
  }
  return 'This conversation is linked to order $number. We typically reply within one business day.';
}

String _mailtoQuery(Map<String, String> params) {
  return params.entries
      .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
}

Future<bool> launchSupportEmail({String? subject, String? body}) {
  final uri = Uri(
    scheme: 'mailto',
    path: SupportConfig.email,
    query: _mailtoQuery({
      'subject': subject ?? 'HotPotChef support',
      if (body != null && body.isNotEmpty) 'body': body,
    }),
  );
  return launchUrl(uri);
}

Future<bool> launchSupportWhatsApp({String? message}) {
  if (!SupportConfig.hasWhatsApp) return Future.value(false);
  final uri = Uri.https('wa.me', '/${SupportConfig.whatsappDigits}', {
    if (message != null && message.isNotEmpty) 'text': message,
  });
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Opens WhatsApp (preferred) or email so the supply store gets the request details.
Future<bool> notifySupplyStore({
  required String requestId,
  required String message,
}) async {
  if (SupportConfig.hasWhatsApp) {
    final opened = await launchSupportWhatsApp(message: message);
    if (opened) return true;
  }
  return launchSupportEmail(
    subject: supportSupplyRequestSubject(requestId),
    body: message,
  );
}

Future<bool> launchPlayStore() {
  return launchUrl(Uri.parse(SupportConfig.playStoreUrl), mode: LaunchMode.externalApplication);
}

Future<void> openLegalDocument(BuildContext context, LegalDocumentType type) async {
  final url = SupportConfig.urlFor(type);
  if (url != null) {
    final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (launched || !context.mounted) return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => LegalDocumentScreen(type: type)),
  );
}

/// Creates an in-app support ticket via `create_support_ticket`.
Future<Map<String, dynamic>?> createSupportTicket({
  required String subject,
  required String body,
  String? orderId,
  String? orderNumber,
  String category = 'general',
  String channel = 'in_app',
}) async {
  final parsedOrderId = parseOrderUuid(orderId);
  final response = await Supabase.instance.client.rpc(
    'create_support_ticket',
    params: {
      'p_subject': subject,
      'p_body': body,
      'p_order_id': parsedOrderId,
      'p_order_number': (orderNumber?.trim().isEmpty ?? true) ? null : orderNumber!.trim(),
      'p_category': category,
      'p_channel': channel,
    },
  );
  if (response == null) return null;
  if (response is Map<String, dynamic>) return response;
  if (response is Map) return Map<String, dynamic>.from(response);
  return null;
}

Future<void> showContactSupportSheet(
  BuildContext context, {
  String? orderNumber,
  String? orderUuid,
  String? orderRef,
}) {
  final number = (orderNumber ?? orderRef)?.trim();
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: AppTheme.bottomSheetDecoration(isDark: isDark),
      child: ContactSupportSheet(
        orderNumber: (number == null || number.isEmpty) ? null : number,
        orderUuid: orderUuid,
      ),
    ),
  );
}

class ContactSupportSheet extends StatefulWidget {
  const ContactSupportSheet({super.key, this.orderNumber, this.orderUuid});

  final String? orderNumber;
  final String? orderUuid;

  @override
  State<ContactSupportSheet> createState() => _ContactSupportSheetState();
}

class _ContactSupportSheetState extends State<ContactSupportSheet> {
  bool _submitting = false;

  String get _message => supportContactMessage(
        orderNumber: widget.orderNumber,
        orderUuid: widget.orderUuid,
      );

  String get _subject => supportContactSubject(orderNumber: widget.orderNumber);

  Future<void> _openTicket() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final hasOrder = parseOrderUuid(widget.orderUuid) != null;
      final row = await createSupportTicket(
        subject: _subject,
        body: _message,
        orderId: widget.orderUuid,
        orderNumber: widget.orderNumber,
        category: hasOrder ? 'order' : 'general',
        channel: 'in_app',
      );
      if (!mounted) return;
      final publicId = row?['public_id']?.toString() ?? '';
      final router = GoRouter.maybeOf(context);
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            publicId.isEmpty
                ? 'Support ticket opened'
                : 'Ticket $publicId opened — we typically reply within one business day.',
          ),
          backgroundColor: AppTheme.success,
          action: router == null
              ? null
              : SnackBarAction(
                  label: 'View tickets',
                  textColor: Colors.white,
                  onPressed: () => router.push('/support-tickets'),
                ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open ticket: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final linkedOrder = widget.orderNumber?.trim() ?? '';
    final onSurface = AppTheme.onSurfaceOf(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: onSurface.withValues(alpha: 0.12),
                  borderRadius: AppTheme.radiusXl,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Contact support',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              supportLinkedOrderCopy(orderNumber: widget.orderNumber),
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 6),
            const Text(
              'Ops replies within 1 business day (SLA)',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (linkedOrder.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: AppTheme.radiusSm,
                  ),
                  child: Text(
                    'Order $linkedOrder',
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _submitting ? null : _openTicket,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.confirmation_number_outlined),
              label: Text(
                _submitting ? 'Opening ticket…' : 'Open support ticket',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                child: const Icon(Icons.email_outlined, color: AppTheme.primary),
              ),
              title: Text('Email us', style: TextStyle(fontWeight: FontWeight.w700, color: onSurface)),
              subtitle: Text(SupportConfig.email),
              onTap: _submitting
                  ? null
                  : () async {
                      await launchSupportEmail(subject: _subject, body: _message);
                    },
            ),
            if (SupportConfig.hasWhatsApp)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppTheme.success.withValues(alpha: 0.1),
                  child: const Icon(Icons.chat_outlined, color: AppTheme.success),
                ),
                title: Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w700, color: onSurface)),
                subtitle: const Text('Message the support line'),
                onTap: _submitting ? null : () => launchSupportWhatsApp(message: _message),
              ),
          ],
        ),
      ),
    );
  }
}
