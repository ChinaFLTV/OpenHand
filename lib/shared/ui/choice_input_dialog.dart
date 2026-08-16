import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../../l10n/app_localizations.dart';
import 'animated_dialog.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_dialog_action_button.dart';

/// 单个可选项。
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

/// 选择结果；[selectedOption] 与 [customInput] 仅有一个非空。
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

  /// 选项值或去除首尾空白后的自定义输入。
  final String value;

  final ChoiceInputOption? selectedOption;
  final String? customInput;

  bool get isCustom => customInput != null;
}

/// 显示支持自定义输入的单选弹窗；关闭时返回 null。
///
/// 进退场动画由 [showAnimatedDialog] 统一读取全局设置。
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
  Future<void>? cancelSignal,
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
      cancelSignal: cancelSignal,
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
    this.cancelSignal,
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
  final Future<void>? cancelSignal;

  @override
  State<_ChoiceInputDialog> createState() => _ChoiceInputDialogState();
}

class _ChoiceInputDialogState extends State<_ChoiceInputDialog> {
  static const String _customValueSentinel = '__openhand.choice_input.custom__';

  late String _selectedValue;
  late final TextEditingController _customController;
  final FocusNode _customFocusNode = FocusNode();
  bool _dismissedByCancelSignal = false;

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
    widget.cancelSignal?.then<void>(
      (_) => _dismissForCancelSignal(),
      onError: (Object _, StackTrace _) => _dismissForCancelSignal(),
    );
  }

  @override
  void dispose() {
    _customController.dispose();
    _customFocusNode.dispose();
    super.dispose();
  }

  bool get _isCustomSelected => _selectedValue == _customValueSentinel;

  void _dismissForCancelSignal() {
    if (!mounted || _dismissedByCancelSignal) return;
    _dismissedByCancelSignal = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  bool get _canConfirm {
    if (_isCustomSelected) return _customController.text.trim().isNotEmpty;
    return widget.options.any((option) => option.value == _selectedValue);
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
    final l10n = AppLocalizations.of(context)!;
    final customLabel =
        widget.customOptionLabel ?? l10n.choiceInputCustomOptionLabel;
    final hintText = widget.customInputHint ?? l10n.choiceInputCustomInputHint;
    final confirm = widget.confirmLabel ?? l10n.commonConfirm;
    final cancel = widget.cancelLabel ?? l10n.commonCancel;
    final fieldExpandDuration = openHandTickerMotionEnabled(context)
        ? kOpenHandMotion220
        : Duration.zero;

    // 仅订阅尺寸变化，避免其他 MediaQuery 字段触发弹窗重建。
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
              kOpenHandGap8,
              Text(
                widget.description!,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            kOpenHandGap16,
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
                        subtitle: l10n.choiceInputCustomOptionDescription,
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
                      if (fieldExpandDuration == Duration.zero)
                        _buildCustomInputField(colorScheme, hintText)
                      else
                        AnimatedSize(
                          duration: fieldExpandDuration,
                          curve: Curves.easeInOutCubic,
                          alignment: Alignment.topLeft,
                          child: _buildCustomInputField(colorScheme, hintText),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            kOpenHandGap14,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.secondary(
                  label: cancel,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                kOpenHandHGap12,
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

  Widget _buildCustomInputField(ColorScheme colorScheme, String hintText) {
    if (!_isCustomSelected) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 6, bottom: 8),
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
            borderRadius: BorderRadius.circular(kOpenHandRadius14),
            borderSide: BorderSide.none,
          ),
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
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kOpenHandRadius14),
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
                kOpenHandHGap10,
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
                        kOpenHandGap2,
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
