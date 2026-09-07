import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/chef_academy_curriculum.dart';
import '../data/chef_academy_quizzes.dart';
import '../services/chef_academy_progress.dart';
import '../utils/app_theme.dart';

EdgeInsets _academyListPadding(BuildContext context) {
  final bottomInset = MediaQuery.paddingOf(context).bottom;
  return EdgeInsets.fromLTRB(20, 8, 20, 28 + bottomInset);
}

ButtonStyle _academyPrimaryButtonStyle(BuildContext context, {bool outlined = false}) {
  return ElevatedButton.styleFrom(
    backgroundColor: outlined ? AppTheme.surfaceOf(context) : AppTheme.primary,
    foregroundColor: outlined ? AppTheme.primary : Colors.white,
    elevation: 0,
    minimumSize: const Size(double.infinity, 52),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    side: outlined ? BorderSide(color: AppTheme.primary.withValues(alpha: 0.45)) : BorderSide.none,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}

IconData _moduleIcon(String name) {
  switch (name) {
    case 'clean_hands':
      return Icons.clean_hands_outlined;
    case 'restaurant':
      return Icons.restaurant_outlined;
    case 'schedule':
      return Icons.schedule_outlined;
    case 'receipt_long':
      return Icons.receipt_long_outlined;
    case 'handshake':
      return Icons.handshake_outlined;
    case 'inventory_2':
      return Icons.inventory_2_outlined;
    case 'soup_kitchen':
      return Icons.soup_kitchen_outlined;
    default:
      return Icons.school_outlined;
  }
}

class ChefAcademyScreen extends StatefulWidget {
  const ChefAcademyScreen({super.key});

  @override
  State<ChefAcademyScreen> createState() => _ChefAcademyScreenState();
}

class _ChefAcademyScreenState extends State<ChefAcademyScreen> {
  ChefAcademySnapshot _snap = const ChefAcademySnapshot();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await ChefAcademyProgress.load();
    if (!mounted) return;
    setState(() {
      _snap = snap;
      _loading = false;
    });
  }

  Future<void> _openModule(AcademyModule module) async {
    final updated = await Navigator.of(context).push<ChefAcademySnapshot>(
      MaterialPageRoute(
        builder: (_) => _AcademyModuleScreen(module: module, snapshot: _snap),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() => _snap = updated);
  }

  Future<void> _openCertificate() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _AcademyCertificateScreen(snapshot: _snap)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canvas = AppTheme.canvasOf(context);
    final onSurface = AppTheme.onSurfaceOf(context);
    final percent = academyCourseProgressPercent(
      completedLessonKeys: _snap.completedLessons,
      passedQuizKeys: _snap.passedQuizzes,
    );

    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        title: const Text(kChefAcademyTitle),
        backgroundColor: canvas,
        foregroundColor: onSurface,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: _academyListPadding(context),
              children: [
                Text(
                  kChefAcademyTagline,
                  style: const TextStyle(fontSize: 14, color: AppTheme.textMuted, height: 1.4),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.14),
                        AppTheme.accent.withValues(alpha: 0.10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${percent.toStringAsFixed(0)}% complete',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: percent / 100,
                          minHeight: 8,
                          backgroundColor: AppTheme.hairlineOf(context),
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_snap.completedLessons.intersection(allAcademyLessonIds().toSet()).length}/${allAcademyLessonIds().length} lessons · '
                        '${_snap.passedQuizzes.intersection(allAcademyQuizKeys().toSet()).length}/${allAcademyQuizKeys().length} quizzes',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                      if (_snap.hasCertificate) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openCertificate,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 52),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                            label: const Text('View certificate', style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ] else if (_snap.canIssueCertificate) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Course complete — preparing your practice certificate…',
                          style: TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                for (final module in kChefAcademyModules) ...[
                  _ModuleCard(
                    module: module,
                    completedCount: academyModuleCompletedCount(module, _snap.completedLessons),
                    quizPassed: academyQuizPassed(module.id, _snap.passedQuizzes),
                    onTap: () => _openModule(module),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                const Text(
                  kChefAcademyLegalNote,
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.35),
                ),
              ],
            ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.module,
    required this.completedCount,
    required this.quizPassed,
    required this.onTap,
  });

  final AcademyModule module;
  final int completedCount;
  final bool quizPassed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lessonsDone = completedCount >= module.lessonCount;
    return Material(
      color: AppTheme.surfaceOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.hairlineOf(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_moduleIcon(module.iconName), color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onSurfaceOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      module.subtitle,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$completedCount/${module.lessonCount} lessons'
                      '${lessonsDone ? ' · lessons done' : ''}'
                      '${quizPassed ? ' · quiz passed' : ' · quiz pending'}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: lessonsDone && quizPassed ? AppTheme.primary : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTheme.onSurfaceOf(context).withValues(alpha: 0.45)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AcademyModuleScreen extends StatefulWidget {
  const _AcademyModuleScreen({
    required this.module,
    required this.snapshot,
  });

  final AcademyModule module;
  final ChefAcademySnapshot snapshot;

  @override
  State<_AcademyModuleScreen> createState() => _AcademyModuleScreenState();
}

class _AcademyModuleScreenState extends State<_AcademyModuleScreen> {
  late ChefAcademySnapshot _snap;

  @override
  void initState() {
    super.initState();
    _snap = widget.snapshot;
  }

  Future<void> _openLesson(AcademyLesson lesson) async {
    final updated = await Navigator.of(context).push<ChefAcademySnapshot>(
      MaterialPageRoute(
        builder: (_) => _AcademyLessonScreen(
          module: widget.module,
          lesson: lesson,
          snapshot: _snap,
        ),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() => _snap = updated);
  }

  Future<void> _openQuiz() async {
    final updated = await Navigator.of(context).push<ChefAcademySnapshot>(
      MaterialPageRoute(
        builder: (_) => _AcademyQuizScreen(module: widget.module, snapshot: _snap),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() => _snap = updated);
  }

  @override
  Widget build(BuildContext context) {
    final canvas = AppTheme.canvasOf(context);
    final quizDone = academyQuizPassed(widget.module.id, _snap.passedQuizzes);
    final lessonsDone =
        academyModuleCompletedCount(widget.module, _snap.completedLessons) >= widget.module.lessonCount;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_snap);
      },
      child: Scaffold(
        backgroundColor: canvas,
        appBar: AppBar(
          title: Text(widget.module.title),
          backgroundColor: canvas,
          foregroundColor: AppTheme.onSurfaceOf(context),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_snap),
          ),
        ),
        body: ListView(
          padding: _academyListPadding(context),
          children: [
            for (final lesson in widget.module.lessons) ...[
              _LessonTile(
                lesson: lesson,
                done: _snap.completedLessons.contains(academyLessonKey(widget.module.id, lesson.id)),
                hasVideo: academyLessonVideoUrl(lesson.id) != null,
                onTap: () => _openLesson(lesson),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            Material(
              color: AppTheme.surfaceOf(context),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: _openQuiz,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: quizDone
                          ? AppTheme.primary.withValues(alpha: 0.45)
                          : AppTheme.hairlineOf(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        quizDone ? Icons.quiz : Icons.quiz_outlined,
                        color: quizDone ? AppTheme.primary : AppTheme.textMuted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              quizDone ? 'Module quiz · passed' : 'Module quiz',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.onSurfaceOf(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lessonsDone
                                  ? '3 questions · need $kAcademyQuizPassCorrect correct to pass'
                                  : 'Finish lessons first, then take the quiz',
                              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({
    required this.lesson,
    required this.done,
    required this.hasVideo,
    required this.onTap,
  });

  final AcademyLesson lesson;
  final bool done;
  final bool hasVideo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.hairlineOf(context)),
          ),
          child: Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.play_circle_outline,
                color: done ? AppTheme.primary : AppTheme.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onSurfaceOf(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${lesson.minutes} min read${hasVideo ? ' · video tip' : ''}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AcademyLessonScreen extends StatefulWidget {
  const _AcademyLessonScreen({
    required this.module,
    required this.lesson,
    required this.snapshot,
  });

  final AcademyModule module;
  final AcademyLesson lesson;
  final ChefAcademySnapshot snapshot;

  @override
  State<_AcademyLessonScreen> createState() => _AcademyLessonScreenState();
}

class _AcademyLessonScreenState extends State<_AcademyLessonScreen> {
  late ChefAcademySnapshot _snap;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _snap = widget.snapshot;
  }

  bool get _isDone =>
      _snap.completedLessons.contains(academyLessonKey(widget.module.id, widget.lesson.id));

  Future<void> _toggleComplete() async {
    if (_saving) return;
    setState(() => _saving = true);
    final next = _isDone
        ? await ChefAcademyProgress.markLessonIncomplete(
            moduleId: widget.module.id,
            lessonId: widget.lesson.id,
          )
        : await ChefAcademyProgress.markLessonComplete(
            moduleId: widget.module.id,
            lessonId: widget.lesson.id,
          );
    if (!mounted) return;
    setState(() {
      _snap = next;
      _saving = false;
    });
  }

  Future<void> _openVideo() async {
    final url = academyLessonVideoUrl(widget.lesson.id);
    if (url == null) return;
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final canvas = AppTheme.canvasOf(context);
    final onSurface = AppTheme.onSurfaceOf(context);
    final videoUrl = academyLessonVideoUrl(widget.lesson.id);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_snap);
      },
      child: Scaffold(
        backgroundColor: canvas,
        appBar: AppBar(
          title: Text(widget.lesson.title),
          backgroundColor: canvas,
          foregroundColor: onSurface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_snap),
          ),
        ),
        body: ListView(
          padding: _academyListPadding(context),
          children: [
            Text(
              '${widget.module.title} · ${widget.lesson.minutes} min',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text(
              widget.lesson.body,
              style: TextStyle(fontSize: 15, height: 1.55, color: onSurface),
            ),
            if (videoUrl != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _openVideo,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.ondemand_video_outlined),
                label: const Text('Watch related video tip', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _toggleComplete,
                style: _academyPrimaryButtonStyle(context, outlined: _isDone),
                icon: Icon(_isDone ? Icons.undo : Icons.check),
                label: Text(
                  _isDone ? 'Mark as not done' : 'Mark lesson complete',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcademyQuizScreen extends StatefulWidget {
  const _AcademyQuizScreen({
    required this.module,
    required this.snapshot,
  });

  final AcademyModule module;
  final ChefAcademySnapshot snapshot;

  @override
  State<_AcademyQuizScreen> createState() => _AcademyQuizScreenState();
}

class _AcademyQuizScreenState extends State<_AcademyQuizScreen> {
  late ChefAcademySnapshot _snap;
  final Map<String, int> _answers = {};
  String? _resultMessage;
  bool _passed = false;
  bool _saving = false;

  List<AcademyQuizQuestion> get _questions => quizzesForModule(widget.module.id);

  @override
  void initState() {
    super.initState();
    _snap = widget.snapshot;
    _passed = academyQuizPassed(widget.module.id, _snap.passedQuizzes);
  }

  Future<void> _submit() async {
    if (_answers.length < _questions.length) {
      setState(() => _resultMessage = 'Answer every question before submitting.');
      return;
    }
    final score = scoreAcademyQuiz(_questions, _answers);
    final ok = academyQuizAttemptPassed(_questions, _answers);
    setState(() {
      _passed = ok;
      _resultMessage = ok
          ? 'Passed with $score/${_questions.length}. Nice work.'
          : 'Scored $score/${_questions.length}. Need $kAcademyQuizPassCorrect correct — review lessons and retry.';
    });
    if (!ok || _saving) return;
    setState(() => _saving = true);
    final next = await ChefAcademyProgress.markQuizPassed(widget.module.id);
    if (!mounted) return;
    setState(() {
      _snap = next;
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canvas = AppTheme.canvasOf(context);
    final onSurface = AppTheme.onSurfaceOf(context);
    final lessonsDone =
        academyModuleCompletedCount(widget.module, _snap.completedLessons) >= widget.module.lessonCount;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_snap);
      },
      child: Scaffold(
        backgroundColor: canvas,
        appBar: AppBar(
          title: Text('${widget.module.title} quiz'),
          backgroundColor: canvas,
          foregroundColor: onSurface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_snap),
          ),
        ),
        body: ListView(
          padding: _academyListPadding(context),
          children: [
            if (!lessonsDone)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Tip: finish the module lessons first — quiz answers come from that material.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
              ),
            if (_passed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'You already passed this quiz. Retake anytime to practice.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary),
                ),
              ),
            for (final q in _questions) ...[
              Text(
                q.prompt,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: onSurface),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < q.choices.length; i++)
                RadioListTile<int>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: i,
                  groupValue: _answers[q.id],
                  activeColor: AppTheme.primary,
                  title: Text(q.choices[i], style: TextStyle(fontSize: 14, color: onSurface)),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _answers[q.id] = v;
                      _resultMessage = null;
                    });
                  },
                ),
              const SizedBox(height: 12),
            ],
            if (_resultMessage != null) ...[
              Text(
                _resultMessage!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _passed ? AppTheme.primary : Colors.redAccent,
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: _academyPrimaryButtonStyle(context),
                child: Text(
                  _saving ? 'Saving…' : 'Submit quiz',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcademyCertificateScreen extends StatelessWidget {
  const _AcademyCertificateScreen({required this.snapshot});

  final ChefAcademySnapshot snapshot;

  Future<void> _share(BuildContext context) async {
    final user = Supabase.instance.client.auth.currentUser;
    final name = user?.userMetadata?['full_name']?.toString() ??
        user?.userMetadata?['name']?.toString() ??
        user?.email?.split('@').first ??
        'Home chef';
    final code = snapshot.certificateCode ?? '';
    final issued = snapshot.certificateIssuedAt ?? DateTime.now();
    final text = academyCertificateShareText(
      chefName: name,
      certificateCode: code,
      issuedAt: issued.toLocal(),
    );
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    final canvas = AppTheme.canvasOf(context);
    final onSurface = AppTheme.onSurfaceOf(context);
    final user = Supabase.instance.client.auth.currentUser;
    final name = user?.userMetadata?['full_name']?.toString() ??
        user?.userMetadata?['name']?.toString() ??
        user?.email?.split('@').first ??
        'Home chef';
    final issued = snapshot.certificateIssuedAt?.toLocal();
    final date = issued == null
        ? ''
        : '${issued.day.toString().padLeft(2, '0')}/${issued.month.toString().padLeft(2, '0')}/${issued.year}';

    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        title: const Text('Academy certificate'),
        backgroundColor: canvas,
        foregroundColor: onSurface,
        elevation: 0,
      ),
      body: ListView(
        padding: _academyListPadding(context),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.16),
                  AppTheme.accent.withValues(alpha: 0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.workspace_premium_outlined, color: AppTheme.primary),
                    SizedBox(width: 8),
                    Text(
                      'HotPotChef Kitchen Academy',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  'Completed Kitchen Academy: hygiene, bulk cooking, timing, orders, handling, packaging, and equipment for home kitchens.',
                  style: TextStyle(fontSize: 14, height: 1.45, color: onSurface.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 16),
                Text(
                  'Certificate ${snapshot.certificateCode ?? ''}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textMuted),
                ),
                if (date.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Issued $date', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            kChefAcademyCertificateNote,
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _share(context),
              style: _academyPrimaryButtonStyle(context),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share certificate', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final code = snapshot.certificateCode ?? '';
                await Clipboard.setData(ClipboardData(text: code));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Certificate code copied')),
                );
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copy code', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
