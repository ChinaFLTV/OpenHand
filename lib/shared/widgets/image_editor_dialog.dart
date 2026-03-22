import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../l10n/app_localizations.dart';

class ImageEditorResult {
  const ImageEditorResult({required this.bytes});

  final Uint8List bytes;
}

Future<ImageEditorResult?> showImageEditorDialog(
  BuildContext context, {
  required Uint8List imageBytes,
}) {
  return showDialog<ImageEditorResult>(
    context: context,
    builder: (dialogContext) {
      return _ImageEditorDialog(imageBytes: imageBytes);
    },
  );
}

class _ImageEditorDialog extends StatefulWidget {
  const _ImageEditorDialog({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<_ImageEditorDialog> createState() => _ImageEditorDialogState();
}

class _ImageEditorDialogState extends State<_ImageEditorDialog> {
  static const double _previewMaxWidth = 620;
  static const double _previewHeight = 380;
  static const double _outputSide = 512;
  static const double _minCropSide = 72;

  img.Image? _orientedImage;
  Uint8List? _previewBytes;
  Rect? _cropRect;
  Size _previewSize = Size.zero;
  double _brightness = 1;
  double _contrast = 1;
  bool _isSaving = false;
  String? _errorMessage;
  Offset? _moveDragStartGlobalPosition;
  Rect? _moveDragStartRect;
  Offset? _resizeDragStartGlobalPosition;
  Rect? _resizeDragStartRect;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960, maxHeight: 880),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.imageEditorTitle,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.imageEditorCropHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPreviewPanel(context),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _canEdit
                                  ? () => _rotateImage(-90)
                                  : null,
                              icon: const Icon(Icons.rotate_left_rounded),
                              label: Text(l10n.imageEditorRotateLeft),
                            ),
                            OutlinedButton.icon(
                              onPressed: _canEdit
                                  ? () => _rotateImage(90)
                                  : null,
                              icon: const Icon(Icons.rotate_right_rounded),
                              label: Text(l10n.imageEditorRotateRight),
                            ),
                            TextButton.icon(
                              onPressed: _canEdit ? _resetAdjustments : null,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(l10n.imageEditorReset),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _EditorSlider(
                          label: l10n.imageEditorBrightnessLabel,
                          value: _brightness,
                          min: 0.6,
                          max: 1.4,
                          onChanged: _canEdit
                              ? (value) {
                                  setState(() {
                                    _brightness = value;
                                  });
                                }
                              : null,
                        ),
                        const SizedBox(height: 8),
                        _EditorSlider(
                          label: l10n.imageEditorContrastLabel,
                          value: _contrast,
                          min: 0.6,
                          max: 1.6,
                          onChanged: _canEdit
                              ? (value) {
                                  setState(() {
                                    _contrast = value;
                                  });
                                }
                              : null,
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_isSaving) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 132,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(l10n.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 132,
                      height: 52,
                      child: FilledButton(
                        onPressed: _canEdit && !_isSaving ? _handleSave : null,
                        child: Text(l10n.commonSave),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _canEdit => _orientedImage != null && _previewBytes != null;

  void _loadImage() {
    final decodedImage = img.decodeImage(widget.imageBytes);
    if (decodedImage == null) {
      return;
    }
    final bakedImage = img.bakeOrientation(decodedImage);
    _orientedImage = bakedImage;
    _previewBytes = Uint8List.fromList(img.encodePng(bakedImage));
    _cropRect = null;
  }

  Widget _buildPreviewPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final previewBytes = _previewBytes;
    final orientedImage = _orientedImage;

    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final previewWidth = math.min(constraints.maxWidth, _previewMaxWidth);
          final previewSize = Size(previewWidth, _previewHeight);
          _previewSize = previewSize;

          if (previewBytes == null || orientedImage == null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: SizedBox(
                width: previewWidth,
                height: _previewHeight,
                child: ColoredBox(
                  color: colorScheme.surfaceContainerHigh,
                  child: Center(child: Text(l10n.imageEditorLoadFailed)),
                ),
              ),
            );
          }

          final imageRect = _computeImageRect(previewSize, orientedImage);
          final cropRect = _resolvedCropRect(imageRect);

          return ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: SizedBox(
              width: previewWidth,
              height: _previewHeight,
              child: ColoredBox(
                color: colorScheme.surfaceContainerHigh,
                child: Stack(
                  children: [
                    Positioned.fromRect(
                      rect: imageRect,
                      child: ColorFiltered(
                        colorFilter: ColorFilter.matrix(
                          _buildPreviewColorMatrix(
                            brightness: _brightness,
                            contrast: _contrast,
                          ),
                        ),
                        child: Image.memory(previewBytes, fit: BoxFit.fill),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CropOverlayPainter(
                            imageRect: imageRect,
                            cropRect: cropRect,
                            overlayColor: colorScheme.scrim.withValues(
                              alpha: 0.28,
                            ),
                            borderColor: colorScheme.outline.withValues(
                              alpha: 0.78,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fromRect(
                      rect: cropRect,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.move,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) {
                            _moveDragStartGlobalPosition =
                                details.globalPosition;
                            _moveDragStartRect = cropRect;
                          },
                          onPanUpdate: (details) {
                            final startPosition = _moveDragStartGlobalPosition;
                            final startRect = _moveDragStartRect;
                            if (startPosition == null || startRect == null) {
                              return;
                            }
                            final delta =
                                details.globalPosition - startPosition;
                            setState(() {
                              _cropRect = _clampMovedCropRect(
                                startRect.shift(delta),
                                imageRect,
                              );
                            });
                          },
                          onPanEnd: (_) {
                            _moveDragStartGlobalPosition = null;
                            _moveDragStartRect = null;
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: colorScheme.primary,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: cropRect.right - 14,
                      top: cropRect.bottom - 14,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeUpLeftDownRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) {
                            _resizeDragStartGlobalPosition =
                                details.globalPosition;
                            _resizeDragStartRect = cropRect;
                          },
                          onPanUpdate: (details) {
                            final startPosition =
                                _resizeDragStartGlobalPosition;
                            final startRect = _resizeDragStartRect;
                            if (startPosition == null || startRect == null) {
                              return;
                            }
                            final delta =
                                details.globalPosition - startPosition;
                            final dominantDelta =
                                delta.dx.abs() > delta.dy.abs()
                                ? delta.dx
                                : delta.dy;
                            setState(() {
                              _cropRect = _resizeCropRect(
                                startRect,
                                imageRect,
                                dominantDelta,
                              );
                            });
                          },
                          onPanEnd: (_) {
                            _resizeDragStartGlobalPosition = null;
                            _resizeDragStartRect = null;
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.surface,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.open_in_full_rounded,
                              size: 14,
                              color: colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: imageRect.left + 12,
                      bottom: imageRect.bottom - 36,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            l10n.imageEditorCropHint,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _rotateImage(int angle) {
    final orientedImage = _orientedImage;
    if (orientedImage == null) {
      return;
    }
    final rotatedImage = img.copyRotate(orientedImage, angle: angle);
    setState(() {
      _orientedImage = rotatedImage;
      _previewBytes = Uint8List.fromList(img.encodePng(rotatedImage));
      _cropRect = null;
      _errorMessage = null;
    });
  }

  void _resetAdjustments() {
    setState(() {
      _brightness = 1;
      _contrast = 1;
      _cropRect = null;
      _errorMessage = null;
    });
  }

  Rect _resolvedCropRect(Rect imageRect) {
    final existingCropRect = _cropRect;
    if (existingCropRect == null) {
      return _initialCropRect(imageRect);
    }
    return _clampMovedCropRect(existingCropRect, imageRect);
  }

  Rect _initialCropRect(Rect imageRect) {
    final maxSide = math.min(imageRect.width, imageRect.height);
    final side = math.max(
      math.min(maxSide * 0.64, maxSide),
      math.min(_minCropSide, maxSide),
    );
    return Rect.fromCenter(center: imageRect.center, width: side, height: side);
  }

  Rect _computeImageRect(Size previewSize, img.Image image) {
    final scale = math.min(
      previewSize.width / image.width,
      previewSize.height / image.height,
    );
    final fittedWidth = image.width * scale;
    final fittedHeight = image.height * scale;
    final left = (previewSize.width - fittedWidth) / 2;
    final top = (previewSize.height - fittedHeight) / 2;
    return Rect.fromLTWH(left, top, fittedWidth, fittedHeight);
  }

  Rect _clampMovedCropRect(Rect candidate, Rect imageRect) {
    final minSide = math.min(
      _minCropSide,
      math.min(imageRect.width, imageRect.height),
    );
    final side = candidate.width.clamp(
      minSide,
      math.min(imageRect.width, imageRect.height),
    );
    final maxLeft = imageRect.right - side;
    final maxTop = imageRect.bottom - side;
    final left = candidate.left.clamp(imageRect.left, maxLeft).toDouble();
    final top = candidate.top.clamp(imageRect.top, maxTop).toDouble();
    return Rect.fromLTWH(left, top, side.toDouble(), side.toDouble());
  }

  Rect _resizeCropRect(Rect startRect, Rect imageRect, double sideDelta) {
    final minSide = math.min(
      _minCropSide,
      math.min(imageRect.width, imageRect.height),
    );
    final maxSide = math.min(
      imageRect.right - startRect.left,
      imageRect.bottom - startRect.top,
    );
    final side = (startRect.width + sideDelta).clamp(minSide, maxSide);
    return Rect.fromLTWH(
      startRect.left,
      startRect.top,
      side.toDouble(),
      side.toDouble(),
    );
  }

  List<double> _buildPreviewColorMatrix({
    required double brightness,
    required double contrast,
  }) {
    final translate = (1 - contrast) * 128 + (brightness - 1) * 255;
    return <double>[
      contrast,
      0,
      0,
      0,
      translate,
      0,
      contrast,
      0,
      0,
      translate,
      0,
      0,
      contrast,
      0,
      translate,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context)!;
    final orientedImage = _orientedImage;
    if (orientedImage == null || _previewSize == Size.zero) {
      setState(() {
        _errorMessage = l10n.imageEditorLoadFailed;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final imageRect = _computeImageRect(_previewSize, orientedImage);
      final cropRect = _resolvedCropRect(imageRect);
      final cropRegion = _computeCropRegion(orientedImage, imageRect, cropRect);
      var outputImage = img.copyCrop(
        orientedImage,
        x: cropRegion.x,
        y: cropRegion.y,
        width: cropRegion.size,
        height: cropRegion.size,
      );
      outputImage = img.copyResize(
        outputImage,
        width: _outputSide.toInt(),
        height: _outputSide.toInt(),
      );
      outputImage = img.adjustColor(
        outputImage,
        brightness: _brightness,
        contrast: _contrast,
      );
      final outputBytes = Uint8List.fromList(img.encodePng(outputImage));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(ImageEditorResult(bytes: outputBytes));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.imageEditorProcessFailed;
      });
    }
  }

  _SquareCropRegion _computeCropRegion(
    img.Image image,
    Rect imageRect,
    Rect cropRect,
  ) {
    final scaleX = image.width / imageRect.width;
    final scaleY = image.height / imageRect.height;
    final cropX = ((cropRect.left - imageRect.left) * scaleX)
        .round()
        .clamp(0, image.width - 1)
        .toInt();
    final cropY = ((cropRect.top - imageRect.top) * scaleY)
        .round()
        .clamp(0, image.height - 1)
        .toInt();
    final maxSize = math.min(image.width - cropX, image.height - cropY);
    final cropSize = (cropRect.width * scaleX)
        .round()
        .clamp(1, maxSize)
        .toInt();
    return _SquareCropRegion(x: cropX, y: cropY, size: cropSize);
  }
}

class _EditorSlider extends StatelessWidget {
  const _EditorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.imageRect,
    required this.cropRect,
    required this.overlayColor,
    required this.borderColor,
  });

  final Rect imageRect;
  final Rect cropRect;
  final Color overlayColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(imageRect),
        Path()..addRect(cropRect),
      ),
      Paint()..color = overlayColor,
    );
    canvas.drawRect(
      cropRect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final guidePaint = Paint()
      ..color = borderColor.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final horizontalThird = cropRect.height / 3;
    final verticalThird = cropRect.width / 3;
    for (var index = 1; index <= 2; index++) {
      final dy = cropRect.top + horizontalThird * index;
      final dx = cropRect.left + verticalThird * index;
      canvas.drawLine(
        Offset(cropRect.left, dy),
        Offset(cropRect.right, dy),
        guidePaint,
      );
      canvas.drawLine(
        Offset(dx, cropRect.top),
        Offset(dx, cropRect.bottom),
        guidePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return imageRect != oldDelegate.imageRect ||
        cropRect != oldDelegate.cropRect ||
        overlayColor != oldDelegate.overlayColor ||
        borderColor != oldDelegate.borderColor;
  }
}

class _SquareCropRegion {
  const _SquareCropRegion({
    required this.x,
    required this.y,
    required this.size,
  });

  final int x;
  final int y;
  final int size;
}
