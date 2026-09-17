import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/chef_academy_curriculum.dart';
import '../data/chef_academy_quizzes.dart';

class ChefAcademySnapshot {
  const ChefAcademySnapshot({
    this.completedLessons = const {},
    this.passedQuizzes = const {},
    this.certificateCode,
    this.certificateIssuedAt,
  });

  final Set<String> completedLessons;
  final Set<String> passedQuizzes;
  final String? certificateCode;
  final DateTime? certificateIssuedAt;

  bool get hasCertificate =>
      certificateCode != null &&
      certificateCode!.trim().isNotEmpty &&
      certificateIssuedAt != null;

  bool get canIssueCertificate => academyCertificateEligible(
        completedLessonKeys: completedLessons,
        passedQuizKeys: passedQuizzes,
      );

  ChefAcademySnapshot copyWith({
    Set<String>? completedLessons,
    Set<String>? passedQuizzes,
    String? certificateCode,
    DateTime? certificateIssuedAt,
    bool clearCertificate = false,
  }) {
    return ChefAcademySnapshot(
      completedLessons: completedLessons ?? this.completedLessons,
      passedQuizzes: passedQuizzes ?? this.passedQuizzes,
      certificateCode: clearCertificate ? null : (certificateCode ?? this.certificateCode),
      certificateIssuedAt:
          clearCertificate ? null : (certificateIssuedAt ?? this.certificateIssuedAt),
    );
  }
}

class ChefAcademyProgress {
  ChefAcademyProgress._();

  static String _lessonsKey(String userId) => 'chef_academy_progress_$userId';
  static String _quizzesKey(String userId) => 'chef_academy_quizzes_$userId';
  static String _certCodeKey(String userId) => 'chef_academy_cert_code_$userId';
  static String _certAtKey(String userId) => 'chef_academy_cert_at_$userId';

  static Future<ChefAcademySnapshot> load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return const ChefAcademySnapshot();

    final local = await _loadLocal(userId);
    ChefAcademySnapshot cloud = const ChefAcademySnapshot();
    try {
      cloud = await _loadCloud(userId);
    } catch (_) {
      // Offline / missing table — keep local.
    }

    final merged = ChefAcademySnapshot(
      completedLessons: {...local.completedLessons, ...cloud.completedLessons},
      passedQuizzes: {...local.passedQuizzes, ...cloud.passedQuizzes},
      certificateCode: cloud.certificateCode ?? local.certificateCode,
      certificateIssuedAt: cloud.certificateIssuedAt ?? local.certificateIssuedAt,
    );

    final withCert = await _ensureCertificate(userId, merged);
    await _saveLocal(userId, withCert);
    try {
      await _saveCloud(userId, withCert);
    } catch (_) {}
    return withCert;
  }

  static Future<ChefAcademySnapshot> markLessonComplete({
    required String moduleId,
    required String lessonId,
  }) async {
    final snap = await load();
    final next = snap.copyWith(
      completedLessons: {...snap.completedLessons, academyLessonKey(moduleId, lessonId)},
    );
    return _persist(next);
  }

  static Future<ChefAcademySnapshot> markLessonIncomplete({
    required String moduleId,
    required String lessonId,
  }) async {
    final snap = await load();
    final lessons = {...snap.completedLessons}..remove(academyLessonKey(moduleId, lessonId));
    final next = snap.copyWith(completedLessons: lessons);
    return _persist(next);
  }

  /// Legacy helpers used by older screens — prefer [markLessonComplete].
  static Future<Set<String>> markComplete({
    required String moduleId,
    required String lessonId,
  }) async {
    final snap = await markLessonComplete(moduleId: moduleId, lessonId: lessonId);
    return snap.completedLessons;
  }

  static Future<Set<String>> markIncomplete({
    required String moduleId,
    required String lessonId,
  }) async {
    final snap = await markLessonIncomplete(moduleId: moduleId, lessonId: lessonId);
    return snap.completedLessons;
  }

  static Future<Set<String>> loadCompleted() async {
    final snap = await load();
    return snap.completedLessons;
  }

  static Future<ChefAcademySnapshot> markQuizPassed(String moduleId) async {
    final snap = await load();
    final next = snap.copyWith(
      passedQuizzes: {...snap.passedQuizzes, academyQuizKey(moduleId)},
    );
    return _persist(next);
  }

  static Future<ChefAcademySnapshot> _persist(ChefAcademySnapshot snap) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return snap;
    final withCert = await _ensureCertificate(userId, snap);
    await _saveLocal(userId, withCert);
    try {
      await _saveCloud(userId, withCert);
    } catch (_) {}
    return withCert;
  }

  static Future<ChefAcademySnapshot> _ensureCertificate(
    String userId,
    ChefAcademySnapshot snap,
  ) async {
    if (snap.hasCertificate) return snap;
    if (!snap.canIssueCertificate) return snap;
    final now = DateTime.now().toUtc();
    return snap.copyWith(
      certificateCode: generateAcademyCertificateCode(userId, now),
      certificateIssuedAt: now,
    );
  }

  static Future<ChefAcademySnapshot> _loadLocal(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final lessons = (prefs.getStringList(_lessonsKey(userId)) ?? const <String>[]).toSet();
    final quizzes = (prefs.getStringList(_quizzesKey(userId)) ?? const <String>[]).toSet();
    final code = prefs.getString(_certCodeKey(userId));
    final atRaw = prefs.getString(_certAtKey(userId));
    final at = atRaw == null || atRaw.isEmpty ? null : DateTime.tryParse(atRaw);
    return ChefAcademySnapshot(
      completedLessons: lessons,
      passedQuizzes: quizzes,
      certificateCode: code,
      certificateIssuedAt: at,
    );
  }

  static Future<void> _saveLocal(String userId, ChefAcademySnapshot snap) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_lessonsKey(userId), snap.completedLessons.toList()..sort());
    await prefs.setStringList(_quizzesKey(userId), snap.passedQuizzes.toList()..sort());
    if (snap.certificateCode != null && snap.certificateCode!.isNotEmpty) {
      await prefs.setString(_certCodeKey(userId), snap.certificateCode!);
    } else {
      await prefs.remove(_certCodeKey(userId));
    }
    if (snap.certificateIssuedAt != null) {
      await prefs.setString(_certAtKey(userId), snap.certificateIssuedAt!.toIso8601String());
    } else {
      await prefs.remove(_certAtKey(userId));
    }
  }

  static Future<ChefAcademySnapshot> _loadCloud(String userId) async {
    final row = await Supabase.instance.client
        .from('chef_academy_progress')
        .select(
          'completed_lessons, passed_quizzes, certificate_code, certificate_issued_at',
        )
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return const ChefAcademySnapshot();
    final lessons = _asStringSet(row['completed_lessons']);
    final quizzes = _asStringSet(row['passed_quizzes']);
    final code = row['certificate_code']?.toString();
    final atRaw = row['certificate_issued_at']?.toString();
    final at = atRaw == null || atRaw.isEmpty ? null : DateTime.tryParse(atRaw);
    return ChefAcademySnapshot(
      completedLessons: lessons,
      passedQuizzes: quizzes,
      certificateCode: code,
      certificateIssuedAt: at?.toLocal(),
    );
  }

  static Future<void> _saveCloud(String userId, ChefAcademySnapshot snap) async {
    await Supabase.instance.client.from('chef_academy_progress').upsert({
      'user_id': userId,
      'completed_lessons': snap.completedLessons.toList()..sort(),
      'passed_quizzes': snap.passedQuizzes.toList()..sort(),
      'certificate_code': snap.certificateCode,
      'certificate_issued_at': snap.certificateIssuedAt?.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Set<String> _asStringSet(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
    }
    return {};
  }
}
