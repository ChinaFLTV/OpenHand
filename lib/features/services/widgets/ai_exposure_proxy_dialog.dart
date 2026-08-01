import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_trailing_toolbar.dart';
import '../../../shared/util/localized_text.dart';
import '../model/ai_exposure_models.dart';
import '../services_controller.dart';

const int _kMaxProxyImportBytes = 4 * 1024 * 1024;
const int _kMaxProxyEndpoints = 10000;

Future<void> showAiExposureProxyDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthExtraWide,
        maxHeight: kOpenHandDialogHeightTall,
        child: const _ProxyDialog(),
      ),
    );

class _ProxyDialog extends StatefulWidget {
  const _ProxyDialog();

  @override
  State<_ProxyDialog> createState() => _ProxyDialogState();
}

class _ProxyDialogState extends State<_ProxyDialog> {
  final TextEditingController _endpoint = TextEditingController();
  late bool _enabled;
  late bool _bypassLocal;
  late AiExposureProxyStrategy _strategy;
  late double _rotationEvery;
  late List<AiExposureProxyEndpoint> _endpoints;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final configuration = context.read<ServicesController>().proxyConfiguration;
    _enabled = configuration.enabled;
    _bypassLocal = configuration.bypassLocal;
    _strategy = configuration.strategy;
    _rotationEvery = configuration.rotationEvery.toDouble();
    _endpoints = List<AiExposureProxyEndpoint>.of(configuration.endpoints);
  }

  @override
  void dispose() {
    _endpoint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = openHandTextResolver(context);
    final status = context.watch<ServicesController>().proxyStatus;
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpenHandResponsiveHeaderLayout(
            compactBreakpoint: 620,
            identity: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.lan_outlined, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text(zh: '网络代理与代理池', en: 'Network proxy pool'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        _enabled
                            ? text(
                                zh: '${_endpoints.length} 个代理 · ${_strategyLabel(_strategy, text)}',
                                en: '${_endpoints.length} proxies · ${_strategyLabel(_strategy, text)}',
                              )
                            : text(zh: '当前使用直接连接', en: 'Direct connection'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                  secondary: Icon(
                    _enabled ? Icons.vpn_lock_rounded : Icons.public_rounded,
                    color: _enabled ? cs.primary : cs.onSurfaceVariant,
                  ),
                  title: Text(
                    text(zh: '代理底层网络请求', en: 'Proxy network requests'),
                  ),
                  subtitle: Text(
                    text(
                      zh: '覆盖资产发现、目标探测、主动验证和 GPT 辅助请求。',
                      en: 'Covers discovery, probing, validation, and assisted requests.',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final strategy =
                        DropdownButtonFormField<AiExposureProxyStrategy>(
                          initialValue: _strategy,
                          decoration: InputDecoration(
                            labelText: text(zh: '代理策略', en: 'Proxy strategy'),
                            border: const OutlineInputBorder(),
                          ),
                          items: AiExposureProxyStrategy.values
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(_strategyLabel(item, text)),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _strategy = value);
                            }
                          },
                        );
                    final bypass = CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _bypassLocal,
                      onChanged: (value) =>
                          setState(() => _bypassLocal = value == true),
                      title: Text(
                        text(zh: '本地与私网直连', en: 'Bypass local networks'),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                    if (constraints.maxWidth < 680) {
                      return Column(
                        children: [strategy, const SizedBox(height: 8), bypass],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: strategy),
                        const SizedBox(width: 14),
                        Expanded(child: bypass),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        text(
                          zh: '每 ${_rotationEvery.round()} 次请求轮换',
                          en: 'Rotate every ${_rotationEvery.round()} requests',
                        ),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    Text('${_rotationEvery.round()}'),
                  ],
                ),
                Slider(
                  value: _rotationEvery,
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: '${_rotationEvery.round()}',
                  onChanged: _strategy == AiExposureProxyStrategy.roundRobin
                      ? (value) => setState(() => _rotationEvery = value)
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _endpoint,
                  onSubmitted: (_) => _addEndpoint(),
                  decoration: InputDecoration(
                    labelText: text(zh: '代理地址', en: 'Proxy address'),
                    hintText: 'username:password@127.0.0.1:8080',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: text(zh: '添加代理', en: 'Add proxy'),
                onPressed: _addEndpoint,
                icon: const Icon(Icons.add_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: text(zh: '批量导入', en: 'Bulk import'),
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.upload_file_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: text(zh: '导出代理池', en: 'Export pool'),
                onPressed: _endpoints.isEmpty || _busy ? null : _exportAll,
                icon: const Icon(Icons.download_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _endpoints.isEmpty
                ? Center(
                    child: Text(
                      text(
                        zh: '代理池为空，可手工添加或批量导入 TXT/JSON。',
                        en: 'Add a proxy or import a TXT/JSON pool.',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _endpoints.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final endpoint = _endpoints[index];
                      final selections = status?.endpoints
                          .where((item) => item.address == endpoint.maskedUrl)
                          .firstOrNull
                          ?.selections;
                      return Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.28,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.language_rounded,
                              size: 19,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                endpoint.maskedUrl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            if (selections != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                text(
                                  zh: '请求 $selections',
                                  en: '$selections requests',
                                ),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                            IconButton(
                              tooltip: text(zh: '导出此代理', en: 'Export proxy'),
                              onPressed: () => _exportOne(endpoint),
                              icon: const Icon(Icons.file_download_outlined),
                            ),
                            IconButton(
                              tooltip: text(zh: '移除代理', en: 'Remove proxy'),
                              onPressed: () =>
                                  setState(() => _endpoints.removeAt(index)),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: kOpenHandDialogActionSpacing,
            runSpacing: kOpenHandDialogActionSpacing,
            children: [
              OpenHandDialogActionButton.secondary(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).maybePop(),
                label: text(zh: '取消', en: 'Cancel'),
              ),
              OpenHandDialogActionButton.primary(
                icon: Icons.save_rounded,
                busy: _busy,
                onPressed: _busy ? null : _save,
                label: text(zh: '应用代理设置', en: 'Apply proxy settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addEndpoint() {
    try {
      final endpoint = AiExposureProxyEndpoint.parse(_endpoint.text);
      if (_endpoints.any((item) => item.url == endpoint.url)) {
        throw const FormatException('该代理已存在。');
      }
      if (_endpoints.length >= _kMaxProxyEndpoints) {
        throw const FormatException('代理池已达到 10000 条上限。');
      }
      setState(() {
        _endpoints.add(endpoint);
        _endpoint.clear();
      });
    } catch (error) {
      showOpenHandErrorSnack(context, '$error');
    }
  }

  Future<void> _import() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'Proxy', extensions: <String>['txt', 'json']),
      ],
    );
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final source = File(file.path);
      if (await source.length() > _kMaxProxyImportBytes) {
        throw const FormatException('代理文件不能超过 4 MB。');
      }
      final content = await source.readAsString();
      final values = _proxyValues(content);
      final merged = <String, AiExposureProxyEndpoint>{
        for (final endpoint in _endpoints) endpoint.url: endpoint,
      };
      var invalid = 0;
      for (final value in values) {
        if (merged.length >= _kMaxProxyEndpoints) break;
        try {
          final endpoint = AiExposureProxyEndpoint.parse(value);
          merged[endpoint.url] = endpoint;
        } on FormatException {
          invalid++;
        }
      }
      if (!mounted) return;
      setState(() => _endpoints = merged.values.toList(growable: true));
      showOpenHandSuccessSnack(
        context,
        invalid == 0
            ? '已导入 ${_endpoints.length} 个代理。'
            : '已导入 ${_endpoints.length} 个代理，忽略 $invalid 条无效记录。',
      );
    } catch (error) {
      if (mounted) showOpenHandErrorSnack(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportAll() async {
    final location = await getSaveLocation(
      suggestedName: 'openhand-ai-exposure-proxies.txt',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'TXT', extensions: <String>['txt']),
      ],
    );
    if (location == null) return;
    await writeFileAtomically(
      File(location.path),
      '${_endpoints.map((endpoint) => endpoint.url).join('\n')}\n',
    );
    if (mounted) showOpenHandSuccessSnack(context, '代理池已导出。');
  }

  Future<void> _exportOne(AiExposureProxyEndpoint endpoint) async {
    final location = await getSaveLocation(
      suggestedName: 'openhand-ai-exposure-proxy.json',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'JSON', extensions: <String>['json']),
      ],
    );
    if (location == null) return;
    final payload = const JsonEncoder.withIndent('  ').convert(
      <String, Object?>{
        'type': 'openhand_ai_exposure_proxy',
        'version': 1,
        'url': endpoint.url,
      },
    );
    await writeFileAtomically(File(location.path), payload);
    if (mounted) showOpenHandSuccessSnack(context, '代理配置已导出。');
  }

  Future<void> _save() async {
    if (_enabled && _endpoints.isEmpty) {
      showOpenHandErrorSnack(context, '启用代理前至少添加一个代理。');
      return;
    }
    setState(() => _busy = true);
    final updated = await context
        .read<ServicesController>()
        .updateProxyConfiguration(
          AiExposureProxyConfiguration(
            enabled: _enabled,
            strategy: _strategy,
            rotationEvery: _rotationEvery.round(),
            bypassLocal: _bypassLocal,
            endpoints: List<AiExposureProxyEndpoint>.unmodifiable(_endpoints),
          ),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (updated) Navigator.of(context).maybePop();
  }
}

List<String> _proxyValues(String content) {
  final trimmed = content.trim();
  if (trimmed.startsWith('{')) {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map && decoded['url'] is String) {
      return <String>[decoded['url'] as String];
    }
    throw const FormatException('代理 JSON 配置无效。');
  }
  return const LineSplitter()
      .convert(content)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList(growable: false);
}

String _strategyLabel(
  AiExposureProxyStrategy strategy,
  String Function({required String zh, required String en}) text,
) => switch (strategy) {
  AiExposureProxyStrategy.fixed => text(zh: '固定首选', en: 'Fixed'),
  AiExposureProxyStrategy.roundRobin => text(zh: '顺序轮询', en: 'Round robin'),
  AiExposureProxyStrategy.random => text(zh: '均衡随机', en: 'Random'),
  AiExposureProxyStrategy.stickyHost => text(zh: '目标粘性', en: 'Sticky host'),
};
