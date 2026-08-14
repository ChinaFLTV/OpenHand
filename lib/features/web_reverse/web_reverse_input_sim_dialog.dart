/// 输入事件模拟面板。
///
/// 三个 tab：鼠标 / 键盘 / 文本。底层封装在
/// [WebReverseSessionController.dispatchMouseEvent] /
/// [WebReverseSessionController.dispatchKeyEvent] /
/// [WebReverseSessionController.insertText]。
library;

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/util/input_value_parsing.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseInputSimDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _InputSimDialog(controller: controller, isZh: isZh),
  );
}

class _InputSimDialog extends StatefulWidget {
  const _InputSimDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_InputSimDialog> createState() => _InputSimDialogState();
}

class _InputSimDialogState extends State<_InputSimDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  // mouse
  final _mouseX = TextEditingController(text: '200');
  final _mouseY = TextEditingController(text: '200');
  String _mouseButton = 'left';
  int _clickCount = 1;
  // key
  final _keyText = TextEditingController();
  final _keyCode = TextEditingController();
  final _keyKey = TextEditingController();
  bool _modShift = false;
  bool _modCtrl = false;
  bool _modAlt = false;
  bool _modMeta = false;
  // text
  final _insertCtrl = TextEditingController();

  String _status = '';
  bool _busy = false;

  @override
  void dispose() {
    _tab.dispose();
    _mouseX.dispose();
    _mouseY.dispose();
    _keyText.dispose();
    _keyCode.dispose();
    _keyKey.dispose();
    _insertCtrl.dispose();
    super.dispose();
  }

  int get _modifiers {
    var v = 0;
    if (_modAlt) v |= 1;
    if (_modCtrl) v |= 2;
    if (_modMeta) v |= 4;
    if (_modShift) v |= 8;
    return v;
  }

  void _snack(String msg) {
    if (!mounted) return;
    showOpenHandSuccessSnack(context, msg);
  }

  Future<void> _runMouseClick() async {
    final loc0 = AppLocalizations.of(context);
    final point = _mousePoint;
    final x = point.x;
    final y = point.y;
    setState(() {
      _busy = true;
      _status =
          loc0?.webReverseInputSimDispatchingClick ?? 'Dispatching click...';
    });
    try {
      await widget.controller.dispatchMouseEvent(
        type: 'mouseMoved',
        x: x,
        y: y,
        modifiers: _modifiers,
      );
      await widget.controller.dispatchMouseEvent(
        type: 'mousePressed',
        x: x,
        y: y,
        button: _mouseButton,
        buttons: 1,
        clickCount: _clickCount,
        modifiers: _modifiers,
      );
      await widget.controller.dispatchMouseEvent(
        type: 'mouseReleased',
        x: x,
        y: y,
        button: _mouseButton,
        clickCount: _clickCount,
        modifiers: _modifiers,
      );
    } catch (e, st) {
      silentLog('web_reverse_input_sim_dialog', '模拟鼠标输入', e, st);
    }
    if (!mounted) return;
    final loc1 = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _status =
          loc1?.webReverseInputSimClickedAt(x.toString(), y.toString()) ??
          'Clicked ($x, $y)';
    });
    _snack(loc1?.webReverseInputSimDispatched ?? 'Dispatched');
  }

  Future<void> _runWheel(double dy) async {
    final point = _mousePoint;
    final x = point.x;
    final y = point.y;
    setState(() => _busy = true);
    try {
      await widget.controller.dispatchMouseEvent(
        type: 'mouseWheel',
        x: x,
        y: y,
        deltaY: dy,
        modifiers: _modifiers,
      );
    } catch (e, st) {
      silentLog('web_reverse_input_sim_dialog', '模拟滚轮输入', e, st);
    }
    if (!mounted) return;
    final loc1 = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _status =
          loc1?.webReverseInputSimWheelDy(dy.toString()) ?? 'Wheel dy=$dy';
    });
  }

  Future<void> _runKey() async {
    final loc0 = AppLocalizations.of(context);
    final key = _keyKey.text.trim();
    final code = _keyCode.text.trim();
    final text = _keyText.text;
    if (key.isEmpty && code.isEmpty && text.isEmpty) return;
    setState(() {
      _busy = true;
      _status = loc0?.webReverseInputSimDispatchingKey ?? 'Dispatching key...';
    });
    try {
      await widget.controller.dispatchKeyEvent(
        type: 'keyDown',
        key: key.isEmpty ? null : key,
        code: code.isEmpty ? null : code,
        text: text.isEmpty ? null : text,
        modifiers: _modifiers,
      );
      await widget.controller.dispatchKeyEvent(
        type: 'keyUp',
        key: key.isEmpty ? null : key,
        code: code.isEmpty ? null : code,
        modifiers: _modifiers,
      );
    } catch (e, st) {
      silentLog('web_reverse_input_sim_dialog', '模拟按键输入', e, st);
    }
    if (!mounted) return;
    final loc1 = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _status = loc1?.webReverseInputSimKeyDispatched ?? 'Key dispatched';
    });
    _snack(loc1?.webReverseInputSimDispatched ?? 'Dispatched');
  }

  ({double x, double y}) get _mousePoint => (
    x: doubleFromValue(_mouseX.text, fallback: 0),
    y: doubleFromValue(_mouseY.text, fallback: 0),
  );

  Future<void> _runInsertText() async {
    final loc0 = AppLocalizations.of(context);
    final t = _insertCtrl.text;
    if (t.isEmpty) return;
    setState(() {
      _busy = true;
      _status = loc0?.webReverseInputSimInsertingText ?? 'Inserting text...';
    });
    try {
      await widget.controller.insertText(t);
    } catch (e, st) {
      silentLog('web_reverse_input_sim_dialog', '模拟文本输入', e, st);
    }
    if (!mounted) return;
    final loc1 = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _status =
          loc1?.webReverseInputSimInsertedCount(t.length) ??
          'Inserted ${t.length} chars';
    });
    _snack(loc1?.webReverseInputSimInserted ?? 'Inserted');
  }

  Widget _modifierChips() {
    Widget chip(String label, bool v, ValueChanged<bool> set) => FilterChip(
      label: Text(label),
      selected: v,
      onSelected: set,
      showCheckmark: false,
    );
    return Wrap(
      spacing: 6,
      children: [
        chip('Shift', _modShift, (v) => setState(() => _modShift = v)),
        chip('Ctrl', _modCtrl, (v) => setState(() => _modCtrl = v)),
        chip('Alt', _modAlt, (v) => setState(() => _modAlt = v)),
        chip('Meta/⌘', _modMeta, (v) => setState(() => _modMeta = v)),
      ],
    );
  }

  Widget _mouseTab() {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _mouseX,
                  decoration: const InputDecoration(
                    labelText: 'X',
                    border: OutlineInputBorder(
                      borderRadius: kOpenHandBorderRadius10,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              kOpenHandHGap10,
              Expanded(
                child: TextField(
                  controller: _mouseY,
                  decoration: const InputDecoration(
                    labelText: 'Y',
                    border: OutlineInputBorder(
                      borderRadius: kOpenHandBorderRadius10,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          kOpenHandGap12,
          Text(
            loc?.webReverseInputSimButton ?? 'Button',
            style: theme.textTheme.labelMedium,
          ),
          kOpenHandGap4,
          Wrap(
            spacing: 6,
            children: ['left', 'middle', 'right']
                .map(
                  (b) => ChoiceChip(
                    label: Text(b),
                    selected: _mouseButton == b,
                    onSelected: (_) => setState(() => _mouseButton = b),
                  ),
                )
                .toList(),
          ),
          kOpenHandGap12,
          Row(
            children: [
              Text(loc?.webReverseInputSimClickCount ?? 'Click count'),
              kOpenHandHGap8,
              ...List.generate(3, (i) {
                final n = i + 1;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('$n'),
                    selected: _clickCount == n,
                    onSelected: (_) => setState(() => _clickCount = n),
                  ),
                );
              }),
            ],
          ),
          kOpenHandGap12,
          Text(
            loc?.webReverseInputSimModifiers ?? 'Modifiers',
            style: theme.textTheme.labelMedium,
          ),
          kOpenHandGap4,
          _modifierChips(),
          kOpenHandGap16,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _runMouseClick,
                icon: const Icon(Icons.touch_app_rounded),
                label: Text(loc?.webReverseInputSimClickBtn ?? 'Click'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _runWheel(120),
                icon: const Icon(Icons.expand_more_rounded),
                label: Text(loc?.webReverseInputSimWheelDown ?? 'Wheel ↓'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _runWheel(-120),
                icon: const Icon(Icons.expand_less_rounded),
                label: Text(loc?.webReverseInputSimWheelUp ?? 'Wheel ↑'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _keyTab() {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _keyKey,
            decoration: const InputDecoration(
              labelText: 'key',
              hintText: 'Enter / ArrowDown / a',
              border: OutlineInputBorder(borderRadius: kOpenHandBorderRadius10),
            ),
          ),
          kOpenHandGap10,
          TextField(
            controller: _keyCode,
            decoration: const InputDecoration(
              labelText: 'code',
              hintText: 'KeyA / Enter / ArrowDown',
              border: OutlineInputBorder(borderRadius: kOpenHandBorderRadius10),
            ),
          ),
          kOpenHandGap10,
          TextField(
            controller: _keyText,
            decoration: InputDecoration(
              labelText:
                  loc?.webReverseInputSimKeyTextLabel ??
                  'text (printable char)',
              border: const OutlineInputBorder(
                borderRadius: kOpenHandBorderRadius10,
              ),
            ),
          ),
          kOpenHandGap12,
          Text(
            loc?.webReverseInputSimModifiers ?? 'Modifiers',
            style: theme.textTheme.labelMedium,
          ),
          kOpenHandGap4,
          _modifierChips(),
          kOpenHandGap16,
          FilledButton.icon(
            onPressed: _busy ? null : _runKey,
            icon: const Icon(Icons.keyboard_rounded),
            label: Text(
              loc?.webReverseInputSimDispatchKeyDownUp ??
                  'Dispatch keyDown+keyUp',
            ),
          ),
        ],
      ),
    );
  }

  Widget _textTab() {
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _insertCtrl,
            decoration: InputDecoration(
              labelText: loc?.webReverseInputSimInsertTextLabel ?? 'insertText',
              border: const OutlineInputBorder(
                borderRadius: kOpenHandBorderRadius10,
              ),
            ),
            minLines: 4,
            maxLines: 8,
          ),
          kOpenHandGap12,
          FilledButton.icon(
            onPressed: _busy ? null : _runInsertText,
            icon: const Icon(Icons.text_fields_rounded),
            label: Text(loc?.webReverseInputSimInsertBtn ?? 'Insert'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthStandard,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.ads_click_rounded,
            title: loc?.webReverseInputSimTitle ?? 'Input Event Simulator',
            subtitle:
                'Input.dispatchMouseEvent / dispatchKeyEvent / insertText',
          ),
          TabBar(
            controller: _tab,
            tabs: [
              Tab(text: loc?.webReverseInputSimTabMouse ?? 'Mouse'),
              Tab(text: loc?.webReverseInputSimTabKey ?? 'Key'),
              Tab(text: loc?.webReverseInputSimTabText ?? 'Text'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [_mouseTab(), _keyTab(), _textTab()],
            ),
          ),
          OpenHandBusyProgressBar(busy: _busy),
          buildWebReverseStatusBar(context, status: _status),
          buildOpenHandDialogFooter(
            primaryLabel: loc?.webReverseInputSimCloseBtn ?? 'Close',
            onPrimaryPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
