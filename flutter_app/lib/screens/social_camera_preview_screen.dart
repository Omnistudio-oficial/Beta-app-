import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// User-initiated live camera preview for the Social face-filter work.
/// Face landmarks and overlays are deliberately not represented until a
/// licensed MediaPipe model and native Android/iOS inference bridge are added.
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (_initializing) return;
    _initializing = true;
    if (mounted) setState(() { _loading = true; _error = null; });
    CameraController? controller;
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('NoCamera', 'No camera is available.');
      _cameraIndex %= _cameras.length;
      controller = CameraController(_cameras[_cameraIndex], ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final old = _controller;
      _controller = controller;
      controller = null;
      if (old != null) await old.dispose();
      setState(() { _loading = false; _error = null; });
    } on CameraException catch (error) {
      if (mounted) setState(() { _loading = false; _error = _cameraError(error); });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'No se pudo iniciar la cámara.'; });
    } finally {
      await controller?.dispose();
      _initializing = false;
    }
  }

  String _cameraError(CameraException error) {
    if (error.code.startsWith('CameraAccessDenied')) {
      return 'Se necesita permiso de cámara para mostrar la vista previa.';
    }
    return 'No se pudo iniciar la cámara.';
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _initializing) return;
    final old = _controller;
    _controller = null;
    if (mounted) setState(() { _loading = true; _error = null; });
    await old?.dispose();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      final controller = _controller;
      _controller = null;
      if (mounted) setState(() => _loading = true);
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initializeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
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
                              child: CameraPreview(controller),
                            )
                          : const SizedBox.shrink(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Text(
              'Los filtros faciales aún no están disponibles. Esta pantalla muestra solo la cámara.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
