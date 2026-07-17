import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;
import 'package:zxing2/qrcode.dart';

class QrCodeService {
  const QrCodeService._();

  /// Decodes away from the UI isolate because large article images are costly.
  static Future<String?> decode(Uint8List bytes) {
    return compute(decodeQrCodeBytes, bytes);
  }
}

/// Public synchronous entry point used by the background isolate and tests.
String? decodeQrCodeBytes(Uint8List bytes) {
  final decoded = image_lib.decodeImage(bytes);
  if (decoded == null) return null;

  // Cap resolution so large article screenshots stay interactive.
  final image = _limitSize(decoded, maxSide: 900);

  final result = _decodeLuminanceImage(image);
  if (result != null) return result;

  // One downscale pass helps dense / noisy phone screenshots.
  if (image.width > 320 && image.height > 320) {
    final smaller = image_lib.copyResize(
      image,
      width: (image.width * 0.65).round(),
      height: (image.height * 0.65).round(),
      interpolation: image_lib.Interpolation.average,
    );
    final smallerResult = _decodeLuminanceImage(smaller);
    if (smallerResult != null) return smallerResult;
  }

  return null;
}

image_lib.Image _limitSize(image_lib.Image image, {required int maxSide}) {
  final longest = image.width > image.height ? image.width : image.height;
  if (longest <= maxSide) return image;
  final scale = maxSide / longest;
  return image_lib.copyResize(
    image,
    width: (image.width * scale).round(),
    height: (image.height * scale).round(),
    interpolation: image_lib.Interpolation.average,
  );
}

String? _decodeLuminanceImage(image_lib.Image image) {
  final pixels = image
      .convert(numChannels: 4)
      .getBytes(order: image_lib.ChannelOrder.abgr);
  final pixelValues = Int32List.view(
    pixels.buffer,
    pixels.offsetInBytes,
    pixels.lengthInBytes ~/ 4,
  );
  final source = RGBLuminanceSource(image.width, image.height, pixelValues);
  final bitmap = BinaryBitmap(HybridBinarizer(source));

  try {
    return QRCodeReader().decode(bitmap).text;
  } on ReaderException {
    return null;
  }
}
