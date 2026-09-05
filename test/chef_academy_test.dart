import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/data/chef_academy_curriculum.dart';
import 'package:hotpotchef_new/data/chef_academy_quizzes.dart';

void main() {
  group('chef academy curriculum', () {
    test('covers hygiene through equipment with unique lesson ids', () {
      expect(kChefAcademyModules, hasLength(7));
      expect(
        kChefAcademyModules.map((m) => m.id).toSet(),
        containsAll([
          'hygiene',
          'bulk_consistency',
          'time_mgmt',
          'order_mgmt',
          'professional',
          'packaging',
          'equipment',
        ]),
      );

      final keys = allAcademyLessonIds();
      expect(keys.length, greaterThanOrEqualTo(20));
      expect(keys.toSet(), hasLength(keys.length));

      for (final module in kChefAcademyModules) {
        expect(module.lessons, isNotEmpty);
        for (final lesson in module.lessons) {
          expect(lesson.title.trim(), isNotEmpty);
          expect(lesson.body.trim().length, greaterThan(40));
          expect(lesson.minutes, greaterThan(0));
        }
      }
    });

    test('progress percent and module counts use lesson keys', () {
      final module = kChefAcademyModules.first;
      final key = academyLessonKey(module.id, module.lessons.first.id);
      expect(academyProgressPercent({}), 0);
      expect(academyModuleCompletedCount(module, {}), 0);
      expect(academyModuleCompletedCount(module, {key}), 1);
      expect(academyProgressPercent({key}), greaterThan(0));
      expect(academyProgressPercent(allAcademyLessonIds().toSet()), 100);
    });
  });

  group('chef academy quizzes and certificate', () {
    test('every module has a 3-question quiz with a valid correct index', () {
      for (final module in kChefAcademyModules) {
        final quiz = quizzesForModule(module.id);
        expect(quiz, hasLength(3), reason: module.id);
        for (final q in quiz) {
          expect(q.choices.length, greaterThanOrEqualTo(2));
          expect(q.correctIndex, inInclusiveRange(0, q.choices.length - 1));
        }
      }
      expect(allAcademyQuizKeys().toSet(), hasLength(kChefAcademyModules.length));
    });

    test('pass rule requires at least two correct answers', () {
      final quiz = quizzesForModule('hygiene');
      final pass = {
        for (final q in quiz) q.id: q.correctIndex,
      };
      final fail = {
        quiz[0].id: quiz[0].correctIndex,
        quiz[1].id: (quiz[1].correctIndex + 1) % quiz[1].choices.length,
        quiz[2].id: (quiz[2].correctIndex + 1) % quiz[2].choices.length,
      };
      expect(academyQuizAttemptPassed(quiz, pass), isTrue);
      expect(academyQuizAttemptPassed(quiz, fail), isFalse);
      expect(scoreAcademyQuiz(quiz, pass), 3);
    });

    test('certificate eligibility needs all lessons and quizzes', () {
      final lessons = allAcademyLessonIds().toSet();
      final quizzes = allAcademyQuizKeys().toSet();
      expect(
        academyCertificateEligible(completedLessonKeys: lessons, passedQuizKeys: {}),
        isFalse,
      );
      expect(
        academyCertificateEligible(completedLessonKeys: {}, passedQuizKeys: quizzes),
        isFalse,
      );
      expect(
        academyCertificateEligible(completedLessonKeys: lessons, passedQuizKeys: quizzes),
        isTrue,
      );
      expect(
        academyCourseProgressPercent(completedLessonKeys: lessons, passedQuizKeys: quizzes),
        100,
      );
      final code = generateAcademyCertificateCode('11111111-2222-3333-4444-555555555555', DateTime.utc(2026, 9, 6));
      expect(code, startsWith('HPC-KA-20260906-'));
      expect(
        academyCertificateShareText(
          chefName: 'Meera',
          certificateCode: code,
          issuedAt: DateTime(2026, 9, 6),
        ),
        contains('Meera'),
      );
    });

    test('selected lessons expose external video tips', () {
      expect(academyLessonVideoUrl('hygiene_handwash'), isNotNull);
      expect(academyLessonVideoUrl('hygiene_fssai'), contains('fssai.gov.in'));
      expect(academyLessonVideoUrl('missing'), isNull);
    });
  });
}
