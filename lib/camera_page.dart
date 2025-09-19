// lib/camera_page.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

/// Cámara para documentos en VERTICAL con:
/// - Máscara rectangular vertical (A4 portrait).
/// - Tap-to-focus SOLO dentro del rectángulo + botón "enfocar al centro".
/// - Zoom por pellizco, flash (off/auto/on/torch), cambiar cámara.
/// - Captura recortada: devuelve SOLO lo que está dentro del rectángulo.
///
/// Uso:
/// final XFile? shot = await Navigator.push(
///   context, MaterialPageRoute(builder: (_) => const CameraPage()),
/// );
/// if (shot != null) { /* usar shot.path */ }
class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;

  bool _isInitialized = false;
  bool _isBusy = false;

  // Rectángulo guía: A4 vertical => width/height ~= 1/√2 ≈ 0.707
  // (antes estaba horizontal con 1.414; ahora lo invertimos)
  double _targetAspect = 1 / 1.41421356237;
  // Margen relativo al lado corto para que no ocupe toda la pantalla
  double _frameMarginPct = 0.07;

  // Flash y zoom
  FlashMode _flashMode = FlashMode.off;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 4.0;

  CameraDescription? _activeCamera;

  // Visual del foco
  Offset? _lastFocusPoint;
  DateTime? _lastFocusTs;

  List<DeviceOrientation>? _prevOrientations;

 @override
 void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  _lockPortrait();
  _initCameras();
}

  @override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  _controller?.dispose();
  _unlockOrientations();
  super.dispose();
}

 /// Bloquea la pantalla a vertical (portrait)
Future<void> _lockPortrait() async {
  await SystemChrome.setPreferredOrientations(
    [DeviceOrientation.portraitUp],
  );
}
  /// Restaura todas las orientaciones permitidas
Future<void> _unlockOrientations() async {
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _rebuildController(_activeCamera);
    }
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      final back = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.isNotEmpty ? _cameras.first : throw 'No hay cámaras disponibles',
      );
      _activeCamera = back;
      await _rebuildController(_activeCamera);
    } catch (e) {
      if (mounted) _snack('No se pudo iniciar la cámara: $e');
    }
  }

  Future<void> _rebuildController(CameraDescription? cam) async {
    if (cam == null) return;
    setState(() {
      _isInitialized = false;
      _isBusy = true;
    });

    _controller?.dispose();
    final controller = CameraController(
      cam,
      ResolutionPreset.max,
      imageFormatGroup: ImageFormatGroup.jpeg,
      enableAudio: false,
    );
    _controller = controller;

    try {
      await controller.initialize();
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      _currentZoom = _minZoom;
      await controller.setFlashMode(_flashMode);

      setState(() => _isInitialized = true);
    } catch (e) {
      _snack('Error al inicializar la cámara: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleCamera() async {
    if (_cameras.isEmpty) return;
    final current = _activeCamera;
    CameraDescription? next;
    if (current == null) {
      next = _cameras.first;
    } else {
      final idx = _cameras.indexOf(current);
      next = _cameras[(idx + 1) % _cameras.length];
    }
    _activeCamera = next;
    await _rebuildController(next);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    final order = <FlashMode>[
      FlashMode.off,
      FlashMode.auto,
      FlashMode.always,
      FlashMode.torch,
    ];
    final i = order.indexOf(_flashMode);
    final next = order[(i + 1) % order.length];
    try {
      await _controller!.setFlashMode(next);
      setState(() => _flashMode = next);
    } catch (e) {
      _snack('No se pudo cambiar el flash: $e');
    }
  }

  IconData _flashIcon(FlashMode mode) {
    switch (mode) {
      case FlashMode.off:
        return Icons.flash_off_rounded;
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      case FlashMode.always:
        return Icons.flash_on_rounded;
      case FlashMode.torch:
        return Icons.flashlight_on_rounded;
    }
  }

  Rect _computeDocRect(Size size) {
    final w = size.width;
    final h = size.height;

    final m = _frameMarginPct * math.min(w, h);
    final usable = Rect.fromLTWH(m, m, w - 2 * m, h - 2 * m);

    final usableAspect = usable.width / usable.height; // w/h
    late Rect doc;
    if (usableAspect > _targetAspect) {
      // Muy ancho -> limitar por alto (queremos vertical)
      final targetW = usable.height * _targetAspect;
      final dx = (usable.width - targetW) / 2;
      doc = Rect.fromLTWH(usable.left + dx, usable.top, targetW, usable.height);
    } else {
      // Muy alto -> limitar por ancho
      final targetH = usable.width / _targetAspect;
      final dy = (usable.height - targetH) / 2;
      doc = Rect.fromLTWH(usable.left, usable.top + dy, usable.width, targetH);
    }
    return doc;
  }

  bool _insideDoc(Offset p, Rect r) => r.contains(p);

  Future<void> _focusAtOffset(Offset localTap, Size widgetSize) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    final offset = Offset(
      localTap.dx / widgetSize.width,
      localTap.dy / widgetSize.height,
    );
    try {
      await ctrl.setFocusPoint(offset);
      await ctrl.setExposurePoint(offset);
      setState(() {
        _lastFocusPoint = localTap;
        _lastFocusTs = DateTime.now();
      });
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        if (_lastFocusTs != null &&
            DateTime.now().difference(_lastFocusTs!) >
                const Duration(milliseconds: 800)) {
          setState(() => _lastFocusPoint = null);
        }
      });
    } catch (e) {
      _snack('No se pudo enfocar: $e');
    }
  }

  Future<void> _focusCenter(Size widgetSize) async {
    await _focusAtOffset(_computeDocRect(widgetSize).center, widgetSize);
  }

  Future<void> _onTapDown(TapDownDetails d, BoxConstraints c) async {
    final size = c.biggest;
    final doc = _computeDocRect(size);
    if (!_insideDoc(d.localPosition, doc)) {
      _snack('Toca dentro del rectángulo para enfocar');
      return;
    }
    await _focusAtOffset(d.localPosition, size);
  }

  Future<void> _onScale(double scale) async {
    final ctrl = _controller;
    if (ctrl == null) return;
    _currentZoom = (_currentZoom * scale).clamp(_minZoom, _maxZoom);
    try {
      await ctrl.setZoomLevel(_currentZoom);
    } catch (_) {}
    setState(() {});
  }

  /// Captura y RECORTA a lo que hay dentro del rectángulo guía.
  Future<void> _captureCropped(Size widgetSize) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (_isBusy) return;

    setState(() => _isBusy = true);
    try {
      final xfile = await ctrl.takePicture();

      // Leemos imagen real
      final bytes = await File(xfile.path).readAsBytes();
      final src = img.decodeImage(bytes);
      if (src == null) {
        throw 'No se pudo decodificar la imagen';
      }

      // Mapeo del rectángulo del widget (CameraPreview con BoxFit.cover)
      final Rect docRectWidget = _computeDocRect(widgetSize);

      // Dimensiones reales de la imagen (ya rotada por camera)
      final imgW = src.width.toDouble();
      final imgH = src.height.toDouble();

      // BoxFit.cover: escalamos la imagen para cubrir el widget
      final widgetW = widgetSize.width;
      final widgetH = widgetSize.height;

      final scale = math.max(widgetW / imgW, widgetH / imgH);
      final displayedW = imgW * scale;
      final displayedH = imgH * scale;

      // offsets (pueden ser negativos si recorta)
      final offsetX = (widgetW - displayedW) / 2.0;
      final offsetY = (widgetH - displayedH) / 2.0;

      // Función para mapear coordenadas del widget -> a la imagen real
      Offset widgetToImage(Offset p) {
        final dx = (p.dx - offsetX) / scale;
        final dy = (p.dy - offsetY) / scale;
        return Offset(dx.clamp(0, imgW - 1), dy.clamp(0, imgH - 1));
      }

      final topLeftImg = widgetToImage(docRectWidget.topLeft);
      final bottomRightImg = widgetToImage(docRectWidget.bottomRight);

      // Rect recorte en enteros y dentro del rango
      int cropX = topLeftImg.dx.floor();
      int cropY = topLeftImg.dy.floor();
      int cropW = (bottomRightImg.dx - topLeftImg.dx).round();
      int cropH = (bottomRightImg.dy - topLeftImg.dy).round();

      if (cropX < 0) cropX = 0;
      if (cropY < 0) cropY = 0;
      if (cropX + cropW > imgW) cropW = imgW.toInt() - cropX;
      if (cropY + cropH > imgH) cropH = imgH.toInt() - cropY;

      final cropped = img.copyCrop(
        src,
        x: cropX,
        y: cropY,
        width: math.max(1, cropW),
        height: math.max(1, cropH),
      );

      // Guardar recorte a un archivo temporal
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final outPath = '${dir.path}/doc_cropped_$ts.jpg';
      final outFile = File(outPath)..writeAsBytesSync(img.encodeJpg(cropped, quality: 95));

      if (!mounted) return;
      Navigator.of(context).pop(XFile(outFile.path));
    } catch (e) {
      _snack('No se pudo capturar/recortar: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: !_isInitialized || ctrl == null
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  final docRect = _computeDocRect(size);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Preview + gestos
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => _onTapDown(d, constraints),
                        onScaleUpdate: (details) {
                          if (details.scale != 1.0) {
                            _onScale(details.scale);
                          }
                        },
                        child: CameraPreview(ctrl),
                      ),

                      // Máscara vertical (menos oscura)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _DocMaskPainter(docRect: docRect),
                          size: Size.infinite,
                        ),
                      ),

                      // Ring de enfoque
                      if (_lastFocusPoint != null)
                        Positioned(
                          left: _lastFocusPoint!.dx - 34,
                          top: _lastFocusPoint!.dy - 34,
                          child: IgnorePointer(
                            ignoring: true,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.yellow, width: 2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),

                      // Top bar (cerrar + indicador de zoom)
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _roundIcon(
                              icon: Icons.close_rounded,
                              onTap: () => Navigator.of(context).pop(),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_currentZoom.toStringAsFixed(1)}x',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Botones laterales: flash / enfocar al centro / cambiar cámara
                      Positioned(
                        right: 8,
                        top: 70,
                        child: Column(
                          children: [
                            _roundIcon(
                              icon: _flashIcon(_flashMode),
                              onTap: _toggleFlash,
                            ),
                            const SizedBox(height: 10),
                            _roundIcon(
                              icon: Icons.center_focus_strong_rounded,
                              tooltip: 'Enfocar al centro del rectángulo',
                              onTap: () => _focusCenter(size),
                            ),
                            const SizedBox(height: 10),
                            _roundIcon(
                              icon: Icons.flip_camera_android_rounded,
                              onTap: _toggleCamera,
                            ),
                          ],
                        ),
                      ),

                      // Disparador (recorte)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 18,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () => _captureCropped(size),
                              child: Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _isBusy ? Colors.grey : Colors.white,
                                    width: 6,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _roundIcon({
    required IconData icon,
    String? tooltip,
    required VoidCallback onTap,
  }) {
    final btn = InkResponse(
      onTap: onTap,
      radius: 30,
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip, child: btn);
  }
}

/// Máscara vertical: fondo ligeramente oscuro con "agujero" del rectángulo.
/// El fondo se dejó menos oscuro para que no se vea “negra” la cámara.
class _DocMaskPainter extends CustomPainter {
  final Rect docRect;
  _DocMaskPainter({required this.docRect});

  @override
  void paint(Canvas canvas, Size size) {
    // Fondo más claro (antes 0xAA000000); ahora 0x66000000
    final bg = Paint()..color = const Color(0x66000000);
    canvas.drawRect(Offset.zero & size, bg);

    // Crea "agujero" transparente
    final clear = Paint()..blendMode = BlendMode.clear;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(docRect, clear);
    canvas.restore();

    // Borde y esquinas
    final border = Paint()
      ..color = Colors.white.withOpacity(0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawRect(docRect, border);

    final corner = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 24.0;

    void cornerMarks(Offset o, {bool tl = false, bool tr = false, bool bl = false, bool br = false}) {
      if (tl) {
        canvas.drawLine(o, o + const Offset(len, 0), corner);
        canvas.drawLine(o, o + const Offset(0, len), corner);
      }
      if (tr) {
        canvas.drawLine(o, o + const Offset(-len, 0), corner);
        canvas.drawLine(o, o + const Offset(0, len), corner);
      }
      if (bl) {
        canvas.drawLine(o, o + const Offset(len, 0), corner);
        canvas.drawLine(o, o + const Offset(0, -len), corner);
      }
      if (br) {
        canvas.drawLine(o, o + const Offset(-len, 0), corner);
        canvas.drawLine(o, o + const Offset(0, -len), corner);
      }
    }

    cornerMarks(docRect.topLeft, tl: true);
    cornerMarks(docRect.topRight, tr: true);
    cornerMarks(docRect.bottomLeft, bl: true);
    cornerMarks(docRect.bottomRight, br: true);
  }

  @override
  bool shouldRepaint(covariant _DocMaskPainter oldDelegate) =>
      oldDelegate.docRect != docRect;
}
