import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/src/objects/barcode_capture_performance.dart';

void main() {
  group('$BarcodeCapturePerformance', () {
    test('parses native timing metadata and calculates durations', () {
      final performance = BarcodeCapturePerformance.fromNative(
        const {
          'platform': 'android',
          'sequence': 7,
          'frameReceivedUs': 100,
          'decodeStartedUs': 130,
          'decodeCompletedUs': 530,
          'eventPreparedUs': 550,
          'eventSentUs': 570,
          'eventSentEpochUs': 1000000,
        },
        dartReceivedUs: 800,
        dartReceivedEpochUs: 1000060,
      );

      expect(performance, isNotNull);
      expect(performance?.preprocessingUs, 30);
      expect(performance?.decodeUs, 400);
      expect(performance?.nativePostprocessingUs, 20);
      expect(performance?.nativeEventQueueUs, 20);
      expect(performance?.nativeTotalUs, 470);
      expect(performance?.platformDeliveryUs, 60);
    });

    test('rejects incomplete metadata', () {
      final performance = BarcodeCapturePerformance.fromNative(
        const {'platform': 'android'},
        dartReceivedUs: 0,
        dartReceivedEpochUs: 0,
      );

      expect(performance, isNull);
    });

    test('clamps negative wall-clock delivery estimates', () {
      final performance = BarcodeCapturePerformance.fromNative(
        const {
          'platform': 'apple',
          'sequence': 1,
          'frameReceivedUs': 100,
          'decodeStartedUs': 110,
          'decodeCompletedUs': 120,
          'eventPreparedUs': 130,
          'eventSentUs': 140,
          'eventSentEpochUs': 2000,
        },
        dartReceivedUs: 150,
        dartReceivedEpochUs: 1999,
      );

      expect(performance?.platformDeliveryUs, 0);
    });
  });
}
