// Minimal in-app legal copy for DPDP / FSSAI consumer notice.
// Replace URLs and operator details before a public store listing.

enum LegalDocumentId {
  terms,
  privacy,
  faq,
  cancellation,
  contact,
}

class LegalDocument {
  const LegalDocument({
    required this.id,
    required this.routePath,
    required this.title,
    required this.body,
  });

  final LegalDocumentId id;
  final String routePath;
  final String title;
  final String body;
}

abstract final class LegalDocuments {
  static const termsPath = '/legal/terms';
  static const privacyPath = '/legal/privacy';
  static const faqPath = '/legal/faq';
  static const cancellationPath = '/legal/cancellation';
  static const contactPath = '/legal/contact';

  static const allPaths = {
    termsPath,
    privacyPath,
    faqPath,
    cancellationPath,
    contactPath,
  };

  static const terms = LegalDocument(
    id: LegalDocumentId.terms,
    routePath: termsPath,
    title: 'Terms & conditions',
    body: '''
These terms govern use of the HotPotChef marketplace (customer, chef, and delivery partner apps, plus the website).

HotPotChef is a platform that lists home-cooked meals from independent kitchens. Chefs are responsible for food safety, FSSAI licensing where required, allergen disclosure, and fulfilling accepted orders. Delivery partners are independent contractors.

Prices, availability, and time slots shown in the catalog apply only to meals with status Available. Archived, closed, paused, or cancelled listings are not offers.

Checkout uses Razorpay. Test-mode payments are not live charges. Refunds and cancellations follow the Cancellation & Reschedule Policy.

We may suspend accounts that abuse inventory, payments, or other users.

These terms are a working draft for closed Test-mode dogfood. A lawyer-reviewed version is required before a public India launch.
''',
  );

  static const privacy = LegalDocument(
    id: LegalDocumentId.privacy,
    routePath: privacyPath,
    title: 'Privacy policy',
    body: '''
HotPotChef processes personal data to run a food marketplace: account email/phone, delivery addresses, order history, device push tokens, and (for chefs/drivers) KYC fields such as kitchen name and FSSAI numbers.

Legal basis (India DPDP Act, 2023): we process this data to provide the service you request, to complete payments, and to meet food-safety obligations. We do not sell personal data.

Data is stored on Supabase (currently hosted in ap-northeast-1 / Tokyo). A region move to India is a separate ops decision and is not claimed here.

Payment card data is handled by Razorpay; HotPotChef stores order ids, payment ids, and payout account references — not full card numbers.

You may request access or deletion of your account data by using Contact Us. Push tokens are cleared on logout.

This notice is a working draft. A DPDP-compliant notice with a named Data Fiduciary and grievance officer is required before public launch.
''',
  );

  static const faq = LegalDocument(
    id: LegalDocumentId.faq,
    routePath: faqPath,
    title: 'FAQs',
    body: '''
What is HotPotChef?
A three-sided marketplace for home chefs, diners, and delivery partners.

Do I need an account to browse?
Guests can browse Available meals and build a cart. Checkout requires sign-in.

How do chef payouts work?
When Razorpay Route is configured, chef shares are held on the payment and released after the order is marked delivered — not when a catalog meal is paused or archived.

Why did search hide a dish I saw yesterday?
Search and the feed only show Available meals. Archived, closed, paused, cancelled, and sold-out plates are excluded.

Is this live UPI / production Razorpay?
No. The current integration is Test mode until webhook secrets, Route KYC, and a store listing are complete.

How do I reset my password?
Use Sign in → forgot password. The app opens /reset-password after the email link.
''',
  );

  static const cancellation = LegalDocument(
    id: LegalDocumentId.cancellation,
    routePath: cancellationPath,
    title: 'Cancellation & reschedule policy',
    body: '''
Customers may cancel while an order is still awaiting chef approval. After the kitchen accepts, cancellation is at the chef's discretion and may be refused if cooking has started.

Chefs should not cancel after marking food ready for pickup except for genuine kitchen issues. Inventory is restocked when a supported cancel RPC succeeds.

Reschedules are not automatic. Message the chef in in-app chat if a time slot must move; a new order may be required.

Refunds for paid Razorpay orders are processed by the operator after a confirmed cancel. Test-mode payments are not live bank credits.

Delivery partner no-shows are handled by the platform assigning another driver when possible.
''',
  );

  static const contact = LegalDocument(
    id: LegalDocumentId.contact,
    routePath: contactPath,
    title: 'Contact us',
    body: '''
For order issues, use in-app chat on the order first so the chef and driver can respond.

For account, privacy, or KYC questions, email support@hotpotchef.app from the same address you use to sign in. Include your user id from Account if you have one.

This address is the product contact for Test-mode dogfood. A public grievance officer (DPDP) will be named before store launch.

Do not send passwords, full Aadhaar numbers, or live Razorpay secrets by email.
''',
  );

  static const List<LegalDocument> all = [
    terms,
    privacy,
    faq,
    cancellation,
    contact,
  ];

  static LegalDocument byId(LegalDocumentId id) =>
      all.firstWhere((doc) => doc.id == id);

  static LegalDocument? byPath(String path) {
    for (final doc in all) {
      if (doc.routePath == path) return doc;
    }
    return null;
  }
}
