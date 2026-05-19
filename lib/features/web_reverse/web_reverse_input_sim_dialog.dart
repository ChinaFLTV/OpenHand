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
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseInputSimDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
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

  Future<void> _snack(String msg) async {
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) OpenHandSnackBar.showSuccessOn(context, m, msg);
  }

  Future<void> _runMouseClick() async {
    final loc0 = AppLocalizations.of(context);
    final x = double.tryParse(_mouseX.text.trim()) ?? 0;
    final y = double.tryParse(_mouseY.text.trim()) ?? 0;
    setState(() {
      _busy = true;
      _status = loc0?.webReverseInputSimDispatchingClick ?? 'Dispatching click...';
    });
    try {
      await widget.controller.dispatchMouseEvent(
        type: 'mouseMoved',
        x: x,
        y: y,
        button: 'none',
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
      silentLog('web-reverse', 'input-sim.mouse', e, st);
    }
    if (!mounted) return;
    final loc1 = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _status = loc1?.webReverseInputSimClickedAt(x.toString(), y.toString())
          ?? 'Clicked ($x, $y)';
    });
    await _snack(loc1?.webReverseInputSimDispatched ?? 'Dispatched');
  }

  Future<void> _runWheel(double dy) async {
    final loc0 = AppLocalizations.of(context);
    final x = double.tryParse(_mouseX.text.trim()) ?? 0;
    final y = double.tryParse(_mouseY.text.trim()) ?? 0;
    setState(() => _busy = true);
    try {
      await widget.controller.dispatchMouseEvent(
        type: 'mouseWheel',
        x: x,
        y: y,
        deltaX: 0,
        deltaY: dy,
        modifiers: _modifiers,
      );
    } catch (e, st) {
      silentLog('web-reverse', 'input-sim.wheel', e, st);
    }
    if (!mounted) return;
    final loc1 = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _status = loc1?.webReverseInputSimWheelDy(dy.toString())
          ?? 'Wheel dy=$dy';
    });
    // ignore unused
    loc0;
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
      silentLog('web-reverse', 'input-sim.key', e, st);
    }
    if (!mounted) return;
    final loc1 = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _status = loc1?.webReverseInputSimKeyDispatched ?? 'Key dispatched';
    });
    await _snack(loc1?.webReverseInputSimDispatched ?? 'Dispatched');
  }

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
      silentLog('web-reverse', 'input-sim.insert', e, st);
    }
    if (!mounted) return;
    final loc1 = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _status = loc1?.webReverseInputSimInsertedCount(t.length)
          ?? 'Inserted ${t.length} chars';
    });
    await _snack(loc1?.webReverseInputSimInserted ?? 'Inserted');
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
                  decoration: InputDecoration(
                    labelText: 'X',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _mouseY,
                  decoration: InputDecoration(
                    labelText: 'Y',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(loc?.webReverseInputSimButton ?? 'Button',
              style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: ['left', 'middle', 'right']
                .map((b) => ChoiceChip(
                      label: Text(b),
                      selected: _mouseButton == b,
                      onSelected: (_) => setState(() => _mouseButton = b),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(loc?.webReverseInputSimClickCount ?? 'Click count'),
              const SizedBox(width: 8),
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
          const SizedBox(height: 12),
          Text(loc?.webReverseInputSimModifiers ?? 'Modifiers',
              style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          _modifierChips(),
          const SizedBox(height: 16),
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
            decoration: InputDecoration(
              labelText: 'key',
              hintText: 'Enter / ArrowDown / a',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _keyCode,
            decoration: InputDecoration(
              labelText: 'code',
              hintText: 'KeyA / Enter / ArrowDown',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _keyText,
            decoration: InputDecoration(
              labelText: loc?.webReverseInputSimKeyTextLabel ?? 'text (printable char)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          Text(loc?.webReverseInputSimModifiers ?? 'Modifiers',
              style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          _modifierChips(),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _runKey,
            icon: const Icon(Icons.keyboard_rounded),
            label: Text(loc?.webReverseInputSimDispatchKeyDownUp ?? 'Dispatch keyDown+keyUp'),
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            minLines: 4,
            maxLines: 8,
          ),
          const SizedBox(height: 12),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  Icon(Icons.ads_click_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc?.webReverseInputSimTitle ?? 'Input Event Simulator',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Input.dispatchMouseEvent / dispatchKeyEvent / insertText',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
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
            if (_busy) const LinearProgressIndicator(minHeight: 3),
            if (_status.isNotEmpty)
              Container(
                width: double.infinity,
                color: cs.surfaceContainerHigh,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  _status,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OpenHandDialogActionButton.primary(
                  label: loc?.webReverseInputSimCloseBtn ?? 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
