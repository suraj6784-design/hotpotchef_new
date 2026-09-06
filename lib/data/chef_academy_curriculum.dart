/// Curated home-chef course content for HotPotChef Kitchen Academy.
/// Practical, FSSAI-aware guidance — not a substitute for formal food-safety certification.

class AcademyLesson {
  const AcademyLesson({
    required this.id,
    required this.title,
    required this.minutes,
    required this.body,
  });

  final String id;
  final String title;
  final int minutes;
  final String body;
}

class AcademyModule {
  const AcademyModule({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.lessons,
  });

  final String id;
  final String title;
  final String subtitle;
  final String iconName;
  final List<AcademyLesson> lessons;

  int get lessonCount => lessons.length;
}

const kChefAcademyTitle = 'Kitchen Academy';
const kChefAcademyTagline =
    'Short, practical lessons for home kitchens — hygiene, timing, orders, packing, and tools.';

/// Shown under the course list and on the certificate screen.
const kChefAcademyLegalNote =
    'Kitchen Academy helps you run a safer home kitchen on HotPotChef. '
    'It is practice training only — not an FSSAI licence, not a government certificate, '
    'and not a substitute for registration or food-safety rules that apply to you. '
    'Progress syncs to your chef account when you are online.';

const kChefAcademyCertificateNote =
    'This is a HotPotChef practice certificate for completing Kitchen Academy. '
    'It does not replace an FSSAI licence or any legal food-safety requirement.';

const List<AcademyModule> kChefAcademyModules = [
  AcademyModule(
    id: 'hygiene',
    title: 'Hygiene & food safety',
    subtitle: 'Clean kitchen habits diners can trust',
    iconName: 'clean_hands',
    lessons: [
      AcademyLesson(
        id: 'hygiene_handwash',
        title: 'Handwash and personal hygiene',
        minutes: 4,
        body:
            'Wash hands with soap for 20 seconds before prep, after raw protein, after touching phone/door, and before packing.\n\n'
            'Keep nails short. Tie hair back. Wear a clean apron. Cover cuts with a waterproof bandage, then a glove.\n\n'
            'Never cook when you have fever, vomiting, or an open infected wound. Pause the kitchen on HotPotChef until you recover.',
      ),
      AcademyLesson(
        id: 'hygiene_zones',
        title: 'Clean zones and cross-contamination',
        minutes: 5,
        body:
            'Separate raw and cooked: different boards/knives for veg vs raw chicken/mutton/eggs.\n\n'
            'Wipe counters with soap, then a food-safe sanitiser. Change cloths every service; do not reuse a wet dirty towel.\n\n'
            'Store raw protein on the bottom fridge shelf. Keep ready-to-eat food covered above it.\n\n'
            'Allergens (nuts, dairy, gluten): wash tools between dishes and note allergens clearly in the meal description.',
      ),
      AcademyLesson(
        id: 'hygiene_temps',
        title: 'Safe temperatures and leftovers',
        minutes: 5,
        body:
            'Cook poultry and minced meat thoroughly. Hot food for dispatch should stay steaming; cool leftovers quickly in shallow containers.\n\n'
            'Fridge: keep cold foods cold. Do not leave cooked food in the “danger zone” (roughly room temperature) for long stretches.\n\n'
            'Label containers with cook date. When in doubt, do not serve. HotPotChef leftovers/flash offers must still be safe and fresh — not spoiled food.',
      ),
      AcademyLesson(
        id: 'hygiene_fssai',
        title: 'FSSAI basics for home kitchens',
        minutes: 4,
        body:
            'Add your valid 14-digit FSSAI licence on Chef Profile. Diners see it on your kitchen card, story, and plate shares.\n\n'
            'Keep a copy of the licence, clear kitchen photos, and honest meal descriptions. That builds trust faster than discounts.\n\n'
            'Register and follow FSSAI rules for your kitchen type (including home kitchen / petty FBOs where they apply). '
            'HotPotChef does not register you with FSSAI and does not replace your duty as the food business operator.\n\n'
            'Apply or verify on FoSCoS (foscos.fssai.gov.in). Kitchen Academy lessons support good practice — they are not the licence itself.',
      ),
    ],
  ),
  AcademyModule(
    id: 'bulk_consistency',
    title: 'Bulk cooking & consistency',
    subtitle: 'Same taste on plate 1 and plate 20',
    iconName: 'restaurant',
    lessons: [
      AcademyLesson(
        id: 'bulk_mise',
        title: 'Mise en place before you scale',
        minutes: 4,
        body:
            'Write a batch sheet: portions promised, spice weights, oil, salt, water ratios.\n\n'
            'Chop, weigh, and stage ingredients before oil hits the kadhai. Scaling fails when you “eyeball” mid-rush.\n\n'
            'Cook base gravies in a controlled batch, then finish per slot so texture stays fresh.',
      ),
      AcademyLesson(
        id: 'bulk_taste',
        title: 'Taste locks and salt discipline',
        minutes: 4,
        body:
            'Taste at three points: after base, after simmer, before packing. Use the same spoon style each time (or weigh salt).\n\n'
            'Keep a small “golden portion” from a good batch as reference for colour and thickness.\n\n'
            'For weekly plans, freeze a sample gravy cube as your flavour memory — thaw and compare when remaking.',
      ),
      AcademyLesson(
        id: 'bulk_portions',
        title: 'Portion control that protects margin',
        minutes: 5,
        body:
            'Decide gram weight per plate (rice, sabzi, dal, raita) and use the same ladle/cup every service.\n\n'
            'Publish only the quantity you can finish well in your prep window. Overselling destroys consistency and ratings.\n\n'
            'For society nights and bulk/catering leads, cook in waves timed to pickup — not one giant pile that dries out.',
      ),
    ],
  ),
  AcademyModule(
    id: 'time_mgmt',
    title: 'Time management',
    subtitle: 'Slots, prep windows, and calm service',
    iconName: 'schedule',
    lessons: [
      AcademyLesson(
        id: 'time_slots',
        title: 'Publish honest time slots',
        minutes: 4,
        body:
            'Only open slots your kitchen can hit. Diners order against your published clocks — not invented ASAP times.\n\n'
            'Block buffer between lunch and dinner waves. Include packing and handoff time, not only cooking time.\n\n'
            'If a slot is full, stop accepting rather than promising “10 more minutes” forever.',
      ),
      AcademyLesson(
        id: 'time_prep',
        title: 'Prep timeline for one service',
        minutes: 5,
        body:
            'Work backwards from the first dispatch: packing (−15 min), finishing (−30), main cook (−60/+90), mise (−120).\n\n'
            'Do soak/ferment/dough work the night before when possible.\n\n'
            'Put phones on charge, bags ready, labels printed or written before orders peak.',
      ),
      AcademyLesson(
        id: 'time_delay',
        title: 'When you will be late',
        minutes: 3,
        body:
            'Message the diner early with a new ETA. Silence destroys trust more than a 15-minute delay.\n\n'
            'Use order chat. If you cannot fulfil, cancel promptly so inventory and payment recovery can run cleanly.\n\n'
            'Close the kitchen if equipment fails — do not keep accepting.',
      ),
    ],
  ),
  AcademyModule(
    id: 'order_mgmt',
    title: 'Order management',
    subtitle: 'Accept, cook, pack, hand off without chaos',
    iconName: 'receipt_long',
    lessons: [
      AcademyLesson(
        id: 'order_board',
        title: 'Run an order board',
        minutes: 4,
        body:
            'Keep HotPotChef Orders tab open during service. Sort by slot time, not only newest.\n\n'
            'Mark status honestly: accepted → preparing → ready/packed → handed to partner or self-delivery.\n\n'
            'Group same-slot plates together so you cook once and pack many.',
      ),
      AcademyLesson(
        id: 'order_notes',
        title: 'Special notes and diet tags',
        minutes: 3,
        body:
            'Read diner notes before oiling the pan: less oil, no onion/garlic, Jain, diabetic.\n\n'
            'Publish diet tags on meals so the right diners find you — fewer angry substitutions later.\n\n'
            'If a note is unclear, ask in chat before cooking.',
      ),
      AcademyLesson(
        id: 'order_inventory',
        title: 'Inventory and last-portion discipline',
        minutes: 4,
        body:
            'Update quantity as you sell. Do not leave “5 left” when you have two.\n\n'
            'Flash/leftover offers need accurate counts — oversell triggers refunds and bad reviews.\n\n'
            'For society/office group plans, confirm drop note and slot before you commit the batch.',
      ),
    ],
  ),
  AcademyModule(
    id: 'professional',
    title: 'Professional handling',
    subtitle: 'Tone, complaints, and kitchen presence',
    iconName: 'handshake',
    lessons: [
      AcademyLesson(
        id: 'pro_tone',
        title: 'Chat tone that keeps diners',
        minutes: 3,
        body:
            'Reply short and warm: confirm slot, clarify spice level, share when packed.\n\n'
            'Never argue in chat. Offer a fix: remake, partial refund path via support, or clear apology + next-order care.\n\n'
            'Use kitchen story + live clip to show real cooking — that is your advertising without shouting.',
      ),
      AcademyLesson(
        id: 'pro_complaints',
        title: 'Handle a bad order calmly',
        minutes: 4,
        body:
            'Ask what went wrong (cold, late, taste, missing item). Own the part you control.\n\n'
            'Photo evidence helps: packed-box photo before handoff protects both sides.\n\n'
            'Fix process the same day (salt sheet, hotter pack, earlier start) so the next diner is safer.',
      ),
      AcademyLesson(
        id: 'pro_presence',
        title: 'Look like a kitchen business',
        minutes: 3,
        body:
            'Clear meal titles, real photos, price that matches portion, FSSAI on profile.\n\n'
            'Open/close the kitchen deliberately. Ghost kitchens that accept then go silent lose followers.\n\n'
            'Local language on your chef card (Marathi/Hindi) builds neighbourhood trust in Pune-first markets.',
      ),
    ],
  ),
  AcademyModule(
    id: 'packaging',
    title: 'Packaging & processing',
    subtitle: 'Hot, leak-proof, presentable boxes',
    iconName: 'inventory_2',
    lessons: [
      AcademyLesson(
        id: 'pack_choose',
        title: 'Choose the right container',
        minutes: 4,
        body:
            'Use food-grade containers sized to the portion — not oversized boxes that spill and look empty.\n\n'
            'Gravy dishes need leak-proof lids. Keep dry items (roti, papad) separate from wet.\n\n'
            'Festival hampers and shelf items (pickle/masala) need sealed, labelled jars with make/best-before guidance.',
      ),
      AcademyLesson(
        id: 'pack_process',
        title: 'Pack line that stays hot',
        minutes: 4,
        body:
            'Heat containers if needed. Fill, wipe rims, seal, label name + veg/non-veg mark, bag, then photo.\n\n'
            'Packed-box photo before dispatch is a trust move — use it.\n\n'
            'Do not seal steaming food so tight that condensation turns crisp items soggy; vent briefly when needed.',
      ),
      AcademyLesson(
        id: 'pack_supply',
        title: 'Supplies without mid-service panic',
        minutes: 3,
        body:
            'Stock bags, tape, stickers, and boxes before the rush. Reorder from the packaging store when low.\n\n'
            'Keep a spare sleeve of containers for sudden society-night spikes.\n\n'
            'Recycling/disposal: separate oil waste; do not pour large oil amounts down the sink.',
      ),
    ],
  ),
  AcademyModule(
    id: 'equipment',
    title: 'Utensils & equipment',
    subtitle: 'What you need and how to use it safely',
    iconName: 'soup_kitchen',
    lessons: [
      AcademyLesson(
        id: 'equip_core',
        title: 'Core kit for a home kitchen',
        minutes: 5,
        body:
            'Must-haves: heavy kadhai/pot, steamer or cooker, sharp knives, two chopping boards, ladle set, weighing scale or measuring cups, food thermometer (helpful), clean towels, apron, gloves, first-aid.\n\n'
            'Nice-to-have for volume: larger stockpot, rice cooker, extra gas burner, insulated bags for self-delivery.\n\n'
            'Shelf items may need dry jars, funnel, and clean dry spoons dedicated to spices.',
      ),
      AcademyLesson(
        id: 'equip_use',
        title: 'Safe use and maintenance',
        minutes: 4,
        body:
            'Dry hands before lighting gas. Keep kids/pets out of the cook zone during service.\n\n'
            'Sharpen knives; dull blades cause more cuts. Store knives in a block or sheath, not loose in a drawer.\n\n'
            'Descale cookers, check regulator hoses monthly, and keep a fire extinguisher or fire blanket accessible.',
      ),
      AcademyLesson(
        id: 'equip_layout',
        title: 'Layout for speed',
        minutes: 3,
        body:
            'Set a one-way flow: wash → cut → cook → pack → handoff. Avoid crossing raw and ready paths.\n\n'
            'Keep salt/spices in a fixed tray so you do not hunt mid-recipe.\n\n'
            'Charge phone + power bank near the pack station for order updates and packed photos.',
      ),
    ],
  ),
];

AcademyModule? academyModuleById(String id) {
  for (final module in kChefAcademyModules) {
    if (module.id == id) return module;
  }
  return null;
}

AcademyLesson? academyLessonById(String moduleId, String lessonId) {
  final module = academyModuleById(moduleId);
  if (module == null) return null;
  for (final lesson in module.lessons) {
    if (lesson.id == lessonId) return lesson;
  }
  return null;
}

List<String> allAcademyLessonIds() {
  return [
    for (final module in kChefAcademyModules)
      for (final lesson in module.lessons) '${module.id}::${lesson.id}',
  ];
}

double academyProgressPercent(Set<String> completedLessonKeys) {
  final total = allAcademyLessonIds().length;
  if (total == 0) return 0;
  final done = completedLessonKeys.where(allAcademyLessonIds().contains).length;
  return (done / total * 100).clamp(0, 100);
}

int academyModuleCompletedCount(AcademyModule module, Set<String> completedLessonKeys) {
  var n = 0;
  for (final lesson in module.lessons) {
    if (completedLessonKeys.contains('${module.id}::${lesson.id}')) n++;
  }
  return n;
}

String academyLessonKey(String moduleId, String lessonId) => '$moduleId::$lessonId';
