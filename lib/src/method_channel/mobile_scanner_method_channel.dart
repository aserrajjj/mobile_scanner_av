import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/src/enums/barcode_format.dart';
import 'package:mobile_scanner/src/enums/mobile_scanner_authorization_state.dart';
import 'package:mobile_scanner/src/enums/mobile_scanner_error_code.dart';
import 'package:mobile_scanner/src/enums/torch_state.dart';
import 'package:mobile_scanner/src/mobile_scanner_exception.dart';
import 'package:mobile_scanner/src/mobile_scanner_platform_interface.dart';
import 'package:mobile_scanner/src/mobile_scanner_view_attributes.dart';
import 'package:mobile_scanner/src/objects/barcode.dart';
import 'package:mobile_scanner/src/objects/barcode_capture.dart';
import 'package:mobile_scanner/src/objects/start_options.dart';

/// An implementation of [MobileScannerPlatform] that uses method channels.
class MethodChannelMobileScanner extends MobileScannerPlatform {
  /// The name of the barcode event that is sent when a barcode is scanned.
  @visibleForTesting
  static const String kBarcodeEventName = 'barcode';

  /// The name of the error event that is sent when a barcode scan error occurs.
  @visibleForTesting
  static const String kBarcodeErrorEventName = 'mobile_scanner_BARCODE_ERROR';

  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );

  /// The event channel that sends back scanned barcode events.
  @visibleForTesting
  final eventChannel = const EventChannel(
    'dev.steenbakker.mobile_scanner/scanner/event',
  );

  Stream<Map<Object?, Object?>>? _eventsStream;

  Stream<Map<Object?, Object?>> get eventsStream {
    _eventsStream ??=
        eventChannel.receiveBroadcastStream().cast<Map<Object?, Object?>>();

    return _eventsStream!;
  }

  int? _textureId;

  /// Parse a [BarcodeCapture] from the given [event].
  BarcodeCapture? _parseBarcode(Map<Object?, Object?>? event) {
    if (event == null) {
      return null;
    }

    final Object? data = event['data'];

    if (data == null || data is! List<Object?>) {
      return null;
    }

    final List<Map<Object?, Object?>> barcodes =
        data.cast<Map<Object?, Object?>>();

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      final Map<Object?, Object?>? imageData =
          event['image'] as Map<Object?, Object?>?;
      final Uint8List? image = imageData?['bytes'] as Uint8List?;
      final double? width = imageData?['width'] as double?;
      final double? height = imageData?['height'] as double?;

      return BarcodeCapture(
        raw: event,
        barcodes: barcodes.map(Barcode.fromNative).toList(),
        image: image,
        size: width == null || height == null ? Size.zero : Size(width, height),
      );
    }

    throw const MobileScannerException(
      errorCode: MobileScannerErrorCode.genericError,
      errorDetails: MobileScannerErrorDetails(
        message: 'Only Android, iOS and macOS are supported.',
      ),
    );
  }

  /// Parse a [MobileScannerBarcodeException] from the given [error] and [stackTrace], and throw it.
  ///
  /// If the error is not a [PlatformException],
  /// with [kBarcodeErrorEventName] as [PlatformException.code], the error is rethrown as-is.
  Never _parseBarcodeError(Object error, StackTrace stackTrace) {
    if (error case PlatformException(:final String code, :final String? message)
        when code == kBarcodeErrorEventName) {
      throw MobileScannerBarcodeException(message);
    }

    Error.throwWithStackTrace(error, stackTrace);
  }

  /// Request permission to access the camera.
  ///
  /// Throws a [MobileScannerException] if the permission is not granted.
  Future<void> _requestCameraPermission() async {
    try {
      final MobileScannerAuthorizationState authorizationState =
          MobileScannerAuthorizationState.fromRawValue(
        await methodChannel.invokeMethod<int>('state') ?? 0,
      );

      switch (authorizationState) {
        // Authorization was already granted, no need to request it again.
        case MobileScannerAuthorizationState.authorized:
          return;
        // Android does not have an undetermined authorization state.
        // So if the permission was denied, request it again.
        case MobileScannerAuthorizationState.denied:
        case MobileScannerAuthorizationState.undetermined:
          final bool permissionGranted =
              await methodChannel.invokeMethod<bool>('request') ?? false;

          if (!permissionGranted) {
            throw const MobileScannerException(
              errorCode: MobileScannerErrorCode.permissionDenied,
            );
          }
      }
    } on PlatformException catch (error) {
      // If the permission state is invalid, that is an error.
      throw MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
        errorDetails: MobileScannerErrorDetails(
          code: error.code,
          details: error.details as Object?,
          message: error.message,
        ),
      );
    }
  }

  @override
  Stream<BarcodeCapture?> get barcodesStream {
    // Handle incoming barcode events.
    // The error events are transformed to `MobileScannerBarcodeException` where possible.
    return eventsStream
        .where((e) => e['name'] == kBarcodeEventName)
        .map((event) => _parseBarcode(event))
        .handleError(_parseBarcodeError);
  }

  @override
  Stream<TorchState> get torchStateStream {
    return eventsStream
        .where((event) => event['name'] == 'torchState')
        .map((event) => TorchState.fromRawValue(event['data'] as int? ?? 0));
  }

  @override
  Stream<double> get zoomScaleStateStream {
    return eventsStream
        .where((event) => event['name'] == 'zoomScaleState')
        .map((event) => event['data'] as double? ?? 0.0);
  }

  @override
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const <BarcodeFormat>[],
  }) async {
    try {
      final Map<Object?, Object?>? result =
          await methodChannel.invokeMapMethod<Object?, Object?>(
        'analyzeImage',
        {
          'filePath': path,
          'formats': formats.isEmpty
              ? null
              : [
                  for (final BarcodeFormat format in formats)
                    if (format != BarcodeFormat.unknown) format.rawValue,
                ],
        },
      );

      return _parseBarcode(result);
    } on PlatformException catch (error) {
      // Handle any errors from analyze image requests.
      if (error.code == kBarcodeErrorEventName) {
        throw MobileScannerBarcodeException(error.message);
      }

      return null;
    }
  }

  @override
  Widget buildCameraView() {
    if (_textureId == null) {
      return const SizedBox();
    }

    return Texture(textureId: _textureId!);
  }

  @override
  Future<void> resetZoomScale() async {
    await methodChannel.invokeMethod<void>('resetScale');
  }

  @override
  Future<void> setZoomScale(double zoomScale) async {
    await methodChannel.invokeMethod<void>('setScale', zoomScale);
  }

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    if (_textureId != null) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerAlreadyInitialized,
        errorDetails: MobileScannerErrorDetails(
          message: 'The scanner was already started.',
        ),
      );
    }

    await _requestCameraPermission();

    Map<String, Object?>? startResult;

    try {
      startResult = await methodChannel.invokeMapMethod<String, Object?>(
        'start',
        startOptions.toMap(),
      );
    } on PlatformException catch (error) {
      throw MobileScannerException(
        errorCode: MobileScannerErrorCode.fromPlatformException(error),
        errorDetails: MobileScannerErrorDetails(
          code: error.code,
          details: error.details as Object?,
          message: error.message,
        ),
      );
    }

    if (startResult == null) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
        errorDetails: MobileScannerErrorDetails(
          message: 'The start method did not return a view configuration.',
        ),
      );
    }

    final int? textureId = startResult['textureId'] as int?;

    if (textureId == null) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
        errorDetails: MobileScannerErrorDetails(
          message: 'The start method did not return a texture id.',
        ),
      );
    }

    _textureId = textureId;

    final int? numberOfCameras = startResult['numberOfCameras'] as int?;
    final TorchState currentTorchState = TorchState.fromRawValue(
      startResult['currentTorchState'] as int? ?? -1,
    );

    final Size size;

    if (startResult['size']
        case {'width': final double width, 'height': final double height}) {
      size = Size(width, height);
    } else {
      size = Size.zero;
    }

    return MobileScannerViewAttributes(
      currentTorchMode: currentTorchState,
      numberOfCameras: numberOfCameras,
      size: size,
    );
  }

  @override
  Future<void> setShouldConsiderInvertedImages(
      bool shouldConsiderInvertedImages) async {
    await methodChannel.invokeMethod<void>(
      'setShouldConsiderInvertedImages',
      {'shouldConsiderInvertedImages': shouldConsiderInvertedImages},
    );
  }

  @override
  Future<void> stop() async {
    if (_textureId == null) {
      return;
    }

    _textureId = null;

    await methodChannel.invokeMethod<void>('stop');
  }

  @override
  Future<void> toggleTorch() async {
    await methodChannel.invokeMethod<void>('toggleTorch');
  }

  @override
  Future<void> updateScanWindow(Rect? window) async {
    if (_textureId == null) {
      return;
    }

    List<double>? points;

    if (window != null) {
      points = [window.left, window.top, window.right, window.bottom];
    }

    await methodChannel.invokeMethod<void>(
      'updateScanWindow',
      {'rect': points},
    );
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
