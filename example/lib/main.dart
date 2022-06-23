import 'package:camera_face_detector/camera_face_detector.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Face> _faces = [];
  final _scanKey = GlobalKey<CameraMlVisionState>();
  CameraLensDirection cameraLensDirection = CameraLensDirection.front;
  FaceDetector detector = FaceDetector(
      options: FaceDetectorOptions(
    enableTracking: true,
    performanceMode: FaceDetectorMode.accurate,
  ));

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: SizedBox.expand(
        child: CameraMlVision<List<Face>>(
          key: _scanKey,
          cameraLensDirection: cameraLensDirection,
          detector: detector.processImage,
          overlayBuilder: (c) {
            return CustomPaint(
              painter: FaceDetectorPainter(
                  _scanKey.currentState!.cameraValue!.previewSize!.flipped,
                  _faces,
                  reflection: cameraLensDirection == CameraLensDirection.front),
            );
          },
          onResult: (faces) {
            if (faces.isEmpty || !mounted) {
              return;
            }
            setState(() {
              _faces = [...faces];
            });
          },
          onDispose: () {
            detector.close();
          },
        ),
      ),
    );
  }
}

class FaceDetectorPainter extends CustomPainter {
  FaceDetectorPainter(this.imageSize, this.faces, {this.reflection = false});

  final bool reflection;
  final Size imageSize;
  final List<Face> faces;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.red;

    for (final face in faces) {
      final faceRect =
          _reflectionRect(reflection, face.boundingBox, imageSize.width);
      canvas.drawRect(
        _scaleRect(
          rect: faceRect,
          imageSize: imageSize,
          widgetSize: size,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return oldDelegate.imageSize != imageSize || oldDelegate.faces != faces;
  }
}

Rect _reflectionRect(bool reflection, Rect boundingBox, double width) {
  if (!reflection) {
    return boundingBox;
  }
  final centerX = width / 2;
  final left = ((boundingBox.left - centerX) * -1) + centerX;
  final right = ((boundingBox.right - centerX) * -1) + centerX;
  return Rect.fromLTRB(left, boundingBox.top, right, boundingBox.bottom);
}

Rect _scaleRect({
  required Rect rect,
  required Size imageSize,
  required Size widgetSize,
}) {
  final scaleX = widgetSize.width / imageSize.width;
  final scaleY = widgetSize.height / imageSize.height;

  final scaledRect = Rect.fromLTRB(
    rect.left.toDouble() * scaleX,
    rect.top.toDouble() * scaleY,
    rect.right.toDouble() * scaleX,
    rect.bottom.toDouble() * scaleY,
  );
  return scaledRect;
}
