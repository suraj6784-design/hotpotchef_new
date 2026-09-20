import 'package:flutter/material.dart';
import 'app_env.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final value = appEnv(key);
    return value.isEmpty ? null : value;
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
    if (value != null && value.isNotEmpty) return value;
    // Public site pages (same copy as in-app LegalDocumentScreen).
    return switch (type) {
      LegalDocumentType.terms => 'https://hotpotchef.com/terms',
      LegalDocumentType.privacy => 'https://hotpotchef.com/privacy',
      LegalDocumentType.faq => 'https://hotpotchef.com/faq',
      LegalDocumentType.cancellation => 'https://hotpotchef.com/cancellation',
    };
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
    return 'Answer a few questions first so ops has the issue details. We typically reply within one business day.';
  }
  return 'This conversation is linked to order $number. Answer a few questions first so ops has the issue details. We typically reply within one business day.';
}

class SupportDrillChoice {
  const SupportDrillChoice({
    required this.id,
    required this.label,
    this.category,
    this.needsNotes = false,
    this.children = const [],
  });

  final String id;
  final String label;
  final String? category;
  final bool needsNotes;
  final List<SupportDrillChoice> children;

  bool get isLeaf => children.isEmpty;
}

const _kSupportNotesMin = 8;

List<SupportDrillChoice> supportDrillTree({required bool hasOrder}) {
  final order = SupportDrillChoice(
    id: 'order',
    label: hasOrder ? 'This order' : 'An order',
    category: 'order',
    children: const [
      SupportDrillChoice(
        id: 'late',
        label: 'Running late or not arriving',
        category: 'order',
        children: [
          SupportDrillChoice(id: 'kitchen', label: 'Kitchen has not started', category: 'order'),
          SupportDrillChoice(id: 'driver', label: 'Driver is delayed', category: 'delivery'),
          SupportDrillChoice(id: 'tracking', label: 'Tracking is not updating', category: 'order'),
        ],
      ),
      SupportDrillChoice(
        id: 'wrong',
        label: 'Missing or wrong food',
        category: 'order',
        children: [
          SupportDrillChoice(id: 'missing', label: 'An item is missing', category: 'order'),
          SupportDrillChoice(id: 'wrong_dish', label: 'Wrong dish delivered', category: 'order'),
          SupportDrillChoice(id: 'short', label: 'Quantity is short', category: 'order'),
        ],
      ),
      SupportDrillChoice(
        id: 'quality',
        label: 'Food quality or safety',
        category: 'quality',
        children: [
          SupportDrillChoice(id: 'cold', label: 'Cold or not as described', category: 'quality'),
          SupportDrillChoice(id: 'hygiene', label: 'Hygiene or allergen concern', category: 'quality', needsNotes: true),
          SupportDrillChoice(id: 'pack', label: 'Packaging was damaged', category: 'quality'),
        ],
      ),
      SupportDrillChoice(
        id: 'money',
        label: 'Cancel, refund, or charge',
        category: 'order',
        children: [
          SupportDrillChoice(id: 'cancel', label: 'Want to cancel', category: 'order'),
          SupportDrillChoice(id: 'refund', label: 'Refund is pending', category: 'payment'),
          SupportDrillChoice(id: 'charged', label: 'Charged after cancel', category: 'payment'),
        ],
      ),
      SupportDrillChoice(id: 'order_other', label: 'Something else about this order', category: 'order', needsNotes: true),
    ],
  );
  return [
    order,
    const SupportDrillChoice(
      id: 'payment',
      label: 'Payment',
      category: 'payment',
      children: [
        SupportDrillChoice(id: 'deducted', label: 'Failed but amount deducted', category: 'payment'),
        SupportDrillChoice(id: 'twice', label: 'Charged twice', category: 'payment'),
        SupportDrillChoice(id: 'method', label: 'Card or UPI issue', category: 'payment'),
        SupportDrillChoice(id: 'pay_other', label: 'Something else about payment', category: 'payment', needsNotes: true),
      ],
    ),
    const SupportDrillChoice(
      id: 'rider',
      label: 'Delivery partner',
      category: 'delivery',
      children: [
        SupportDrillChoice(id: 'reach', label: 'Could not contact the partner', category: 'delivery'),
        SupportDrillChoice(id: 'conduct', label: 'Behaviour or safety', category: 'delivery', needsNotes: true),
        SupportDrillChoice(id: 'pin', label: 'Delivery PIN or door drop', category: 'delivery'),
      ],
    ),
    const SupportDrillChoice(
      id: 'account',
      label: 'Account or app',
      category: 'account',
      children: [
        SupportDrillChoice(id: 'otp', label: 'Login or OTP', category: 'account'),
        SupportDrillChoice(id: 'address', label: 'Address or map pin', category: 'account'),
        SupportDrillChoice(id: 'crash', label: 'App error or crash', category: 'account', needsNotes: true),
      ],
    ),
    const SupportDrillChoice(
      id: 'other',
      label: 'Something else',
      category: 'general',
      needsNotes: true,
    ),
  ];
}

SupportDrillChoice? supportDrillAt(List<String> path, {required bool hasOrder}) {
  var nodes = supportDrillTree(hasOrder: hasOrder);
  SupportDrillChoice? current;
  for (final id in path) {
    SupportDrillChoice? next;
    for (final node in nodes) {
      if (node.id == id) {
        next = node;
        break;
      }
    }
    if (next == null) return null;
    current = next;
    nodes = next.children;
  }
  return current;
}

List<SupportDrillChoice> supportDrillOptions(List<String> path, {required bool hasOrder}) {
  if (path.isEmpty) return supportDrillTree(hasOrder: hasOrder);
  return supportDrillAt(path, hasOrder: hasOrder)?.children ?? const [];
}

List<String> supportDrillPathLabels(List<String> path, {required bool hasOrder}) {
  final labels = <String>[];
  var nodes = supportDrillTree(hasOrder: hasOrder);
  for (final id in path) {
    SupportDrillChoice? next;
    for (final node in nodes) {
      if (node.id == id) {
        next = node;
        break;
      }
    }
    if (next == null) break;
    labels.add(next.label);
    nodes = next.children;
  }
  return labels;
}

String supportDrillCategory(List<String> path, {required bool hasOrder}) {
  var category = 'general';
  var nodes = supportDrillTree(hasOrder: hasOrder);
  for (final id in path) {
    SupportDrillChoice? next;
    for (final node in nodes) {
      if (node.id == id) {
        next = node;
        break;
      }
    }
    if (next == null) break;
    if ((next.category ?? '').isNotEmpty) category = next.category!;
    nodes = next.children;
  }
  return category;
}

bool supportDrillIsLeaf(List<String> path, {required bool hasOrder}) {
  final node = supportDrillAt(path, hasOrder: hasOrder);
  return node != null && node.isLeaf;
}

bool supportDrillNeedsNotes(List<String> path, {required bool hasOrder}) {
  return supportDrillAt(path, hasOrder: hasOrder)?.needsNotes ?? false;
}

bool supportDrillCanSubmit(List<String> path, String notes, {required bool hasOrder}) {
  if (!supportDrillIsLeaf(path, hasOrder: hasOrder)) return false;
  return notes.trim().length >= _kSupportNotesMin;
}

String supportDrillTicketSubject({
  required List<String> path,
  String? orderNumber,
  required bool hasOrder,
}) {
  final labels = supportDrillPathLabels(path, hasOrder: hasOrder);
  final issue = labels.isEmpty ? 'support' : labels.last;
  final number = orderNumber?.trim() ?? '';
  if (number.isEmpty) return 'HotPotChef support — $issue';
  return 'HotPotChef support — Order $number — $issue';
}

String supportDrillTicketBody({
  required List<String> path,
  required String notes,
  String? orderNumber,
  String? orderUuid,
  required bool hasOrder,
}) {
  final labels = supportDrillPathLabels(path, hasOrder: hasOrder);
  final buffer = StringBuffer('Support intake\n');
  for (var i = 0; i < labels.length; i++) {
    buffer.writeln('${i == 0 ? 'Topic' : 'Issue ${i}'}: ${labels[i]}');
  }
  final detail = notes.trim();
  if (detail.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Details:')
      ..writeln(detail);
  }
  final number = orderNumber?.trim() ?? '';
  final uuid = orderUuid?.trim() ?? '';
  if (number.isNotEmpty || uuid.isNotEmpty) {
    buffer.writeln();
    if (number.isNotEmpty) buffer.writeln('Order: $number');
    if (uuid.isNotEmpty && uuid.toUpperCase() != number.toUpperCase()) {
      buffer.writeln('Internal order id: $uuid');
    }
  }
  return buffer.toString().trim();
}

/// Public ops replies wait on the diner unless the ticket is already in that state.
bool shouldMarkPendingCustomerAfterOpsPublicReply(String? status) {
  return (status ?? '').toLowerCase() != 'pending_customer';
}

String formatTicketSlaDue(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return '';
  final dt = DateTime.tryParse(text);
  if (dt == null) return text;
  return formatAppDateTime(dt);
}

bool dinerHasSupportReplyWaiting({
  required String? status,
  String? lastMessageAt,
  String? lastSeenMessageAt,
}) {
  if ((status ?? '').toLowerCase() != 'pending_customer') return false;
  final latest = (lastMessageAt ?? '').trim();
  if (latest.isEmpty) return true;
  return latest != (lastSeenMessageAt ?? '').trim();
}

String supportRepliedNoticeCopy({required String? publicId, int extraCount = 0}) {
  final id = (publicId ?? '').trim();
  if (id.isEmpty) {
    return extraCount > 0 ? 'Support replied to your tickets.' : 'Support replied to your ticket.';
  }
  if (extraCount > 0) return 'Support replied on $id and $extraCount more.';
  return 'Support replied on $id.';
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
  context.push(legalPathFor(type));
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
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: Container(
        decoration: AppTheme.bottomSheetDecoration(isDark: isDark),
        child: ContactSupportSheet(
          orderNumber: (number == null || number.isEmpty) ? null : number,
          orderUuid: orderUuid,
        ),
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
  final List<String> _path = [];
  final TextEditingController _notes = TextEditingController();

  bool get _hasOrder => parseOrderUuid(widget.orderUuid) != null || (widget.orderNumber ?? '').trim().isNotEmpty;

  bool get _leaf => supportDrillIsLeaf(_path, hasOrder: _hasOrder);

  bool get _ready => supportDrillCanSubmit(_path, _notes.text, hasOrder: _hasOrder);

  String get _subject => _leaf
      ? supportDrillTicketSubject(path: _path, orderNumber: widget.orderNumber, hasOrder: _hasOrder)
      : supportContactSubject(orderNumber: widget.orderNumber);

  String get _message => _ready
      ? supportDrillTicketBody(
          path: _path,
          notes: _notes.text,
          orderNumber: widget.orderNumber,
          orderUuid: widget.orderUuid,
          hasOrder: _hasOrder,
        )
      : supportContactMessage(orderNumber: widget.orderNumber, orderUuid: widget.orderUuid);

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _openTicket() async {
    if (_submitting || !_ready) return;
    setState(() => _submitting = true);
    try {
      final row = await createSupportTicket(
        subject: _subject,
        body: _message,
        orderId: widget.orderUuid,
        orderNumber: widget.orderNumber,
        category: supportDrillCategory(_path, hasOrder: _hasOrder),
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
    final options = supportDrillOptions(_path, hasOrder: _hasOrder);
    final labels = supportDrillPathLabels(_path, hasOrder: _hasOrder);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
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
                    color: onSurface.withValues(alpha: 0.12),
                    borderRadius: AppTheme.radiusXl,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_path.isNotEmpty)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: _submitting
                          ? null
                          : () => setState(() {
                                _path.removeLast();
                              }),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  Expanded(
                    child: Text(
                      'Contact support',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: onSurface),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                supportLinkedOrderCopy(orderNumber: widget.orderNumber),
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 6),
              Text(
                'Ops replies within 1 business day (SLA)',
                style: AppTheme.caption,
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
                        color: AppTheme.link,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ],
              if (labels.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(labels[i], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (!_leaf) ...[
                Text(
                  _path.isEmpty ? 'What do you need help with?' : 'Tell us a bit more',
                  style: TextStyle(fontWeight: FontWeight.w800, color: onSurface),
                ),
                const SizedBox(height: 8),
                for (final option in options)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(option.label, style: TextStyle(fontWeight: FontWeight.w700, color: onSurface)),
                    trailing: Icon(
                      option.isLeaf ? Icons.check_circle_outline : Icons.chevron_right,
                      color: AppTheme.primary,
                    ),
                    onTap: _submitting
                        ? null
                        : () => setState(() {
                              _path.add(option.id);
                            }),
                  ),
              ] else ...[
                Text(
                  supportDrillNeedsNotes(_path, hasOrder: _hasOrder)
                      ? 'Please describe what happened'
                      : 'Add a short note for ops',
                  style: TextStyle(fontWeight: FontWeight.w800, color: onSurface),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notes,
                  enabled: !_submitting,
                  minLines: 3,
                  maxLines: 5,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'What went wrong, when, and what you need from us.',
                    border: OutlineInputBorder(borderRadius: AppTheme.radiusMd),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _notes.text.trim().length >= _kSupportNotesMin
                      ? 'Ready to open the ticket.'
                      : 'At least $_kSupportNotesMin characters so ops can act.',
                  style: AppTheme.caption,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: (_submitting || !_ready) ? null : _openTicket,
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
              ],
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  child: const Icon(Icons.email_outlined, color: AppTheme.primary),
                ),
                title: Text('Email us', style: TextStyle(fontWeight: FontWeight.w700, color: onSurface)),
                subtitle: Text(SupportConfig.email),
                onTap: (_submitting || !_ready)
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
                  onTap: (_submitting || !_ready) ? null : () => launchSupportWhatsApp(message: _message),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
