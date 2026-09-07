enum LegalDocumentType { terms, privacy, faq, cancellation }

class LegalSection {
  const LegalSection(this.heading, this.body);
  final String heading;
  final String body;
}

class LegalDocument {
  const LegalDocument({required this.title, required this.updated, required this.sections});
  final String title;
  final String updated;
  final List<LegalSection> sections;
}

LegalDocument legalDocumentFor(LegalDocumentType type) {
  switch (type) {
    case LegalDocumentType.terms:
      return const LegalDocument(
        title: 'Terms & conditions',
        updated: '7 September 2026',
        sections: [
          LegalSection(
            'The marketplace',
            'HotPotChef connects customers with independent home chefs and delivery partners. Chefs prepare meals in their own kitchens. HotPotChef is not a restaurant and does not cook the food itself.',
          ),
          LegalSection(
            'Accounts',
            'You must provide accurate contact and address details. You are responsible for keeping your login private. We may suspend accounts that misuse the platform, including fraudulent payments or abuse of chefs or drivers.',
          ),
          LegalSection(
            'Orders and payment',
            'Prices shown at checkout include food, packaging, optional delivery, tips, and any HotPot Coins you apply. Payment is collected through Razorpay. Placing an order is an offer to buy that meal; the chef may accept or decline. Pay only through HotPotChef for marketplace orders so refunds, coins, tracking, and support remain available.',
          ),
          LegalSection(
            'Marketplace integrity (chefs and diners)',
            'Chefs must not solicit diners found on HotPotChef to pay outside the app (WhatsApp, UPI, cash deals for the same relationship) to avoid platform fees. Diners should complete payment in-app. We may warn, withhold promotions/boost, or suspend accounts that repeatedly bypass checkout. Phone calls are for active order coordination only — not for taking future orders offline.',
          ),
          LegalSection(
            'Invoices',
            'If the kitchen has given a GSTIN, your PDF is a tax invoice with HSN 9963 and 5% GST shown as CGST and SGST from the inclusive price. If no GSTIN is on file, you receive a bill of supply, not a GST tax invoice.',
          ),
          LegalSection(
            'Availability',
            'Portions are limited. If a meal sells out after you start checkout, you will not be charged, or a captured payment will be refunded to the original method.',
          ),
          LegalSection(
            'Cancellation',
            'Customers may cancel until the kitchen starts preparing. After that, cancellation may be refused. Chefs may cancel if they cannot fulfil the order. See the Cancellation & Reschedule Policy for refund timing.',
          ),
          LegalSection(
            'Liability',
            'Chefs are responsible for food safety, labelling, and FSSAI compliance where required. HotPotChef provides the ordering software and payment routing. To the extent allowed by Indian law, we are not liable for delays, allergen incidents, or chef kitchen issues beyond facilitating a refund or support ticket.',
          ),
          LegalSection(
            'Grievance',
            'For complaints or disputes, email hello@hotpotchef.com or open an in-app support ticket from Account → Contact Us. Ops aims to reply within one business day.',
          ),
          LegalSection(
            'Data and deletion',
            'Location and payment-related data are used only to fulfil delivery, prevent fraud, and process checkout via Razorpay. You can request account deletion or a data export from Account; we process these subject to legal retention (for example tax and dispute records).',
          ),
        ],
      );
    case LegalDocumentType.privacy:
      return const LegalDocument(
        title: 'Privacy policy',
        updated: '7 September 2026',
        sections: [
          LegalSection(
            'What we collect',
            'We collect your name, email, phone, saved addresses, order history, HotPot Coins balance, device push token, and approximate location when you use maps or delivery. Delivery partners may provide Aadhaar; we store only the last four digits, never the full number. Payment card data is handled by Razorpay, not stored on our servers.',
          ),
          LegalSection(
            'How we use it',
            'We use this information to place and track orders, notify you about order status, calculate delivery fees, prevent fraud, and improve the app. Chefs see the details needed to cook and hand over your order. Drivers see delivery address and contact for active deliveries.',
          ),
          LegalSection(
            'Location and payment purpose',
            'Approximate location supports maps, delivery fee estimates, and drop-off accuracy. Payment identifiers from Razorpay confirm successful checkout and refunds — we do not store full card numbers.',
          ),
          LegalSection(
            'Sharing',
            'We share data with Supabase (hosting), Firebase (crash reporting and push), Razorpay (payments), and Google Maps (location). We do not sell your personal information.',
          ),
          LegalSection(
            'Retention and rights (DPDP)',
            'Order records are kept as required for tax and dispute handling. You can update profile fields in the app, open an in-app ticket, or use Account → Request data export / Request account deletion to ask for access, correction, or erasure, subject to legal retention needs.',
          ),
          LegalSection(
            'Grievance',
            'Privacy and grievance contact: hello@hotpotchef.com, or in-app support tickets under Account.',
          ),
        ],
      );
    case LegalDocumentType.faq:
      return const LegalDocument(
        title: 'FAQs',
        updated: '7 September 2026',
        sections: [
          LegalSection(
            'How do I place an order?',
            'Add meals from a chef to your cart, choose address and contact number, then pay with Razorpay. The chef is notified after payment is recorded.',
          ),
          LegalSection(
            'Can I pay the chef on WhatsApp or UPI?',
            'No for HotPotChef marketplace orders. Pay in the app so refunds, HotPot Coins, live tracking, and Support stay available. Chefs must not move diners found here to off-app payment.',
          ),
          LegalSection(
            'When can I cancel?',
            'You can cancel until the chef starts preparing. Inventory is restored and an online payment is refunded to the original method, usually in 5–7 business days.',
          ),
          LegalSection(
            'What if a meal sells out at checkout?',
            'The last remaining portions are held when you tap Pay. If it sold out, nothing is charged. If money was captured after a hold expired, we issue a refund.',
          ),
          LegalSection(
            'What are HotPot Coins?',
            'Coins are a wallet balance you can apply at checkout. Cancelled orders that used coins restore those coins to your wallet.',
          ),
          LegalSection(
            'How do I reach support?',
            'Use Contact Us in Account, or Support on an order. Opening Support from an order attaches that order number to email and WhatsApp automatically. Email is always available; WhatsApp appears if a support number is configured.',
          ),
        ],
      );
    case LegalDocumentType.cancellation:
      return const LegalDocument(
        title: 'Cancellation & reschedule policy',
        updated: '2 September 2026',
        sections: [
          LegalSection(
            'Customer cancel',
            'Cancel from Orders while the status is still waiting for the chef (for example Pending Chef Approval or Confirmed). Once the kitchen is preparing, ready, or out for delivery, in-app cancel is blocked.',
          ),
          LegalSection(
            'Chef cancel',
            'If a chef cannot fulfil an order, they can cancel from the kitchen. Stock is put back and a paid order is refunded.',
          ),
          LegalSection(
            'Refunds',
            'Razorpay refunds return to the original payment method. Banks typically take 5–7 business days. HotPot Coins used on the order are restored immediately when cancel succeeds.',
          ),
          LegalSection(
            'Reschedule',
            'Time slots are chosen at checkout. To change a slot after paying, cancel while still allowed and place a new order, or contact support with your order id before the kitchen starts.',
          ),
          LegalSection(
            'Failed payments',
            'If checkout is cancelled or the network drops before payment, no order is placed. Any inventory hold is released so others can buy the meal.',
          ),
        ],
      );
  }
}
