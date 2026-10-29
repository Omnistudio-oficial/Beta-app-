import 'dart:async';
import 'dart:math' show Point;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../social/face_sticker_geometry.dart';

enum FaceStickerFilter { none, dogEars, glasses, crown }

/// On-device, real-time face stickers for Social's camera preview.
/// ML Kit detects facial geometry locally; images are never uploaded and no
/// identity recognition is performed.
class SocialCameraPreviewScreen extends StatefulWidget {
  const SocialCameraPreviewScreen({super.key});

  @override
  State<SocialCameraPreviewScreen> createState() => _SocialCameraPreviewScreenState();
}

class _SocialCameraPreviewScreenState extends State<SocialCameraPreviewScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  String? _error;
  bool _loading = true;
  bool _initializing = false;
  bool _processingFrame = false;
  FaceStickerFilter _filter = FaceStickerFilter.none;
  List<FaceStickerFace> _faces = const [];
  FaceDetector? _detector;
  int _streamGeneration = 0;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detector = FaceDetector(options: FaceDetectorOptions(
      enableLandmarks: true,
      enableContours: false,
      enableClassification: false,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.12,
    ));
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (_initializing || !mounted || !_appActive) return;
    _initializing = true;
    if (mounted) setState(() { _loading = true; _error = null; _faces = const []; });
    CameraController? controller;
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('NoCamera', 'No camera is available.');
      _cameraIndex %= _cameras.length;
      final description = _cameras[_cameraIndex];
      controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: _imageFormatForPlatform(),
      );
      await controller.initialize();
      if (!mounted || !_appActive) {
        await controller.dispose();
        return;
      }
      final old = _controller;
      _controller = controller;
      controller = null;
      if (old != null) await old.dispose();
      await _startImageStream(_controller!);
      if (mounted) setState(() { _loading = false; _error = null; });
    } on CameraException catch (error) {
      if (mounted) setState(() { _loading = false; _error = _cameraError(error); });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'No se pudo iniciar la cámara.'; });
    } finally {
      await controller?.dispose();
      _initializing = false;
    }
  }

  ImageFormatGroup _imageFormatForPlatform() {
    // ML Kit accepts NV21 on Android and packed BGRA8888 on iOS.
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => ImageFormatGroup.nv21,
      TargetPlatform.iOS => ImageFormatGroup.bgra8888,
      _ => ImageFormatGroup.yuv420,
    };
  }

  Future<void> _startImageStream(CameraController controller) async {
    if (!controller.value.isInitialized || controller.value.isStreamingImages) return;
    final generation = ++_streamGeneration;
    await controller.startImageStream((image) {
      if (_processingFrame || !mounted || generation != _streamGeneration) return;
      _processingFrame = true;
      unawaited(_detectFaces(image, controller, generation));
    });
  }

  InputImage? _inputImage(CameraImage image, CameraDescription camera) {
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    // The stream is requested as NV21 on Android and BGRA8888 on iOS. Refuse
    // unsupported multi-plane layouts instead of feeding malformed bytes.
    if (defaultTargetPlatform == TargetPlatform.android && format != InputImageFormat.nv21) return null;
    if (defaultTargetPlatform == TargetPlatform.iOS && format != InputImageFormat.bgra8888) return null;
    final bytes = WriteBuffer();
    for (final plane in image.planes) {
      bytes.putUint8List(plane.bytes);
    }
    final rotationCompensation = _rotationFor(camera, rotation);
    return InputImage.fromBytes(
      bytes: bytes.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotationCompensation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  InputImageRotation _rotationFor(CameraDescription camera, InputImageRotation sensorRotation) {
    final deviceOrientation = _controller?.value.deviceOrientation ?? DeviceOrientation.portraitUp;
    final deviceDegrees = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    final isFront = camera.lensDirection == CameraLensDirection.front;
    final degrees = (camera.sensorOrientation + (isFront ? deviceDegrees : -deviceDegrees) + 360) % 360;
    return switch (degrees) {
      0 => InputImageRotation.rotation0deg,
      90 => InputImageRotation.rotation90deg,
      180 => InputImageRotation.rotation180deg,
      270 => InputImageRotation.rotation270deg,
      _ => sensorRotation,
    };
  }

  Future<void> _detectFaces(CameraImage image, CameraController controller, int generation) async {
    try {
      final input = _inputImage(image, controller.description);
      if (input == null || _detector == null) return;
      final found = await _detector!.processImage(input);
      if (!mounted || generation != _streamGeneration || _controller != controller) return;
      final rotation = input.metadata?.rotation ?? InputImageRotation.rotation0deg;
      final isRotated = rotation == InputImageRotation.rotation90deg || rotation == InputImageRotation.rotation270deg;
      final sourceSize = Size(
        (isRotated ? image.height : image.width).toDouble(),
        (isRotated ? image.width : image.height).toDouble(),
      );
      final mapped = found.map((face) => FaceStickerFace(
        bounds: face.boundingBox,
        leftEye: face.landmarks[FaceLandmarkType.leftEye]?.position,
        rightEye: face.landmarks[FaceLandmarkType.rightEye]?.position,
        sourceSize: sourceSize,
      )).toList(growable: false);
      setState(() => _faces = mapped);
    } catch (_) {
      // Keep the preview responsive; transient per-frame inference failures
      // simply leave the last successfully detected overlay visible.
    } finally {
      _processingFrame = false;
    }
  }

  String _cameraError(CameraException error) {
    if (error.code.startsWith('CameraAccessDenied')) {
      return 'Se necesita permiso de cámara para mostrar la vista previa.';
    }
    return 'No se pudo iniciar la cámara.';
  }

  Future<void> _stopCamera() async {
    ++_streamGeneration;
    final controller = _controller;
    _controller = null;
    _faces = const [];
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) await controller.stopImageStream();
      } catch (_) {}
      await controller.dispose();
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _initializing) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    await _stopCamera();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (mounted) setState(() => _loading = true);
      unawaited(_stopCamera());
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initializeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_streamGeneration;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      if (controller.value.isStreamingImages) unawaited(controller.stopImageStream());
      unawaited(controller.dispose());
    }
    unawaited(_detector?.close() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isFront = controller?.description.lensDirection == CameraLensDirection.front;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vista previa de cámara'),
        actions: [
          IconButton(
            key: const ValueKey('social-camera-switch'),
            tooltip: 'Cambiar cámara',
            onPressed: _cameras.length > 1 && !_loading ? _switchCamera : null,
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.no_photography_outlined, size: 48),
                              const SizedBox(height: 12),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(onPressed: _initializeCamera, child: const Text('Reintentar')),
                            ],
                          ),
                        )
                      : controller != null && controller.value.isInitialized
                          ? AspectRatio(
                              aspectRatio: controller.value.aspectRatio,
                              child: LayoutBuilder(builder: (context, _) {
                                return Stack(fit: StackFit.expand, children: [
                                  CameraPreview(controller),
                                  if (_filter != FaceStickerFilter.none)
                                    IgnorePointer(child: CustomPaint(
                                      key: const ValueKey('social-face-sticker-overlay'),
                                      painter: FaceStickerPainter(
                                        faces: _faces,
                                        filter: _filter,
                                        mirror: isFront,
                                      ),
                                    )),
                                ]);
                              }),
                            )
                          : const SizedBox.shrink(),
            ),
          ),
          _filterPicker(),
        ],
      ),
    );
  }

  Widget _filterPicker() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          _filterChoice(FaceStickerFilter.none, 'Sin filtro', 'none'),
          _filterChoice(FaceStickerFilter.dogEars, '🐶 Orejas', 'dog-ears'),
          _filterChoice(FaceStickerFilter.glasses, '😎 Gafas', 'glasses'),
          _filterChoice(FaceStickerFilter.crown, '👑 Corona', 'crown'),
        ],
      ),
    ),
  );

  Widget _filterChoice(FaceStickerFilter filter, String label, String keyName) => ChoiceChip(
    key: ValueKey('social-filter-$keyName'),
    label: Text(label),
    selected: _filter == filter,
    onSelected: (selected) => setState(() => _filter = filter),
  );
}

class FaceStickerFace {
  const FaceStickerFace({required this.bounds, required this.sourceSize, this.leftEye, this.rightEye});
  final Rect bounds;
  final Size sourceSize;
  final Point<int>? leftEye;
  final Point<int>? rightEye;
}

class FaceStickerPainter extends CustomPainter {
  const FaceStickerPainter({required this.faces, required this.filter, required this.mirror});
  final List<FaceStickerFace> faces;
  final FaceStickerFilter filter;
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    for (final face in faces) {
      final rect = mapFaceRectToPreview(face.bounds, face.sourceSize, size, mirror: mirror);
      final center = rect.center;
      final stickerHeight = rect.height * 0.48;
      final stickerWidth = rect.width * 0.40;
      switch (filter) {
        case FaceStickerFilter.none:
          break;
        case FaceStickerFilter.dogEars:
          _paintDogEars(canvas, rect, stickerHeight);
          break;
        case FaceStickerFilter.glasses:
          final left = face.leftEye == null
              ? Offset(rect.left + rect.width * .32, rect.top + rect.height * .42)
              : mapFacePointToPreview(Offset(face.leftEye!.x.toDouble(), face.leftEye!.y.toDouble()), face.sourceSize, size, mirror: mirror);
          final right = face.rightEye == null
              ? Offset(rect.left + rect.width * .68, rect.top + rect.height * .42)
              : mapFacePointToPreview(Offset(face.rightEye!.x.toDouble(), face.rightEye!.y.toDouble()), face.sourceSize, size, mirror: mirror);
          final midpoint = (left + right) / 2;
          _emoji(canvas, '🕶️', midpoint, (right - left).distance * 1.9);
          break;
        case FaceStickerFilter.crown:
          _emoji(canvas, '👑', Offset(center.dx, rect.top - stickerHeight * .3), stickerWidth * 1.5);
          break;
      }
    }
  }

  void _paintDogEars(Canvas canvas, Rect rect, double height) {
    final fill = Paint()..color = const Color(0xFF9C5A2E);
    final inner = Paint()..color = const Color(0xFFFFB5A1);
    final left = Path()
      ..moveTo(rect.left + rect.width * .12, rect.top + rect.height * .2)
      ..quadraticBezierTo(rect.left - rect.width * .08, rect.top - height * .5, rect.left + rect.width * .38, rect.top + rect.height * .08)
      ..close();
    final right = Path()
      ..moveTo(rect.right - rect.width * .12, rect.top + rect.height * .2)
      ..quadraticBezierTo(rect.right + rect.width * .08, rect.top - height * .5, rect.right - rect.width * .38, rect.top + rect.height * .08)
      ..close();
    canvas.drawPath(left, fill);
    canvas.drawPath(right, fill);
    canvas.drawOval(Rect.fromCenter(center: Offset(rect.left + rect.width * .16, rect.top + rect.height * .04), width: rect.width * .13, height: height * .45), inner);
    canvas.drawOval(Rect.fromCenter(center: Offset(rect.right - rect.width * .16, rect.top + rect.height * .04), width: rect.width * .13, height: height * .45), inner);
  }

  void _emoji(Canvas canvas, String value, Offset center, double height) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: TextStyle(fontSize: height.clamp(18, 180))),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant FaceStickerPainter oldDelegate) =>
      oldDelegate.faces != faces || oldDelegate.filter != filter || oldDelegate.mirror != mirror;
}
