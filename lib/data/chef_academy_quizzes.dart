import 'chef_academy_curriculum.dart';

class AcademyQuizQuestion {
  const AcademyQuizQuestion({
    required this.id,
    required this.prompt,
    required this.choices,
    required this.correctIndex,
  });

  final String id;
  final String prompt;
  final List<String> choices;
  final int correctIndex;
}

/// Pass when at least 2 of 3 answers are correct.
const int kAcademyQuizPassCorrect = 2;

String academyQuizKey(String moduleId) => 'quiz::$moduleId';

List<AcademyQuizQuestion> quizzesForModule(String moduleId) =>
    kChefAcademyQuizzes[moduleId] ?? const [];

List<String> allAcademyQuizKeys() => [
      for (final module in kChefAcademyModules) academyQuizKey(module.id),
    ];

bool academyQuizPassed(String moduleId, Set<String> passedQuizKeys) =>
    passedQuizKeys.contains(academyQuizKey(moduleId));

int scoreAcademyQuiz(List<AcademyQuizQuestion> questions, Map<String, int> answers) {
  var correct = 0;
  for (final q in questions) {
    if (answers[q.id] == q.correctIndex) correct++;
  }
  return correct;
}

bool academyQuizAttemptPassed(List<AcademyQuizQuestion> questions, Map<String, int> answers) {
  if (questions.isEmpty) return false;
  return scoreAcademyQuiz(questions, answers) >= kAcademyQuizPassCorrect;
}

bool academyLessonsComplete(Set<String> completedLessonKeys) {
  final required = allAcademyLessonIds();
  return required.every(completedLessonKeys.contains);
}

bool academyQuizzesComplete(Set<String> passedQuizKeys) {
  return allAcademyQuizKeys().every(passedQuizKeys.contains);
}

bool academyCertificateEligible({
  required Set<String> completedLessonKeys,
  required Set<String> passedQuizKeys,
}) {
  return academyLessonsComplete(completedLessonKeys) && academyQuizzesComplete(passedQuizKeys);
}

/// Overall course progress: lessons + quizzes weighted equally by item count.
double academyCourseProgressPercent({
  required Set<String> completedLessonKeys,
  required Set<String> passedQuizKeys,
}) {
  final lessonIds = allAcademyLessonIds();
  final quizKeys = allAcademyQuizKeys();
  final total = lessonIds.length + quizKeys.length;
  if (total == 0) return 0;
  final done = lessonIds.where(completedLessonKeys.contains).length +
      quizKeys.where(passedQuizKeys.contains).length;
  return (done / total * 100).clamp(0, 100);
}

String academyCertificateShareText({
  required String chefName,
  required String certificateCode,
  required DateTime issuedAt,
}) {
  final date =
      '${issuedAt.day.toString().padLeft(2, '0')}/${issuedAt.month.toString().padLeft(2, '0')}/${issuedAt.year}';
  final name = chefName.trim().isEmpty ? 'Home chef' : chefName.trim();
  return [
    'HotPotChef Kitchen Academy',
    '$name completed Kitchen Academy — practical training for home kitchens.',
    'Certificate: $certificateCode',
    'Issued: $date',
    'Covered: hygiene, bulk cooking, timing, orders, handling, packaging, equipment.',
    'Practice certificate only — not an FSSAI licence or government food-safety certification.',
  ].join('\n');
}

String generateAcademyCertificateCode(String userId, DateTime issuedAt) {
  final stamp =
      '${issuedAt.year}${issuedAt.month.toString().padLeft(2, '0')}${issuedAt.day.toString().padLeft(2, '0')}';
  final short = userId.replaceAll('-', '');
  final tail = short.length >= 6 ? short.substring(short.length - 6).toUpperCase() : short.toUpperCase();
  return 'HPC-KA-$stamp-$tail';
}

/// Optional external video / guidance links for a few lessons.
const Map<String, String> kChefAcademyLessonVideos = {
  'hygiene_handwash': 'https://www.youtube.com/results?search_query=WHO+hand+washing+steps',
  'hygiene_fssai': 'https://www.fssai.gov.in/',
  'pack_choose': 'https://www.youtube.com/results?search_query=safe+food+packaging+hygiene',
  'equip_use': 'https://www.youtube.com/results?search_query=kitchen+gas+safety+home',
};

String? academyLessonVideoUrl(String lessonId) => kChefAcademyLessonVideos[lessonId];

const Map<String, List<AcademyQuizQuestion>> kChefAcademyQuizzes = {
  'hygiene': [
    AcademyQuizQuestion(
      id: 'hygiene_q1',
      prompt: 'When should you wash hands during service?',
      choices: [
        'Only at the start of the day',
        'Before prep, after raw protein, after phone/door, and before packing',
        'Only after cooking is finished',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'hygiene_q2',
      prompt: 'Where should raw meat sit in the fridge?',
      choices: [
        'On the top shelf above ready-to-eat food',
        'On the bottom shelf, covered, below ready-to-eat food',
        'Beside open salads for easy access',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'hygiene_q3',
      prompt: 'What should you do if you have fever while listed as open?',
      choices: [
        'Keep cooking but wear a double mask',
        'Pause / close the kitchen until you recover',
        'Only accept pickup orders',
      ],
      correctIndex: 1,
    ),
  ],
  'bulk_consistency': [
    AcademyQuizQuestion(
      id: 'bulk_q1',
      prompt: 'Best way to keep plate 1 and plate 20 tasting alike?',
      choices: [
        'Eyeball spices while rushing',
        'Use a batch sheet with weighed ratios and taste locks',
        'Add extra salt at the end for every box',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'bulk_q2',
      prompt: 'How do you protect portion margin?',
      choices: [
        'Fill whatever container is free',
        'Use fixed ladle/cup weights per plate',
        'Always give double rice for 5-star ratings',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'bulk_q3',
      prompt: 'For society nights / catering, cook…',
      choices: [
        'One giant batch hours early and reheat forever',
        'In waves timed to pickup so food stays fresh',
        'Only after every diner arrives',
      ],
      correctIndex: 1,
    ),
  ],
  'time_mgmt': [
    AcademyQuizQuestion(
      id: 'time_q1',
      prompt: 'What slots should you publish?',
      choices: [
        'Any ASAP time diners might want',
        'Only clocks your kitchen can honestly hit',
        'One slot for the whole day',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'time_q2',
      prompt: 'If you will be late, you should…',
      choices: [
        'Stay silent until the driver calls',
        'Message early with a new ETA',
        'Mark delivered and fix later',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'time_q3',
      prompt: 'Prep planning should work…',
      choices: [
        'Forward from waking up only',
        'Backwards from first dispatch including pack time',
        'Only when the first order lands',
      ],
      correctIndex: 1,
    ),
  ],
  'order_mgmt': [
    AcademyQuizQuestion(
      id: 'order_q1',
      prompt: 'How should you sort active orders in service?',
      choices: [
        'Newest first only',
        'By promised slot time, grouping same-slot plates',
        'Alphabetical by diner name',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'order_q2',
      prompt: 'If a diner note is unclear (Jain / spice), you should…',
      choices: [
        'Guess and hope',
        'Ask in chat before cooking',
        'Ignore notes to save time',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'order_q3',
      prompt: 'Leaving “5 left” when you have two…',
      choices: [
        'Is fine for marketing',
        'Risks oversell, refunds, and bad reviews',
        'Helps flash offers only',
      ],
      correctIndex: 1,
    ),
  ],
  'professional': [
    AcademyQuizQuestion(
      id: 'pro_q1',
      prompt: 'Best chat tone under pressure?',
      choices: [
        'Argue until the diner admits fault',
        'Short, warm, clear ETA or fix',
        'Ignore chat until after service',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'pro_q2',
      prompt: 'A packed-box photo before handoff…',
      choices: [
        'Wastes time',
        'Builds trust and protects both sides',
        'Is only for festival hampers',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'pro_q3',
      prompt: 'Ghosting diners after accepting orders…',
      choices: [
        'Is OK if you are busy',
        'Destroys followers and trust — close kitchen if you cannot fulfil',
        'Is fine for leftover flash only',
      ],
      correctIndex: 1,
    ),
  ],
  'packaging': [
    AcademyQuizQuestion(
      id: 'pack_q1',
      prompt: 'Gravy dishes need…',
      choices: [
        'Any open bowl',
        'Leak-proof lids; keep dry items separate',
        'Extra ice always',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'pack_q2',
      prompt: 'Shelf items like pickle/masala should be…',
      choices: [
        'Unlabelled so packaging looks clean',
        'Sealed and labelled with make / best-before guidance',
        'Mixed into meal boxes only',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'pack_q3',
      prompt: 'Stock bags and boxes…',
      choices: [
        'During the rush when they run out',
        'Before service; reorder when low',
        'Never — diners bring containers',
      ],
      correctIndex: 1,
    ),
  ],
  'equipment': [
    AcademyQuizQuestion(
      id: 'equip_q1',
      prompt: 'A core home-kitchen kit should include…',
      choices: [
        'Only one shared board for raw and veg',
        'Separate boards, sharp knives, measuring tools, clean towels/apron',
        'Just a kadhai and phone',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'equip_q2',
      prompt: 'Dull knives are…',
      choices: [
        'Safer than sharp knives',
        'More likely to cause cuts — keep blades sharp and sheathed',
        'Required by FSSAI',
      ],
      correctIndex: 1,
    ),
    AcademyQuizQuestion(
      id: 'equip_q3',
      prompt: 'Best kitchen flow for speed and safety?',
      choices: [
        'Random stations wherever space exists',
        'One-way: wash → cut → cook → pack → handoff',
        'Pack first, then cook',
      ],
      correctIndex: 1,
    ),
  ],
};
