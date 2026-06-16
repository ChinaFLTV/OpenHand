import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../app/theme/openhand_status_colors.dart';
import '../../l10n/app_localizations.dart';
import 'animated_dialog.dart';
import 'highlight_pulse.dart';
import 'openhand_dialog_action_button.dart';
import 'openhand_snack_bar.dart';

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

/// Anchor positions for the optional text watermark.
enum _WatermarkPosition {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  middleCenter,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
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

  /// Width / height of the oriented source image. All actual pixel data
  /// lives exclusively in [_previewBytes] (PNG-encoded) and is only decoded
  /// inside background isolates — never on the UI thread.
  int _imageWidth = 0;
  int _imageHeight = 0;

  /// PNG bytes of the current source image, used for on-screen preview
  /// via [Image.memory] and as the input for every isolate render call.
  Uint8List? _previewBytes;

  /// Original oriented source (never mutated after initial load). Used by
  /// hold-to-compare and reset-all.
  Uint8List? _originalPreviewBytes;
  int _originalImageWidth = 0;
  int _originalImageHeight = 0;

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

  // ── Advanced adjustments (applied at save-time through package:image) ──
  double _temperature = 0.0; // -100..100 (warm/cool)
  double _tint = 0.0; // -100..100 (green/magenta)
  double _gamma = 1.0; // 0.5..2.0 (tone curve)
  double _shadowHue = 210.0; // 0..360 degrees
  double _shadowStrength = 0.0; // 0..100
  double _highlightHue = 45.0; // 0..360 degrees
  double _highlightStrength = 0.0; // 0..100
  double _clarity = 0.0; // 0..100 (unsharp-like via convolution)
  double _sharpness = 0.0; // 0..100 (convolution sharpen)
  double _denoise = 0.0; // 0..100 (gaussian blur radius)
  double _grain = 0.0; // 0..100 (noise sigma)
  double _dispersion = 0.0; // 0..20 px channel shift
  double _distort = 0.0; // -100..100 (negative=stretch, positive=bulge)

  // Watermark / text mark.
  final TextEditingController _watermarkController = TextEditingController();
  double _watermarkSize = 48.0; // 12..160 px (rendered size on output)
  double _watermarkOpacity = 0.85;
  _WatermarkPosition _watermarkPosition = _WatermarkPosition.bottomRight;
  double _watermarkHue = 0.0; // 0..360
  double _watermarkSaturation = 0.0; // 0..1
  double _watermarkLightness = 0.94; // 0..1

  bool _isSaving = false;
  bool _isProcessing = false;
  bool _showOriginalPreview = false;
  bool _previewCompareScheduled = false;
  bool _hasBakedChanges = false;
  String? _errorMessage;
  String? _statusMessage;

  /// Undo stack: stores (previewBytes, width, height) snapshots.
  final List<(Uint8List, int, int)> _undoStack = [];
  static const int _maxUndoDepth = 20;

  Offset? _moveDragStartGlobalPosition;
  Rect? _moveDragStartRect;
  Offset? _resizeDragStartGlobalPosition;
  Rect? _resizeDragStartRect;

  /// Key for the local [ScaffoldMessenger] inside this dialog so that
  /// snackbars appear within the dialog surface, not behind it.
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Increments after each significant in-dialog action lands (currently
  /// reset-all + reset-adjustments). Drives the top-edge [HighlightPulse]
  /// to confirm the user's action without an extra SnackBar.
  final ValueNotifier<int> _actionPulse = ValueNotifier<int>(0);

  /// Increments after every successful SnackBar confirmation; drives the
  /// green top-edge confirmation flash.
  final ValueNotifier<int> _successPulse = ValueNotifier<int>(0);

  /// Increments after every error SnackBar; drives the red top-edge
  /// failure flash.
  final ValueNotifier<int> _errorPulse = ValueNotifier<int>(0);

  void _firePulse() => _actionPulse.value = _actionPulse.value + 1;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _watermarkController.dispose();
    _actionPulse.dispose();
    _successPulse.dispose();
    _errorPulse.dispose();
    _dismissProcessingOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: !_isSaving && !_isProcessing,
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 920),
          child: ScaffoldMessenger(
            key: _messengerKey,
            child: Scaffold(
              backgroundColor: colorScheme.surfaceContainerHigh,
              // 2026-05 — Stack the Scaffold body with a top-edge
              // HighlightPulse so user-triggered "important" actions
              // (currently reset-all / reset-adjustments) get a brief
              // primary-tinted confirmation flash. Honors reduceMotion
              // via the pulse widget itself.
              body: Stack(
                children: [
                  Padding(
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
                                const SizedBox(height: 8),
                                _buildAdvancedPanels(context),
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
                        if (_isSaving || _isProcessing) ...[
                          const SizedBox(height: 16),
                          const LinearProgressIndicator(),
                        ],
                        const SizedBox(height: 16),
                        _buildActionBar(context),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: HighlightPulse(signal: _actionPulse),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: HighlightPulse(
                        signal: _successPulse,
                        color: OpenHandStatusColors.success,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: HighlightPulse(
                        signal: _errorPulse,
                        color: OpenHandStatusColors.error,
                      ),
                    ),
                  ),
                ],
              ),
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
    // Uniform pill-style button styling so every capsule in the row shares
    // the exact same height, padding and shape, matching the outlined chips
    // above and giving the whole bar a consistent rhythm.
    final pillStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const StadiumBorder(),
    );
    Widget pill({
      required VoidCallback? onPressed,
      required IconData icon,
      required String label,
    }) {
      return SizedBox(
        height: 40,
        child: OutlinedButton.icon(
          style: pillStyle,
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        pill(
          onPressed: _canEdit ? () => _rotateImage(-90) : null,
          icon: Icons.rotate_left_rounded,
          label: l10n.imageEditorRotateLeft,
        ),
        pill(
          onPressed: _canEdit ? () => _rotateImage(90) : null,
          icon: Icons.rotate_right_rounded,
          label: l10n.imageEditorRotateRight,
        ),
        pill(
          onPressed: _canEdit
              ? () => setState(() => _flipHorizontal = !_flipHorizontal)
              : null,
          icon: Icons.flip_rounded,
          label: l10n.imageEditorFlipHorizontal,
        ),
        pill(
          onPressed: _canEdit
              ? () => setState(() => _flipVertical = !_flipVertical)
              : null,
          icon: Icons.swap_vert_rounded,
          label: l10n.imageEditorFlipVertical,
        ),
        pill(
          onPressed: _canEdit ? _resetAdjustments : null,
          icon: Icons.refresh_rounded,
          label: l10n.imageEditorReset,
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

  // ─────────────────────────────────────────────────── Advanced panels ─────

  Widget _buildAdvancedPanels(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hint = Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
      child: Text(
        l10n.imageEditorAdvancedApplyHint,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        hint,
        _AdvancedSection(
          title: l10n.imageEditorSectionColor,
          children: [
            _EditorSlider(
              label: l10n.imageEditorTemperatureLabel,
              value: _temperature,
              min: -100,
              max: 100,
              onChanged: _canEdit
                  ? (v) => setState(() => _temperature = v)
                  : null,
            ),
            _EditorSlider(
              label: l10n.imageEditorTintLabel,
              value: _tint,
              min: -100,
              max: 100,
              onChanged: _canEdit ? (v) => setState(() => _tint = v) : null,
            ),
            _EditorSlider(
              label: l10n.imageEditorGammaLabel,
              value: _gamma,
              min: 0.5,
              max: 2.0,
              onChanged: _canEdit ? (v) => setState(() => _gamma = v) : null,
            ),
          ],
        ),
        _AdvancedSection(
          title: l10n.imageEditorSectionSplitToning,
          children: [
            _EditorSlider(
              label: l10n.imageEditorShadowHueLabel,
              value: _shadowHue,
              min: 0,
              max: 360,
              onChanged: _canEdit
                  ? (v) => setState(() => _shadowHue = v)
                  : null,
            ),
            _EditorSlider(
              label: l10n.imageEditorShadowStrengthLabel,
              value: _shadowStrength,
              min: 0,
              max: 100,
              onChanged: _canEdit
                  ? (v) => setState(() => _shadowStrength = v)
                  : null,
            ),
            _EditorSlider(
              label: l10n.imageEditorHighlightHueLabel,
              value: _highlightHue,
              min: 0,
              max: 360,
              onChanged: _canEdit
                  ? (v) => setState(() => _highlightHue = v)
                  : null,
            ),
            _EditorSlider(
              label: l10n.imageEditorHighlightStrengthLabel,
              value: _highlightStrength,
              min: 0,
              max: 100,
              onChanged: _canEdit
                  ? (v) => setState(() => _highlightStrength = v)
                  : null,
            ),
          ],
        ),
        _AdvancedSection(
          title: l10n.imageEditorSectionDetail,
          children: [
            _EditorSlider(
              label: l10n.imageEditorClarityLabel,
              value: _clarity,
              min: 0,
              max: 100,
              onChanged: _canEdit ? (v) => setState(() => _clarity = v) : null,
            ),
            _EditorSlider(
              label: l10n.imageEditorSharpnessLabel,
              value: _sharpness,
              min: 0,
              max: 100,
              onChanged: _canEdit
                  ? (v) => setState(() => _sharpness = v)
                  : null,
            ),
            _EditorSlider(
              label: l10n.imageEditorDenoiseLabel,
              value: _denoise,
              min: 0,
              max: 100,
              onChanged: _canEdit ? (v) => setState(() => _denoise = v) : null,
            ),
            _EditorSlider(
              label: l10n.imageEditorGrainLabel,
              value: _grain,
              min: 0,
              max: 100,
              onChanged: _canEdit ? (v) => setState(() => _grain = v) : null,
            ),
          ],
        ),
        _AdvancedSection(
          title: l10n.imageEditorSectionEffects,
          children: [
            _EditorSlider(
              label: l10n.imageEditorDispersionLabel,
              value: _dispersion,
              min: 0,
              max: 20,
              onChanged: _canEdit
                  ? (v) => setState(() => _dispersion = v)
                  : null,
            ),
            _EditorSlider(
              label: l10n.imageEditorDistortLabel,
              value: _distort,
              min: -100,
              max: 100,
              onChanged: _canEdit ? (v) => setState(() => _distort = v) : null,
            ),
          ],
        ),
        _AdvancedSection(
          title: l10n.imageEditorSectionWatermark,
          children: [_buildWatermarkEditor(context)],
        ),
      ],
    );
  }

  Widget _buildWatermarkEditor(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final watermarkColor = _currentWatermarkColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _watermarkController,
          enabled: _canEdit,
          decoration: InputDecoration(
            labelText: l10n.imageEditorWatermarkTextLabel,
            hintText: l10n.imageEditorWatermarkTextHint,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          maxLength: 120,
        ),
        const SizedBox(height: 8),
        _EditorSlider(
          label: l10n.imageEditorWatermarkSizeLabel,
          value: _watermarkSize,
          min: 12,
          max: 160,
          onChanged: _canEdit
              ? (v) => setState(() => _watermarkSize = v)
              : null,
        ),
        _EditorSlider(
          label: l10n.imageEditorWatermarkOpacityLabel,
          value: _watermarkOpacity,
          min: 0.1,
          max: 1.0,
          onChanged: _canEdit
              ? (v) => setState(() => _watermarkOpacity = v)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.imageEditorWatermarkPositionLabel,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        // 3×3 position grid.
        Column(
          children: [
            for (final row in const <List<_WatermarkPosition>>[
              [
                _WatermarkPosition.topLeft,
                _WatermarkPosition.topCenter,
                _WatermarkPosition.topRight,
              ],
              [
                _WatermarkPosition.middleLeft,
                _WatermarkPosition.middleCenter,
                _WatermarkPosition.middleRight,
              ],
              [
                _WatermarkPosition.bottomLeft,
                _WatermarkPosition.bottomCenter,
                _WatermarkPosition.bottomRight,
              ],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (final pos in row) ...[
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              backgroundColor: _watermarkPosition == pos
                                  ? colorScheme.primaryContainer
                                  : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _canEdit
                                ? () => setState(() => _watermarkPosition = pos)
                                : null,
                            child: Icon(
                              Icons.circle,
                              size: 8,
                              color: _watermarkPosition == pos
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      if (pos != row.last) const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _canEdit ? _showWatermarkColorPickerDialog : null,
                icon: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: watermarkColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colorScheme.outline),
                  ),
                ),
                label: Text(l10n.imageEditorWatermarkColorLabel),
              ),
            ),
          ],
        ),
        _EditorSlider(
          label: l10n.imageEditorWatermarkColorHue,
          value: _watermarkHue,
          min: 0,
          max: 360,
          onChanged: _canEdit ? (v) => setState(() => _watermarkHue = v) : null,
        ),
        _EditorSlider(
          label: l10n.imageEditorWatermarkColorSaturation,
          value: _watermarkSaturation,
          min: 0,
          max: 1,
          onChanged: _canEdit
              ? (v) => setState(() => _watermarkSaturation = v)
              : null,
        ),
        _EditorSlider(
          label: l10n.imageEditorWatermarkColorLightness,
          value: _watermarkLightness,
          min: 0,
          max: 1,
          onChanged: _canEdit
              ? (v) => setState(() => _watermarkLightness = v)
              : null,
        ),
      ],
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Keep the left secondary actions and the right primary actions on the
    // same vertical rhythm: shared height, shared padding, shared stadium
    // shape for the outlined pair, and a fixed sized slot for each button so
    // the whole bar looks like one consistent capsule row.
    const double barHeight = 52;
    final secondaryStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, barHeight),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      shape: const StadiumBorder(),
    );
    return Row(
      children: [
        SizedBox(
          height: barHeight,
          child: OutlinedButton.icon(
            style: secondaryStyle,
            onPressed: _canEdit && !_isSaving ? _handleSaveToFile : null,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(l10n.imageEditorSaveToFile),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: barHeight,
          child: OutlinedButton.icon(
            style: secondaryStyle,
            onPressed: _canEdit && !_isSaving ? _handleCopyToClipboard : null,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(l10n.imageEditorCopyToClipboard),
          ),
        ),
        const Spacer(),
        SizedBox(
          height: barHeight,
          child: OutlinedButton.icon(
            style: secondaryStyle,
            onPressed: _canEdit && !_isSaving && _hasUnappliedEdits
                ? _handleApply
                : null,
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: Text(l10n.imageEditorApplyButton),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: barHeight,
          child: OutlinedButton.icon(
            style: secondaryStyle,
            onPressed: _canEdit && !_isSaving && _canResetAll
                ? _handleResetAll
                : null,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(l10n.imageEditorResetAllButton),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: barHeight,
          child: OutlinedButton.icon(
            style: secondaryStyle,
            onPressed: _canEdit && !_isSaving && _undoStack.isNotEmpty
                ? _handleUndo
                : null,
            icon: const Icon(Icons.undo_rounded, size: 18),
            label: Text(l10n.imageEditorUndoButton),
          ),
        ),
        const SizedBox(width: 10),
        OpenHandDialogActionButton.secondary(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
        const SizedBox(width: 12),
        OpenHandDialogActionButton.primary(
          onPressed: _canEdit && !_isSaving ? _handleConfirmSave : null,
          label: l10n.commonSave,
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────── Preview panel ─────

  Widget _buildPreviewPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final showOriginal =
        _showOriginalPreview &&
        _originalPreviewBytes != null &&
        _originalImageWidth > 0 &&
        _originalImageHeight > 0;
    final previewBytes = showOriginal ? _originalPreviewBytes : _previewBytes;
    final previewImageWidth = showOriginal ? _originalImageWidth : _imageWidth;
    final previewImageHeight = showOriginal
        ? _originalImageHeight
        : _imageHeight;
    final compareEnabled =
        _canEdit && _originalPreviewBytes != null && _originalImageWidth > 0;

    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rawPreviewWidth = math.min(
            constraints.maxWidth - 116,
            _previewMaxWidth,
          );
          final previewWidth = rawPreviewWidth
              .clamp(220.0, _previewMaxWidth)
              .toDouble();
          final previewSize = Size(previewWidth, _previewHeight);
          _previewSize = previewSize;

          Widget previewBody;
          if (previewBytes == null || previewImageWidth == 0) {
            previewBody = Center(
              child: _isProcessing
                  ? const CircularProgressIndicator()
                  : Text(l10n.imageEditorLoadFailed),
            );
          } else {
            final imageRect = _computeImageRectFor(
              previewSize,
              previewImageWidth,
              previewImageHeight,
            );
            final cropRect = _resolvedCropRect(imageRect);

            previewBody = Stack(
              children: [
                Positioned.fromRect(
                  rect: imageRect,
                  child: showOriginal
                      ? Image.memory(previewBytes, fit: BoxFit.fill)
                      : Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..rotateZ(_rotation * math.pi / 180.0)
                            ..scaleByDouble(
                              _flipHorizontal ? -1.0 : 1.0,
                              _flipVertical ? -1.0 : 1.0,
                              1.0,
                              1.0,
                            ),
                          child: ColorFiltered(
                            colorFilter: ColorFilter.matrix(
                              _buildPreviewColorMatrix(),
                            ),
                            child: Image.memory(previewBytes, fit: BoxFit.fill),
                          ),
                        ),
                ),
                if (showOriginal)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.scrim.withValues(alpha: 0.58),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l10n.imageEditorCompareOriginal,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                if (!showOriginal) ...[
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
                          _moveDragStartGlobalPosition = details.globalPosition;
                          _moveDragStartRect = cropRect;
                        },
                        onPanUpdate: (details) {
                          final startPosition = _moveDragStartGlobalPosition;
                          final startRect = _moveDragStartRect;
                          if (startPosition == null || startRect == null) {
                            return;
                          }
                          final delta = details.globalPosition - startPosition;
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
                          final startPosition = _resizeDragStartGlobalPosition;
                          final startRect = _resizeDragStartRect;
                          if (startPosition == null || startRect == null) {
                            return;
                          }
                          final delta = details.globalPosition - startPosition;
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
              ],
            );
          }

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: previewWidth,
                height: _previewHeight,
                child: ColoredBox(
                  color: colorScheme.surfaceContainerHigh,
                  child: previewBody,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 104,
                child: Listener(
                  onPointerDown: compareEnabled
                      ? (_) {
                          _showOriginalPreview = true;
                          if (!_previewCompareScheduled) {
                            _previewCompareScheduled = true;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _previewCompareScheduled = false;
                              if (mounted) setState(() {});
                            });
                          }
                        }
                      : null,
                  onPointerUp: compareEnabled
                      ? (_) {
                          _showOriginalPreview = false;
                          if (!_previewCompareScheduled) {
                            _previewCompareScheduled = true;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _previewCompareScheduled = false;
                              if (mounted) setState(() {});
                            });
                          }
                        }
                      : null,
                  onPointerCancel: compareEnabled
                      ? (_) {
                          _showOriginalPreview = false;
                          if (!_previewCompareScheduled) {
                            _previewCompareScheduled = true;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _previewCompareScheduled = false;
                              if (mounted) setState(() {});
                            });
                          }
                        }
                      : null,
                  child: OutlinedButton.icon(
                    onPressed: compareEnabled ? () {} : null,
                    icon: const Icon(Icons.compare_rounded, size: 18),
                    label: Text(
                      showOriginal
                          ? l10n.imageEditorCompareRelease
                          : l10n.imageEditorCompareHold,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ────────────────────────────────────────────────── State / behaviour ─────

  bool get _canEdit =>
      _previewBytes != null && _imageWidth > 0 && !_isProcessing;

  bool get _canResetAll =>
      _hasBakedChanges || _undoStack.isNotEmpty || _hasUnappliedEdits;

  /// Shows a brief [SnackBar] notification at the bottom of the dialog
  /// using the green / red `OpenHandSnackBar` variants and pulses the
  /// corresponding top-edge HighlightPulse.
  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    final messengerContext = _messengerKey.currentContext ?? context;
    final messengerState = _messengerKey.currentState;
    if (messengerState == null) return;
    if (isError) {
      OpenHandSnackBar.show(
        messengerContext,
        messengerState,
        OpenHandSnackBar.error(messengerContext, message),
      );
      _errorPulse.value = _errorPulse.value + 1;
    } else {
      OpenHandSnackBar.show(
        messengerContext,
        messengerState,
        OpenHandSnackBar.success(messengerContext, message),
      );
      _successPulse.value = _successPulse.value + 1;
    }
  }

  void _loadImage() {
    _loadImageAsync();
  }

  Future<void> _loadImageAsync() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    try {
      // Decode on the main thread: a single decode+bake is typically well
      // under 200ms even for multi-megapixel photos and is far simpler /
      // more reliable than spawning an isolate (closures around
      // `Isolate.run` are fragile — if the enclosing scope inadvertently
      // becomes non-sendable the whole spawn silently fails). Only the
      // truly heavy pipeline (convolutions, gaussian blur, etc.) still runs
      // in a background isolate — see `_renderInIsolate`.
      //
      // We yield to the event loop once via `Future.microtask` so the
      // progress indicator has a chance to paint before we block.
      await Future<void>.delayed(Duration.zero);
      final decoded = img.decodeImage(widget.imageBytes);
      if (decoded == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = AppLocalizations.of(context)!.imageEditorLoadFailed;
        });
        return;
      }
      final baked = img.bakeOrientation(decoded);
      final pngBytes = Uint8List.fromList(img.encodePng(baked));
      if (!mounted) return;
      setState(() {
        _previewBytes = pngBytes;
        _originalPreviewBytes = Uint8List.fromList(pngBytes);
        _imageWidth = baked.width;
        _imageHeight = baked.height;
        _originalImageWidth = baked.width;
        _originalImageHeight = baked.height;
        _undoStack.clear();
        _hasBakedChanges = false;
        _showOriginalPreview = false;
        _resetAdjustmentControls(clearMessages: false);
      });
    } catch (error, stack) {
      silentLog('image_editor', 'load image', error, stack);
      if (mounted) {
        setState(() {
          _errorMessage = AppLocalizations.of(context)!.imageEditorLoadFailed;
        });
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _rotateImage(int angle) {
    if (_previewBytes == null) return;
    _rotateImageAsync(angle);
  }

  Future<void> _rotateImageAsync(int angle) async {
    final sourceBytes = _previewBytes;
    if (sourceBytes == null) return;
    setState(() => _isProcessing = true);
    _showProcessingOverlay();
    try {
      final result = await _runRotateInIsolate(
        sourceBytes: sourceBytes,
        angle: angle,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _errorMessage = AppLocalizations.of(
            context,
          )!.imageEditorProcessFailed;
        });
        _showSnackBar(
          AppLocalizations.of(context)!.imageEditorProcessFailed,
          isError: true,
        );
        return;
      }
      setState(() {
        _previewBytes = result.$1;
        _imageWidth = result.$2;
        _imageHeight = result.$3;
        _cropRect = null;
        _showOriginalPreview = false;
        _syncBakedState();
        _errorMessage = null;
        _statusMessage = null;
      });
    } catch (error, stack) {
      silentLog('image_editor', 'rotate image', error, stack);
      if (mounted) {
        setState(() {
          _errorMessage = AppLocalizations.of(
            context,
          )!.imageEditorProcessFailed;
        });
        _showSnackBar(
          AppLocalizations.of(context)!.imageEditorProcessFailed,
          isError: true,
        );
      }
    } finally {
      _dismissProcessingOverlay();
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _resetAdjustments() {
    setState(() {
      _resetAdjustmentControls();
    });
    _firePulse();
  }

  void _handleResetAll() {
    final original = _originalPreviewBytes;
    if (original == null) return;
    setState(() {
      _previewBytes = Uint8List.fromList(original);
      _imageWidth = _originalImageWidth;
      _imageHeight = _originalImageHeight;
      _undoStack.clear();
      _showOriginalPreview = false;
      _hasBakedChanges = false;
      _resetAdjustmentControls();
    });
    _firePulse();
  }

  void _resetAdjustmentControls({bool clearMessages = true}) {
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

    _temperature = 0;
    _tint = 0;
    _gamma = 1;
    _shadowHue = 210;
    _shadowStrength = 0;
    _highlightHue = 45;
    _highlightStrength = 0;
    _clarity = 0;
    _sharpness = 0;
    _denoise = 0;
    _grain = 0;
    _dispersion = 0;
    _distort = 0;

    _watermarkController.clear();
    _watermarkSize = 48;
    _watermarkOpacity = 0.85;
    _watermarkPosition = _WatermarkPosition.bottomRight;
    _watermarkHue = 0;
    _watermarkSaturation = 0;
    _watermarkLightness = 0.94;

    if (clearMessages) {
      _errorMessage = null;
      _statusMessage = null;
    }
  }

  void _syncBakedState() {
    final current = _previewBytes;
    final original = _originalPreviewBytes;
    if (current == null || original == null) {
      _hasBakedChanges = false;
      return;
    }
    _hasBakedChanges = !listEquals(current, original);
  }

  // ─────────────── Processing overlay (shown during heavy image ops) ──────

  BuildContext? _processingDialogContext;
  bool _processingDialogVisible = false;
  bool _processingDialogCloseRequested = false;

  void _showProcessingOverlay() {
    if (!mounted || _processingDialogVisible) {
      return;
    }
    _processingDialogVisible = true;
    _processingDialogCloseRequested = false;
    final processingMessage =
        AppLocalizations.of(context)?.imageEditorProcessing ?? '处理中…';
    showAnimatedDialog<void>(
      context: context,
      barrierDismissible: false,
      dismissOnEscape: false,
      builder: (dialogContext) {
        _processingDialogContext = dialogContext;
        if (_processingDialogCloseRequested) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!dialogContext.mounted) {
              return;
            }
            Navigator.of(dialogContext, rootNavigator: true).pop();
          });
        }
        return _ProcessingDialog(message: processingMessage);
      },
    ).whenComplete(() {
      _processingDialogContext = null;
      _processingDialogVisible = false;
      _processingDialogCloseRequested = false;
    });
  }

  void _dismissProcessingOverlay() {
    if (!_processingDialogVisible) {
      return;
    }
    _processingDialogVisible = false;
    final dialogContext = _processingDialogContext;
    if (dialogContext == null || !dialogContext.mounted) {
      _processingDialogCloseRequested = true;
      return;
    }
    _processingDialogContext = null;
    Navigator.of(dialogContext, rootNavigator: true).pop();
  }

  // ──────────────────────────────── Apply (bake edits) / Undo ────────────

  /// Whether there are non-default adjustments to bake into the preview.
  bool get _hasUnappliedEdits =>
      _cropRect != null ||
      _aspect != _CropAspect.freeform ||
      _brightness != 1 ||
      _contrast != 1 ||
      _saturation != 1 ||
      _exposure != 0 ||
      _hue != 0 ||
      _vignette != 0 ||
      _rotation.abs() > 0.01 ||
      _flipHorizontal ||
      _flipVertical ||
      _temperature.abs() > 0.5 ||
      _tint.abs() > 0.5 ||
      _gamma != 1 ||
      _shadowStrength > 0 ||
      _highlightStrength > 0 ||
      _clarity > 0 ||
      _sharpness > 0 ||
      _denoise > 0 ||
      _grain > 0 ||
      _dispersion > 0.5 ||
      _distort.abs() > 1 ||
      _watermarkController.text.trim().isNotEmpty;

  /// Bake all current adjustments + crop into the preview image, reset sliders,
  /// push the previous state onto [_undoStack].
  Future<void> _handleApply() async {
    final l10n = AppLocalizations.of(context)!;
    final previewBytes = _previewBytes;
    if (previewBytes == null) return;
    final watermarkText = _watermarkController.text.trim();
    final watermarkSize = _watermarkSize;
    final watermarkOpacity = _watermarkOpacity;
    final watermarkPosition = _watermarkPosition;
    final watermarkColor = _currentWatermarkColor;
    final watermarkTextDirection =
        Directionality.maybeOf(context) ?? TextDirection.ltr;

    final effectivePreviewSize = _previewSize == Size.zero
        ? const Size(_previewMaxWidth, _previewHeight)
        : _previewSize;

    setState(() => _isProcessing = true);
    _showProcessingOverlay();

    try {
      final params = _IsolateRenderParams(
        imageBytes: previewBytes,
        previewWidth: effectivePreviewSize.width,
        previewHeight: effectivePreviewSize.height,
        hasCropRect: _cropRect != null,
        cropLeft: _cropRect?.left ?? 0,
        cropTop: _cropRect?.top ?? 0,
        cropWidth: _cropRect?.width ?? 0,
        cropHeight: _cropRect?.height ?? 0,
        rotation: _rotation,
        flipHorizontal: _flipHorizontal,
        flipVertical: _flipVertical,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
        exposure: _exposure,
        hue: _hue,
        gamma: _gamma,
        temperature: _temperature,
        tint: _tint,
        shadowHue: _shadowHue,
        shadowStrength: _shadowStrength,
        highlightHue: _highlightHue,
        highlightStrength: _highlightStrength,
        clarity: _clarity,
        sharpness: _sharpness,
        denoise: _denoise,
        grain: _grain,
        dispersion: _dispersion,
        distort: _distort,
        vignette: _vignette,
        watermarkText: _watermarkController.text.trim(),
        watermarkSize: _watermarkSize,
        watermarkOpacity: _watermarkOpacity,
        watermarkPositionIndex: _watermarkPosition.index,
        watermarkColorArgb: _currentWatermarkColor.toARGB32(),
        isCircle: _aspect == _CropAspect.circle,
        forcePng: true, // Apply always keeps PNG to avoid JPEG quality loss
        maxOutputLongSide: null,
        imageSizeLimitBytes: null,
      );

      final result = await _runRenderInIsolate(params);
      if (result == null) {
        if (mounted) {
          setState(() => _errorMessage = l10n.imageEditorProcessFailed);
          _showSnackBar(l10n.imageEditorProcessFailed, isError: true);
        }
        return;
      }

      final composedBytes = await _composeWatermarkIfNeeded(
        sourceBytes: result.$1,
        watermarkText: watermarkText,
        watermarkSize: watermarkSize,
        watermarkOpacity: watermarkOpacity,
        watermarkPosition: watermarkPosition,
        watermarkColor: watermarkColor,
        watermarkTextDirection: watermarkTextDirection,
        outputPng: true,
        imageSizeLimitBytes: null,
      );
      if (composedBytes == null) {
        if (mounted) {
          setState(() => _errorMessage = l10n.imageEditorProcessFailed);
          _showSnackBar(l10n.imageEditorProcessFailed, isError: true);
        }
        return;
      }

      if (!mounted) return;

      // Push undo snapshot AFTER successful render (not before) so a failed
      // apply doesn't leave a phantom entry in the undo stack.
      if (_undoStack.length >= _maxUndoDepth) {
        _undoStack.removeAt(0);
      }
      _undoStack.add((previewBytes, _imageWidth, _imageHeight));

      setState(() {
        _previewBytes = composedBytes;
        _imageWidth = result.$2;
        _imageHeight = result.$3;
        _showOriginalPreview = false;
        _resetAdjustmentControls(clearMessages: false);
        _syncBakedState();
        _errorMessage = null;
        _statusMessage = l10n.imageEditorApplySuccess;
      });
      _showSnackBar(l10n.imageEditorApplySuccess);
    } catch (error, stack) {
      silentLog('image_editor', 'apply edits', error, stack);
      if (mounted) {
        setState(() => _errorMessage = l10n.imageEditorProcessFailed);
        _showSnackBar(l10n.imageEditorProcessFailed, isError: true);
      }
    } finally {
      _dismissProcessingOverlay();
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _handleUndo() {
    if (_undoStack.isEmpty) return;
    final (prevBytes, prevWidth, prevHeight) = _undoStack.removeLast();
    setState(() {
      _previewBytes = prevBytes;
      _imageWidth = prevWidth;
      _imageHeight = prevHeight;
      _showOriginalPreview = false;
      _resetAdjustmentControls(clearMessages: false);
      _syncBakedState();
      _errorMessage = null;
      _statusMessage = null;
    });
  }

  Rect _resolvedCropRect(Rect imageRect) {
    final existing = _cropRect;
    if (existing == null) {
      return _initialCropRect(imageRect);
    }
    return _clampMovedCropRect(existing, imageRect);
  }

  Rect _initialCropRect(Rect imageRect) {
    final ratio = _targetAspectRatio();
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
  double? _targetAspectRatio() {
    switch (_aspect) {
      case _CropAspect.freeform:
        return null;
      case _CropAspect.original:
        if (_imageHeight == 0) return null;
        return _imageWidth / _imageHeight;
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

  Rect _computeImageRectFor(Size previewSize, int width, int height) {
    final safeWidth = math.max(1, width);
    final safeHeight = math.max(1, height);
    final scale = math.min(
      previewSize.width / safeWidth,
      previewSize.height / safeHeight,
    );
    final fittedWidth = safeWidth * scale;
    final fittedHeight = safeHeight * scale;
    final left = (previewSize.width - fittedWidth) / 2;
    final top = (previewSize.height - fittedHeight) / 2;
    return Rect.fromLTWH(left, top, fittedWidth, fittedHeight);
  }

  Color get _currentWatermarkColor {
    return HSLColor.fromAHSL(
      1,
      _watermarkHue,
      _watermarkSaturation,
      _watermarkLightness,
    ).toColor();
  }

  Future<void> _showWatermarkColorPickerDialog() async {
    final l10n = AppLocalizations.of(context)!;
    var hue = _watermarkHue;
    var saturation = _watermarkSaturation;
    var lightness = _watermarkLightness;
    const presets = <Color>[
      Colors.white,
      Colors.black,
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.cyan,
      Colors.blue,
      Colors.purple,
      Colors.pink,
    ];

    final picked = await showAnimatedDialog<HSLColor>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final previewColor = HSLColor.fromAHSL(
              1,
              hue,
              saturation,
              lightness,
            ).toColor();
            return AlertDialog(
              title: Text(l10n.imageEditorWatermarkColorLabel),
              actionsAlignment: MainAxisAlignment.center,
              actionsOverflowAlignment: OverflowBarAlignment.center,
              actionsOverflowButtonSpacing: 12,
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: previewColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final color in presets)
                            InkWell(
                              onTap: () {
                                final hsl = HSLColor.fromColor(color);
                                setDialogState(() {
                                  hue = hsl.hue;
                                  saturation = hsl.saturation;
                                  lightness = hsl.lightness;
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _EditorSlider(
                        label: l10n.imageEditorWatermarkColorHue,
                        value: hue,
                        min: 0,
                        max: 360,
                        onChanged: (value) => setDialogState(() => hue = value),
                      ),
                      _EditorSlider(
                        label: l10n.imageEditorWatermarkColorSaturation,
                        value: saturation,
                        min: 0,
                        max: 1,
                        onChanged: (value) =>
                            setDialogState(() => saturation = value),
                      ),
                      _EditorSlider(
                        label: l10n.imageEditorWatermarkColorLightness,
                        value: lightness,
                        min: 0,
                        max: 1,
                        onChanged: (value) =>
                            setDialogState(() => lightness = value),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                OpenHandDialogActionButton.secondary(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  label: l10n.commonCancel,
                ),
                OpenHandDialogActionButton.primary(
                  onPressed: () {
                    Navigator.of(
                      dialogContext,
                    ).pop(HSLColor.fromAHSL(1, hue, saturation, lightness));
                  },
                  label: l10n.commonSave,
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() {
      _watermarkHue = picked.hue;
      _watermarkSaturation = picked.saturation;
      _watermarkLightness = picked.lightness;
    });
  }

  Future<Uint8List?> _composeWatermarkIfNeeded({
    required Uint8List sourceBytes,
    required String watermarkText,
    required double watermarkSize,
    required double watermarkOpacity,
    required _WatermarkPosition watermarkPosition,
    required Color watermarkColor,
    required TextDirection watermarkTextDirection,
    required bool outputPng,
    required int? imageSizeLimitBytes,
  }) async {
    if (watermarkText.isEmpty) return sourceBytes;

    ui.Codec? codec;
    ui.Image? baseImage;
    ui.Image? composedImage;
    try {
      codec = await ui.instantiateImageCodec(sourceBytes);
      final frame = await codec.getNextFrame();
      baseImage = frame.image;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(baseImage, Offset.zero, Paint());

      final imageSize = Size(
        baseImage.width.toDouble(),
        baseImage.height.toDouble(),
      );
      final margin = math.max(
        12.0,
        math.min(imageSize.width, imageSize.height) * 0.02,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: watermarkText,
          style: TextStyle(
            color: watermarkColor.withValues(
              alpha: watermarkOpacity.clamp(0.0, 1.0),
            ),
            fontSize: watermarkSize.clamp(8.0, imageSize.height * 0.5),
            fontWeight: FontWeight.w600,
            height: 1.1,
            shadows: const [
              Shadow(
                color: Color(0x66000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
        textDirection: watermarkTextDirection,
        maxLines: 6,
        ellipsis: '…',
      )..layout(maxWidth: math.max(48.0, imageSize.width - margin * 2));

      final offset = _resolveWatermarkOffset(
        watermarkPosition: watermarkPosition,
        imageSize: imageSize,
        textSize: textPainter.size,
        margin: margin,
      );
      textPainter.paint(canvas, offset);

      final picture = recorder.endRecording();
      composedImage = await picture.toImage(baseImage.width, baseImage.height);
      final pngData = await composedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (pngData == null) return null;
      final pngBytes = pngData.buffer.asUint8List();

      if (outputPng) {
        return pngBytes;
      }

      final decoded = img.decodeImage(pngBytes);
      if (decoded == null) return null;
      return _encodeJpgWithSizeLimit(
        decoded,
        imageSizeLimitBytes: imageSizeLimitBytes,
      );
    } catch (error, stack) {
      silentLog('image_editor', 'compose watermark', error, stack);
      return null;
    } finally {
      codec?.dispose();
      baseImage?.dispose();
      composedImage?.dispose();
    }
  }

  Offset _resolveWatermarkOffset({
    required _WatermarkPosition watermarkPosition,
    required Size imageSize,
    required Size textSize,
    required double margin,
  }) {
    double x;
    double y;
    switch (watermarkPosition) {
      case _WatermarkPosition.topLeft:
        x = margin;
        y = margin;
      case _WatermarkPosition.topCenter:
        x = (imageSize.width - textSize.width) / 2;
        y = margin;
      case _WatermarkPosition.topRight:
        x = imageSize.width - textSize.width - margin;
        y = margin;
      case _WatermarkPosition.middleLeft:
        x = margin;
        y = (imageSize.height - textSize.height) / 2;
      case _WatermarkPosition.middleCenter:
        x = (imageSize.width - textSize.width) / 2;
        y = (imageSize.height - textSize.height) / 2;
      case _WatermarkPosition.middleRight:
        x = imageSize.width - textSize.width - margin;
        y = (imageSize.height - textSize.height) / 2;
      case _WatermarkPosition.bottomLeft:
        x = margin;
        y = imageSize.height - textSize.height - margin;
      case _WatermarkPosition.bottomCenter:
        x = (imageSize.width - textSize.width) / 2;
        y = imageSize.height - textSize.height - margin;
      case _WatermarkPosition.bottomRight:
        x = imageSize.width - textSize.width - margin;
        y = imageSize.height - textSize.height - margin;
    }

    final clampedX = x.clamp(
      0.0,
      math.max(0.0, imageSize.width - textSize.width),
    );
    final clampedY = y.clamp(
      0.0,
      math.max(0.0, imageSize.height - textSize.height),
    );
    return Offset(clampedX.toDouble(), clampedY.toDouble());
  }

  Uint8List _encodeJpgWithSizeLimit(
    img.Image source, {
    required int? imageSizeLimitBytes,
  }) {
    var working = source;
    var encoded = Uint8List.fromList(img.encodeJpg(working, quality: 92));
    final limit = imageSizeLimitBytes;
    if (limit == null || limit <= 0 || encoded.length <= limit) {
      return encoded;
    }

    for (var quality = 86; quality >= 30; quality -= 8) {
      encoded = Uint8List.fromList(img.encodeJpg(working, quality: quality));
      if (encoded.length <= limit) {
        return encoded;
      }
    }

    while (encoded.length > limit &&
        working.width > 320 &&
        working.height > 320) {
      working = img.copyResize(working, width: (working.width * 0.8).round());
      encoded = Uint8List.fromList(img.encodeJpg(working, quality: 82));
    }
    return encoded;
  }

  Rect _clampMovedCropRect(Rect candidate, Rect imageRect) {
    if (_imageWidth == 0) return candidate;
    final ratio = _targetAspectRatio();
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
    if (_imageWidth == 0) return startRect;
    final ratio = _targetAspectRatio();
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
      r1,
      r2,
      r3,
      0,
      translate,
      g1,
      g2,
      g3,
      0,
      translate,
      b1,
      b2,
      b3,
      0,
      translate,
      0,
      0,
      0,
      1,
      0,
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
        suggestedName:
            'image-${DateTime.now().millisecondsSinceEpoch}.${isPng ? 'png' : 'jpg'}',
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
      _showSnackBar(l10n.imageEditorSavedTo(location.path));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = l10n.imageEditorSaveFailed(error.toString());
      });
      _showSnackBar(
        l10n.imageEditorSaveFailed(error.toString()),
        isError: true,
      );
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
        // Use the safe subprocess wrapper so a hung osascript cannot leak
        // and corrupt the host app's input-method context (which would
        // surface as TextFields no longer accepting input/paste).
        final result = await runProcessWithTimeout('osascript', <String>[
          '-e',
          'set the clipboard to (read POSIX file "${tempFile.path.replaceAll('"', r'\"')}") as ${ext == 'png' ? 'picture' : 'JPEG picture'}',
        ], tag: 'image_editor_dialog');
        bitmapCopied = result?.exitCode == 0;
      }

      // Always also push the file path so non-image-aware paste targets get
      // something useful.
      await Clipboard.setData(ClipboardData(text: tempFile.path));

      if (!mounted) {
        return;
      }
      final clipMsg = bitmapCopied
          ? l10n.imageEditorClipboardCopiedBitmap
          : l10n.imageEditorClipboardCopiedPath(tempFile.path);
      setState(() {
        _statusMessage = clipMsg;
        _errorMessage = null;
      });
      _showSnackBar(clipMsg);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = l10n.imageEditorClipboardFailed(error.toString());
      });
      _showSnackBar(
        l10n.imageEditorClipboardFailed(error.toString()),
        isError: true,
      );
    }
  }

  /// Materialises the final image. Returns `null` on failure (and updates
  /// [_errorMessage] in-place).
  Future<Uint8List?> _renderOutput() async {
    final l10n = AppLocalizations.of(context)!;
    final previewBytes = _previewBytes;
    if (previewBytes == null) {
      setState(() {
        _errorMessage = l10n.imageEditorLoadFailed;
      });
      _showSnackBar(l10n.imageEditorLoadFailed, isError: true);
      return null;
    }

    final effectivePreviewSize = _previewSize == Size.zero
        ? const Size(_previewMaxWidth, _previewHeight)
        : _previewSize;
    final watermarkText = _watermarkController.text.trim();
    final watermarkSize = _watermarkSize;
    final watermarkOpacity = _watermarkOpacity;
    final watermarkPosition = _watermarkPosition;
    final watermarkColor = _currentWatermarkColor;
    final watermarkTextDirection =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
    final hasWatermark = watermarkText.isNotEmpty;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _statusMessage = null;
    });
    _showProcessingOverlay();

    try {
      final params = _IsolateRenderParams(
        imageBytes: previewBytes,
        previewWidth: effectivePreviewSize.width,
        previewHeight: effectivePreviewSize.height,
        hasCropRect: _cropRect != null,
        cropLeft: _cropRect?.left ?? 0,
        cropTop: _cropRect?.top ?? 0,
        cropWidth: _cropRect?.width ?? 0,
        cropHeight: _cropRect?.height ?? 0,
        rotation: _rotation,
        flipHorizontal: _flipHorizontal,
        flipVertical: _flipVertical,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
        exposure: _exposure,
        hue: _hue,
        gamma: _gamma,
        temperature: _temperature,
        tint: _tint,
        shadowHue: _shadowHue,
        shadowStrength: _shadowStrength,
        highlightHue: _highlightHue,
        highlightStrength: _highlightStrength,
        clarity: _clarity,
        sharpness: _sharpness,
        denoise: _denoise,
        grain: _grain,
        dispersion: _dispersion,
        distort: _distort,
        vignette: _vignette,
        watermarkText: _watermarkController.text.trim(),
        watermarkSize: _watermarkSize,
        watermarkOpacity: _watermarkOpacity,
        watermarkPositionIndex: _watermarkPosition.index,
        watermarkColorArgb: _currentWatermarkColor.toARGB32(),
        isCircle: _aspect == _CropAspect.circle,
        forcePng: false,
        maxOutputLongSide: _maxOutputLongSide,
        imageSizeLimitBytes: hasWatermark ? null : widget.imageSizeLimitBytes,
      );

      final result = await _runRenderInIsolate(params);
      if (result == null) {
        if (mounted) {
          setState(() {
            _errorMessage = l10n.imageEditorProcessFailed;
          });
          _showSnackBar(l10n.imageEditorProcessFailed, isError: true);
        }
        return null;
      }
      final composedBytes = await _composeWatermarkIfNeeded(
        sourceBytes: result.$1,
        watermarkText: watermarkText,
        watermarkSize: watermarkSize,
        watermarkOpacity: watermarkOpacity,
        watermarkPosition: watermarkPosition,
        watermarkColor: watermarkColor,
        watermarkTextDirection: watermarkTextDirection,
        outputPng: _aspect == _CropAspect.circle,
        imageSizeLimitBytes: widget.imageSizeLimitBytes,
      );
      if (composedBytes == null) {
        if (mounted) {
          setState(() {
            _errorMessage = l10n.imageEditorProcessFailed;
          });
          _showSnackBar(l10n.imageEditorProcessFailed, isError: true);
        }
        return null;
      }

      return composedBytes;
    } catch (error, stack) {
      silentLog('image_editor', 'render output', error, stack);
      if (!mounted) return null;
      setState(() {
        _errorMessage = l10n.imageEditorProcessFailed;
      });
      _showSnackBar(l10n.imageEditorProcessFailed, isError: true);
      return null;
    } finally {
      _dismissProcessingOverlay();
      if (mounted) setState(() => _isSaving = false);
    }
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

/// Collapsible advanced-adjustments section used underneath the basic
/// sliders. Uses an [ExpansionTile] so the dialog remains scrollable and
/// each group can be opened independently.
class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(title, style: theme.textTheme.titleSmall),
          children: children,
        ),
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

// ═══════════════════════════════════════════════════════════════════════════
//  Isolate-safe rendering pipeline
// ═══════════════════════════════════════════════════════════════════════════

/// Top-level isolate-safe helper: decode PNG bytes, rotate by [angle]
/// degrees, re-encode as PNG and return `(pngBytes, width, height)`.
(Uint8List, int, int)? _rotatePng(Uint8List sourceBytes, int angle) {
  final decoded = img.decodePng(sourceBytes);
  if (decoded == null) return null;
  final rotated = img.copyRotate(decoded, angle: angle);
  final pngBytes = Uint8List.fromList(img.encodePng(rotated));
  return (pngBytes, rotated.width, rotated.height);
}

/// Runs rotation in a background isolate using a pure message payload.
Future<(Uint8List, int, int)?> _runRotateInIsolate({
  required Uint8List sourceBytes,
  required int angle,
}) {
  final message = <String, Object>{'sourceBytes': sourceBytes, 'angle': angle};
  return Isolate.run<(Uint8List, int, int)?>(
    () => _rotatePngFromMessage(message),
  );
}

(Uint8List, int, int)? _rotatePngFromMessage(Map<String, Object> message) {
  final sourceBytes = message['sourceBytes'] as Uint8List;
  final angle = message['angle'] as int;
  return _rotatePng(sourceBytes, angle);
}

/// Runs the full render pipeline in a background isolate from a map payload.
Future<(Uint8List, int, int)?> _runRenderInIsolate(
  _IsolateRenderParams params,
) {
  final message = params.toMessage();
  return Isolate.run<(Uint8List, int, int)?>(
    () => _renderInIsolateFromMessage(message),
  );
}

(Uint8List, int, int)? _renderInIsolateFromMessage(
  Map<String, Object?> message,
) {
  return _renderInIsolate(_IsolateRenderParams.fromMessage(message));
}

/// All the parameters needed to render an image in a background isolate.
/// Every field is a primitive / enum / Uint8List — no Widgets or BuildContext.
class _IsolateRenderParams {
  _IsolateRenderParams({
    required this.imageBytes,
    required this.previewWidth,
    required this.previewHeight,
    required this.hasCropRect,
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
    required this.rotation,
    required this.flipHorizontal,
    required this.flipVertical,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.exposure,
    required this.hue,
    required this.gamma,
    required this.temperature,
    required this.tint,
    required this.shadowHue,
    required this.shadowStrength,
    required this.highlightHue,
    required this.highlightStrength,
    required this.clarity,
    required this.sharpness,
    required this.denoise,
    required this.grain,
    required this.dispersion,
    required this.distort,
    required this.vignette,
    required this.watermarkText,
    required this.watermarkSize,
    required this.watermarkOpacity,
    required this.watermarkPositionIndex,
    required this.watermarkColorArgb,
    required this.isCircle,
    required this.forcePng,
    required this.maxOutputLongSide,
    required this.imageSizeLimitBytes,
  });

  final Uint8List imageBytes;
  final double previewWidth;
  final double previewHeight;
  final bool hasCropRect;
  final double cropLeft;
  final double cropTop;
  final double cropWidth;
  final double cropHeight;
  final double rotation;
  final bool flipHorizontal;
  final bool flipVertical;
  final double brightness;
  final double contrast;
  final double saturation;
  final double exposure;
  final double hue;
  final double gamma;
  final double temperature;
  final double tint;
  final double shadowHue;
  final double shadowStrength;
  final double highlightHue;
  final double highlightStrength;
  final double clarity;
  final double sharpness;
  final double denoise;
  final double grain;
  final double dispersion;
  final double distort;
  final double vignette;
  final String watermarkText;
  final double watermarkSize;
  final double watermarkOpacity;
  final int watermarkPositionIndex;
  final int watermarkColorArgb;
  final bool isCircle;
  final bool forcePng;
  final int? maxOutputLongSide;
  final int? imageSizeLimitBytes;

  Map<String, Object?> toMessage() {
    return <String, Object?>{
      'imageBytes': imageBytes,
      'previewWidth': previewWidth,
      'previewHeight': previewHeight,
      'hasCropRect': hasCropRect,
      'cropLeft': cropLeft,
      'cropTop': cropTop,
      'cropWidth': cropWidth,
      'cropHeight': cropHeight,
      'rotation': rotation,
      'flipHorizontal': flipHorizontal,
      'flipVertical': flipVertical,
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'exposure': exposure,
      'hue': hue,
      'gamma': gamma,
      'temperature': temperature,
      'tint': tint,
      'shadowHue': shadowHue,
      'shadowStrength': shadowStrength,
      'highlightHue': highlightHue,
      'highlightStrength': highlightStrength,
      'clarity': clarity,
      'sharpness': sharpness,
      'denoise': denoise,
      'grain': grain,
      'dispersion': dispersion,
      'distort': distort,
      'vignette': vignette,
      'watermarkText': watermarkText,
      'watermarkSize': watermarkSize,
      'watermarkOpacity': watermarkOpacity,
      'watermarkPositionIndex': watermarkPositionIndex,
      'watermarkColorArgb': watermarkColorArgb,
      'isCircle': isCircle,
      'forcePng': forcePng,
      'maxOutputLongSide': maxOutputLongSide,
      'imageSizeLimitBytes': imageSizeLimitBytes,
    };
  }

  static _IsolateRenderParams fromMessage(Map<String, Object?> message) {
    return _IsolateRenderParams(
      imageBytes: message['imageBytes']! as Uint8List,
      previewWidth: (message['previewWidth']! as num).toDouble(),
      previewHeight: (message['previewHeight']! as num).toDouble(),
      hasCropRect: message['hasCropRect']! as bool,
      cropLeft: (message['cropLeft']! as num).toDouble(),
      cropTop: (message['cropTop']! as num).toDouble(),
      cropWidth: (message['cropWidth']! as num).toDouble(),
      cropHeight: (message['cropHeight']! as num).toDouble(),
      rotation: (message['rotation']! as num).toDouble(),
      flipHorizontal: message['flipHorizontal']! as bool,
      flipVertical: message['flipVertical']! as bool,
      brightness: (message['brightness']! as num).toDouble(),
      contrast: (message['contrast']! as num).toDouble(),
      saturation: (message['saturation']! as num).toDouble(),
      exposure: (message['exposure']! as num).toDouble(),
      hue: (message['hue']! as num).toDouble(),
      gamma: (message['gamma']! as num).toDouble(),
      temperature: (message['temperature']! as num).toDouble(),
      tint: (message['tint']! as num).toDouble(),
      shadowHue: (message['shadowHue']! as num).toDouble(),
      shadowStrength: (message['shadowStrength']! as num).toDouble(),
      highlightHue: (message['highlightHue']! as num).toDouble(),
      highlightStrength: (message['highlightStrength']! as num).toDouble(),
      clarity: (message['clarity']! as num).toDouble(),
      sharpness: (message['sharpness']! as num).toDouble(),
      denoise: (message['denoise']! as num).toDouble(),
      grain: (message['grain']! as num).toDouble(),
      dispersion: (message['dispersion']! as num).toDouble(),
      distort: (message['distort']! as num).toDouble(),
      vignette: (message['vignette']! as num).toDouble(),
      watermarkText: (message['watermarkText'] as String?) ?? '',
      watermarkSize: (message['watermarkSize']! as num).toDouble(),
      watermarkOpacity: (message['watermarkOpacity']! as num).toDouble(),
      watermarkPositionIndex: message['watermarkPositionIndex']! as int,
      watermarkColorArgb: message['watermarkColorArgb']! as int,
      isCircle: message['isCircle']! as bool,
      forcePng: message['forcePng']! as bool,
      maxOutputLongSide: message['maxOutputLongSide'] as int?,
      imageSizeLimitBytes: message['imageSizeLimitBytes'] as int?,
    );
  }
}

/// Top-level function that runs entirely inside an [Isolate].
/// Returns (encoded bytes, width, height) or null on failure.
(Uint8List, int, int)? _renderInIsolate(_IsolateRenderParams p) {
  final orientedImage = img.decodeImage(p.imageBytes);
  if (orientedImage == null) return null;

  final previewSize = Size(p.previewWidth, p.previewHeight);

  // 1) Compute crop in source-image coordinates from preview-space.
  final imageRect = _computeImageRectStatic(previewSize, orientedImage);
  final cropRect = p.hasCropRect
      ? Rect.fromLTWH(p.cropLeft, p.cropTop, p.cropWidth, p.cropHeight)
      : imageRect;

  final scaleX = orientedImage.width / imageRect.width;
  final scaleY = orientedImage.height / imageRect.height;
  final cropX = ((cropRect.left - imageRect.left) * scaleX).round().clamp(
    0,
    orientedImage.width - 1,
  );
  final cropY = ((cropRect.top - imageRect.top) * scaleY).round().clamp(
    0,
    orientedImage.height - 1,
  );
  final cropW = (cropRect.width * scaleX).round().clamp(
    1,
    orientedImage.width - cropX,
  );
  final cropH = (cropRect.height * scaleY).round().clamp(
    1,
    orientedImage.height - cropY,
  );

  // 2) Apply free rotation first (if any), then flips, then crop.
  img.Image working = orientedImage;
  if (p.rotation.abs() > 0.01) {
    working = img.copyRotate(working, angle: p.rotation);
  }
  if (p.flipHorizontal) {
    working = img.flipHorizontal(working);
  }
  if (p.flipVertical) {
    working = img.flipVertical(working);
  }

  // Re-derive crop region against the (possibly rotated/flipped) working image.
  final sx = working.width / orientedImage.width;
  final sy = working.height / orientedImage.height;
  final cx = (cropX * sx).round().clamp(0, working.width - 1);
  final cy = (cropY * sy).round().clamp(0, working.height - 1);
  final cw = (cropW * sx).round().clamp(1, working.width - cx);
  final ch = (cropH * sy).round().clamp(1, working.height - cy);
  working = img.copyCrop(working, x: cx, y: cy, width: cw, height: ch);

  // 3) Color adjustments.
  working = img.adjustColor(
    working,
    brightness: p.brightness,
    contrast: p.contrast,
    saturation: p.saturation,
    exposure: p.exposure,
    hue: p.hue,
    gamma: p.gamma,
    blacks: p.shadowStrength > 0
        ? _hueToColorStatic(p.shadowHue, p.shadowStrength / 100)
        : null,
    whites: p.highlightStrength > 0
        ? _hueToColorStatic(p.highlightHue, p.highlightStrength / 100)
        : null,
  );

  // 3a) Temperature / tint via per-channel offset.
  if (p.temperature.abs() > 0.5 || p.tint.abs() > 0.5) {
    working = img.colorOffset(
      working,
      red: p.temperature * 0.4 - p.tint * 0.2,
      green: p.tint * 0.4,
      blue: -p.temperature * 0.4 - p.tint * 0.2,
    );
  }

  // 3b) Denoise → clarity → sharpness → grain → chromatic aberration → distort → vignette.
  if (p.denoise > 0) {
    final radius = (p.denoise / 100 * 3).round().clamp(1, 4);
    working = img.gaussianBlur(working, radius: radius);
  }
  if (p.clarity > 0) {
    // Clarity targets mid-frequency local contrast. We use a wider 5x5
    // unsharp-like kernel for a softer, more natural result.
    final amount = (p.clarity / 100).clamp(0.0, 1.0);
    working = img.convolution(
      working,
      filter: const <num>[
        0,
        -1,
        -1,
        -1,
        0,
        -1,
        2,
        2,
        2,
        -1,
        -1,
        2,
        12,
        2,
        -1,
        -1,
        2,
        2,
        2,
        -1,
        0,
        -1,
        -1,
        -1,
        0,
      ],
      div: 12,
      amount: amount,
    );
  }
  if (p.sharpness > 0) {
    // Standard 3×3 sharpen kernel. The `amount` parameter (0..1) blends
    // between the original image and the sharpened result; at 1.0 the
    // convolution is fully applied.
    final amount = (p.sharpness / 100).clamp(0.0, 1.0);
    working = img.convolution(
      working,
      filter: const <num>[0, -1, 0, -1, 5, -1, 0, -1, 0],
      div: 1,
      amount: amount,
    );
  }
  if (p.grain > 0) {
    // `noise` sigma is in pixel-value space (0..255). Scale 0..100 → 0..25.
    working = img.noise(working, p.grain / 100 * 25);
  }
  if (p.dispersion > 0.5) {
    working = img.chromaticAberration(
      working,
      shift: p.dispersion.round().clamp(1, 20),
    );
  }
  if (p.distort.abs() > 1) {
    if (p.distort > 0) {
      working = img.bulgeDistortion(
        working,
        scale: (p.distort / 100 * 0.8).clamp(0.0, 0.8),
      );
    } else if (p.distort < -20) {
      working = img.stretchDistortion(working);
    }
  }
  if (p.vignette > 0) {
    working = img.vignette(working, amount: p.vignette);
  }

  // 3c) Watermark text is composed on the UI isolate with Flutter text
  // rendering so Unicode/CJK text and arbitrary colors always render.

  // 4) Optional circular mask.
  if (p.isCircle) {
    working = _applyCircularMaskStatic(working);
  }

  // 5) Cap longest side.
  final maxSide = p.maxOutputLongSide;
  if (maxSide != null) {
    final longSide = math.max(working.width, working.height);
    if (longSide > maxSide) {
      if (working.width >= working.height) {
        working = img.copyResize(working, width: maxSide);
      } else {
        working = img.copyResize(working, height: maxSide);
      }
    }
  }

  // 6) Encode + optionally compress to limit.
  Uint8List outputBytes;
  if (p.isCircle || p.forcePng) {
    outputBytes = Uint8List.fromList(img.encodePng(working));
  } else {
    outputBytes = Uint8List.fromList(img.encodeJpg(working, quality: 92));
    final limit = p.imageSizeLimitBytes;
    if (limit != null && limit > 0 && outputBytes.length > limit) {
      for (var quality = 86; quality >= 30; quality -= 8) {
        outputBytes = Uint8List.fromList(
          img.encodeJpg(working, quality: quality),
        );
        if (outputBytes.length <= limit) break;
      }
      while (outputBytes.length > limit &&
          working.width > 320 &&
          working.height > 320) {
        working = img.copyResize(working, width: (working.width * 0.8).round());
        outputBytes = Uint8List.fromList(img.encodeJpg(working, quality: 82));
      }
    }
  }
  return (outputBytes, working.width, working.height);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Top-level helper functions (isolate-safe — no `this`, no `BuildContext`)
// ═══════════════════════════════════════════════════════════════════════════

Rect _computeImageRectStatic(Size previewSize, img.Image image) {
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

img.Image _applyCircularMaskStatic(img.Image source) {
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

img.Color _hueToColorStatic(double hueDeg, double strength) {
  final h = ((hueDeg % 360) + 360) % 360;
  final s = strength.clamp(0.0, 1.0);
  const l = 0.5;
  final c = (1 - (2 * l - 1).abs()) * s;
  final hp = h / 60;
  final x = c * (1 - (hp % 2 - 1).abs());
  double r = 0;
  double g = 0;
  double b = 0;
  if (hp < 1) {
    r = c;
    g = x;
  } else if (hp < 2) {
    r = x;
    g = c;
  } else if (hp < 3) {
    g = c;
    b = x;
  } else if (hp < 4) {
    g = x;
    b = c;
  } else if (hp < 5) {
    r = x;
    b = c;
  } else {
    r = c;
    b = x;
  }
  final m = l - c / 2;
  return img.ColorUint8.rgb(
    ((r + m) * 255).round().clamp(0, 255),
    ((g + m) * 255).round().clamp(0, 255),
    ((b + m) * 255).round().clamp(0, 255),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  Processing dialog
// ═══════════════════════════════════════════════════════════════════════════

/// A compact themed progress dialog used during heavy image processing.
class _ProcessingDialog extends StatelessWidget {
  const _ProcessingDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog(
      elevation: 0,
      backgroundColor: colorScheme.surfaceContainerHigh,
      surfaceTintColor: colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Text(
                message,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
