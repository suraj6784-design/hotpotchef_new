/** Same copy as lib/utils/legal_content.dart — keep in sync when policies change. */
(function (global) {
  var DOCS = {
    terms: {
      slug: 'terms',
      title: 'Terms & conditions',
      updated: '7 September 2026',
      sections: [
        {
          heading: 'The marketplace',
          body:
            'HotPotChef connects customers with independent home chefs and delivery partners. Chefs prepare meals in their own kitchens. HotPotChef is not a restaurant and does not cook the food itself.',
        },
        {
          heading: 'Accounts',
          body:
            'You must provide accurate contact and address details. You are responsible for keeping your login private. We may suspend accounts that misuse the platform, including fraudulent payments or abuse of chefs or drivers.',
        },
        {
          heading: 'Orders and payment',
          body:
            'Prices shown at checkout include food, packaging, optional delivery, tips, and any HotPot Coins you apply. Payment is collected through Razorpay. Placing an order is an offer to buy that meal; the chef may accept or decline. Pay only through HotPotChef for marketplace orders so refunds, coins, tracking, and support remain available.',
        },
        {
          heading: 'Marketplace integrity (chefs and diners)',
          body:
            'Chefs must not solicit diners found on HotPotChef to pay outside the app (WhatsApp, UPI, cash deals for the same relationship) to avoid platform fees. Diners should complete payment in-app. We may warn, withhold promotions/boost, or suspend accounts that repeatedly bypass checkout. Phone calls are for active order coordination only — not for taking future orders offline.',
        },
        {
          heading: 'Invoices',
          body:
            'If the kitchen has given a GSTIN, your PDF is a tax invoice with HSN 9963 and 5% GST shown as CGST and SGST from the inclusive price. If no GSTIN is on file, you receive a bill of supply, not a GST tax invoice.',
        },
        {
          heading: 'Availability',
          body:
            'Portions are limited. If a meal sells out after you start checkout, you will not be charged, or a captured payment will be refunded to the original method.',
        },
        {
          heading: 'Cancellation',
          body:
            'Customers may cancel until the kitchen starts preparing. After that, cancellation may be refused. Chefs may cancel if they cannot fulfil the order. See the Cancellation & Reschedule Policy for refund timing.',
        },
        {
          heading: 'Liability',
          body:
            'Chefs are responsible for food safety, labelling, and FSSAI compliance where required. HotPotChef provides the ordering software and payment routing. To the extent allowed by Indian law, we are not liable for delays, allergen incidents, or chef kitchen issues beyond facilitating a refund or support ticket.',
        },
        {
          heading: 'Grievance',
          body:
            'For complaints or disputes, email hello@hotpotchef.com or open an in-app support ticket from Account → Contact Us. Ops aims to reply within one business day.',
        },
        {
          heading: 'Data and deletion',
          body:
            'Location and payment-related data are used only to fulfil delivery, prevent fraud, and process checkout via Razorpay. You can request account deletion or a data export from Account; we process these subject to legal retention (for example tax and dispute records).',
        },
      ],
    },
    privacy: {
      slug: 'privacy',
      title: 'Privacy policy',
      updated: '7 September 2026',
      sections: [
        {
          heading: 'What we collect',
          body:
            'We collect your name, email, phone, saved addresses, order history, HotPot Coins balance, device push token, and approximate location when you use maps or delivery. Delivery partners may provide Aadhaar; we store only the last four digits, never the full number. Payment card data is handled by Razorpay, not stored on our servers.',
        },
        {
          heading: 'How we use it',
          body:
            'We use this information to place and track orders, notify you about order status, calculate delivery fees, prevent fraud, and improve the app. Chefs see the details needed to cook and hand over your order. Drivers see delivery address and contact for active deliveries.',
        },
        {
          heading: 'Location and payment purpose',
          body:
            'Approximate location supports maps, delivery fee estimates, and drop-off accuracy. Payment identifiers from Razorpay confirm successful checkout and refunds — we do not store full card numbers.',
        },
        {
          heading: 'Sharing',
          body:
            'We share data with Supabase (hosting), Firebase (crash reporting and push), Razorpay (payments), and Google Maps (location). We do not sell your personal information.',
        },
        {
          heading: 'Retention and rights (DPDP)',
          body:
            'Order records are kept as required for tax and dispute handling. You can update profile fields in the app, open an in-app ticket, or use Account → Request data export / Request account deletion to ask for access, correction, or erasure, subject to legal retention needs.',
        },
        {
          heading: 'Grievance',
          body:
            'Privacy and grievance contact: hello@hotpotchef.com, or in-app support tickets under Account.',
        },
      ],
    },
    faq: {
      slug: 'faq',
      title: 'FAQs',
      updated: '7 September 2026',
      sections: [
        {
          heading: 'How do I place an order?',
          body:
            'Add meals from a chef to your cart, choose address and contact number, then pay with Razorpay. The chef is notified after payment is recorded.',
        },
        {
          heading: 'Can I pay the chef on WhatsApp or UPI?',
          body:
            'No for HotPotChef marketplace orders. Pay in the app so refunds, HotPot Coins, live tracking, and Support stay available. Chefs must not move diners found here to off-app payment.',
        },
        {
          heading: 'When can I cancel?',
          body:
            'You can cancel until the chef starts preparing. Inventory is restored and an online payment is refunded to the original method, usually in 5–7 business days.',
        },
        {
          heading: 'What if a meal sells out at checkout?',
          body:
            'The last remaining portions are held when you tap Pay. If it sold out, nothing is charged. If money was captured after a hold expired, we issue a refund.',
        },
        {
          heading: 'What are HotPot Coins?',
          body:
            'Coins are a wallet balance you can apply at checkout. Cancelled orders that used coins restore those coins to your wallet.',
        },
        {
          heading: 'How do I reach support?',
          body:
            'Use Contact Us in Account, or Support on an order. Opening Support from an order attaches that order number to email and WhatsApp automatically. Email is always available; WhatsApp appears if a support number is configured.',
        },
      ],
    },
    cancellation: {
      slug: 'cancellation',
      title: 'Cancellation & reschedule policy',
      updated: '2 September 2026',
      sections: [
        {
          heading: 'Customer cancel',
          body:
            'Cancel from Orders while the status is still waiting for the chef (for example Pending Chef Approval or Confirmed). Once the kitchen is preparing, ready, or out for delivery, in-app cancel is blocked.',
        },
        {
          heading: 'Chef cancel',
          body:
            'If a chef cannot fulfil an order, they can cancel from the kitchen. Stock is put back and a paid order is refunded.',
        },
        {
          heading: 'Refunds',
          body:
            'Razorpay refunds return to the original payment method. Banks typically take 5–7 business days. HotPot Coins used on the order are restored immediately when cancel succeeds.',
        },
        {
          heading: 'Reschedule',
          body:
            'Time slots are chosen at checkout. To change a slot after paying, cancel while still allowed and place a new order, or contact support with your order id before the kitchen starts.',
        },
        {
          heading: 'Failed payments',
          body:
            'If checkout is cancelled or the network drops before payment, no order is placed. Any inventory hold is released so others can buy the meal.',
        },
      ],
    },
  };

  var ALIASES = {
    terms: 'terms',
    'terms-and-conditions': 'terms',
    privacy: 'privacy',
    'privacy-policy': 'privacy',
    faq: 'faq',
    faqs: 'faq',
    cancellation: 'cancellation',
    'cancellation-policy': 'cancellation',
    'reschedule-policy': 'cancellation',
  };

  function docFromPath(pathname) {
    var path = (pathname || '').replace(/\/+$/, '').split('/').pop() || '';
    var key = ALIASES[path.toLowerCase()];
    return key ? DOCS[key] : null;
  }

  global.HotPotLegal = {
    docs: DOCS,
    docFromPath: docFromPath,
    nav: [
      { href: '/terms', label: 'Terms' },
      { href: '/privacy', label: 'Privacy' },
      { href: '/faq', label: 'FAQs' },
      { href: '/cancellation', label: 'Cancellation' },
    ],
  };
})(window);
