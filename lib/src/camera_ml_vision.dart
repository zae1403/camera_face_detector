import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:collection/collection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

part 'utils.dart';

typedef HandleDetection<T> = Future<T> Function(InputImage image);
typedef ErrorWidgetBuilder = Widget Function(
    BuildContext context, CameraError error);
typedef HandlerError = void Function(CameraError error);

enum CameraError {
  unknown,
  cantInitializeCamera,
  androidVersionNotSupported,
  noCameraAvailable,
  functionNotSupported,
  unableProcessImage,
}

enum _CameraState {
  loading,
  error,
  ready,
}

class CameraFaceDetector<T> extends StatefulWidget {
  final HandleDetection<T> detector;
  final Function(T) onResult;
  final WidgetBuilder? loadingBuilder;
  final ErrorWidgetBuilder? errorBuilder;
  final WidgetBuilder? overlayBuilder;
  final CameraLensDirection cameraLensDirection;
  final ResolutionPreset? resolution;
  final HandlerError? onError;
  final Function? onDispose;

  const CameraFaceDetector({
    Key? key,
    required this.onResult,
    required this.detector,
    this.loadingBuilder,
    this.errorBuilder,
    this.overlayBuilder,
    this.cameraLensDirection = CameraLensDirection.back,
    this.resolution,
    this.onError,
    this.onDispose,
  }) : super(key: key);

  @override
  CameraFaceDetectorState createState() => CameraFaceDetectorState<T>();
}

class CameraFaceDetectorState<T> extends State<CameraFaceDetector<T>>
    with WidgetsBindingObserver {
  XFile? _lastImage;
  CameraController? _cameraController;
  InputImageRotation? _rotation;
  _CameraState _cameraMlVisionState = _CameraState.loading;
  CameraError _cameraError = CameraError.unknown;
  bool isBusy = false;
  bool _isStreaming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didUpdateWidget(CameraFaceDetector<T> oldWidget) {
    if (oldWidget.resolution != widget.resolution) {
      _initialize();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App state changed before we got the chance to initialize.
    if (_cameraController == null ||
        _cameraController?.value.isInitialized == false) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _stop(true).then((value) => _cameraController?.dispose());
    } else if (state == AppLifecycleState.resumed && _isStreaming) {
      _initialize();
    }
  }

  Future<void> stop() async {
    if (_cameraController != null) {
      await _stop(true);
      try {
        final image = await _cameraController!.takePicture();
        setState(() {
          _lastImage = image;
        });
      } on PlatformException catch (e) {
        debugPrint('$e');
        widget.onError?.call(CameraError.functionNotSupported);
      }
    }
  }

  Future<void> _stop(bool silently) {
    final completer = Completer();
    scheduleMicrotask(() async {
      if (_cameraController?.value.isStreamingImages == true && mounted) {
        await _cameraController?.stopImageStream().catchError((_) {});
      }

      if (silently) {
        if (mounted) {
          setState(() {
            _isStreaming = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isStreaming = false;
          });
        }
      }
      completer.complete();
    });
    return completer.future;
  }

  void start() async {
    if (_cameraController != null) {
      await _start();
    }
  }

  Future<void> _start() async {
    if (_cameraController?.value.isStreamingImages ?? true) return;
    await _cameraController?.startImageStream(_processImage);
    setState(() {
      _isStreaming = true;
    });
  }

  CameraValue? get cameraValue => _cameraController?.value;

  InputImageRotation? get imageRotation => _rotation;

  Future<void> Function() get prepareForVideoRecording =>
      _cameraController!.prepareForVideoRecording;

  Future<void> startVideoRecording() async {
    await _cameraController!.stopImageStream();
    return _cameraController!.startVideoRecording();
  }

  Future<XFile> stopVideoRecording(String path) async {
    final file = await _cameraController!.stopVideoRecording();
    await _cameraController!.startImageStream(_processImage);
    return file;
  }

  CameraController? get cameraController => _cameraController;

  Future<XFile> takePicture(String path) async {
    await _stop(true);
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      final image = await _cameraController?.takePicture();
      await Future.delayed(const Duration(milliseconds: 200));
      await _start();
      return image!;
    } on PlatformException catch (e) {
      debugPrint('$e');
      widget.onError?.call(CameraError.functionNotSupported);

      rethrow;
    }
  }

  Future<void> flash(FlashMode mode) async {
    await _cameraController?.setFlashMode(mode);
  }

  Future<void> focus(FocusMode mode) async {
    await _cameraController?.setFocusMode(mode);
  }

  Future<void> focusPoint(Offset point) async {
    await _cameraController?.setFocusPoint(point);
  }

  Future<void> zoom(double zoom) async {
    await _cameraController?.setZoomLevel(zoom);
  }

  Future<void> exposure(ExposureMode mode) async {
    await _cameraController?.setExposureMode(mode);
  }

  Future<void> exposureOffset(double offset) async {
    await _cameraController?.setExposureOffset(offset);
  }

  Future<void> exposurePoint(Offset offset) async {
    await _cameraController?.setExposurePoint(offset);
  }

  Future<void> _initialize() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      if (androidInfo.version.sdkInt! < 21) {
        debugPrint('Camera plugin doesn\'t support android under version 21');
        if (mounted) {
          setState(() {
            _cameraMlVisionState = _CameraState.error;
            _cameraError = CameraError.androidVersionNotSupported;
          });
          widget.onError?.call(CameraError.androidVersionNotSupported);
        }
      }
    }

    final description = await _getCamera(widget.cameraLensDirection);
    if (description == null) {
      _cameraMlVisionState = _CameraState.error;
      _cameraError = CameraError.noCameraAvailable;
      widget.onError?.call(CameraError.noCameraAvailable);

      return;
    }

    if (_cameraController != null) {
      await _stop(true);
      await _cameraController?.dispose();
    }

    _cameraController = CameraController(
      description,
      widget.resolution ?? ResolutionPreset.low,
      enableAudio: false,
    );

    if (!mounted) {
      return;
    }

    try {
      await _cameraController?.initialize();
    } catch (ex, stack) {
      debugPrint('Can\'t initialize camera');
      debugPrint('$ex, $stack');
      if (mounted) {
        setState(() {
          _cameraMlVisionState = _CameraState.error;
          _cameraError = CameraError.cantInitializeCamera;
        });
        widget.onError?.call(CameraError.cantInitializeCamera);
      }
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _cameraMlVisionState = _CameraState.ready;
      _rotation = _rotationIntToImageRotation(
        description.sensorOrientation,
      );
    });

    //FIXME hacky technique to avoid having black screen on some android devices
    await Future.delayed(const Duration(milliseconds: 200));
    start();
  }

  @override
  void dispose() {
    widget.onDispose?.call();

    if (_cameraController != null) {
      _cameraController!.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraMlVisionState == _CameraState.loading) {
      return widget.loadingBuilder == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : widget.loadingBuilder!(context);
    }
    if (_cameraMlVisionState == _CameraState.error) {
      return widget.errorBuilder == null
          ? Center(child: Text('$_cameraMlVisionState $_cameraError'))
          : widget.errorBuilder!(context, _cameraError);
    }

    var cameraPreview = _isStreaming
        ? CameraPreview(
            _cameraController!,
          )
        : _getPicture();

    if (widget.overlayBuilder != null) {
      cameraPreview = Stack(
        fit: StackFit.passthrough,
        children: [
          cameraPreview,
          (cameraController?.value.isInitialized ?? false)
              ? AspectRatio(
                  aspectRatio: _isLandscape()
                      ? cameraController!.value.aspectRatio
                      : (1 / cameraController!.value.aspectRatio),
                  child:
                      widget.overlayBuilder?.call(context) ?? const SizedBox(),
                )
              : const SizedBox(),
        ],
      );
    }
    return cameraPreview;
  }

  DeviceOrientation? _getApplicableOrientation() {
    return (cameraController?.value.isRecordingVideo ?? false)
        ? cameraController?.value.recordingOrientation
        : (cameraController?.value.lockedCaptureOrientation ??
            cameraController?.value.deviceOrientation);
  }

  bool _isLandscape() {
    return [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        .contains(_getApplicableOrientation());
  }

  void _processImage(CameraImage cameraImage) async {
    if (isBusy) {
      return;
    }

    isBusy = true;
    try {
      final results =
          await _detect<T>(cameraImage, widget.detector, _rotation!);
      widget.onResult(results);
    } catch (ex, stack) {
      debugPrint('$ex, $stack');

      _cameraMlVisionState = _CameraState.error;
      _cameraError = CameraError.unableProcessImage;

      widget.onError?.call(CameraError.unableProcessImage);
    }
    isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }

  void toggle() async {
    if (_isStreaming && _cameraController!.value.isStreamingImages) {
      await stop();
    } else {
      start();
    }
  }

  Widget _getPicture() {
    if (_lastImage != null) {
      return Image.file(File(_lastImage!.path));
    }
    return const SizedBox();
  }
}
