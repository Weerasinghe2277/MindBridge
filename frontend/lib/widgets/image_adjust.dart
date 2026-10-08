import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;

import '../core/theme.dart';
import 'page.dart';
import 'ui.dart';

/// Shape of the finished picture.
enum CropShape {
  /// Square picture shown in a circle (profile photos).
  circle(1, 512),

  /// 2:1 banner (article covers).
  wide(2, 1200);

  const CropShape(this.aspect, this.outputWidth);
  final double aspect; // width / height
  final int outputWidth; // pixels
}

/// Opens the photo editor: drag to move, pinch or use the slider to resize, with a live preview of
/// how it will look in the app. Returns the finished PNG, or null if the user cancels.
Future<Uint8List?> adjustImage(BuildContext context, {required Uint8List bytes, required CropShape shape, String title = 'Adjust photo'}) {
  return Navigator.of(context, rootNavigator: true).push<Uint8List>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => ImageAdjustScreen(bytes: bytes, shape: shape, title: title)),
  );
}

/// Lets the user choose a JPG, PNG or WebP picture. Large photos are fine: they're resized after adjusting.
Future<Uint8List?> pickImageBytes(BuildContext context) async {
  final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp']);
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  if (bytes.length > 20 * 1024 * 1024) {
    if (context.mounted) toast(context, 'That photo is too large. Choose one under 20 MB.');
    return null;
  }
  return bytes;
}

/// Downloads an image already in the app (e.g. the current profile photo) so it can be adjusted.
Future<Uint8List?> downloadImage(String url) async {
  try {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    return r.statusCode == 200 ? r.bodyBytes : null;
  } catch (_) {
    return null;
  }
}

class ImageAdjustScreen extends StatefulWidget {
  const ImageAdjustScreen({super.key, required this.bytes, required this.shape, required this.title});
  final Uint8List bytes;
  final CropShape shape;
  final String title;

  @override
  State<ImageAdjustScreen> createState() => _ImageAdjustScreenState();
}

class _ImageAdjustScreenState extends State<ImageAdjustScreen> {
  final _ctrl = TransformationController();
  final _boundary = GlobalKey();
  ui.Image? _image;
  String? _error;
  bool _saving = false;

  // Frame (crop window) size on screen, and the photo's size when it just covers the frame.
  Size _frame = Size.zero;
  Size _child = Size.zero;

  static const _minZoom = .5; // smaller than the frame: the rest is filled with white
  static const _maxZoom = 5.0;

  @override
  void initState() {
    super.initState();
    decodeImageFromList(widget.bytes).then((img) {
      if (mounted) setState(() => _image = img);
    }).catchError((Object _) {
      if (mounted) setState(() => _error = 'This file can’t be opened as a picture. Try a JPG or PNG.');
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Sizes the frame for the screen width and starts with the photo filling it, centred.
  void _layout(double maxWidth) {
    final w = math.min(maxWidth, 360.0);
    final frame = Size(w, w / widget.shape.aspect);
    if (frame == _frame || _image == null) return;
    final img = _image!;
    final cover = math.max(frame.width / img.width, frame.height / img.height);
    final first = _frame == Size.zero;
    _frame = frame;
    _child = Size(img.width * cover, img.height * cover);
    // Later size changes (e.g. rotating the phone) happen mid-build, when the controller's
    // listeners can't be told yet, so reset after this frame instead.
    if (first) {
      _setZoom(1, recentre: true);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setZoom(1, recentre: true);
      });
    }
  }

  double get _zoom => _ctrl.value.getMaxScaleOnAxis();

  /// 1 = photo fills the frame. Keeps the centre of the frame where it is unless [recentre].
  void _setZoom(double zoom, {bool recentre = false}) {
    zoom = zoom.clamp(_minZoom, _maxZoom);
    if (recentre) {
      final dx = (_frame.width - _child.width * zoom) / 2;
      final dy = (_frame.height - _child.height * zoom) / 2;
      _ctrl.value = Matrix4.translationValues(dx, dy, 0).multiplied(Matrix4.diagonal3Values(zoom, zoom, 1));
      return;
    }
    final f = zoom / _zoom;
    final c = _frame.center(Offset.zero);
    _ctrl.value = Matrix4.translationValues(c.dx, c.dy, 0)
        .multiplied(Matrix4.diagonal3Values(f, f, 1))
        .multiplied(Matrix4.translationValues(-c.dx, -c.dy, 0))
        .multiplied(_ctrl.value);
  }

  /// Zoom at which the whole photo fits inside the frame.
  double get _fitZoom => math.min(_frame.width / _child.width, _frame.height / _child.height);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: widget.shape.outputWidth / _frame.width);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      Navigator.of(context).pop(data!.buffer.asUint8List());
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        toast(context, 'Couldn’t prepare the picture. Please try again.');
      }
    }
  }

  /// The photo with the current position and size, cut to the frame. Used for the editor and
  /// for the small previews, so they always match.
  Widget _photo() => ColoredBox(
        color: Colors.white,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => Transform(transform: _ctrl.value, child: child),
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: SizedBox.fromSize(size: _child, child: RawImage(image: _image, fit: BoxFit.fill)),
            ),
          ),
        ),
      );

  Widget _preview(double width, {bool circle = false, double radius = 0}) {
    final h = width / widget.shape.aspect;
    final pic = SizedBox(width: width, height: h, child: FittedBox(fit: BoxFit.fill, child: SizedBox.fromSize(size: _frame, child: _photo())));
    return circle ? ClipOval(child: pic) : ClipRRect(borderRadius: BorderRadius.circular(radius), child: pic);
  }

  @override
  Widget build(BuildContext context) {
    final circle = widget.shape == CropShape.circle;
    if (_error != null) {
      return MbPage(title: widget.title, children: [BannerCard(tone: Tone.red, icon: 'error', text: _error)]);
    }
    if (_image == null) return MbPage(title: widget.title, children: const [Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))]);
    return LayoutBuilder(builder: (context, box) {
      _layout(box.maxWidth - 36);
      return MbPage(
        title: widget.title,
        children: [
          const Txt('Drag to move the photo. Pinch or use the slider to make it bigger or smaller.', size: TxtSize.sm),
          Center(
            child: SizedBox.fromSize(
              size: _frame,
              child: Stack(children: [
                RepaintBoundary(
                  key: _boundary,
                  child: ColoredBox(
                    color: Colors.white,
                    child: InteractiveViewer(
                      transformationController: _ctrl,
                      constrained: false,
                      minScale: _minZoom,
                      maxScale: _maxZoom,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      child: SizedBox.fromSize(size: _child, child: RawImage(image: _image, fit: BoxFit.fill)),
                    ),
                  ),
                ),
                // What will be kept: a circle for profile photos, the full frame for covers.
                IgnorePointer(child: CustomPaint(size: _frame, painter: _FramePainter(circle: circle))),
              ]),
            ),
          ),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => Row(children: [
              const MbIcon('photo_size_select_small', color: C.muted),
              Expanded(
                child: Slider(
                  value: _zoom.clamp(_minZoom, _maxZoom),
                  min: _minZoom,
                  max: _maxZoom,
                  activeColor: C.primary,
                  label: 'Size',
                  onChanged: (v) => _setZoom(v),
                ),
              ),
              const MbIcon('photo_size_select_large', color: C.muted),
            ]),
          ),
          ButtonGroup([
            MbButton('Fill the frame', kind: BtnKind.soft, icon: 'fit_screen', height: 42, fontSize: 14, onPressed: () => _setZoom(1, recentre: true)),
            MbButton('Show whole photo', kind: BtnKind.ghost, icon: 'zoom_out_map', height: 42, fontSize: 14, onPressed: () => _setZoom(_fitZoom, recentre: true)),
          ]),
          const SectionHeader('Preview'),
          MbCard(
            child: circle
                ? Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (final (size, label) in const [(88.0, 'Profile'), (44.0, 'Lists'), (32.0, 'Small')])
                      Column(children: [_preview(size, circle: true), const SizedBox(height: 6), Text(label, style: Ty.nunito(size: 12, color: C.muted))]),
                  ])
                : LayoutBuilder(builder: (context, b) => _preview(b.maxWidth, radius: 20)),
          ),
        ],
        foot: [
          MbButton('Use this photo', icon: 'check', loading: _saving, onPressed: _save),
          MbButton('Cancel', kind: BtnKind.ghost, onPressed: _saving ? null : () => Navigator.of(context).pop()),
        ],
      );
    });
  }
}

/// Dims everything outside the circle (profile photos) and outlines the frame.
class _FramePainter extends CustomPainter {
  const _FramePainter({required this.circle});
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    if (circle) {
      final hole = Path()..addOval(rect.deflate(1));
      final dim = Path.combine(PathOperation.difference, Path()..addRect(rect), hole);
      canvas.drawPath(dim, Paint()..color = const Color(0x99000000));
      canvas.drawOval(rect.deflate(1), line);
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(18)), line);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.circle != circle;
}
