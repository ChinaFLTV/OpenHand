import 'package:flutter/material.dart';

import '../util/localized_text.dart';
import 'animated_dialog.dart';
import 'motion_preference.dart';
import 'openhand_dialog_action_button.dart';

/// A single selectable choice displayed to the user.
///
/// - [value]: machine-readable identifier returned via [ChoiceInputResult.value].
/// - [label]: short primary text rendered on the radio tile.
/// - [description]: optional secondary helper text shown beneath the label.
class ChoiceInputOption {
  const ChoiceInputOption({
    required this.value,
    required this.label,
    this.description,
  });

  final String value;
  final String label;
  final String? description;
}

/// Result returned from the choice-input dialog.
///
/// Exactly one of [selectedOption] or [customInput] is set:
/// - [selectedOption] — the user picked one of the predefined options
///   (its [ChoiceInputOption.value] is returned directly as [value]).
/// - [customInput] — the user chose the "custom" radio and typed free text;
///   the trimmed text is returned as [value].
class ChoiceInputResult {
  const ChoiceInputResult._({
    required this.value,
    this.selectedOption,
    this.customInput,
  });

  factory ChoiceInputResult.option(ChoiceInputOption option) =>
      ChoiceInputResult._(value: option.value, selectedOption: option);

  factory ChoiceInputResult.custom(String text) =>
      ChoiceInputResult._(value: text, customInput: text);

  /// Either the selected option's value or the trimmed custom input.
  final String value;

  final ChoiceInputOption? selectedOption;
  final String? customInput;

  bool get isCustom => customInput != null;
}

/// Shows a modal "single-select with optional free-form answer" dialog.
///
/// Uses [showAnimatedDialog] so the entrance/exit animations honor the
/// global `Settings → 弹窗动画` configuration automatically.
///
/// Returns `null` if the user dismisses the dialog (tap outside / Esc / cancel).
Future<ChoiceInputResult?> showChoiceInputDialog({
  required BuildContext context,
  required String title,
  required List<ChoiceInputOption> options,
  String? description,
  String? confirmLabel,
  String? cancelLabel,
  String? customOptionLabel,
  String? customInputHint,
  bool allowCustomInput = true,
  String? initialSelectedValue,
  String? initialCustomInput,
  bool barrierDismissible = true,
}) {
  if (options.isEmpty && !allowCustomInput) {
    return Future<ChoiceInputResult?>.value();
  }
  return showAnimatedDialog<ChoiceInputResult>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => _ChoiceInputDialog(
      title: title,
      description: description,
      options: options,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      customOptionLabel: customOptionLabel,
      customInputHint: customInputHint,
      allowCustomInput: allowCustomInput,
      initialSelectedValue: initialSelectedValue,
      initialCustomInput: initialCustomInput,
    ),
  );
}

class _ChoiceInputDialog extends StatefulWidget {
  const _ChoiceInputDialog({
    required this.title,
    required this.options,
    required this.allowCustomInput,
    this.description,
    this.confirmLabel,
    this.cancelLabel,
    this.customOptionLabel,
    this.customInputHint,
    this.initialSelectedValue,
    this.initialCustomInput,
  });

  final String title;
  final String? description;
  final List<ChoiceInputOption> options;
  final String? confirmLabel;
  final String? cancelLabel;
  final String? customOptionLabel;
  final String? customInputHint;
  final bool allowCustomInput;
  final String? initialSelectedValue;
  final String? initialCustomInput;

  @override
  State<_ChoiceInputDialog> createState() => _ChoiceInputDialogState();
}

class _ChoiceInputDialogState extends State<_ChoiceInputDialog> {
  static const String _customValueSentinel = '__openhand.choice_input.custom__';

  late String _selectedValue;
  late final TextEditingController _customController;
  final FocusNode _customFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController(
      text: widget.initialCustomInput ?? '',
    );
    final initial = widget.initialSelectedValue?.trim();
    final matched = initial == null
        ? null
        : widget.options.firstWhere(
            (option) => option.value == initial,
            orElse: () => const ChoiceInputOption(value: '', label: ''),
          );
    if (matched != null && matched.value.isNotEmpty) {
      _selectedValue = matched.value;
    } else if (widget.allowCustomInput &&
        (widget.options.isEmpty ||
            (widget.initialCustomInput?.trim().isNotEmpty ?? false))) {
      _selectedValue = _customValueSentinel;
    } else if (widget.options.isNotEmpty) {
      _selectedValue = widget.options.first.value;
    } else {
      _selectedValue = '';
    }
    if (_selectedValue == _customValueSentinel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _customFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    _customFocusNode.dispose();
    super.dispose();
  }

  bool get _isCustomSelected => _selectedValue == _customValueSentinel;

  bool get _canConfirm {
    if (_isCustomSelected) return _customController.text.trim().isNotEmpty;
    return widget.options.any((option) => option.value == _selectedValue);
  }

  String _localized({required String zh, required String en}) {
    return openHandLocalizedText(context, zh: zh, en: en);
  }

  void _confirm() {
    if (_isCustomSelected) {
      final trimmed = _customController.text.trim();
      if (trimmed.isEmpty) return;
      Navigator.of(context).pop(ChoiceInputResult.custom(trimmed));
      return;
    }
    ChoiceInputOption? selected;
    for (final option in widget.options) {
      if (option.value == _selectedValue) {
        selected = option;
        break;
      }
    }
    if (selected == null) return;
    Navigator.of(context).pop(ChoiceInputResult.option(selected));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final customLabel =
        widget.customOptionLabel ?? _localized(zh: '自定义输入', en: 'Custom input');
    final hintText =
        widget.customInputHint ??
        _localized(zh: '在此输入你的回答…', en: 'Type your answer here…');
    final confirm = widget.confirmLabel ?? _localized(zh: '确定', en: 'Confirm');
    final cancel = widget.cancelLabel ?? _localized(zh: '取消', en: 'Cancel');
    final fieldExpandDuration = openHandMotionDuration(
      context,
      const Duration(milliseconds: 220),
    );

    // `MediaQuery.sizeOf` only depends on the `size` aspect, so this dialog
    // does not rebuild on unrelated MediaQuery changes (text scale, viewInsets,
    // padding, etc.).
    final mediaSize = MediaQuery.sizeOf(context);
    final maxDialogWidth = mediaSize.width.clamp(280.0, 560.0);
    final maxContentHeight = mediaSize.height * 0.7;

    return buildOpenHandDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      maxWidth: maxDialogWidth,
      maxHeight: maxContentHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.description != null &&
                widget.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.description!,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final option in widget.options)
                      _ChoiceTile(
                        title: option.label,
                        subtitle: option.description,
                        selected: _selectedValue == option.value,
                        onTap: () {
                          setState(() {
                            _selectedValue = option.value;
                          });
                        },
                      ),
                    if (widget.allowCustomInput) ...[
                      _ChoiceTile(
                        title: customLabel,
                        subtitle: _localized(
                          zh: '选择此项以手动填写内容',
                          en: 'Pick this to type your own answer',
                        ),
                        selected: _isCustomSelected,
                        onTap: () {
                          setState(() {
                            _selectedValue = _customValueSentinel;
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _customFocusNode.requestFocus();
                          });
                        },
                      ),
                      AnimatedSize(
                        duration: fieldExpandDuration,
                        curve: Curves.easeInOutCubic,
                        alignment: Alignment.topLeft,
                        child: _isCustomSelected
                            ? Padding(
                                padding: const EdgeInsets.only(
                                  left: 12,
                                  right: 4,
                                  top: 6,
                                  bottom: 8,
                                ),
                                child: TextField(
                                  controller: _customController,
                                  focusNode: _customFocusNode,
                                  minLines: 2,
                                  maxLines: 6,
                                  textInputAction: TextInputAction.newline,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText: hintText,
                                    filled: true,
                                    fillColor: colorScheme.surfaceContainerHigh,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.secondary(
                  label: cancel,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
                OpenHandDialogActionButton.primary(
                  label: confirm,
                  onPressed: _canConfirm ? _confirm : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.55)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface,
                        ),
                      ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: selected
                                ? colorScheme.onPrimaryContainer.withValues(
                                    alpha: 0.85,
                                  )
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
