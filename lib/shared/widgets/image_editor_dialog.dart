import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import 'animated_dialog.dart';

/// Result returned by [showImageEditorDialog] when the user confirms.
///
/// [bytes] always carries the encoded image (PNG when the editor opted into
/// transparency for circular crops, otherwise JPEG with the editor's
/// configured quality).
class ImageEditorResult {
  const ImageEditorResult({required this.bytes, required this.format});

  final Uint8List bytes;
  final String format; // 'png' | 'jpg'
}

/// Available crop aspect ratios.
enum _CropAspect {
  freeform,
  original,
  square,
  fourByThree,
  threeByFour,
  sixteenByNine,
  nineBySixteen,
  circle, // square crop with rounded mask + PNG transparency on save
}

/// Opens the in-app image editor on top of [imageBytes].
///
/// When [imageSizeLimitBytes] is provided the editor will progressively
/// compress its JPEG output to fit within the cap.
Future<ImageEditorResult?> showImageEditorDialog(
  BuildContext context, {
  required Uint8List imageBytes,
  int? imageSizeLimitBytes,
}) {
  return showAnimatedDialog<ImageEditorResult>(
    context: context,
    builder: (dialogContext) {
      return _ImageEditorDialog(
        imageBytes: imageBytes,
        imageSizeLimitBytes: imageSizeLimitBytes,
      );
    },
  );
}

class _ImageEditorDialog extends StatefulWidget {
  const _ImageEditorDialog({
    required this.imageBytes,
    this.imageSizeLimitBytes,
  });

  final Uint8List imageBytes;
  final int? imageSizeLimitBytes;

  @override
  State<_ImageEditorDialog> createState() => _ImageEditorDialogState();
}

class _ImageEditorDialogState extends State<_ImageEditorDialog> {
  static const double _previewMaxWidth = 720;
  static const double _previewHeight = 420;
  static const double _minCropSide = 64;
  static const int _maxOutputLongSide = 2048;

  /// The decoded source image (orientation baked, no edits applied).
  img.Image? _orientedImage;

  /// PNG bytes of [_orientedImage] used purely for on-screen preview.
  Uint8List? _previewBytes;

  Rect? _cropRect;
  Size _previewSize = Size.zero;

  // Color adjustments (preview applied via ColorFilter; full quality applied on save).
  double _brightness = 1.0; // 0.5..1.5
  double _contrast = 1.0; // 0.6..1.6
  double _saturation = 1.0; // 0.0..2.0
  double _exposure = 0.0; // -1.0..1.0 (extra brightness offset)
  double _hue = 0.0; // -180..180 degrees
  double _vignette = 0.0; // 0.0..1.0 (strength)
  double _rotation = 0.0; // -180..180 degrees, free rotation
  bool _flipHorizontal = false;
  bool _flipVertical = false;
  _CropAspect _aspect = _CropAspect.freeform;

  bool _isSaving = false;
  String? _errorMessage;
  String? _statusMessage;

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
          constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 920),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.imageEditorTitle,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.imageEditorCropHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPreviewPanel(context),
                        const SizedBox(height: 18),
                        _buildAspectChips(context),
                        const SizedBox(height: 12),
                        _buildTransformActions(context),
                        const SizedBox(height: 16),
                        _buildAdjustmentSliders(context),
                        if (_statusMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _statusMessage!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
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
                _buildActionBar(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────── UI sections ─────

  Widget _buildAspectChips(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final entries = <_CropAspect, String>{
      _CropAspect.freeform: l10n.imageEditorAspectFree,
      _CropAspect.original: l10n.imageEditorAspectOriginal,
      _CropAspect.square: l10n.imageEditorAspectSquare,
      _CropAspect.fourByThree: l10n.imageEditorAspect4x3,
      _CropAspect.threeByFour: l10n.imageEditorAspect3x4,
      _CropAspect.sixteenByNine: l10n.imageEditorAspect16x9,
      _CropAspect.nineBySixteen: l10n.imageEditorAspect9x16,
      _CropAspect.circle: l10n.imageEditorAspectCircle,
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in entries.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: _aspect == entry.key,
            onSelected: _canEdit
                ? (selected) {
                    if (!selected) {
                      return;
                    }
                    setState(() {
                      _aspect = entry.key;
                      _cropRect = null;
                    });
                  }
                : null,
          ),
      ],
    );
  }

  Widget _buildTransformActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        OutlinedButton.icon(
          onPressed: _canEdit ? () => _rotateImage(-90) : null,
          icon: const Icon(Icons.rotate_left_rounded),
          label: Text(l10n.imageEditorRotateLeft),
        ),
        OutlinedButton.icon(
          onPressed: _canEdit ? () => _rotateImage(90) : null,
          icon: const Icon(Icons.rotate_right_rounded),
          label: Text(l10n.imageEditorRotateRight),
        ),
        OutlinedButton.icon(
          onPressed: _canEdit
              ? () => setState(() => _flipHorizontal = !_flipHorizontal)
              : null,
          icon: const Icon(Icons.flip_rounded),
          label: Text(l10n.imageEditorFlipHorizontal),
        ),
        OutlinedButton.icon(
          onPressed: _canEdit
              ? () => setState(() => _flipVertical = !_flipVertical)
              : null,
          icon: const Icon(Icons.swap_vert_rounded),
          label: Text(l10n.imageEditorFlipVertical),
        ),
        TextButton.icon(
          onPressed: _canEdit ? _resetAdjustments : null,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.imageEditorReset),
        ),
      ],
    );
  }

  Widget _buildAdjustmentSliders(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorSlider(
          label: l10n.imageEditorBrightnessLabel,
          value: _brightness,
          min: 0.5,
          max: 1.5,
          onChanged: _canEdit
              ? (value) => setState(() => _brightness = value)
              : null,
        ),
        _EditorSlider(
          label: l10n.imageEditorContrastLabel,
          value: _contrast,
          min: 0.6,
          max: 1.6,
          onChanged: _canEdit
              ? (value) => setState(() => _contrast = value)
              : null,
        ),
        _EditorSlider(
          label: l10n.imageEditorSaturationLabel,
          value: _saturation,
          min: 0.0,
          max: 2.0,
          onChanged: _canEdit
              ? (value) => setState(() => _saturation = value)
              : null,
        ),
        _EditorSlider(
          label: l10n.imageEditorExposureLabel,
          value: _exposure,
          min: -1.0,
          max: 1.0,
          onChanged: _canEdit
              ? (value) => setState(() => _exposure = value)
              : null,
        ),
        _EditorSlider(
          label: l10n.imageEditorHueLabel,
          value: _hue,
          min: -180,
          max: 180,
          onChanged: _canEdit ? (value) => setState(() => _hue = value) : null,
        ),
        _EditorSlider(
          label: l10n.imageEditorVignetteLabel,
          value: _vignette,
          min: 0.0,
          max: 1.0,
          onChanged: _canEdit
              ? (value) => setState(() => _vignette = value)
              : null,
        ),
        _EditorSlider(
          label: l10n.imageEditorFineRotationLabel,
          value: _rotation,
          min: -180,
          max: 180,
          onChanged: _canEdit
              ? (value) => setState(() => _rotation = value)
              : null,
        ),
      ],
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _canEdit && !_isSaving ? _handleSaveToFile : null,
          icon: const Icon(Icons.download_rounded),
          label: Text(l10n.imageEditorSaveToFile),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _canEdit && !_isSaving ? _handleCopyToClipboard : null,
          icon: const Icon(Icons.copy_rounded),
          label: Text(l10n.imageEditorCopyToClipboard),
        ),
        const Spacer(),
        SizedBox(
          width: 132,
          height: 52,
          child: OutlinedButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 132,
          height: 52,
          child: FilledButton(
            onPressed: _canEdit && !_isSaving ? _handleConfirmSave : null,
            child: Text(l10n.commonSave),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────── Preview panel ─────

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
          final cropRect = _resolvedCropRect(imageRect, orientedImage);

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
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..rotateZ(_rotation * math.pi / 180.0)
                          ..scale(
                            _flipHorizontal ? -1.0 : 1.0,
                            _flipVertical ? -1.0 : 1.0,
                          ),
                        child: ColorFiltered(
                          colorFilter: ColorFilter.matrix(
                            _buildPreviewColorMatrix(),
                          ),
                          child: Image.memory(previewBytes, fit: BoxFit.fill),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CropOverlayPainter(
                            imageRect: imageRect,
                            cropRect: cropRect,
                            isCircle: _aspect == _CropAspect.circle,
                            overlayColor: colorScheme.scrim.withValues(
                              alpha: 0.32,
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
                          child: const SizedBox.expand(),
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
                            setState(() {
                              _cropRect = _resizeCropRect(
                                startRect,
                                imageRect,
                                delta,
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
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ────────────────────────────────────────────────── State / behaviour ─────

  bool get _canEdit => _orientedImage != null && _previewBytes != null;

  void _loadImage() {
    try {
      final decodedImage = img.decodeImage(widget.imageBytes);
      if (decodedImage == null) {
        return;
      }
      final bakedImage = img.bakeOrientation(decodedImage);
      _orientedImage = bakedImage;
      _previewBytes = Uint8List.fromList(img.encodePng(bakedImage));
    } catch (_) {
      // Corrupt or unsupported image — UI shows the load-failed placeholder.
    }
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
      _statusMessage = null;
    });
  }

  void _resetAdjustments() {
    setState(() {
      _brightness = 1;
      _contrast = 1;
      _saturation = 1;
      _exposure = 0;
      _hue = 0;
      _vignette = 0;
      _rotation = 0;
      _flipHorizontal = false;
      _flipVertical = false;
      _cropRect = null;
      _aspect = _CropAspect.freeform;
      _errorMessage = null;
      _statusMessage = null;
    });
  }

  Rect _resolvedCropRect(Rect imageRect, img.Image orientedImage) {
    final existing = _cropRect;
    if (existing == null) {
      return _initialCropRect(imageRect, orientedImage);
    }
    return _clampMovedCropRect(existing, imageRect);
  }

  Rect _initialCropRect(Rect imageRect, img.Image orientedImage) {
    final ratio = _targetAspectRatio(orientedImage);
    if (ratio == null) {
      // Freeform / original — fill image rect.
      return imageRect;
    }
    final maxWidth = imageRect.width;
    final maxHeight = imageRect.height;
    final candidateHeight = maxWidth / ratio;
    final fitWidth = candidateHeight <= maxHeight;
    final width = fitWidth ? maxWidth : maxHeight * ratio;
    final height = fitWidth ? candidateHeight : maxHeight;
    return Rect.fromCenter(
      center: imageRect.center,
      width: width,
      height: height,
    );
  }

  /// Returns `null` for freeform (caller treats as "any ratio").
  /// For [_CropAspect.original] returns the source image's aspect ratio so the
  /// crop matches the original frame. For [_CropAspect.circle] returns `1.0`
  /// (square) — the round mask is applied at save-time.
  double? _targetAspectRatio(img.Image orientedImage) {
    switch (_aspect) {
      case _CropAspect.freeform:
        return null;
      case _CropAspect.original:
        return orientedImage.width / orientedImage.height;
      case _CropAspect.square:
      case _CropAspect.circle:
        return 1.0;
      case _CropAspect.fourByThree:
        return 4.0 / 3.0;
      case _CropAspect.threeByFour:
        return 3.0 / 4.0;
      case _CropAspect.sixteenByNine:
        return 16.0 / 9.0;
      case _CropAspect.nineBySixteen:
        return 9.0 / 16.0;
    }
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
    final orientedImage = _orientedImage;
    if (orientedImage == null) {
      return candidate;
    }
    final ratio = _targetAspectRatio(orientedImage);
    var width = candidate.width;
    var height = candidate.height;
    final maxWidth = imageRect.width;
    final maxHeight = imageRect.height;
    width = width.clamp(_minCropSide, maxWidth);
    height = height.clamp(_minCropSide, maxHeight);
    if (ratio != null) {
      // Re-derive height from width to keep the requested ratio.
      height = width / ratio;
      if (height > maxHeight) {
        height = maxHeight;
        width = height * ratio;
      }
    }
    final maxLeft = imageRect.right - width;
    final maxTop = imageRect.bottom - height;
    final left = candidate.left.clamp(imageRect.left, maxLeft).toDouble();
    final top = candidate.top.clamp(imageRect.top, maxTop).toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  Rect _resizeCropRect(Rect startRect, Rect imageRect, Offset delta) {
    final orientedImage = _orientedImage;
    if (orientedImage == null) {
      return startRect;
    }
    final ratio = _targetAspectRatio(orientedImage);
    final dominant = delta.dx.abs() > delta.dy.abs() ? delta.dx : delta.dy;
    final maxWidth = imageRect.right - startRect.left;
    final maxHeight = imageRect.bottom - startRect.top;
    if (ratio != null) {
      final widthDelta = dominant;
      final width = (startRect.width + widthDelta)
          .clamp(_minCropSide, math.min(maxWidth, maxHeight * ratio))
          .toDouble();
      final height = width / ratio;
      return Rect.fromLTWH(startRect.left, startRect.top, width, height);
    }
    final width = (startRect.width + delta.dx)
        .clamp(_minCropSide, maxWidth)
        .toDouble();
    final height = (startRect.height + delta.dy)
        .clamp(_minCropSide, maxHeight)
        .toDouble();
    return Rect.fromLTWH(startRect.left, startRect.top, width, height);
  }

  /// Builds the 4x5 ColorFilter matrix used purely for the on-screen preview.
  ///
  /// Approximates: brightness + exposure → uniform offset; contrast → scale
  /// then re-center; saturation → blend with luminance; hue → simple
  /// rotation. This is intentionally not perfectly identical to the
  /// `package:image` adjustments applied on save: it just gives a "good
  /// enough" feedback so the user can dial in values quickly.
  List<double> _buildPreviewColorMatrix() {
    final brightness = _brightness;
    final contrast = _contrast;
    final saturation = _saturation;
    final hue = _hue;
    final exposure = _exposure * 80; // map -1..1 to roughly ±80 lumi offset
    final translate = (1 - contrast) * 128 + (brightness - 1) * 255 + exposure;

    // Saturation matrix: weights chosen for perceived luminance.
    const lumR = 0.2126;
    const lumG = 0.7152;
    const lumB = 0.0722;
    final sr = (1 - saturation) * lumR;
    final sg = (1 - saturation) * lumG;
    final sb = (1 - saturation) * lumB;

    // Hue rotation matrix (approximation).
    final hueRad = hue * math.pi / 180.0;
    final cosH = math.cos(hueRad);
    final sinH = math.sin(hueRad);

    // Combine: we apply contrast scale + brightness offset on top of hue
    // and saturation. Pre-compute per-channel coefficients.
    double r1 = (sr + saturation) * contrast;
    double r2 = sg * contrast;
    double r3 = sb * contrast;
    double g1 = sr * contrast;
    double g2 = (sg + saturation) * contrast;
    double g3 = sb * contrast;
    double b1 = sr * contrast;
    double b2 = sg * contrast;
    double b3 = (sb + saturation) * contrast;

    // Apply hue rotation onto chroma channels (simplified).
    final hr1 = r1 * cosH + r2 * sinH;
    final hr2 = r2 * cosH - r1 * sinH;
    final hg1 = g1 * cosH + g2 * sinH;
    final hg2 = g2 * cosH - g1 * sinH;
    r1 = hr1;
    r2 = hr2;
    g1 = hg1;
    g2 = hg2;

    return <double>[
      r1, r2, r3, 0, translate,
      g1, g2, g3, 0, translate,
      b1, b2, b3, 0, translate,
      0, 0, 0, 1, 0,
    ];
  }

  // ──────────────────────────────────────────────────────── Save flows ─────

  Future<void> _handleConfirmSave() async {
    final outputBytes = await _renderOutput();
    if (outputBytes == null || !mounted) {
      return;
    }
    Navigator.of(context).pop(
      ImageEditorResult(
        bytes: outputBytes,
        format: _aspect == _CropAspect.circle ? 'png' : 'jpg',
      ),
    );
  }

  Future<void> _handleSaveToFile() async {
    final l10n = AppLocalizations.of(context)!;
    final outputBytes = await _renderOutput();
    if (outputBytes == null || !mounted) {
      return;
    }
    final isPng = _aspect == _CropAspect.circle;
    try {
      final location = await getSaveLocation(
        suggestedName: 'image-${DateTime.now().millisecondsSinceEpoch}.${isPng ? 'png' : 'jpg'}',
        acceptedTypeGroups: <XTypeGroup>[
          XTypeGroup(
            label: isPng ? 'PNG' : 'JPEG',
            extensions: <String>[isPng ? 'png' : 'jpg'],
          ),
        ],
      );
      if (location == null) {
        return;
      }
      await File(location.path).writeAsBytes(outputBytes, flush: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = l10n.imageEditorSavedTo(location.path);
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = l10n.imageEditorSaveFailed(error.toString());
      });
    }
  }

  Future<void> _handleCopyToClipboard() async {
    final l10n = AppLocalizations.of(context)!;
    final outputBytes = await _renderOutput();
    if (outputBytes == null || !mounted) {
      return;
    }
    try {
      // Write a temp file so we can both share its path via the regular
      // Flutter clipboard AND, on macOS, push the bitmap into the system
      // clipboard via osascript so users can paste into image-aware apps.
      final tempDir = await Directory.systemTemp.createTemp('openhand_clip_');
      final ext = _aspect == _CropAspect.circle ? 'png' : 'jpg';
      final tempFile = File(p.join(tempDir.path, 'image.$ext'));
      await tempFile.writeAsBytes(outputBytes, flush: true);

      var bitmapCopied = false;
      if (Platform.isMacOS) {
        try {
          final result = await Process.run('osascript', <String>[
            '-e',
            'set the clipboard to (read POSIX file "${tempFile.path.replaceAll('"', r'\"')}") as ${ext == 'png' ? 'picture' : 'JPEG picture'}',
          ]);
          bitmapCopied = result.exitCode == 0;
        } catch (_) {
          bitmapCopied = false;
        }
      }

      // Always also push the file path so non-image-aware paste targets get
      // something useful.
      await Clipboard.setData(ClipboardData(text: tempFile.path));

      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = bitmapCopied
            ? l10n.imageEditorClipboardCopiedBitmap
            : l10n.imageEditorClipboardCopiedPath(tempFile.path);
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = l10n.imageEditorClipboardFailed(error.toString());
      });
    }
  }

  /// Materialises the final image. Returns `null` on failure (and updates
  /// [_errorMessage] in-place).
  Future<Uint8List?> _renderOutput() async {
    final l10n = AppLocalizations.of(context)!;
    final orientedImage = _orientedImage;
    if (orientedImage == null || _previewSize == Size.zero) {
      setState(() {
        _errorMessage = l10n.imageEditorLoadFailed;
      });
      return null;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      // 1) Compute crop in source-image coordinates from preview-space.
      final imageRect = _computeImageRect(_previewSize, orientedImage);
      final cropRect = _resolvedCropRect(imageRect, orientedImage);
      final cropRegion = _computeCropRegion(orientedImage, imageRect, cropRect);

      // 2) Apply free rotation first (if any), then flips, then crop.
      img.Image working = orientedImage;
      if (_rotation.abs() > 0.01) {
        working = img.copyRotate(working, angle: _rotation);
      }
      if (_flipHorizontal) {
        working = img.flipHorizontal(working);
      }
      if (_flipVertical) {
        working = img.flipVertical(working);
      }

      // Re-derive crop region against the (possibly rotated/flipped)
      // working image. To keep the math simple, re-fit crop proportionally.
      final scaleX = working.width / orientedImage.width;
      final scaleY = working.height / orientedImage.height;
      final cropX = (cropRegion.x * scaleX).round().clamp(0, working.width - 1);
      final cropY = (cropRegion.y * scaleY).round().clamp(0, working.height - 1);
      final cropW = (cropRegion.width * scaleX)
          .round()
          .clamp(1, working.width - cropX);
      final cropH = (cropRegion.height * scaleY)
          .round()
          .clamp(1, working.height - cropY);
      working = img.copyCrop(
        working,
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
      );

      // 3) Color adjustments (full quality).
      working = img.adjustColor(
        working,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
        exposure: _exposure,
        hue: _hue,
      );
      if (_vignette > 0) {
        working = img.vignette(working, amount: _vignette);
      }

      // 4) Optional circular mask (transparent corners → PNG).
      final isCircle = _aspect == _CropAspect.circle;
      if (isCircle) {
        working = _applyCircularMask(working);
      }

      // 5) Cap longest side to keep file size reasonable.
      final longSide = math.max(working.width, working.height);
      if (longSide > _maxOutputLongSide) {
        if (working.width >= working.height) {
          working = img.copyResize(working, width: _maxOutputLongSide);
        } else {
          working = img.copyResize(working, height: _maxOutputLongSide);
        }
      }

      // 6) Encode + optionally compress to limit.
      Uint8List outputBytes;
      if (isCircle) {
        outputBytes = Uint8List.fromList(img.encodePng(working));
      } else {
        outputBytes = Uint8List.fromList(img.encodeJpg(working, quality: 92));
        final limit = widget.imageSizeLimitBytes;
        if (limit != null && limit > 0 && outputBytes.length > limit) {
          for (var quality = 86; quality >= 30; quality -= 8) {
            outputBytes = Uint8List.fromList(
              img.encodeJpg(working, quality: quality),
            );
            if (outputBytes.length <= limit) {
              break;
            }
          }
          // If still too big, downscale progressively.
          while (outputBytes.length > limit &&
              working.width > 320 &&
              working.height > 320) {
            working = img.copyResize(
              working,
              width: (working.width * 0.8).round(),
            );
            outputBytes = Uint8List.fromList(
              img.encodeJpg(working, quality: 82),
            );
          }
        }
      }
      return outputBytes;
    } catch (_) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _errorMessage = l10n.imageEditorProcessFailed;
      });
      return null;
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Applies a circular alpha mask so corners outside the inscribed circle
  /// become fully transparent.
  img.Image _applyCircularMask(img.Image source) {
    final w = source.width;
    final h = source.height;
    final cx = w / 2.0;
    final cy = h / 2.0;
    final radius = math.min(cx, cy);
    final radiusSquared = radius * radius;
    final result = source.convert(numChannels: 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x - cx;
        final dy = y - cy;
        if (dx * dx + dy * dy > radiusSquared) {
          final pixel = result.getPixel(x, y);
          result.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, 0);
        }
      }
    }
    return result;
  }

  _CropRegion _computeCropRegion(
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
    final cropWidth = (cropRect.width * scaleX)
        .round()
        .clamp(1, image.width - cropX)
        .toInt();
    final cropHeight = (cropRect.height * scaleY)
        .round()
        .clamp(1, image.height - cropY)
        .toInt();
    return _CropRegion(x: cropX, y: cropY, width: cropWidth, height: cropHeight);
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                value.toStringAsFixed(2),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          Slider(value: value, min: min, max: max, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.imageRect,
    required this.cropRect,
    required this.isCircle,
    required this.overlayColor,
    required this.borderColor,
  });

  final Rect imageRect;
  final Rect cropRect;
  final bool isCircle;
  final Color overlayColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cropPath = isCircle
        ? (Path()..addOval(cropRect))
        : (Path()..addRect(cropRect));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(imageRect),
        cropPath,
      ),
      Paint()..color = overlayColor,
    );
    canvas.drawPath(
      cropPath,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (isCircle) {
      return;
    }
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
        isCircle != oldDelegate.isCircle ||
        overlayColor != oldDelegate.overlayColor ||
        borderColor != oldDelegate.borderColor;
  }
}

class _CropRegion {
  const _CropRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;
}
