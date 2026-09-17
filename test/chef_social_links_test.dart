import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  test('instagram accepts handle or https profile', () {
    expect(
      sanitizeChefSocialUrl('@home_thali', ChefSocialPlatform.instagram),
      'https://www.instagram.com/home_thali',
    );
    expect(
      sanitizeChefSocialUrl('https://instagram.com/home.thali', ChefSocialPlatform.instagram),
      'https://instagram.com/home.thali',
    );
    expect(sanitizeChefSocialUrl('javascript:alert(1)', ChefSocialPlatform.instagram), isNull);
    expect(sanitizeChefSocialUrl('https://evil.example/ig', ChefSocialPlatform.instagram), isNull);
  });

  test('youtube and facebook require known hosts', () {
    expect(
      sanitizeChefSocialUrl('https://www.youtube.com/@masala', ChefSocialPlatform.youtube),
      isNotNull,
    );
    expect(
      sanitizeChefSocialUrl('https://youtu.be/abc123', ChefSocialPlatform.youtube),
      isNotNull,
    );
    expect(sanitizeChefSocialUrl('https://youtu.be', ChefSocialPlatform.youtube), isNull);
    expect(
      sanitizeChefSocialUrl('https://www.facebook.com/homechef', ChefSocialPlatform.facebook),
      isNotNull,
    );
  });

  test('chef social links ignore empty and junk', () {
    final links = ChefSocialLinks.fromMap({
      'instagram_url': '@pune_dabba',
      'youtube_url': 'not-a-url',
      'facebook_url': '',
    });
    expect(links.hasAny, isTrue);
    expect(links.platformsLabel, 'Instagram');
  });
}
