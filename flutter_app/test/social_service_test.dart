import 'package:beta_app/social/social_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const image = SocialMediaFile(path: '/private/image.png', mimeType: 'image/png', name: 'image.png');

  group('SocialPostValidation', () {
    test('allows a text-only post and supported image/video media', () {
      expect(SocialPostValidation.validate(caption: 'hello', media: const []), isNull);
      expect(SocialPostValidation.validate(caption: '', media: const [image]), isNull);
      expect(SocialPostValidation.validate(caption: '', media: const [
        SocialMediaFile(path: '/private/clip.mp4', mimeType: 'video/mp4', name: 'clip.mp4'),
      ]), isNull);
    });

    test('rejects empty, overlong, over-count and unsupported posts', () {
      expect(SocialPostValidation.validate(caption: ' ', media: const []), isNotNull);
      expect(SocialPostValidation.validate(caption: List.filled(2201, 'x').join(), media: const []), contains('2.200'));
      expect(SocialPostValidation.validate(caption: '', media: List.filled(6, image)), contains('cinco'));
      expect(SocialPostValidation.validate(caption: '', media: const [
        SocialMediaFile(path: '/private/file.pdf', mimeType: 'application/pdf', name: 'file.pdf'),
      ]), contains('no está permitido'));
    });
  });
}
