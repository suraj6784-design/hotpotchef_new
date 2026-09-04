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
        updated: '2 September 2026',
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
            'Prices shown at checkout include food, packaging, optional delivery, tips, and any HotPot Coins you apply. Payment is collected through Razorpay. Placing an order is an offer to buy that meal; the chef may accept or decline.',
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
        ],
      );
    case LegalDocumentType.privacy:
      return const LegalDocument(
        title: 'Privacy policy',
        updated: '2 September 2026',
        sections: [
          LegalSection(
            'What we collect',
            'We collect your name, email, phone, saved addresses, order history, HotPot Coins balance, device push token, and approximate location when you use maps or delivery. Payment card data is handled by Razorpay, not stored on our servers.',
          ),
          LegalSection(
            'How we use it',
            'We use this information to place and track orders, notify you about order status, calculate delivery fees, prevent fraud, and improve the app. Chefs see the details needed to cook and hand over your order. Drivers see delivery address and contact for active deliveries.',
          ),
          LegalSection(
            'Sharing',
            'We share data with Supabase (hosting), Firebase (crash reporting and push), Razorpay (payments), and Google Maps (location). We do not sell your personal information.',
          ),
          LegalSection(
            'Retention and rights',
            'Order records are kept as required for tax and dispute handling. You can update profile fields in the app or email support to request access, correction, or deletion of your account data, subject to legal retention needs.',
          ),
          LegalSection(
            'Contact',
            'Privacy questions can be sent to our support email from Contact Us in this app.',
          ),
        ],
      );
    case LegalDocumentType.faq:
      return const LegalDocument(
        title: 'FAQs',
        updated: '2 September 2026',
        sections: [
          LegalSection(
            'How do I place an order?',
            'Add meals from a chef to your cart, choose address and contact number, then pay with Razorpay. The chef is notified after payment is recorded.',
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
