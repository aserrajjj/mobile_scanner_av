/// Native and Dart timing metadata for one barcode capture.
///
/// Values ending in `Us` are microseconds. Native monotonic timestamps may be
/// compared with other native timestamps from the same capture. Dart monotonic
/// timestamps may be compared with other Dart `Timeline.now` timestamps.
class BarcodeCapturePerformance {
  /// Creates timing metadata for a barcode capture.
  const BarcodeCapturePerformance({
    required this.platform,
    required this.sequence,
    required this.frameReceivedUs,
    required this.decodeStartedUs,
    required this.decodeCompletedUs,
    required this.eventPreparedUs,
    required this.eventSentUs,
    required this.eventSentEpochUs,
    required this.dartReceivedUs,
    required this.dartReceivedEpochUs,
  });

  /// Parses native timing metadata, returning null for incomplete payloads.
  static BarcodeCapturePerformance? fromNative(
    Map<Object?, Object?>? data, {
    required int dartReceivedUs,
    required int dartReceivedEpochUs,
  }) {
    if (data == null) {
      return null;
    }

    final platform = data['platform'];
    final sequence = _asInt(data['sequence']);
    final frameReceivedUs = _asInt(data['frameReceivedUs']);
    final decodeStartedUs = _asInt(data['decodeStartedUs']);
    final decodeCompletedUs = _asInt(data['decodeCompletedUs']);
    final eventPreparedUs = _asInt(data['eventPreparedUs']);
    final eventSentUs = _asInt(data['eventSentUs']);
    final eventSentEpochUs = _asInt(data['eventSentEpochUs']);

    if (platform is! String ||
        sequence == null ||
        frameReceivedUs == null ||
        decodeStartedUs == null ||
        decodeCompletedUs == null ||
        eventPreparedUs == null ||
        eventSentUs == null ||
        eventSentEpochUs == null) {
      return null;
    }

    return BarcodeCapturePerformance(
      platform: platform,
      sequence: sequence,
      frameReceivedUs: frameReceivedUs,
      decodeStartedUs: decodeStartedUs,
      decodeCompletedUs: decodeCompletedUs,
      eventPreparedUs: eventPreparedUs,
      eventSentUs: eventSentUs,
      eventSentEpochUs: eventSentEpochUs,
      dartReceivedUs: dartReceivedUs,
      dartReceivedEpochUs: dartReceivedEpochUs,
    );
  }

  /// Native platform that produced the capture.
  final String platform;

  /// Successful barcode-event sequence number for the camera session.
  final int sequence;

  /// Native monotonic time when the analyzer received the frame.
  final int frameReceivedUs;

  /// Native monotonic time immediately before decoder execution.
  final int decodeStartedUs;

  /// Native monotonic time when decoder execution completed.
  final int decodeCompletedUs;

  /// Native monotonic time when the event payload was ready.
  final int eventPreparedUs;

  /// Native monotonic time immediately before sending the Flutter event.
  final int eventSentUs;

  /// Device wall-clock time immediately before sending the Flutter event.
  final int eventSentEpochUs;

  /// Dart monotonic time when the platform event began parsing.
  final int dartReceivedUs;

  /// Dart wall-clock time when the platform event began parsing.
  final int dartReceivedEpochUs;

  /// Native preprocessing duration before decoder execution.
  int get preprocessingUs => decodeStartedUs - frameReceivedUs;

  /// Native decoder execution duration.
  int get decodeUs => decodeCompletedUs - decodeStartedUs;

  /// Native result serialization duration.
  int get nativePostprocessingUs => eventPreparedUs - decodeCompletedUs;

  /// Time waiting for the native platform-event delivery queue.
  int get nativeEventQueueUs => eventSentUs - eventPreparedUs;

  /// Total native frame-to-event duration.
  int get nativeTotalUs => eventSentUs - frameReceivedUs;

  /// Approximate native-to-Dart delivery time based on the device wall clock.
  int get platformDeliveryUs {
    final duration = dartReceivedEpochUs - eventSentEpochUs;
    return duration < 0 ? 0 : duration;
  }

  static int? _asInt(Object? value) => value is num ? value.toInt() : null;
}
