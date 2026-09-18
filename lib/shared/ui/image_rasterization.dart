import 'dart:typed_data';
import 'dart:ui' as ui;

/// 只解码首帧并释放解码器；返回的图像由调用方释放。
Future<ui.Image> decodeFirstImageFrame(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// 栅格化后释放绘图指令；返回的图像由调用方释放。
Future<ui.Image> rasterizePicture(
  ui.Picture picture,
  int width,
  int height,
) async {
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}
