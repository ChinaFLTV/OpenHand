import 'package:flutter/material.dart';

import '../../app/model/app_settings_snapshot.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_form_fields.dart';
import '../../shared/ui/openhand_model_selector_field.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';
import '../ai/index.dart';
import 'android_reverse_dialog_utils.dart';
import 'android_reverse_session_config.dart';

/// 弹出 Android 逆向会话创建表单。
/// 返回 null 表示用户取消；返回结果后上层负责创建 controller 和会话。
Future<AndroidReverseSetupResult?> showAndroidReverseSetupDialog(
  BuildContext context, {
  String? initialPackageName,
  String? initialObjective,
  List<AiModelConfig> availableModels = const <AiModelConfig>[],
  List<RecentModelSelection> recentModelSelections =
      const <RecentModelSelection>[],
  String? initialSelectedModelConfigId,
  String? initialSelectedModelId,
}) {
  return androidReverseToolDialogs.show<AndroidReverseSetupResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AndroidReverseSetupDialog(
      initialPackageName: initialPackageName,
      initialObjective: initialObjective,
      availableModels: availableModels,
      recentModelSelections: recentModelSelections,
      initialSelectedModelConfigId: initialSelectedModelConfigId,
      initialSelectedModelId: initialSelectedModelId,
    ),
  );
}

class AndroidReverseSetupResult {
  const AndroidReverseSetupResult({
    required this.config,
    required this.selectedModelConfigId,
    required this.selectedModelId,
  });

  final AndroidReverseSessionConfig config;
  final String? selectedModelConfigId;
  final String? selectedModelId;
}

class _AndroidReverseSetupDialog extends StatefulWidget {
  const _AndroidReverseSetupDialog({
    required this.initialPackageName,
    required this.initialObjective,
    required this.availableModels,
    required this.recentModelSelections,
    required this.initialSelectedModelConfigId,
    required this.initialSelectedModelId,
  });

  final String? initialPackageName;
  final String? initialObjective;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;
  final String? initialSelectedModelConfigId;
  final String? initialSelectedModelId;

  @override
  State<_AndroidReverseSetupDialog> createState() =>
      _AndroidReverseSetupDialogState();
}

class _AndroidReverseSetupDialogState extends State<_AndroidReverseSetupDialog>
    with OpenHandModelSelectionState<_AndroidReverseSetupDialog> {
  late final TextEditingController _objectiveCtrl;
  late final TextEditingController _packageCtrl;
  late final TextEditingController _apkCtrl;
  late final TextEditingController _deviceCtrl;
  late final TextEditingController _authorizationScopeCtrl;
  late final TextEditingController _keywordsCtrl;
  late final TextEditingController _notesCtrl;
  AndroidReverseAnalysisMode _analysisMode =
      AndroidReverseAnalysisMode.balanced;
  bool _adbMcpEnabled = false;
  bool _fridaMcpEnabled = false;

  @override
  void initState() {
    super.initState();
    _objectiveCtrl = TextEditingController(text: widget.initialObjective ?? '');
    _packageCtrl = TextEditingController(text: widget.initialPackageName ?? '');
    _apkCtrl = TextEditingController();
    _deviceCtrl = TextEditingController();
    _authorizationScopeCtrl = TextEditingController();
    _keywordsCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    initializeOpenHandModelSelection(
      initialConfigId: widget.initialSelectedModelConfigId,
      initialModelId: widget.initialSelectedModelId,
      availableModels: widget.availableModels,
    );
  }

  @override
  void dispose() {
    _objectiveCtrl.dispose();
    _packageCtrl.dispose();
    _apkCtrl.dispose();
    _deviceCtrl.dispose();
    _authorizationScopeCtrl.dispose();
    _keywordsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _hasValidModelSelection {
    return hasValidOpenHandModelSelection(widget.availableModels);
  }

  bool get _requiresAuthorizationScope =>
      _analysisMode == AndroidReverseAnalysisMode.dynamicFirst ||
      _adbMcpEnabled ||
      _fridaMcpEnabled;

  bool get _hasAuthorizationScope =>
      _authorizationScopeCtrl.text.trim().isNotEmpty;

  bool get _canSubmit =>
      _objectiveCtrl.text.trim().isNotEmpty &&
      _hasValidModelSelection &&
      (!_requiresAuthorizationScope || _hasAuthorizationScope);

  void _submit() {
    final keywords = splitLooseDelimitedValues(_keywordsCtrl.text);
    final config = AndroidReverseSessionConfig(
      objective: _objectiveCtrl.text.trim(),
      packageName: nullIfBlank(_packageCtrl.text),
      apkPath: nullIfBlank(_apkCtrl.text),
      deviceSerial: nullIfBlank(_deviceCtrl.text),
      authorizationScope: nullIfBlank(_authorizationScopeCtrl.text),
      analysisMode: _analysisMode,
      adbMcpEnabled: _adbMcpEnabled,
      fridaMcpEnabled: _fridaMcpEnabled,
      keywords: keywords,
      notes: nullIfBlank(_notesCtrl.text),
    );
    Navigator.of(context).pop(
      AndroidReverseSetupResult(
        config: config,
        selectedModelConfigId: selectedModelConfigId,
        selectedModelId: selectedModelId,
      ),
    );
  }

  /// 绑定当前语言的行内文本取值；语言切换后随重建自动生效。
  OpenHandLocalizedTextResolver get _text => openHandTextResolver(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 620,
      insetPadding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.android_rounded,
            title: _text(
              zh: '新建 Android 逆向会话',
              en: 'New Android Reverse Session',
              zhHant: '新建 Android 逆向會話',
              fr: 'Nouvelle session reverse Android',
              de: 'Neue Android-Reverse-Sitzung',
              ja: '新規 Android リバースセッション',
            ),
            subtitle: _text(
              zh: '通过 ADB + Frida + jadx 完成 APP 接口逆向与参数还原',
              en: 'Reverse Android APP APIs via ADB + Frida + jadx',
              zhHant: '透過 ADB + Frida + jadx 完成 APP 介面逆向與參數還原',
              fr: 'Reverse des API Android avec ADB + Frida + jadx',
              de: 'Android-App-APIs mit ADB + Frida + jadx analysieren und Parameter rekonstruieren',
              ja: 'ADB + Frida + jadx で Android アプリ API とパラメータを解析',
            ),
            closeTooltip: openHandCloseLabel(context),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OpenHandFormLabel(
                    _text(
                      zh: '逆向目标 *',
                      en: 'Objective *',
                      zhHant: '逆向目標 *',
                      fr: 'Objectif *',
                      de: 'Ziel *',
                      ja: '解析目標 *',
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _objectiveCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _text(
                        zh: '例：还原微信 APP 的 sign 签名算法',
                        en: 'e.g. reverse the sign algorithm in com.tencent.mm',
                        zhHant: '例：還原微信 APP 的 sign 簽名演算法',
                        fr: 'ex. reconstruire l’algorithme de signature sign de com.tencent.mm',
                        de: 'z. B. den sign-Algorithmus in com.tencent.mm rekonstruieren',
                        ja: '例: com.tencent.mm の sign 署名アルゴリズムを解析',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  OpenHandModelSelectorField(
                    models: widget.availableModels,
                    recentSelections: widget.recentModelSelections,
                    selectedConfigId: selectedModelConfigId,
                    selectedModelId: selectedModelId,
                    required: true,
                    onSelected: selectOpenHandModel,
                  ),
                  const SizedBox(height: 14),
                  OpenHandFormLabel(
                    _text(
                      zh: '目标包名（可选）',
                      en: 'Package name (optional)',
                      zhHant: '目標套件名稱（可選）',
                      fr: 'Nom du paquet (facultatif)',
                      de: 'Paketname (optional)',
                      ja: '対象パッケージ名（任意）',
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _packageCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'com.example.app',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OpenHandFormLabel(
                    _text(
                      zh: 'APK 路径（可选，仅用于静态分析）',
                      en: 'APK path (optional)',
                      zhHant: 'APK 路徑（可選，僅用於靜態分析）',
                      fr: 'Chemin APK (facultatif)',
                      de: 'APK-Pfad (optional)',
                      ja: 'APK パス（任意）',
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _apkCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '/path/to/app.apk',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OpenHandFormLabel(
                    _text(
                      zh: 'ADB 设备序列号（可选，留空自动选唯一在线设备）',
                      en: 'Device serial (optional)',
                      zhHant: 'ADB 裝置序號（可選，留空自動選唯一在線裝置）',
                      fr: 'Série de l’appareil (facultatif)',
                      de: 'Geräteseriennummer (optional)',
                      ja: 'ADB デバイスシリアル（任意）',
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _deviceCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'emulator-5554',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OpenHandFormLabel(
                    _text(
                      zh: '分析模式',
                      en: 'Analysis mode',
                      zhHant: '分析模式',
                      fr: 'Mode d’analyse',
                      de: 'Analysemodus',
                      ja: '解析モード',
                    ),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<AndroidReverseAnalysisMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: AndroidReverseAnalysisMode.staticFirst,
                        icon: const Icon(Icons.manage_search_rounded),
                        label: Text(
                          _text(
                            zh: '静态优先',
                            en: 'Static',
                            zhHant: '靜態優先',
                            fr: 'Statique',
                            de: 'Statisch',
                            ja: '静的優先',
                          ),
                        ),
                      ),
                      ButtonSegment(
                        value: AndroidReverseAnalysisMode.balanced,
                        icon: const Icon(Icons.hub_rounded),
                        label: Text(
                          _text(
                            zh: '均衡',
                            en: 'Balanced',
                            zhHant: '均衡',
                            fr: 'Équilibré',
                            de: 'Ausgewogen',
                            ja: 'バランス',
                          ),
                        ),
                      ),
                      ButtonSegment(
                        value: AndroidReverseAnalysisMode.dynamicFirst,
                        icon: const Icon(Icons.play_circle_rounded),
                        label: Text(
                          _text(
                            zh: '动态验证',
                            en: 'Dynamic',
                            zhHant: '動態驗證',
                            fr: 'Dynamique',
                            de: 'Dynamisch',
                            ja: '動的検証',
                          ),
                        ),
                      ),
                    ],
                    selected: {_analysisMode},
                    onSelectionChanged: (values) {
                      final next = values.firstOrNull;
                      if (next != null) {
                        setState(() => _analysisMode = next);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  OpenHandFormLabel(
                    _requiresAuthorizationScope
                        ? _text(
                            zh: '授权范围 *',
                            en: 'Authorization scope *',
                            zhHant: '授權範圍 *',
                            fr: 'Périmètre autorisé *',
                            de: 'Autorisierungsumfang *',
                            ja: '許可範囲 *',
                          )
                        : _text(
                            zh: '授权范围（建议填写）',
                            en: 'Authorization scope (recommended)',
                            zhHant: '授權範圍（建議填寫）',
                            fr: 'Périmètre autorisé (recommandé)',
                            de: 'Autorisierungsumfang (empfohlen)',
                            ja: '許可範囲（推奨）',
                          ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _authorizationScopeCtrl,
                    maxLines: 2,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _text(
                        zh: '例：自有测试 APP / CTF / 已获授权的安全研究，不涉及第三方隐私数据',
                        en: 'e.g. owned test app / CTF / authorized research; no third-party private data',
                        zhHant: '例：自有測試 APP / CTF / 已獲授權的安全研究，不涉及第三方隱私資料',
                        fr: 'ex. app de test possédée / CTF / recherche autorisée, sans données privées tierces',
                        de: 'z. B. eigene Test-App / CTF / autorisierte Forschung, keine privaten Daten Dritter',
                        ja: '例: 所有するテストアプリ / CTF / 許可済み研究、第三者の個人データなし',
                      ),
                      border: const OutlineInputBorder(),
                      errorText:
                          _requiresAuthorizationScope && !_hasAuthorizationScope
                          ? _text(
                              zh: '动态验证或 MCP 通道需要先填写授权范围',
                              en: 'Dynamic verification or MCP requires an authorization scope',
                              zhHant: '動態驗證或 MCP 通道需要先填寫授權範圍',
                              fr: 'La vérification dynamique ou MCP nécessite un périmètre autorisé',
                              de: 'Dynamische Prüfung oder MCP erfordert einen Autorisierungsumfang',
                              ja: '動的検証または MCP には許可範囲が必要です',
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  OpenHandAnimatedSwitchTile(
                    icon: Icons.usb_rounded,
                    title: _text(
                      zh: 'ADB MCP（可选）',
                      en: 'ADB MCP (optional)',
                      zhHant: 'ADB MCP（可選）',
                      fr: 'ADB MCP (facultatif)',
                      de: 'ADB MCP (optional)',
                      ja: 'ADB MCP（任意）',
                    ),
                    description: _text(
                      zh: '默认关闭。需先在全局 MCP 配置安装/启用；开启后优先通过 ADB MCP 调用 adb。',
                      en: 'Off by default. Install/enable it in global MCP settings first; then adb uses ADB MCP first.',
                      zhHant: '預設關閉。需先在全域 MCP 配置安裝/啟用；開啟後優先透過 ADB MCP 呼叫 adb。',
                      fr: 'Désactivé par défaut. Installez/activez-le dans la configuration MCP globale, puis adb utilisera ADB MCP en priorité.',
                      de: 'Standardmäßig aus. Erst in den globalen MCP-Einstellungen installieren/aktivieren; danach nutzt adb zuerst ADB MCP.',
                      ja: 'デフォルトはオフです。先にグローバル MCP 設定でインストール/有効化してください。有効化後は adb で ADB MCP を優先します。',
                    ),
                    value: _adbMcpEnabled,
                    onChanged: (v) => setState(() => _adbMcpEnabled = v),
                  ),
                  const SizedBox(height: 10),
                  OpenHandAnimatedSwitchTile(
                    icon: Icons.bug_report_rounded,
                    title: _text(
                      zh: 'Frida MCP（可选）',
                      en: 'Frida MCP (optional)',
                      zhHant: 'Frida MCP（可選）',
                      fr: 'Frida MCP (facultatif)',
                      de: 'Frida MCP (optional)',
                      ja: 'Frida MCP（任意）',
                    ),
                    description: _text(
                      zh: '默认关闭。需先在全局 MCP 配置安装/启用；开启后优先通过 Frida MCP 注入脚本。',
                      en: 'Off by default. Install/enable it in global MCP settings first; then Frida injection uses Frida MCP first.',
                      zhHant: '預設關閉。需先在全域 MCP 配置安裝/啟用；開啟後優先透過 Frida MCP 注入腳本。',
                      fr: 'Désactivé par défaut. Installez/activez-le dans la configuration MCP globale, puis l’injection Frida utilisera Frida MCP en priorité.',
                      de: 'Standardmäßig aus. Erst in den globalen MCP-Einstellungen installieren/aktivieren; danach nutzt Frida-Injektion zuerst Frida MCP.',
                      ja: 'デフォルトはオフです。先にグローバル MCP 設定でインストール/有効化してください。有効化後は Frida 注入で Frida MCP を優先します。',
                    ),
                    value: _fridaMcpEnabled,
                    onChanged: (v) => setState(() => _fridaMcpEnabled = v),
                  ),
                  const SizedBox(height: 14),
                  OpenHandFormLabel(
                    _text(
                      zh: '关键字（可选，逗号分隔）',
                      en: 'Keywords (optional, comma-separated)',
                      zhHant: '關鍵字（可選，逗號分隔）',
                      fr: 'Mots-clés (facultatif, séparés par des virgules)',
                      de: 'Schlüsselwörter (optional, kommagetrennt)',
                      ja: 'キーワード（任意、カンマ区切り）',
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _keywordsCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'sign, encrypt, token',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OpenHandFormLabel(
                    _text(
                      zh: '备注（可选）',
                      en: 'Notes (optional)',
                      zhHant: '備註（可選）',
                      fr: 'Notes (facultatif)',
                      de: 'Notizen (optional)',
                      ja: 'メモ（任意）',
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _text(
                        zh: '例：账号 test@example.com，代理 127.0.0.1:8080',
                        en: 'e.g. test account, proxy 127.0.0.1:8080',
                        zhHant: '例：帳號 test@example.com，代理 127.0.0.1:8080',
                        fr: 'ex. compte de test, proxy 127.0.0.1:8080',
                        de: 'z. B. Testkonto, Proxy 127.0.0.1:8080',
                        ja: '例: テストアカウント、プロキシ 127.0.0.1:8080',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          buildOpenHandDialogActionsBar(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(context).pop(),
                label: openHandCancelLabel(context),
              ),
              OpenHandDialogActionButton.primary(
                onPressed: _canSubmit ? _submit : null,
                label: _text(
                  zh: '创建会话',
                  en: 'Create Session',
                  zhHant: '建立會話',
                  fr: 'Créer la session',
                  de: 'Sitzung erstellen',
                  ja: 'セッションを作成',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
