part of 'camera_ml_vision.dart';

Future<CameraDescription?> _getCamera(CameraLensDirection dir) async {
  final cameras = await availableCameras();
  final camera =
      cameras.firstWhereOrNull((camera) => camera.lensDirection == dir);
  return camera ?? (cameras.isEmpty ? null : cameras.first);
}

Uint8List _concatenatePlanes(List<Plane> planes) {
  final allBytes = WriteBuffer();
  for (var plane in planes) {
    allBytes.putUint8List(plane.bytes);
  }
  return allBytes.done().buffer.asUint8List();
}

InputImageData buildMetaData(
  CameraImage image,
  InputImageRotation rotation,
) {
  return InputImageData(
    inputImageFormat: InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21,
    size: Size(image.width.toDouble(), image.height.toDouble()),
    imageRotation: rotation,
    planeData: image.planes
        .map(
          (plane) => InputImagePlaneMetadata(
            bytesPerRow: plane.bytesPerRow,
            height: plane.height,
            width: plane.width,
          ),
        )
        .toList(),
  );
}

Future<T> _detect<T>(
  CameraImage image,
  HandleDetection<T> handleDetection,
  InputImageRotation rotation,
) async {
  return handleDetection(
    InputImage.fromBytes(
      bytes: _concatenatePlanes(image.planes),
      inputImageData: buildMetaData(image, rotation),
    ),
  );
}

InputImageRotation _rotationIntToImageRotation(int rotation) {
  switch (rotation) {
    case 0:
      return InputImageRotation.rotation0deg;
    case 90:
      return InputImageRotation.rotation90deg;
    case 180:
      return InputImageRotation.rotation180deg;
    default:
      assert(rotation == 270);
      return InputImageRotation.rotation270deg;
  }
}
