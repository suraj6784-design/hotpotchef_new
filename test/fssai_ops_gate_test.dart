import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('FSSAI verification gate', () {
    test('blocks publish without proof', () {
      expect(
        chefCanPublishWithFssai(
          fssaiNumber: '11234567890123',
          proofUrl: null,
          verificationStatus: 'unsubmitted',
        ),
        isFalse,
      );
    });

    test('blocks pending until ops verifies', () {
      expect(
        chefCanPublishWithFssai(
          fssaiNumber: '11234567890123',
          proofUrl: 'https://example.com/fssai.jpg',
          verificationStatus: 'pending',
        ),
        isFalse,
      );
    });

    test('allows only verified once proof exists', () {
      expect(
        chefCanPublishWithFssai(
          fssaiNumber: '11234567890123',
          proofUrl: 'https://example.com/fssai.jpg',
          verificationStatus: 'verified',
        ),
        isTrue,
      );
      expect(
        chefFssaiPublishBlockReason(
          fssaiNumber: '11234567890123',
          proofUrl: 'https://example.com/fssai.jpg',
          verificationStatus: 'verified',
        ),
        isNull,
      );
    });

    test('verified without loaded proof still blocks, with a proof message', () {
      expect(
        chefFssaiPublishBlockReason(
          fssaiNumber: '11234567890123',
          proofUrl: null,
          verificationStatus: 'verified',
        ),
        contains('licence proof'),
      );
    });

    test('rejects when ops marked rejected', () {
      expect(
        chefCanPublishWithFssai(
          fssaiNumber: '11234567890123',
          proofUrl: 'https://example.com/fssai.jpg',
          verificationStatus: 'rejected',
        ),
        isFalse,
      );
    });

    test('diner trust label never says verified for pending', () {
      expect(
        dinerFssaiTrustLabel(fssaiNumber: '11234567890123', verificationStatus: 'pending'),
        contains('under review'),
      );
      expect(
        dinerFssaiIsVerified('pending'),
        isFalse,
      );
      expect(
        dinerFssaiIsVerified('verified'),
        isTrue,
      );
    });

    test('masks pan and bank', () {
      expect(maskPan('ABCDE1234F'), '******234F');
      expect(maskBankAccount('123456789012'), 'XXXXXX9012');
    });

    test('delivery otp match', () {
      expect(deliveryOtpMatches('0482', '0482'), isTrue);
      expect(deliveryOtpMatches('0482', '482'), isFalse);
      expect(deliveryOtpMatches('0482', '9999'), isFalse);
    });

    test('packaging supply helpers still resolve', () {
      expect(isPackagingSupplyRequest({'request_type': 'packaging_supply'}), isTrue);
    });
  });
}
