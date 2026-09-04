import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/legal_document_screen.dart';
import 'legal_content.dart';

class SupportConfig {
  static String get email {
    final value = dotenv.env['SUPPORT_EMAIL']?.trim();
    if (value != null && value.contains('@')) return value;
    return 'hello@hotpotchef.com';
  }

  static String get whatsappDigits =>
      (dotenv.env['SUPPORT_WHATSAPP'] ?? '').replaceAll(RegExp(r'\D'), '');

  static bool get hasWhatsApp => whatsappDigits.length >= 10;

  static String? get playStoreUrl {
    final value = dotenv.env['PLAY_STORE_URL']?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static String? urlFor(LegalDocumentType type) {
    final key = switch (type) {
      LegalDocumentType.terms => 'TERMS_URL',
      LegalDocumentType.privacy => 'PRIVACY_URL',
      LegalDocumentType.faq => 'FAQ_URL',
      LegalDocumentType.cancellation => 'CANCELLATION_POLICY_URL',
    };
    final value = dotenv.env[key]?.trim();
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

Future<bool> launchPlayStore() {
  final url = SupportConfig.playStoreUrl;
  if (url == null) return Future.value(false);
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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

Future<void> showContactSupportSheet(
  BuildContext context, {
  String? orderNumber,
  String? orderUuid,
  String? orderRef,
}) {
  final number = (orderNumber ?? orderRef)?.trim();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => ContactSupportSheet(
      orderNumber: (number == null || number.isEmpty) ? null : number,
      orderUuid: orderUuid,
    ),
  );
}

class ContactSupportSheet extends StatelessWidget {
  const ContactSupportSheet({super.key, this.orderNumber, this.orderUuid});

  final String? orderNumber;
  final String? orderUuid;

  String get _message => supportContactMessage(
        orderNumber: orderNumber,
        orderUuid: orderUuid,
      );

  @override
  Widget build(BuildContext context) {
    final linkedOrder = orderNumber?.trim() ?? '';
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
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Contact support',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              supportLinkedOrderCopy(orderNumber: orderNumber),
              style: const TextStyle(color: Color(0xFF8C8279), fontSize: 13, height: 1.4),
            ),
            if (linkedOrder.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0x14F4511E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Order $linkedOrder',
                    style: const TextStyle(
                      color: Color(0xFFF4511E),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
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
                  subject: supportContactSubject(orderNumber: orderNumber),
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
