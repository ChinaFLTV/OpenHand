import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../app/state/settings_controller.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/model_search_selector.dart';
import '../../../shared/ui/openhand_busy_indicators.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_tap_region.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../model/harness_agent_role.dart';
import '../model/harness_role_config.dart';
import '../model/harness_session_config.dart';
import '../service/harness_cli_catalog.dart';
import 'harness_cli_install_dialog.dart';
import 'harness_cli_login_dialog.dart';

const double _kHarnessModeDropdownWidth = 132;

String _heEngineeringRoleLabel(BuildContext context, HarnessAgentRole role) {
  return switch (role) {
    HarnessAgentRole.profiler => openHandLocalizedText(
      context,
      zh: '探档者',
      zhHant: '探檔者',
      en: 'Profiler',
      fr: 'Profileur',
      de: 'Profiler',
      ja: 'プロファイラー',
    ),
    HarnessAgentRole.reader => openHandLocalizedText(
      context,
      zh: '调查者',
      zhHant: '調查者',
      en: 'Reader',
      fr: 'Lecteur',
      de: 'Leser',
      ja: 'リーダー',
    ),
    HarnessAgentRole.planner => openHandLocalizedText(
      context,
      zh: '规划者',
      zhHant: '規劃者',
      en: 'Planner',
      fr: 'Planificateur',
      de: 'Planer',
      ja: 'プランナー',
    ),
    HarnessAgentRole.implementer => openHandLocalizedText(
      context,
      zh: '实施者',
      zhHant: '實施者',
      en: 'Implementer',
      fr: 'Implémenteur',
      de: 'Umsetzer',
      ja: '実装者',
    ),
    HarnessAgentRole.reviewer => openHandLocalizedText(
      context,
      zh: '验收者',
      zhHant: '驗收者',
      en: 'Reviewer',
      fr: 'Relecteur',
      de: 'Prüfer',
      ja: 'レビュー担当',
    ),
  };
}

class HarnessEngineeringDialog extends StatefulWidget {
  const HarnessEngineeringDialog({super.key, this.settingsController});

  /// 可选的设置控制器，用于读取已配置的 AI 模型。
  final SettingsController? settingsController;

  @override
  State<HarnessEngineeringDialog> createState() =>
      _HarnessEngineeringDialogState();
}

class _HarnessEngineeringDialogState extends State<HarnessEngineeringDialog> {
  final TextEditingController _taskController = TextEditingController();
  final TextEditingController _workingDirController = TextEditingController();
  final TextEditingController _persistenceDirController =
      TextEditingController();
  String? _lastSuggestedPersistenceDir;

  final Map<HarnessAgentRole, String?> _selectedCli = {};
  final Map<HarnessAgentRole, String?> _selectedModel = {};
  final Map<HarnessAgentRole, HarnessExecutionMode> _executionMode = {};
  final Map<HarnessAgentRole, String?> _selectedAiModelConfigId = {};
  final Map<HarnessAgentRole, String?> _selectedUrlModeModelId = {};

  HarnessExecutionMode _quickExecutionMode = HarnessExecutionMode.cli;
  String? _quickCli;
  String? _quickModel;
  String? _quickAiModelConfigId;
  String? _quickUrlModeModelId;

  List<CliScanEntry> _scanResults = [];
  bool _isScanning = true;
  bool _isCheckingAuth = false;
  int _scanRequestId = 0;
  final ValueNotifier<int> _logoutSuccessSignal = ValueNotifier<int>(0);
  final ValueNotifier<int> _logoutErrorSignal = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _taskController.addListener(_onFormChanged);
    _workingDirController.addListener(_onFormChanged);
    _persistenceDirController.addListener(_onFormChanged);
    _scanClis();
  }

  @override
  void dispose() {
    _taskController.dispose();
    _workingDirController.dispose();
    _persistenceDirController.dispose();
    _logoutSuccessSignal.dispose();
    _logoutErrorSignal.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  Future<void> _scanClis() async {
    final requestId = ++_scanRequestId;
    setState(() {
      _isScanning = true;
      _isCheckingAuth = false;
    });

    // 第一阶段：限并发探测 CLI 安装状态。
    final results = await scanInstalledClis();
    if (!mounted || requestId != _scanRequestId) return;
    final hasCheckable = results.any((e) => e.installed && e.cli.hasLoginCheck);
    setState(() {
      _scanResults = results;
      _isScanning = false;
      _isCheckingAuth = hasCheckable;
    });

    if (!hasCheckable) return;

    // 第二阶段：限并发探测已安装 CLI 的认证状态。
    final authResults = await probeCliAuthBatch(results);
    if (!mounted || requestId != _scanRequestId) return;
    setState(() {
      _scanResults = [
        for (int i = 0; i < results.length; i++)
          (
            cli: results[i].cli,
            installed: results[i].installed,
            resolvedPath: results[i].resolvedPath,
            isLoggedIn: authResults[i],
          ),
      ];
      _isCheckingAuth = false;
    });
  }

  bool get _isValid =>
      _taskController.text.trim().isNotEmpty &&
      _taskController.text.trim().length <= kHarnessTaskMaxCharacters &&
      _workingDirController.text.trim().isNotEmpty &&
      _persistenceDirController.text.trim().isNotEmpty;

  String _defaultPersistenceDirectoryFor(String workingDirectory) {
    final trimmedWorkingDirectory = workingDirectory.trim();
    if (trimmedWorkingDirectory.isEmpty) {
      return '';
    }
    return p.join(trimmedWorkingDirectory, 'harness');
  }

  void _applyWorkingDirectorySelection(String workingDirectory) {
    final trimmedWorkingDirectory = workingDirectory.trim();
    final previousSuggestedPersistenceDir = _lastSuggestedPersistenceDir;
    _workingDirController.text = trimmedWorkingDirectory;

    if (trimmedWorkingDirectory.isEmpty) {
      _lastSuggestedPersistenceDir = null;
      return;
    }

    final nextSuggestedPersistenceDir = _defaultPersistenceDirectoryFor(
      trimmedWorkingDirectory,
    );
    final currentPersistenceDir = _persistenceDirController.text.trim();
    final shouldAutofillPersistenceDir =
        currentPersistenceDir.isEmpty ||
        (previousSuggestedPersistenceDir != null &&
            currentPersistenceDir == previousSuggestedPersistenceDir);

    if (shouldAutofillPersistenceDir) {
      _persistenceDirController.text = nextSuggestedPersistenceDir;
    }
    _lastSuggestedPersistenceDir = nextSuggestedPersistenceDir;
  }

  Future<void> _pickDirectory(TextEditingController controller) async {
    final current = controller.text.trim();
    final result = await getDirectoryPath(
      initialDirectory: current.isNotEmpty ? current : null,
    );
    if (result != null && mounted) {
      if (identical(controller, _workingDirController)) {
        _applyWorkingDirectorySelection(result);
        return;
      }
      controller.text = result;
    }
  }

  List<String> _modelsForCli(String? cliName) {
    if (cliName == null) return const [];
    return _scanResults
            .where((r) => r.cli.name == cliName)
            .firstOrNull
            ?.cli
            .knownModels ??
        const [];
  }

  String? _preferredModelForCli(String? cliName, {String? currentModel}) {
    if (cliName == null) {
      return null;
    }
    final trimmedCurrentModel = currentModel?.trim();
    return trimmedCurrentModel == null || trimmedCurrentModel.isEmpty
        ? null
        : trimmedCurrentModel;
  }

  HarnessRoleConfig _roleConfig(HarnessAgentRole role) {
    final mode = _executionMode[role] ?? HarnessExecutionMode.cli;
    if (mode == HarnessExecutionMode.url) {
      return HarnessRoleConfig(
        cliName: '',
        modelId: '',
        executionMode: HarnessExecutionMode.url,
        aiModelConfigId: _selectedAiModelConfigId[role],
        urlModeModelId: _selectedUrlModeModelId[role],
      );
    }
    return HarnessRoleConfig(
      cliName: _selectedCli[role] ?? '',
      modelId: (_selectedModel[role] ?? '').trim(),
    );
  }

  List<String> _configurationIssues(BuildContext context) {
    final issues = <String>[];
    final settingsModels = widget.settingsController?.aiModels ?? const [];
    for (final role in HarnessAgentRole.values) {
      final roleLabel = _heEngineeringRoleLabel(context, role);
      final roleConfig = _roleConfig(role);

      if (roleConfig.isUrlMode) {
        final configId = roleConfig.aiModelConfigId;
        if (configId == null || configId.trim().isEmpty) {
          issues.add(
            openHandLocalizedText(
              context,
              zh: '$roleLabel：请选择 API 模型提供商。',
              zhHant: '$roleLabel：請選擇 API 模型提供者。',
              en: '$roleLabel: choose an API model provider.',
              fr: '$roleLabel : choisissez un fournisseur de modèle API.',
              de: '$roleLabel: API-Modellanbieter auswählen.',
              ja: '$roleLabel: API モデルプロバイダーを選択してください。',
            ),
          );
          continue;
        }
        final provider = settingsModels
            .where((m) => m.id == configId)
            .firstOrNull;
        if (provider == null) {
          issues.add(
            openHandLocalizedText(
              context,
              zh: '$roleLabel：所选 API 模型提供商不存在，请重新选择。',
              zhHant: '$roleLabel：所選 API 模型提供者不存在，請重新選擇。',
              en: '$roleLabel: the selected API model provider no longer exists.',
              fr: '$roleLabel : le fournisseur de modèle API sélectionné n’existe plus.',
              de: '$roleLabel: Der ausgewählte API-Modellanbieter existiert nicht mehr.',
              ja: '$roleLabel: 選択した API モデルプロバイダーは存在しません。',
            ),
          );
          continue;
        }
        final urlModelId = roleConfig.urlModeModelId?.trim();
        if (urlModelId != null &&
            urlModelId.isNotEmpty &&
            !provider.allModelIds.contains(urlModelId)) {
          issues.add(
            openHandLocalizedText(
              context,
              zh: '$roleLabel：所选模型 "$urlModelId" 在该提供商中不存在。',
              zhHant: '$roleLabel：所選模型 "$urlModelId" 在該提供者中不存在。',
              en: '$roleLabel: model "$urlModelId" not found in this provider.',
              fr: '$roleLabel : modèle "$urlModelId" introuvable chez ce fournisseur.',
              de: '$roleLabel: Modell "$urlModelId" wurde bei diesem Anbieter nicht gefunden.',
              ja: '$roleLabel: モデル "$urlModelId" はこのプロバイダーにありません。',
            ),
          );
        }
        continue;
      }

      final cliName = roleConfig.cliName.trim();
      final modelId = roleConfig.modelId.trim();

      if (cliName.isEmpty) {
        issues.add(
          openHandLocalizedText(
            context,
            zh: '$roleLabel：请选择 CLI。',
            zhHant: '$roleLabel：請選擇 CLI。',
            en: '$roleLabel: choose a CLI.',
            fr: '$roleLabel : choisissez un CLI.',
            de: '$roleLabel: CLI auswählen.',
            ja: '$roleLabel: CLI を選択してください。',
          ),
        );
        continue;
      }

      final entry = _entryForCli(cliName);
      if (entry == null) {
        issues.add(
          openHandLocalizedText(
            context,
            zh: '$roleLabel：无法识别所选 CLI，请重新选择。',
            zhHant: '$roleLabel：無法識別所選 CLI，請重新選擇。',
            en: '$roleLabel: the selected CLI is no longer available. Re-select it.',
            fr: '$roleLabel : le CLI sélectionné n’est plus disponible. Sélectionnez-le à nouveau.',
            de: '$roleLabel: Die ausgewählte CLI ist nicht mehr verfügbar. Bitte erneut auswählen.',
            ja: '$roleLabel: 選択した CLI は利用できません。再選択してください。',
          ),
        );
        continue;
      }

      if (!entry.installed) {
        issues.add(
          openHandLocalizedText(
            context,
            zh: '$roleLabel：所选 CLI 尚未安装。',
            zhHant: '$roleLabel：所選 CLI 尚未安裝。',
            en: '$roleLabel: the selected CLI is not installed.',
            fr: '$roleLabel : le CLI sélectionné n’est pas installé.',
            de: '$roleLabel: Die ausgewählte CLI ist nicht installiert.',
            ja: '$roleLabel: 選択した CLI はインストールされていません。',
          ),
        );
        continue;
      }

      if (modelId.isEmpty) {
        issues.add(
          openHandLocalizedText(
            context,
            zh: '$roleLabel：请选择模型。',
            zhHant: '$roleLabel：請選擇模型。',
            en: '$roleLabel: choose a model.',
            fr: '$roleLabel : choisissez un modèle.',
            de: '$roleLabel: Modell auswählen.',
            ja: '$roleLabel: モデルを選択してください。',
          ),
        );
        continue;
      }
    }
    return issues;
  }

  List<String> _geminiAccessAdvisories(BuildContext context) {
    final geminiRoleLabels = <String>[];
    var hasLoggedInGemini = false;
    var hasPinnedGeminiModel = false;

    for (final role in HarnessAgentRole.values) {
      final roleLabel = _heEngineeringRoleLabel(context, role);
      final roleConfig = _roleConfig(role);

      // URL 模式不调用 Gemini CLI。
      if (roleConfig.isUrlMode) continue;

      final cliName = roleConfig.cliName.trim();
      final modelId = roleConfig.modelId.trim();

      if (cliName.isEmpty || modelId.isEmpty) {
        continue;
      }

      final entry = _entryForCli(cliName);
      if (entry == null ||
          !entry.installed ||
          entry.cli.executable != 'gemini') {
        continue;
      }

      geminiRoleLabels.add(roleLabel);
      hasLoggedInGemini = hasLoggedInGemini || entry.isLoggedIn == true;
      hasPinnedGeminiModel =
          hasPinnedGeminiModel || !isHarnessCliDefaultModel(entry.cli, modelId);
    }

    if (geminiRoleLabels.isEmpty) {
      return const [];
    }

    final roleSummary = geminiRoleLabels.join(
      openHandIsChineseLocale(context) ? '、' : ', ',
    );
    final defaultModelLabel = describeHarnessCliModel(
      kHarnessGeminiDefaultModelId,
      locale: Localizations.localeOf(context),
    );
    final flashModelLabel = describeHarnessCliModel(
      'gemini-2.5-flash',
      locale: Localizations.localeOf(context),
    );

    return [
      openHandLocalizedText(
        context,
        zh: '当前使用 Gemini 的角色：$roleSummary。OpenHand 不会在 setup 阶段预判 Gemini 模型是否受支持，实际可用性以 CLI 运行结果为准。',
        zhHant:
            '目前使用 Gemini 的角色：$roleSummary。OpenHand 不會在 setup 階段預判 Gemini 模型是否受支援，實際可用性以 CLI 執行結果為準。',
        en: 'Roles using Gemini: $roleSummary. OpenHand does not pre-judge Gemini model support during setup; real CLI/runtime results decide availability.',
        fr: 'Rôles utilisant Gemini : $roleSummary. OpenHand ne préjuge pas la prise en charge du modèle pendant la configuration ; le résultat CLI réel fait foi.',
        de: 'Rollen mit Gemini: $roleSummary. OpenHand bewertet Modellunterstützung im Setup nicht vorab; entscheidend ist das echte CLI-Ergebnis.',
        ja: 'Gemini を使うロール：$roleSummary。OpenHand は setup 時に Gemini モデル対応を事前判定しません。実際の CLI 実行結果が基準です。',
      ),
      hasLoggedInGemini
          ? openHandLocalizedText(
              context,
              zh: '即使显示已登录，免费版或受限账号运行部分 Pro / Preview 模型时仍可能无权限或找不到模型。',
              zhHant: '即使顯示已登入，免費版或受限帳號執行部分 Pro / Preview 模型時仍可能無權限或找不到模型。',
              en: 'Even when logged in, free-tier or restricted accounts may still hit permission or model-not-found errors for some Pro / Preview models.',
              fr: 'Même connecté, un compte gratuit ou restreint peut rencontrer des erreurs de permission ou modèle introuvable sur certains modèles Pro / Preview.',
              de: 'Auch angemeldet können kostenlose oder eingeschränkte Konten bei einigen Pro-/Preview-Modellen Berechtigungs- oder Model-not-found-Fehler erhalten.',
              ja: 'ログイン済みでも、無料または制限付きアカウントでは一部 Pro / Preview モデルで権限不足や model not found が起きる場合があります。',
            )
          : openHandLocalizedText(
              context,
              zh: 'Setup 阶段只能校验模型 ID 和登录状态，无法预先确认后续 Google 账号是否具备模型权限。',
              zhHant: 'Setup 階段只能校驗模型 ID 和登入狀態，無法預先確認後續 Google 帳號是否具備模型權限。',
              en: 'During setup, OpenHand can only validate model ID and login state; it cannot pre-verify Google account entitlement.',
              fr: 'Pendant la configuration, OpenHand vérifie seulement l’ID du modèle et l’état de connexion ; il ne peut pas confirmer les droits du compte Google.',
              de: 'Im Setup prüft OpenHand nur Modell-ID und Loginstatus; Google-Kontoberechtigungen kann es nicht vorab bestätigen.',
              ja: 'Setup 時に確認できるのはモデル ID とログイン状態だけで、Google アカウントの権限は事前確認できません。',
            ),
      hasPinnedGeminiModel
          ? openHandLocalizedText(
              context,
              zh: '如果不确定额度或权限，优先改用 $defaultModelLabel 或 $flashModelLabel；运行后失败可在 dashboard 改模型并从失败阶段重试。',
              zhHant:
                  '如果不確定額度或權限，優先改用 $defaultModelLabel 或 $flashModelLabel；執行後失敗可在 dashboard 改模型並從失敗階段重試。',
              en: 'If quota or entitlement is uncertain, prefer $defaultModelLabel or $flashModelLabel. If runtime fails, change the model in the dashboard and retry the failed phase.',
              fr: 'Si les quotas ou droits sont incertains, préférez $defaultModelLabel ou $flashModelLabel. En cas d’échec, changez le modèle dans le dashboard et réessayez la phase.',
              de: 'Bei unklaren Quoten oder Rechten nutze bevorzugt $defaultModelLabel oder $flashModelLabel. Bei Laufzeitfehlern Modell im Dashboard ändern und Phase erneut versuchen.',
              ja: '割り当てや権限が不明な場合は $defaultModelLabel または $flashModelLabel を優先してください。失敗時は dashboard でモデルを変えて失敗フェーズを再試行できます。',
            )
          : openHandLocalizedText(
              context,
              zh: '即使使用 $defaultModelLabel，也仍受当前账号权限影响；运行后失败可在 dashboard 改模型并从失败阶段重试。',
              zhHant:
                  '即使使用 $defaultModelLabel，也仍受目前帳號權限影響；執行後失敗可在 dashboard 改模型並從失敗階段重試。',
              en: 'Even with $defaultModelLabel, access depends on the current account. If execution fails, change the model in the dashboard and retry the failed phase.',
              fr: 'Même avec $defaultModelLabel, l’accès dépend du compte actuel. En cas d’échec, changez le modèle dans le dashboard et réessayez la phase.',
              de: 'Auch mit $defaultModelLabel hängt der Zugriff vom aktuellen Konto ab. Bei Fehlern Modell im Dashboard ändern und Phase erneut versuchen.',
              ja: '$defaultModelLabel でもアクセス権は現在のアカウント次第です。失敗時は dashboard でモデルを変えて失敗フェーズを再試行できます。',
            ),
    ];
  }

  CliScanEntry? _entryForCli(String? name) => name == null
      ? null
      : _scanResults.where((r) => r.cli.name == name).firstOrNull;

  Future<void> _showInstallDialog(HarnessCli cli) async {
    final result = await showAnimatedDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => HarnessCliInstallDialog(cli: cli),
    );
    if (result == true && mounted) {
      await _scanClis();
    }
  }

  Future<void> _openDocUrl(String url) async {
    final normalizedUrl = url.trim();
    final parsedUrl = Uri.tryParse(normalizedUrl);
    final canOpenExternally =
        parsedUrl != null &&
        parsedUrl.hasScheme &&
        (parsedUrl.scheme == 'https' || parsedUrl.scheme == 'http');
    final copiedMessage = openHandLocalizedText(
      context,
      zh: '链接已复制到剪贴板',
      zhHant: '連結已複製到剪貼簿',
      en: 'Link copied to clipboard',
      fr: 'Lien copié dans le presse-papiers',
      de: 'Link in die Zwischenablage kopiert',
      ja: 'リンクをクリップボードにコピーしました',
    );
    if (!canOpenExternally) {
      await copyOpenHandTextToClipboard(
        logTag: 'harness',
        context: context,
        text: normalizedUrl,
        successMessage: copiedMessage,
        logAction: '复制无效文档地址',
      );
      return;
    }

    try {
      final launched = await openHttpUrlWithSystemBrowser(
        normalizedUrl,
        tag: 'harness_engineering.open_url',
      );
      if (!launched) {
        if (!mounted) return;
        await copyOpenHandTextToClipboard(
          logTag: 'harness',
          context: context,
          text: normalizedUrl,
          successMessage: copiedMessage,
          logAction: '复制未打开的文档地址',
        );
      }
    } catch (error, stack) {
      silentLog('harness_engineering', '打开文档链接', error, stack);
      if (!mounted) return;
      await copyOpenHandTextToClipboard(
        logTag: 'harness',
        context: context,
        text: normalizedUrl,
        successMessage: copiedMessage,
        logAction: '打开失败后复制文档地址',
      );
    }
  }

  Future<void> _launchCliLogin(CliScanEntry entry) async {
    final cli = entry.cli;
    if (!cli.hasLoginTrigger) return;

    await showAnimatedDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => HarnessCliLoginDialog(entry: entry),
    );

    if (mounted) {
      await _scanClis();
    }
  }

  Future<void> _launchCliLogout(CliScanEntry entry) async {
    final cli = entry.cli;
    if (!cli.hasLogoutTrigger) return;

    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '确认登出',
        zhHant: '確認登出',
        en: 'Confirm Logout',
        fr: 'Confirmer la déconnexion',
        de: 'Logout bestätigen',
        ja: 'ログアウトを確認',
      ),
      message: openHandLocalizedText(
        context,
        zh: '确定要登出 ${cli.name} 吗？登出后需要重新登录才能使用该 CLI。',
        zhHant: '確定要登出 ${cli.name} 嗎？登出後需要重新登入才能使用該 CLI。',
        en: 'Are you sure you want to log out of ${cli.name}? You will need to log in again to use this CLI.',
        fr: 'Voulez-vous vous déconnecter de ${cli.name} ? Une reconnexion sera nécessaire pour utiliser ce CLI.',
        de: 'Von ${cli.name} abmelden? Danach musst du dich erneut anmelden, um diese CLI zu nutzen.',
        ja: '${cli.name} からログアウトしますか？この CLI を使うには再ログインが必要です。',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandLocalizedText(
        context,
        zh: '登出',
        zhHant: '登出',
        en: 'Logout',
        fr: 'Se déconnecter',
        de: 'Abmelden',
        ja: 'ログアウト',
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isCheckingAuth = true);

    final result = await performCliLogout(entry);

    if (!mounted) return;

    final strippedMessage = stripHarnessCliTerminalSequences(result.message);
    final snackMessage = result.success
        ? openHandLocalizedText(
            context,
            zh: '${cli.name} 已登出。$strippedMessage',
            zhHant: '${cli.name} 已登出。$strippedMessage',
            en: '${cli.name} logged out. $strippedMessage',
            fr: '${cli.name} déconnecté. $strippedMessage',
            de: '${cli.name} abgemeldet. $strippedMessage',
            ja: '${cli.name} からログアウトしました。$strippedMessage',
          )
        : openHandLocalizedText(
            context,
            zh: '${cli.name} 登出失败：$strippedMessage',
            zhHant: '${cli.name} 登出失敗：$strippedMessage',
            en: '${cli.name} logout failed: $strippedMessage',
            fr: 'Échec de la déconnexion de ${cli.name} : $strippedMessage',
            de: '${cli.name} Abmeldung fehlgeschlagen: $strippedMessage',
            ja: '${cli.name} のログアウトに失敗しました：$strippedMessage',
          );
    if (result.success) {
      showOpenHandSuccessSnack(context, snackMessage);
      _logoutSuccessSignal.value++;
    } else {
      showOpenHandErrorSnack(context, snackMessage);
      _logoutErrorSignal.value++;
    }

    await _scanClis();
  }

  void _submit() {
    Navigator.of(context).pop(
      HarnessSessionConfig(
        task: _taskController.text.trim(),
        workingDirectory: _workingDirController.text.trim(),
        persistenceDirectory: _persistenceDirController.text.trim(),
        profilerConfig: _roleConfig(HarnessAgentRole.profiler),
        readerConfig: _roleConfig(HarnessAgentRole.reader),
        plannerConfig: _roleConfig(HarnessAgentRole.planner),
        implementerConfig: _roleConfig(HarnessAgentRole.implementer),
        reviewerConfig: _roleConfig(HarnessAgentRole.reviewer),
      ),
    );
  }

  void _applyQuickConfig() {
    setState(() {
      if (_quickExecutionMode == HarnessExecutionMode.url) {
        if (_quickAiModelConfigId == null) return;
        for (final role in HarnessAgentRole.values) {
          _executionMode[role] = HarnessExecutionMode.url;
          _selectedAiModelConfigId[role] = _quickAiModelConfigId;
          _selectedUrlModeModelId[role] = _quickUrlModeModelId;
        }
      } else {
        if (_quickCli == null) return;
        final preferredModel = _preferredModelForCli(
          _quickCli,
          currentModel: _quickModel,
        );
        for (final role in HarnessAgentRole.values) {
          _executionMode[role] = HarnessExecutionMode.cli;
          _selectedCli[role] = _quickCli;
          _selectedModel[role] = preferredModel;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final configurationIssues = _configurationIssues(context);
    final geminiAccessAdvisories = _geminiAccessAdvisories(context);
    final canSubmit = _isValid && !_isScanning && configurationIssues.isEmpty;
    final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.9;

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: maxDialogHeight,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  openHandLocalizedText(
                    context,
                    zh: 'Harness Engineering 配置',
                    zhHant: 'Harness Engineering 設定',
                    en: 'Harness Engineering Setup',
                    fr: 'Configuration Harness Engineering',
                    de: 'Harness Engineering einrichten',
                    ja: 'Harness Engineering 設定',
                  ),
                  style: theme.textTheme.headlineSmall,
                ),
                kOpenHandGap20,
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          openHandLocalizedText(
                            context,
                            zh: 'OpenHand 将作为编排协调层。每个角色可使用 CLI 模式（委托给外部 CLI 工具）或 URL 模式（使用设置中的 API 模型）。',
                            zhHant:
                                'OpenHand 將作為編排協調層。每個角色可使用 CLI 模式（委託外部 CLI 工具）或 URL 模式（使用設定中的 API 模型）。',
                            en: 'OpenHand acts as orchestrator. Each role can use CLI mode for external CLI tools or URL mode for configured API models.',
                            fr: 'OpenHand orchestre le flux. Chaque rôle peut utiliser le mode CLI ou le mode URL avec les modèles API configurés.',
                            de: 'OpenHand orchestriert den Ablauf. Jede Rolle kann CLI-Modus oder URL-Modus mit konfigurierten API-Modellen nutzen.',
                            ja: 'OpenHand がオーケストレーターとして動作します。各ロールは外部 CLI の CLI モード、または設定済み API モデルの URL モードを使用できます。',
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        kOpenHandGap24,

                        TextField(
                          controller: _taskController,
                          autofocus: true,
                          maxLines: 5,
                          minLines: 3,
                          inputFormatters: <TextInputFormatter>[
                            LengthLimitingTextInputFormatter(
                              kHarnessTaskMaxCharacters,
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: openHandLocalizedText(
                              context,
                              zh: '任务 / 需求',
                              zhHant: '任務 / 需求',
                              en: 'Task / Requirement',
                              fr: 'Tâche / besoin',
                              de: 'Aufgabe / Anforderung',
                              ja: 'タスク / 要件',
                            ),
                            hintText: openHandLocalizedText(
                              context,
                              zh: '描述你的开发任务或需求...',
                              zhHant: '描述你的開發任務或需求...',
                              en: 'Describe your development task or requirement...',
                              fr: 'Décrivez votre tâche ou besoin de développement...',
                              de: 'Beschreibe deine Entwicklungsaufgabe oder Anforderung...',
                              ja: '開発タスクまたは要件を説明してください...',
                            ),
                            alignLabelWithHint: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        kOpenHandGap20,

                        OpenHandDirectoryField(
                          controller: _workingDirController,
                          label: openHandLocalizedText(
                            context,
                            zh: '工作目录（项目根目录）',
                            zhHant: '工作目錄（專案根目錄）',
                            en: 'Working Directory',
                            fr: 'Répertoire de travail',
                            de: 'Arbeitsverzeichnis',
                            ja: '作業ディレクトリ',
                          ),
                          hintText: openHandLocalizedText(
                            context,
                            zh: '输入或选择项目根目录路径',
                            zhHant: '輸入或選擇專案根目錄路徑',
                            en: 'Enter or browse project root path',
                            fr: 'Saisir ou choisir le chemin racine du projet',
                            de: 'Projektwurzel eingeben oder auswählen',
                            ja: 'プロジェクトルートのパスを入力または選択',
                          ),
                          browseTooltip: _harnessEngineeBrowseFolderLabel(
                            context,
                          ),
                          onBrowse: () => _pickDirectory(_workingDirController),
                          crossAxisAlignment: CrossAxisAlignment.center,
                        ),
                        kOpenHandGap14,

                        OpenHandDirectoryField(
                          controller: _persistenceDirController,
                          label: openHandLocalizedText(
                            context,
                            zh: '持久化根目录（steering 数据目录）',
                            zhHant: '持久化根目錄（steering 資料目錄）',
                            en: 'Persistence Root (steering dir)',
                            fr: 'Racine persistante (dossier steering)',
                            de: 'Persistenzwurzel (steering-Verzeichnis)',
                            ja: '永続化ルート（steering データディレクトリ）',
                          ),
                          hintText: openHandLocalizedText(
                            context,
                            zh: '输入或选择持久化根目录路径',
                            zhHant: '輸入或選擇持久化根目錄路徑',
                            en: 'Enter or browse persistence root path',
                            fr: 'Saisir ou choisir le chemin de persistance',
                            de: 'Persistenzpfad eingeben oder auswählen',
                            ja: '永続化ルートのパスを入力または選択',
                          ),
                          browseTooltip: _harnessEngineeBrowseFolderLabel(
                            context,
                          ),
                          onBrowse: () =>
                              _pickDirectory(_persistenceDirController),
                          crossAxisAlignment: CrossAxisAlignment.center,
                        ),
                        const SizedBox(height: 28),

                        Row(
                          children: [
                            Text(
                              openHandLocalizedText(
                                context,
                                zh: '角色配置',
                                zhHant: '角色設定',
                                en: 'Role Configuration',
                                fr: 'Configuration des rôles',
                                de: 'Rollenkonfiguration',
                                ja: 'ロール設定',
                              ),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            // 忙碌时保留按钮本体、只把图标换成转圈：此前是把
                            // 整个 IconButton 换成一个 14px 转圈，忙碌一开始
                            // 这一行就塌陷一次。
                            IconButton(
                              onPressed: _isScanning || _isCheckingAuth
                                  ? null
                                  : _scanClis,
                              icon: OpenHandBusyStatusIcon(
                                busy: _isScanning || _isCheckingAuth,
                                icon: Icons.refresh_rounded,
                              ),
                              tooltip: openHandLocalizedText(
                                context,
                                zh: '重新扫描 CLI',
                                zhHant: '重新掃描 CLI',
                                en: 'Re-scan CLIs',
                                fr: 'Relancer le scan des CLI',
                                de: 'CLIs erneut scannen',
                                ja: 'CLI を再スキャン',
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                        kOpenHandGap4,
                        Text(
                          openHandLocalizedText(
                            context,
                            zh: '为每个角色选择执行模式（CLI 或 URL）并指定模型。● 已安装，○ 未安装，✓ 已登录，✗ 未登录。',
                            zhHant:
                                '為每個角色選擇執行模式（CLI 或 URL）並指定模型。● 已安裝，○ 未安裝，✓ 已登入，✗ 未登入。',
                            en: 'Choose execution mode (CLI or URL) and model for each role. ● installed, ○ not installed, ✓ logged in, ✗ not logged in.',
                            fr: 'Choisissez le mode (CLI ou URL) et le modèle pour chaque rôle. ● installé, ○ non installé, ✓ connecté, ✗ déconnecté.',
                            de: 'Wähle Modus (CLI oder URL) und Modell je Rolle. ● installiert, ○ nicht installiert, ✓ angemeldet, ✗ nicht angemeldet.',
                            ja: '各ロールの実行モード（CLI または URL）とモデルを選択してください。● インストール済み、○ 未インストール、✓ ログイン済み、✗ 未ログイン。',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        kOpenHandGap16,

                        if (!_isScanning) ...[
                          _CliScanSummary(
                            scanResults: _scanResults,
                            isCheckingAuth: _isCheckingAuth,
                          ),
                          kOpenHandGap12,
                        ],

                        _QuickApplyBar(
                          scanResults: _scanResults,
                          isScanning: _isScanning,
                          isCheckingAuth: _isCheckingAuth,
                          executionMode: _quickExecutionMode,
                          selectedCli: _quickCli,
                          selectedModel: _quickModel,
                          settingsModels:
                              widget.settingsController?.aiModels ?? const [],
                          selectedAiModelConfigId: _quickAiModelConfigId,
                          selectedUrlModeModelId: _quickUrlModeModelId,
                          onExecutionModeChanged: (v) => setState(() {
                            _quickExecutionMode = v ?? HarnessExecutionMode.cli;
                          }),
                          onCliChanged: (v) => setState(() {
                            _quickCli = v;
                            _quickModel = _preferredModelForCli(
                              v,
                              currentModel: _quickModel,
                            );
                          }),
                          onModelChanged: (v) =>
                              setState(() => _quickModel = v),
                          onAiModelConfigChanged: (configId, modelId) =>
                              setState(() {
                                _quickAiModelConfigId = configId;
                                _quickUrlModeModelId = modelId;
                              }),
                          onApply: _applyQuickConfig,
                          modelsForCli: _modelsForCli,
                        ),
                        kOpenHandGap12,

                        if (_isScanning && _scanResults.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                  kOpenHandGap12,
                                  Text(
                                    openHandLocalizedText(
                                      context,
                                      zh: '扫描已安装的 CLI...',
                                      zhHant: '掃描已安裝的 CLI...',
                                      en: 'Scanning installed CLIs...',
                                      fr: 'Analyse des CLI installés...',
                                      de: 'Installierte CLIs werden gescannt...',
                                      ja: 'インストール済み CLI をスキャン中...',
                                    ),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ...HarnessAgentRole.values.map((role) {
                            final selectedCliName = _selectedCli[role];
                            final entry = _entryForCli(selectedCliName);
                            final cli = entry?.cli;
                            final notInstalled =
                                selectedCliName != null &&
                                !(entry?.installed ?? true);
                            final showInstall =
                                notInstalled &&
                                (cli?.isAutoInstallable ?? false);
                            final showViewDocs =
                                notInstalled &&
                                !(cli?.isAutoInstallable ?? false) &&
                                (cli?.installDocUrl?.isNotEmpty ?? false);
                            final showLogin =
                                selectedCliName != null &&
                                (entry?.installed ?? false) &&
                                entry?.isLoggedIn == false &&
                                (cli?.hasLoginTrigger ?? false);
                            final showLogout =
                                selectedCliName != null &&
                                (entry?.installed ?? false) &&
                                entry?.isLoggedIn == true &&
                                (cli?.hasLogoutTrigger ?? false);
                            final executionMode =
                                _executionMode[role] ??
                                HarnessExecutionMode.cli;
                            return _RoleConfigRow(
                              key: ValueKey(role),
                              role: role,
                              scanResults: _scanResults,
                              executionMode: executionMode,
                              selectedCli: selectedCliName,
                              availableModels: _modelsForCli(selectedCliName),
                              selectedModel: _selectedModel[role],
                              settingsModels:
                                  widget.settingsController?.aiModels ??
                                  const [],
                              selectedAiModelConfigId:
                                  _selectedAiModelConfigId[role],
                              selectedUrlModeModelId:
                                  _selectedUrlModeModelId[role],
                              showInstallButton: showInstall,
                              showViewDocsButton: showViewDocs,
                              showLoginButton: showLogin,
                              showLogoutButton: showLogout,
                              isCheckingAuth: _isCheckingAuth,
                              onExecutionModeChanged: (v) => setState(() {
                                _executionMode[role] =
                                    v ?? HarnessExecutionMode.cli;
                              }),
                              onCliChanged: (v) => setState(() {
                                _selectedCli[role] = v;
                                _selectedModel[role] = _preferredModelForCli(
                                  v,
                                  currentModel: _selectedModel[role],
                                );
                              }),
                              onModelChanged: (v) => setState(() {
                                _selectedModel[role] = v;
                              }),
                              onAiModelConfigChanged: (configId, modelId) =>
                                  setState(() {
                                    _selectedAiModelConfigId[role] = configId;
                                    _selectedUrlModeModelId[role] = modelId;
                                  }),
                              onInstall: cli != null
                                  ? () => _showInstallDialog(cli)
                                  : null,
                              onViewDocs: (cli?.installDocUrl != null)
                                  ? () => _openDocUrl(cli!.installDocUrl!)
                                  : null,
                              onLogin:
                                  (entry != null &&
                                      (cli?.hasLoginTrigger ?? false))
                                  ? () => _launchCliLogin(entry)
                                  : null,
                              onLogout:
                                  (entry != null &&
                                      (cli?.hasLogoutTrigger ?? false))
                                  ? () => _launchCliLogout(entry)
                                  : null,
                            );
                          }),

                        if (!_isScanning && configurationIssues.isNotEmpty) ...[
                          kOpenHandGap4,
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer.withValues(
                                alpha: 0.16,
                              ),
                              borderRadius: BorderRadius.circular(
                                kOpenHandRadius10,
                              ),
                              border: Border.all(
                                color: colorScheme.error.withValues(
                                  alpha: 0.24,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        size: 16,
                                        color: colorScheme.error,
                                      ),
                                      kOpenHandHGap8,
                                      Expanded(
                                        child: Text(
                                          openHandLocalizedText(
                                            context,
                                            zh: '开始前请先修正以下配置问题',
                                            zhHant: '開始前請先修正以下設定問題',
                                            en: 'Resolve these configuration issues before starting',
                                            fr: 'Corrigez ces problèmes avant de démarrer',
                                            de: 'Behebe diese Konfigurationsprobleme vor dem Start',
                                            ja: '開始前に以下の設定問題を修正してください',
                                          ),
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                                color: colorScheme.error,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  kOpenHandGap8,
                                  for (final issue in configurationIssues.take(
                                    4,
                                  ))
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '• $issue',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: colorScheme.onSurface,
                                              height: 1.4,
                                            ),
                                      ),
                                    ),
                                  if (configurationIssues.length > 4)
                                    Text(
                                      openHandLocalizedText(
                                        context,
                                        zh: '还有 ${configurationIssues.length - 4} 项待处理。',
                                        zhHant:
                                            '還有 ${configurationIssues.length - 4} 項待處理。',
                                        en: '${configurationIssues.length - 4} more issue(s) need attention.',
                                        fr: '${configurationIssues.length - 4} autre(s) problème(s) à traiter.',
                                        de: '${configurationIssues.length - 4} weitere Punkte benötigen Aufmerksamkeit.',
                                        ja: 'あと ${configurationIssues.length - 4} 件の対応が必要です。',
                                      ),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        if (!_isScanning &&
                            geminiAccessAdvisories.isNotEmpty) ...[
                          kOpenHandGap12,
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer.withValues(
                                alpha: 0.28,
                              ),
                              borderRadius: BorderRadius.circular(
                                kOpenHandRadius10,
                              ),
                              border: Border.all(
                                color: colorScheme.secondary.withValues(
                                  alpha: 0.22,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 16,
                                        color: colorScheme.secondary,
                                      ),
                                      kOpenHandHGap8,
                                      Expanded(
                                        child: Text(
                                          openHandLocalizedText(
                                            context,
                                            zh: 'Gemini 模型访问说明',
                                            zhHant: 'Gemini 模型存取說明',
                                            en: 'Gemini model access note',
                                            fr: 'Note d’accès aux modèles Gemini',
                                            de: 'Hinweis zum Gemini-Modellzugriff',
                                            ja: 'Gemini モデルアクセスの注意',
                                          ),
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                                color: colorScheme.secondary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  kOpenHandGap8,
                                  for (final advisory in geminiAccessAdvisories)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '• $advisory',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: colorScheme.onSurface,
                                              height: 1.4,
                                            ),
                                      ),
                                    ),
                                  kOpenHandGap4,
                                  TextButton.icon(
                                    onPressed: () =>
                                        _openDocUrl(kHarnessGeminiModelsDocUrl),
                                    icon: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 15,
                                    ),
                                    label: Text(
                                      openHandLocalizedText(
                                        context,
                                        zh: '查看 Gemini 官方模型文档',
                                        zhHant: '查看 Gemini 官方模型文件',
                                        en: 'View Gemini model docs',
                                        fr: 'Voir la documentation des modèles Gemini',
                                        de: 'Gemini-Modelldokumentation öffnen',
                                        ja: 'Gemini モデル公式ドキュメントを表示',
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: colorScheme.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 13,
                                color: colorScheme.outline,
                              ),
                              kOpenHandHGap5,
                              Expanded(
                                child: Text(
                                  openHandLocalizedText(
                                    context,
                                    zh: '若 CLI 未被检测到但实际已安装，可能是启动环境未加载完整 PATH。可刷新重扫，或从终端启动 OpenHand。',
                                    zhHant:
                                        '若 CLI 未被偵測到但實際已安裝，可能是啟動環境未載入完整 PATH。可刷新重掃，或從終端啟動 OpenHand。',
                                    en: 'If an installed CLI is not detected, the launch environment may not include your shell PATH. Refresh or launch OpenHand from a terminal.',
                                    fr: 'Si un CLI installé n’est pas détecté, l’environnement de lancement peut manquer le PATH du shell. Actualisez ou lancez OpenHand depuis un terminal.',
                                    de: 'Wenn eine installierte CLI nicht erkannt wird, fehlt im Startumfeld evtl. dein Shell-PATH. Aktualisiere oder starte OpenHand aus dem Terminal.',
                                    ja: 'インストール済み CLI が検出されない場合、起動環境に shell PATH が含まれていない可能性があります。再スキャンするか、端末から OpenHand を起動してください。',
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.outline,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                kOpenHandGap16,
                OverflowBar(
                  spacing: 8,
                  overflowAlignment: OverflowBarAlignment.center,
                  alignment: MainAxisAlignment.center,
                  children: [
                    OpenHandDialogActionButton.secondary(
                      onPressed: () => Navigator.of(context).pop(),
                      label: openHandCancelLabel(context),
                    ),
                    OpenHandDialogActionButton.primary(
                      onPressed: canSubmit ? _submit : null,
                      label: openHandLocalizedText(
                        context,
                        zh: '开始会话',
                        zhHant: '開始會話',
                        en: 'Start Session',
                        fr: 'Démarrer la session',
                        de: 'Sitzung starten',
                        ja: 'セッションを開始',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: HighlightPulse(
                signal: _logoutSuccessSignal,
                color: OpenHandStatusColors.success,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: HighlightPulse(
                signal: _logoutErrorSignal,
                color: OpenHandStatusColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _harnessConfiguredModelLabel(BuildContext context, String modelId) {
  return describeHarnessCliModel(
    modelId,
    locale: Localizations.localeOf(context),
  );
}

List<DropdownMenuItem<String>> _harnessModelDropdownItems({
  required BuildContext context,
  required List<String> availableModels,
  required String? configuredModel,
}) {
  final items = <DropdownMenuItem<String>>[];
  final trimmedConfiguredModel = configuredModel?.trim();
  if (trimmedConfiguredModel != null &&
      trimmedConfiguredModel.isNotEmpty &&
      !availableModels.contains(trimmedConfiguredModel)) {
    items.add(
      DropdownMenuItem<String>(
        value: trimmedConfiguredModel,
        child: Text(
          _harnessConfiguredModelLabel(context, trimmedConfiguredModel),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
  items.addAll(
    availableModels.map(
      (modelId) => DropdownMenuItem<String>(
        value: modelId,
        child: Text(
          describeHarnessCliModel(
            modelId,
            locale: Localizations.localeOf(context),
          ),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    ),
  );
  return items;
}

String? _harnessResolvedDropdownModelValue(
  List<DropdownMenuItem<String>> items,
  String? configuredModel,
) {
  final trimmedConfiguredModel = configuredModel?.trim();
  if (trimmedConfiguredModel == null || trimmedConfiguredModel.isEmpty) {
    return null;
  }
  return items.any((item) => item.value == trimmedConfiguredModel)
      ? trimmedConfiguredModel
      : null;
}

List<DropdownMenuItem<String>> _harnessCliDropdownItems(
  BuildContext context, {
  required List<CliScanEntry> scanResults,
  required bool isCheckingAuth,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return scanResults
      .where((entry) => entry.cli.supportsHeadless)
      .map((entry) {
        Widget? loginIcon;
        if (entry.installed && entry.cli.hasLoginCheck) {
          if (isCheckingAuth) {
            loginIcon = const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            );
          } else if (entry.isLoggedIn == true) {
            loginIcon = Icon(
              Icons.check_circle_rounded,
              size: 11,
              color: Colors.green.shade600,
            );
          } else if (entry.isLoggedIn == false) {
            loginIcon = Icon(
              Icons.cancel_rounded,
              size: 11,
              color: Colors.orange.shade700,
            );
          }
        }
        return DropdownMenuItem<String>(
          value: entry.cli.name,
          child: Row(
            children: [
              Icon(
                entry.installed ? Icons.circle_rounded : Icons.circle_outlined,
                size: 10,
                color: entry.installed
                    ? colorScheme.primary
                    : colorScheme.outline,
              ),
              kOpenHandHGap6,
              Expanded(
                child: Text(
                  entry.cli.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (loginIcon != null) ...[kOpenHandHGap4, loginIcon],
            ],
          ),
        );
      })
      .toList(growable: false);
}

class _RoleConfigRow extends StatelessWidget {
  const _RoleConfigRow({
    super.key,
    required this.role,
    required this.scanResults,
    required this.executionMode,
    required this.selectedCli,
    required this.availableModels,
    required this.selectedModel,
    this.settingsModels = const [],
    this.selectedAiModelConfigId,
    this.selectedUrlModeModelId,
    required this.showInstallButton,
    this.showViewDocsButton = false,
    this.showLoginButton = false,
    this.showLogoutButton = false,
    this.isCheckingAuth = false,
    required this.onExecutionModeChanged,
    required this.onCliChanged,
    required this.onModelChanged,
    this.onAiModelConfigChanged,
    this.onInstall,
    this.onViewDocs,
    this.onLogin,
    this.onLogout,
  });

  final HarnessAgentRole role;
  final List<CliScanEntry> scanResults;
  final HarnessExecutionMode executionMode;
  final String? selectedCli;
  final List<String> availableModels;
  final String? selectedModel;
  final List<AiModelConfig> settingsModels;
  final String? selectedAiModelConfigId;
  final String? selectedUrlModeModelId;
  final bool showInstallButton;
  final bool showViewDocsButton;
  final bool showLoginButton;
  final bool showLogoutButton;
  final bool isCheckingAuth;
  final ValueChanged<HarnessExecutionMode?> onExecutionModeChanged;
  final ValueChanged<String?> onCliChanged;
  final ValueChanged<String?> onModelChanged;
  final void Function(String? configId, String? modelId)?
  onAiModelConfigChanged;
  final VoidCallback? onInstall;
  final VoidCallback? onViewDocs;
  final VoidCallback? onLogin;
  final VoidCallback? onLogout;

  CliScanEntry? get _selectedEntry => selectedCli == null
      ? null
      : scanResults.where((r) => r.cli.name == selectedCli).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final roleName = _heEngineeringRoleLabel(context, role);
    final isUrlMode = executionMode == HarnessExecutionMode.url;
    final modelItems = _harnessModelDropdownItems(
      context: context,
      availableModels: availableModels,
      configuredModel: selectedModel,
    );
    final effectiveModel = _harnessResolvedDropdownModelValue(
      modelItems,
      selectedModel,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(kOpenHandRadius10),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 68,
                child: Text(
                  roleName,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              kOpenHandHGap10,
              SizedBox(
                width: _kHarnessModeDropdownWidth,
                child: _CompactDropdown<HarnessExecutionMode>(
                  label: openHandModeLabel(context),
                  value: executionMode,
                  items: const [
                    DropdownMenuItem(
                      value: HarnessExecutionMode.cli,
                      child: Text('CLI', style: TextStyle(fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: HarnessExecutionMode.url,
                      child: Text('URL', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                  onChanged: onExecutionModeChanged,
                ),
              ),
              kOpenHandHGap10,
              if (isUrlMode) ...[
                Expanded(
                  flex: 2,
                  child: _SearchableModelSelector(
                    label: _harnessEngineeApiModelLabel(context),
                    settingsModels: settingsModels,
                    selectedAiModelConfigId: selectedAiModelConfigId,
                    selectedUrlModeModelId: selectedUrlModeModelId,
                    onChanged: (configId, modelId) {
                      onAiModelConfigChanged?.call(configId, modelId);
                    },
                    enabled: settingsModels.isNotEmpty,
                  ),
                ),
                if (settingsModels.isEmpty) ...[
                  kOpenHandHGap8,
                  Tooltip(
                    message: openHandLocalizedText(
                      context,
                      zh: '请先在设置中配置 API 模型提供商',
                      zhHant: '請先在設定中設定 API 模型提供者',
                      en: 'Configure API model providers in Settings first',
                      fr: 'Configurez d’abord les fournisseurs de modèles API dans les paramètres',
                      de: 'Konfiguriere zuerst API-Modellanbieter in den Einstellungen',
                      ja: '先に設定で API モデルプロバイダーを設定してください',
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: colorScheme.error,
                    ),
                  ),
                ],
              ] else ...[
                Expanded(
                  child: _CompactDropdown<String>(
                    label: _harnessEngineeCliClientLabel(context),
                    value: selectedCli,
                    items: _harnessCliDropdownItems(
                      context,
                      scanResults: scanResults,
                      isCheckingAuth: isCheckingAuth,
                    ),
                    onChanged: onCliChanged,
                  ),
                ),
                kOpenHandHGap10,
                Expanded(
                  child: _CompactDropdown<String>(
                    label: openHandModelLabel(context),
                    value: effectiveModel,
                    items: modelItems,
                    onChanged: modelItems.isNotEmpty ? onModelChanged : null,
                    enabled: selectedCli != null && availableModels.isNotEmpty,
                  ),
                ),
                if (showInstallButton) ...[
                  kOpenHandHGap8,
                  Tooltip(
                    message: openHandLocalizedText(
                      context,
                      zh: '安装此 CLI',
                      zhHant: '安裝此 CLI',
                      en: 'Install this CLI',
                      fr: 'Installer ce CLI',
                      de: 'Diese CLI installieren',
                      ja: 'この CLI をインストール',
                    ),
                    child: OutlinedButton.icon(
                      onPressed: onInstall,
                      icon: const Icon(Icons.download_rounded, size: 15),
                      label: Text(
                        openHandInstallLabel(context),
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        side: BorderSide(
                          color: colorScheme.primary.withValues(alpha: 0.7),
                        ),
                        foregroundColor: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
                if (showViewDocsButton && onViewDocs != null) ...[
                  kOpenHandHGap8,
                  Tooltip(
                    message: openHandLocalizedText(
                      context,
                      zh: '打开安装文档',
                      zhHant: '開啟安裝文件',
                      en: 'Open install docs',
                      fr: 'Ouvrir la documentation d’installation',
                      de: 'Installationsdokumentation öffnen',
                      ja: 'インストールドキュメントを開く',
                    ),
                    child: OutlinedButton.icon(
                      onPressed: onViewDocs,
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: Text(
                        openHandLocalizedText(
                          context,
                          zh: '安装文档',
                          zhHant: '安裝文件',
                          en: 'Docs',
                          fr: 'Docs',
                          de: 'Doku',
                          ja: 'ドキュメント',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        side: BorderSide(
                          color: colorScheme.secondary.withValues(alpha: 0.7),
                        ),
                        foregroundColor: colorScheme.secondary,
                      ),
                    ),
                  ),
                ],
              ],
              if (!isUrlMode &&
                  isCheckingAuth &&
                  selectedCli != null &&
                  (_selectedEntry?.installed ?? false) &&
                  (_selectedEntry?.cli.hasLoginCheck ?? false)) ...[
                kOpenHandHGap8,
                Tooltip(
                  message: openHandLocalizedText(
                    context,
                    zh: '正在检测登录状态...',
                    zhHant: '正在檢查登入狀態...',
                    en: 'Checking login state...',
                    fr: 'Vérification de la connexion...',
                    de: 'Loginstatus wird geprüft...',
                    ja: 'ログイン状態を確認中...',
                  ),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: colorScheme.primary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
              if (!isUrlMode &&
                  !isCheckingAuth &&
                  selectedCli != null &&
                  _selectedEntry?.isLoggedIn == true &&
                  (_selectedEntry?.cli.hasLoginCheck ?? false)) ...[
                kOpenHandHGap6,
                Tooltip(
                  message: openHandLocalizedText(
                    context,
                    zh: '已登录',
                    zhHant: '已登入',
                    en: 'Logged in',
                    fr: 'Connecté',
                    de: 'Angemeldet',
                    ja: 'ログイン済み',
                  ),
                  child: Icon(
                    Icons.verified_user_rounded,
                    size: 16,
                    color: Colors.green.shade600,
                  ),
                ),
              ],
              if (!isUrlMode && showLoginButton) ...[
                kOpenHandHGap8,
                Tooltip(
                  message: openHandLocalizedText(
                    context,
                    zh: '此 CLI 尚未登录，点击引导登录',
                    zhHant: '此 CLI 尚未登入，點擊以引導登入',
                    en: 'This CLI is not logged in. Click to start login.',
                    fr: 'Ce CLI n’est pas connecté. Cliquez pour lancer la connexion.',
                    de: 'Diese CLI ist nicht angemeldet. Klicken zum Anmelden.',
                    ja: 'この CLI は未ログインです。クリックしてログインを開始します。',
                  ),
                  child: OutlinedButton.icon(
                    onPressed: onLogin,
                    icon: const Icon(Icons.login_rounded, size: 15),
                    label: Text(
                      openHandLocalizedText(
                        context,
                        zh: '登录',
                        zhHant: '登入',
                        en: 'Login',
                        fr: 'Connexion',
                        de: 'Anmelden',
                        ja: 'ログイン',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      side: BorderSide(
                        color: Colors.orange.shade600.withValues(alpha: 0.8),
                      ),
                      foregroundColor: Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
              if (!isUrlMode && showLogoutButton) ...[
                kOpenHandHGap6,
                Tooltip(
                  message: openHandLocalizedText(
                    context,
                    zh: '此 CLI 已登录，点击可登出以切换账号',
                    zhHant: '此 CLI 已登入，點擊可登出以切換帳號',
                    en: 'This CLI is logged in. Click to log out and switch accounts.',
                    fr: 'Ce CLI est connecté. Cliquez pour vous déconnecter et changer de compte.',
                    de: 'Diese CLI ist angemeldet. Klicken zum Abmelden und Konto wechseln.',
                    ja: 'この CLI はログイン済みです。クリックしてログアウトし、アカウントを切り替えます。',
                  ),
                  child: OutlinedButton.icon(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout_rounded, size: 15),
                    label: Text(
                      openHandLocalizedText(
                        context,
                        zh: '登出',
                        zhHant: '登出',
                        en: 'Logout',
                        fr: 'Déconnexion',
                        de: 'Abmelden',
                        ja: 'ログアウト',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      side: BorderSide(
                        color: colorScheme.outline.withValues(alpha: 0.6),
                      ),
                      foregroundColor: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (!isUrlMode &&
                  selectedCli != null &&
                  _selectedEntry?.cli.supportsHeadless == false) ...[
                kOpenHandHGap6,
                Tooltip(
                  message: openHandLocalizedText(
                    context,
                    zh: '此工具为 GUI 应用，不支持无交互调用，Harness Engineering 将跳过此角色阶段',
                    zhHant: '此工具為 GUI 應用，不支援無互動呼叫，Harness Engineering 將跳過此角色階段',
                    en: 'GUI-only app: non-interactive invocation is not supported. This role phase will be skipped.',
                    fr: 'Application GUI uniquement : l’exécution non interactive n’est pas prise en charge. Cette phase sera ignorée.',
                    de: 'Nur GUI-App: Nichtinteraktive Ausführung wird nicht unterstützt. Diese Rollenphase wird übersprungen.',
                    ja: 'GUI 専用アプリのため非対話実行に対応していません。このロールフェーズはスキップされます。',
                  ),
                  child: Icon(
                    Icons.monitor_rounded,
                    size: 18,
                    color: colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactDropdown<T> extends StatelessWidget {
  const _CompactDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: AnimatedDropdownButton<T>(
          isDense: true,
          isExpanded: true,
          value: value,
          hint: Text(
            enabled ? label : '—',
            style: const TextStyle(fontSize: 13),
          ),
          items: items,
          onChanged: (enabled && items.isNotEmpty) ? onChanged : null,
        ),
      ),
    );
  }
}

class _QuickApplyBar extends StatelessWidget {
  const _QuickApplyBar({
    required this.scanResults,
    required this.isScanning,
    required this.isCheckingAuth,
    required this.executionMode,
    required this.selectedCli,
    required this.selectedModel,
    required this.settingsModels,
    required this.selectedAiModelConfigId,
    required this.selectedUrlModeModelId,
    required this.onExecutionModeChanged,
    required this.onCliChanged,
    required this.onModelChanged,
    required this.onAiModelConfigChanged,
    required this.onApply,
    required this.modelsForCli,
  });

  final List<CliScanEntry> scanResults;
  final bool isScanning;
  final bool isCheckingAuth;
  final HarnessExecutionMode executionMode;
  final String? selectedCli;
  final String? selectedModel;
  final List<AiModelConfig> settingsModels;
  final String? selectedAiModelConfigId;
  final String? selectedUrlModeModelId;
  final ValueChanged<HarnessExecutionMode?> onExecutionModeChanged;
  final ValueChanged<String?> onCliChanged;
  final ValueChanged<String?> onModelChanged;
  final void Function(String? configId, String? modelId) onAiModelConfigChanged;
  final VoidCallback onApply;
  final List<String> Function(String?) modelsForCli;

  bool get _hasUrlModelSelected {
    final id = selectedAiModelConfigId?.trim();
    if (id == null || id.isEmpty) return false;
    final provider = settingsModels.where((m) => m.id == id).firstOrNull;
    if (provider == null) return false;
    final modelId = selectedUrlModeModelId?.trim();
    if (modelId != null && modelId.isNotEmpty) return true;
    return provider.modelId.trim().isNotEmpty;
  }

  bool get _canApply {
    if (executionMode == HarnessExecutionMode.url) {
      return _hasUrlModelSelected;
    }
    return selectedCli != null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUrlMode = executionMode == HarnessExecutionMode.url;
    final cliItems = isUrlMode
        ? const <DropdownMenuItem<String>>[]
        : _harnessCliDropdownItems(
            context,
            scanResults: scanResults,
            isCheckingAuth: isCheckingAuth,
          );

    // 提前构建下拉数据，避免在组件树内重复创建临时组件。
    final cliModels = isUrlMode ? const <String>[] : modelsForCli(selectedCli);
    final cliModelItems = isUrlMode
        ? const <DropdownMenuItem<String>>[]
        : _harnessModelDropdownItems(
            context: context,
            availableModels: cliModels,
            configuredModel: selectedModel,
          );
    final cliEffectiveModel = isUrlMode
        ? null
        : _harnessResolvedDropdownModelValue(cliModelItems, selectedModel);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(kOpenHandRadius10),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.bolt_rounded, size: 16, color: colorScheme.primary),
            kOpenHandHGap6,
            Text(
              openHandLocalizedText(
                context,
                zh: '一键配置',
                zhHant: '一鍵設定',
                en: 'Batch',
                fr: 'Lot',
                de: 'Stapel',
                ja: '一括設定',
              ),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            kOpenHandHGap10,
            SizedBox(
              width: _kHarnessModeDropdownWidth,
              child: _CompactDropdown<HarnessExecutionMode>(
                label: openHandModeLabel(context),
                value: executionMode,
                items: const [
                  DropdownMenuItem(
                    value: HarnessExecutionMode.cli,
                    child: Text('CLI', style: TextStyle(fontSize: 13)),
                  ),
                  DropdownMenuItem(
                    value: HarnessExecutionMode.url,
                    child: Text('URL', style: TextStyle(fontSize: 13)),
                  ),
                ],
                onChanged: onExecutionModeChanged,
              ),
            ),
            kOpenHandHGap8,
            if (isUrlMode) ...[
              Expanded(
                flex: 2,
                child: _SearchableModelSelector(
                  label: _harnessEngineeApiModelLabel(context),
                  settingsModels: settingsModels,
                  selectedAiModelConfigId: selectedAiModelConfigId,
                  selectedUrlModeModelId: selectedUrlModeModelId,
                  onChanged: onAiModelConfigChanged,
                  enabled: settingsModels.isNotEmpty,
                ),
              ),
            ] else ...[
              Expanded(
                child: _CompactDropdown<String>(
                  label: _harnessEngineeCliClientLabel(context),
                  value: selectedCli,
                  items: cliItems,
                  onChanged: isScanning ? null : onCliChanged,
                  enabled: !isScanning && scanResults.isNotEmpty,
                ),
              ),
              kOpenHandHGap8,
              Expanded(
                child: _CompactDropdown<String>(
                  label: openHandModelLabel(context),
                  value: cliEffectiveModel,
                  items: cliModelItems,
                  onChanged: cliModelItems.isNotEmpty ? onModelChanged : null,
                  enabled: selectedCli != null && cliModels.isNotEmpty,
                ),
              ),
            ],
            kOpenHandHGap8,
            FilledButton.tonal(
              onPressed: _canApply ? onApply : null,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Text(
                openHandLocalizedText(
                  context,
                  zh: '应用至所有角色',
                  zhHant: '套用至所有角色',
                  en: 'Apply to all roles',
                  fr: 'Appliquer à tous les rôles',
                  de: 'Auf alle Rollen anwenden',
                  ja: 'すべてのロールに適用',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CliScanSummary extends StatelessWidget {
  const _CliScanSummary({
    required this.scanResults,
    required this.isCheckingAuth,
  });

  final List<CliScanEntry> scanResults;
  final bool isCheckingAuth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final headless = scanResults.where((r) => r.cli.supportsHeadless).toList();
    if (headless.isEmpty) return const SizedBox.shrink();

    final installed = headless.where((r) => r.installed).toList();
    final notInstalled = headless.where((r) => !r.installed).toList();

    final chips = <Widget>[];

    for (final entry in installed) {
      String? authSuffix;
      if (entry.cli.hasLoginCheck) {
        if (isCheckingAuth) {
          authSuffix = '…';
        } else if (entry.isLoggedIn == true) {
          authSuffix = '✓';
        } else if (entry.isLoggedIn == false) {
          authSuffix = '✗';
        }
      }
      final label = authSuffix != null
          ? '${entry.cli.name}($authSuffix)'
          : entry.cli.name;
      chips.add(
        _ScanChip(
          label: label,
          icon: Icons.circle_rounded,
          iconColor: colorScheme.primary,
        ),
      );
    }

    for (final entry in notInstalled) {
      chips.add(
        _ScanChip(
          label: entry.cli.name,
          icon: Icons.circle_outlined,
          iconColor: colorScheme.outline,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          openHandLocalizedText(
            context,
            zh: 'CLI 状态：',
            zhHant: 'CLI 狀態：',
            en: 'CLIs:',
            fr: 'CLI :',
            de: 'CLIs:',
            ja: 'CLI:',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        ...chips,
        // 固定占位的切换：转圈直接插进这一行会把已有徽标整体推开。
        OpenHandBusyStatusIcon(
          busy: isCheckingAuth,
          icon: null,
          size: 12,
          strokeWidth: 1.5,
          color: colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _ScanChip extends StatelessWidget {
  const _ScanChip({
    required this.label,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 8, color: iconColor),
        kOpenHandHGap3,
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _SearchableModelSelector extends StatefulWidget {
  const _SearchableModelSelector({
    required this.label,
    required this.settingsModels,
    required this.selectedAiModelConfigId,
    required this.selectedUrlModeModelId,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final List<AiModelConfig> settingsModels;
  final String? selectedAiModelConfigId;
  final String? selectedUrlModeModelId;
  final void Function(String? configId, String? modelId) onChanged;
  final bool enabled;

  @override
  State<_SearchableModelSelector> createState() =>
      _SearchableModelSelectorState();
}

class _SearchableModelSelectorState extends State<_SearchableModelSelector> {
  bool _menuOpen = false;

  String? get _displayLabel {
    final id = widget.selectedAiModelConfigId?.trim();
    if (id == null || id.isEmpty) return null;
    final config = widget.settingsModels.where((m) => m.id == id).firstOrNull;
    if (config == null) return null;
    final modelId = widget.selectedUrlModeModelId?.trim();
    if (modelId != null && modelId.isNotEmpty) return modelId;
    if (config.modelId.trim().isNotEmpty) return config.modelId;
    return config.providerLabel;
  }

  void _showMenu() {
    if (_menuOpen || !widget.enabled || widget.settingsModels.isEmpty) return;

    final settingsController = context
        .findAncestorStateOfType<_HarnessEngineeringDialogState>()
        ?.widget
        .settingsController;

    setState(() => _menuOpen = true);
    showModelSearchSelector(
      context: context,
      models: widget.settingsModels,
      recentSelections: settingsController?.recentModelSelections ?? const [],
      selectedConfigId: widget.selectedAiModelConfigId,
      selectedModelId: widget.selectedUrlModeModelId,
    ).then((value) {
      if (mounted) setState(() => _menuOpen = false);
      if (!mounted || value == null) return;
      settingsController?.addRecentModelSelection(value.$1, value.$2);
      widget.onChanged(value.$1, value.$2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OpenHandTapRegion(
      onTap: (widget.enabled && widget.settingsModels.isNotEmpty)
          ? _showMenu
          : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          isDense: true,
          suffixIcon: Icon(
            _menuOpen
                ? Icons.arrow_drop_up_rounded
                : Icons.arrow_drop_down_rounded,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
          ),
        ),
        child: Text(
          _displayLabel ?? (widget.enabled ? widget.label : '—'),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: widget.enabled
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ── 本文件内复用的文案 ──
// 同一标签在本文件里出现两次以上；抽成函数后措辞只有一个改动点。

String _harnessEngineeApiModelLabel(BuildContext context) {
  return openHandApiModelLabel(context);
}

String _harnessEngineeBrowseFolderLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '浏览文件夹',
    zhHant: '瀏覽資料夾',
    en: 'Browse folder',
    fr: 'Parcourir le dossier',
    de: 'Ordner durchsuchen',
    ja: 'フォルダーを参照',
  );
}

String _harnessEngineeCliClientLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: 'CLI 客户端',
    zhHant: 'CLI 用戶端',
    en: 'CLI Client',
    fr: 'Client CLI',
    de: 'CLI-Client',
    ja: 'CLI クライアント',
  );
}
