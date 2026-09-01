import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:openhand/shared/util/text_normalization.dart';
import 'package:provider/provider.dart';

import '../../app/support/silent_log.dart';
import '../../shared/db/atomic_file_operations.dart';
import '../../shared/net/tcp_port_utils.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/animated_menu.dart';
import '../../shared/ui/ansi_text.dart';
import '../../shared/ui/frame_coalesced_rebuild.dart';
import '../../shared/ui/motion_durations.dart';
import '../../shared/ui/motion_preference.dart';
import '../../shared/ui/oh_pill.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_clipboard.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_reveal_switcher.dart';
import '../../shared/ui/openhand_safe_scrollbar.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_tap_region.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_base64.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/platform_shell.dart';
import '../../shared/util/structured_text_format.dart';
import '../../shared/util/timer_safety.dart';
import '../../shared/util/tool_name_normalization.dart';
import '../ai/index.dart';
import '../mcp/index.dart';
import '../plugin_service/index.dart';
import '../thread_template_runtime/index.dart';
import 'android_reverse_adb_client.dart';
import 'android_reverse_dialog_utils.dart';
import 'android_reverse_session_config.dart';
import 'android_reverse_session_controller.dart';
import 'android_reverse_toolchain_diagnostics.dart';

const Duration _kSwitchDuration = kOpenHandMotion220;
const double _kAdbInlineControlHeight = 44;
const double _kDashboardFilterControlHeight = 36;
const double _kDashboardActionButtonHeight = 36;
const double _kDashboardActionIconSize = 14;
const double _kDashboardIconActionButtonSize = 36;
const double _kDashboardIconActionIconSize = 17;
const double _kDashboardTrailingActionGap = 8;
const double _kDashboardHeaderCompactBreakpoint = 720;
const double _kDashboardHeaderLeadingMaxWidth = 320;
const double _kDashboardHeaderLeadingMaxWidthRatio = 0.34;
const double _kDeviceTrailingActionWidth = 88;
const double _kShellOutputMaxHeight = 220;
const double _kIconButtonGap = 8;
const EdgeInsets _kDashboardDialogInsetPadding = EdgeInsets.all(16);
const int _kDefaultLogcatLines = 200;
const int _kAutoLogcatLines = 80;
const int _kDefaultLogcatCacheLimit = 200;
const int _kMinLogcatCacheLimit = 50;
const int _kMaxLogcatCacheLimit = 2000;
const int _kShellHistoryLimit = 6;
const int _kPackageDumpsysSummaryMaxLines = 160;
const int _kDefaultScreenRecordSeconds = 10;
const int _kMcpToolPreviewLimit = 8;
const int _kMcpReconnectConcurrency = 4;
const int _kCryptoDecodeMaxBytes = 8 * kBytesPerMiB;
const int _kMaxNetworkFlowExportBytes = kBytesPerGiB;
const Duration _kArtifactFileProbeTimeout = Duration(seconds: 3);
const Duration _kInteractiveShellTimeout = Duration(seconds: 8);
const Duration _kPackageDumpsysTimeout = Duration(seconds: 12);
const Duration _kDeviceSnapshotTimeout = Duration(seconds: 8);

/// frida-doctor 环境体检脚本：逐项探测工具链，比单条命令久。
const Duration _kFridaDoctorTimeout = Duration(seconds: 15);

/// frida spawn / attach：要等目标进程起来并完成注入。
const Duration _kFridaCaptureTimeout = Duration(seconds: 28);

/// 本机 shell 形式的 frida 辅助命令（列举脚本、查状态）。
const Duration _kFridaLocalShellTimeout = Duration(seconds: 8);

/// 网络代理探测脚本：需要真机往返一次请求。
const Duration _kNetworkProxyProbeTimeout = Duration(seconds: 18);
const Duration _kLogcatAutoRefreshInterval = Duration(seconds: 1);
const Duration _kLogcatFollowScrollDuration = kOpenHandMotion360;
const int _kDeviceSnapshotMaxLines = 80;
const int _kMinTcpPort = kTcpPortMin;
const int _kMaxTcpPort = kTcpPortMax;
const String _kAdbShellHintZh = '请输入 adb shell 命令';
const String _kAdbShellHintEn = 'Enter adb shell command';
const String _kDeviceSnapshotScript = '''
printf '[battery]\\n'
dumpsys battery | grep -E 'level:|status:|temperature:|voltage:|AC powered:|USB powered:|Wireless powered:' || true
printf '[display]\\n'
wm size; wm density
printf '[storage]\\n'
df -h /data /sdcard 2>/dev/null || df /data /sdcard 2>/dev/null || true
printf '[foreground]\\n'
dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | head -4 || true
printf '[abi]\\n'
getprop ro.product.cpu.abi
getprop ro.product.cpu.abilist
''';
const List<String> _kLogcatLevels = <String>['V', 'D', 'I', 'W', 'E', 'F'];
const List<String> _kAndroidMcpKeywords =
    TemplateRuntimeDependencyRegistry.androidReverseMcpKeywords;
const List<String> _kAndroidRuntimePluginIds =
    TemplateRuntimeDependencyRegistry.androidReversePluginIds;

typedef _LogcatQueryContext = ({
  int generation,
  String? serial,
  String tag,
  String level,
  String explicitPid,
  String? packageName,
});

typedef _AndroidTargetContext = ({
  int generation,
  String? serial,
  String? packageName,
});

typedef _StaticAnalysisContext = ({String? apkPath, String? packageName});

String _androidToolchainInstallHint(
  BuildContext context,
  AndroidReverseToolchainProbe probe,
) {
  return switch (probe.id) {
    'adb' => openHandLocalizedText(
      context,
      zh: '安装 Android SDK Platform Tools，并把 adb 加入 PATH。',
      zhHant: '安裝 Android SDK Platform Tools，並將 adb 加入 PATH。',
      en: 'Install Android SDK Platform Tools and add adb to PATH.',
      fr: 'Installez Android SDK Platform Tools et ajoutez adb au PATH.',
      de: 'Installiere Android SDK Platform Tools und füge adb zum PATH hinzu.',
      ja: 'Android SDK Platform Tools をインストールし、adb を PATH に追加してください。',
    ),
    'aapt' => openHandLocalizedText(
      context,
      zh: '在 Android SDK Manager 安装 Build Tools。',
      zhHant: '在 Android SDK Manager 安裝 Build Tools。',
      en: 'Install Android SDK Build Tools.',
      fr: 'Installez Android SDK Build Tools.',
      de: 'Installiere Android SDK Build Tools.',
      ja: 'Android SDK Build Tools をインストールしてください。',
    ),
    'apksigner' => openHandLocalizedText(
      context,
      zh: '在 Android SDK Manager 安装 Build Tools，用于 APK 签名证书检查。',
      zhHant: '在 Android SDK Manager 安裝 Build Tools，用於 APK 簽章憑證檢查。',
      en: 'Install Android SDK Build Tools for APK signing certificate checks.',
      fr: 'Installez Android SDK Build Tools pour vérifier les certificats de signature APK.',
      de: 'Installiere Android SDK Build Tools für Prüfungen von APK-Signaturzertifikaten.',
      ja: 'APK 署名証明書の確認用に Android SDK Build Tools をインストールしてください。',
    ),
    'keytool' => openHandLocalizedText(
      context,
      zh: '安装 JDK，并把 keytool 加入 PATH，用于证书查看。',
      zhHant: '安裝 JDK，並將 keytool 加入 PATH，用於憑證查看。',
      en: 'Install a JDK and add keytool to PATH for certificate checks.',
      fr: 'Installez un JDK et ajoutez keytool au PATH pour vérifier les certificats.',
      de: 'Installiere ein JDK und füge keytool für Zertifikatsprüfungen zum PATH hinzu.',
      ja: '証明書確認用に JDK をインストールし、keytool を PATH に追加してください。',
    ),
    'strings' => openHandLocalizedText(
      context,
      zh: '安装系统开发者工具或 binutils，用于 dex/so/assets 字符串扫描。',
      zhHant: '安裝系統開發者工具或 binutils，用於 dex/so/assets 字串掃描。',
      en: 'Install system developer tools or binutils for dex/so/assets string scans.',
      fr: 'Installez les outils développeur système ou binutils pour scanner les chaînes dex/so/assets.',
      de: 'Installiere System-Entwicklertools oder binutils für dex/so/assets-Stringscans.',
      ja: 'dex/so/assets の文字列スキャン用にシステム開発者ツールまたは binutils をインストールしてください。',
    ),
    'readelf' => openHandLocalizedText(
      context,
      zh: '安装 binutils / LLVM / Android NDK，用于 so 符号与段信息分析。',
      zhHant: '安裝 binutils / LLVM / Android NDK，用於 so 符號與區段資訊分析。',
      en: 'Install binutils, LLVM, or Android NDK for native symbol analysis.',
      fr: 'Installez binutils, LLVM ou Android NDK pour analyser les symboles natifs.',
      de: 'Installiere binutils, LLVM oder Android NDK für native Symbolanalysen.',
      ja: 'ネイティブシンボル解析用に binutils、LLVM、または Android NDK をインストールしてください。',
    ),
    'apktool' => openHandLocalizedText(
      context,
      zh: '可通过 Homebrew 安装：brew install apktool。',
      zhHant: '可透過 Homebrew 安裝：brew install apktool。',
      en: 'Install with Homebrew: brew install apktool.',
      fr: 'Installez avec Homebrew : brew install apktool.',
      de: 'Mit Homebrew installieren: brew install apktool.',
      ja: 'Homebrew でインストールできます: brew install apktool。',
    ),
    'jadx' => openHandLocalizedText(
      context,
      zh: '可通过 Homebrew 安装：brew install jadx。',
      zhHant: '可透過 Homebrew 安裝：brew install jadx。',
      en: 'Install with Homebrew: brew install jadx.',
      fr: 'Installez avec Homebrew : brew install jadx.',
      de: 'Mit Homebrew installieren: brew install jadx.',
      ja: 'Homebrew でインストールできます: brew install jadx。',
    ),
    'frida' => openHandLocalizedText(
      context,
      zh: '安装 frida-tools，并按设备架构准备 frida-server。',
      zhHant: '安裝 frida-tools，並依裝置架構準備 frida-server。',
      en: 'Install frida-tools and prepare frida-server for the device ABI.',
      fr: 'Installez frida-tools et préparez frida-server pour l’ABI de l’appareil.',
      de: 'Installiere frida-tools und bereite frida-server für die Geräte-ABI vor.',
      ja: 'frida-tools をインストールし、デバイス ABI に合う frida-server を準備してください。',
    ),
    'mitmproxy' => openHandLocalizedText(
      context,
      zh: '可通过 Homebrew 安装：brew install mitmproxy。',
      zhHant: '可透過 Homebrew 安裝：brew install mitmproxy。',
      en: 'Install with Homebrew: brew install mitmproxy.',
      fr: 'Installez avec Homebrew : brew install mitmproxy.',
      de: 'Mit Homebrew installieren: brew install mitmproxy.',
      ja: 'Homebrew でインストールできます: brew install mitmproxy。',
    ),
    'radare2' => openHandLocalizedText(
      context,
      zh: '可通过 Homebrew 安装：brew install radare2。',
      zhHant: '可透過 Homebrew 安裝：brew install radare2。',
      en: 'Install with Homebrew: brew install radare2.',
      fr: 'Installez avec Homebrew : brew install radare2.',
      de: 'Mit Homebrew installieren: brew install radare2.',
      ja: 'Homebrew でインストールできます: brew install radare2。',
    ),
    'blutter' => openHandLocalizedText(
      context,
      zh: '可在插件板块直接安装 blutter，或按项目说明安装并加入 PATH。',
      zhHant: '可在外掛板塊直接安裝 blutter，或依專案說明安裝並加入 PATH。',
      en: 'Install blutter from the Plugins tab, or from its project instructions and add it to PATH.',
      fr: 'Installez blutter depuis l’onglet Plugins ou suivez le projet puis ajoutez-le au PATH.',
      de: 'Installiere blutter im Plugin-Tab oder nach Projektanleitung und füge es zum PATH hinzu.',
      ja: 'プラグインタブから blutter をインストールするか、プロジェクト手順に従って PATH に追加してください。',
    ),
    'doldrums' => openHandLocalizedText(
      context,
      zh: '可在插件板块直接安装 Doldrums，或按项目说明安装并加入 PATH。',
      zhHant: '可在外掛板塊直接安裝 Doldrums，或依專案說明安裝並加入 PATH。',
      en: 'Install Doldrums from the Plugins tab, or from its project instructions and add it to PATH.',
      fr: 'Installez Doldrums depuis l’onglet Plugins ou suivez le projet puis ajoutez-le au PATH.',
      de: 'Installiere Doldrums im Plugin-Tab oder nach Projektanleitung und füge es zum PATH hinzu.',
      ja: 'プラグインタブから Doldrums をインストールするか、プロジェクト手順に従って PATH に追加してください。',
    ),
    'anything_analyzer' => openHandLocalizedText(
      context,
      zh: '可在插件板块直接安装 Anything Analyzer，并在 MCP 面板启用对应 server。',
      zhHant: '可在外掛板塊直接安裝 Anything Analyzer，並在 MCP 面板啟用對應 server。',
      en: 'Install Anything Analyzer from the Plugins tab and enable the corresponding server in the MCP panel.',
      fr: 'Installez Anything Analyzer depuis l’onglet Plugins et activez le serveur correspondant dans MCP.',
      de: 'Installiere Anything Analyzer im Plugin-Tab und aktiviere den passenden Server im MCP-Panel.',
      ja: 'プラグインタブから Anything Analyzer をインストールし、MCP パネルで対応 server を有効化してください。',
    ),
    _ => openHandLocalizedText(
      context,
      zh: probe.installHintZh,
      en: probe.installHintEn,
    ),
  };
}

Future<void> showAndroidReverseDashboardDialog(
  BuildContext context, {
  required AndroidReverseSessionController controller,
  required String sessionId,
}) {
  return androidReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _AndroidReverseDashboardDialog(
      controller: controller,
      sessionId: sessionId,
    ),
  );
}

enum _Tab {
  devices,
  overview,
  toolchain,
  mcp,
  plugins,
  packages,
  processes,
  logcat,
  frida,
  network,
  staticAnalysis,
  certs,
  crypto,
}

enum _DeviceMenuAction {
  useForPanel,
  copySerial,
  refreshProps,
  listForwards,
  tcpip5555,
  deviceReport,
  screenshot,
  screenRecord,
  root,
  remount,
  reboot,
  disconnect,
}

enum _PackageMenuAction {
  analyze,
  report,
  copyPackage,
  launch,
  forceStop,
  clearData,
  pullApks,
  logcat,
  uninstall,
}

enum _ProcessMenuAction { copyPid, copyName, kill, forceStopPackage, logcatPid }

enum _ToolchainCommandAction { install, update, uninstall, reference }

enum _RuntimePluginAction {
  info,
  install,
  checkUpdate,
  update,
  enable,
  disable,
  uninstall,
}

enum _LogcatLineAction { copy, delete }

class _FridaSnippetPreset {
  const _FridaSnippetPreset({
    required this.id,
    required this.assetPath,
    required this.labelZh,
    required this.labelEn,
    required this.descZh,
    required this.descEn,
  });

  final String id;
  final String assetPath;
  final String labelZh;
  final String labelEn;
  final String descZh;
  final String descEn;

  String label(BuildContext context) {
    return switch (id) {
      'java_method' => openHandLocalizedText(
        context,
        zh: labelZh,
        zhHant: 'Java 方法',
        en: labelEn,
        fr: 'Méthode Java',
        de: 'Java-Methode',
        ja: 'Java メソッド',
      ),
      'native_func' => openHandLocalizedText(
        context,
        zh: labelZh,
        zhHant: 'Native 函式',
        en: labelEn,
        fr: 'Fonction native',
        de: 'Native-Funktion',
        ja: 'Native 関数',
      ),
      _ => openHandLocalizedText(
        context,
        zh: labelZh,
        zhHant: labelZh,
        en: labelEn,
        fr: labelEn,
        de: labelEn,
        ja: labelEn,
      ),
    };
  }

  String desc(BuildContext context) {
    return switch (id) {
      'java_method' => openHandLocalizedText(
        context,
        zh: descZh,
        zhHant: '入參、返回值、呼叫堆疊',
        en: descEn,
        fr: 'Arguments, valeur de retour, pile',
        de: 'Argumente, Rückgabewert, Stack',
        ja: '引数、戻り値、スタック',
      ),
      'okhttp' => openHandLocalizedText(
        context,
        zh: descZh,
        zhHant: '請求/回應 URL、Header、Body',
        en: descEn,
        fr: 'URL, headers et body requête/réponse',
        de: 'Request/Response-URL, Header, Body',
        ja: 'リクエスト/レスポンス URL、Header、Body',
      ),
      'ssl_pinning' => openHandLocalizedText(
        context,
        zh: descZh,
        zhHant: '常見憑證鎖定繞過',
        en: descEn,
        fr: 'Contournements courants du pinning',
        de: 'Gängige Pinning-Bypässe',
        ja: '一般的なピンニング回避',
      ),
      'aes_cbc' => openHandLocalizedText(
        context,
        zh: descZh,
        zhHant: 'Cipher doFinal 明文/密文',
        en: descEn,
        fr: 'Clair/chiffré de Cipher doFinal',
        de: 'Cipher doFinal Klartext/Chiffrat',
        ja: 'Cipher doFinal 平文/暗号文',
      ),
      'native_func' => openHandLocalizedText(
        context,
        zh: descZh,
        zhHant: 'JNI/so 入參與返回值',
        en: descEn,
        fr: 'Arguments et retours JNI/so',
        de: 'JNI/so-Argumente und Rückgabewert',
        ja: 'JNI/so 引数と戻り値',
      ),
      'flutter_dart' => openHandLocalizedText(
        context,
        zh: descZh,
        zhHant: '配合 blutter/Doldrums',
        en: descEn,
        fr: 'Avec blutter/Doldrums',
        de: 'Mit blutter/Doldrums',
        ja: 'blutter/Doldrums と併用',
      ),
      _ => openHandLocalizedText(
        context,
        zh: descZh,
        zhHant: descZh,
        en: descEn,
        fr: descEn,
        de: descEn,
        ja: descEn,
      ),
    };
  }
}

const List<_FridaSnippetPreset> _kFridaSnippetPresets = <_FridaSnippetPreset>[
  _FridaSnippetPreset(
    id: 'java_method',
    assetPath:
        'assets/prompts/android_reverse_expert/snippets/hook_java_method.js',
    labelZh: 'Java 方法',
    labelEn: 'Java method',
    descZh: '入参、返回值、调用栈',
    descEn: 'Args, return value, stack',
  ),
  _FridaSnippetPreset(
    id: 'okhttp',
    assetPath: 'assets/prompts/android_reverse_expert/snippets/hook_okhttp.js',
    labelZh: 'OkHttp',
    labelEn: 'OkHttp',
    descZh: '请求/响应 URL、Header、Body',
    descEn: 'Request/response URL, headers, body',
  ),
  _FridaSnippetPreset(
    id: 'ssl_pinning',
    assetPath:
        'assets/prompts/android_reverse_expert/snippets/hook_ssl_pinning.js',
    labelZh: 'SSL Pinning',
    labelEn: 'SSL Pinning',
    descZh: '常见证书锁定绕过',
    descEn: 'Common pinning bypass',
  ),
  _FridaSnippetPreset(
    id: 'aes_cbc',
    assetPath: 'assets/prompts/android_reverse_expert/snippets/hook_aes_cbc.js',
    labelZh: 'AES/CBC',
    labelEn: 'AES/CBC',
    descZh: 'Cipher doFinal 明文/密文',
    descEn: 'Cipher doFinal plaintext/ciphertext',
  ),
  _FridaSnippetPreset(
    id: 'native_func',
    assetPath:
        'assets/prompts/android_reverse_expert/snippets/hook_native_func.js',
    labelZh: 'Native 函数',
    labelEn: 'Native function',
    descZh: 'JNI/so 入参与返回值',
    descEn: 'JNI/so args and return value',
  ),
  _FridaSnippetPreset(
    id: 'webview',
    assetPath: 'assets/prompts/android_reverse_expert/snippets/hook_webview.js',
    labelZh: 'WebView',
    labelEn: 'WebView',
    descZh: 'loadUrl / evaluateJavascript',
    descEn: 'loadUrl / evaluateJavascript',
  ),
  _FridaSnippetPreset(
    id: 'flutter_dart',
    assetPath:
        'assets/prompts/android_reverse_expert/snippets/hook_flutter_dart.js',
    labelZh: 'Flutter/Dart',
    labelEn: 'Flutter/Dart',
    descZh: '配合 blutter/Doldrums',
    descEn: 'Use with blutter/Doldrums',
  ),
];

extension _TabLabel on _Tab {
  String label(BuildContext context) {
    return switch (this) {
      _Tab.devices => openHandLocalizedText(
        context,
        zh: '设备管理',
        zhHant: '裝置管理',
        en: 'Devices',
        fr: 'Appareils',
        de: 'Geräte',
        ja: 'デバイス',
      ),
      _Tab.overview => openHandOverviewLabel(context),
      _Tab.toolchain => openHandLocalizedText(
        context,
        zh: '工具链',
        zhHant: '工具鏈',
        en: 'Toolchain',
        fr: 'Chaîne d’outils',
        de: 'Toolchain',
        ja: 'ツールチェーン',
      ),
      _Tab.mcp => 'MCP',
      _Tab.plugins => openHandPluginsLabel(context),
      _Tab.packages => openHandLocalizedText(
        context,
        zh: 'APP 信息',
        zhHant: 'APP 資訊',
        en: 'APP Info',
        fr: 'Infos APP',
        de: 'APP-Info',
        ja: 'APP 情報',
      ),
      _Tab.processes => openHandLocalizedText(
        context,
        zh: '进程',
        zhHant: '程序',
        en: 'Processes',
        fr: 'Processus',
        de: 'Prozesse',
        ja: 'プロセス',
      ),
      _Tab.logcat => 'Logcat',
      _Tab.frida => 'Frida',
      _Tab.network => openHandNetworkLabel(context),
      _Tab.staticAnalysis => openHandLocalizedText(
        context,
        zh: '静态分析',
        zhHant: '靜態分析',
        en: 'Static',
        fr: 'Statique',
        de: 'Statisch',
        ja: '静的解析',
      ),
      _Tab.certs => openHandLocalizedText(
        context,
        zh: '证书',
        zhHant: '憑證',
        en: 'Certs',
        fr: 'Certificats',
        de: 'Zertifikate',
        ja: '証明書',
      ),
      _Tab.crypto => openHandLocalizedText(
        context,
        zh: '加密',
        zhHant: '加密',
        en: 'Crypto',
        fr: 'Crypto',
        de: 'Krypto',
        ja: '暗号',
      ),
    };
  }

  IconData get icon => switch (this) {
    _Tab.devices => Icons.phone_android_rounded,
    _Tab.overview => Icons.dashboard_rounded,
    _Tab.toolchain => Icons.construction_rounded,
    _Tab.mcp => Icons.extension_rounded,
    _Tab.plugins => Icons.extension_outlined,
    _Tab.packages => Icons.apps_rounded,
    _Tab.processes => Icons.memory_rounded,
    _Tab.logcat => Icons.receipt_long_rounded,
    _Tab.frida => Icons.bug_report_rounded,
    _Tab.network => Icons.wifi_rounded,
    _Tab.staticAnalysis => Icons.code_rounded,
    _Tab.certs => Icons.verified_user_rounded,
    _Tab.crypto => Icons.lock_rounded,
  };
}

class _AndroidReverseDashboardDialog extends StatefulWidget {
  const _AndroidReverseDashboardDialog({
    required this.controller,
    required this.sessionId,
  });

  final AndroidReverseSessionController controller;
  final String sessionId;

  @override
  State<_AndroidReverseDashboardDialog> createState() =>
      _AndroidReverseDashboardDialogState();
}

class _AndroidReverseDashboardDialogState
    extends State<_AndroidReverseDashboardDialog>
    with FrameCoalescedRebuild<_AndroidReverseDashboardDialog> {
  _Tab _currentTab = _Tab.devices;
  late final AndroidReverseSessionController _ctrl;
  final _logcatLines = <String>[];
  final _logcatParseCache = <String, _ParsedLogcatLine>{};
  final _shellHistory = <String>[];
  Timer? _logcatTimer;
  final ScrollController _logcatScrollController = ScrollController();
  final TextEditingController _shellCtrl = TextEditingController();
  final TextEditingController _shellOutputCtrl = TextEditingController();
  final TextEditingController _wirelessEndpointCtrl = TextEditingController();
  final TextEditingController _forwardLocalCtrl = TextEditingController();
  final TextEditingController _forwardRemoteCtrl = TextEditingController();
  final TextEditingController _reverseDeviceCtrl = TextEditingController();
  final TextEditingController _reverseHostCtrl = TextEditingController();
  final TextEditingController _logcatFilterCtrl = TextEditingController();
  final TextEditingController _logcatPidCtrl = TextEditingController();
  final TextEditingController _installApkPathCtrl = TextEditingController();
  final TextEditingController _pushLocalCtrl = TextEditingController();
  final TextEditingController _pushRemoteCtrl = TextEditingController();
  final TextEditingController _pullRemoteCtrl = TextEditingController();
  final TextEditingController _pullLocalCtrl = TextEditingController();
  final TextEditingController _fridaScriptCtrl = TextEditingController();
  final TextEditingController _networkProxyHostCtrl = TextEditingController();
  final TextEditingController _networkProxyPortCtrl = TextEditingController();
  final TextEditingController _mitmCertPathCtrl = TextEditingController();
  final TextEditingController _base64Ctrl = TextEditingController();
  final TextEditingController _base64OutCtrl = TextEditingController();
  bool _loadingLogcat = false;
  bool _logcatRefreshQueued = false;
  bool _loadingPackages = false;
  bool _loadingProcesses = false;
  bool _packagesRefreshQueued = false;
  bool _processesRefreshQueued = false;
  bool _deviceDetailsRefreshQueued = false;
  bool _toolchainRefreshQueued = false;
  bool _loadingToolchain = false;
  bool _loadingPackageAnalysis = false;
  bool _capturingPackageReport = false;
  bool _runningShell = false;
  bool _runningDeviceAction = false;
  bool _runningStaticQuickScan = false;
  bool _runningStaticAction = false;
  bool _runningFridaDoctor = false;
  bool _runningFridaAction = false;
  bool _runningNetworkProbe = false;
  bool _runningNetworkAction = false;
  bool _runningCertificateAction = false;
  bool _writingNetworkAddon = false;
  bool _writingCertificateArtifacts = false;
  bool _writingMcpArtifacts = false;
  bool _makingEvidenceBundle = false;
  bool _capturingLogcatSnapshot = false;
  bool _clearingLogcat = false;
  bool _savingLogcatFile = false;
  bool _loadingDeviceDetails = false;
  bool _savingFridaScript = false;
  bool _logcatPackageFilterEnabled = false;
  bool _logcatAutoRefresh = false;
  bool _logcatStickToBottom = true;
  bool _didKickInitialRefresh = false;
  int _deviceContextGeneration = 0;
  int _fridaScriptRevision = 0;
  int _fridaSnippetLoadGeneration = 0;
  String? _selectedDeviceSerial;
  String? _lastDeviceActionOutput;
  AdbCommandResult? _lastShellResult;
  AdbCommandResult? _lastDeviceActionResult;
  AdbCommandResult? _lastToolchainCommandResult;
  String? _logcatError;
  String _logcatLevel = 'V';
  int _logcatCacheLimit = _kDefaultLogcatCacheLimit;
  int _logcatContextGeneration = 0;
  Map<String, String> _deviceProps = const <String, String>{};
  List<String> _forwardRows = const <String>[];
  List<String> _reverseRows = const <String>[];
  String? _deviceSnapshotOutput;
  List<String> _packages = const <String>[];
  List<AndroidReverseToolchainProbeResult> _toolchainRows =
      const <AndroidReverseToolchainProbeResult>[];
  final Set<String> _runningToolchainCommandIds = <String>{};
  List<AndroidProcess> _processes = const <AndroidProcess>[];
  String? _selectedPackageName;
  String? _pendingPackageAnalysis;
  String? _packageAnalysisOutput;
  String? _selectedFridaSnippetAsset;
  String? _lastSavedFridaScriptPath;
  String? _fridaArtifactOutput;
  String? _staticQuickScanOutput;
  String? _logcatArtifactOutput;
  String? _networkAddonOutput;
  String? _certificateArtifactOutput;
  String? _mcpArtifactOutput;
  String? _evidenceBundleOutput;
  String _cryptoCopyValue = '';
  final _processFilter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller;
    _logcatPackageFilterEnabled = (_ctrl.config.packageName ?? '')
        .trim()
        .isNotEmpty;
    _installApkPathCtrl.text = _ctrl.config.apkPath ?? '';
    _pushRemoteCtrl.text = '$kAndroidSdCardRoot/Download/';
    _pullRemoteCtrl.text = '$kAndroidSdCardRoot/Download/';
    _pullLocalCtrl.text = _ctrl.artifactsRootDir;
    _networkProxyHostCtrl.text = kAndroidEmulatorHostIp;
    _networkProxyPortCtrl.text = kDefaultMitmProxyPort.toString();
    _mitmCertPathCtrl.text = '~/.mitmproxy/mitmproxy-ca-cert.pem';
    _ctrl.addListener(_onControllerChanged);
    _fridaScriptCtrl.addListener(_onFridaScriptChanged);
    _logcatScrollController.addListener(_onLogcatScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didKickInitialRefresh) return;
    _didKickInitialRefresh = true;
    _refreshAll();
    unawaited(_refreshToolchain());
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _fridaScriptCtrl.removeListener(_onFridaScriptChanged);
    _logcatScrollController.removeListener(_onLogcatScroll);
    _logcatTimer?.cancel();
    _logcatScrollController.dispose();
    _shellCtrl.dispose();
    _shellOutputCtrl.dispose();
    _wirelessEndpointCtrl.dispose();
    _forwardLocalCtrl.dispose();
    _forwardRemoteCtrl.dispose();
    _reverseDeviceCtrl.dispose();
    _reverseHostCtrl.dispose();
    _logcatFilterCtrl.dispose();
    _logcatPidCtrl.dispose();
    _installApkPathCtrl.dispose();
    _pushLocalCtrl.dispose();
    _pushRemoteCtrl.dispose();
    _pullRemoteCtrl.dispose();
    _pullLocalCtrl.dispose();
    _fridaScriptCtrl.dispose();
    _networkProxyHostCtrl.dispose();
    _networkProxyPortCtrl.dispose();
    _mitmCertPathCtrl.dispose();
    _base64Ctrl.dispose();
    _base64OutCtrl.dispose();
    _processFilter.dispose();
    super.dispose();
  }

  void _onControllerChanged() => scheduleCoalescedRebuild();

  void _onFridaScriptChanged() {
    if (!mounted) return;
    _fridaScriptRevision += 1;
    _lastSavedFridaScriptPath = null;
    setState(() {});
  }

  void _onLogcatScroll() {
    if (!_logcatScrollController.hasClients) return;
    final position = _logcatScrollController.position;
    final distanceToBottom = position.maxScrollExtent - position.pixels;
    final shouldStick = distanceToBottom <= 72;
    if (_logcatStickToBottom == shouldStick) return;
    _logcatStickToBottom = shouldStick;
  }

  void _setLogcatAutoRefresh(bool enabled) {
    if (_logcatAutoRefresh == enabled) return;
    setState(() => _logcatAutoRefresh = enabled);
    _logcatTimer?.cancel();
    _logcatTimer = null;
    if (!enabled) return;
    _logcatStickToBottom = true;
    unawaited(_fetchLogcat(append: _logcatLines.isNotEmpty, silent: true));
    _logcatTimer = startNonOverlappingPeriodicTimer(
      _kLogcatAutoRefreshInterval,
      (_) async {
        if (!mounted || !_logcatAutoRefresh || _loadingLogcat) return;
        await _fetchLogcat(append: true, silent: true);
      },
    );
  }

  void _scheduleLogcatFollowScroll({bool force = false}) {
    if (!force && !_logcatStickToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_logcatScrollController.hasClients) return;
      final position = _logcatScrollController.position;
      final target = position.maxScrollExtent;
      if ((target - position.pixels).abs() < 2) return;
      _logcatScrollController.animateTo(
        target,
        duration: _kLogcatFollowScrollDuration,
        curve: kOpenHandSwitchInCurve,
      );
    });
  }

  String? get _targetSerial {
    final selected = _selectedDeviceSerial?.trim();
    if (selected != null && selected.isNotEmpty) return selected;
    final configured = _ctrl.config.deviceSerial?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return _ctrl.connectedDevice?.serial;
  }

  _AndroidTargetContext _captureAndroidTargetContext() {
    return (
      generation: _deviceContextGeneration,
      serial: _targetSerial?.trim(),
      packageName: _logcatPackageTarget(),
    );
  }

  bool _isCurrentAndroidTargetContext(
    _AndroidTargetContext? target, {
    bool includePackage = true,
  }) {
    if (!mounted) return false;
    if (target == null) return true;
    if (target.generation != _deviceContextGeneration ||
        target.serial != _targetSerial?.trim()) {
      return false;
    }
    return !includePackage || target.packageName == _logcatPackageTarget();
  }

  bool _isCurrentFridaScriptContext(
    _AndroidTargetContext target,
    int scriptRevision,
  ) {
    return scriptRevision == _fridaScriptRevision &&
        _isCurrentAndroidTargetContext(target);
  }

  _StaticAnalysisContext _captureStaticAnalysisContext() {
    final apkPath = _ctrl.config.apkPath?.trim();
    return (
      apkPath: apkPath == null || apkPath.isEmpty ? null : apkPath,
      packageName: _logcatPackageTarget(),
    );
  }

  bool _isCurrentStaticAnalysisContext(_StaticAnalysisContext target) {
    if (!mounted) return false;
    final current = _captureStaticAnalysisContext();
    return target.apkPath == current.apkPath &&
        target.packageName == current.packageName;
  }

  void _setTargetDevice(
    String? serial, {
    bool preserveDeviceActionOutput = false,
  }) {
    final normalized = serial?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_selectedDeviceSerial == next) return;
    _deviceContextGeneration += 1;
    _pendingPackageAnalysis = null;
    setState(() {
      _selectedDeviceSerial = next;
      _selectedPackageName = null;
      _packages = const <String>[];
      _processes = const <AndroidProcess>[];
      _deviceProps = const <String, String>{};
      _forwardRows = const <String>[];
      _reverseRows = const <String>[];
      _deviceSnapshotOutput = null;
      _packageAnalysisOutput = null;
      _logcatContextGeneration += 1;
      _logcatLines.clear();
      _logcatParseCache.clear();
      _logcatError = null;
      _logcatArtifactOutput = null;
      _lastShellResult = null;
      _shellOutputCtrl.clear();
      _fridaArtifactOutput = null;
      _networkAddonOutput = null;
      _certificateArtifactOutput = null;
      if (!preserveDeviceActionOutput) {
        _lastDeviceActionResult = null;
        _lastDeviceActionOutput = null;
      }
    });
  }

  void _refreshAll() {
    unawaited(_doRefreshDevices());
    unawaited(_doRefreshPackages());
    unawaited(_doRefreshProcesses());
    unawaited(_refreshDeviceDetails());
  }

  Future<void> _refreshToolchain() async {
    if (_loadingToolchain) {
      _toolchainRefreshQueued = true;
      return;
    }
    _toolchainRefreshQueued = false;
    setState(() => _loadingToolchain = true);
    try {
      final rows = await probeAndroidReverseToolchain();
      if (!mounted || _toolchainRefreshQueued) return;
      setState(() => _toolchainRows = rows);
    } finally {
      if (mounted) {
        final shouldRefreshAgain = _toolchainRefreshQueued;
        _toolchainRefreshQueued = false;
        setState(() => _loadingToolchain = false);
        if (shouldRefreshAgain) unawaited(_refreshToolchain());
      }
    }
  }

  Future<void> _doRefreshDevices() async {
    await _ctrl.refreshDevices();
    if (!mounted) return;
    final selected = _selectedDeviceSerial;
    if (selected != null &&
        !_ctrl.allDevices.any((device) => device.serial == selected)) {
      _setTargetDevice(null, preserveDeviceActionOutput: true);
    }
  }

  Future<void> _doRefreshPackages() async {
    if (_loadingPackages) {
      _packagesRefreshQueued = true;
      return;
    }
    _packagesRefreshQueued = false;
    final serial = _targetSerial;
    setState(() => _loadingPackages = true);
    try {
      final pkgs = await _ctrl.listPackages(serial: serial);
      if (!mounted || _packagesRefreshQueued || serial != _targetSerial) {
        return;
      }
      setState(() {
        _packages = pkgs;
        if (_selectedPackageName != null &&
            !pkgs.contains(_selectedPackageName)) {
          _pendingPackageAnalysis = null;
          _selectedPackageName = null;
          _packageAnalysisOutput = null;
        }
      });
    } catch (error, stack) {
      if (mounted && !_packagesRefreshQueued && serial == _targetSerial) {
        silentLog('android_reverse_dashboard', '刷新应用列表', error, stack);
      }
    } finally {
      if (mounted) {
        final shouldRefreshAgain =
            _packagesRefreshQueued || serial != _targetSerial;
        _packagesRefreshQueued = false;
        setState(() => _loadingPackages = false);
        if (shouldRefreshAgain) unawaited(_doRefreshPackages());
      }
    }
  }

  Future<void> _analyzePackage(String packageName) async {
    if (_loadingPackageAnalysis || _capturingPackageReport) {
      _pendingPackageAnalysis = packageName;
      setState(() {
        _selectedPackageName = packageName;
        _packageAnalysisOutput = null;
      });
      return;
    }
    _pendingPackageAnalysis = null;
    final serial = _targetSerial;
    setState(() {
      _selectedPackageName = packageName;
      _packageAnalysisOutput = null;
      _loadingPackageAnalysis = true;
    });
    try {
      final pathFuture = _ctrl.getPackagePath(packageName, serial: serial);
      final versionFuture = _ctrl.getPackageVersion(
        packageName,
        serial: serial,
      );
      final launcherFuture = _ctrl.resolveLauncherActivity(
        packageName,
        serial: serial,
      );
      final dumpsysFuture = _ctrl.shellDetailed(
        'dumpsys package $packageName',
        serial: serial,
        timeout: _kPackageDumpsysTimeout,
      );
      final path = await pathFuture;
      final version = await versionFuture;
      final launcher = await launcherFuture;
      final dumpsys = await dumpsysFuture;
      if (!mounted ||
          _pendingPackageAnalysis != null ||
          serial != _targetSerial ||
          packageName != _selectedPackageName) {
        return;
      }
      final summary = _summarizePackageDumpsys(dumpsys.stdout);
      final buf = StringBuffer()
        ..writeln(
          '${openHandLocalizedText(context, zh: "包名", zhHant: "套件名稱", en: "Package", fr: "Package", de: "Paket", ja: "パッケージ")}: $packageName',
        )
        ..writeln(
          '${openHandLocalizedText(context, zh: "安装路径", zhHant: "安裝路徑", en: "APK path", fr: "Chemin APK", de: "APK-Pfad", ja: "APK パス")}: ${path ?? "-"}',
        )
        ..writeln(
          '${openHandLocalizedText(context, zh: "版本", zhHant: "版本", en: "Version", fr: "Version", de: "Version", ja: "バージョン")}: ${version ?? "-"}',
        )
        ..writeln(
          '${openHandLocalizedText(context, zh: "启动入口", zhHant: "啟動入口", en: "Launcher", fr: "Lanceur", de: "Launcher", ja: "ランチャー")}: ${launcher ?? "-"}',
        )
        ..writeln()
        ..writeln(
          openHandLocalizedText(
            context,
            zh: 'dumpsys 摘要:',
            zhHant: 'dumpsys 摘要:',
            en: 'dumpsys summary:',
            fr: 'Résumé dumpsys :',
            de: 'dumpsys-Zusammenfassung:',
            ja: 'dumpsys 要約:',
          ),
        )
        ..write(
          summary.isEmpty
              ? openHandLocalizedText(
                  context,
                  zh: '(无输出)',
                  zhHant: '（無輸出）',
                  en: '(no output)',
                  fr: '(aucune sortie)',
                  de: '(keine Ausgabe)',
                  ja: '（出力なし）',
                )
              : summary,
        );
      if (dumpsys.timedOut) {
        buf
          ..writeln()
          ..writeln(
            openHandLocalizedText(
              context,
              zh: '(dumpsys 已超时，已展示可用输出)',
              zhHant: '（dumpsys 已逾時，已顯示可用輸出）',
              en: '(dumpsys timed out; usable output shown)',
              fr: '(dumpsys a expiré ; sortie disponible affichée)',
              de: '(dumpsys-Timeout; verfügbare Ausgabe wird angezeigt)',
              ja: '（dumpsys がタイムアウトしました。利用可能な出力を表示しています）',
            ),
          );
      }
      final err = dumpsys.stderr.trim();
      if (!dumpsys.ok && err.isNotEmpty) {
        buf
          ..writeln()
          ..writeln(
            '${openHandLocalizedText(context, zh: "错误", zhHant: "錯誤", en: "Error", fr: "Erreur", de: "Fehler", ja: "エラー")}: $err',
          );
      }
      setState(() => _packageAnalysisOutput = buf.toString());
    } finally {
      if (mounted) {
        final pending = _pendingPackageAnalysis;
        _pendingPackageAnalysis = null;
        setState(() => _loadingPackageAnalysis = false);
        if (pending != null) unawaited(_analyzePackage(pending));
      }
    }
  }

  Future<void> _capturePackageReport(String packageName) async {
    if (_capturingPackageReport || _loadingPackageAnalysis) return;
    _pendingPackageAnalysis = null;
    final serial = _targetSerial;
    setState(() {
      _selectedPackageName = packageName;
      _packageAnalysisOutput = null;
      _capturingPackageReport = true;
    });
    try {
      final result = await _ctrl.capturePackageReportToArtifacts(
        packageName,
        serial: serial,
      );
      if (!mounted) return;
      final isCurrentTarget =
          serial == _targetSerial && packageName == _selectedPackageName;
      if (!isCurrentTarget) return;
      setState(() => _packageAnalysisOutput = _formatAdbResult(result));
      if (result.ok || result.partialOk) {
        _showSnack(
          openHandLocalizedText(
            context,
            zh: '已生成 APP 信息报告工件。',
            zhHant: '已產生 APP 資訊報告工件。',
            en: 'APP report artifacts saved.',
            fr: 'Artefacts du rapport APP enregistrés.',
            de: 'APP-Berichtsartefakte gespeichert.',
            ja: 'APP レポート成果物を保存しました。',
          ),
          kind: OpenHandSnackKind.success,
          duration: kOpenHandSnackBarNormalDuration,
        );
      }
    } catch (error) {
      if (!mounted ||
          serial != _targetSerial ||
          packageName != _selectedPackageName) {
        return;
      }
      setState(() {
        _packageAnalysisOutput =
            '${openHandLocalizedText(context, zh: "生成 APP 信息报告失败", zhHant: "產生 APP 資訊報告失敗", en: "Failed to generate APP report", fr: "Échec de génération du rapport APP", de: "APP-Bericht konnte nicht erstellt werden", ja: "APP レポートの生成に失敗しました")}: $error';
      });
    } finally {
      if (mounted) {
        final pending = _pendingPackageAnalysis;
        _pendingPackageAnalysis = null;
        setState(() => _capturingPackageReport = false);
        if (pending != null) unawaited(_analyzePackage(pending));
      }
    }
  }

  String _summarizePackageDumpsys(String raw) {
    final summary = <String>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final isSectionHeader =
          trimmed == 'requested permissions:' ||
          trimmed == 'install permissions:' ||
          trimmed == 'runtime permissions:' ||
          trimmed == 'PackageSignatures{' ||
          trimmed.startsWith('SigningDetails');
      final isKeyLine =
          trimmed.startsWith('versionCode=') ||
          trimmed.startsWith('versionName=') ||
          trimmed.startsWith('targetSdk=') ||
          trimmed.startsWith('firstInstallTime=') ||
          trimmed.startsWith('lastUpdateTime=') ||
          trimmed.startsWith('signatures=') ||
          trimmed.startsWith('pkgFlags=') ||
          trimmed.startsWith('privateFlags=') ||
          trimmed.startsWith('User 0:');
      final isPermissionLine = trimmed.startsWith('android.permission.');
      if (isSectionHeader || isKeyLine || isPermissionLine) {
        summary.add(trimmed);
      }
      if (summary.length >= _kPackageDumpsysSummaryMaxLines) break;
    }
    if (summary.isEmpty && raw.trim().isNotEmpty) {
      return trimRightNonEmptyLines(
        raw.split('\n'),
        limit: _kPackageDumpsysSummaryMaxLines,
      ).join('\n');
    }
    return summary.join('\n');
  }

  Future<void> _doRefreshProcesses() async {
    if (_loadingProcesses) {
      _processesRefreshQueued = true;
      return;
    }
    _processesRefreshQueued = false;
    final serial = _targetSerial;
    setState(() => _loadingProcesses = true);
    try {
      final filter = _processFilter.text.trim().isEmpty
          ? null
          : _processFilter.text.trim();
      final procs = await _ctrl.refreshProcesses(
        filterName: filter,
        serial: serial,
      );
      if (!mounted || _processesRefreshQueued || serial != _targetSerial) {
        return;
      }
      setState(() => _processes = procs);
    } catch (error, stack) {
      if (mounted && !_processesRefreshQueued && serial == _targetSerial) {
        silentLog('android_reverse_dashboard', '刷新进程列表', error, stack);
      }
    } finally {
      if (mounted) {
        final shouldRefreshAgain =
            _processesRefreshQueued || serial != _targetSerial;
        _processesRefreshQueued = false;
        setState(() => _loadingProcesses = false);
        if (shouldRefreshAgain) unawaited(_doRefreshProcesses());
      }
    }
  }

  Future<void> _refreshDeviceDetails() async {
    if (_loadingDeviceDetails) {
      _deviceDetailsRefreshQueued = true;
      return;
    }
    _deviceDetailsRefreshQueued = false;
    final serial = _targetSerial;
    if (serial == null || serial.isEmpty) {
      if (mounted) {
        setState(() {
          _deviceProps = const <String, String>{};
          _forwardRows = const <String>[];
          _reverseRows = const <String>[];
          _deviceSnapshotOutput = null;
        });
      }
      return;
    }
    setState(() => _loadingDeviceDetails = true);
    try {
      final propsFuture = _ctrl.getProperties(serial: serial);
      final forwardsFuture = _ctrl.listForwards(serial: serial);
      final reversesFuture = _ctrl.listReverses(serial: serial);
      final snapshotFuture = _ctrl.shellDetailed(
        _kDeviceSnapshotScript,
        serial: serial,
        timeout: _kDeviceSnapshotTimeout,
      );
      final props = await propsFuture;
      final forwards = await forwardsFuture;
      final reverses = await reversesFuture;
      final snapshot = await snapshotFuture;
      if (!mounted || _deviceDetailsRefreshQueued || serial != _targetSerial) {
        return;
      }
      setState(() {
        _deviceProps = props;
        _forwardRows = splitTrimmedNonEmpty(forwards ?? '', separator: '\n');
        _reverseRows = splitTrimmedNonEmpty(reverses ?? '', separator: '\n');
        _deviceSnapshotOutput = _formatDeviceSnapshot(snapshot);
      });
    } catch (error) {
      if (!mounted || _deviceDetailsRefreshQueued || serial != _targetSerial) {
        return;
      }
      setState(() {
        _deviceSnapshotOutput = openHandLocalizedText(
          context,
          zh: '刷新设备详情失败：$error',
          zhHant: '重新整理裝置詳情失敗：$error',
          en: 'Failed to refresh device details: $error',
          fr: 'Échec d’actualisation des détails appareil : $error',
          de: 'Gerätedetails konnten nicht aktualisiert werden: $error',
          ja: 'デバイス詳細の更新に失敗しました: $error',
        );
      });
    } finally {
      if (mounted) {
        final shouldRefreshAgain =
            _deviceDetailsRefreshQueued || serial != _targetSerial;
        _deviceDetailsRefreshQueued = false;
        setState(() => _loadingDeviceDetails = false);
        if (shouldRefreshAgain) unawaited(_refreshDeviceDetails());
      }
    }
  }

  String? _formatDeviceSnapshot(AdbCommandResult result) {
    final lines = trimRightNonEmptyLines(
      result.stdout.split('\n'),
      limit: _kDeviceSnapshotMaxLines,
    );
    final stderr = result.stderr.trim();
    if (lines.isEmpty && stderr.isEmpty) return null;
    final buffer = StringBuffer();
    if (lines.isNotEmpty) {
      buffer.write(lines.join('\n'));
    }
    if (result.timedOut) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(
        openHandLocalizedText(
          context,
          zh: '(设备现场读取超时，已展示可用输出)',
          zhHant: '（裝置現場讀取逾時，已顯示可用輸出）',
          en: '(snapshot timed out; usable output shown)',
          fr: '(snapshot expiré ; sortie disponible affichée)',
          de: '(Snapshot-Timeout; verfügbare Ausgabe wird angezeigt)',
          ja: '（スナップショットがタイムアウトしました。利用可能な出力を表示しています）',
        ),
      );
    }
    if (!result.ok && stderr.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(
        '${openHandLocalizedText(context, zh: "错误", zhHant: "錯誤", en: "Error", fr: "Erreur", de: "Fehler", ja: "エラー")}: $stderr',
      );
    }
    return buffer.toString().trimRight();
  }

  Future<void> _fetchLogcat({bool append = false, bool silent = false}) async {
    if (_loadingLogcat || _clearingLogcat) {
      _logcatRefreshQueued = true;
      return;
    }
    _logcatRefreshQueued = false;
    final query = _captureLogcatQueryContext();
    setState(() {
      _loadingLogcat = true;
      if (!silent) _logcatError = null;
    });
    try {
      final pidFilter = await _resolveLogcatPidFilter(query);
      if (!mounted || !_isCurrentLogcatQueryContext(query)) return;
      final result = await _ctrl.logcatDetailed(
        lines: append ? _kAutoLogcatLines : _kDefaultLogcatLines,
        tag: query.tag.isEmpty ? null : query.tag,
        level: query.level,
        pid: pidFilter.pid,
        serial: query.serial,
      );
      if (mounted && _isCurrentLogcatQueryContext(query)) {
        final incoming = result.stdout
            .split('\n')
            .map(_sanitizeLogcatLine)
            .where(_hasVisibleLogcatText)
            .toList(growable: false);
        final err = result.stderr.trim();
        final added = append
            ? _appendLogcatTail(incoming)
            : _replaceLogcatLines(incoming);
        setState(() {
          if (incoming.isNotEmpty && result.timedOut) {
            _logcatError = openHandLocalizedText(
              context,
              zh: 'Logcat 读取超时，已展示可用输出。',
              zhHant: 'Logcat 讀取逾時，已顯示可用輸出。',
              en: 'Logcat timed out; usable output is shown.',
              fr: 'Logcat a expiré ; la sortie disponible est affichée.',
              de: 'Logcat-Timeout; verfügbare Ausgabe wird angezeigt.',
              ja: 'Logcat の読み取りがタイムアウトしました。利用可能な出力を表示しています。',
            );
          } else if (incoming.isNotEmpty && pidFilter.notice != null) {
            _logcatError = pidFilter.notice;
          } else if (incoming.isNotEmpty) {
            if (!silent || added > 0) _logcatError = null;
          } else if (err.isNotEmpty) {
            _logcatError = err;
          } else if (!silent && !append) {
            _logcatError = openHandLocalizedText(
              context,
              zh: '没有读取到 Logcat 输出。请确认设备在线，或清空 Tag 过滤后重试。',
              zhHant: '沒有讀取到 Logcat 輸出。請確認裝置在線，或清空 Tag 篩選後重試。',
              en: 'No Logcat output was read. Check the device or clear the tag filter and retry.',
              fr: 'Aucune sortie Logcat lue. Vérifiez l’appareil ou effacez le filtre Tag puis réessayez.',
              de: 'Keine Logcat-Ausgabe gelesen. Prüfen Sie das Gerät oder leeren Sie den Tag-Filter und versuchen Sie es erneut.',
              ja: 'Logcat 出力を読み取れませんでした。デバイスを確認するか Tag フィルターをクリアして再試行してください。',
            );
          }
        });
        if (added > 0 || !append) {
          _scheduleLogcatFollowScroll(force: !append || _logcatAutoRefresh);
        }
      }
    } catch (error) {
      if (!mounted || !_isCurrentLogcatQueryContext(query)) return;
      setState(() {
        if (!append) _logcatLines.clear();
        if (!silent || !append) _logcatError = '$error';
      });
    } finally {
      if (mounted) {
        final shouldRefreshAgain = _logcatRefreshQueued;
        _logcatRefreshQueued = false;
        setState(() => _loadingLogcat = false);
        if (shouldRefreshAgain) unawaited(_fetchLogcat());
      }
    }
  }

  _LogcatQueryContext _captureLogcatQueryContext() {
    return (
      generation: _logcatContextGeneration,
      serial: _targetSerial,
      tag: _logcatFilterCtrl.text.trim(),
      level: _logcatLevel,
      explicitPid: _logcatPidCtrl.text.trim(),
      packageName: _logcatPackageFilterEnabled ? _logcatPackageTarget() : null,
    );
  }

  bool _isCurrentLogcatQueryContext(_LogcatQueryContext query) {
    if (!mounted || query.generation != _logcatContextGeneration) {
      return false;
    }
    return query.serial == _targetSerial &&
        query.tag == _logcatFilterCtrl.text.trim() &&
        query.level == _logcatLevel &&
        query.explicitPid == _logcatPidCtrl.text.trim() &&
        query.packageName ==
            (_logcatPackageFilterEnabled ? _logcatPackageTarget() : null);
  }

  int _replaceLogcatLines(List<String> lines) {
    _logcatLines
      ..clear()
      ..addAll(_trimLogcatBuffer(lines));
    _compactLogcatParseCache();
    return _logcatLines.length;
  }

  int _appendLogcatTail(List<String> incoming) {
    if (incoming.isEmpty) return 0;
    if (_logcatLines.isEmpty) {
      _logcatLines.addAll(_trimLogcatBuffer(incoming));
      return _logcatLines.length;
    }
    final overlap = _tailHeadOverlap(_logcatLines, incoming);
    final additions = incoming.skip(overlap).toList(growable: false);
    if (additions.isEmpty) return 0;
    _logcatLines.addAll(additions);
    final overflow = _logcatLines.length - _logcatCacheLimit;
    if (overflow > 0) {
      _logcatLines.removeRange(0, overflow);
    }
    _compactLogcatParseCache();
    return additions.length;
  }

  List<String> _trimLogcatBuffer(List<String> lines) {
    if (lines.length <= _logcatCacheLimit) return lines;
    return lines.sublist(lines.length - _logcatCacheLimit);
  }

  void _compactLogcatParseCache() {
    final maxCacheSize = _logcatCacheLimit * 3;
    if (_logcatParseCache.length <= maxCacheSize) return;
    final visible = _logcatLines.toSet();
    _logcatParseCache.removeWhere((line, _) => !visible.contains(line));
  }

  int _tailHeadOverlap(List<String> existing, List<String> incoming) {
    final max = existing.length < incoming.length
        ? existing.length
        : incoming.length;
    for (var len = max; len > 0; len--) {
      var matched = true;
      for (var i = 0; i < len; i++) {
        if (existing[existing.length - len + i] != incoming[i]) {
          matched = false;
          break;
        }
      }
      if (matched) return len;
    }
    return 0;
  }

  Future<void> _clearLogcat() async {
    if (_clearingLogcat || _capturingLogcatSnapshot) return;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '清空 Logcat？',
        zhHant: '清空 Logcat？',
        en: 'Clear Logcat?',
        fr: 'Effacer Logcat ?',
        de: 'Logcat leeren?',
        ja: 'Logcat をクリアしますか？',
      ),
      message: openHandLocalizedText(
        context,
        zh: '将清空当前面板日志，并尝试清空设备 Logcat 缓冲区。自动刷新开启时会继续读取清空后的新日志。',
        zhHant: '將清空目前面板日誌，並嘗試清空裝置 Logcat 緩衝區。自動重新整理開啟時會繼續讀取清空後的新日誌。',
        en: 'This clears the panel logs and tries to clear the device logcat buffer. Auto refresh will continue reading new logs afterwards.',
        fr: 'Efface les journaux du panneau et tente de vider le tampon Logcat de l’appareil. L’actualisation automatique continuera à lire les nouveaux journaux.',
        de: 'Leert die Panel-Logs und versucht, den Logcat-Puffer des Geräts zu leeren. Auto-Aktualisierung liest danach weiter neue Logs.',
        ja: '現在のパネルログを消去し、デバイスの Logcat バッファーもクリアします。自動更新が有効な場合は新しいログを読み続けます。',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandClearLabel(context),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _clearingLogcat = true;
      _logcatLines.clear();
      _logcatParseCache.clear();
      _logcatContextGeneration++;
      _logcatError = openHandLocalizedText(
        context,
        zh: '正在清空设备 Logcat...',
        zhHant: '正在清空裝置 Logcat...',
        en: 'Clearing device logcat...',
        fr: 'Effacement du Logcat de l’appareil...',
        de: 'Geräte-Logcat wird geleert...',
        ja: 'デバイス Logcat をクリアしています...',
      );
    });
    final query = _captureLogcatQueryContext();
    try {
      final result = await _ctrl.clearLogcatDetailed(serial: query.serial);
      if (!mounted || !_isCurrentLogcatQueryContext(query)) return;
      setState(() {
        _logcatError = result.ok
            ? openHandLocalizedText(
                context,
                zh: '已清空设备 Logcat。',
                zhHant: '已清空裝置 Logcat。',
                en: 'Device logcat was cleared.',
                fr: 'Logcat de l’appareil effacé.',
                de: 'Geräte-Logcat wurde geleert.',
                ja: 'デバイス Logcat をクリアしました。',
              )
            : _formatAdbResult(result);
      });
    } catch (error) {
      if (!mounted || !_isCurrentLogcatQueryContext(query)) return;
      setState(() {
        _logcatError =
            '${openHandLocalizedText(context, zh: "清空 Logcat 失败", zhHant: "清空 Logcat 失敗", en: "Failed to clear logcat", fr: "Échec de l’effacement de Logcat", de: "Logcat konnte nicht geleert werden", ja: "Logcat のクリアに失敗しました")}: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _clearingLogcat = false);
        if (_logcatRefreshQueued && !_loadingLogcat) {
          _logcatRefreshQueued = false;
          unawaited(_fetchLogcat());
        }
      }
    }
  }

  String _sanitizeLogcatLine(String line) {
    return line
        .replaceAll(
          RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'),
          '',
        )
        .trimRight();
  }

  bool _hasVisibleLogcatText(String line) {
    return line.replaceAll(kInlineWhitespacePattern, '').isNotEmpty;
  }

  _ParsedLogcatLine _parseLogcatLine(String raw) {
    final line = raw.trimRight();
    final timeMatch = RegExp(
      r'^(\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+)\s+(\d+)\s+(\d+)\s+([VDIWEF])\s+([^:]+):\s?(.*)$',
    ).firstMatch(line);
    if (timeMatch != null) {
      return _ParsedLogcatLine(
        raw: line,
        level: timeMatch.group(4),
        time: timeMatch.group(1),
        pid: timeMatch.group(2),
        tid: timeMatch.group(3),
        tag: timeMatch.group(5)?.trim(),
        message: timeMatch.group(6)?.trimRight() ?? '',
      );
    }
    final briefMatch = RegExp(
      r'^([VDIWEF])\/([^(]+)\(\s*(\d+)\):\s?(.*)$',
    ).firstMatch(line);
    if (briefMatch != null) {
      return _ParsedLogcatLine(
        raw: line,
        level: briefMatch.group(1),
        pid: briefMatch.group(3),
        tag: briefMatch.group(2)?.trim(),
        message: briefMatch.group(4)?.trimRight() ?? '',
      );
    }
    return _ParsedLogcatLine(
      raw: line,
      level: _fallbackLogcatLevel(line),
      message: line,
    );
  }

  String? _fallbackLogcatLevel(String line) {
    final spaced = RegExp(r'\s([VDIWEF])\s').firstMatch(line);
    if (spaced != null) return spaced.group(1);
    final slash = RegExp(r'\b([VDIWEF])\/').firstMatch(line);
    return slash?.group(1);
  }

  _ParsedLogcatLine _parseCachedLogcatLine(String raw) {
    return _logcatParseCache.putIfAbsent(raw, () => _parseLogcatLine(raw));
  }

  String _logcatLevelOptionLabel(String level, BuildContext context) {
    return switch (level) {
      'V' => openHandLocalizedText(
        context,
        zh: '详细',
        zhHant: '詳細',
        en: 'Verbose',
        fr: 'Verbeux',
        de: 'Ausführlich',
        ja: '詳細',
      ),
      'D' => openHandLocalizedText(
        context,
        zh: '调试',
        zhHant: '除錯',
        en: 'Debug',
        fr: 'Débogage',
        de: 'Debug',
        ja: 'デバッグ',
      ),
      'I' => openHandLocalizedText(
        context,
        zh: '信息',
        zhHant: '資訊',
        en: 'Info',
        fr: 'Info',
        de: 'Info',
        ja: '情報',
      ),
      'W' => openHandWarningLabel(context),
      'E' => openHandErrorLabel(context),
      'F' => openHandLocalizedText(
        context,
        zh: '致命',
        zhHant: '致命',
        en: 'Fatal',
        fr: 'Fatal',
        de: 'Fatal',
        ja: '致命的',
      ),
      _ => level,
    };
  }

  Future<void> _showLogcatLineMenu(
    int index,
    String line,
    Offset position,
  ) async {
    if (!mounted) return;
    final selected = await showAnimatedPointerMenu<_LogcatLineAction>(
      context: context,
      globalPosition: position,
      items: [
        PopupMenuItem<_LogcatLineAction>(
          value: _LogcatLineAction.copy,
          child: Row(
            children: [
              const Icon(Icons.copy_rounded, size: 16),
              kOpenHandHGap8,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '复制日志',
                  zhHant: '複製日誌',
                  en: 'Copy log',
                  fr: 'Copier le log',
                  de: 'Log kopieren',
                  ja: 'ログをコピー',
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<_LogcatLineAction>(
          value: _LogcatLineAction.delete,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              kOpenHandHGap8,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '删除此条',
                  zhHant: '刪除此列',
                  en: 'Delete row',
                  fr: 'Supprimer la ligne',
                  de: 'Zeile löschen',
                  ja: 'この行を削除',
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case _LogcatLineAction.copy:
        await _copyText(line);
      case _LogcatLineAction.delete:
        if (index < 0 || index >= _logcatLines.length) return;
        setState(() {
          _logcatLines.removeAt(index);
          _logcatContextGeneration++;
          _compactLogcatParseCache();
        });
    }
  }

  Future<void> _saveLogcatSnapshot() async {
    if (_logcatLines.isEmpty || _savingLogcatFile) return;
    final lineCount = _logcatLines.length;
    final content = '${_logcatLines.join('\n')}\n';
    setState(() => _savingLogcatFile = true);
    String? path;
    Object? failure;
    try {
      path = await _saveTextWithPicker(
        suggestedName: 'openhand-logcat-${_fileTimestamp()}.log',
        typeLabel: 'LOG',
        extensions: const <String>['log', 'txt'],
        content: content,
      );
    } catch (error) {
      failure = error;
    } finally {
      if (mounted) setState(() => _savingLogcatFile = false);
    }
    if (!mounted) return;
    if (failure != null) {
      _showSnack(
        '${openHandLocalizedText(context, zh: "保存 Logcat 失败", zhHant: "儲存 Logcat 失敗", en: "Failed to save Logcat", fr: "Échec de l’enregistrement Logcat", de: "Logcat konnte nicht gespeichert werden", ja: "Logcat の保存に失敗しました")}: $failure',
      );
    } else if (path != null) {
      _showSnack(
        openHandLocalizedText(
          context,
          zh: '已保存 $lineCount 行到 $path',
          zhHant: '已儲存 $lineCount 行到 $path',
          en: 'Saved $lineCount lines to $path',
          fr: '$lineCount lignes enregistrées dans $path',
          de: '$lineCount Zeilen in $path gespeichert',
          ja: '$lineCount 行を $path に保存しました',
        ),
      );
    }
  }

  Future<void> _captureLogcatArtifactSnapshot() async {
    if (_capturingLogcatSnapshot || _clearingLogcat) return;
    final query = _captureLogcatQueryContext();
    setState(() {
      _capturingLogcatSnapshot = true;
      _logcatArtifactOutput = null;
    });
    try {
      final pidFilter = await _resolveLogcatPidFilter(query);
      if (!mounted || !_isCurrentLogcatQueryContext(query)) return;
      final result = await _ctrl.captureLogcatSnapshotToArtifacts(
        tag: query.tag.isEmpty ? null : query.tag,
        level: query.level,
        pid: pidFilter.pid,
        packageName: pidFilter.packageName,
        serial: query.serial,
        lines: _kDefaultLogcatLines,
      );
      if (!mounted || !_isCurrentLogcatQueryContext(query)) return;
      final formattedResult = _formatAdbResult(result);
      setState(() {
        _logcatArtifactOutput = <String>[
          if (pidFilter.notice != null) pidFilter.notice!,
          if (formattedResult.trim().isNotEmpty) formattedResult,
        ].join('\n\n');
        if (pidFilter.notice != null) {
          _logcatError = pidFilter.notice;
        } else if (!result.ok && !result.partialOk) {
          _logcatError = _logcatArtifactOutput;
        }
      });
      if (result.ok || result.partialOk) {
        _showSnack(
          openHandLocalizedText(
            context,
            zh: '已生成 Logcat 快照工件。',
            zhHant: '已產生 Logcat 快照工件。',
            en: 'Logcat snapshot artifacts saved.',
            fr: 'Artefacts du snapshot Logcat enregistrés.',
            de: 'Logcat-Snapshot-Artefakte gespeichert.',
            ja: 'Logcat スナップショット成果物を保存しました。',
          ),
          kind: OpenHandSnackKind.success,
          duration: kOpenHandSnackBarNormalDuration,
        );
      }
    } catch (error) {
      if (!mounted || !_isCurrentLogcatQueryContext(query)) return;
      setState(() {
        _logcatArtifactOutput =
            '${openHandLocalizedText(context, zh: "生成 Logcat 快照失败", zhHant: "產生 Logcat 快照失敗", en: "Failed to capture Logcat snapshot", fr: "Échec de capture du snapshot Logcat", de: "Logcat-Snapshot konnte nicht erstellt werden", ja: "Logcat スナップショットの取得に失敗しました")}: $error';
        _logcatError = _logcatArtifactOutput;
      });
    } finally {
      if (mounted) setState(() => _capturingLogcatSnapshot = false);
    }
  }

  Future<({String? pid, String? notice, String? packageName})>
  _resolveLogcatPidFilter(_LogcatQueryContext query) async {
    final explicitPid = query.explicitPid;
    final packageName = query.packageName;
    final explicitPidValid = RegExp(r'^\d+$').hasMatch(explicitPid);
    if (explicitPidValid) {
      return (pid: explicitPid, notice: null, packageName: packageName);
    }
    if (explicitPid.isNotEmpty) {
      return (
        pid: null,
        notice: openHandLocalizedText(
          context,
          zh: 'PID 只能填写数字，已忽略该 PID 过滤。',
          zhHant: 'PID 只能填寫數字，已忽略該 PID 篩選。',
          en: 'PID must be numeric; PID filter was ignored.',
          fr: 'Le PID doit être numérique ; le filtre PID a été ignoré.',
          de: 'PID muss numerisch sein; der PID-Filter wurde ignoriert.',
          ja: 'PID は数字のみです。PID フィルターを無視しました。',
        ),
        packageName: packageName,
      );
    }
    if (packageName == null) {
      return (pid: null, notice: null, packageName: null);
    }
    final lookup = await _ctrl.pidOfPackageDetailed(
      packageName,
      serial: query.serial,
    );
    if (!mounted || !_isCurrentLogcatQueryContext(query)) {
      return (pid: null, notice: null, packageName: packageName);
    }
    final pid = lookup.pid?.trim();
    if (pid != null && pid.isNotEmpty) {
      return (pid: pid, notice: null, packageName: packageName);
    }
    return (
      pid: null,
      notice: _logcatPidLookupNotice(lookup),
      packageName: packageName,
    );
  }

  String _logcatPidLookupNotice(AndroidPackagePidLookupResult lookup) {
    final stderr = lookup.stderr.trim();
    if (lookup.timedOut) {
      return openHandLocalizedText(
        context,
        zh: '解析目标包 PID 超时，已按当前等级读取全局 Logcat。',
        zhHant: '解析目標套件 PID 逾時，已按目前等級讀取全域 Logcat。',
        en: 'Resolving the target package PID timed out; loaded global logcat with the selected level.',
        fr: 'La résolution du PID du package cible a expiré ; Logcat global chargé au niveau sélectionné.',
        de: 'PID des Zielpakets konnte nicht rechtzeitig ermittelt werden; globales Logcat mit der gewählten Stufe geladen.',
        ja: '対象パッケージの PID 解決がタイムアウトしました。選択レベルで全体 Logcat を読み込みました。',
      );
    }
    if (stderr.isNotEmpty) {
      return openHandLocalizedText(
        context,
        zh: '解析目标包 PID 失败：$stderr。已按当前等级读取全局 Logcat。',
        zhHant: '解析目標套件 PID 失敗：$stderr。已按目前等級讀取全域 Logcat。',
        en: 'Failed to resolve the target package PID: $stderr. Loaded global logcat with the selected level.',
        fr: 'Échec de résolution du PID du package cible : $stderr. Logcat global chargé au niveau sélectionné.',
        de: 'PID des Zielpakets konnte nicht ermittelt werden: $stderr. Globales Logcat mit der gewählten Stufe geladen.',
        ja: '対象パッケージの PID 解決に失敗しました: $stderr。選択レベルで全体 Logcat を読み込みました。',
      );
    }
    return openHandLocalizedText(
      context,
      zh: '目标包未运行或无法解析 PID，已按当前等级读取全局 Logcat。',
      zhHant: '目標套件未執行或無法解析 PID，已按目前等級讀取全域 Logcat。',
      en: 'Target package is not running or PID was unavailable; loaded global logcat with the selected level.',
      fr: 'Le package cible n’est pas en cours d’exécution ou le PID est indisponible ; Logcat global chargé au niveau sélectionné.',
      de: 'Zielpaket läuft nicht oder PID ist nicht verfügbar; globales Logcat mit der gewählten Stufe geladen.',
      ja: '対象パッケージが実行中でないか PID を取得できません。選択レベルで全体 Logcat を読み込みました。',
    );
  }

  Future<void> _runStaticQuickScan() async {
    if (_runningStaticQuickScan || _runningStaticAction) return;
    final target = _captureStaticAnalysisContext();
    setState(() {
      _runningStaticQuickScan = true;
      _staticQuickScanOutput = null;
    });
    try {
      final result = await _ctrl.runStaticQuickScan(
        apkPath: target.apkPath,
        packageName: target.packageName,
      );
      if (!mounted || !_isCurrentStaticAnalysisContext(target)) return;
      setState(() => _staticQuickScanOutput = _formatAdbResult(result));
      if (!result.ok && !result.hasUsableStdout) {
        _showSnack(
          openHandLocalizedText(
            context,
            zh: '静态扫描失败，已展示错误输出。',
            zhHant: '靜態掃描失敗，已顯示錯誤輸出。',
            en: 'Static scan failed. Error output is shown.',
            fr: 'Échec du scan statique. La sortie d’erreur est affichée.',
            de: 'Statischer Scan fehlgeschlagen. Fehlerausgabe wird angezeigt.',
            ja: '静的スキャンに失敗しました。エラー出力を表示しています。',
          ),
          kind: OpenHandSnackKind.error,
          duration: kOpenHandSnackBarNormalDuration,
        );
      }
    } catch (error) {
      if (!mounted || !_isCurrentStaticAnalysisContext(target)) return;
      _setStaticAnalysisFailure(error);
    } finally {
      if (mounted) setState(() => _runningStaticQuickScan = false);
    }
  }

  Future<void> _ensureMitmproxyAddon() async {
    if (_writingNetworkAddon) return;
    setState(() => _writingNetworkAddon = true);
    try {
      final addonPath = await _ctrl.ensureMitmproxyJsonlAddon();
      if (!mounted) return;
      final command =
          'OPENHAND_NETWORK_JSONL=${posixShellQuoteIfNeeded(_ctrl.networkJsonlPath)} '
          'mitmdump -p $kDefaultMitmProxyPort -s ${posixShellQuoteIfNeeded(addonPath)} '
          '-w ${posixShellQuoteIfNeeded('${_ctrl.networkDir}/flows.mitm')}';
      setState(() {
        _networkAddonOutput = [
          openHandLocalizedText(
            context,
            zh: '已生成网络抓包工件:',
            zhHant: '已產生網路抓包工件:',
            en: 'Generated network capture artifacts:',
            fr: 'Artefacts de capture réseau générés :',
            de: 'Netzwerk-Capture-Artefakte erstellt:',
            ja: 'ネットワークキャプチャ成果物を生成しました:',
          ),
          addonPath,
          'README: ${_ctrl.networkReadmePath}',
          'Proxy probe: ${_ctrl.networkProxyProbeScriptPath}',
          '',
          openHandLocalizedText(
            context,
            zh: '启动命令:',
            zhHant: '啟動指令:',
            en: 'Start command:',
            fr: 'Commande de démarrage :',
            de: 'Startbefehl:',
            ja: '起動コマンド:',
          ),
          command,
          '',
          'JSONL: ${_ctrl.networkJsonlPath}',
        ].join('\n');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _networkAddonOutput =
            '${openHandLocalizedText(context, zh: "生成 mitmproxy addon 失败", zhHant: "產生 mitmproxy addon 失敗", en: "Failed to generate mitmproxy addon", fr: "Échec de génération de l’addon mitmproxy", de: "mitmproxy-Addon konnte nicht erstellt werden", ja: "mitmproxy addon の生成に失敗しました")}: $error';
      });
      _showSnack(
        openHandLocalizedText(
          context,
          zh: '生成 mitmproxy addon 失败。',
          zhHant: '產生 mitmproxy addon 失敗。',
          en: 'Failed to generate mitmproxy addon.',
          fr: 'Échec de génération de l’addon mitmproxy.',
          de: 'mitmproxy-Addon konnte nicht erstellt werden.',
          ja: 'mitmproxy addon の生成に失敗しました。',
        ),
        kind: OpenHandSnackKind.error,
        duration: kOpenHandSnackBarNormalDuration,
      );
    } finally {
      if (mounted) setState(() => _writingNetworkAddon = false);
    }
  }

  Future<void> _ensureCertificateArtifacts() async {
    if (_writingCertificateArtifacts || _runningCertificateAction) return;
    final packageName = _logcatPackageTarget();
    setState(() => _writingCertificateArtifacts = true);
    try {
      final output = await _ctrl.ensureCertificateArtifacts(
        packageName: packageName,
      );
      if (!mounted || packageName != _logcatPackageTarget()) return;
      setState(() => _certificateArtifactOutput = output);
    } catch (error) {
      if (!mounted || packageName != _logcatPackageTarget()) return;
      _setCertificateOperationFailure(error);
      _showSnack(
        openHandLocalizedText(
          context,
          zh: '生成证书工件失败。',
          zhHant: '產生憑證工件失敗。',
          en: 'Failed to generate certificate artifacts.',
          fr: 'Échec de génération des artefacts certificat.',
          de: 'Zertifikatsartefakte konnten nicht erstellt werden.',
          ja: '証明書成果物の生成に失敗しました。',
        ),
        kind: OpenHandSnackKind.error,
        duration: kOpenHandSnackBarNormalDuration,
      );
    } finally {
      if (mounted) setState(() => _writingCertificateArtifacts = false);
    }
  }

  Future<void> _ensureMcpLinkageArtifacts() async {
    if (_writingMcpArtifacts) return;
    setState(() => _writingMcpArtifacts = true);
    try {
      final output = await _ctrl.ensureMcpLinkageArtifacts();
      if (!mounted) return;
      setState(() => _mcpArtifactOutput = output);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _mcpArtifactOutput =
            '${openHandLocalizedText(context, zh: "生成 MCP 联动工件失败", zhHant: "產生 MCP 聯動工件失敗", en: "Failed to generate MCP linkage artifacts", fr: "Échec de génération des artefacts de liaison MCP", de: "MCP-Linkage-Artefakte konnten nicht erstellt werden", ja: "MCP 連携成果物の生成に失敗しました")}: $error';
      });
      _showSnack(
        openHandLocalizedText(
          context,
          zh: '生成 MCP 联动工件失败。',
          zhHant: '產生 MCP 聯動工件失敗。',
          en: 'Failed to generate MCP linkage artifacts.',
          fr: 'Échec de génération des artefacts de liaison MCP.',
          de: 'MCP-Linkage-Artefakte konnten nicht erstellt werden.',
          ja: 'MCP 連携成果物の生成に失敗しました。',
        ),
        kind: OpenHandSnackKind.error,
        duration: kOpenHandSnackBarNormalDuration,
      );
    } finally {
      if (mounted) setState(() => _writingMcpArtifacts = false);
    }
  }

  Future<void> _makeEvidenceBundle() async {
    if (_makingEvidenceBundle) return;
    setState(() {
      _makingEvidenceBundle = true;
      _evidenceBundleOutput = openHandLocalizedText(
        context,
        zh: '生成中...',
        zhHant: '產生中...',
        en: 'Generating...',
        fr: 'Génération...',
        de: 'Wird erstellt...',
        ja: '生成中...',
      );
    });
    try {
      final result = await _ctrl.makeEvidenceBundleToArtifacts();
      if (!mounted) return;
      setState(() => _evidenceBundleOutput = _formatAdbResult(result));
      showOpenHandInfoSnack(
        context,
        result.ok
            ? openHandLocalizedText(
                context,
                zh: '证据包已生成。',
                zhHant: '證據包已產生。',
                en: 'Evidence bundle generated.',
                fr: 'Paquet de preuves généré.',
                de: 'Beweispaket erstellt.',
                ja: '証拠パッケージを生成しました。',
              )
            : openHandLocalizedText(
                context,
                zh: '证据包生成失败。',
                zhHant: '證據包產生失敗。',
                en: 'Evidence bundle generation failed.',
                fr: 'Échec de génération du paquet de preuves.',
                de: 'Beweispaket konnte nicht erstellt werden.',
                ja: '証拠パッケージの生成に失敗しました。',
              ),
      );
    } finally {
      if (mounted) setState(() => _makingEvidenceBundle = false);
    }
  }

  Future<void> _loadFridaSnippet(_FridaSnippetPreset preset) async {
    final loadGeneration = ++_fridaSnippetLoadGeneration;
    final scriptRevision = _fridaScriptRevision;
    try {
      final script = await rootBundle.loadString(
        preset.assetPath,
        cache: false,
      );
      if (!mounted ||
          loadGeneration != _fridaSnippetLoadGeneration ||
          scriptRevision != _fridaScriptRevision) {
        return;
      }
      _selectedFridaSnippetAsset = preset.assetPath;
      final nextScript = script.trimRight();
      if (_fridaScriptCtrl.text == nextScript) {
        setState(() {});
      } else {
        _fridaScriptCtrl.text = nextScript;
      }
    } catch (error) {
      if (!mounted ||
          loadGeneration != _fridaSnippetLoadGeneration ||
          scriptRevision != _fridaScriptRevision) {
        return;
      }
      _showSnack(
        openHandLocalizedText(
          context,
          zh: '加载 Frida snippet 失败：$error',
          zhHant: '載入 Frida snippet 失敗：$error',
          en: 'Failed to load Frida snippet: $error',
          fr: 'Échec de chargement du snippet Frida : $error',
          de: 'Frida-Snippet konnte nicht geladen werden: $error',
          ja: 'Frida snippet の読み込みに失敗しました: $error',
        ),
        kind: OpenHandSnackKind.error,
        duration: kOpenHandSnackBarNormalDuration,
      );
    }
  }

  Future<void> _saveFridaScriptArtifact() async {
    if (_savingFridaScript || _runningFridaAction) return;
    final script = _fridaScriptCtrl.text;
    if (script.trim().isEmpty) return;
    final scriptRevision = _fridaScriptRevision;
    final presetAssetPath = _selectedFridaSnippetAsset;
    final packageName = _logcatPackageTarget();
    setState(() => _savingFridaScript = true);
    try {
      final result = await _ctrl.saveFridaScriptToArtifacts(
        script: script,
        presetAssetPath: presetAssetPath,
        packageName: packageName,
      );
      if (!mounted ||
          scriptRevision != _fridaScriptRevision ||
          packageName != _logcatPackageTarget()) {
        return;
      }
      setState(() {
        _lastSavedFridaScriptPath = _extractFridaScriptPath(result.stdout);
        _fridaArtifactOutput = _formatAdbResult(result);
      });
      if (result.ok) {
        _showSnack(
          openHandLocalizedText(
            context,
            zh: '已保存 Frida 脚本工件。',
            zhHant: '已儲存 Frida 腳本工件。',
            en: 'Frida script artifact saved.',
            fr: 'Artefact de script Frida enregistré.',
            de: 'Frida-Skriptartefakt gespeichert.',
            ja: 'Frida スクリプト成果物を保存しました。',
          ),
          kind: OpenHandSnackKind.success,
          duration: kOpenHandSnackBarNormalDuration,
        );
      }
    } catch (error) {
      if (!mounted ||
          scriptRevision != _fridaScriptRevision ||
          packageName != _logcatPackageTarget()) {
        return;
      }
      setState(() {
        _fridaArtifactOutput =
            '${openHandLocalizedText(context, zh: "保存 Frida 脚本失败", zhHant: "儲存 Frida 腳本失敗", en: "Failed to save Frida script", fr: "Échec d’enregistrement du script Frida", de: "Frida-Skript konnte nicht gespeichert werden", ja: "Frida スクリプトの保存に失敗しました")}: $error';
      });
    } finally {
      if (mounted) setState(() => _savingFridaScript = false);
    }
  }

  Future<void> _runFridaDoctor() async {
    if (_runningFridaDoctor) return;
    final target = _captureAndroidTargetContext();
    setState(() {
      _runningFridaDoctor = true;
      _fridaArtifactOutput = openHandLocalizedText(
        context,
        zh: 'Frida 诊断运行中...',
        zhHant: 'Frida 診斷執行中...',
        en: 'Running Frida doctor...',
        fr: 'Diagnostic Frida en cours...',
        de: 'Frida-Diagnose läuft...',
        ja: 'Frida 診断を実行中...',
      );
    });
    try {
      await _ctrl.ensureMcpLinkageArtifacts();
      if (!_isCurrentAndroidTargetContext(target)) return;
      final pkg = target.packageName;
      final serial = target.serial;
      final result = await _ctrl.runLocalArtifactScriptDetailed(
        scriptPath: _ctrl.fridaDoctorScriptPath,
        args: <String>[
          '--timeout',
          '6',
          if (pkg != null && pkg.isNotEmpty) ...['--package', pkg],
          if (serial != null && serial.isNotEmpty) ...['-s', serial],
        ],
        timeout: _kFridaDoctorTimeout,
        displayCommand:
            'bash ${posixShellQuoteIfNeeded(_ctrl.fridaDoctorScriptPath)} --timeout 6${pkg == null ? "" : " --package ${posixShellQuoteIfNeeded(pkg)}"}${serial == null || serial.isEmpty ? "" : " -s ${posixShellQuoteIfNeeded(serial)}"}',
        tag: 'android_reverse.frida_doctor',
      );
      if (!mounted || !_isCurrentAndroidTargetContext(target)) return;
      setState(() => _fridaArtifactOutput = _formatAdbResult(result));
    } catch (error) {
      if (!mounted || !_isCurrentAndroidTargetContext(target)) return;
      _setFridaOperationFailure(error);
    } finally {
      if (mounted) setState(() => _runningFridaDoctor = false);
    }
  }

  Future<String?> _ensureFridaScriptPath() async {
    final cached = _lastSavedFridaScriptPath?.trim();
    if (cached != null && cached.isNotEmpty) return cached;
    final script = _fridaScriptCtrl.text;
    if (script.trim().isEmpty) return null;
    final scriptRevision = _fridaScriptRevision;
    final presetAssetPath = _selectedFridaSnippetAsset;
    final packageName = _logcatPackageTarget();
    final result = await _ctrl.saveFridaScriptToArtifacts(
      script: script,
      presetAssetPath: presetAssetPath,
      packageName: packageName,
    );
    final path = _extractFridaScriptPath(result.stdout);
    if (!mounted ||
        scriptRevision != _fridaScriptRevision ||
        packageName != _logcatPackageTarget()) {
      return null;
    }
    setState(() {
      _lastSavedFridaScriptPath = path;
      _fridaArtifactOutput = _formatAdbResult(result);
    });
    return path;
  }

  String? _extractFridaScriptPath(String text) {
    final match = RegExp(r'Frida script:\s*(.+)').firstMatch(text);
    final path = match?.group(1)?.trim();
    return path == null || path.isEmpty ? null : path;
  }

  void _setFridaOperationFailure(Object error) {
    setState(() {
      _fridaArtifactOutput =
          '${openHandLocalizedText(context, zh: "Frida 操作失败", zhHant: "Frida 操作失敗", en: "Frida operation failed", fr: "Échec de l’opération Frida", de: "Frida-Vorgang fehlgeschlagen", ja: "Frida 操作に失敗しました")}: $error';
    });
  }

  Future<void> _runFridaCapture({required bool spawn}) async {
    if (_runningFridaAction || _savingFridaScript) return;
    final target = _captureAndroidTargetContext();
    final pkg = target.packageName;
    if (pkg == null || pkg.isEmpty) {
      _showSnack(
        openHandLocalizedText(
          context,
          zh: '请先选择或配置包名。',
          zhHant: '請先選擇或設定套件名稱。',
          en: 'Select or configure a package first.',
          fr: 'Sélectionnez ou configurez d’abord un package.',
          de: 'Wählen oder konfigurieren Sie zuerst einen Paketnamen.',
          ja: '先にパッケージ名を選択または設定してください。',
        ),
      );
      return;
    }
    final scriptRevision = _fridaScriptRevision;
    setState(() {
      _runningFridaAction = true;
      _fridaArtifactOutput = openHandLocalizedText(
        context,
        zh: 'Frida 注入执行中...',
        zhHant: 'Frida 注入執行中...',
        en: 'Running Frida capture...',
        fr: 'Capture Frida en cours...',
        de: 'Frida-Capture läuft...',
        ja: 'Frida キャプチャを実行中...',
      );
    });
    try {
      await _ctrl.ensureMcpLinkageArtifacts();
      if (!_isCurrentFridaScriptContext(target, scriptRevision)) return;
      final scriptPath = await _ensureFridaScriptPath();
      if (!_isCurrentFridaScriptContext(target, scriptRevision)) return;
      if (scriptPath == null || scriptPath.isEmpty) {
        if (mounted) {
          setState(() {
            _fridaArtifactOutput = openHandLocalizedText(
              context,
              zh: '请先选择 snippet 或保存脚本。',
              zhHant: '請先選擇 snippet 或儲存腳本。',
              en: 'Load a snippet or save a script first.',
              fr: 'Chargez un snippet ou enregistrez d’abord un script.',
              de: 'Laden Sie zuerst ein Snippet oder speichern Sie ein Skript.',
              ja: '先に snippet を読み込むかスクリプトを保存してください。',
            );
          });
        }
        return;
      }
      final serial = target.serial;
      final result = await _ctrl.runLocalArtifactScriptDetailed(
        scriptPath: _ctrl.fridaCaptureScriptPath,
        args: <String>[
          '--package',
          pkg,
          '--script',
          scriptPath,
          spawn ? '--spawn' : '--attach',
          if (serial != null && serial.isNotEmpty) ...['-s', serial],
        ],
        timeout: _kFridaCaptureTimeout,
        displayCommand:
            'bash ${posixShellQuoteIfNeeded(_ctrl.fridaCaptureScriptPath)} --package ${posixShellQuoteIfNeeded(pkg)} --script ${posixShellQuoteIfNeeded(scriptPath)} ${spawn ? "--spawn" : "--attach"}${serial == null || serial.isEmpty ? "" : " -s ${posixShellQuoteIfNeeded(serial)}"}',
        tag: spawn
            ? 'android_reverse.frida_spawn_capture'
            : 'android_reverse.frida_attach_capture',
      );
      if (!mounted || !_isCurrentFridaScriptContext(target, scriptRevision)) {
        return;
      }
      setState(() => _fridaArtifactOutput = _formatAdbResult(result));
    } catch (error) {
      if (!mounted || !_isCurrentFridaScriptContext(target, scriptRevision)) {
        return;
      }
      _setFridaOperationFailure(error);
    } finally {
      if (mounted) setState(() => _runningFridaAction = false);
    }
  }

  Future<void> _readFridaArtifacts() async {
    if (_runningFridaAction) return;
    setState(() {
      _runningFridaAction = true;
      _fridaArtifactOutput = openHandLocalizedText(
        context,
        zh: '读取 Frida 工件中...',
        zhHant: '讀取 Frida 工件中...',
        en: 'Reading Frida artifacts...',
        fr: 'Lecture des artefacts Frida...',
        de: 'Frida-Artefakte werden gelesen...',
        ja: 'Frida 成果物を読み込み中...',
      );
    });
    try {
      await _ctrl.ensureMcpLinkageArtifacts();
      final result = await _ctrl.runLocalShellDetailed(
        actionName: 'frida-read-artifacts',
        command: r'''
set +e
printf '[scripts]\n'
find "$FRIDA_SCRIPTS_DIR" -maxdepth 1 -type f 2>/dev/null | sort | tail -40
printf '\n[output]\n'
find "$FRIDA_OUTPUT_DIR" -maxdepth 1 -type f 2>/dev/null | sort | tail -40
latest="$(find "$FRIDA_OUTPUT_DIR" -maxdepth 1 -type f 2>/dev/null | sort | tail -1)"
if [ -n "$latest" ]; then
  printf '\n[latest:%s]\n' "$latest"
  tail -160 "$latest"
fi
''',
        environment: <String, String>{
          'FRIDA_SCRIPTS_DIR': _ctrl.fridaScriptsDir,
          'FRIDA_OUTPUT_DIR': _ctrl.fridaOutputDir,
        },
        timeout: _kFridaLocalShellTimeout,
        displayCommand: 'read Frida artifacts',
        tag: 'android_reverse.frida_read_artifacts',
      );
      if (!mounted) return;
      setState(() => _fridaArtifactOutput = _formatAdbResult(result));
    } catch (error) {
      if (!mounted) return;
      _setFridaOperationFailure(error);
    } finally {
      if (mounted) setState(() => _runningFridaAction = false);
    }
  }

  Future<void> _startExistingFridaServer() async {
    if (_runningFridaAction) return;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '启动设备端 frida-server？',
        zhHant: '啟動裝置端 frida-server？',
        en: 'Start device frida-server?',
        fr: 'Démarrer frida-server sur l’appareil ?',
        de: 'frida-server auf dem Gerät starten?',
        ja: 'デバイス側 frida-server を起動しますか？',
      ),
      message: openHandLocalizedText(
        context,
        zh: '仅会尝试启动已存在的 /data/local/tmp/frida-server 并建立 27042 端口转发，不会自动下载或推送二进制。',
        zhHant:
            '僅會嘗試啟動已存在的 /data/local/tmp/frida-server 並建立 27042 連接埠轉發，不會自動下載或推送二進位檔。',
        en: 'This only starts an existing /data/local/tmp/frida-server and forwards port 27042. It will not download or push binaries.',
        fr: 'Démarre seulement /data/local/tmp/frida-server s’il existe et transfère le port 27042. Aucun binaire ne sera téléchargé ni poussé.',
        de: 'Startet nur einen vorhandenen /data/local/tmp/frida-server und leitet Port 27042 weiter. Es werden keine Binärdateien heruntergeladen oder übertragen.',
        ja: '既存の /data/local/tmp/frida-server の起動と 27042 ポート転送のみ試行します。バイナリの自動ダウンロードや push は行いません。',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandStartLabel(context),
    );
    if (!confirmed || !mounted || _runningFridaAction) return;
    final target = _captureAndroidTargetContext();
    setState(() {
      _runningFridaAction = true;
      _fridaArtifactOutput = openHandLocalizedText(
        context,
        zh: '启动 frida-server 中...',
        zhHant: '啟動 frida-server 中...',
        en: 'Starting frida-server...',
        fr: 'Démarrage de frida-server...',
        de: 'frida-server wird gestartet...',
        ja: 'frida-server を起動中...',
      );
    });
    try {
      final start = await _ctrl.shellDetailed(
        'if [ -x /data/local/tmp/frida-server ]; then pidof frida-server >/dev/null 2>&1 || nohup /data/local/tmp/frida-server >/dev/null 2>&1 & echo started; else echo missing:/data/local/tmp/frida-server; exit 2; fi',
        serial: target.serial,
        timeout: _kInteractiveShellTimeout,
      );
      if (!_isCurrentAndroidTargetContext(target, includePackage: false)) {
        return;
      }
      final forward = await _ctrl.forwardPortDetailed(
        27042,
        27042,
        serial: target.serial,
      );
      final output = <String>[
        _formatAdbResult(start),
        '',
        _formatAdbResult(forward),
      ].join('\n');
      if (!mounted ||
          !_isCurrentAndroidTargetContext(target, includePackage: false)) {
        return;
      }
      setState(() => _fridaArtifactOutput = output);
    } catch (error) {
      if (!mounted ||
          !_isCurrentAndroidTargetContext(target, includePackage: false)) {
        return;
      }
      _setFridaOperationFailure(error);
    } finally {
      if (mounted) setState(() => _runningFridaAction = false);
    }
  }

  Future<void> _runNetworkProxyProbe() async {
    if (_runningNetworkProbe) return;
    final target = _captureAndroidTargetContext();
    setState(() {
      _runningNetworkProbe = true;
      _networkAddonOutput = openHandLocalizedText(
        context,
        zh: '代理 / 证书预检运行中...',
        zhHant: '代理 / 憑證預檢執行中...',
        en: 'Running proxy / cert preflight...',
        fr: 'Préflight proxy / certificat en cours...',
        de: 'Proxy-/Zertifikats-Preflight läuft...',
        ja: 'プロキシ / 証明書プリフライトを実行中...',
      );
    });
    try {
      await _ctrl.ensureMitmproxyJsonlAddon();
      if (!_isCurrentAndroidTargetContext(target)) return;
      final serial = target.serial;
      final packageName = target.packageName;
      final result = await _ctrl.runLocalArtifactScriptDetailed(
        scriptPath: _ctrl.networkProxyProbeScriptPath,
        args: const <String>['--timeout', '6'],
        environment: <String, String>{
          if (serial != null && serial.isNotEmpty) 'ADB_SERIAL': serial,
          if (packageName != null && packageName.isNotEmpty)
            'ANDROID_PACKAGE_NAME': packageName,
        },
        timeout: _kNetworkProxyProbeTimeout,
        displayCommand:
            'bash ${posixShellQuoteIfNeeded(_ctrl.networkProxyProbeScriptPath)} --timeout 6',
        tag: 'android_reverse.network_proxy_probe',
      );
      if (!mounted || !_isCurrentAndroidTargetContext(target)) return;
      setState(() => _networkAddonOutput = _formatAdbResult(result));
    } catch (error) {
      if (!mounted || !_isCurrentAndroidTargetContext(target)) return;
      _setNetworkOperationFailure(error);
    } finally {
      if (mounted) setState(() => _runningNetworkProbe = false);
    }
  }

  Future<void> _runNetworkAction(
    Future<AdbCommandResult> Function() action, {
    _AndroidTargetContext? target,
  }) async {
    if (_runningNetworkAction) return;
    setState(() {
      _runningNetworkAction = true;
      _networkAddonOutput = openHandLocalizedText(
        context,
        zh: '网络动作执行中...',
        zhHant: '網路動作執行中...',
        en: 'Running network action...',
        fr: 'Action réseau en cours...',
        de: 'Netzwerkaktion läuft...',
        ja: 'ネットワーク操作を実行中...',
      );
    });
    try {
      final result = await action();
      if (!mounted ||
          !_isCurrentAndroidTargetContext(target, includePackage: false)) {
        return;
      }
      setState(() => _networkAddonOutput = _formatAdbResult(result));
    } catch (error) {
      if (!mounted ||
          !_isCurrentAndroidTargetContext(target, includePackage: false)) {
        return;
      }
      _setNetworkOperationFailure(error);
    } finally {
      if (mounted) setState(() => _runningNetworkAction = false);
    }
  }

  int? _networkProxyPort() {
    final value = optionalIntFromValue(_networkProxyPortCtrl.text);
    return validTcpPort(value);
  }

  String? _networkProxyHost() {
    final host = _networkProxyHostCtrl.text.trim();
    if (host.isEmpty || host.length > 255) return null;
    if (!RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(host)) return null;
    return host;
  }

  void _setNetworkOperationFailure(Object error) {
    setState(() {
      _networkAddonOutput =
          '${openHandLocalizedText(context, zh: "网络操作失败", zhHant: "網路操作失敗", en: "Network operation failed", fr: "Échec de l’opération réseau", de: "Netzwerkvorgang fehlgeschlagen", ja: "ネットワーク操作に失敗しました")}: $error';
    });
  }

  Future<void> _startNetworkCapture() async {
    final port = _networkProxyPort();
    if (port == null) {
      _showSnack(
        openHandLocalizedText(
          context,
          zh: '请输入合法端口。',
          zhHant: '請輸入合法連接埠。',
          en: 'Enter a valid port.',
          fr: 'Saisissez un port valide.',
          de: 'Geben Sie einen gültigen Port ein.',
          ja: '有効なポートを入力してください。',
        ),
      );
      return;
    }
    await _runNetworkAction(() => _ctrl.startNetworkCapture(port: port));
  }

  Future<void> _setDeviceProxy() async {
    final host = _networkProxyHost();
    final port = _networkProxyPort();
    if (host == null || port == null) {
      _showSnack(
        openHandLocalizedText(
          context,
          zh: '请输入合法代理主机和端口。',
          zhHant: '請輸入合法代理主機和連接埠。',
          en: 'Enter a valid proxy host and port.',
          fr: 'Saisissez un hôte proxy et un port valides.',
          de: 'Geben Sie einen gültigen Proxy-Host und Port ein.',
          ja: '有効なプロキシホストとポートを入力してください。',
        ),
      );
      return;
    }
    final target = _captureAndroidTargetContext();
    await _runNetworkAction(
      () => _ctrl.shellDetailed(
        'settings put global http_proxy ${posixShellQuoteIfNeeded('$host:$port')}; settings get global http_proxy',
        serial: target.serial,
        timeout: _kInteractiveShellTimeout,
      ),
      target: target,
    );
  }

  Future<void> _readDeviceProxy() {
    final target = _captureAndroidTargetContext();
    return _runNetworkAction(
      () => _ctrl.shellDetailed(
        'settings get global http_proxy; settings get global global_http_proxy_host 2>/dev/null; settings get global global_http_proxy_port 2>/dev/null',
        serial: target.serial,
        timeout: _kInteractiveShellTimeout,
      ),
      target: target,
    );
  }

  Future<void> _clearDeviceProxy() {
    final target = _captureAndroidTargetContext();
    return _runNetworkAction(
      () => _ctrl.shellDetailed(
        'settings delete global http_proxy; settings delete global global_http_proxy_host 2>/dev/null; settings delete global global_http_proxy_port 2>/dev/null; settings get global http_proxy',
        serial: target.serial,
        timeout: _kInteractiveShellTimeout,
      ),
      target: target,
    );
  }

  Future<void> _exportNetworkFlowsWithPicker() async {
    if (_runningNetworkAction) return;
    final saveDialogErrorPrefix = openHandLocalizedText(
      context,
      zh: '打开保存对话框失败',
      zhHant: '開啟儲存對話框失敗',
      en: 'Failed to open save dialog',
      fr: 'Échec d’ouverture de la boîte d’enregistrement',
      de: 'Speicherdialog konnte nicht geöffnet werden',
      ja: '保存ダイアログを開けませんでした',
    );
    final missingFlowsArtifactMessage = openHandLocalizedText(
      context,
      zh: 'mitmproxy flows 文本产物不存在。',
      zhHant: 'mitmproxy flows 文字工件不存在。',
      en: 'mitmproxy flows text artifact does not exist.',
      fr: 'L’artefact texte mitmproxy flows n’existe pas.',
      de: 'Das Textartefakt mitmproxy flows existiert nicht.',
      ja: 'mitmproxy flows テキスト成果物が存在しません。',
    );
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'openhand-mitm-flows-${_fileTimestamp()}.txt',
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'TXT', extensions: <String>['txt', 'log']),
        ],
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack('$saveDialogErrorPrefix: $error');
      return;
    }
    if (location == null || !mounted) return;
    final destination = location.path;
    await _runNetworkAction(() async {
      final result = await _ctrl.exportMitmproxyFlows();
      if (!result.ok && !result.partialOk) return result;
      final source = File('${_ctrl.networkDir}/flows.txt');
      if (!await source.exists().timeout(_kArtifactFileProbeTimeout)) {
        return AdbCommandResult(
          args: const <String>['network-capture-export'],
          exitCode: -1,
          stdout: result.stdout,
          stderr: missingFlowsArtifactMessage,
          displayCommand: result.displayCommand,
        );
      }
      await copyFileAtomically(
        source,
        File(destination),
        maxBytes: _kMaxNetworkFlowExportBytes,
      );
      return AdbCommandResult(
        args: const <String>['network-capture-export'],
        exitCode: result.exitCode,
        stdout: '${result.stdout.trimRight()}\nexported=$destination',
        stderr: result.stderr,
        timedOut: result.timedOut,
        displayCommand: result.displayCommand,
      );
    });
  }

  Future<void> _runStaticAction(
    Future<AdbCommandResult> Function(_StaticAnalysisContext target) action,
  ) async {
    if (_runningStaticAction || _runningStaticQuickScan) return;
    final target = _captureStaticAnalysisContext();
    setState(() {
      _runningStaticAction = true;
      _staticQuickScanOutput = openHandLocalizedText(
        context,
        zh: '静态分析动作执行中...',
        zhHant: '靜態分析動作執行中...',
        en: 'Running static analysis action...',
        fr: 'Action d’analyse statique en cours...',
        de: 'Statische Analyseaktion läuft...',
        ja: '静的解析アクションを実行中...',
      );
    });
    try {
      final result = await action(target);
      if (!mounted || !_isCurrentStaticAnalysisContext(target)) return;
      setState(() => _staticQuickScanOutput = _formatAdbResult(result));
    } catch (error) {
      if (!mounted || !_isCurrentStaticAnalysisContext(target)) return;
      _setStaticAnalysisFailure(error);
    } finally {
      if (mounted) setState(() => _runningStaticAction = false);
    }
  }

  void _setStaticAnalysisFailure(Object error) {
    setState(() {
      _staticQuickScanOutput =
          '${openHandLocalizedText(context, zh: "静态分析失败", zhHant: "靜態分析失敗", en: "Static analysis failed", fr: "Échec de l’analyse statique", de: "Statische Analyse fehlgeschlagen", ja: "静的解析に失敗しました")}: $error';
    });
  }

  String? _mitmCertPathArg() {
    final value = _mitmCertPathCtrl.text.trim();
    if (value.isEmpty || value == '~/.mitmproxy/mitmproxy-ca-cert.pem') {
      return null;
    }
    return value;
  }

  void _setCertificateOperationFailure(Object error) {
    setState(() {
      _certificateArtifactOutput =
          '${openHandLocalizedText(context, zh: "证书操作失败", zhHant: "憑證操作失敗", en: "Certificate operation failed", fr: "Échec de l’opération certificat", de: "Zertifikatsvorgang fehlgeschlagen", ja: "証明書操作に失敗しました")}: $error';
    });
  }

  Future<void> _runCertificateArtifactScript({
    required String scriptPath,
    required List<String> args,
    required String displayCommand,
  }) async {
    if (_runningCertificateAction || _writingCertificateArtifacts) return;
    final target = _captureStaticAnalysisContext();
    setState(() {
      _runningCertificateAction = true;
      _certificateArtifactOutput = openHandLocalizedText(
        context,
        zh: '证书动作执行中...',
        zhHant: '憑證動作執行中...',
        en: 'Running certificate action...',
        fr: 'Action certificat en cours...',
        de: 'Zertifikatsaktion läuft...',
        ja: '証明書アクションを実行中...',
      );
    });
    try {
      await _ctrl.ensureCertificateArtifacts(packageName: target.packageName);
      if (!_isCurrentStaticAnalysisContext(target)) return;
      final result = await _ctrl.runLocalArtifactScriptDetailed(
        scriptPath: scriptPath,
        args: args,
        displayCommand: displayCommand,
        tag: 'android_reverse.certificate_action',
      );
      if (!mounted || !_isCurrentStaticAnalysisContext(target)) return;
      setState(() => _certificateArtifactOutput = _formatAdbResult(result));
    } catch (error) {
      if (!mounted || !_isCurrentStaticAnalysisContext(target)) return;
      _setCertificateOperationFailure(error);
    } finally {
      if (mounted) setState(() => _runningCertificateAction = false);
    }
  }

  Future<void> _generateDebugKeystore() {
    return _runCertificateArtifactScript(
      scriptPath: _ctrl.generateDebugKeystoreScriptPath,
      args: const <String>[],
      displayCommand:
          'bash ${posixShellQuoteIfNeeded(_ctrl.generateDebugKeystoreScriptPath)}',
    );
  }

  Future<void> _verifyConfiguredApkSignature() async {
    final apkPath = _ctrl.config.apkPath?.trim();
    if (apkPath == null || apkPath.isEmpty) {
      _showSnack(
        openHandLocalizedText(
          context,
          zh: '当前会话未配置 APK 路径。',
          zhHant: '目前會話未設定 APK 路徑。',
          en: 'No APK path is configured.',
          fr: 'Aucun chemin APK n’est configuré.',
          de: 'Kein APK-Pfad ist konfiguriert.',
          ja: 'APK パスが設定されていません。',
        ),
      );
      return;
    }
    await _runCertificateArtifactScript(
      scriptPath: _ctrl.verifyApkSignatureScriptPath,
      args: <String>[apkPath],
      displayCommand:
          'bash ${posixShellQuoteIfNeeded(_ctrl.verifyApkSignatureScriptPath)} ${posixShellQuoteIfNeeded(apkPath)}',
    );
  }

  Future<void> _readCertificateArtifacts() async {
    if (_runningCertificateAction || _writingCertificateArtifacts) return;
    final packageName = _logcatPackageTarget();
    setState(() {
      _runningCertificateAction = true;
      _certificateArtifactOutput = openHandLocalizedText(
        context,
        zh: '读取证书工件中...',
        zhHant: '讀取憑證工件中...',
        en: 'Reading certificate artifacts...',
        fr: 'Lecture des artefacts certificat...',
        de: 'Zertifikatsartefakte werden gelesen...',
        ja: '証明書成果物を読み込み中...',
      );
    });
    try {
      final result = await _ctrl.readCertificateArtifacts(
        packageName: packageName,
      );
      if (!mounted || packageName != _logcatPackageTarget()) return;
      setState(() => _certificateArtifactOutput = _formatAdbResult(result));
    } catch (error) {
      if (!mounted || packageName != _logcatPackageTarget()) return;
      _setCertificateOperationFailure(error);
    } finally {
      if (mounted) setState(() => _runningCertificateAction = false);
    }
  }

  Future<void> _inspectMitmproxyCa() async {
    if (_runningCertificateAction || _writingCertificateArtifacts) return;
    final certPath = _mitmCertPathArg();
    setState(() {
      _runningCertificateAction = true;
      _certificateArtifactOutput = openHandLocalizedText(
        context,
        zh: '检查 CA 证书中...',
        zhHant: '檢查 CA 憑證中...',
        en: 'Inspecting CA certificate...',
        fr: 'Inspection du certificat CA...',
        de: 'CA-Zertifikat wird geprüft...',
        ja: 'CA 証明書を検査中...',
      );
    });
    try {
      final result = await _ctrl.inspectMitmproxyCa(certPath: certPath);
      if (!mounted || certPath != _mitmCertPathArg()) return;
      setState(() => _certificateArtifactOutput = _formatAdbResult(result));
    } catch (error) {
      if (!mounted || certPath != _mitmCertPathArg()) return;
      _setCertificateOperationFailure(error);
    } finally {
      if (mounted) setState(() => _runningCertificateAction = false);
    }
  }

  Future<void> _installMitmproxySystemCa() async {
    if (_runningCertificateAction || _writingCertificateArtifacts) return;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '安装系统 CA？',
        zhHant: '安裝系統 CA？',
        en: 'Install system CA?',
        fr: 'Installer la CA système ?',
        de: 'System-CA installieren?',
        ja: 'システム CA をインストールしますか？',
      ),
      message: openHandLocalizedText(
        context,
        zh: '此操作会执行 adb root/remount，并把 mitmproxy CA 写入系统证书目录。仅在测试设备、root/Magisk 环境中使用。',
        zhHant:
            '此操作會執行 adb root/remount，並將 mitmproxy CA 寫入系統憑證目錄。僅在測試裝置、root/Magisk 環境中使用。',
        en: 'This runs adb root/remount and writes the mitmproxy CA into the system cert store. Use only on rooted test devices.',
        fr: 'Exécute adb root/remount et écrit la CA mitmproxy dans le magasin de certificats système. À utiliser uniquement sur des appareils de test rootés.',
        de: 'Führt adb root/remount aus und schreibt die mitmproxy-CA in den System-Zertifikatsspeicher. Nur auf gerooteten Testgeräten verwenden.',
        ja: 'adb root/remount を実行し、mitmproxy CA をシステム証明書ストアへ書き込みます。root/Magisk のテストデバイスでのみ使用してください。',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandInstallLabel(context),
      destructive: true,
    );
    if (!confirmed ||
        !mounted ||
        _runningCertificateAction ||
        _writingCertificateArtifacts) {
      return;
    }
    final target = _captureAndroidTargetContext();
    final certPath = _mitmCertPathArg();
    setState(() {
      _runningCertificateAction = true;
      _certificateArtifactOutput = openHandLocalizedText(
        context,
        zh: '安装系统 CA 中...',
        zhHant: '安裝系統 CA 中...',
        en: 'Installing system CA...',
        fr: 'Installation de la CA système...',
        de: 'System-CA wird installiert...',
        ja: 'システム CA をインストール中...',
      );
    });
    try {
      final result = await _ctrl.installMitmproxyCaAsSystemCert(
        certPath: certPath,
        serial: target.serial,
      );
      if (!mounted ||
          !_isCurrentAndroidTargetContext(target, includePackage: false) ||
          certPath != _mitmCertPathArg()) {
        return;
      }
      setState(() => _certificateArtifactOutput = _formatAdbResult(result));
    } catch (error) {
      if (!mounted ||
          !_isCurrentAndroidTargetContext(target, includePackage: false) ||
          certPath != _mitmCertPathArg()) {
        return;
      }
      _setCertificateOperationFailure(error);
    } finally {
      if (mounted) setState(() => _runningCertificateAction = false);
    }
  }

  Future<void> _runShell() async {
    final rawCmd = _shellCtrl.text.trim();
    final cmd = _normalizeAdbShellInput(rawCmd);
    if (_runningShell) return;
    if (cmd.isEmpty) {
      final message = openHandLocalizedText(
        context,
        zh: '请输入要执行的 adb shell 命令。',
        zhHant: '請輸入要執行的 adb shell 指令。',
        en: 'Enter an adb shell command to run.',
        fr: 'Saisissez une commande adb shell à exécuter.',
        de: 'Geben Sie einen auszuführenden adb-shell-Befehl ein.',
        ja: '実行する adb shell コマンドを入力してください。',
      );
      setState(() => _shellOutputCtrl.text = message);
      showOpenHandInfoSnack(context, message);
      return;
    }
    final serial = _targetSerial;
    final contextGeneration = _deviceContextGeneration;
    setState(() {
      _runningShell = true;
      _lastShellResult = null;
      _rememberShellCommand(cmd);
      _shellOutputCtrl.text =
          '${openHandLocalizedText(context, zh: "执行中", zhHant: "執行中", en: "Running", fr: "Exécution", de: "Läuft", ja: "実行中")}: $cmd\n'
          '${openHandLocalizedText(context, zh: "目标设备", zhHant: "目標裝置", en: "Target", fr: "Cible", de: "Ziel", ja: "ターゲット")}: ${_shellTargetLabel(serial)}\n'
          '${openHandLocalizedText(context, zh: "超时", zhHant: "逾時", en: "Timeout", fr: "Expiration", de: "Timeout", ja: "タイムアウト")}: ${_kInteractiveShellTimeout.inSeconds}s';
    });
    try {
      final result = await _ctrl.shellDetailed(
        cmd,
        serial: serial,
        timeout: _kInteractiveShellTimeout,
      );
      if (!mounted ||
          contextGeneration != _deviceContextGeneration ||
          serial != _targetSerial) {
        return;
      }
      final output = _formatAdbResult(result);
      setState(() {
        _lastShellResult = result;
        _shellOutputCtrl.text = output;
      });
    } catch (error) {
      if (!mounted ||
          contextGeneration != _deviceContextGeneration ||
          serial != _targetSerial) {
        return;
      }
      setState(() {
        _shellOutputCtrl.text =
            '${openHandLocalizedText(context, zh: "执行失败", zhHant: "執行失敗", en: "Run failed", fr: "Échec d’exécution", de: "Ausführung fehlgeschlagen", ja: "実行に失敗しました")}: $error';
      });
    } finally {
      if (mounted) setState(() => _runningShell = false);
    }
  }

  void _rememberShellCommand(String command) {
    final normalized = command.trim();
    if (normalized.isEmpty) return;
    _shellHistory.removeWhere((entry) => entry == normalized);
    _shellHistory.insert(0, normalized);
    if (_shellHistory.length > _kShellHistoryLimit) {
      _shellHistory.removeRange(_kShellHistoryLimit, _shellHistory.length);
    }
  }

  String _shellTargetLabel(String? serial) {
    final value = serial?.trim();
    if (value == null || value.isEmpty) {
      return openHandLocalizedText(
        context,
        zh: '默认设备',
        zhHant: '預設裝置',
        en: 'default device',
        fr: 'appareil par défaut',
        de: 'Standardgerät',
        ja: '既定デバイス',
      );
    }
    return value;
  }

  String _formatAdbResult(AdbCommandResult result) {
    final buffer = StringBuffer()
      ..writeln('\$ ${result.commandLine}')
      ..writeln(
        '${openHandLocalizedText(context, zh: "退出码", zhHant: "退出碼", en: "exit", fr: "code", de: "Exit", ja: "終了コード")}: ${result.exitCode}',
      );
    if (result.partialOk) {
      buffer.writeln(
        openHandLocalizedText(
          context,
          zh: '状态: 命令超时，但已保留可用输出；请优先采纳输出并减少重复重试。',
          zhHant: '狀態: 指令逾時，但已保留可用輸出；請優先採納輸出並減少重複重試。',
          en: 'status: timed out with usable output; prefer the output and avoid repeating the same command.',
          fr: 'état : expiration avec sortie utilisable ; privilégiez la sortie et évitez de répéter la même commande.',
          de: 'Status: Timeout mit nutzbarer Ausgabe; bevorzugen Sie die Ausgabe und vermeiden Sie Wiederholungen.',
          ja: '状態: タイムアウトしましたが利用可能な出力があります。同じコマンドの繰り返しは避けてください。',
        ),
      );
    }
    final stdout = result.stdout.trim();
    final stderr = result.stderr.trim();
    if (stdout.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(stdout);
    }
    if (stderr.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('stderr:')
        ..writeln(stderr);
    }
    if (stdout.isEmpty && stderr.isEmpty) {
      buffer
        ..writeln()
        ..write(_androidReverseNoOutputLabel(context));
    }
    return buffer.toString().trimRight();
  }

  Future<void> _runDeviceAction(
    Future<AdbCommandResult> Function() action,
  ) async {
    if (_runningDeviceAction) return;
    final contextGeneration = _deviceContextGeneration;
    setState(() {
      _runningDeviceAction = true;
      _lastDeviceActionResult = null;
      _lastDeviceActionOutput = _androidReverseRunningLabel(context);
    });
    try {
      final result = await action();
      if (!mounted) return;
      if (contextGeneration == _deviceContextGeneration) {
        setState(() {
          _lastDeviceActionResult = result;
          _lastDeviceActionOutput = _formatAdbResult(result);
        });
      }
      unawaited(_refreshDeviceStateAfterAction());
    } catch (error) {
      if (!mounted || contextGeneration != _deviceContextGeneration) return;
      setState(() {
        _lastDeviceActionResult = null;
        _lastDeviceActionOutput =
            '${openHandLocalizedText(context, zh: "执行失败", zhHant: "執行失敗", en: "Run failed", fr: "Échec d’exécution", de: "Ausführung fehlgeschlagen", ja: "実行に失敗しました")}: $error';
      });
    } finally {
      if (mounted) setState(() => _runningDeviceAction = false);
    }
  }

  Future<void> _refreshDeviceStateAfterAction() async {
    await _doRefreshDevices();
    if (!mounted) return;
    await _refreshDeviceDetails();
  }

  Future<void> _copyText(String text) async {
    await copyOpenHandTextToClipboard(
      context: context,
      text: text,
      logTag: 'android_reverse_dashboard',
      logAction: '复制文本',
    );
  }

  /// 各面板统一的「复制结果」按钮；[text] 为空白时自动置灰。
  Widget _copyResultButton(String text) {
    final payload = text.trim();
    return _DashboardActionButton(
      onPressed: payload.isEmpty ? null : () => _copyText(payload),
      icon: Icons.copy_rounded,
      label: openHandLocalizedText(
        context,
        zh: '复制结果',
        zhHant: '複製結果',
        en: 'Copy result',
        fr: 'Copier le résultat',
        de: 'Ergebnis kopieren',
        ja: '結果をコピー',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = openHandIsChineseLocale(context);
    final device = _ctrl.connectedDevice;
    final config =
        AndroidReverseSessionConfig.fromJson(
          context
              .watch<AiSessionController>()
              .sessions
              .where((s) => s.id == widget.sessionId)
              .firstOrNull
              ?.metadata['android_reverse_config'],
        ) ??
        _ctrl.config;

    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthExtraWide,
      insetPadding: _kDashboardDialogInsetPadding,
      clipBehavior: Clip.hardEdge,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: kOpenHandDialogWidthExtraWide,
          maxHeight: kOpenHandDialogHeightTall,
        ),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            _buildHeader(context, cs, isZh, device, config),
            Divider(height: 1, color: cs.outlineVariant),
            // ── Tab bar ─────────────────────────────────────────────────
            _buildTabBar(context, theme, cs, isZh),
            Divider(height: 1, color: cs.outlineVariant),
            // ── Body ────────────────────────────────────────────────────
            Expanded(child: _buildBody(context, cs, theme, isZh)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme cs,
    bool isZh,
    AdbDevice? device,
    AndroidReverseSessionConfig config,
  ) {
    final running = _ctrl.isRunning;
    final activeDevice = _selectedDeviceSerial == null
        ? device
        : _ctrl.allDevices
              .where((item) => item.serial == _selectedDeviceSerial)
              .firstOrNull;
    final statusColor = !running
        ? cs.outline
        : activeDevice == null
        ? cs.error
        : cs.primary;
    final statusLabel = !running
        ? openHandLocalizedText(
            context,
            zh: '已停止',
            zhHant: '已停止',
            en: 'stopped',
            fr: 'arrêté',
            de: 'gestoppt',
            ja: '停止中',
          )
        : activeDevice == null
        ? openHandLocalizedText(
            context,
            zh: '无设备',
            zhHant: '無裝置',
            en: 'no device',
            fr: 'aucun appareil',
            de: 'kein Gerät',
            ja: 'デバイスなし',
          )
        : activeDevice.model ?? activeDevice.serial;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Icon(Icons.android_rounded, size: 22, color: cs.primary),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  openHandLocalizedText(
                    context,
                    zh: 'Android 逆向调试面板',
                    zhHant: 'Android 逆向偵錯面板',
                    en: 'Android Reverse Debugger',
                    fr: 'Débogueur reverse Android',
                    de: 'Android-Reverse-Debugger',
                    ja: 'Android リバースデバッガー',
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                kOpenHandGap2,
                Text(
                  config.objective,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: openHandMotionDuration(context, kOpenHandMotion220),
            curve: kOpenHandSwitchInCurve,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: kOpenHandPillBorderRadius,
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
                kOpenHandHGap6,
                Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          kOpenHandHGap8,
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: openHandRefreshLabel(context),
            onPressed: _refreshAll,
            iconSize: 20,
          ),
          const SizedBox(width: _kIconButtonGap),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: openHandCloseLabel(context),
            onPressed: () => Navigator.of(context).pop(),
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    bool isZh,
  ) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: _Tab.values
            .map((tab) {
              final selected = _currentTab == tab;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: AnimatedContainer(
                  duration: openHandMotionDuration(context, _kSwitchDuration),
                  curve: kOpenHandSwitchInCurve,
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primaryContainer.withValues(alpha: 0.6)
                        : Colors.transparent,
                    borderRadius: kOpenHandPillBorderRadius,
                  ),
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _currentTab = tab);
                      if (tab == _Tab.logcat) _fetchLogcat();
                      if (tab == _Tab.processes) _doRefreshProcesses();
                      if (tab == _Tab.packages) _doRefreshPackages();
                      if (tab == _Tab.toolchain && _toolchainRows.isEmpty) {
                        _refreshToolchain();
                      }
                      if (tab == _Tab.plugins && _toolchainRows.isEmpty) {
                        _refreshToolchain();
                      }
                    },
                    icon: Icon(tab.icon, size: 14),
                    label: Text(
                      tab.label(context),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    return AnimatedSwitcher(
      duration: openHandMotionDuration(context, _kSwitchDuration),
      switchInCurve: kOpenHandSwitchInCurve,
      child: KeyedSubtree(
        key: ValueKey<_Tab>(_currentTab),
        child: _buildTab(context, cs, theme, isZh),
      ),
    );
  }

  Widget _buildTab(
    BuildContext context,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    return switch (_currentTab) {
      _Tab.devices => _buildDevicesTab(cs, theme, isZh),
      _Tab.overview => _buildOverviewTab(cs, theme),
      _Tab.toolchain => _buildToolchainTab(cs, theme, isZh),
      _Tab.mcp => _buildMcpTab(cs, theme, isZh),
      _Tab.plugins => _buildPluginsTab(cs, theme, isZh),
      _Tab.packages => _buildPackagesTab(cs, theme, isZh),
      _Tab.processes => _buildProcessesTab(cs, theme, isZh),
      _Tab.logcat => _buildLogcatTab(cs, theme, isZh),
      _Tab.frida => _buildFridaTab(cs, theme, isZh),
      _Tab.network => _buildNetworkTab(cs, theme, isZh),
      _Tab.staticAnalysis => _buildStaticTab(cs, theme, isZh),
      _Tab.certs => _buildCertsTab(cs, theme, isZh),
      _Tab.crypto => _buildCryptoTab(cs, theme, isZh),
    };
  }

  // ── Devices tab ─────────────────────────────────────────────────────────

  Widget _buildDevicesTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final devices = _ctrl.allDevices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: '已检测设备',
                        zhHant: '已偵測裝置',
                        en: 'Detected devices',
                        fr: 'Appareils détectés',
                        de: 'Erkannte Geräte',
                        ja: '検出済みデバイス',
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_targetSerial != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Text(
                          '${openHandLocalizedText(context, zh: "当前目标", zhHant: "目前目標", en: "Target", fr: "Cible", de: "Ziel", ja: "ターゲット")}: $_targetSerial',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontFamily: kOpenHandMonospaceFontFamily,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              kOpenHandHGap8,
              SizedBox(
                width: _kDeviceTrailingActionWidth,
                child: _DashboardActionButton(
                  onPressed: () {
                    _refreshAll();
                  },
                  icon: Icons.refresh_rounded,
                  label: openHandRefreshLabel(context),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final list = _buildDeviceList(devices, cs, theme, isZh);
              final details = _buildDeviceDetailsPanel(cs, theme, isZh);
              if (constraints.maxWidth < 760) {
                return Column(
                  children: [
                    Expanded(child: list),
                    Divider(height: 1, color: cs.outlineVariant),
                    SizedBox(height: 220, child: details),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 6, child: list),
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                  Expanded(flex: 5, child: details),
                ],
              );
            },
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: _kAdbInlineControlHeight,
                      child: TextField(
                        controller: _shellCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: openHandLocalizedText(
                            context,
                            zh: _kAdbShellHintZh,
                            zhHant: '請輸入 adb shell 指令',
                            en: _kAdbShellHintEn,
                            fr: 'Entrez une commande adb shell',
                            de: 'adb-shell-Befehl eingeben',
                            ja: 'adb shell コマンドを入力',
                          ),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        style: const TextStyle(
                          fontFamily: kOpenHandMonospaceFontFamily,
                        ),
                        onSubmitted: (_) => _runShell(),
                      ),
                    ),
                  ),
                  kOpenHandHGap10,
                  _DashboardActionButton(
                    onPressed: _runningShell ? null : _runShell,
                    icon: Icons.play_arrow_rounded,
                    busy: _runningShell,
                    label: openHandRunLabel(context),
                    filled: true,
                    height: _kAdbInlineControlHeight,
                  ),
                ],
              ),
              if (_shellHistory.isNotEmpty) ...[
                kOpenHandGap8,
                _buildShellHistoryChips(cs, theme, isZh),
              ],
              if (_shellOutputCtrl.text.isNotEmpty) ...[
                kOpenHandGap8,
                _buildShellOutputPanel(cs, theme, isZh),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShellHistoryChips(ColorScheme cs, ThemeData theme, bool isZh) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          openHandLocalizedText(
            context,
            zh: '最近',
            zhHant: '最近',
            en: 'Recent',
            fr: 'Récent',
            de: 'Zuletzt',
            ja: '最近',
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        for (final command in _shellHistory)
          ActionChip(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                command,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontSize: 11,
                ),
              ),
            ),
            tooltip: command,
            onPressed: () {
              setState(() {
                _shellCtrl.text = command;
                _shellCtrl.selection = TextSelection.collapsed(
                  offset: _shellCtrl.text.length,
                );
              });
            },
          ),
      ],
    );
  }

  Widget _buildShellOutputPanel(ColorScheme cs, ThemeData theme, bool isZh) {
    final output = _shellOutputCtrl.text;
    final result = _lastShellResult;
    return Container(
      constraints: const BoxConstraints(maxHeight: _kShellOutputMaxHeight),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      openHandLocalizedText(
                        context,
                        zh: 'ADB Shell 输出',
                        zhHant: 'ADB Shell 輸出',
                        en: 'ADB Shell output',
                        fr: 'Sortie ADB Shell',
                        de: 'ADB-Shell-Ausgabe',
                        ja: 'ADB Shell 出力',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _DashboardIconActionButton(
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '复制输出',
                      zhHant: '複製輸出',
                      en: 'Copy output',
                      fr: 'Copier la sortie',
                      de: 'Ausgabe kopieren',
                      ja: '出力をコピー',
                    ),
                    icon: Icons.copy_rounded,
                    onPressed: output.trim().isEmpty
                        ? null
                        : () => _copyText(output),
                  ),
                  const SizedBox(width: _kDashboardTrailingActionGap),
                  _DashboardIconActionButton(
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '清空输出',
                      zhHant: '清空輸出',
                      en: 'Clear output',
                      fr: 'Effacer la sortie',
                      de: 'Ausgabe leeren',
                      ja: '出力をクリア',
                    ),
                    icon: Icons.close_rounded,
                    onPressed: () => setState(() {
                      _lastShellResult = null;
                      _shellOutputCtrl.clear();
                    }),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.7)),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Align(
                alignment: Alignment.topLeft,
                child: result == null
                    ? _formattedTerminalText(output, cs)
                    : _buildAdbCommandResultView(result, cs, theme),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(
    List<AdbDevice> devices,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    if (devices.isEmpty) {
      return OpenHandInlineEmptyState(
        message: openHandLocalizedText(
          context,
          zh: '未找到设备。请连接 Android 设备或启动模拟器后刷新。',
          zhHant: '找不到裝置。請連接 Android 裝置或啟動模擬器後重新整理。',
          en: 'No devices found. Connect a device or start an emulator, then refresh.',
          fr: 'Aucun appareil trouvé. Connectez un appareil ou démarrez un émulateur, puis actualisez.',
          de: 'Keine Geräte gefunden. Gerät verbinden oder Emulator starten und aktualisieren.',
          ja: 'デバイスが見つかりません。Android デバイスを接続するかエミュレーターを起動して更新してください。',
        ),
      );
    }
    return OpenHandSafeScrollbar(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: devices.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: cs.outlineVariant),
        itemBuilder: (_, i) {
          final d = devices[i];
          final selected = _targetSerial == d.serial;
          return GestureDetector(
            onSecondaryTapDown: (details) =>
                _showDeviceMenu(d, details.globalPosition),
            onDoubleTap: () => _showDeviceMenu(d, null),
            child: ListTile(
              selected: selected,
              selectedTileColor: cs.primaryContainer.withValues(alpha: 0.22),
              leading: Icon(
                d.isOnline
                    ? Icons.phone_android_rounded
                    : Icons.phone_disabled_rounded,
                color: d.isOnline ? cs.primary : cs.error,
              ),
              title: Text(
                d.model ?? d.serial,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${d.serial} · ${d.state}${d.product != null ? " · ${d.product}" : ""}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              trailing: Chip(
                label: Text(
                  d.isOnline
                      ? openHandLocalizedText(
                          context,
                          zh: '在线',
                          zhHant: '線上',
                          en: 'online',
                          fr: 'en ligne',
                          de: 'online',
                          ja: 'オンライン',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '异常',
                          zhHant: '異常',
                          en: d.state,
                          fr: d.state,
                          de: d.state,
                          ja: d.state,
                        ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: d.isOnline ? cs.primary : cs.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                backgroundColor:
                    (d.isOnline ? cs.primaryContainer : cs.errorContainer)
                        .withValues(alpha: 0.42),
                visualDensity: VisualDensity.compact,
                side: BorderSide.none,
              ),
              onTap: () {
                _setTargetDevice(d.serial);
                unawaited(_refreshDeviceDetails());
                unawaited(_doRefreshPackages());
                unawaited(_doRefreshProcesses());
              },
              dense: true,
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeviceDetailsPanel(ColorScheme cs, ThemeData theme, bool isZh) {
    final serial = _targetSerial;
    final device = serial == null
        ? null
        : _ctrl.allDevices.where((item) => item.serial == serial).firstOrNull;
    final snapshot = _deviceSnapshotOutput?.trim();
    final propItems = <(String, String)>[
      (
        openHandLocalizedText(
          context,
          zh: '系统版本',
          zhHant: '系統版本',
          en: 'Android',
          fr: 'Android',
          de: 'Android',
          ja: 'Android',
        ),
        _deviceProps['ro.build.version.release'] ?? '-',
      ),
      ('SDK', _deviceProps['ro.build.version.sdk'] ?? '-'),
      (
        openHandLocalizedText(
          context,
          zh: '品牌',
          zhHant: '品牌',
          en: 'Brand',
          fr: 'Marque',
          de: 'Marke',
          ja: 'ブランド',
        ),
        _deviceProps['ro.product.brand'] ?? '-',
      ),
      (openHandDeviceLabel(context), _deviceProps['ro.product.device'] ?? '-'),
      (
        openHandLocalizedText(
          context,
          zh: '指纹',
          zhHant: '指紋',
          en: 'Fingerprint',
          fr: 'Empreinte',
          de: 'Fingerprint',
          ja: 'フィンガープリント',
        ),
        _deviceProps['ro.build.fingerprint'] ?? '-',
      ),
    ];
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '设备操作',
                    zhHant: '裝置操作',
                    en: 'Device actions',
                    fr: 'Actions appareil',
                    de: 'Geräteaktionen',
                    ja: 'デバイス操作',
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              // 只在忙碌时显示；用固定占位的切换，避免转圈出现时把整行顶开。
              OpenHandBusyStatusIcon(
                busy: _loadingDeviceDetails,
                icon: null,
                size: 14,
                strokeWidth: 1.5,
              ),
            ],
          ),
          kOpenHandGap8,
          if (serial == null)
            _InfoCard(
              cs: cs,
              theme: theme,
              icon: Icons.info_outline_rounded,
              text: openHandLocalizedText(
                context,
                zh: '请选择一个在线设备，或通过无线 ADB 连接设备。',
                zhHant: '請選擇一個線上裝置，或透過無線 ADB 連接裝置。',
                en: 'Select an online device or connect one through wireless ADB.',
                fr: 'Sélectionnez un appareil en ligne ou connectez-en un via ADB sans fil.',
                de: 'Wählen Sie ein Online-Gerät oder verbinden Sie eines per Wireless ADB.',
                ja: 'オンラインデバイスを選択するか、ワイヤレス ADB で接続してください。',
              ),
            )
          else ...[
            _monospaceCard(
              cs,
              [
                device?.model ?? serial,
                serial,
                if (device?.product != null) device!.product!,
              ].join('\n'),
            ),
            kOpenHandGap10,
            for (final item in propItems)
              _DeviceInfoRow(label: item.$1, value: item.$2, colorScheme: cs),
            if (snapshot != null && snapshot.isNotEmpty) ...[
              kOpenHandGap12,
              Row(
                children: [
                  Expanded(
                    child: Text(
                      openHandLocalizedText(
                        context,
                        zh: '现场快照',
                        zhHant: '現場快照',
                        en: 'Field snapshot',
                        fr: 'Snapshot terrain',
                        de: 'Feld-Snapshot',
                        ja: '現場スナップショット',
                      ),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '复制现场快照',
                      zhHant: '複製現場快照',
                      en: 'Copy field snapshot',
                      fr: 'Copier le snapshot terrain',
                      de: 'Feld-Snapshot kopieren',
                      ja: '現場スナップショットをコピー',
                    ),
                    onPressed: () => _copyText(snapshot),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              kOpenHandGap6,
              _monospaceCard(cs, snapshot),
            ],
          ],
          kOpenHandGap14,
          Text(
            openHandLocalizedText(
              context,
              zh: '无线 ADB',
              zhHant: '無線 ADB',
              en: 'Wireless ADB',
              fr: 'ADB sans fil',
              de: 'Wireless ADB',
              ja: 'ワイヤレス ADB',
            ),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          kOpenHandGap6,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: TextField(
                    controller: _wirelessEndpointCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '192.168.1.10:5555',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _connectWirelessDevice(),
                  ),
                ),
              ),
              kOpenHandHGap8,
              _DashboardActionButton(
                onPressed: _runningDeviceAction ? null : _connectWirelessDevice,
                icon: Icons.link_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '连接',
                  zhHant: '連接',
                  en: 'Connect',
                  fr: 'Connecter',
                  de: 'Verbinden',
                  ja: '接続',
                ),
              ),
            ],
          ),
          kOpenHandGap10,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SmallActionButton(
                icon: Icons.link_off_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '断开当前',
                  zhHant: '中斷目前連線',
                  en: 'Disconnect',
                  fr: 'Déconnecter',
                  de: 'Trennen',
                  ja: '切断',
                ),
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () => _runDeviceAction(() => _ctrl.disconnect(serial)),
              ),
              _SmallActionButton(
                icon: Icons.restart_alt_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '重启',
                  zhHant: '重新啟動',
                  en: 'Reboot',
                  fr: 'Redémarrer',
                  de: 'Neustarten',
                  ja: '再起動',
                ),
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () =>
                          _runDeviceAction(() => _ctrl.reboot(serial: serial)),
              ),
              _SmallActionButton(
                icon: Icons.admin_panel_settings_rounded,
                label: 'root',
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () => _runDeviceAction(() => _ctrl.root(serial: serial)),
              ),
              _SmallActionButton(
                icon: Icons.storage_rounded,
                label: 'remount',
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () =>
                          _runDeviceAction(() => _ctrl.remount(serial: serial)),
              ),
            ],
          ),
          kOpenHandGap14,
          Text(
            openHandLocalizedText(
              context,
              zh: '端口转发',
              zhHant: '連接埠轉發',
              en: 'Port forwarding',
              fr: 'Redirection de port',
              de: 'Portweiterleitung',
              ja: 'ポート転送',
            ),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          kOpenHandGap6,
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: TextField(
                    controller: _forwardLocalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: openHandLocalizedText(
                        context,
                        zh: '本地端口',
                        zhHant: '本機連接埠',
                        en: 'local',
                        fr: 'local',
                        de: 'lokal',
                        ja: 'ローカル',
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _addForward(),
                  ),
                ),
              ),
              kOpenHandHGap8,
              Expanded(
                child: SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: TextField(
                    controller: _forwardRemoteCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: openHandLocalizedText(
                        context,
                        zh: '设备端口',
                        zhHant: '裝置連接埠',
                        en: 'remote',
                        fr: 'distant',
                        de: 'remote',
                        ja: 'リモート',
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _addForward(),
                  ),
                ),
              ),
              kOpenHandHGap8,
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _DashboardActionButton(
                  onPressed: serial == null || _runningDeviceAction
                      ? null
                      : _addForward,
                  icon: Icons.add_rounded,
                  label: openHandAddLabel(context),
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          if (_forwardRows.isEmpty)
            Text(
              openHandLocalizedText(
                context,
                zh: '暂无端口转发',
                zhHant: '暫無連接埠轉發',
                en: 'No active forwards',
                fr: 'Aucune redirection active',
                de: 'Keine aktiven Weiterleitungen',
                ja: '有効な転送はありません',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in _forwardRows)
                  _ForwardRow(
                    row: row,
                    colorScheme: cs,
                    removeTooltip: openHandLocalizedText(
                      context,
                      zh: '移除转发',
                      zhHant: '移除轉發',
                      en: 'Remove forward',
                      fr: 'Supprimer la redirection',
                      de: 'Weiterleitung entfernen',
                      ja: '転送を削除',
                    ),
                    onRemove: _runningDeviceAction
                        ? null
                        : () => _removeForwardFromRow(row),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _runningDeviceAction
                        ? null
                        : () => _runDeviceAction(
                            () => _ctrl
                                .removeAllForwards(serial: serial)
                                .then(
                                  (ok) => AdbCommandResult(
                                    args: const <String>[
                                      'forward',
                                      '--remove-all',
                                    ],
                                    exitCode: ok ? 0 : 1,
                                    stdout: ok ? 'removed all forwards' : '',
                                    stderr: ok ? '' : 'remove-all failed',
                                  ),
                                ),
                          ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 14),
                    label: Text(
                      openHandLocalizedText(
                        context,
                        zh: '移除全部转发',
                        zhHant: '移除全部轉發',
                        en: 'Remove all forwards',
                        fr: 'Supprimer toutes les redirections',
                        de: 'Alle Weiterleitungen entfernen',
                        ja: 'すべての転送を削除',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          kOpenHandGap14,
          Text(
            openHandLocalizedText(
              context,
              zh: '反向端口映射',
              zhHant: '反向連接埠映射',
              en: 'Reverse port mapping',
              fr: 'Mappage de port inverse',
              de: 'Reverse-Portmapping',
              ja: 'リバースポートマッピング',
            ),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          kOpenHandGap6,
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: TextField(
                    controller: _reverseDeviceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: openHandLocalizedText(
                        context,
                        zh: '设备端口',
                        zhHant: '裝置連接埠',
                        en: 'device port',
                        fr: 'port appareil',
                        de: 'Geräteport',
                        ja: 'デバイスポート',
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _addReverse(),
                  ),
                ),
              ),
              kOpenHandHGap8,
              Expanded(
                child: SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: TextField(
                    controller: _reverseHostCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: openHandLocalizedText(
                        context,
                        zh: '主机端口',
                        zhHant: '主機連接埠',
                        en: 'host port',
                        fr: 'port hôte',
                        de: 'Host-Port',
                        ja: 'ホストポート',
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _addReverse(),
                  ),
                ),
              ),
              kOpenHandHGap8,
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _DashboardActionButton(
                  onPressed: serial == null || _runningDeviceAction
                      ? null
                      : _addReverse,
                  icon: Icons.add_link_rounded,
                  label: openHandAddLabel(context),
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          if (_reverseRows.isEmpty)
            Text(
              openHandLocalizedText(
                context,
                zh: '暂无反向映射',
                zhHant: '暫無反向映射',
                en: 'No active reverse mappings',
                fr: 'Aucun mappage inverse actif',
                de: 'Keine aktiven Reverse-Mappings',
                ja: '有効なリバースマッピングはありません',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in _reverseRows)
                  _ForwardRow(
                    row: row,
                    colorScheme: cs,
                    removeTooltip: openHandLocalizedText(
                      context,
                      zh: '移除反向映射',
                      zhHant: '移除反向映射',
                      en: 'Remove reverse mapping',
                      fr: 'Supprimer le mappage inverse',
                      de: 'Reverse-Mapping entfernen',
                      ja: 'リバースマッピングを削除',
                    ),
                    onRemove: _runningDeviceAction
                        ? null
                        : () => _removeReverseFromRow(row),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _runningDeviceAction
                        ? null
                        : () => _runDeviceAction(
                            () => _ctrl
                                .removeAllReverses(serial: serial)
                                .then(
                                  (ok) => AdbCommandResult(
                                    args: const <String>[
                                      'reverse',
                                      '--remove-all',
                                    ],
                                    exitCode: ok ? 0 : 1,
                                    stdout: ok ? 'removed all reverses' : '',
                                    stderr: ok ? '' : 'remove-all failed',
                                  ),
                                ),
                          ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 14),
                    label: Text(
                      openHandLocalizedText(
                        context,
                        zh: '移除全部反向映射',
                        zhHant: '移除全部反向映射',
                        en: 'Remove all reverses',
                        fr: 'Supprimer tous les mappages inverses',
                        de: 'Alle Reverse-Mappings entfernen',
                        ja: 'すべてのリバースマッピングを削除',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          kOpenHandGap14,
          Text(
            openHandLocalizedText(
              context,
              zh: '文件 / APK',
              zhHant: '檔案 / APK',
              en: 'Files / APK',
              fr: 'Fichiers / APK',
              de: 'Dateien / APK',
              ja: 'ファイル / APK',
            ),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          kOpenHandGap6,
          _buildPathActionRow(
            primaryController: _installApkPathCtrl,
            primaryHint: openHandLocalizedText(
              context,
              zh: '本地 APK 路径',
              zhHant: '本機 APK 路徑',
              en: 'local APK path',
              fr: 'chemin APK local',
              de: 'lokaler APK-Pfad',
              ja: 'ローカル APK パス',
            ),
            icon: Icons.install_mobile_rounded,
            label: openHandInstallLabel(context),
            onPressed: serial == null || _runningDeviceAction
                ? null
                : _installApkFromPanel,
          ),
          kOpenHandGap8,
          _buildPathActionRow(
            primaryController: _pushLocalCtrl,
            primaryHint: openHandLocalizedText(
              context,
              zh: '本地路径',
              zhHant: '本機路徑',
              en: 'local path',
              fr: 'chemin local',
              de: 'lokaler Pfad',
              ja: 'ローカルパス',
            ),
            secondaryController: _pushRemoteCtrl,
            secondaryHint: _androidReverseRemotePathLabel(context),
            icon: Icons.upload_file_rounded,
            label: openHandLocalizedText(
              context,
              zh: '推送',
              zhHant: '推送',
              en: 'Push',
              fr: 'Pousser',
              de: 'Push',
              ja: 'Push',
            ),
            onPressed: serial == null || _runningDeviceAction
                ? null
                : _pushFileFromPanel,
          ),
          kOpenHandGap8,
          _buildPathActionRow(
            primaryController: _pullRemoteCtrl,
            primaryHint: _androidReverseRemotePathLabel(context),
            secondaryController: _pullLocalCtrl,
            secondaryHint: openHandLocalizedText(
              context,
              zh: '本地目录 / 文件',
              zhHant: '本機目錄 / 檔案',
              en: 'local dir / file',
              fr: 'dossier / fichier local',
              de: 'lokaler Ordner / Datei',
              ja: 'ローカルディレクトリ / ファイル',
            ),
            icon: Icons.download_rounded,
            label: openHandLocalizedText(
              context,
              zh: '拉取',
              zhHant: '拉取',
              en: 'Pull',
              fr: 'Tirer',
              de: 'Pull',
              ja: 'Pull',
            ),
            onPressed: serial == null || _runningDeviceAction
                ? null
                : _pullFileFromPanel,
          ),
          kOpenHandGap12,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SmallActionButton(
                icon: Icons.battery_charging_full_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '电池',
                  zhHant: '電池',
                  en: 'Battery',
                  fr: 'Batterie',
                  de: 'Akku',
                  ja: 'バッテリー',
                ),
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('dumpsys battery'),
              ),
              _SmallActionButton(
                icon: Icons.aspect_ratio_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '屏幕',
                  zhHant: '螢幕',
                  en: 'Display',
                  fr: 'Écran',
                  de: 'Display',
                  ja: '画面',
                ),
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('wm size; wm density'),
              ),
              _SmallActionButton(
                icon: Icons.home_rounded,
                label: 'HOME',
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('input keyevent KEYCODE_HOME'),
              ),
              _SmallActionButton(
                icon: Icons.arrow_back_rounded,
                label: openHandBackLabel(context),
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('input keyevent KEYCODE_BACK'),
              ),
              _SmallActionButton(
                icon: Icons.view_carousel_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '最近任务',
                  zhHant: '最近任務',
                  en: 'Recents',
                  fr: 'Récents',
                  de: 'Zuletzt',
                  ja: '履歴',
                ),
                onPressed: serial == null
                    ? null
                    : () =>
                          _runShellPreset('input keyevent KEYCODE_APP_SWITCH'),
              ),
              _SmallActionButton(
                icon: Icons.screenshot_monitor_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '截屏',
                  zhHant: '截圖',
                  en: 'Screenshot',
                  fr: 'Capture',
                  de: 'Screenshot',
                  ja: 'スクリーンショット',
                ),
                onPressed: serial == null
                    ? null
                    : () => _runDeviceAction(
                        () => _ctrl.captureScreenshotToArtifacts(
                          serial: _targetSerial,
                        ),
                      ),
              ),
              _SmallActionButton(
                icon: Icons.radio_button_checked_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '录屏 ${_kDefaultScreenRecordSeconds}s',
                  zhHant: '錄影 ${_kDefaultScreenRecordSeconds}s',
                  en: 'Record ${_kDefaultScreenRecordSeconds}s',
                  fr: 'Enregistrer ${_kDefaultScreenRecordSeconds}s',
                  de: '${_kDefaultScreenRecordSeconds}s aufnehmen',
                  ja: '$_kDefaultScreenRecordSeconds秒録画',
                ),
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () => _runDeviceAction(
                        () => _ctrl.screenRecordToArtifacts(
                          serial: _targetSerial,
                        ),
                      ),
              ),
              _SmallActionButton(
                icon: Icons.delete_sweep_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '清 Logcat',
                  zhHant: '清空 Logcat',
                  en: 'Clear logcat',
                  fr: 'Effacer Logcat',
                  de: 'Logcat leeren',
                  ja: 'Logcat をクリア',
                ),
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () async {
                        final confirmed = await _confirmAction(
                          title: openHandLocalizedText(
                            context,
                            zh: '清空设备 Logcat？',
                            zhHant: '清空裝置 Logcat？',
                            en: 'Clear device logcat?',
                            fr: 'Effacer le Logcat de l’appareil ?',
                            de: 'Geräte-Logcat leeren?',
                            ja: 'デバイス Logcat をクリアしますか？',
                          ),
                          message: openHandLocalizedText(
                            context,
                            zh: '将清空当前设备的 Logcat 缓冲区。',
                            zhHant: '將清空目前裝置的 Logcat 緩衝區。',
                            en: 'This clears the current device logcat buffer.',
                            fr: 'Efface le tampon Logcat de l’appareil actuel.',
                            de: 'Leert den Logcat-Puffer des aktuellen Geräts.',
                            ja: '現在のデバイスの Logcat バッファーをクリアします。',
                          ),
                          confirmLabel: openHandClearLabel(context),
                        );
                        if (!confirmed) return;
                        await _runDeviceAction(
                          () =>
                              _ctrl.clearLogcatDetailed(serial: _targetSerial),
                        );
                      },
              ),
              _SmallActionButton(
                icon: Icons.wifi_tethering_rounded,
                label: 'tcpip 5555',
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () => _runDeviceAction(
                        () => _ctrl.tcpip(5555, serial: _targetSerial),
                      ),
              ),
              _SmallActionButton(
                icon: Icons.settings_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '系统设置',
                  zhHant: '系統設定',
                  en: 'Settings',
                  fr: 'Réglages',
                  de: 'Einstellungen',
                  ja: '設定',
                ),
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('settings list global | head -80'),
              ),
              _SmallActionButton(
                icon: Icons.fact_check_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '现场报告',
                  zhHant: '現場報告',
                  en: 'Report',
                  fr: 'Rapport',
                  de: 'Bericht',
                  ja: 'レポート',
                ),
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () => _runDeviceAction(
                        () => _ctrl.captureDeviceReportToArtifacts(
                          serial: _targetSerial,
                        ),
                      ),
              ),
              _SmallActionButton(
                icon: Icons.hub_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '网络地址',
                  zhHant: '網路位址',
                  en: 'IP addr',
                  fr: 'Adresse IP',
                  de: 'IP-Adresse',
                  ja: 'IP アドレス',
                ),
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('ip addr show | grep -E "inet "'),
              ),
              _SmallActionButton(
                icon: Icons.filter_center_focus_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '前台窗口',
                  zhHant: '前景視窗',
                  en: 'Focus',
                  fr: 'Focus',
                  de: 'Fokus',
                  ja: 'フォーカス',
                ),
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset(
                        'dumpsys window | grep -E "mCurrentFocus|mFocusedApp" | head -8',
                      ),
              ),
              _SmallActionButton(
                icon: Icons.sd_storage_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '存储',
                  zhHant: '儲存空間',
                  en: 'Storage',
                  fr: 'Stockage',
                  de: 'Speicher',
                  ja: 'ストレージ',
                ),
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset(
                        'df -h /data /sdcard 2>/dev/null || df /data /sdcard',
                      ),
              ),
              _SmallActionButton(
                icon: Icons.tune_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '属性',
                  zhHant: '屬性',
                  en: 'Props',
                  fr: 'Propriétés',
                  de: 'Eigenschaften',
                  ja: 'プロパティ',
                ),
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset(
                        'getprop | grep -E "ro.product|ro.build|ro.debuggable|ro.secure" | head -120',
                      ),
              ),
              _SmallActionButton(
                icon: Icons.light_mode_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '亮屏',
                  zhHant: '喚醒螢幕',
                  en: 'Wake',
                  fr: 'Réveiller',
                  de: 'Aufwecken',
                  ja: '画面オン',
                ),
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('input keyevent KEYCODE_WAKEUP'),
              ),
              _SmallActionButton(
                icon: Icons.power_settings_new_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '电源键',
                  zhHant: '電源鍵',
                  en: 'Power',
                  fr: 'Alim.',
                  de: 'Power',
                  ja: '電源',
                ),
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('input keyevent KEYCODE_POWER'),
              ),
              _SmallActionButton(
                icon: Icons.volume_up_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '音量+',
                  zhHant: '音量+',
                  en: 'Vol+',
                  fr: 'Vol+',
                  de: 'Lauter',
                  ja: '音量+',
                ),
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('input keyevent KEYCODE_VOLUME_UP'),
              ),
              _SmallActionButton(
                icon: Icons.security_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '包权限',
                  zhHant: '套件權限',
                  en: 'Permissions',
                  fr: 'Autorisations',
                  de: 'Berechtigungen',
                  ja: '権限',
                ),
                onPressed: serial == null || _logcatPackageTarget() == null
                    ? null
                    : () => _runShellPreset(
                        'dumpsys package ${_logcatPackageTarget()} | grep -Ei "requested permissions:|install permissions:|runtime permissions:|android.permission" | head -140',
                      ),
              ),
            ],
          ),
          if (_lastDeviceActionOutput != null &&
              _lastDeviceActionOutput!.trim().isNotEmpty) ...[
            kOpenHandGap12,
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(kOpenHandRadius8),
              ),
              child: _lastDeviceActionResult == null
                  ? _formattedTerminalText(_lastDeviceActionOutput!, cs)
                  : _buildAdbCommandResultView(
                      _lastDeviceActionResult!,
                      cs,
                      theme,
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _connectWirelessDevice() async {
    final endpoint = _wirelessEndpointCtrl.text.trim();
    if (endpoint.isEmpty) return;
    await _runDeviceAction(() => _ctrl.connect(endpoint));
  }

  Future<void> _addForward() async {
    final local = optionalIntFromValue(_forwardLocalCtrl.text);
    final remote = optionalIntFromValue(_forwardRemoteCtrl.text);
    if (!isValidTcpPort(local) || !isValidTcpPort(remote)) {
      _setDeviceActionMessage(
        zh: '端口转发失败：本地端口和设备端口必须在 $_kMinTcpPort-$_kMaxTcpPort 范围内。',
        zhHant: '連接埠轉發失敗：本機連接埠和裝置連接埠必須在 $_kMinTcpPort-$_kMaxTcpPort 範圍內。',
        en: 'Forward failed: local and device ports must be between $_kMinTcpPort and $_kMaxTcpPort.',
        fr: 'Échec de la redirection : les ports local et appareil doivent être entre $_kMinTcpPort et $_kMaxTcpPort.',
        de: 'Weiterleitung fehlgeschlagen: Lokaler und Geräteport müssen zwischen $_kMinTcpPort und $_kMaxTcpPort liegen.',
        ja: '転送に失敗しました: ローカルポートとデバイスポートは $_kMinTcpPort から $_kMaxTcpPort の範囲で指定してください。',
      );
      return;
    }
    await _runDeviceAction(
      () => _ctrl.forwardPortDetailed(local!, remote!, serial: _targetSerial),
    );
  }

  Future<void> _removeForwardFromRow(String row) async {
    final match = RegExp(r'tcp:(\d+)').firstMatch(row);
    final local = optionalIntFromValue(match?.group(1));
    if (local == null) return;
    await _runDeviceAction(
      () => _ctrl.removeForwardDetailed(local, serial: _targetSerial),
    );
  }

  Future<void> _addReverse() async {
    final devicePort = optionalIntFromValue(_reverseDeviceCtrl.text);
    final hostPort = optionalIntFromValue(_reverseHostCtrl.text);
    if (!isValidTcpPort(devicePort) || !isValidTcpPort(hostPort)) {
      _setDeviceActionMessage(
        zh: '反向映射失败：设备端口和主机端口必须在 $_kMinTcpPort-$_kMaxTcpPort 范围内。',
        zhHant: '反向映射失敗：裝置連接埠和主機連接埠必須在 $_kMinTcpPort-$_kMaxTcpPort 範圍內。',
        en: 'Reverse mapping failed: device and host ports must be between $_kMinTcpPort and $_kMaxTcpPort.',
        fr: 'Échec du mappage inverse : les ports appareil et hôte doivent être entre $_kMinTcpPort et $_kMaxTcpPort.',
        de: 'Reverse-Mapping fehlgeschlagen: Geräte- und Host-Port müssen zwischen $_kMinTcpPort und $_kMaxTcpPort liegen.',
        ja: 'リバースマッピングに失敗しました: デバイスポートとホストポートは $_kMinTcpPort から $_kMaxTcpPort の範囲で指定してください。',
      );
      return;
    }
    await _runDeviceAction(
      () => _ctrl.reversePortDetailed(
        devicePort!,
        hostPort!,
        serial: _targetSerial,
      ),
    );
  }

  Future<void> _removeReverseFromRow(String row) async {
    final match = RegExp(r'tcp:(\d+)').firstMatch(row);
    final devicePort = optionalIntFromValue(match?.group(1));
    if (devicePort == null) return;
    await _runDeviceAction(
      () => _ctrl.removeReverseDetailed(devicePort, serial: _targetSerial),
    );
  }

  Future<void> _runShellPreset(String command) async {
    _shellCtrl.text = command;
    await _runShell();
  }

  Future<void> _installApkFromPanel() async {
    final path = _installApkPathCtrl.text.trim();
    if (path.isEmpty) return;
    await _runDeviceAction(
      () => _ctrl.installApkDetailed(path, serial: _targetSerial),
    );
    await _doRefreshPackages();
  }

  Future<void> _pushFileFromPanel() async {
    final local = _pushLocalCtrl.text.trim();
    final remote = _pushRemoteCtrl.text.trim();
    if (local.isEmpty || remote.isEmpty) return;
    await _runDeviceAction(
      () => _ctrl.pushDetailed(local, remote, serial: _targetSerial),
    );
  }

  Future<void> _pullFileFromPanel() async {
    final remote = _pullRemoteCtrl.text.trim();
    final local = _pullLocalCtrl.text.trim();
    if (remote.isEmpty || local.isEmpty) return;
    await _runDeviceAction(
      () => _ctrl.pullDetailed(remote, local, serial: _targetSerial),
    );
  }

  Future<void> _showDeviceMenu(AdbDevice device, Offset? globalPosition) async {
    final selected = await showAnimatedPointerMenu<_DeviceMenuAction>(
      context: context,
      globalPosition: globalPosition,
      items: [
        PopupMenuItem(
          value: _DeviceMenuAction.useForPanel,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '设为面板目标',
              zhHant: '設為面板目標',
              en: 'Use for panel',
              fr: 'Utiliser dans le panneau',
              de: 'Für Panel nutzen',
              ja: 'パネル対象にする',
            ),
          ),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.copySerial,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '复制序列号',
              zhHant: '複製序號',
              en: 'Copy serial',
              fr: 'Copier le numéro de série',
              de: 'Seriennummer kopieren',
              ja: 'シリアルをコピー',
            ),
          ),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.refreshProps,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '刷新属性 / 现场',
              zhHant: '重新整理屬性 / 現場',
              en: 'Refresh properties / snapshot',
              fr: 'Actualiser propriétés / snapshot',
              de: 'Eigenschaften / Snapshot aktualisieren',
              ja: 'プロパティ / スナップショット更新',
            ),
          ),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.listForwards,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '查看端口映射',
              zhHant: '查看連接埠映射',
              en: 'List port mappings',
              fr: 'Lister les mappages de ports',
              de: 'Portmappings anzeigen',
              ja: 'ポートマッピングを表示',
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _DeviceMenuAction.tcpip5555,
          child: Text('adb tcpip 5555'),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.deviceReport,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '生成现场报告',
              zhHant: '產生現場報告',
              en: 'Generate field report',
              fr: 'Générer le rapport terrain',
              de: 'Feldbericht erstellen',
              ja: '現場レポートを生成',
            ),
          ),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.screenshot,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '截屏到工件目录',
              zhHant: '截圖到工件目錄',
              en: 'Capture screenshot',
              fr: 'Capturer l’écran',
              de: 'Screenshot aufnehmen',
              ja: 'スクリーンショットを保存',
            ),
          ),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.screenRecord,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '录屏 $_kDefaultScreenRecordSeconds 秒到工件目录',
              zhHant: '錄影 $_kDefaultScreenRecordSeconds 秒到工件目錄',
              en: 'Record $_kDefaultScreenRecordSeconds seconds',
              fr: 'Enregistrer $_kDefaultScreenRecordSeconds secondes',
              de: '$_kDefaultScreenRecordSeconds Sekunden aufnehmen',
              ja: '$_kDefaultScreenRecordSeconds 秒録画',
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _DeviceMenuAction.root,
          child: Text('adb root'),
        ),
        const PopupMenuItem(
          value: _DeviceMenuAction.remount,
          child: Text('adb remount'),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.reboot,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '重启设备',
              zhHant: '重新啟動裝置',
              en: 'Reboot',
              fr: 'Redémarrer',
              de: 'Neustarten',
              ja: '再起動',
            ),
          ),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.disconnect,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '断开连接',
              zhHant: '中斷連線',
              en: 'Disconnect',
              fr: 'Déconnecter',
              de: 'Trennen',
              ja: '切断',
            ),
          ),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case _DeviceMenuAction.useForPanel:
        _setTargetDevice(device.serial);
        await _refreshDeviceDetails();
        await _doRefreshPackages();
        await _doRefreshProcesses();
      case _DeviceMenuAction.copySerial:
        await _copyText(device.serial);
      case _DeviceMenuAction.refreshProps:
        _setTargetDevice(device.serial);
        await _refreshDeviceDetails();
      case _DeviceMenuAction.listForwards:
        _setTargetDevice(device.serial);
        await _refreshDeviceDetails();
      case _DeviceMenuAction.tcpip5555:
        _setTargetDevice(device.serial);
        await _runDeviceAction(() => _ctrl.tcpip(5555, serial: device.serial));
      case _DeviceMenuAction.deviceReport:
        _setTargetDevice(device.serial);
        await _runDeviceAction(
          () => _ctrl.captureDeviceReportToArtifacts(serial: device.serial),
        );
      case _DeviceMenuAction.screenshot:
        _setTargetDevice(device.serial);
        await _runDeviceAction(
          () => _ctrl.captureScreenshotToArtifacts(serial: device.serial),
        );
      case _DeviceMenuAction.screenRecord:
        _setTargetDevice(device.serial);
        await _runDeviceAction(
          () => _ctrl.screenRecordToArtifacts(serial: device.serial),
        );
      case _DeviceMenuAction.root:
        _setTargetDevice(device.serial);
        await _runDeviceAction(() => _ctrl.root(serial: device.serial));
      case _DeviceMenuAction.remount:
        _setTargetDevice(device.serial);
        await _runDeviceAction(() => _ctrl.remount(serial: device.serial));
      case _DeviceMenuAction.reboot:
        _setTargetDevice(device.serial);
        await _runDeviceAction(() => _ctrl.reboot(serial: device.serial));
      case _DeviceMenuAction.disconnect:
        _setTargetDevice(device.serial);
        await _runDeviceAction(() => _ctrl.disconnect(device.serial));
    }
  }

  void _setDeviceActionMessage({
    required String zh,
    String? zhHant,
    required String en,
    String? fr,
    String? de,
    String? ja,
  }) {
    if (!mounted) return;
    setState(() {
      _lastDeviceActionResult = null;
      _lastDeviceActionOutput = openHandLocalizedText(
        context,
        zh: zh,
        zhHant: zhHant,
        en: en,
        fr: fr,
        de: de,
        ja: ja,
      );
    });
  }

  Future<void> _showPackageMenu(
    String packageName,
    Offset? globalPosition,
  ) async {
    final selected = await showAnimatedPointerMenu<_PackageMenuAction>(
      context: context,
      globalPosition: globalPosition,
      items: [
        PopupMenuItem(
          value: _PackageMenuAction.analyze,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '分析 APP 信息',
              zhHant: '分析 APP 資訊',
              en: 'Analyze app info',
              fr: 'Analyser l’APP',
              de: 'APP-Info analysieren',
              ja: 'APP 情報を解析',
            ),
          ),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.report,
          child: Text(_androidReverseGenerateAppReportLabel(context)),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.copyPackage,
          child: Text(_androidReverseCopyPackageNameLabel(context)),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.logcat,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '按此包过滤 Logcat',
              zhHant: '依此套件篩選 Logcat',
              en: 'Filter Logcat by package',
              fr: 'Filtrer Logcat par package',
              de: 'Logcat nach Paket filtern',
              ja: 'パッケージで Logcat を絞り込み',
            ),
          ),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.pullApks,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '拉取 APK 到工件目录',
              zhHant: '拉取 APK 到工件目錄',
              en: 'Pull APKs to artifacts',
              fr: 'Extraire les APK vers les artefacts',
              de: 'APKs in Artefakte ziehen',
              ja: 'APK を成果物へ取得',
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _PackageMenuAction.launch,
          child: Text(_androidReverseLaunchAppLabel(context)),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.forceStop,
          child: Text(_androidReverseForceStopLabel(context)),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.clearData,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '清除数据...',
              zhHant: '清除資料...',
              en: 'Clear data...',
              fr: 'Effacer les données...',
              de: 'Daten löschen...',
              ja: 'データを消去...',
            ),
          ),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.uninstall,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '卸载...',
              zhHant: '解除安裝...',
              en: 'Uninstall...',
              fr: 'Désinstaller...',
              de: 'Deinstallieren...',
              ja: 'アンインストール...',
            ),
          ),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    await _handlePackageAction(packageName, selected);
  }

  Future<void> _handlePackageAction(
    String packageName,
    _PackageMenuAction action,
  ) async {
    switch (action) {
      case _PackageMenuAction.analyze:
        await _analyzePackage(packageName);
      case _PackageMenuAction.report:
        await _capturePackageReport(packageName);
      case _PackageMenuAction.copyPackage:
        await _copyText(packageName);
      case _PackageMenuAction.logcat:
        setState(() {
          _selectedPackageName = packageName;
          _logcatPackageFilterEnabled = true;
          _logcatPidCtrl.clear();
          _currentTab = _Tab.logcat;
        });
        await _fetchLogcat();
      case _PackageMenuAction.pullApks:
        await _runDeviceAction(
          () =>
              _ctrl.pullPackageApksDetailed(packageName, serial: _targetSerial),
        );
      case _PackageMenuAction.launch:
        await _runDeviceAction(
          () => _ctrl.startPackageDetailed(packageName, serial: _targetSerial),
        );
      case _PackageMenuAction.forceStop:
        await _runDeviceAction(
          () => _ctrl.forceStopAppDetailed(packageName, serial: _targetSerial),
        );
      case _PackageMenuAction.clearData:
        final confirmed = await _confirmAction(
          title: openHandLocalizedText(
            context,
            zh: '清除 APP 数据',
            zhHant: '清除 APP 資料',
            en: 'Clear app data',
            fr: 'Effacer les données APP',
            de: 'APP-Daten löschen',
            ja: 'APP データを消去',
          ),
          message: openHandLocalizedText(
            context,
            zh: '将执行 pm clear $packageName，应用数据会被清空。',
            zhHant: '將執行 pm clear $packageName，應用資料會被清空。',
            en: 'This will run pm clear $packageName and erase app data.',
            fr: 'Exécute pm clear $packageName et efface les données de l’APP.',
            de: 'Führt pm clear $packageName aus und löscht die APP-Daten.',
            ja: 'pm clear $packageName を実行し、APP データを消去します。',
          ),
          confirmLabel: openHandLocalizedText(
            context,
            zh: '清除',
            zhHant: '清除',
            en: 'Clear',
            fr: 'Effacer',
            de: 'Löschen',
            ja: '消去',
          ),
        );
        if (!confirmed) return;
        await _runDeviceAction(
          () => _ctrl.clearPackageDataDetailed(
            packageName,
            serial: _targetSerial,
          ),
        );
      case _PackageMenuAction.uninstall:
        final confirmed = await _confirmAction(
          title: openHandLocalizedText(
            context,
            zh: '卸载 APP',
            zhHant: '解除安裝 APP',
            en: 'Uninstall app',
            fr: 'Désinstaller l’APP',
            de: 'APP deinstallieren',
            ja: 'APP をアンインストール',
          ),
          message: openHandLocalizedText(
            context,
            zh: '将从当前设备卸载 $packageName。',
            zhHant: '將從目前裝置解除安裝 $packageName。',
            en: 'This will uninstall $packageName from the current device.',
            fr: 'Désinstalle $packageName de l’appareil actuel.',
            de: 'Deinstalliert $packageName vom aktuellen Gerät.',
            ja: '現在のデバイスから $packageName をアンインストールします。',
          ),
          confirmLabel: _androidReverseUninstallLabel(context),
        );
        if (!confirmed) return;
        await _runDeviceAction(
          () => _ctrl.uninstallPackageDetailed(
            packageName,
            serial: _targetSerial,
          ),
        );
        await _doRefreshPackages();
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return showOpenHandConfirmDialog(
      context: context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: true,
    );
  }

  Future<void> _showProcessMenu(
    AndroidProcess process,
    Offset? globalPosition,
  ) async {
    final isPackageProcess = looksLikeAndroidPackageName(process.name);
    final selected = await showAnimatedPointerMenu<_ProcessMenuAction>(
      context: context,
      globalPosition: globalPosition,
      items: [
        PopupMenuItem(
          value: _ProcessMenuAction.copyPid,
          child: Text(_androidReverseCopyPidLabel(context)),
        ),
        PopupMenuItem(
          value: _ProcessMenuAction.copyName,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '复制进程名',
              zhHant: '複製程序名稱',
              en: 'Copy process name',
              fr: 'Copier le nom du processus',
              de: 'Prozessnamen kopieren',
              ja: 'プロセス名をコピー',
            ),
          ),
        ),
        PopupMenuItem(
          value: _ProcessMenuAction.logcatPid,
          child: Text(
            openHandLocalizedText(
              context,
              zh: '按 PID 过滤 Logcat',
              zhHant: '依 PID 篩選 Logcat',
              en: 'Filter Logcat by PID',
              fr: 'Filtrer Logcat par PID',
              de: 'Logcat nach PID filtern',
              ja: 'PID で Logcat を絞り込み',
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _ProcessMenuAction.kill,
          child: Text(
            openHandLocalizedText(
              context,
              zh: 'kill -9 进程...',
              zhHant: 'kill -9 程序...',
              en: 'kill -9 process...',
              fr: 'kill -9 processus...',
              de: 'Prozess mit kill -9 beenden...',
              ja: 'kill -9 プロセス...',
            ),
          ),
        ),
        if (isPackageProcess)
          PopupMenuItem(
            value: _ProcessMenuAction.forceStopPackage,
            child: Text(
              openHandLocalizedText(
                context,
                zh: '强制停止包名',
                zhHant: '強制停止套件',
                en: 'Force-stop package',
                fr: 'Forcer l’arrêt du package',
                de: 'Paket-Stopp erzwingen',
                ja: 'パッケージを強制停止',
              ),
            ),
          ),
      ],
    );
    if (!mounted || selected == null) return;
    await _handleProcessAction(process, selected);
  }

  Future<void> _handleProcessAction(
    AndroidProcess process,
    _ProcessMenuAction action,
  ) async {
    switch (action) {
      case _ProcessMenuAction.copyPid:
        await _copyText('${process.pid}');
      case _ProcessMenuAction.copyName:
        await _copyText(process.name);
      case _ProcessMenuAction.logcatPid:
        setState(() {
          _logcatPidCtrl.text = '${process.pid}';
          _logcatPackageFilterEnabled = false;
          _currentTab = _Tab.logcat;
        });
        await _fetchLogcat();
      case _ProcessMenuAction.kill:
        final confirmed = await _confirmAction(
          title: openHandLocalizedText(
            context,
            zh: '终止进程',
            zhHant: '終止程序',
            en: 'Kill process',
            fr: 'Tuer le processus',
            de: 'Prozess beenden',
            ja: 'プロセスを終了',
          ),
          message: openHandLocalizedText(
            context,
            zh: '将执行 kill -9 ${process.pid} (${process.name})。',
            zhHant: '將執行 kill -9 ${process.pid} (${process.name})。',
            en: 'This will run kill -9 ${process.pid} (${process.name}).',
            fr: 'Exécute kill -9 ${process.pid} (${process.name}).',
            de: 'Führt kill -9 ${process.pid} (${process.name}) aus.',
            ja: 'kill -9 ${process.pid} (${process.name}) を実行します。',
          ),
          confirmLabel: 'kill -9',
        );
        if (!confirmed) return;
        await _runDeviceAction(
          () => _ctrl.killProcessDetailed(process.pid, serial: _targetSerial),
        );
        await _doRefreshProcesses();
      case _ProcessMenuAction.forceStopPackage:
        if (!looksLikeAndroidPackageName(process.name)) return;
        await _runDeviceAction(
          () => _ctrl.forceStopAppDetailed(process.name, serial: _targetSerial),
        );
        await _doRefreshProcesses();
    }
  }

  // ── Overview tab ────────────────────────────────────────────────────────

  Widget _buildOverviewTab(ColorScheme cs, ThemeData theme) {
    final config = _ctrl.config;
    final device = _ctrl.connectedDevice;
    final items = <(String, String)>[
      (openHandObjectiveLabel(context), config.objective),
      if (config.packageName != null)
        (
          openHandLocalizedText(
            context,
            zh: '包名',
            zhHant: '套件名稱',
            en: 'Package',
            fr: 'Package',
            de: 'Paket',
            ja: 'パッケージ',
          ),
          config.packageName!,
        ),
      if (config.apkPath != null)
        (
          openHandLocalizedText(
            context,
            zh: 'APK 路径',
            zhHant: 'APK 路徑',
            en: 'APK path',
            fr: 'Chemin APK',
            de: 'APK-Pfad',
            ja: 'APK パス',
          ),
          config.apkPath!,
        ),
      (
        openHandLocalizedText(
          context,
          zh: '分析模式',
          zhHant: '分析模式',
          en: 'Analysis mode',
          fr: 'Mode d’analyse',
          de: 'Analysemodus',
          ja: '解析モード',
        ),
        _analysisModeLabel(config),
      ),
      if (config.authorizationScope != null &&
          config.authorizationScope!.trim().isNotEmpty)
        (
          openHandLocalizedText(
            context,
            zh: '授权范围',
            zhHant: '授權範圍',
            en: 'Authorization',
            fr: 'Autorisation',
            de: 'Autorisierung',
            ja: '認可範囲',
          ),
          config.authorizationScope!.trim(),
        ),
      ('ADB MCP', _enabledStateLabel(config.adbMcpEnabled)),
      ('Frida MCP', _enabledStateLabel(config.fridaMcpEnabled)),
      if (device != null) ...[
        (
          openHandLocalizedText(
            context,
            zh: '设备型号',
            zhHant: '裝置型號',
            en: 'Device model',
            fr: 'Modèle appareil',
            de: 'Gerätemodell',
            ja: 'デバイスモデル',
          ),
          device.model ?? device.serial,
        ),
        (
          openHandLocalizedText(
            context,
            zh: '设备序列号',
            zhHant: '裝置序號',
            en: 'Device serial',
            fr: 'Numéro de série',
            de: 'Geräteseriennummer',
            ja: 'デバイスシリアル',
          ),
          device.serial,
        ),
      ] else if (config.deviceSerial != null &&
          config.deviceSerial!.trim().isNotEmpty) ...[
        (
          openHandLocalizedText(
            context,
            zh: '配置设备',
            zhHant: '設定裝置',
            en: 'Configured serial',
            fr: 'Série configurée',
            de: 'Konfigurierte Seriennummer',
            ja: '設定済みシリアル',
          ),
          config.deviceSerial!.trim(),
        ),
      ],
      if (config.keywords.isNotEmpty)
        (openHandKeywordsLabel(context), config.keywords.join(', ')),
      if (config.notes != null && config.notes!.isNotEmpty)
        (openHandNotesLabel(context), config.notes!),
    ];
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _dashboardSectionHeader(
            leading: const [],
            actions: [
              _DashboardActionButton(
                onPressed: _makingEvidenceBundle ? null : _makeEvidenceBundle,
                icon: Icons.inventory_2_rounded,
                busy: _makingEvidenceBundle,
                label: openHandLocalizedText(
                  context,
                  zh: '生成证据包',
                  zhHant: '產生證據包',
                  en: 'Make evidence bundle',
                  fr: 'Créer le paquet de preuves',
                  de: 'Beweispaket erstellen',
                  ja: '証拠パッケージを作成',
                ),
              ),
              if (_evidenceBundleOutput?.trim().isNotEmpty ?? false)
                _copyResultButton(_evidenceBundleOutput!.trim()),
            ],
          ),
          if (_evidenceBundleOutput?.trim().isNotEmpty ?? false) ...[
            kOpenHandGap10,
            _monospaceCard(cs, _evidenceBundleOutput!.trim()),
          ],
          kOpenHandGap12,
          for (final (label, value) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  kOpenHandHGap12,
                  Expanded(
                    child: OpenHandTapRegion(
                      onTap: () => _copyText(value),
                      child: Text(
                        value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: value.contains('/')
                              ? kOpenHandMonospaceFontFamily
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _analysisModeLabel(AndroidReverseSessionConfig config) {
    return switch (config.analysisMode) {
      AndroidReverseAnalysisMode.staticFirst => openHandLocalizedText(
        context,
        zh: config.analysisMode.labelZh,
        zhHant: '靜態優先',
        en: 'Static first',
        fr: 'Statique d’abord',
        de: 'Statisch zuerst',
        ja: '静的優先',
      ),
      AndroidReverseAnalysisMode.balanced => openHandLocalizedText(
        context,
        zh: config.analysisMode.labelZh,
        zhHant: '均衡',
        en: 'Balanced',
        fr: 'Équilibré',
        de: 'Ausgewogen',
        ja: 'バランス',
      ),
      AndroidReverseAnalysisMode.dynamicFirst => openHandLocalizedText(
        context,
        zh: config.analysisMode.labelZh,
        zhHant: '動態優先',
        en: 'Dynamic first',
        fr: 'Dynamique d’abord',
        de: 'Dynamisch zuerst',
        ja: '動的優先',
      ),
    };
  }

  String _enabledStateLabel(bool enabled) {
    return enabled
        ? openHandLocalizedText(
            context,
            zh: '已启用',
            zhHant: '已啟用',
            en: 'enabled',
            fr: 'activé',
            de: 'aktiviert',
            ja: '有効',
          )
        : openHandLocalizedText(
            context,
            zh: '未启用',
            zhHant: '未啟用',
            en: 'disabled',
            fr: 'désactivé',
            de: 'deaktiviert',
            ja: '無効',
          );
  }

  // ── Toolchain tab ───────────────────────────────────────────────────────

  Widget _buildToolchainTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final pluginController = context.watch<PluginServiceController>();
    final requiredMissing = _toolchainRows
        .where((row) => row.probe.required && !row.ok)
        .length;
    final optionalMissing = _toolchainRows
        .where((row) => !row.probe.required && !row.ok)
        .length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: _dashboardSectionHeader(
            leading: [
              if (_toolchainRows.isNotEmpty)
                _StatusPill(
                  label: openHandLocalizedText(
                    context,
                    zh: '必需缺失 $requiredMissing · 可选缺失 $optionalMissing',
                    zhHant: '必要缺失 $requiredMissing · 可選缺失 $optionalMissing',
                    en: 'required missing $requiredMissing · optional missing $optionalMissing',
                    fr: 'requis manquants $requiredMissing · optionnels manquants $optionalMissing',
                    de: 'erforderlich fehlt $requiredMissing · optional fehlt $optionalMissing',
                    ja: '必須不足 $requiredMissing · 任意不足 $optionalMissing',
                  ),
                  color: requiredMissing == 0 ? cs.primary : cs.error,
                ),
            ],
            actions: [
              _DashboardActionButton(
                onPressed: _loadingToolchain ? null : _refreshToolchain,
                icon: Icons.refresh_rounded,
                busy: _loadingToolchain,
                label: openHandRefreshLabel(context),
              ),
            ],
          ),
        ),
        if (_lastToolchainCommandResult != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(kOpenHandRadius8),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.58),
                ),
              ),
              child: _buildAdbCommandResultView(
                _lastToolchainCommandResult!,
                cs,
                theme,
              ),
            ),
          ),
        Expanded(
          child: OpenHandContentStateSwitcher(
            stateKey: _loadingToolchain && _toolchainRows.isEmpty
                ? 'loading'
                : 'list',
            animateSize: false,
            child: _loadingToolchain && _toolchainRows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : OpenHandSafeScrollbar(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: _toolchainRows.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: cs.outlineVariant),
                      itemBuilder: (_, i) {
                        final row = _toolchainRows[i];
                        final plugin = _toolchainPluginForProbe(
                          row.probe,
                          pluginController,
                        );
                        final ok = row.ok;
                        final statusColor = ok
                            ? cs.primary
                            : row.probe.required
                            ? cs.error
                            : cs.tertiary;
                        return ListTile(
                          leading: Icon(
                            ok
                                ? Icons.check_circle_rounded
                                : Icons.error_outline_rounded,
                            color: statusColor,
                          ),
                          title: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                row.probe.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (row.probe.required)
                                _StatusPill(
                                  label: openHandLocalizedText(
                                    context,
                                    zh: '必需',
                                    zhHant: '必要',
                                    en: 'required',
                                    fr: 'requis',
                                    de: 'erforderlich',
                                    ja: '必須',
                                  ),
                                  color: cs.error,
                                  compact: true,
                                  subtle: true,
                                ),
                              if (plugin != null)
                                _StatusPill(
                                  label: openHandLocalizedText(
                                    context,
                                    zh: '插件托管',
                                    zhHant: '外掛托管',
                                    en: 'plugin-managed',
                                    fr: 'géré par plugin',
                                    de: 'pluginverwaltet',
                                    ja: 'プラグイン管理',
                                  ),
                                  color: cs.secondary,
                                  compact: true,
                                  subtle: true,
                                ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  ok
                                      ? row.displayValue
                                      : _androidToolchainInstallHint(
                                          context,
                                          row.probe,
                                        ),
                                  style: TextStyle(
                                    fontFamily: ok
                                        ? kOpenHandMonospaceFontFamily
                                        : null,
                                    fontSize: 12,
                                    color: ok ? cs.onSurface : statusColor,
                                  ),
                                ),
                                kOpenHandGap2,
                                Text(
                                  '${openHandLocalizedText(context, zh: "耗时", zhHant: "耗時", en: "Duration", fr: "Durée", de: "Dauer", ja: "所要時間")}: ${row.durationMs}ms',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _DashboardIconActionButton(
                                icon: Icons.copy_rounded,
                                tooltip: openHandLocalizedText(
                                  context,
                                  zh: '复制诊断',
                                  zhHant: '複製診斷',
                                  en: 'Copy diagnostic',
                                  fr: 'Copier le diagnostic',
                                  de: 'Diagnose kopieren',
                                  ja: '診断をコピー',
                                ),
                                onPressed: () => _copyText(
                                  '${row.probe.label}\n${row.displayValue}\n${_androidToolchainInstallHint(context, row.probe)}',
                                ),
                              ),
                              const SizedBox(
                                width: _kDashboardTrailingActionGap,
                              ),
                              _DashboardPopupIconActionButton<
                                _ToolchainCommandAction
                              >(
                                tooltip: openHandLocalizedText(
                                  context,
                                  zh: '安装 / 更新 / 卸载 / 信息',
                                  zhHant: '安裝 / 更新 / 解除安裝 / 資訊',
                                  en: 'Install / update / uninstall / info',
                                  fr: 'Installer / mettre à jour / désinstaller / infos',
                                  de: 'Installieren / aktualisieren / deinstallieren / Info',
                                  ja: 'インストール / 更新 / アンインストール / 情報',
                                ),
                                icon: const Icon(Icons.terminal_rounded),
                                itemBuilder: (context) =>
                                    _toolchainCommandMenuItems(row.probe),
                                onSelected: (action) =>
                                    _handleToolchainAction(row.probe, action),
                              ),
                            ],
                          ),
                          dense: true,
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ── MCP tab ─────────────────────────────────────────────────────────────

  Widget _buildMcpTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final mcpController = context.watch<McpController>();
    final capabilities =
        TemplateRuntimeDependencyRegistry.androidReverse.mcpCapabilities;
    final serverRows = _androidMcpServerViews(mcpController);
    final configuredCapabilityCount = capabilities.where((capability) {
      return _matchingAndroidMcpServersForCapability(
        mcpController,
        capability,
      ).isNotEmpty;
    }).length;
    final totalAndroidTools = serverRows.fold<int>(
      0,
      (sum, row) => sum + row.matchedTools.length,
    );

    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        children: [
          _dashboardSectionHeader(
            leading: [
              _StatusPill(
                label: openHandLocalizedText(
                  context,
                  zh: '$configuredCapabilityCount/${capabilities.length} 个能力 · $totalAndroidTools 个工具',
                  zhHant:
                      '$configuredCapabilityCount/${capabilities.length} 個能力 · $totalAndroidTools 個工具',
                  en: '$configuredCapabilityCount/${capabilities.length} capabilities · $totalAndroidTools tools',
                  fr: '$configuredCapabilityCount/${capabilities.length} capacités · $totalAndroidTools outils',
                  de: '$configuredCapabilityCount/${capabilities.length} Fähigkeiten · $totalAndroidTools Tools',
                  ja: '$configuredCapabilityCount/${capabilities.length} 件の機能 · $totalAndroidTools 件のツール',
                ),
                color: cs.primary,
              ),
            ],
            actions: [
              _DashboardActionButton(
                onPressed: mcpController.isLoading
                    ? null
                    : () => unawaited(mcpController.refresh()),
                icon: Icons.sync_rounded,
                busy: mcpController.isLoading,
                label: openHandLocalizedText(
                  context,
                  zh: '刷新 MCP',
                  zhHant: '重新整理 MCP',
                  en: 'Refresh MCP',
                  fr: 'Actualiser MCP',
                  de: 'MCP aktualisieren',
                  ja: 'MCP を更新',
                ),
              ),
              _DashboardActionButton(
                onPressed: _writingMcpArtifacts
                    ? null
                    : _ensureMcpLinkageArtifacts,
                icon: Icons.article_rounded,
                busy: _writingMcpArtifacts,
                label: openHandLocalizedText(
                  context,
                  zh: '生成联动工件',
                  zhHant: '產生聯動工件',
                  en: 'Generate artifacts',
                  fr: 'Générer les artefacts',
                  de: 'Artefakte erstellen',
                  ja: '成果物を生成',
                ),
              ),
            ],
          ),
          if (_mcpArtifactOutput?.trim().isNotEmpty ?? false) ...[
            kOpenHandGap8,
            _monospaceCard(cs, _mcpArtifactOutput!.trim()),
          ],
          kOpenHandGap18,
          _sectionTitle(
            theme,
            cs,
            openHandLocalizedText(
              context,
              zh: '推荐 MCP 能力',
              zhHant: '推薦 MCP 能力',
              en: 'Recommended MCP capabilities',
              fr: 'Capacités MCP recommandées',
              de: 'Empfohlene MCP-Fähigkeiten',
              ja: '推奨 MCP 機能',
            ),
          ),
          kOpenHandGap8,
          for (final capability in capabilities) ...[
            _buildAndroidMcpCapabilityCard(
              capability,
              mcpController,
              cs,
              theme,
            ),
            kOpenHandGap8,
          ],
          kOpenHandGap18,
          _sectionTitle(
            theme,
            cs,
            openHandLocalizedText(
              context,
              zh: 'Android 相关 MCP',
              zhHant: 'Android 相關 MCP',
              en: 'Android-related MCP',
              fr: 'MCP liés à Android',
              de: 'Android-bezogene MCP',
              ja: 'Android 関連 MCP',
            ),
          ),
          kOpenHandGap8,
          if (mcpController.errorMessage?.trim().isNotEmpty ?? false) ...[
            _InfoCard(
              cs: cs,
              theme: theme,
              icon: Icons.error_outline_rounded,
              text:
                  '${openHandLocalizedText(context, zh: "MCP 加载异常", zhHant: "MCP 載入異常", en: "MCP load error", fr: "Erreur de chargement MCP", de: "MCP-Ladefehler", ja: "MCP 読み込みエラー")}: ${mcpController.errorMessage}',
            ),
            kOpenHandGap8,
          ],
          if (serverRows.isEmpty)
            _InfoCard(
              cs: cs,
              theme: theme,
              icon: Icons.search_off_rounded,
              text: openHandLocalizedText(
                context,
                zh: '当前未发现名称、命令或工具描述中包含 ADB / Android / Frida / IDA / jadx / apktool / Flutter 逆向关键词的 MCP server。',
                zhHant:
                    '目前未發現名稱、指令或工具描述中包含 ADB / Android / Frida / IDA / jadx / apktool / Flutter 逆向關鍵字的 MCP server。',
                en: 'No configured MCP server currently matches ADB / Android / Frida / IDA / jadx / apktool / Flutter reverse keywords.',
                fr: 'Aucun server MCP configuré ne correspond aux mots-clés ADB / Android / Frida / IDA / jadx / apktool / Flutter reverse.',
                de: 'Kein konfigurierter MCP server passt derzeit zu ADB / Android / Frida / IDA / jadx / apktool / Flutter-Reverse-Keywords.',
                ja: 'ADB / Android / Frida / IDA / jadx / apktool / Flutter リバース関連キーワードに一致する MCP server はありません。',
              ),
            )
          else
            for (final row in serverRows) ...[
              _buildMcpServerCard(row, cs, theme, isZh),
              kOpenHandGap8,
            ],
        ],
      ),
    );
  }

  // ── Plugins tab ────────────────────────────────────────────────────────

  Widget _buildPluginsTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final pluginController = context.watch<PluginServiceController>();
    final runtimePlugins = _kAndroidRuntimePluginIds
        .map(pluginController.pluginById)
        .whereType<PluginInfo>()
        .toList(growable: false);
    final installedRuntimeCount = runtimePlugins
        .where((plugin) => plugin.isInstalled)
        .length;

    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        children: [
          _dashboardSectionHeader(
            leading: [
              _StatusPill(
                label: openHandLocalizedText(
                  context,
                  zh: '$installedRuntimeCount/${runtimePlugins.length} 个前置条件可用',
                  zhHant:
                      '$installedRuntimeCount/${runtimePlugins.length} 個前置條件可用',
                  en: '$installedRuntimeCount/${runtimePlugins.length} prerequisites ready',
                  fr: '$installedRuntimeCount/${runtimePlugins.length} prérequis prêts',
                  de: '$installedRuntimeCount/${runtimePlugins.length} Voraussetzungen bereit',
                  ja: '$installedRuntimeCount/${runtimePlugins.length} 件の前提条件が利用可能',
                ),
                color: installedRuntimeCount == runtimePlugins.length
                    ? cs.primary
                    : cs.tertiary,
              ),
            ],
            actions: [
              _DashboardActionButton(
                onPressed: pluginController.isBusy
                    ? null
                    : () => unawaited(pluginController.rescan()),
                icon: Icons.refresh_rounded,
                busy: pluginController.isLoading,
                label: openHandLocalizedText(
                  context,
                  zh: '扫描插件',
                  zhHant: '掃描外掛',
                  en: 'Scan plugins',
                  fr: 'Scanner les plugins',
                  de: 'Plugins scannen',
                  ja: 'プラグインをスキャン',
                ),
              ),
              _DashboardActionButton(
                onPressed: _loadingToolchain ? null : _refreshToolchain,
                icon: Icons.construction_rounded,
                busy: _loadingToolchain,
                label: openHandLocalizedText(
                  context,
                  zh: '刷新工具链',
                  zhHant: '重新整理工具鏈',
                  en: 'Refresh tools',
                  fr: 'Actualiser les outils',
                  de: 'Tools aktualisieren',
                  ja: 'ツールを更新',
                ),
              ),
            ],
          ),
          kOpenHandGap14,
          _sectionTitle(
            theme,
            cs,
            openHandLocalizedText(
              context,
              zh: '相邻运行时前置条件',
              zhHant: '相鄰執行期前置條件',
              en: 'Adjacent runtime prerequisites',
              fr: 'Prérequis du runtime adjacent',
              de: 'Benachbarte Runtime-Voraussetzungen',
              ja: '隣接ランタイム前提条件',
            ),
          ),
          kOpenHandGap8,
          if (pluginController.errorMessage?.trim().isNotEmpty ?? false) ...[
            _InfoCard(
              cs: cs,
              theme: theme,
              icon: Icons.error_outline_rounded,
              text:
                  '${openHandLocalizedText(context, zh: "插件扫描异常", zhHant: "外掛掃描異常", en: "Plugin scan error", fr: "Erreur de scan plugin", de: "Plugin-Scanfehler", ja: "プラグインスキャンエラー")}: ${pluginController.errorMessage}',
            ),
            kOpenHandGap8,
          ],
          if (runtimePlugins.isEmpty)
            _InfoCard(
              cs: cs,
              theme: theme,
              icon: Icons.hourglass_empty_rounded,
              text: pluginController.isLoading
                  ? openHandLocalizedText(
                      context,
                      zh: '正在扫描插件运行时...',
                      zhHant: '正在掃描外掛執行期...',
                      en: 'Scanning plugin runtimes...',
                      fr: 'Scan des runtimes de plugins...',
                      de: 'Plugin-Runtimes werden gescannt...',
                      ja: 'プラグインランタイムをスキャン中...',
                    )
                  : openHandLocalizedText(
                      context,
                      zh: '插件服务暂未返回 Android 逆向关联插件状态。',
                      zhHant: '外掛服務尚未返回 Android 逆向關聯外掛狀態。',
                      en: 'Plugin service has not reported Android reverse plugin status.',
                      fr: 'Le service de plugins n’a pas encore renvoyé l’état des plugins Android reverse.',
                      de: 'Der Plugin-Dienst hat den Status der Android-Reverse-Plugins noch nicht gemeldet.',
                      ja: 'プラグインサービスは Android リバース関連プラグインの状態をまだ返していません。',
                    ),
            )
          else
            for (final plugin in runtimePlugins) ...[
              _buildRuntimePluginTile(
                plugin,
                pluginController,
                cs,
                theme,
                isZh,
              ),
              kOpenHandGap8,
            ],
          kOpenHandGap14,
          _sectionTitle(
            theme,
            cs,
            openHandLocalizedText(
              context,
              zh: 'CLI 工具操作建议',
              zhHant: 'CLI 工具操作建議',
              en: 'CLI tool setup actions',
              fr: 'Actions de configuration CLI',
              de: 'CLI-Tool-Einrichtung',
              ja: 'CLI ツール設定アクション',
            ),
          ),
          kOpenHandGap8,
          OpenHandContentStateSwitcher(
            stateKey: _loadingToolchain && _toolchainRows.isEmpty
                ? 'loading'
                : 'tiles',
            child: _loadingToolchain && _toolchainRows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final row in _toolchainRows) ...[
                        _buildToolchainCommandTile(row, cs, theme, isZh),
                        kOpenHandGap8,
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMcpServerCard(
    _AndroidMcpServerView row,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    final server = row.server;
    final catalog = row.catalog;
    final health = row.health;
    final healthColor = _mcpHealthColor(health.status, cs);
    final catalogColor = _mcpCatalogColor(catalog.status, cs);
    final tools = row.matchedTools.take(_kMcpToolPreviewLimit).toList();
    final queryNames = tools
        .map((tool) => _mcpResolvedToolName(server, tool))
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final query = queryNames.isEmpty ? null : 'select:${queryNames.join(',')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                server.enabled
                    ? Icons.extension_rounded
                    : Icons.extension_off_rounded,
                size: 18,
                color: server.enabled ? cs.primary : cs.onSurfaceVariant,
              ),
              kOpenHandHGap8,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      server.name,
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFamily: kOpenHandMonospaceFontFamily,
                      ),
                    ),
                    kOpenHandGap3,
                    Text(
                      server.summary.isEmpty
                          ? server.type.transportValue
                          : server.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: kOpenHandMonospaceFontFamily,
                      ),
                    ),
                  ],
                ),
              ),
              kOpenHandHGap8,
              Wrap(
                spacing: _kDashboardTrailingActionGap,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  _DashboardIconActionButton(
                    tooltip: server.enabled
                        ? openHandLocalizedText(
                            context,
                            zh: '禁用 MCP',
                            zhHant: '停用 MCP',
                            en: 'Disable MCP',
                            fr: 'Désactiver MCP',
                            de: 'MCP deaktivieren',
                            ja: 'MCP を無効化',
                          )
                        : openHandLocalizedText(
                            context,
                            zh: '启用 MCP',
                            zhHant: '啟用 MCP',
                            en: 'Enable MCP',
                            fr: 'Activer MCP',
                            de: 'MCP aktivieren',
                            ja: 'MCP を有効化',
                          ),
                    icon: server.enabled
                        ? Icons.toggle_on_rounded
                        : Icons.toggle_off_outlined,
                    onPressed: () => unawaited(
                      _toggleAndroidMcpServer(server, !server.enabled),
                    ),
                  ),
                  _DashboardIconActionButton(
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '检查健康状态',
                      zhHant: '檢查健康狀態',
                      en: 'Check health',
                      fr: 'Vérifier la santé',
                      de: 'Status prüfen',
                      ja: 'ヘルスチェック',
                    ),
                    icon: Icons.health_and_safety_rounded,
                    busy: health.status == McpServerHealthStatus.checking,
                    onPressed: health.status == McpServerHealthStatus.checking
                        ? null
                        : () => unawaited(
                            context.read<McpController>().checkServerHealth(
                              server.name,
                            ),
                          ),
                  ),
                  _DashboardIconActionButton(
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '刷新此 MCP 工具目录',
                      zhHant: '重新整理此 MCP 工具目錄',
                      en: 'Refresh this MCP catalog',
                      fr: 'Actualiser ce catalogue MCP',
                      de: 'Diesen MCP-Katalog aktualisieren',
                      ja: 'この MCP カタログを更新',
                    ),
                    icon: Icons.sync_rounded,
                    busy: catalog.isLoading,
                    onPressed: catalog.isLoading
                        ? null
                        : () => unawaited(
                            context.read<McpController>().refreshServerTools(
                              server.name,
                            ),
                          ),
                  ),
                  if (query != null)
                    _DashboardIconActionButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '复制 ToolSearch 查询',
                        zhHant: '複製 ToolSearch 查詢',
                        en: 'Copy ToolSearch query',
                        fr: 'Copier la requête ToolSearch',
                        de: 'ToolSearch-Abfrage kopieren',
                        ja: 'ToolSearch クエリをコピー',
                      ),
                      icon: Icons.manage_search_rounded,
                      onPressed: () => _copyText(query),
                    ),
                  _DashboardIconActionButton(
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '删除 MCP 服务',
                      zhHant: '刪除 MCP 服務',
                      en: 'Delete MCP service',
                      fr: 'Supprimer le service MCP',
                      de: 'MCP-Dienst löschen',
                      ja: 'MCP サービスを削除',
                    ),
                    icon: Icons.delete_outline_rounded,
                    color: cs.error,
                    onPressed: () => unawaited(_deleteAndroidMcpServer(server)),
                  ),
                ],
              ),
            ],
          ),
          kOpenHandGap8,
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StatusPill(
                label: _enabledStateLabel(server.enabled),
                color: server.enabled ? cs.primary : cs.outline,
              ),
              _StatusPill(
                label:
                    '${openHandLocalizedText(context, zh: "健康", zhHant: "健康", en: "health", fr: "santé", de: "Status", ja: "ヘルス")}: ${_mcpHealthStatusLabel(health.status)}',
                color: healthColor,
              ),
              _StatusPill(
                label:
                    '${openHandLocalizedText(context, zh: "目录", zhHant: "目錄", en: "catalog", fr: "catalogue", de: "Katalog", ja: "カタログ")}: ${_mcpCatalogStatusLabel(catalog.status)}',
                color: catalogColor,
              ),
              _StatusPill(
                label:
                    '${openHandLocalizedText(context, zh: "相关工具", zhHant: "相關工具", en: "related tools", fr: "outils liés", de: "relevante Tools", ja: "関連ツール")}: ${row.matchedTools.length}/${catalog.tools.length}',
                color: row.matchedTools.isEmpty ? cs.outline : cs.primary,
              ),
            ],
          ),
          if (health.errorMessage?.trim().isNotEmpty ?? false) ...[
            kOpenHandGap8,
            Text(
              health.errorMessage!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          if (catalog.errorMessage?.trim().isNotEmpty ?? false) ...[
            kOpenHandGap8,
            Text(
              catalog.errorMessage!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          if (tools.isNotEmpty) ...[
            kOpenHandGap8,
            SelectableText(
              tools
                  .map((tool) => _mcpResolvedToolName(server, tool))
                  .join('\n'),
              style: TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
                color: cs.onSurface,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAndroidMcpCapabilityCard(
    TemplateRuntimeMcpCapabilitySpec capability,
    McpController controller,
    ColorScheme cs,
    ThemeData theme,
  ) {
    final matches = _matchingAndroidMcpServersForCapability(
      controller,
      capability,
    );
    final configuredMatches = _matchingAndroidMcpServersForCapability(
      controller,
      capability,
      visibleOnly: false,
    );
    final installed = matches.isNotEmpty;
    final needsAssociation = !installed && configuredMatches.isNotEmpty;
    final canInstall = _canRegisterAndroidMcpCapability(capability);
    final statusColor = installed
        ? cs.primary
        : needsAssociation
        ? cs.secondary
        : canInstall
        ? cs.tertiary
        : cs.outline;
    final statusLabel = installed
        ? openHandLocalizedText(
            context,
            zh: '已配置 ${matches.length}',
            zhHant: '已設定 ${matches.length}',
            en: '${matches.length} configured',
            fr: '${matches.length} configuré(s)',
            de: '${matches.length} konfiguriert',
            ja: '${matches.length} 件設定済み',
          )
        : needsAssociation
        ? openHandLocalizedText(
            context,
            zh: '待关联',
            zhHant: '待關聯',
            en: 'link required',
            fr: 'association requise',
            de: 'Verknüpfung erforderlich',
            ja: '関連付けが必要',
          )
        : canInstall
        ? openHandLocalizedText(
            context,
            zh: '可安装',
            zhHant: '可安裝',
            en: 'installable',
            fr: 'installable',
            de: 'installierbar',
            ja: 'インストール可能',
          )
        : openHandLocalizedText(
            context,
            zh: '缺少安装源',
            zhHant: '缺少安裝來源',
            en: 'source missing',
            fr: 'source manquante',
            de: 'Quelle fehlt',
            ja: 'インストール元なし',
          );
    final firstServer = installed
        ? matches.first
        : configuredMatches.firstOrNull;
    final capabilityLabel = openHandLocalizedText(
      context,
      zh: capability.labelZh,
      zhHant: capability.labelZhHant,
      en: capability.labelEn,
      fr: capability.labelFr,
      de: capability.labelDe,
      ja: capability.labelJa,
    );
    final capabilityDescription = openHandLocalizedText(
      context,
      zh: capability.descriptionZh,
      zhHant: capability.descriptionZhHant,
      en: capability.descriptionEn,
      fr: capability.descriptionFr,
      de: capability.descriptionDe,
      ja: capability.descriptionJa,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.62)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            installed
                ? Icons.extension_rounded
                : Icons.add_circle_outline_rounded,
            size: 19,
            color: statusColor,
          ),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      capabilityLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    _StatusPill(label: statusLabel, color: statusColor),
                    if (capability.packageName?.trim().isNotEmpty ?? false)
                      _StatusPill(
                        label: capability.packageName!.trim(),
                        color: cs.secondary,
                      ),
                  ],
                ),
                kOpenHandGap4,
                Text(
                  [
                    capabilityDescription,
                    if (firstServer != null)
                      '${openHandLocalizedText(context, zh: "服务", zhHant: "服務", en: "server", fr: "serveur", de: "Server", ja: "server")}: ${firstServer.name}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          kOpenHandHGap10,
          Wrap(
            spacing: _kDashboardTrailingActionGap,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              _DashboardActionButton(
                onPressed:
                    installed ||
                        (!needsAssociation && !canInstall) ||
                        controller.isLoading
                    ? null
                    : () => unawaited(_installAndroidMcpCapability(capability)),
                icon: needsAssociation
                    ? Icons.link_rounded
                    : Icons.download_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: needsAssociation ? '关联' : '安装',
                  zhHant: needsAssociation ? '關聯' : '安裝',
                  en: needsAssociation ? 'Link' : 'Install',
                  fr: needsAssociation ? 'Associer' : 'Installer',
                  de: needsAssociation ? 'Verknüpfen' : 'Installieren',
                  ja: needsAssociation ? '関連付け' : 'インストール',
                ),
              ),
              _DashboardActionButton(
                onPressed: !installed || controller.isLoading
                    ? null
                    : () => unawaited(_refreshAndroidMcpCapability(matches)),
                icon: Icons.system_update_alt_rounded,
                label: openHandUpdateLabel(context),
              ),
              _DashboardActionButton(
                onPressed: !installed || controller.isLoading
                    ? null
                    : () => unawaited(
                        _uninstallAndroidMcpCapability(capability, matches),
                      ),
                icon: Icons.delete_outline_rounded,
                label: _androidReverseUninstallLabel(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _canRegisterAndroidMcpCapability(
    TemplateRuntimeMcpCapabilitySpec capability,
  ) {
    final name = capability.suggestedServerName?.trim();
    final command = capability.suggestedCommand?.trim();
    final url = capability.suggestedUrl?.trim();
    if (name == null || name.isEmpty) return false;
    if ((command == null || command.isEmpty) && (url == null || url.isEmpty)) {
      return false;
    }
    return !_hasMcpCapabilityPlaceholder(capability);
  }

  bool _hasMcpCapabilityPlaceholder(
    TemplateRuntimeMcpCapabilitySpec capability,
  ) {
    bool hasPlaceholder(String? value) =>
        value != null && (value.contains('<') || value.contains('>'));
    return hasPlaceholder(capability.suggestedCommand) ||
        hasPlaceholder(capability.suggestedUrl) ||
        capability.suggestedArgs.any(hasPlaceholder);
  }

  Future<void> _installAndroidMcpCapability(
    TemplateRuntimeMcpCapabilitySpec capability,
  ) async {
    final controller = context.read<McpController>();
    final existing = _matchingAndroidMcpServersForCapability(
      controller,
      capability,
      visibleOnly: false,
    ).firstOrNull;
    final linksExisting = existing != null;
    if (!linksExisting && !_canRegisterAndroidMcpCapability(capability)) {
      _showSnack(
        openHandLocalizedText(
          context,
          zh: '该 MCP 缺少可直接安装的来源。',
          zhHant: '此 MCP 缺少可直接安裝的來源。',
          en: 'This MCP has no direct install source.',
          fr: 'Ce MCP n’a pas de source d’installation directe.',
          de: 'Dieses MCP hat keine direkt installierbare Quelle.',
          ja: 'この MCP には直接インストールできるソースがありません。',
        ),
      );
      return;
    }
    final server =
        existing?.withVisibleTemplate(
          AiPromptTemplatePolicies.androidReverseExpertTemplateId,
        ) ??
        McpServer(
          name: capability.suggestedServerName!.trim(),
          type: (capability.suggestedUrl?.trim().isNotEmpty ?? false)
              ? McpServerType.sse
              : McpServerType.stdio,
          enabled: true,
          url: capability.suggestedUrl?.trim() ?? '',
          command: capability.suggestedCommand?.trim() ?? '',
          args: capability.suggestedArgs,
          visibleTemplateIds: const <String>{
            AiPromptTemplatePolicies.androidReverseExpertTemplateId,
          },
        );
    final ok =
        identical(server, existing) ||
        await controller.saveServer(server, previousName: existing?.name);
    if (!mounted) return;
    _showSnack(
      ok
          ? openHandLocalizedText(
              context,
              zh: linksExisting
                  ? '已关联 Android 逆向专家：${server.name}'
                  : '已安装 MCP：${server.name}',
              zhHant: linksExisting
                  ? '已關聯 Android 逆向專家：${server.name}'
                  : '已安裝 MCP：${server.name}',
              en: linksExisting
                  ? 'Linked to Android Reverse Expert: ${server.name}'
                  : 'MCP installed: ${server.name}',
              fr: linksExisting
                  ? 'Associé à Expert reverse Android : ${server.name}'
                  : 'MCP installé : ${server.name}',
              de: linksExisting
                  ? 'Mit Android-Reverse-Experte verknüpft: ${server.name}'
                  : 'MCP installiert: ${server.name}',
              ja: linksExisting
                  ? 'Android リバースエキスパートに関連付けました: ${server.name}'
                  : 'MCP をインストールしました: ${server.name}',
            )
          : openHandLocalizedText(
              context,
              zh: 'MCP 已存在或名称冲突：${server.name}',
              zhHant: 'MCP 已存在或名稱衝突：${server.name}',
              en: 'MCP exists or name conflicts: ${server.name}',
              fr: 'MCP existe déjà ou nom en conflit : ${server.name}',
              de: 'MCP existiert bereits oder Namenskonflikt: ${server.name}',
              ja: 'MCP は既に存在するか名前が競合しています: ${server.name}',
            ),
    );
    if (ok && !linksExisting) {
      unawaited(context.read<McpController>().reconnectServer(server.name));
    }
  }

  Future<void> _refreshAndroidMcpCapability(List<McpServer> servers) async {
    if (servers.isEmpty) return;
    final controller = context.read<McpController>();
    await forEachIndexWithConcurrencyLimit(
      itemCount: servers.length,
      maxConcurrency: _kMcpReconnectConcurrency,
      task: (index) => controller.reconnectServer(servers[index].name),
    );
    if (!mounted) return;
    _showSnack(
      openHandLocalizedText(
        context,
        zh: '已更新 MCP 状态。',
        zhHant: '已更新 MCP 狀態。',
        en: 'MCP status updated.',
        fr: 'État MCP mis à jour.',
        de: 'MCP-Status aktualisiert.',
        ja: 'MCP 状態を更新しました。',
      ),
    );
  }

  Future<void> _uninstallAndroidMcpCapability(
    TemplateRuntimeMcpCapabilitySpec capability,
    List<McpServer> servers,
  ) async {
    if (servers.isEmpty) return;
    final names = servers.map((server) => server.name).join(', ');
    final capabilityLabel = openHandLocalizedText(
      context,
      zh: capability.labelZh,
      zhHant: capability.labelZhHant,
      en: capability.labelEn,
      fr: capability.labelFr,
      de: capability.labelDe,
      ja: capability.labelJa,
    );
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '卸载 MCP 能力？',
        zhHant: '解除安裝 MCP 能力？',
        en: 'Uninstall MCP capability?',
        fr: 'Désinstaller la capacité MCP ?',
        de: 'MCP-Fähigkeit deinstallieren?',
        ja: 'MCP 機能をアンインストールしますか？',
      ),
      message: openHandLocalizedText(
        context,
        zh: '将从 OpenHand MCP 配置中删除 $capabilityLabel 对应服务：$names。',
        zhHant: '將從 OpenHand MCP 設定中刪除 $capabilityLabel 對應服務：$names。',
        en: 'This removes the servers for $capabilityLabel from the OpenHand MCP configuration: $names.',
        fr: 'Supprime les serveurs de $capabilityLabel de la configuration MCP OpenHand : $names.',
        de: 'Entfernt die Server für $capabilityLabel aus der OpenHand-MCP-Konfiguration: $names.',
        ja: '$capabilityLabel の server を OpenHand MCP 設定から削除します: $names。',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: _androidReverseUninstallLabel(context),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final controller = context.read<McpController>();
    var ok = true;
    for (final server in servers) {
      ok = await controller.deleteServer(server) && ok;
    }
    if (!mounted) return;
    _showSnack(
      ok
          ? openHandLocalizedText(
              context,
              zh: '已卸载 MCP：$names',
              zhHant: '已解除安裝 MCP：$names',
              en: 'MCP uninstalled: $names',
              fr: 'MCP désinstallé : $names',
              de: 'MCP deinstalliert: $names',
              ja: 'MCP をアンインストールしました: $names',
            )
          : openHandLocalizedText(
              context,
              zh: '卸载 MCP 失败：$names',
              zhHant: '解除安裝 MCP 失敗：$names',
              en: 'Failed to uninstall MCP: $names',
              fr: 'Échec de la désinstallation MCP : $names',
              de: 'MCP-Deinstallation fehlgeschlagen: $names',
              ja: 'MCP のアンインストールに失敗しました: $names',
            ),
    );
  }

  Future<void> _toggleAndroidMcpServer(McpServer server, bool enabled) async {
    final ok = await context.read<McpController>().updateServerEnabled(
      server.name,
      enabled,
    );
    if (!mounted) return;
    _showSnack(
      ok
          ? enabled
                ? openHandLocalizedText(
                    context,
                    zh: '已启用 MCP：${server.name}',
                    zhHant: '已啟用 MCP：${server.name}',
                    en: 'MCP enabled: ${server.name}',
                    fr: 'MCP activé : ${server.name}',
                    de: 'MCP aktiviert: ${server.name}',
                    ja: 'MCP を有効化しました: ${server.name}',
                  )
                : openHandLocalizedText(
                    context,
                    zh: '已禁用 MCP：${server.name}',
                    zhHant: '已停用 MCP：${server.name}',
                    en: 'MCP disabled: ${server.name}',
                    fr: 'MCP désactivé : ${server.name}',
                    de: 'MCP deaktiviert: ${server.name}',
                    ja: 'MCP を無効化しました: ${server.name}',
                  )
          : openHandLocalizedText(
              context,
              zh: 'MCP 状态更新失败',
              zhHant: 'MCP 狀態更新失敗',
              en: 'Failed to update MCP status',
              fr: 'Échec de mise à jour de l’état MCP',
              de: 'MCP-Status konnte nicht aktualisiert werden',
              ja: 'MCP 状態の更新に失敗しました',
            ),
    );
  }

  Future<void> _deleteAndroidMcpServer(McpServer server) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '删除 MCP 服务？',
        zhHant: '刪除 MCP 服務？',
        en: 'Delete MCP service?',
        fr: 'Supprimer le service MCP ?',
        de: 'MCP-Dienst löschen?',
        ja: 'MCP サービスを削除しますか？',
      ),
      message: openHandLocalizedText(
        context,
        zh: '将从 OpenHand MCP 配置中删除 ${server.name}。',
        zhHant: '將從 OpenHand MCP 設定中刪除 ${server.name}。',
        en: 'This will remove ${server.name} from the OpenHand MCP configuration.',
        fr: 'Supprime ${server.name} de la configuration MCP OpenHand.',
        de: 'Entfernt ${server.name} aus der OpenHand-MCP-Konfiguration.',
        ja: '${server.name} を OpenHand MCP 設定から削除します。',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandDeleteLabel(context),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await context.read<McpController>().deleteServer(server);
    if (!mounted) return;
    _showSnack(
      ok
          ? openHandLocalizedText(
              context,
              zh: '已删除 MCP：${server.name}',
              zhHant: '已刪除 MCP：${server.name}',
              en: 'MCP deleted: ${server.name}',
              fr: 'MCP supprimé : ${server.name}',
              de: 'MCP gelöscht: ${server.name}',
              ja: 'MCP を削除しました: ${server.name}',
            )
          : openHandLocalizedText(
              context,
              zh: '删除 MCP 失败',
              zhHant: '刪除 MCP 失敗',
              en: 'Failed to delete MCP',
              fr: 'Échec de suppression MCP',
              de: 'MCP konnte nicht gelöscht werden',
              ja: 'MCP の削除に失敗しました',
            ),
    );
  }

  Widget _buildRuntimePluginTile(
    PluginInfo plugin,
    PluginServiceController pluginController,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    final color = plugin.isInstalled
        ? plugin.enabled
              ? cs.primary
              : cs.outline
        : cs.tertiary;
    final version = plugin.installedVersion?.trim();
    final path = plugin.installPath?.trim();
    final actions = _runtimePluginActions(plugin);
    final actionBusy = plugin.isBusy || pluginController.isBusy;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.58)),
      ),
      child: Row(
        children: [
          Icon(
            plugin.isInstalled
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 17,
            color: color,
          ),
          kOpenHandHGap8,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plugin.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                kOpenHandGap2,
                Text(
                  [
                    plugin.id,
                    if (version != null && version.isNotEmpty) version,
                    if (plugin.hasUpdate)
                      openHandLocalizedText(
                        context,
                        zh: '有可用更新',
                        zhHant: '有可用更新',
                        en: 'update available',
                        fr: 'mise à jour disponible',
                        de: 'Update verfügbar',
                        ja: '更新あり',
                      ),
                    if (path != null && path.isNotEmpty) path,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFamily: path == null
                        ? null
                        : kOpenHandMonospaceFontFamily,
                  ),
                ),
              ],
            ),
          ),
          kOpenHandHGap8,
          _StatusPill(
            label: plugin.isInstalled
                ? plugin.enabled
                      ? openHandLocalizedText(
                          context,
                          zh: '可用',
                          zhHant: '可用',
                          en: 'ready',
                          fr: 'prêt',
                          de: 'bereit',
                          ja: '利用可能',
                        )
                      : _enabledStateLabel(false)
                : openHandLocalizedText(
                    context,
                    zh: '未安装',
                    zhHant: '未安裝',
                    en: 'missing',
                    fr: 'manquant',
                    de: 'fehlt',
                    ja: '未インストール',
                  ),
            color: color,
          ),
          if (path != null && path.isNotEmpty) ...[
            const SizedBox(width: _kDashboardTrailingActionGap),
            _DashboardIconActionButton(
              tooltip: openHandLocalizedText(
                context,
                zh: '复制路径',
                zhHant: '複製路徑',
                en: 'Copy path',
                fr: 'Copier le chemin',
                de: 'Pfad kopieren',
                ja: 'パスをコピー',
              ),
              icon: Icons.copy_rounded,
              onPressed: () => _copyText(path),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(width: _kDashboardTrailingActionGap),
            _DashboardPopupIconActionButton<_RuntimePluginAction>(
              tooltip: openHandLocalizedText(
                context,
                zh: '插件操作',
                zhHant: '外掛操作',
                en: 'Plugin actions',
                fr: 'Actions plugin',
                de: 'Plugin-Aktionen',
                ja: 'プラグイン操作',
              ),
              icon: const Icon(Icons.more_horiz_rounded, size: 17),
              itemBuilder: (context) => actions
                  .map(
                    (action) => PopupMenuItem<_RuntimePluginAction>(
                      value: action,
                      enabled:
                          action == _RuntimePluginAction.info || !actionBusy,
                      child: Row(
                        children: [
                          Icon(_runtimePluginActionIcon(action), size: 16),
                          kOpenHandHGap8,
                          Text(_runtimePluginActionLabel(action)),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
              onSelected: (action) =>
                  unawaited(_handleRuntimePluginAction(plugin, action)),
            ),
          ],
        ],
      ),
    );
  }

  List<_RuntimePluginAction> _runtimePluginActions(PluginInfo plugin) {
    if (plugin.isBusy) {
      return const <_RuntimePluginAction>[_RuntimePluginAction.info];
    }
    if (plugin.isInstalled) {
      return <_RuntimePluginAction>[
        _RuntimePluginAction.info,
        _RuntimePluginAction.checkUpdate,
        if (plugin.hasUpdate || _kAndroidRuntimePluginIds.contains(plugin.id))
          _RuntimePluginAction.update,
        plugin.enabled
            ? _RuntimePluginAction.disable
            : _RuntimePluginAction.enable,
        if (plugin.supportsUninstall) _RuntimePluginAction.uninstall,
      ];
    }
    return const <_RuntimePluginAction>[
      _RuntimePluginAction.info,
      _RuntimePluginAction.install,
    ];
  }

  IconData _runtimePluginActionIcon(_RuntimePluginAction action) {
    return switch (action) {
      _RuntimePluginAction.info => Icons.info_outline_rounded,
      _RuntimePluginAction.install => Icons.download_rounded,
      _RuntimePluginAction.checkUpdate => Icons.refresh_rounded,
      _RuntimePluginAction.update => Icons.system_update_alt_rounded,
      _RuntimePluginAction.enable => Icons.toggle_on_rounded,
      _RuntimePluginAction.disable => Icons.toggle_off_outlined,
      _RuntimePluginAction.uninstall => Icons.delete_outline_rounded,
    };
  }

  String _runtimePluginActionLabel(_RuntimePluginAction action) {
    return switch (action) {
      _RuntimePluginAction.info => openHandLocalizedText(
        context,
        zh: '查看信息',
        zhHant: '查看資訊',
        en: 'View info',
        fr: 'Voir les infos',
        de: 'Info anzeigen',
        ja: '情報を見る',
      ),
      _RuntimePluginAction.install => openHandInstallLabel(context),
      _RuntimePluginAction.checkUpdate => openHandLocalizedText(
        context,
        zh: '检查更新',
        zhHant: '檢查更新',
        en: 'Check updates',
        fr: 'Vérifier les mises à jour',
        de: 'Updates prüfen',
        ja: '更新を確認',
      ),
      _RuntimePluginAction.update => openHandUpdateLabel(context),
      _RuntimePluginAction.enable => openHandLocalizedText(
        context,
        zh: '启用',
        zhHant: '啟用',
        en: 'Enable',
        fr: 'Activer',
        de: 'Aktivieren',
        ja: '有効化',
      ),
      _RuntimePluginAction.disable => openHandLocalizedText(
        context,
        zh: '禁用',
        zhHant: '停用',
        en: 'Disable',
        fr: 'Désactiver',
        de: 'Deaktivieren',
        ja: '無効化',
      ),
      _RuntimePluginAction.uninstall => _androidReverseUninstallLabel(context),
    };
  }

  void _showRuntimePluginInfoDialog(PluginInfo plugin) {
    androidReverseToolDialogs.show<void>(
      context: context,
      builder: (_) => _RuntimePluginInfoDialog(plugin: plugin),
    );
  }

  Future<void> _handleRuntimePluginAction(
    PluginInfo plugin,
    _RuntimePluginAction action,
  ) async {
    final pluginController = context.read<PluginServiceController>();
    switch (action) {
      case _RuntimePluginAction.info:
        _showRuntimePluginInfoDialog(plugin);
        return;
      case _RuntimePluginAction.enable:
      case _RuntimePluginAction.disable:
        pluginController.toggleEnabled(
          plugin.id,
          enabled: action == _RuntimePluginAction.enable,
        );
        _showSnack(
          action == _RuntimePluginAction.enable
              ? openHandLocalizedText(
                  context,
                  zh: '已启用 ${plugin.name}',
                  zhHant: '已啟用 ${plugin.name}',
                  en: '${plugin.name} enabled',
                  fr: '${plugin.name} activé',
                  de: '${plugin.name} aktiviert',
                  ja: '${plugin.name} を有効化しました',
                )
              : openHandLocalizedText(
                  context,
                  zh: '已禁用 ${plugin.name}',
                  zhHant: '已停用 ${plugin.name}',
                  en: '${plugin.name} disabled',
                  fr: '${plugin.name} désactivé',
                  de: '${plugin.name} deaktiviert',
                  ja: '${plugin.name} を無効化しました',
                ),
        );
        return;
      case _RuntimePluginAction.checkUpdate:
        final refreshed = await pluginController.checkPluginUpdate(plugin.id);
        if (!mounted) return;
        final latest = pluginController.pluginById(plugin.id) ?? refreshed;
        _showSnack(
          latest == null
              ? (pluginController.errorMessage ??
                    openHandLocalizedText(
                      context,
                      zh: '检查更新失败',
                      zhHant: '檢查更新失敗',
                      en: 'Failed to check updates',
                      fr: 'Échec de vérification des mises à jour',
                      de: 'Updates konnten nicht geprüft werden',
                      ja: '更新確認に失敗しました',
                    ))
              : latest.hasUpdate && latest.latestVersion != null
              ? openHandLocalizedText(
                  context,
                  zh: '发现新版本：${latest.latestVersion}',
                  zhHant: '發現新版本：${latest.latestVersion}',
                  en: 'New version available: ${latest.latestVersion}',
                  fr: 'Nouvelle version disponible : ${latest.latestVersion}',
                  de: 'Neue Version verfügbar: ${latest.latestVersion}',
                  ja: '新しいバージョンがあります: ${latest.latestVersion}',
                )
              : openHandLocalizedText(
                  context,
                  zh: '未发现新版本',
                  zhHant: '未發現新版本',
                  en: 'No updates available',
                  fr: 'Aucune mise à jour disponible',
                  de: 'Keine Updates verfügbar',
                  ja: '利用可能な更新はありません',
                ),
        );
        return;
      case _RuntimePluginAction.install:
      case _RuntimePluginAction.update:
      case _RuntimePluginAction.uninstall:
        await _runRuntimePluginMutation(plugin, action);
    }
  }

  Future<void> _runRuntimePluginMutation(
    PluginInfo plugin,
    _RuntimePluginAction action,
  ) async {
    final title = switch (action) {
      _RuntimePluginAction.install => openHandLocalizedText(
        context,
        zh: '安装 ${plugin.name}？',
        zhHant: '安裝 ${plugin.name}？',
        en: 'Install ${plugin.name}?',
        fr: 'Installer ${plugin.name} ?',
        de: '${plugin.name} installieren?',
        ja: '${plugin.name} をインストールしますか？',
      ),
      _RuntimePluginAction.update => openHandLocalizedText(
        context,
        zh: '更新 ${plugin.name}？',
        zhHant: '更新 ${plugin.name}？',
        en: 'Update ${plugin.name}?',
        fr: 'Mettre à jour ${plugin.name} ?',
        de: '${plugin.name} aktualisieren?',
        ja: '${plugin.name} を更新しますか？',
      ),
      _RuntimePluginAction.uninstall => openHandLocalizedText(
        context,
        zh: '卸载 ${plugin.name}？',
        zhHant: '解除安裝 ${plugin.name}？',
        en: 'Uninstall ${plugin.name}?',
        fr: 'Désinstaller ${plugin.name} ?',
        de: '${plugin.name} deinstallieren?',
        ja: '${plugin.name} をアンインストールしますか？',
      ),
      _ => '',
    };
    final message = switch (action) {
      _RuntimePluginAction.install => openHandLocalizedText(
        context,
        zh: '将通过 OpenHand 插件服务安装 ${plugin.name}。安装可能需要下载依赖文件。',
        zhHant: '將透過 OpenHand 外掛服務安裝 ${plugin.name}。安裝可能需要下載依賴檔案。',
        en: 'OpenHand plugin service will install ${plugin.name}. Dependencies may be downloaded.',
        fr: 'Le service de plugins OpenHand installera ${plugin.name}. Des dépendances peuvent être téléchargées.',
        de: 'Der OpenHand-Plugin-Dienst installiert ${plugin.name}. Abhängigkeiten können heruntergeladen werden.',
        ja: 'OpenHand プラグインサービスが ${plugin.name} をインストールします。依存ファイルをダウンロードする場合があります。',
      ),
      _RuntimePluginAction.update => openHandLocalizedText(
        context,
        zh: '将通过 OpenHand 插件服务更新 ${plugin.name}。',
        zhHant: '將透過 OpenHand 外掛服務更新 ${plugin.name}。',
        en: 'OpenHand plugin service will update ${plugin.name}.',
        fr: 'Le service de plugins OpenHand mettra à jour ${plugin.name}.',
        de: 'Der OpenHand-Plugin-Dienst aktualisiert ${plugin.name}.',
        ja: 'OpenHand プラグインサービスが ${plugin.name} を更新します。',
      ),
      _RuntimePluginAction.uninstall => openHandLocalizedText(
        context,
        zh: '将从本机卸载 ${plugin.name}。此操作可能影响依赖它的能力。',
        zhHant: '將從本機解除安裝 ${plugin.name}。此操作可能影響依賴它的能力。',
        en: 'This will remove ${plugin.name} from this machine and may affect dependent capabilities.',
        fr: 'Supprime ${plugin.name} de cette machine et peut affecter les capacités qui en dépendent.',
        de: 'Entfernt ${plugin.name} von diesem Rechner und kann abhängige Fähigkeiten beeinflussen.',
        ja: '${plugin.name} をこのマシンから削除します。依存する機能に影響する場合があります。',
      ),
      _ => '',
    };
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: title,
      message: message,
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: _runtimePluginActionLabel(action),
      destructive: action == _RuntimePluginAction.uninstall,
    );
    if (!confirmed || !mounted) return;

    final pluginController = context.read<PluginServiceController>();
    final success = switch (action) {
      _RuntimePluginAction.install => await pluginController.installPlugin(
        plugin.id,
      ),
      _RuntimePluginAction.update => await pluginController.updatePlugin(
        plugin.id,
      ),
      _RuntimePluginAction.uninstall => await pluginController.uninstallPlugin(
        plugin.id,
      ),
      _ => false,
    };
    if (!mounted) return;
    _showSnack(
      success
          ? switch (action) {
              _RuntimePluginAction.install => openHandLocalizedText(
                context,
                zh: '${plugin.name} 安装成功',
                zhHant: '${plugin.name} 安裝成功',
                en: '${plugin.name} installed',
                fr: '${plugin.name} installé',
                de: '${plugin.name} installiert',
                ja: '${plugin.name} をインストールしました',
              ),
              _RuntimePluginAction.update => openHandLocalizedText(
                context,
                zh: '${plugin.name} 更新成功',
                zhHant: '${plugin.name} 更新成功',
                en: '${plugin.name} updated',
                fr: '${plugin.name} mis à jour',
                de: '${plugin.name} aktualisiert',
                ja: '${plugin.name} を更新しました',
              ),
              _RuntimePluginAction.uninstall => openHandLocalizedText(
                context,
                zh: '${plugin.name} 卸载成功',
                zhHant: '${plugin.name} 解除安裝成功',
                en: '${plugin.name} uninstalled',
                fr: '${plugin.name} désinstallé',
                de: '${plugin.name} deinstalliert',
                ja: '${plugin.name} をアンインストールしました',
              ),
              _ => plugin.name,
            }
          : (pluginController.errorMessage ??
                switch (action) {
                  _RuntimePluginAction.install => openHandLocalizedText(
                    context,
                    zh: '${plugin.name} 安装失败',
                    zhHant: '${plugin.name} 安裝失敗',
                    en: '${plugin.name} install failed',
                    fr: 'Échec d’installation de ${plugin.name}',
                    de: 'Installation von ${plugin.name} fehlgeschlagen',
                    ja: '${plugin.name} のインストールに失敗しました',
                  ),
                  _RuntimePluginAction.update => openHandLocalizedText(
                    context,
                    zh: '${plugin.name} 更新失败',
                    zhHant: '${plugin.name} 更新失敗',
                    en: '${plugin.name} update failed',
                    fr: 'Échec de mise à jour de ${plugin.name}',
                    de: 'Aktualisierung von ${plugin.name} fehlgeschlagen',
                    ja: '${plugin.name} の更新に失敗しました',
                  ),
                  _RuntimePluginAction.uninstall => openHandLocalizedText(
                    context,
                    zh: '${plugin.name} 卸载失败',
                    zhHant: '${plugin.name} 解除安裝失敗',
                    en: '${plugin.name} uninstall failed',
                    fr: 'Échec de désinstallation de ${plugin.name}',
                    de: 'Deinstallation von ${plugin.name} fehlgeschlagen',
                    ja: '${plugin.name} のアンインストールに失敗しました',
                  ),
                  _ => plugin.name,
                }),
    );
  }

  void _showSnack(
    String message, {
    OpenHandSnackKind kind = OpenHandSnackKind.info,
    Duration? duration,
  }) {
    if (!mounted || message.trim().isEmpty) return;
    OpenHandSnackBar.flash(context, message, kind: kind, duration: duration);
  }

  Future<String?> _saveTextWithPicker({
    required String suggestedName,
    required String typeLabel,
    required List<String> extensions,
    required String content,
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: typeLabel, extensions: extensions),
      ],
    );
    if (location == null) return null;
    await writeFileAtomically(File(location.path), content);
    return location.path;
  }

  String _fileTimestamp() {
    return DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll(RegExp(r'\.\d+'), '');
  }

  Widget _buildToolchainCommandTile(
    AndroidReverseToolchainProbeResult row,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    final ok = row.ok;
    final color = ok
        ? cs.primary
        : row.probe.required
        ? cs.error
        : cs.tertiary;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.58)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 17,
                color: color,
              ),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  row.probe.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusPill(
                label: ok
                    ? openHandLocalizedText(
                        context,
                        zh: '已安装',
                        zhHant: '已安裝',
                        en: 'installed',
                        fr: 'installé',
                        de: 'installiert',
                        ja: 'インストール済み',
                      )
                    : row.probe.required
                    ? openHandLocalizedText(
                        context,
                        zh: '必需缺失',
                        zhHant: '必要缺失',
                        en: 'required missing',
                        fr: 'requis manquant',
                        de: 'erforderlich fehlt',
                        ja: '必須不足',
                      )
                    : openHandLocalizedText(
                        context,
                        zh: '可选缺失',
                        zhHant: '可選缺失',
                        en: 'optional missing',
                        fr: 'optionnel manquant',
                        de: 'optional fehlt',
                        ja: '任意不足',
                      ),
                color: color,
                compact: true,
                subtle: true,
              ),
            ],
          ),
          kOpenHandGap6,
          SelectableText(
            ok
                ? row.displayValue
                : _androidToolchainInstallHint(context, row.probe),
            maxLines: 2,
            style: TextStyle(
              fontFamily: ok ? kOpenHandMonospaceFontFamily : null,
              fontSize: 12,
              color: ok ? cs.onSurface : color,
              height: 1.35,
            ),
          ),
          kOpenHandGap8,
          _dashboardActionWrap([
            for (final action in _toolchainVisibleActions(row.probe))
              _SmallActionButton(
                icon: _toolchainCommandIcon(action),
                label: _toolchainCommandLabel(action),
                onPressed: _isToolchainCommandRunning(row.probe, action)
                    ? null
                    : () => _handleToolchainAction(row.probe, action),
              ),
          ]),
        ],
      ),
    );
  }

  // ── Packages tab ─────────────────────────────────────────────────────────

  Widget _buildPackagesTab(ColorScheme cs, ThemeData theme, bool isZh) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: _dashboardSectionHeader(
            leading: [
              _StatusPill(
                label: openHandLocalizedText(
                  context,
                  zh: '${_packages.length} 个 APP',
                  zhHant: '${_packages.length} 個 APP',
                  en: '${_packages.length} apps',
                  fr: '${_packages.length} apps',
                  de: '${_packages.length} Apps',
                  ja: '${_packages.length} 件の APP',
                ),
                color: cs.primary,
              ),
            ],
            actions: [
              _DashboardActionButton(
                onPressed: _loadingPackages ? null : _doRefreshPackages,
                icon: Icons.refresh_rounded,
                busy: _loadingPackages,
                label: openHandRefreshLabel(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: OpenHandContentStateSwitcher(
            stateKey: _loadingPackages && _packages.isEmpty
                ? 'loading'
                : 'list',
            animateSize: false,
            child: _loadingPackages && _packages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : OpenHandSafeScrollbar(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _packages.length,
                      itemBuilder: (_, i) {
                        final pkg = _packages[i];
                        final selected = _selectedPackageName == pkg;
                        return GestureDetector(
                          onSecondaryTapDown: (details) =>
                              _showPackageMenu(pkg, details.globalPosition),
                          onDoubleTap: () => _showPackageMenu(pkg, null),
                          child: ListTile(
                            selected: selected,
                            selectedTileColor: cs.primaryContainer.withValues(
                              alpha: 0.22,
                            ),
                            leading: Icon(
                              Icons.apps_rounded,
                              size: 18,
                              color: selected
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                            title: Text(
                              pkg,
                              style: const TextStyle(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 14,
                                  ),
                                  tooltip: _androidReverseCopyPackageNameLabel(
                                    context,
                                  ),
                                  onPressed: () => _copyText(pkg),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: _kIconButtonGap),
                                IconButton(
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 15,
                                  ),
                                  tooltip: _androidReverseLaunchAppLabel(
                                    context,
                                  ),
                                  onPressed: _runningDeviceAction
                                      ? null
                                      : () => _runDeviceAction(
                                          () => _ctrl.startPackageDetailed(
                                            pkg,
                                            serial: _targetSerial,
                                          ),
                                        ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: _kIconButtonGap),
                                IconButton(
                                  icon: const Icon(
                                    Icons.stop_rounded,
                                    size: 14,
                                    color: Colors.redAccent,
                                  ),
                                  tooltip: _androidReverseForceStopLabel(
                                    context,
                                  ),
                                  onPressed: _runningDeviceAction
                                      ? null
                                      : () async {
                                          await _runDeviceAction(
                                            () => _ctrl.forceStopAppDetailed(
                                              pkg,
                                              serial: _targetSerial,
                                            ),
                                          );
                                          if (!mounted) return;
                                          _showSnack(
                                            openHandLocalizedText(
                                              context,
                                              zh: '已发送强制停止：$pkg',
                                              zhHant: '已送出強制停止：$pkg',
                                              en: 'Force-stop sent: $pkg',
                                              fr: 'Arrêt forcé envoyé : $pkg',
                                              de: 'Stopp erzwingen gesendet: $pkg',
                                              ja: '強制停止を送信しました: $pkg',
                                            ),
                                            kind: OpenHandSnackKind.success,
                                          );
                                        },
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: _kIconButtonGap),
                                IconButton(
                                  icon: const Icon(
                                    Icons.more_horiz_rounded,
                                    size: 16,
                                  ),
                                  tooltip: openHandMoreActionsLabel(context),
                                  onPressed: () => _showPackageMenu(pkg, null),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            onTap: () => _analyzePackage(pkg),
                            dense: true,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
        if (_selectedPackageName != null) ...[
          Divider(height: 1, color: cs.outlineVariant),
          SizedBox(
            height: 190,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${openHandLocalizedText(context, zh: "APP 分析", zhHant: "APP 分析", en: "APP analysis", fr: "Analyse APP", de: "APP-Analyse", ja: "APP 解析")}: $_selectedPackageName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      OpenHandBusyStatusIcon(
                        busy: _loadingPackageAnalysis,
                        icon: null,
                        size: 14,
                        strokeWidth: 1.5,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: OpenHandBusyStatusIcon(
                          busy: _capturingPackageReport,
                          icon: null,
                          size: 14,
                          strokeWidth: 1.5,
                        ),
                      ),
                      kOpenHandHGap8,
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        tooltip: openHandLocalizedText(
                          context,
                          zh: '重新分析',
                          zhHant: '重新分析',
                          en: 'Analyze again',
                          fr: 'Analyser à nouveau',
                          de: 'Erneut analysieren',
                          ja: '再解析',
                        ),
                        onPressed: _loadingPackageAnalysis
                            ? null
                            : () => _analyzePackage(_selectedPackageName!),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.snippet_folder_rounded,
                          size: 16,
                        ),
                        tooltip: _androidReverseGenerateAppReportLabel(context),
                        onPressed:
                            _capturingPackageReport || _loadingPackageAnalysis
                            ? null
                            : () =>
                                  _capturePackageReport(_selectedPackageName!),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        tooltip: openHandLocalizedText(
                          context,
                          zh: '复制分析结果',
                          zhHant: '複製分析結果',
                          en: 'Copy analysis',
                          fr: 'Copier l’analyse',
                          de: 'Analyse kopieren',
                          ja: '解析結果をコピー',
                        ),
                        onPressed: (_packageAnalysisOutput ?? '').trim().isEmpty
                            ? null
                            : () => _copyText(_packageAnalysisOutput!),
                      ),
                    ],
                  ),
                  kOpenHandGap6,
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(kOpenHandRadius6),
                      ),
                      child: OpenHandSafeScrollbar(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(8),
                          child: SelectableText(
                            _packageAnalysisOutput ??
                                openHandLocalizedText(
                                  context,
                                  zh: '正在读取 APP 信息...',
                                  zhHant: '正在讀取 APP 資訊...',
                                  en: 'Reading app info...',
                                  fr: 'Lecture des infos APP...',
                                  de: 'APP-Info wird gelesen...',
                                  ja: 'APP 情報を読み込み中...',
                                ),
                            style: TextStyle(
                              fontFamily: kOpenHandMonospaceFontFamily,
                              fontSize: 11,
                              height: 1.45,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Processes tab ───────────────────────────────────────────────────────

  Widget _buildProcessesTab(ColorScheme cs, ThemeData theme, bool isZh) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: TextField(
                    controller: _processFilter,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: openHandLocalizedText(
                        context,
                        zh: '过滤进程名...',
                        zhHant: '篩選程序名稱...',
                        en: 'Filter process name...',
                        fr: 'Filtrer le nom du processus...',
                        de: 'Prozessnamen filtern...',
                        ja: 'プロセス名を絞り込み...',
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search_rounded, size: 16),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _doRefreshProcesses(),
                  ),
                ),
              ),
              kOpenHandHGap8,
              _DashboardActionButton(
                onPressed: _loadingProcesses ? null : _doRefreshProcesses,
                icon: Icons.refresh_rounded,
                busy: _loadingProcesses,
                label: openHandRefreshLabel(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: OpenHandContentStateSwitcher(
            stateKey: _loadingProcesses && _processes.isEmpty
                ? 'loading'
                : 'list',
            animateSize: false,
            child: _loadingProcesses && _processes.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : OpenHandSafeScrollbar(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _processes.length,
                      itemBuilder: (_, i) {
                        final p = _processes[i];
                        return GestureDetector(
                          onSecondaryTapDown: (details) =>
                              _showProcessMenu(p, details.globalPosition),
                          onDoubleTap: () => _showProcessMenu(p, null),
                          child: ListTile(
                            leading: Text(
                              '${p.pid}',
                              style: TextStyle(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            title: Text(
                              p.name,
                              style: const TextStyle(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontSize: 12,
                              ),
                            ),
                            subtitle: p.user != null
                                ? Text(
                                    'user: ${p.user}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 14,
                                  ),
                                  onPressed: () => _copyText('${p.pid}'),
                                  tooltip: _androidReverseCopyPidLabel(context),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: _kIconButtonGap),
                                IconButton(
                                  icon: const Icon(
                                    Icons.more_horiz_rounded,
                                    size: 16,
                                  ),
                                  onPressed: () => _showProcessMenu(p, null),
                                  tooltip: openHandMoreActionsLabel(context),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            dense: true,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ── Logcat tab ──────────────────────────────────────────────────────────

  Widget _buildLogcatPackageFilterChip(
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    final packageName = _logcatPackageTarget()?.trim();
    if (packageName == null || packageName.isEmpty) {
      return const SizedBox.shrink();
    }
    final selected = _logcatPackageFilterEnabled;
    final color = selected ? cs.primary : cs.onSurfaceVariant;
    return Tooltip(
      message: openHandLocalizedText(
        context,
        zh: '按包名过滤 Logcat',
        zhHant: '依套件名稱篩選 Logcat',
        en: 'Filter Logcat by package',
        fr: 'Filtrer Logcat par package',
        de: 'Logcat nach Paket filtern',
        ja: 'パッケージで Logcat を絞り込み',
      ),
      child: FilterChip(
        selected: selected,
        avatar: Icon(Icons.apps_rounded, size: 15, color: color),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            packageName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        onSelected: (value) {
          setState(() {
            _logcatPackageFilterEnabled = value;
            if (value) _logcatPidCtrl.clear();
          });
          unawaited(_fetchLogcat());
        },
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget? _clearFieldSuffix({
    required ColorScheme cs,
    required bool visible,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    if (!visible) return null;
    return Tooltip(
      message: tooltip,
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: IconButton(
            onPressed: onPressed,
            icon: const Icon(Icons.close_rounded, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            splashRadius: 14,
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: cs.onSurfaceVariant,
              hoverColor: cs.primary.withValues(alpha: 0.08),
              focusColor: cs.primary.withValues(alpha: 0.08),
              highlightColor: cs.primary.withValues(alpha: 0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kOpenHandRadius8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogcatTab(ColorScheme cs, ThemeData theme, bool isZh) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dashboardSectionHeader(
                leading: [
                  _StatusPill(
                    label: '${_logcatLines.length}/$_logcatCacheLimit',
                    color: cs.primary,
                  ),
                  if (_logcatPackageTarget()?.isNotEmpty ?? false)
                    _buildLogcatPackageFilterChip(cs, theme, isZh),
                  OpenHandBusyStatusIcon(
                    busy: _loadingLogcat,
                    icon: null,
                    size: 14,
                    strokeWidth: 1.5,
                  ),
                ],
                actions: [
                  _DashboardActionButton(
                    onPressed: _loadingLogcat ? null : _fetchLogcat,
                    icon: Icons.refresh_rounded,
                    label: openHandRefreshLabel(context),
                  ),
                  _DashboardActionButton(
                    onPressed: () => _setLogcatAutoRefresh(!_logcatAutoRefresh),
                    icon: _logcatAutoRefresh
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                    label: _logcatAutoRefresh
                        ? openHandLocalizedText(
                            context,
                            zh: '停止自动',
                            zhHant: '停止自動',
                            en: 'Stop auto',
                            fr: 'Arrêter auto',
                            de: 'Auto stoppen',
                            ja: '自動停止',
                          )
                        : openHandLocalizedText(
                            context,
                            zh: '自动刷新',
                            zhHant: '自動重新整理',
                            en: 'Auto refresh',
                            fr: 'Actualisation auto',
                            de: 'Auto-Aktualisierung',
                            ja: '自動更新',
                          ),
                    filled: _logcatAutoRefresh,
                  ),
                  _DashboardActionButton(
                    onPressed: _capturingLogcatSnapshot || _clearingLogcat
                        ? null
                        : _captureLogcatArtifactSnapshot,
                    icon: Icons.snippet_folder_rounded,
                    busy: _capturingLogcatSnapshot,
                    label: openHandLocalizedText(
                      context,
                      zh: '快照',
                      zhHant: '快照',
                      en: 'Snapshot',
                      fr: 'Snapshot',
                      de: 'Snapshot',
                      ja: 'スナップショット',
                    ),
                  ),
                  _DashboardActionButton(
                    onPressed: _logcatLines.isEmpty || _savingLogcatFile
                        ? null
                        : _saveLogcatSnapshot,
                    icon: Icons.save_alt_rounded,
                    busy: _savingLogcatFile,
                    label: openHandSaveLabel(context),
                  ),
                  _DashboardActionButton(
                    onPressed: _logcatLines.isEmpty
                        ? null
                        : () => _copyText(_logcatLines.join('\n')),
                    icon: Icons.copy_rounded,
                    label: openHandCopyLabel(context),
                  ),
                  _DashboardActionButton(
                    onPressed: _clearingLogcat || _capturingLogcatSnapshot
                        ? null
                        : _clearLogcat,
                    icon: Icons.delete_sweep_rounded,
                    busy: _clearingLogcat,
                    label: openHandClearLabel(context),
                  ),
                ],
              ),
              kOpenHandGap8,
              _dashboardActionWrap([
                SizedBox(
                  width: 220,
                  height: _kDashboardFilterControlHeight,
                  child: TextField(
                    controller: _logcatFilterCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: openHandLocalizedText(
                        context,
                        zh: 'Tag 过滤',
                        zhHant: 'Tag 篩選',
                        en: 'Tag filter',
                        fr: 'Filtre Tag',
                        de: 'Tag-Filter',
                        ja: 'Tag フィルター',
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      suffixIcon: _clearFieldSuffix(
                        cs: cs,
                        visible: _logcatFilterCtrl.text.trim().isNotEmpty,
                        tooltip: openHandLocalizedText(
                          context,
                          zh: '清空过滤',
                          zhHant: '清空篩選',
                          en: 'Clear filter',
                          fr: 'Effacer le filtre',
                          de: 'Filter leeren',
                          ja: 'フィルターをクリア',
                        ),
                        onPressed: () {
                          setState(() => _logcatFilterCtrl.clear());
                          _fetchLogcat();
                        },
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _fetchLogcat(),
                  ),
                ),
                SizedBox(
                  width: isZh ? 118 : 126,
                  height: _kDashboardFilterControlHeight,
                  child: AnimatedDropdownButtonFormField<String>(
                    initialValue: _logcatLevel,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: openHandLocalizedText(
                        context,
                        zh: '等级',
                        zhHant: '等級',
                        en: 'Level',
                        fr: 'Niveau',
                        de: 'Stufe',
                        ja: 'レベル',
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    items: [
                      for (final level in _kLogcatLevels)
                        DropdownMenuItem<String>(
                          value: level,
                          child: Text(_logcatLevelOptionLabel(level, context)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _logcatLevel = value);
                      unawaited(_fetchLogcat());
                    },
                  ),
                ),
                SizedBox(
                  width: isZh ? 112 : 126,
                  height: _kDashboardFilterControlHeight,
                  child: AnimatedDropdownButtonFormField<int>(
                    initialValue: _logcatCacheLimit,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: openHandCacheLabel(context),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    items: const <int>[100, 200, 500, 1000, 2000]
                        .map(
                          (value) => DropdownMenuItem<int>(
                            value: value,
                            child: Text('$value'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _logcatCacheLimit = value
                            .clamp(_kMinLogcatCacheLimit, _kMaxLogcatCacheLimit)
                            .toInt();
                        final retained = _trimLogcatBuffer(
                          List<String>.from(_logcatLines),
                        );
                        _logcatLines
                          ..clear()
                          ..addAll(retained);
                        _compactLogcatParseCache();
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 132,
                  height: _kDashboardFilterControlHeight,
                  child: TextField(
                    controller: _logcatPidCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'PID',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      suffixIcon: _clearFieldSuffix(
                        cs: cs,
                        visible: _logcatPidCtrl.text.trim().isNotEmpty,
                        tooltip: openHandLocalizedText(
                          context,
                          zh: '清空 PID',
                          zhHant: '清空 PID',
                          en: 'Clear PID',
                          fr: 'Effacer le PID',
                          de: 'PID leeren',
                          ja: 'PID をクリア',
                        ),
                        onPressed: () {
                          setState(() => _logcatPidCtrl.clear());
                          _fetchLogcat();
                        },
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _fetchLogcat(),
                  ),
                ),
              ]),
              if (_logcatError != null && _logcatLines.isNotEmpty) ...[
                kOpenHandGap8,
                _InfoCard(
                  cs: cs,
                  theme: theme,
                  icon: Icons.info_outline_rounded,
                  text: _logcatError!,
                ),
              ],
              if (_logcatArtifactOutput?.trim().isNotEmpty ?? false) ...[
                kOpenHandGap8,
                _monospaceCard(cs, _logcatArtifactOutput!.trim()),
              ],
            ],
          ),
        ),
        Expanded(
          child: _logcatLines.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        size: 32,
                        color: cs.onSurfaceVariant,
                      ),
                      kOpenHandGap8,
                      Text(
                        _logcatError ??
                            openHandLocalizedText(
                              context,
                              zh: '尚未加载 Logcat',
                              zhHant: '尚未載入 Logcat',
                              en: 'Logcat has not been loaded yet',
                              fr: 'Logcat n’est pas encore chargé',
                              de: 'Logcat wurde noch nicht geladen',
                              ja: 'Logcat はまだ読み込まれていません',
                            ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      kOpenHandGap10,
                      _DashboardActionButton(
                        onPressed: _loadingLogcat ? null : _fetchLogcat,
                        icon: Icons.download_rounded,
                        label: openHandLocalizedText(
                          context,
                          zh: '加载 Logcat',
                          zhHant: '載入 Logcat',
                          en: 'Load logcat',
                          fr: 'Charger Logcat',
                          de: 'Logcat laden',
                          ja: 'Logcat を読み込む',
                        ),
                      ),
                    ],
                  ),
                )
              : OpenHandSafeScrollbar(
                  child: ListView.builder(
                    scrollCacheExtent: const ScrollCacheExtent.pixels(520),
                    controller: _logcatScrollController,
                    addAutomaticKeepAlives: false,
                    addSemanticIndexes: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    itemCount: _logcatLines.length,
                    itemBuilder: (_, i) {
                      final line = _logcatLines[i];
                      return _LogcatLineTile(
                        parsed: _parseCachedLogcatLine(line),
                        colorScheme: cs,
                        theme: theme,
                        isZh: isZh,
                        onMenu: (position) =>
                            _showLogcatLineMenu(i, line, position),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ── Frida tab ───────────────────────────────────────────────────────────

  Widget _buildFridaTab(ColorScheme cs, ThemeData theme, bool isZh) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final snippets = _buildFridaSnippetPane(cs, theme, isZh);
          final editor = _buildFridaEditorPane(cs, theme, isZh);
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 150, child: snippets),
                kOpenHandGap10,
                Expanded(child: editor),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 286, child: snippets),
                    kOpenHandHGap12,
                    Expanded(child: editor),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFridaSnippetPane(ColorScheme cs, ThemeData theme, bool isZh) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: OpenHandSafeScrollbar(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: _kFridaSnippetPresets.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: cs.outlineVariant),
          itemBuilder: (context, index) {
            final preset = _kFridaSnippetPresets[index];
            final selected = _selectedFridaSnippetAsset == preset.assetPath;
            return ListTile(
              selected: selected,
              selectedTileColor: cs.primaryContainer.withValues(alpha: 0.28),
              leading: Icon(
                selected ? Icons.check_circle_rounded : Icons.code_rounded,
                size: 17,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              title: Text(
                preset.label(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                preset.desc(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.download_rounded, size: 15),
                tooltip: openHandLocalizedText(
                  context,
                  zh: '加载',
                  zhHant: '載入',
                  en: 'Load',
                  fr: 'Charger',
                  de: 'Laden',
                  ja: '読み込み',
                ),
                onPressed: () => _loadFridaSnippet(preset),
                visualDensity: VisualDensity.compact,
              ),
              dense: true,
              onTap: () => _loadFridaSnippet(preset),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFridaEditorPane(ColorScheme cs, ThemeData theme, bool isZh) {
    final scriptAsset = _selectedFridaSnippetAsset;
    final selectedAssetLabel = Text(
      scriptAsset ??
          openHandLocalizedText(
            context,
            zh: '未选择内置 snippet',
            zhHant: '未選擇內建 snippet',
            en: 'No built-in snippet selected',
            fr: 'Aucun snippet intégré sélectionné',
            de: 'Kein integriertes Snippet ausgewählt',
            ja: '内蔵 snippet 未選択',
          ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: cs.onSurfaceVariant,
        fontFamily: scriptAsset == null ? null : kOpenHandMonospaceFontFamily,
      ),
    );
    final actions = <Widget>[
      _DashboardActionButton(
        onPressed:
            _fridaScriptCtrl.text.trim().isEmpty ||
                _savingFridaScript ||
                _runningFridaAction
            ? null
            : _saveFridaScriptArtifact,
        icon: Icons.save_alt_rounded,
        busy: _savingFridaScript,
        label: openHandLocalizedText(
          context,
          zh: '保存工件',
          zhHant: '儲存工件',
          en: 'Save artifact',
          fr: 'Enregistrer l’artefact',
          de: 'Artefakt speichern',
          ja: '成果物を保存',
        ),
      ),
      _DashboardActionButton(
        onPressed: _fridaScriptCtrl.text.trim().isEmpty
            ? null
            : () => _copyText(_fridaScriptCtrl.text),
        icon: Icons.copy_rounded,
        label: openHandLocalizedText(
          context,
          zh: '复制脚本',
          zhHant: '複製腳本',
          en: 'Copy script',
          fr: 'Copier le script',
          de: 'Skript kopieren',
          ja: 'スクリプトをコピー',
        ),
      ),
      _DashboardActionButton(
        onPressed: _runningFridaDoctor || _runningFridaAction
            ? null
            : _runFridaDoctor,
        icon: Icons.health_and_safety_rounded,
        busy: _runningFridaDoctor,
        label: openHandLocalizedText(
          context,
          zh: '运行诊断',
          zhHant: '執行診斷',
          en: 'Run doctor',
          fr: 'Lancer le diagnostic',
          de: 'Diagnose ausführen',
          ja: '診断を実行',
        ),
      ),
      _DashboardActionButton(
        onPressed: _runningFridaAction ? null : _readFridaArtifacts,
        icon: Icons.folder_open_rounded,
        busy: _runningFridaAction,
        label: _androidReverseReadArtifactsLabel(context),
      ),
      _DashboardActionButton(
        onPressed: _runningFridaAction ? null : _startExistingFridaServer,
        icon: Icons.play_circle_outline_rounded,
        busy: _runningFridaAction,
        label: openHandLocalizedText(
          context,
          zh: '启动服务',
          zhHant: '啟動服務',
          en: 'Start server',
          fr: 'Démarrer le server',
          de: 'Server starten',
          ja: 'server を起動',
        ),
      ),
      _DashboardActionButton(
        onPressed:
            _runningFridaAction ||
                _savingFridaScript ||
                _fridaScriptCtrl.text.trim().isEmpty
            ? null
            : () => _runFridaCapture(spawn: true),
        icon: Icons.rocket_launch_rounded,
        label: openHandLocalizedText(
          context,
          zh: 'Spawn 注入',
          zhHant: 'Spawn 注入',
          en: 'Spawn',
          fr: 'Spawn',
          de: 'Spawn',
          ja: 'Spawn',
        ),
      ),
      _DashboardActionButton(
        onPressed:
            _runningFridaAction ||
                _savingFridaScript ||
                _fridaScriptCtrl.text.trim().isEmpty
            ? null
            : () => _runFridaCapture(spawn: false),
        icon: Icons.link_rounded,
        label: openHandLocalizedText(
          context,
          zh: 'Attach 注入',
          zhHant: 'Attach 注入',
          en: 'Attach',
          fr: 'Attach',
          de: 'Attach',
          ja: 'Attach',
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: TextField(
            controller: _fridaScriptCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(
              fontFamily: kOpenHandMonospaceFontFamily,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: openHandLocalizedText(
                context,
                zh: '// 选择 snippet 或粘贴脚本...',
                zhHant: '// 選擇 snippet 或貼上腳本...',
                en: '// Load a snippet or paste script...',
                fr: '// Chargez un snippet ou collez un script...',
                de: '// Snippet laden oder Skript einfügen...',
                ja: '// snippet を読み込むかスクリプトを貼り付け...',
              ),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            ),
          ),
        ),
        kOpenHandGap8,
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  selectedAssetLabel,
                  kOpenHandGap8,
                  _dashboardActionWrap(actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: selectedAssetLabel),
                kOpenHandHGap12,
                Expanded(flex: 2, child: _dashboardActionWrap(actions)),
              ],
            );
          },
        ),
        if (_fridaArtifactOutput?.trim().isNotEmpty ?? false) ...[
          kOpenHandGap8,
          SizedBox(
            height: 160,
            child: OpenHandSafeScrollbar(
              child: ListView(
                children: [_monospaceCard(cs, _fridaArtifactOutput!.trim())],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Network tab ─────────────────────────────────────────────────────────

  Widget _buildNetworkTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final addonOutput = _networkAddonOutput?.trim();
    final captureRunning = _ctrl.networkCaptureRunning;
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _dashboardSectionHeader(
            leading: [
              _StatusPill(
                label: captureRunning
                    ? openHandLocalizedText(
                        context,
                        zh: '抓包中 PID ${_ctrl.networkCapturePid}',
                        zhHant: '抓包中 PID ${_ctrl.networkCapturePid}',
                        en: 'capturing PID ${_ctrl.networkCapturePid}',
                        fr: 'capture PID ${_ctrl.networkCapturePid}',
                        de: 'Capture PID ${_ctrl.networkCapturePid}',
                        ja: 'キャプチャ中 PID ${_ctrl.networkCapturePid}',
                      )
                    : openHandLocalizedText(
                        context,
                        zh: '未抓包',
                        zhHant: '未抓包',
                        en: 'idle',
                        fr: 'inactif',
                        de: 'inaktiv',
                        ja: '待機中',
                      ),
                color: captureRunning ? cs.primary : cs.outline,
              ),
            ],
            actions: [
              _DashboardActionButton(
                onPressed: _writingNetworkAddon ? null : _ensureMitmproxyAddon,
                icon: Icons.receipt_long_rounded,
                busy: _writingNetworkAddon,
                label: openHandLocalizedText(
                  context,
                  zh: '生成 JSONL Addon',
                  zhHant: '產生 JSONL Addon',
                  en: 'Generate JSONL addon',
                  fr: 'Générer l’addon JSONL',
                  de: 'JSONL-Addon erstellen',
                  ja: 'JSONL addon を生成',
                ),
              ),
              _DashboardActionButton(
                onPressed: _runningNetworkProbe || _runningNetworkAction
                    ? null
                    : _runNetworkProxyProbe,
                icon: Icons.fact_check_rounded,
                busy: _runningNetworkProbe,
                label: openHandLocalizedText(
                  context,
                  zh: '运行预检',
                  zhHant: '執行預檢',
                  en: 'Run preflight',
                  fr: 'Lancer le préflight',
                  de: 'Preflight ausführen',
                  ja: 'プリフライトを実行',
                ),
              ),
              if (addonOutput != null && addonOutput.isNotEmpty)
                _copyResultButton(addonOutput),
            ],
          ),
          kOpenHandGap12,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _pathTextField(
                  controller: _networkProxyHostCtrl,
                  hintText: openHandLocalizedText(
                    context,
                    zh: '代理主机，例如 10.0.2.2',
                    zhHant: '代理主機，例如 10.0.2.2',
                    en: 'Proxy host, e.g. 10.0.2.2',
                    fr: 'Hôte proxy, ex. 10.0.2.2',
                    de: 'Proxy-Host, z. B. 10.0.2.2',
                    ja: 'プロキシホスト、例 10.0.2.2',
                  ),
                ),
              ),
              kOpenHandHGap8,
              SizedBox(
                width: 120,
                child: _pathTextField(
                  controller: _networkProxyPortCtrl,
                  hintText: openHandLocalizedText(
                    context,
                    zh: '端口',
                    zhHant: '連接埠',
                    en: 'Port',
                    fr: 'Port',
                    de: 'Port',
                    ja: 'ポート',
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap10,
          _dashboardActionWrap([
            _DashboardActionButton(
              onPressed: _runningNetworkAction || captureRunning
                  ? null
                  : _startNetworkCapture,
              icon: Icons.fiber_manual_record_rounded,
              busy: _runningNetworkAction,
              label: openHandLocalizedText(
                context,
                zh: '启动抓包',
                zhHant: '啟動抓包',
                en: 'Start capture',
                fr: 'Démarrer la capture',
                de: 'Capture starten',
                ja: 'キャプチャ開始',
              ),
            ),
            _DashboardActionButton(
              onPressed: _runningNetworkAction || !captureRunning
                  ? null
                  : () => _runNetworkAction(_ctrl.stopNetworkCapture),
              icon: Icons.stop_circle_rounded,
              label: openHandLocalizedText(
                context,
                zh: '停止抓包',
                zhHant: '停止抓包',
                en: 'Stop capture',
                fr: 'Arrêter la capture',
                de: 'Capture stoppen',
                ja: 'キャプチャ停止',
              ),
            ),
            _DashboardActionButton(
              onPressed: _runningNetworkAction ? null : _setDeviceProxy,
              icon: Icons.settings_ethernet_rounded,
              label: openHandLocalizedText(
                context,
                zh: '设置代理',
                zhHant: '設定代理',
                en: 'Set proxy',
                fr: 'Définir proxy',
                de: 'Proxy setzen',
                ja: 'プロキシ設定',
              ),
            ),
            _DashboardActionButton(
              onPressed: _runningNetworkAction ? null : _readDeviceProxy,
              icon: Icons.visibility_rounded,
              label: openHandLocalizedText(
                context,
                zh: '读取代理',
                zhHant: '讀取代理',
                en: 'Read proxy',
                fr: 'Lire le proxy',
                de: 'Proxy lesen',
                ja: 'プロキシ読取',
              ),
            ),
            _DashboardActionButton(
              onPressed: _runningNetworkAction ? null : _clearDeviceProxy,
              icon: Icons.cleaning_services_rounded,
              label: openHandLocalizedText(
                context,
                zh: '清除代理',
                zhHant: '清除代理',
                en: 'Clear proxy',
                fr: 'Effacer proxy',
                de: 'Proxy löschen',
                ja: 'プロキシ解除',
              ),
            ),
            _DashboardActionButton(
              onPressed: _runningNetworkAction
                  ? null
                  : () => _runNetworkAction(_ctrl.readNetworkCaptureSummary),
              icon: Icons.article_rounded,
              label: openHandLocalizedText(
                context,
                zh: '读取抓包',
                zhHant: '讀取抓包',
                en: 'Read capture',
                fr: 'Lire la capture',
                de: 'Capture lesen',
                ja: 'キャプチャ読取',
              ),
            ),
            _DashboardActionButton(
              onPressed: _runningNetworkAction
                  ? null
                  : _exportNetworkFlowsWithPicker,
              icon: Icons.ios_share_rounded,
              label: openHandLocalizedText(
                context,
                zh: '导出 flows',
                zhHant: '匯出 flows',
                en: 'Export flows',
                fr: 'Exporter flows',
                de: 'flows exportieren',
                ja: 'flows をエクスポート',
              ),
            ),
          ]),
          kOpenHandGap10,
          if (addonOutput != null && addonOutput.isNotEmpty)
            _monospaceCard(cs, addonOutput),
        ],
      ),
    );
  }

  // ── Static analysis tab ─────────────────────────────────────────────────

  Widget _buildStaticTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final scanOutput = _staticQuickScanOutput?.trim();
    final staticBusy = _runningStaticQuickScan || _runningStaticAction;
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _dashboardSectionHeader(
            leading: const [],
            actions: [
              _DashboardActionButton(
                onPressed: staticBusy ? null : _runStaticQuickScan,
                icon: Icons.manage_search_rounded,
                busy: _runningStaticQuickScan,
                label: openHandLocalizedText(
                  context,
                  zh: '快速扫描 APK',
                  zhHant: '快速掃描 APK',
                  en: 'Quick scan APK',
                  fr: 'Scan rapide APK',
                  de: 'APK schnell scannen',
                  ja: 'APK クイックスキャン',
                ),
              ),
              _DashboardActionButton(
                onPressed: staticBusy
                    ? null
                    : () => _runStaticAction(
                        (target) => _ctrl.readStaticQuickScanArtifacts(
                          apkPath: target.apkPath,
                          packageName: target.packageName,
                        ),
                      ),
                icon: Icons.folder_open_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '读取产物',
                  zhHant: '讀取產物',
                  en: 'Read artifacts',
                  fr: 'Lire les artefacts',
                  de: 'Artefakte lesen',
                  ja: '成果物を読み込み',
                ),
              ),
              _DashboardActionButton(
                onPressed: staticBusy
                    ? null
                    : () => _runStaticAction(
                        (target) => _ctrl.inspectApkIdentity(
                          apkPath: target.apkPath,
                          packageName: target.packageName,
                        ),
                      ),
                icon: Icons.badge_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '身份验签',
                  zhHant: '身分驗簽',
                  en: 'Identity',
                  fr: 'Identité',
                  de: 'Identität',
                  ja: '識別情報',
                ),
              ),
              _DashboardActionButton(
                onPressed: staticBusy
                    ? null
                    : () => _runStaticAction(
                        (target) => _ctrl.runJadxDecompile(
                          apkPath: target.apkPath,
                          packageName: target.packageName,
                        ),
                      ),
                icon: Icons.code_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: 'jadx 反编译',
                  zhHant: 'jadx 反編譯',
                  en: 'jadx',
                  fr: 'jadx',
                  de: 'jadx',
                  ja: 'jadx',
                ),
              ),
              _DashboardActionButton(
                onPressed: staticBusy
                    ? null
                    : () => _runStaticAction(
                        (target) => _ctrl.runApktoolUnpack(
                          apkPath: target.apkPath,
                          packageName: target.packageName,
                        ),
                      ),
                icon: Icons.inventory_2_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: 'apktool 解包',
                  zhHant: 'apktool 解包',
                  en: 'apktool',
                  fr: 'apktool',
                  de: 'apktool',
                  ja: 'apktool',
                ),
              ),
              _DashboardActionButton(
                onPressed: staticBusy
                    ? null
                    : () => _runStaticAction(
                        (target) => _ctrl.runStaticStringsScan(
                          apkPath: target.apkPath,
                          packageName: target.packageName,
                        ),
                      ),
                icon: Icons.search_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: '字符串扫描',
                  zhHant: '字串掃描',
                  en: 'Strings',
                  fr: 'Chaînes',
                  de: 'Strings',
                  ja: '文字列',
                ),
              ),
              if (scanOutput != null && scanOutput.isNotEmpty) ...[
                _copyResultButton(scanOutput),
              ],
            ],
          ),
          if (scanOutput != null && scanOutput.isNotEmpty) ...[
            kOpenHandGap10,
            _monospaceCard(cs, scanOutput),
          ],
        ],
      ),
    );
  }

  // ── Certs tab ────────────────────────────────────────────────────────────

  Widget _buildCertsTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final artifactOutput = _certificateArtifactOutput?.trim();
    final certificateBusy =
        _writingCertificateArtifacts || _runningCertificateAction;
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _dashboardSectionHeader(
            leading: const [],
            actions: [
              _DashboardActionButton(
                onPressed: certificateBusy ? null : _ensureCertificateArtifacts,
                icon: Icons.description_rounded,
                busy: _writingCertificateArtifacts,
                label: openHandLocalizedText(
                  context,
                  zh: '生成证书工件',
                  zhHant: '產生憑證工件',
                  en: 'Generate cert artifacts',
                  fr: 'Générer les artefacts cert',
                  de: 'Zertifikatsartefakte erstellen',
                  ja: '証明書成果物を生成',
                ),
              ),
              _DashboardActionButton(
                onPressed: certificateBusy ? null : _readCertificateArtifacts,
                icon: Icons.folder_open_rounded,
                busy: _runningCertificateAction,
                label: _androidReverseReadArtifactsLabel(context),
              ),
              _DashboardActionButton(
                onPressed: certificateBusy ? null : _generateDebugKeystore,
                icon: Icons.key_rounded,
                busy: _runningCertificateAction,
                label: openHandLocalizedText(
                  context,
                  zh: '生成密钥库',
                  zhHant: '產生金鑰庫',
                  en: 'Generate keystore',
                  fr: 'Générer le keystore',
                  de: 'Keystore erstellen',
                  ja: 'キーストア生成',
                ),
              ),
              _DashboardActionButton(
                onPressed: certificateBusy
                    ? null
                    : _verifyConfiguredApkSignature,
                icon: Icons.verified_rounded,
                busy: _runningCertificateAction,
                label: openHandLocalizedText(
                  context,
                  zh: '验签 APK',
                  zhHant: '驗簽 APK',
                  en: 'Verify APK',
                  fr: 'Vérifier APK',
                  de: 'APK prüfen',
                  ja: 'APK 検証',
                ),
              ),
              _DashboardActionButton(
                onPressed: certificateBusy ? null : _inspectMitmproxyCa,
                icon: Icons.policy_rounded,
                busy: _runningCertificateAction,
                label: openHandLocalizedText(
                  context,
                  zh: '检查 CA',
                  zhHant: '檢查 CA',
                  en: 'Inspect CA',
                  fr: 'Inspecter CA',
                  de: 'CA prüfen',
                  ja: 'CA 検査',
                ),
              ),
              _DashboardActionButton(
                onPressed: certificateBusy ? null : _installMitmproxySystemCa,
                icon: Icons.security_update_good_rounded,
                busy: _runningCertificateAction,
                label: openHandLocalizedText(
                  context,
                  zh: '安装系统 CA',
                  zhHant: '安裝系統 CA',
                  en: 'Install system CA',
                  fr: 'Installer la CA système',
                  de: 'System-CA installieren',
                  ja: 'システム CA インストール',
                ),
              ),
              if (artifactOutput != null && artifactOutput.isNotEmpty)
                _copyResultButton(artifactOutput),
            ],
          ),
          kOpenHandGap12,
          _pathTextField(
            controller: _mitmCertPathCtrl,
            hintText: openHandLocalizedText(
              context,
              zh: 'mitmproxy CA 路径，留默认使用 ~/.mitmproxy/mitmproxy-ca-cert.pem',
              zhHant:
                  'mitmproxy CA 路徑，留預設使用 ~/.mitmproxy/mitmproxy-ca-cert.pem',
              en: 'mitmproxy CA path, default ~/.mitmproxy/mitmproxy-ca-cert.pem',
              fr: 'Chemin CA mitmproxy, défaut ~/.mitmproxy/mitmproxy-ca-cert.pem',
              de: 'mitmproxy-CA-Pfad, Standard ~/.mitmproxy/mitmproxy-ca-cert.pem',
              ja: 'mitmproxy CA パス、既定は ~/.mitmproxy/mitmproxy-ca-cert.pem',
            ),
          ),
          kOpenHandGap10,
          if (artifactOutput != null && artifactOutput.isNotEmpty)
            _monospaceCard(cs, artifactOutput),
        ],
      ),
    );
  }

  // ── Crypto pad tab ────────────────────────────────────────────────────────

  Widget _buildCryptoTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final cryptoOutput = _base64OutCtrl.text.trim();
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _base64Ctrl,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              isDense: true,
              hintText: openHandLocalizedText(
                context,
                zh: '粘贴文本、Base64、URL 编码、JWT、密钥材料或待哈希内容...',
                zhHant: '貼上文字、Base64、URL 編碼、JWT、金鑰材料或待雜湊內容...',
                en: 'Paste text, Base64, URL encoding, JWT, key material, or content to hash...',
                fr: 'Collez texte, Base64, encodage URL, JWT, clés ou contenu à hacher...',
                de: 'Text, Base64, URL-Encoding, JWT, Schlüsselmaterial oder Hash-Inhalt einfügen...',
                ja: 'テキスト、Base64、URL エンコード、JWT、鍵素材、ハッシュ対象を貼り付け...',
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          kOpenHandGap10,
          _dashboardActionWrap(
            [
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _setCryptoOutput(
                        openHandLocalizedText(
                          context,
                          zh: 'Base64 编码',
                          zhHant: 'Base64 編碼',
                          en: 'Base64 encode',
                          fr: 'Encodage Base64',
                          de: 'Base64 kodieren',
                          ja: 'Base64 エンコード',
                        ),
                        base64Encode(utf8.encode(_base64Ctrl.text)),
                      ),
                icon: Icons.upload_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: 'Base64 编码',
                  zhHant: 'Base64 編碼',
                  en: 'B64 encode',
                  fr: 'Encoder B64',
                  de: 'B64 kodieren',
                  ja: 'B64 エンコード',
                ),
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty ? null : _decodeBase64Input,
                icon: Icons.download_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: 'Base64 解码',
                  zhHant: 'Base64 解碼',
                  en: 'B64 decode',
                  fr: 'Décoder B64',
                  de: 'B64 dekodieren',
                  ja: 'B64 デコード',
                ),
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _setCryptoOutput(
                        openHandLocalizedText(
                          context,
                          zh: 'URL 编码',
                          zhHant: 'URL 編碼',
                          en: 'URL encode',
                          fr: 'Encodage URL',
                          de: 'URL kodieren',
                          ja: 'URL エンコード',
                        ),
                        Uri.encodeComponent(_base64Ctrl.text),
                      ),
                icon: Icons.link_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: 'URL 编码',
                  zhHant: 'URL 編碼',
                  en: 'URL encode',
                  fr: 'Encoder URL',
                  de: 'URL kodieren',
                  ja: 'URL エンコード',
                ),
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty ? null : _decodeUrlInput,
                icon: Icons.link_off_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: 'URL 解码',
                  zhHant: 'URL 解碼',
                  en: 'URL decode',
                  fr: 'Décoder URL',
                  de: 'URL dekodieren',
                  ja: 'URL デコード',
                ),
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _hashCryptoInput('MD5', crypto.md5),
                icon: Icons.tag_rounded,
                label: 'MD5',
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _hashCryptoInput('SHA1', crypto.sha1),
                icon: Icons.tag_rounded,
                label: 'SHA1',
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _hashCryptoInput('SHA256', crypto.sha256),
                icon: Icons.tag_rounded,
                label: 'SHA256',
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _hashCryptoInput('SHA512', crypto.sha512),
                icon: Icons.tag_rounded,
                label: 'SHA512',
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty ? null : _decodeJwtInput,
                icon: Icons.token_rounded,
                label: openHandLocalizedText(
                  context,
                  zh: 'JWT 解析',
                  zhHant: 'JWT 解析',
                  en: 'JWT decode',
                  fr: 'Décoder JWT',
                  de: 'JWT dekodieren',
                  ja: 'JWT デコード',
                ),
              ),
              _copyResultButton(_cryptoCopyValue),
            ],
            alignment: Alignment.centerLeft,
            wrapAlignment: WrapAlignment.start,
          ),
          kOpenHandGap12,
          if (cryptoOutput.isNotEmpty) _monospaceCard(cs, _base64OutCtrl.text),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionTitle(ThemeData theme, ColorScheme cs, String label) {
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _dashboardSectionHeader({
    required List<Widget> leading,
    required List<Widget> actions,
  }) {
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final leadingWrap = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: leading,
          );
          final actionWrap = _dashboardActionWrap(actions);
          if (leading.isEmpty) {
            return actionWrap;
          }
          if (actions.isEmpty) {
            return Align(alignment: Alignment.centerLeft, child: leadingWrap);
          }
          final maxWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : kOpenHandDialogWidthExtraWide;
          if (maxWidth < _kDashboardHeaderCompactBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [leadingWrap, kOpenHandGap8, actionWrap],
            );
          }
          final leadingMaxWidth =
              maxWidth * _kDashboardHeaderLeadingMaxWidthRatio;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: leadingMaxWidth > _kDashboardHeaderLeadingMaxWidth
                      ? _kDashboardHeaderLeadingMaxWidth
                      : leadingMaxWidth,
                ),
                child: leadingWrap,
              ),
              kOpenHandHGap12,
              Expanded(child: actionWrap),
            ],
          );
        },
      ),
    );
  }

  Widget _dashboardActionWrap(
    List<Widget> actions, {
    AlignmentGeometry alignment = Alignment.centerRight,
    WrapAlignment wrapAlignment = WrapAlignment.end,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: alignment,
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: wrapAlignment,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ),
      ),
    );
  }

  List<_AndroidMcpServerView> _androidMcpServerViews(McpController controller) {
    final rows = <_AndroidMcpServerView>[];
    for (final server in controller.servers) {
      if (!server.isVisibleToTemplate(
        AiPromptTemplatePolicies.androidReverseExpertTemplateId,
      )) {
        continue;
      }
      final catalog = controller.toolCatalogFor(server.name);
      final health = controller.healthStatusFor(server.name);
      final matchedTools = catalog.tools
          .where(_isAndroidRelevantMcpTool)
          .toList(growable: false);
      final serverIsRelevant = _containsAndroidMcpKeyword(
        '${server.name} ${server.summary} ${server.type.transportValue}',
      );
      if (!serverIsRelevant && matchedTools.isEmpty) continue;
      rows.add(
        _AndroidMcpServerView(
          server: server,
          catalog: catalog,
          health: health,
          matchedTools: matchedTools,
        ),
      );
    }
    rows.sort((a, b) {
      final enabled = (b.server.enabled ? 1 : 0).compareTo(
        a.server.enabled ? 1 : 0,
      );
      if (enabled != 0) return enabled;
      final tools = b.matchedTools.length.compareTo(a.matchedTools.length);
      if (tools != 0) return tools;
      return a.server.name.toLowerCase().compareTo(b.server.name.toLowerCase());
    });
    return List<_AndroidMcpServerView>.unmodifiable(rows);
  }

  List<McpServer> _matchingAndroidMcpServersForCapability(
    McpController controller,
    TemplateRuntimeMcpCapabilitySpec capability, {
    bool visibleOnly = true,
  }) {
    bool isVisible(McpServer server) =>
        !visibleOnly ||
        server.isVisibleToTemplate(
          AiPromptTemplatePolicies.androidReverseExpertTemplateId,
        );
    final suggestedName = capability.suggestedServerName?.trim();
    final exactMatches = suggestedName == null || suggestedName.isEmpty
        ? const <McpServer>[]
        : controller.servers
              .where(
                (server) =>
                    isVisible(server) &&
                    server.name.toLowerCase() == suggestedName.toLowerCase(),
              )
              .toList(growable: false);
    if (exactMatches.isNotEmpty) return exactMatches;
    return controller.servers
        .where(
          (server) =>
              isVisible(server) &&
              TemplateRuntimeDependencyRegistry.containsAnyKeyword(
                controller.serverSearchText(server),
                capability.keywords,
              ),
        )
        .toList(growable: false);
  }

  bool _isAndroidRelevantMcpTool(McpTool tool) {
    return _containsAndroidMcpKeyword(
      '${tool.id} ${tool.name} ${tool.description}',
    );
  }

  bool _containsAndroidMcpKeyword(String raw) {
    final text = raw.toLowerCase();
    return _kAndroidMcpKeywords.any(text.contains);
  }

  List<PopupMenuEntry<_ToolchainCommandAction>> _toolchainCommandMenuItems(
    AndroidReverseToolchainProbe probe,
  ) {
    return _toolchainVisibleActions(probe)
        .map(
          (action) => PopupMenuItem<_ToolchainCommandAction>(
            value: action,
            child: Row(
              children: [
                Icon(_toolchainCommandIcon(action), size: 16),
                kOpenHandHGap8,
                Text(_toolchainCommandLabel(action)),
              ],
            ),
          ),
        )
        .toList(growable: false);
  }

  List<_ToolchainCommandAction> _toolchainVisibleActions(
    AndroidReverseToolchainProbe probe,
  ) {
    final plugin = _toolchainPluginForProbe(probe);
    if (plugin != null) {
      return <_ToolchainCommandAction>[
        if (plugin.isInstalled)
          _ToolchainCommandAction.update
        else
          _ToolchainCommandAction.install,
        if (plugin.isInstalled && plugin.supportsUninstall)
          _ToolchainCommandAction.uninstall,
        _ToolchainCommandAction.reference,
      ];
    }
    final installed = _toolchainResultForProbe(probe)?.ok;
    return <_ToolchainCommandAction>[
      if (installed != true) _ToolchainCommandAction.install,
      if (installed == true &&
          (probe.updateCommand?.trim().isNotEmpty ?? false))
        _ToolchainCommandAction.update,
      if (installed == true &&
          (probe.uninstallCommand?.trim().isNotEmpty ?? false))
        _ToolchainCommandAction.uninstall,
      _ToolchainCommandAction.reference,
    ];
  }

  AndroidReverseToolchainProbeResult? _toolchainResultForProbe(
    AndroidReverseToolchainProbe probe,
  ) {
    return _toolchainRows.where((row) => row.probe.id == probe.id).firstOrNull;
  }

  bool _isToolchainCommandRunning(
    AndroidReverseToolchainProbe probe,
    _ToolchainCommandAction action,
  ) {
    return _runningToolchainCommandIds.contains(
      _toolchainCommandKey(probe, action),
    );
  }

  String _toolchainCommandKey(
    AndroidReverseToolchainProbe probe,
    _ToolchainCommandAction action,
  ) {
    return '${probe.id}:${action.name}';
  }

  PluginInfo? _toolchainPluginForProbe(
    AndroidReverseToolchainProbe probe, [
    PluginServiceController? pluginController,
  ]) {
    final pluginId = androidReverseToolchainPluginIdForProbe(probe.id);
    if (pluginId == null) return null;
    return (pluginController ?? context.read<PluginServiceController>())
        .pluginById(pluginId);
  }

  Future<void> _handleToolchainAction(
    AndroidReverseToolchainProbe probe,
    _ToolchainCommandAction action,
  ) async {
    if (_isToolchainCommandRunning(probe, action)) return;
    if (action == _ToolchainCommandAction.reference) {
      _showToolchainInfoDialog(probe);
      return;
    }
    final plugin = _toolchainPluginForProbe(probe);
    if (plugin != null) {
      await _handleToolchainPluginAction(probe, plugin, action);
      return;
    }
    final commandAction = _toolchainCommandAction(action);
    if (commandAction == null) return;
    final actionLabel = _toolchainCommandLabel(action);
    final command = probe.commandFor(commandAction)?.trim() ?? '';
    if (command.isEmpty) {
      _showSnack(
        openHandLocalizedText(
          context,
          zh: '${probe.label} 暂无可自动执行的$actionLabel命令。',
          zhHant: '${probe.label} 暫無可自動執行的$actionLabel指令。',
          en: 'No executable ${actionLabel.toLowerCase()} command is available for ${probe.label}.',
          fr: 'Aucune commande ${actionLabel.toLowerCase()} exécutable disponible pour ${probe.label}.',
          de: 'Kein ausführbarer ${actionLabel.toLowerCase()}-Befehl für ${probe.label} verfügbar.',
          ja: '${probe.label} には自動実行できる $actionLabel コマンドがありません。',
        ),
      );
      return;
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '$actionLabel ${probe.label}？',
        zhHant: '$actionLabel ${probe.label}？',
        en: '$actionLabel ${probe.label}?',
        fr: '$actionLabel ${probe.label} ?',
        de: '$actionLabel ${probe.label}?',
        ja: '${probe.label} を$actionLabelしますか？',
      ),
      message: [
        openHandLocalizedText(
          context,
          zh: 'OpenHand 将直接执行以下命令，完成后自动刷新工具链诊断。',
          zhHant: 'OpenHand 將直接執行以下指令，完成後自動重新整理工具鏈診斷。',
          en: 'OpenHand will run the command below and refresh toolchain diagnostics afterwards.',
          fr: 'OpenHand exécutera la commande ci-dessous puis actualisera le diagnostic de la chaîne d’outils.',
          de: 'OpenHand führt den folgenden Befehl aus und aktualisiert danach die Toolchain-Diagnose.',
          ja: 'OpenHand は次のコマンドを実行し、完了後にツールチェーン診断を更新します。',
        ),
        '',
        command,
      ].join('\n'),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: actionLabel,
      destructive: action == _ToolchainCommandAction.uninstall,
    );
    if (!confirmed || !mounted) return;
    final key = _toolchainCommandKey(probe, action);
    setState(() {
      _runningToolchainCommandIds.add(key);
      _lastToolchainCommandResult = AdbCommandResult(
        args: <String>['toolchain', action.name, probe.id],
        exitCode: -1,
        stdout: _androidReverseRunningLabel(context),
        stderr: '',
        displayCommand: command,
      );
    });
    try {
      final result = await runAndroidReverseToolchainCommand(
        probe,
        commandAction,
      );
      if (!mounted) return;
      final adbResult = AdbCommandResult(
        args: <String>['toolchain', action.name, probe.id],
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
        timedOut: result.timedOut,
        displayCommand: result.command,
      );
      setState(() => _lastToolchainCommandResult = adbResult);
      _showSnack(
        adbResult.ok
            ? openHandLocalizedText(
                context,
                zh: '${probe.label} $actionLabel完成',
                zhHant: '${probe.label} $actionLabel完成',
                en: '${probe.label} ${actionLabel.toLowerCase()} completed',
                fr: '${probe.label} ${actionLabel.toLowerCase()} terminé',
                de: '${probe.label} ${actionLabel.toLowerCase()} abgeschlossen',
                ja: '${probe.label} の$actionLabelが完了しました',
              )
            : openHandLocalizedText(
                context,
                zh: '${probe.label} $actionLabel失败',
                zhHant: '${probe.label} $actionLabel失敗',
                en: '${probe.label} ${actionLabel.toLowerCase()} failed',
                fr: '${probe.label} ${actionLabel.toLowerCase()} échoué',
                de: '${probe.label} ${actionLabel.toLowerCase()} fehlgeschlagen',
                ja: '${probe.label} の$actionLabelに失敗しました',
              ),
      );
      unawaited(_refreshToolchain());
    } finally {
      if (mounted) {
        setState(() => _runningToolchainCommandIds.remove(key));
      }
    }
  }

  void _showToolchainInfoDialog(AndroidReverseToolchainProbe probe) {
    final row = _toolchainResultForProbe(probe);
    final plugin = _toolchainPluginForProbe(probe);
    androidReverseToolDialogs.show<void>(
      context: context,
      builder: (_) =>
          _ToolchainInfoDialog(probe: probe, result: row, plugin: plugin),
    );
  }

  Future<void> _handleToolchainPluginAction(
    AndroidReverseToolchainProbe probe,
    PluginInfo plugin,
    _ToolchainCommandAction action,
  ) async {
    final runtimeAction = switch (action) {
      _ToolchainCommandAction.install => _RuntimePluginAction.install,
      _ToolchainCommandAction.update => _RuntimePluginAction.update,
      _ToolchainCommandAction.uninstall => _RuntimePluginAction.uninstall,
      _ToolchainCommandAction.reference => null,
    };
    if (runtimeAction == null) return;
    final actionLabel = _toolchainCommandLabel(action);
    if (action == _ToolchainCommandAction.update && !plugin.isInstalled) {
      _showSnack(
        openHandLocalizedText(
          context,
          zh: '${plugin.name} 尚未安装。',
          zhHant: '${plugin.name} 尚未安裝。',
          en: '${plugin.name} is not installed.',
          fr: '${plugin.name} n’est pas installé.',
          de: '${plugin.name} ist nicht installiert.',
          ja: '${plugin.name} は未インストールです。',
        ),
      );
      return;
    }
    if (action == _ToolchainCommandAction.uninstall && !plugin.isInstalled) {
      _showSnack(
        openHandLocalizedText(
          context,
          zh: '${plugin.name} 尚未安装。',
          zhHant: '${plugin.name} 尚未安裝。',
          en: '${plugin.name} is not installed.',
          fr: '${plugin.name} n’est pas installé.',
          de: '${plugin.name} ist nicht installiert.',
          ja: '${plugin.name} は未インストールです。',
        ),
      );
      return;
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '$actionLabel ${probe.label}？',
        zhHant: '$actionLabel ${probe.label}？',
        en: '$actionLabel ${probe.label}?',
        fr: '$actionLabel ${probe.label} ?',
        de: '$actionLabel ${probe.label}?',
        ja: '${probe.label} を$actionLabelしますか？',
      ),
      message: openHandLocalizedText(
        context,
        zh: 'OpenHand 将通过插件服务直接$actionLabel ${plugin.name}，完成后自动刷新插件和工具链状态。',
        zhHant:
            'OpenHand 將透過外掛服務直接$actionLabel ${plugin.name}，完成後自動重新整理外掛與工具鏈狀態。',
        en: 'OpenHand will ${actionLabel.toLowerCase()} ${plugin.name} through the plugin service, then refresh plugin and toolchain status.',
        fr: 'OpenHand utilisera le service de plugins pour ${actionLabel.toLowerCase()} ${plugin.name}, puis actualisera les états plugin et outil.',
        de: 'OpenHand führt ${actionLabel.toLowerCase()} für ${plugin.name} über den Plugin-Dienst aus und aktualisiert danach Plugin- und Toolchain-Status.',
        ja: 'OpenHand はプラグインサービス経由で ${plugin.name} を$actionLabelし、完了後にプラグインとツールチェーン状態を更新します。',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: actionLabel,
      destructive: action == _ToolchainCommandAction.uninstall,
    );
    if (!confirmed || !mounted) return;
    final key = _toolchainCommandKey(probe, action);
    final pluginController = context.read<PluginServiceController>();
    setState(() {
      _runningToolchainCommandIds.add(key);
      _lastToolchainCommandResult = AdbCommandResult(
        args: <String>['toolchain-plugin', action.name, plugin.id],
        exitCode: -1,
        stdout: openHandLocalizedText(
          context,
          zh: '插件服务执行中...',
          zhHant: '外掛服務執行中...',
          en: 'Plugin service is running...',
          fr: 'Service de plugins en cours...',
          de: 'Plugin-Dienst läuft...',
          ja: 'プラグインサービスを実行中...',
        ),
        stderr: '',
        displayCommand: 'plugin:${plugin.id} ${action.name}',
      );
    });
    try {
      final success = switch (runtimeAction) {
        _RuntimePluginAction.install => await pluginController.installPlugin(
          plugin.id,
        ),
        _RuntimePluginAction.update => await pluginController.updatePlugin(
          plugin.id,
        ),
        _RuntimePluginAction.uninstall =>
          await pluginController.uninstallPlugin(plugin.id),
        _ => false,
      };
      if (!mounted) return;
      final latest = pluginController.pluginById(plugin.id) ?? plugin;
      final logs = pluginController.operationLogs.join('\n').trim();
      final stdout = <String>[
        '${openHandLocalizedText(context, zh: "插件", zhHant: "外掛", en: "Plugin", fr: "Plugin", de: "Plugin", ja: "プラグイン")}: ${latest.name}',
        '${openHandLocalizedText(context, zh: "动作", zhHant: "動作", en: "Action", fr: "Action", de: "Aktion", ja: "アクション")}: $actionLabel',
        '${openHandLocalizedText(context, zh: "状态", zhHant: "狀態", en: "Status", fr: "État", de: "Status", ja: "状態")}: ${success ? openHandLocalizedText(context, zh: "完成", zhHant: "完成", en: "completed", fr: "terminé", de: "abgeschlossen", ja: "完了") : openHandLocalizedText(context, zh: "失败", zhHant: "失敗", en: "failed", fr: "échec", de: "fehlgeschlagen", ja: "失敗")}',
        if (latest.installedVersion?.trim().isNotEmpty ?? false)
          '${openHandLocalizedText(context, zh: "版本", zhHant: "版本", en: "Version", fr: "Version", de: "Version", ja: "バージョン")}: ${latest.installedVersion}',
        if (latest.installPath?.trim().isNotEmpty ?? false)
          '${openHandLocalizedText(context, zh: "路径", zhHant: "路徑", en: "Path", fr: "Chemin", de: "Pfad", ja: "パス")}: ${latest.installPath}',
        if (logs.isNotEmpty) ...['', logs],
      ].join('\n');
      setState(() {
        _lastToolchainCommandResult = AdbCommandResult(
          args: <String>['toolchain-plugin', action.name, plugin.id],
          exitCode: success ? 0 : -1,
          stdout: stdout,
          stderr: success
              ? ''
              : (pluginController.errorMessage ??
                    latest.errorMessage ??
                    openHandLocalizedText(
                      context,
                      zh: '插件服务动作失败。',
                      zhHant: '外掛服務動作失敗。',
                      en: 'Plugin service action failed.',
                      fr: 'Échec de l’action du service plugin.',
                      de: 'Plugin-Dienstaktion fehlgeschlagen.',
                      ja: 'プラグインサービスの操作に失敗しました。',
                    )),
          displayCommand: 'plugin:${plugin.id} ${action.name}',
        );
      });
      _showSnack(
        success
            ? openHandLocalizedText(
                context,
                zh: '${plugin.name} $actionLabel完成',
                zhHant: '${plugin.name} $actionLabel完成',
                en: '${plugin.name} ${actionLabel.toLowerCase()} completed',
                fr: '${plugin.name} ${actionLabel.toLowerCase()} terminé',
                de: '${plugin.name} ${actionLabel.toLowerCase()} abgeschlossen',
                ja: '${plugin.name} の$actionLabelが完了しました',
              )
            : openHandLocalizedText(
                context,
                zh: '${plugin.name} $actionLabel失败',
                zhHant: '${plugin.name} $actionLabel失敗',
                en: '${plugin.name} ${actionLabel.toLowerCase()} failed',
                fr: '${plugin.name} ${actionLabel.toLowerCase()} échoué',
                de: '${plugin.name} ${actionLabel.toLowerCase()} fehlgeschlagen',
                ja: '${plugin.name} の$actionLabelに失敗しました',
              ),
      );
      unawaited(_refreshToolchain());
    } finally {
      if (mounted) {
        setState(() => _runningToolchainCommandIds.remove(key));
      }
    }
  }

  AndroidReverseToolchainCommandAction? _toolchainCommandAction(
    _ToolchainCommandAction action,
  ) {
    return switch (action) {
      _ToolchainCommandAction.install =>
        AndroidReverseToolchainCommandAction.install,
      _ToolchainCommandAction.update =>
        AndroidReverseToolchainCommandAction.update,
      _ToolchainCommandAction.uninstall =>
        AndroidReverseToolchainCommandAction.uninstall,
      _ToolchainCommandAction.reference => null,
    };
  }

  IconData _toolchainCommandIcon(_ToolchainCommandAction action) {
    return switch (action) {
      _ToolchainCommandAction.install => Icons.download_rounded,
      _ToolchainCommandAction.update => Icons.upgrade_rounded,
      _ToolchainCommandAction.uninstall => Icons.delete_outline_rounded,
      _ToolchainCommandAction.reference => Icons.info_outline_rounded,
    };
  }

  String _toolchainCommandLabel(_ToolchainCommandAction action) {
    return switch (action) {
      _ToolchainCommandAction.install => openHandInstallLabel(context),
      _ToolchainCommandAction.update => openHandUpdateLabel(context),
      _ToolchainCommandAction.uninstall => _androidReverseUninstallLabel(
        context,
      ),
      _ToolchainCommandAction.reference => openHandLocalizedText(
        context,
        zh: '查看信息',
        zhHant: '查看資訊',
        en: 'Info',
        fr: 'Infos',
        de: 'Info',
        ja: '情報',
      ),
    };
  }

  String _mcpResolvedToolName(McpServer server, McpTool tool) {
    return compactToolName(prefix: 'mcp__${server.name}', token: tool.id);
  }

  String _mcpCatalogStatusLabel(McpToolCatalogStatus status) {
    return switch (status) {
      McpToolCatalogStatus.idle => openHandLocalizedText(
        context,
        zh: '未扫描',
        zhHant: '未掃描',
        en: 'idle',
        fr: 'inactif',
        de: 'inaktiv',
        ja: '未スキャン',
      ),
      McpToolCatalogStatus.loading => openHandLocalizedText(
        context,
        zh: '扫描中',
        zhHant: '掃描中',
        en: 'loading',
        fr: 'chargement',
        de: 'lädt',
        ja: '読み込み中',
      ),
      McpToolCatalogStatus.ready => openHandLocalizedText(
        context,
        zh: '已就绪',
        zhHant: '已就緒',
        en: 'ready',
        fr: 'prêt',
        de: 'bereit',
        ja: '準備完了',
      ),
      McpToolCatalogStatus.failed => _androidReverseFailedLabel(context),
    };
  }

  String _mcpHealthStatusLabel(McpServerHealthStatus status) {
    return switch (status) {
      McpServerHealthStatus.idle => openHandLocalizedText(
        context,
        zh: '未探测',
        zhHant: '未探測',
        en: 'idle',
        fr: 'inactif',
        de: 'inaktiv',
        ja: '未チェック',
      ),
      McpServerHealthStatus.checking => openHandLocalizedText(
        context,
        zh: '探测中',
        zhHant: '探測中',
        en: 'checking',
        fr: 'vérification',
        de: 'prüft',
        ja: 'チェック中',
      ),
      McpServerHealthStatus.healthy => openHandLocalizedText(
        context,
        zh: '正常',
        zhHant: '正常',
        en: 'healthy',
        fr: 'sain',
        de: 'fehlerfrei',
        ja: '正常',
      ),
      McpServerHealthStatus.unhealthy => openHandLocalizedText(
        context,
        zh: '异常',
        zhHant: '異常',
        en: 'unhealthy',
        fr: 'anormal',
        de: 'fehlerhaft',
        ja: '異常',
      ),
    };
  }

  Color _mcpCatalogColor(McpToolCatalogStatus status, ColorScheme cs) {
    return switch (status) {
      McpToolCatalogStatus.ready => cs.primary,
      McpToolCatalogStatus.loading => cs.tertiary,
      McpToolCatalogStatus.failed => cs.error,
      McpToolCatalogStatus.idle => cs.outline,
    };
  }

  Color _mcpHealthColor(McpServerHealthStatus status, ColorScheme cs) {
    return switch (status) {
      McpServerHealthStatus.healthy => cs.primary,
      McpServerHealthStatus.checking => cs.tertiary,
      McpServerHealthStatus.unhealthy => cs.error,
      McpServerHealthStatus.idle => cs.outline,
    };
  }

  Widget _monospaceCard(ColorScheme cs, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
      ),
      child: _formattedTerminalText(text, cs),
    );
  }

  Widget _formattedTerminalText(String text, ColorScheme cs) {
    final formatted = formatStructuredTextForDisplay(text);
    final label = formatted.format == null
        ? null
        : structuredTextFormatLabel(formatted.format!);
    final base = TextStyle(
      fontFamily: kOpenHandMonospaceFontFamily,
      fontSize: 11,
      color: cs.onSurface,
      height: 1.5,
    );
    final content = ansiText(formatted.text, colorScheme: cs, base: base);
    if (label == null) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusPill(label: label, color: cs.primary),
        kOpenHandGap6,
        content,
      ],
    );
  }

  Widget _buildAdbCommandResultView(
    AdbCommandResult result,
    ColorScheme cs,
    ThemeData theme,
  ) {
    final ok = result.ok || result.partialOk;
    final statusColor = ok ? cs.primary : cs.error;
    final stdout = result.stdout.trim();
    final stderr = result.stderr.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusPill(
              label: ok
                  ? result.partialOk
                        ? openHandLocalizedText(
                            context,
                            zh: '部分完成',
                            zhHant: '部分完成',
                            en: 'partial',
                            fr: 'partiel',
                            de: 'teilweise',
                            ja: '一部完了',
                          )
                        : openHandLocalizedText(
                            context,
                            zh: '成功',
                            zhHant: '成功',
                            en: 'success',
                            fr: 'succès',
                            de: 'erfolgreich',
                            ja: '成功',
                          )
                  : _androidReverseFailedLabel(context),
              color: statusColor,
            ),
            _StatusPill(
              label:
                  '${openHandLocalizedText(context, zh: "退出码", zhHant: "退出碼", en: "exit", fr: "code", de: "Exit", ja: "終了コード")} ${result.exitCode}',
              color: statusColor,
            ),
            if (result.timedOut)
              _StatusPill(
                label: openHandLocalizedText(
                  context,
                  zh: '超时',
                  zhHant: '逾時',
                  en: 'timeout',
                  fr: 'expiration',
                  de: 'Timeout',
                  ja: 'タイムアウト',
                ),
                color: cs.tertiary,
              ),
          ],
        ),
        kOpenHandGap8,
        _resultSection(
          cs,
          theme,
          openHandLocalizedText(
            context,
            zh: '命令',
            zhHant: '指令',
            en: 'Command',
            fr: 'Commande',
            de: 'Befehl',
            ja: 'コマンド',
          ),
          result.commandLine,
        ),
        if (stdout.isNotEmpty) ...[
          kOpenHandGap8,
          _resultSection(cs, theme, 'stdout', stdout),
        ],
        if (stderr.isNotEmpty) ...[
          kOpenHandGap8,
          _resultSection(cs, theme, 'stderr', stderr, isError: !ok),
        ],
        if (stdout.isEmpty && stderr.isEmpty) ...[
          kOpenHandGap8,
          Text(
            _androidReverseNoOutputLabel(context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  Widget _resultSection(
    ColorScheme cs,
    ThemeData theme,
    String title,
    String text, {
    bool isError = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isError
            ? cs.errorContainer.withValues(alpha: 0.18)
            : cs.surface.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(kOpenHandRadius6),
        border: Border.all(
          color: (isError ? cs.error : cs.outlineVariant).withValues(
            alpha: 0.42,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isError ? cs.error : cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          kOpenHandGap4,
          _formattedTerminalText(text, cs),
        ],
      ),
    );
  }

  void _setCryptoOutput(String title, String output) {
    final value = output.trimRight();
    setState(() {
      _cryptoCopyValue = value;
      _base64OutCtrl.text = [
        '# $title',
        value.isEmpty ? '(empty)' : value,
      ].join('\n');
    });
  }

  void _decodeBase64Input() {
    try {
      final decoded = utf8.decode(
        decodeFlexibleBase64Bounded(
          _base64Ctrl.text,
          maxDecodedBytes: _kCryptoDecodeMaxBytes,
        ),
      );
      _setCryptoOutput(
        openHandLocalizedText(
          context,
          zh: 'Base64 解码',
          zhHant: 'Base64 解碼',
          en: 'Base64 decode',
          fr: 'Décodage Base64',
          de: 'Base64 dekodieren',
          ja: 'Base64 デコード',
        ),
        decoded,
      );
    } catch (error) {
      _setCryptoOutput(
        openHandLocalizedText(
          context,
          zh: 'Base64 解码失败',
          zhHant: 'Base64 解碼失敗',
          en: 'Base64 decode failed',
          fr: 'Échec du décodage Base64',
          de: 'Base64-Dekodierung fehlgeschlagen',
          ja: 'Base64 デコードに失敗しました',
        ),
        '$error',
      );
    }
  }

  void _decodeUrlInput() {
    try {
      _setCryptoOutput(
        openHandLocalizedText(
          context,
          zh: 'URL 解码',
          zhHant: 'URL 解碼',
          en: 'URL decode',
          fr: 'Décodage URL',
          de: 'URL dekodieren',
          ja: 'URL デコード',
        ),
        Uri.decodeComponent(_base64Ctrl.text),
      );
    } catch (error) {
      _setCryptoOutput(
        openHandLocalizedText(
          context,
          zh: 'URL 解码失败',
          zhHant: 'URL 解碼失敗',
          en: 'URL decode failed',
          fr: 'Échec du décodage URL',
          de: 'URL-Dekodierung fehlgeschlagen',
          ja: 'URL デコードに失敗しました',
        ),
        '$error',
      );
    }
  }

  void _hashCryptoInput(String label, crypto.Hash algorithm) {
    final bytes = utf8.encode(_base64Ctrl.text);
    _setCryptoOutput(label, algorithm.convert(bytes).toString());
  }

  void _decodeJwtInput() {
    try {
      final token = _base64Ctrl.text.trim();
      final parts = token.split('.');
      if (parts.length < 2) {
        throw const FormatException('JWT must contain header and payload.');
      }
      final header = _decodeJwtSegment(parts[0]);
      final payload = _decodeJwtSegment(parts[1]);
      final headerText = prettyPrintJson(jsonDecode(header));
      final payloadText = prettyPrintJson(jsonDecode(payload));
      _setCryptoOutput(
        openHandLocalizedText(
          context,
          zh: 'JWT 解析',
          zhHant: 'JWT 解析',
          en: 'JWT decode',
          fr: 'Décodage JWT',
          de: 'JWT dekodieren',
          ja: 'JWT デコード',
        ),
        [
          '## header',
          headerText,
          '',
          '## payload',
          payloadText,
          if (parts.length > 2) ...['', '## signature', parts[2]],
        ].join('\n'),
      );
    } catch (error) {
      _setCryptoOutput(
        openHandLocalizedText(
          context,
          zh: 'JWT 解析失败',
          zhHant: 'JWT 解析失敗',
          en: 'JWT decode failed',
          fr: 'Échec du décodage JWT',
          de: 'JWT-Dekodierung fehlgeschlagen',
          ja: 'JWT デコードに失敗しました',
        ),
        '$error',
      );
    }
  }

  String _decodeJwtSegment(String segment) {
    return utf8.decode(base64Url.decode(base64Url.normalize(segment)));
  }

  Widget _buildPathActionRow({
    required TextEditingController primaryController,
    required String primaryHint,
    TextEditingController? secondaryController,
    String? secondaryHint,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _pathTextField(
            controller: primaryController,
            hintText: primaryHint,
          ),
        ),
        if (secondaryController != null) ...[
          kOpenHandHGap8,
          Expanded(
            child: _pathTextField(
              controller: secondaryController,
              hintText: secondaryHint ?? '',
            ),
          ),
        ],
        kOpenHandHGap8,
        SizedBox(
          width: _kDeviceTrailingActionWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _DashboardActionButton(
              onPressed: onPressed,
              icon: icon,
              label: label,
            ),
          ),
        ),
      ],
    );
  }

  Widget _pathTextField({
    required TextEditingController controller,
    required String hintText,
  }) {
    return SizedBox(
      height: _kAdbInlineControlHeight,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        style: const TextStyle(
          fontFamily: kOpenHandMonospaceFontFamily,
          fontSize: 12,
        ),
      ),
    );
  }

  String _normalizeAdbShellInput(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return value;
    final adbShellPrefix = RegExp(
      r"""^adb(?:\s+(?:-s\s+(?:"[^"]+"|'[^']+'|\S+)|-d|-e|-a|-t\s+\S+|-H\s+\S+|-P\s+\S+))*\s+shell(?:\s+(?:-T|-t|-tt|-x|-n|--))*\s*""",
      caseSensitive: false,
    );
    final match = adbShellPrefix.firstMatch(value);
    if (match == null) return value;
    return value.substring(match.end).trim();
  }

  String? _logcatPackageTarget() {
    final selected = _selectedPackageName?.trim();
    if (selected != null && selected.isNotEmpty) return selected;
    final configured = _ctrl.config.packageName?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return null;
  }
}

class _AndroidMcpServerView {
  const _AndroidMcpServerView({
    required this.server,
    required this.catalog,
    required this.health,
    required this.matchedTools,
  });

  final McpServer server;
  final McpToolCatalog catalog;
  final McpServerHealth health;
  final List<McpTool> matchedTools;
}

class _ParsedLogcatLine {
  const _ParsedLogcatLine({
    required this.raw,
    required this.message,
    this.level,
    this.time,
    this.pid,
    this.tid,
    this.tag,
  });

  final String raw;
  final String message;
  final String? level;
  final String? time;
  final String? pid;
  final String? tid;
  final String? tag;
}

class _LogcatLineTile extends StatelessWidget {
  const _LogcatLineTile({
    required this.parsed,
    required this.colorScheme,
    required this.theme,
    required this.isZh,
    required this.onMenu,
  });

  final _ParsedLogcatLine parsed;
  final ColorScheme colorScheme;
  final ThemeData theme;
  final bool isZh;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final level = parsed.level?.trim().toUpperCase();
    final color = _levelColor(level, colorScheme);
    final meta = <String>[
      if (parsed.time?.trim().isNotEmpty ?? false) parsed.time!.trim(),
      if (parsed.pid?.trim().isNotEmpty ?? false)
        (parsed.tid?.trim().isNotEmpty ?? false)
            ? 'pid ${parsed.pid}/${parsed.tid}'
            : 'pid ${parsed.pid}',
      if (parsed.tag?.trim().isNotEmpty ?? false) parsed.tag!.trim(),
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => onMenu(details.globalPosition),
      onDoubleTapDown: (details) => onMenu(details.globalPosition),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: level == null ? 0.03 : 0.07),
          borderRadius: BorderRadius.circular(kOpenHandRadius6),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: kOpenHandBorderRadius5,
              ),
              child: Text(
                level == null ? '-' : _shortLevelLabel(level),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontFamily: kOpenHandMonospaceFontFamily,
                ),
              ),
            ),
            kOpenHandHGap8,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (meta.isNotEmpty)
                    Text(
                      meta.join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: kOpenHandMonospaceFontFamily,
                        height: 1.25,
                      ),
                    ),
                  Text(
                    parsed.message.isEmpty ? parsed.raw : parsed.message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 11,
                      color: level == 'E' || level == 'F'
                          ? color
                          : colorScheme.onSurface,
                      height: 1.36,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _levelColor(String? level, ColorScheme cs) {
    return switch (level) {
      'F' => const Color(0xFF8B1E1E),
      'E' => cs.error,
      'W' => const Color(0xFFB26A00),
      'I' => const Color(0xFF1E63B6),
      'D' => const Color(0xFF7B4BB3),
      'V' => cs.outline,
      _ => cs.onSurfaceVariant,
    };
  }

  String _shortLevelLabel(String level) {
    return switch (level) {
      'V' => 'V',
      'D' => 'D',
      'I' => 'I',
      'W' => 'W',
      'E' => 'E',
      'F' => 'F',
      _ => level,
    };
  }
}

class _DashboardActionButton extends StatelessWidget {
  const _DashboardActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.filled = false,
    this.height = _kDashboardActionButtonHeight,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// 忙碌时前导位换成转圈：与图标同边长、走全局动效切换。
  ///
  /// 此前二十多个按钮各自内联 `busy ? SizedBox(spinner) : Icon(...)`，转圈边长
  /// 取遍 12/14/16 而图标固定 14，状态一翻转按钮文字就横向抖一下。
  final bool busy;

  final bool filled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = FilledButton.styleFrom(
      minimumSize: const Size(0, _kDashboardActionButtonHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      textStyle: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    );
    final effectiveIcon = OpenHandBusyStatusIcon(
      busy: busy,
      icon: icon,
      size: _kDashboardActionIconSize,
      strokeWidth: 1.6,
    );
    final labelWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
    return SizedBox(
      height: height,
      child: filled
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: effectiveIcon,
              label: labelWidget,
              style: style,
            )
          : FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: effectiveIcon,
              label: labelWidget,
              style: style,
            ),
    );
  }
}

ButtonStyle _dashboardIconActionStyle(ColorScheme cs) {
  return ButtonStyle(
    fixedSize: const WidgetStatePropertyAll<Size>(
      Size.square(_kDashboardIconActionButtonSize),
    ),
    minimumSize: const WidgetStatePropertyAll<Size>(
      Size.square(_kDashboardIconActionButtonSize),
    ),
    maximumSize: const WidgetStatePropertyAll<Size>(
      Size.square(_kDashboardIconActionButtonSize),
    ),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.zero),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: const WidgetStatePropertyAll<OutlinedBorder>(CircleBorder()),
    backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return cs.surfaceContainerHighest.withValues(alpha: 0.46);
      }
      if (states.contains(WidgetState.pressed)) {
        return cs.secondaryContainer.withValues(alpha: 0.92);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return cs.secondaryContainer.withValues(alpha: 0.72);
      }
      return cs.surfaceContainerHighest.withValues(alpha: 0.86);
    }),
    foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return cs.onSurface.withValues(alpha: 0.38);
      }
      return cs.onSurfaceVariant;
    }),
    iconColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return cs.onSurface.withValues(alpha: 0.38);
      }
      return cs.onSurfaceVariant;
    }),
    overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return cs.primary.withValues(alpha: 0.12);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return cs.primary.withValues(alpha: 0.08);
      }
      return null;
    }),
  );
}

class _DashboardIconActionButton extends StatelessWidget {
  const _DashboardIconActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// 忙碌时图标位换成同边长的转圈，避免按钮大小随状态跳变。
  final bool busy;

  /// 覆盖图标配色，用于删除这类破坏性动作。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: _kDashboardIconActionButtonSize,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        splashRadius: _kDashboardIconActionButtonSize / 2,
        style: _dashboardIconActionStyle(cs),
        icon: OpenHandBusyStatusIcon(
          busy: busy,
          icon: icon,
          color: color,
          size: _kDashboardIconActionIconSize,
          strokeWidth: 1.7,
        ),
      ),
    );
  }
}

class _DashboardPopupIconActionButton<T> extends StatelessWidget {
  const _DashboardPopupIconActionButton({
    required this.icon,
    required this.tooltip,
    required this.itemBuilder,
    required this.onSelected,
    this.enabled = true,
  });

  final Widget icon;
  final String tooltip;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: _kDashboardIconActionButtonSize,
      child: IconButtonTheme(
        data: IconButtonThemeData(style: _dashboardIconActionStyle(cs)),
        child: AnimatedPopupMenuButton<T>(
          tooltip: tooltip,
          enabled: enabled,
          icon: IconTheme.merge(
            data: const IconThemeData(size: _kDashboardIconActionIconSize),
            child: icon,
          ),
          iconSize: _kDashboardIconActionIconSize,
          padding: EdgeInsets.zero,
          splashRadius: _kDashboardIconActionButtonSize / 2,
          buttonConstraints: const BoxConstraints.tightFor(
            width: _kDashboardIconActionButtonSize,
            height: _kDashboardIconActionButtonSize,
          ),
          itemBuilder: itemBuilder,
          onSelected: onSelected,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    this.compact = false,
    this.subtle = false,
  });

  final String label;
  final Color color;
  final bool compact;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: subtle
            ? cs.surfaceContainerHighest.withValues(alpha: 0.56)
            : color.withValues(alpha: 0.12),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(
          color: color.withValues(alpha: subtle ? 0.24 : 0.36),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 10.5 : null,
          height: 1.05,
        ),
      ),
    );
  }
}

class _DeviceInfoRow extends StatelessWidget {
  const _DeviceInfoRow({
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  final String label;
  final String value;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          kOpenHandHGap8,
          Expanded(
            child: SelectableText(
              value,
              maxLines: label.length > 12 ? 2 : 3,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: kOpenHandMonospaceFontFamily,
                color: colorScheme.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForwardRow extends StatelessWidget {
  const _ForwardRow({
    required this.row,
    required this.colorScheme,
    required this.onRemove,
    required this.removeTooltip,
  });

  final String row;
  final ColorScheme colorScheme;
  final VoidCallback? onRemove;
  final String removeTooltip;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(kOpenHandRadius6),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              row,
              maxLines: 2,
              style: TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          kOpenHandHGap6,
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 14),
            tooltip: removeTooltip,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          ),
        ],
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _DashboardActionButton(
      onPressed: onPressed,
      icon: icon,
      label: label,
    );
  }
}

String _runtimePluginStatusLabel(BuildContext context, PluginInfo plugin) {
  return switch (plugin.status) {
    PluginStatus.notInstalled => _androidReverseNotInstalledLabel(context),
    PluginStatus.installed =>
      plugin.enabled
          ? openHandLocalizedText(
              context,
              zh: '已安装并启用',
              zhHant: '已安裝並啟用',
              en: 'Installed and enabled',
              fr: 'Installé et activé',
              de: 'Installiert und aktiviert',
              ja: 'インストール済み、有効',
            )
          : openHandLocalizedText(
              context,
              zh: '已安装但禁用',
              zhHant: '已安裝但停用',
              en: 'Installed but disabled',
              fr: 'Installé mais désactivé',
              de: 'Installiert, aber deaktiviert',
              ja: 'インストール済み、無効',
            ),
    PluginStatus.installing => openHandLocalizedText(
      context,
      zh: '安装中',
      zhHant: '安裝中',
      en: 'Installing',
      fr: 'Installation',
      de: 'Installation läuft',
      ja: 'インストール中',
    ),
    PluginStatus.updating => openHandLocalizedText(
      context,
      zh: '更新中',
      zhHant: '更新中',
      en: 'Updating',
      fr: 'Mise à jour',
      de: 'Aktualisierung läuft',
      ja: '更新中',
    ),
    PluginStatus.uninstalling => openHandLocalizedText(
      context,
      zh: '卸载中',
      zhHant: '解除安裝中',
      en: 'Uninstalling',
      fr: 'Désinstallation',
      de: 'Deinstallation läuft',
      ja: 'アンインストール中',
    ),
    PluginStatus.error => openHandLocalizedText(
      context,
      zh: '异常',
      zhHant: '異常',
      en: 'Error',
      fr: 'Erreur',
      de: 'Fehler',
      ja: 'エラー',
    ),
  };
}

class _ToolchainInfoDialog extends StatelessWidget {
  const _ToolchainInfoDialog({
    required this.probe,
    required this.result,
    required this.plugin,
  });

  final AndroidReverseToolchainProbe probe;
  final AndroidReverseToolchainProbeResult? result;
  final PluginInfo? plugin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final installed = result?.ok ?? plugin?.isInstalled;
    final statusColor = installed == true
        ? cs.primary
        : installed == false
        ? cs.error
        : cs.outline;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthCompact,
      maxHeight: kOpenHandDialogHeightStandard,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.info_outline_rounded,
            title:
                '${probe.label} ${openHandLocalizedText(context, zh: "详情", zhHant: "詳情", en: "Details", fr: "Détails", de: "Details", ja: "詳細")}',
            subtitle: probe.id,
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Flexible(
            child: OpenHandSafeScrollbar(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _DashboardDetailSection(
                    title: _androidReverseBasicInfoLabel(context),
                    icon: Icons.construction_rounded,
                    children: [
                      _DashboardDetailRow(
                        label: _androidReverseNameLabel(context),
                        value: probe.label,
                      ),
                      _DashboardDetailRow(label: 'ID', value: probe.id),
                      _DashboardDetailRow(
                        label: openHandTypeLabel(context),
                        value: plugin == null
                            ? openHandLocalizedText(
                                context,
                                zh: '系统工具链',
                                zhHant: '系統工具鏈',
                                en: 'System toolchain',
                                fr: 'Chaîne d’outils système',
                                de: 'System-Toolchain',
                                ja: 'システムツールチェーン',
                              )
                            : openHandLocalizedText(
                                context,
                                zh: '插件托管工具',
                                zhHant: '外掛托管工具',
                                en: 'Plugin-managed tool',
                                fr: 'Outil géré par plugin',
                                de: 'Pluginverwaltetes Tool',
                                ja: 'プラグイン管理ツール',
                              ),
                      ),
                      _DashboardDetailRow(
                        label: openHandLocalizedText(
                          context,
                          zh: '必要',
                          zhHant: '必要',
                          en: 'Required',
                          fr: 'Requis',
                          de: 'Erforderlich',
                          ja: '必須',
                        ),
                        value: probe.required
                            ? openHandYesLabel(context)
                            : openHandNoLabel(context),
                      ),
                      _DashboardDetailRow(
                        label: _androidReverseStatusLabel(context),
                        value: installed == true
                            ? openHandInstalledLabel(context)
                            : installed == false
                            ? _androidReverseNotInstalledLabel(context)
                            : openHandNotCheckedLabel(context),
                        valueColor: statusColor,
                      ),
                    ],
                  ),
                  if (result != null) ...[
                    kOpenHandGap14,
                    _DashboardDetailSection(
                      title: openHandLocalizedText(
                        context,
                        zh: '诊断结果',
                        zhHant: '診斷結果',
                        en: 'Diagnostic',
                        fr: 'Diagnostic',
                        de: 'Diagnose',
                        ja: '診断',
                      ),
                      icon: Icons.fact_check_rounded,
                      accentColor: statusColor,
                      children: [
                        _DashboardDetailRow(
                          label: openHandOutputLabel(context),
                          value: result!.displayValue,
                          monospace: true,
                          valueColor: result!.ok ? null : cs.error,
                        ),
                        _DashboardDetailRow(
                          label: openHandLocalizedText(
                            context,
                            zh: '退出码',
                            zhHant: '退出碼',
                            en: 'Exit code',
                            fr: 'Code de sortie',
                            de: 'Exit-Code',
                            ja: '終了コード',
                          ),
                          value: '${result!.exitCode}',
                          monospace: true,
                        ),
                        _DashboardDetailRow(
                          label: openHandDurationLabel(context),
                          value: '${result!.durationMs}ms',
                          monospace: true,
                        ),
                        if (result!.stderr.trim().isNotEmpty)
                          _DashboardDetailRow(
                            label: openHandErrorLabel(context),
                            value: result!.stderr.trim(),
                            valueColor: cs.error,
                            monospace: true,
                          ),
                      ],
                    ),
                  ],
                  kOpenHandGap14,
                  _DashboardDetailSection(
                    title: openHandLocalizedText(
                      context,
                      zh: '可用操作',
                      zhHant: '可用操作',
                      en: 'Available actions',
                      fr: 'Actions disponibles',
                      de: 'Verfügbare Aktionen',
                      ja: '利用可能な操作',
                    ),
                    icon: Icons.terminal_rounded,
                    children: [
                      _DashboardDetailRow(
                        label: openHandInstallLabel(context),
                        value:
                            _commandText(probe.installCommand) ??
                            _androidToolchainInstallHint(context, probe),
                        monospace:
                            probe.installCommand?.trim().isNotEmpty ?? false,
                      ),
                      _DashboardDetailRow(
                        label: openHandUpdateLabel(context),
                        value: _commandText(probe.updateCommand),
                        monospace: true,
                      ),
                      _DashboardDetailRow(
                        label: _androidReverseUninstallLabel(context),
                        value: _commandText(probe.uninstallCommand),
                        monospace: true,
                      ),
                      _DashboardDetailRow(
                        label: openHandLocalizedText(
                          context,
                          zh: '参考',
                          zhHant: '參考',
                          en: 'Reference',
                          fr: 'Référence',
                          de: 'Referenz',
                          ja: '参考',
                        ),
                        value: _commandText(probe.referenceUrl),
                        monospace: true,
                      ),
                    ],
                  ),
                  if (plugin != null) ...[
                    kOpenHandGap14,
                    _DashboardDetailSection(
                      title: openHandLocalizedText(
                        context,
                        zh: '关联插件',
                        zhHant: '關聯外掛',
                        en: 'Linked plugin',
                        fr: 'Plugin lié',
                        de: 'Verknüpftes Plugin',
                        ja: '関連プラグイン',
                      ),
                      icon: Icons.extension_rounded,
                      children: [
                        _DashboardDetailRow(
                          label: _androidReverseNameLabel(context),
                          value: plugin!.name,
                        ),
                        _DashboardDetailRow(label: 'ID', value: plugin!.id),
                        _DashboardDetailRow(
                          label: _androidReverseDescriptionLabel(context),
                          value: plugin!.description,
                        ),
                        _DashboardDetailRow(
                          label: _androidReverseStatusLabel(context),
                          value: _runtimePluginStatusLabel(context, plugin!),
                          valueColor: plugin!.isInstalled
                              ? plugin!.enabled
                                    ? cs.primary
                                    : cs.outline
                              : plugin!.status == PluginStatus.error
                              ? cs.error
                              : cs.tertiary,
                        ),
                        _DashboardDetailRow(
                          label: openHandLocalizedText(
                            context,
                            zh: '版本',
                            zhHant: '版本',
                            en: 'Version',
                            fr: 'Version',
                            de: 'Version',
                            ja: 'バージョン',
                          ),
                          value: plugin!.installedVersion,
                        ),
                        _DashboardDetailRow(
                          label: openHandPathLabel(context),
                          value: plugin!.installPath,
                          monospace: true,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _commandText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class _RuntimePluginInfoDialog extends StatelessWidget {
  const _RuntimePluginInfoDialog({required this.plugin});

  final PluginInfo plugin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final specs = TemplateRuntimeDependencyRegistry.specsForPlugin(plugin.id);
    final statusColor = plugin.isInstalled
        ? plugin.enabled
              ? cs.primary
              : cs.outline
        : plugin.status == PluginStatus.error
        ? cs.error
        : cs.tertiary;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthCompact,
      maxHeight: kOpenHandDialogHeightCompact,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.extension_rounded,
            title:
                '${plugin.name} ${openHandLocalizedText(context, zh: "信息", zhHant: "資訊", en: "Info", fr: "Infos", de: "Info", ja: "情報")}',
            subtitle: plugin.id,
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Flexible(
            child: OpenHandSafeScrollbar(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _DashboardDetailSection(
                    title: _androidReverseBasicInfoLabel(context),
                    icon: Icons.info_outline_rounded,
                    children: [
                      _DashboardDetailRow(
                        label: _androidReverseNameLabel(context),
                        value: plugin.name,
                      ),
                      _DashboardDetailRow(label: 'ID', value: plugin.id),
                      _DashboardDetailRow(
                        label: _androidReverseDescriptionLabel(context),
                        value: plugin.description,
                      ),
                      _DashboardDetailRow(
                        label: _androidReverseStatusLabel(context),
                        value: _runtimePluginStatusLabel(context, plugin),
                        valueColor: statusColor,
                      ),
                      _DashboardDetailRow(
                        label: openHandLocalizedText(
                          context,
                          zh: '启用',
                          zhHant: '啟用',
                          en: 'Enabled',
                          fr: 'Activé',
                          de: 'Aktiviert',
                          ja: '有効',
                        ),
                        value: plugin.enabled
                            ? openHandYesLabel(context)
                            : openHandNoLabel(context),
                      ),
                    ],
                  ),
                  kOpenHandGap14,
                  _DashboardDetailSection(
                    title: openHandLocalizedText(
                      context,
                      zh: '版本与路径',
                      zhHant: '版本與路徑',
                      en: 'Version and path',
                      fr: 'Version et chemin',
                      de: 'Version und Pfad',
                      ja: 'バージョンとパス',
                    ),
                    icon: Icons.inventory_2_rounded,
                    children: [
                      _DashboardDetailRow(
                        label: openHandLocalizedText(
                          context,
                          zh: '已安装版本',
                          zhHant: '已安裝版本',
                          en: 'Installed',
                          fr: 'Installé',
                          de: 'Installiert',
                          ja: 'インストール済み',
                        ),
                        value: plugin.installedVersion,
                      ),
                      _DashboardDetailRow(
                        label: openHandLocalizedText(
                          context,
                          zh: '最新版本',
                          zhHant: '最新版本',
                          en: 'Latest',
                          fr: 'Dernière',
                          de: 'Neueste',
                          ja: '最新',
                        ),
                        value: plugin.latestVersion,
                      ),
                      _DashboardDetailRow(
                        label: openHandLocalizedText(
                          context,
                          zh: '安装路径',
                          zhHant: '安裝路徑',
                          en: 'Install path',
                          fr: 'Chemin d’installation',
                          de: 'Installationspfad',
                          ja: 'インストールパス',
                        ),
                        value: plugin.installPath,
                        monospace: true,
                      ),
                      _DashboardDetailRow(
                        label: openHandLocalizedText(
                          context,
                          zh: '支持卸载',
                          zhHant: '支援解除安裝',
                          en: 'Uninstallable',
                          fr: 'Désinstallable',
                          de: 'Deinstallierbar',
                          ja: 'アンインストール可能',
                        ),
                        value: plugin.supportsUninstall
                            ? openHandYesLabel(context)
                            : openHandNoLabel(context),
                      ),
                    ],
                  ),
                  kOpenHandGap14,
                  _DashboardDetailSection(
                    title: openHandLocalizedText(
                      context,
                      zh: '依赖关系',
                      zhHant: '依賴關係',
                      en: 'Dependencies',
                      fr: 'Dépendances',
                      de: 'Abhängigkeiten',
                      ja: '依存関係',
                    ),
                    icon: Icons.account_tree_rounded,
                    children: [
                      _DashboardDetailRow(
                        label: openHandLocalizedText(
                          context,
                          zh: '依赖',
                          zhHant: '依賴',
                          en: 'Depends on',
                          fr: 'Dépend de',
                          de: 'Hängt ab von',
                          ja: '依存先',
                        ),
                        value: plugin.dependencies.isEmpty
                            ? _androidReverseNoneLabel(context)
                            : plugin.dependencies.join(', '),
                        monospace: plugin.dependencies.isNotEmpty,
                      ),
                      _DashboardDetailRow(
                        label: openHandLocalizedText(
                          context,
                          zh: '被依赖',
                          zhHant: '被依賴',
                          en: 'Required by',
                          fr: 'Requis par',
                          de: 'Benötigt von',
                          ja: '依存元',
                        ),
                        value: plugin.dependents.isEmpty
                            ? _androidReverseNoneLabel(context)
                            : plugin.dependents.join(', '),
                        monospace: plugin.dependents.isNotEmpty,
                      ),
                    ],
                  ),
                  if (specs.isNotEmpty) ...[
                    kOpenHandGap14,
                    _DashboardDetailSection(
                      title: openHandLocalizedText(
                        context,
                        zh: '逆向模板关联',
                        zhHant: '逆向模板關聯',
                        en: 'Reverse templates',
                        fr: 'Templates reverse',
                        de: 'Reverse-Vorlagen',
                        ja: 'リバーステンプレート',
                      ),
                      icon: Icons.dashboard_customize_rounded,
                      children: [
                        _DashboardDetailRow(
                          label: openHandLocalizedText(
                            context,
                            zh: '关联模板',
                            zhHant: '關聯模板',
                            en: 'Templates',
                            fr: 'Templates',
                            de: 'Vorlagen',
                            ja: 'テンプレート',
                          ),
                          value: specs
                              .map(
                                (spec) => openHandLocalizedText(
                                  context,
                                  zh: spec.labelZh,
                                  zhHant: spec.labelZhHant,
                                  en: spec.labelEn,
                                  fr: spec.labelFr,
                                  de: spec.labelDe,
                                  ja: spec.labelJa,
                                ),
                              )
                              .join(', '),
                        ),
                      ],
                    ),
                  ],
                  if (plugin.errorMessage?.trim().isNotEmpty ?? false) ...[
                    kOpenHandGap14,
                    _DashboardDetailSection(
                      title: openHandLocalizedText(
                        context,
                        zh: '异常信息',
                        zhHant: '異常資訊',
                        en: 'Error',
                        fr: 'Erreur',
                        de: 'Fehler',
                        ja: 'エラー',
                      ),
                      icon: Icons.error_outline_rounded,
                      accentColor: cs.error,
                      children: [
                        _DashboardDetailRow(
                          label: openHandErrorLabel(context),
                          value: plugin.errorMessage!.trim(),
                          valueColor: cs.error,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardDetailSection extends StatelessWidget {
  const _DashboardDetailSection({
    required this.title,
    required this.icon,
    required this.children,
    this.accentColor,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = accentColor ?? cs.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            kOpenHandHGap8,
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        kOpenHandGap8,
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(kOpenHandRadius8),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _DashboardDetailRow extends StatelessWidget {
  const _DashboardDetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.monospace = false,
  });

  final String label;
  final String? value;
  final Color? valueColor;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final normalized = value?.trim();
    final display = normalized == null || normalized.isEmpty ? '-' : normalized;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          kOpenHandHGap10,
          Expanded(
            child: SelectableText(
              display,
              style: theme.textTheme.bodySmall?.copyWith(
                color: valueColor ?? cs.onSurface,
                fontFamily: monospace ? kOpenHandMonospaceFontFamily : null,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.cs,
    required this.theme,
    required this.icon,
    required this.text,
  });

  final ColorScheme cs;
  final ThemeData theme;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(kOpenHandRadius10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          kOpenHandHGap8,
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _androidReverseBasicInfoLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '基本信息',
    zhHant: '基本資訊',
    en: 'Basic info',
    fr: 'Infos de base',
    de: 'Basisinfo',
    ja: '基本情報',
  );
}

String _androidReverseCopyPackageNameLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '复制包名',
    zhHant: '複製套件名稱',
    en: 'Copy package name',
    fr: 'Copier le nom du package',
    de: 'Paketnamen kopieren',
    ja: 'パッケージ名をコピー',
  );
}

String _androidReverseCopyPidLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '复制 PID',
    zhHant: '複製 PID',
    en: 'Copy PID',
    fr: 'Copier le PID',
    de: 'PID kopieren',
    ja: 'PID をコピー',
  );
}

String _androidReverseDescriptionLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '描述',
    zhHant: '描述',
    en: 'Description',
    fr: 'Description',
    de: 'Beschreibung',
    ja: '説明',
  );
}

String _androidReverseFailedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '失败',
    zhHant: '失敗',
    en: 'failed',
    fr: 'échec',
    de: 'fehlgeschlagen',
    ja: '失敗',
  );
}

String _androidReverseForceStopLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '强制停止',
    zhHant: '強制停止',
    en: 'Force stop',
    fr: 'Forcer l’arrêt',
    de: 'Stopp erzwingen',
    ja: '強制停止',
  );
}

String _androidReverseGenerateAppReportLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '生成 APP 信息报告',
    zhHant: '產生 APP 資訊報告',
    en: 'Generate app report',
    fr: 'Générer le rapport APP',
    de: 'APP-Bericht erstellen',
    ja: 'APP レポートを生成',
  );
}

String _androidReverseLaunchAppLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '启动 APP',
    zhHant: '啟動 APP',
    en: 'Launch app',
    fr: 'Lancer l’APP',
    de: 'APP starten',
    ja: 'APP を起動',
  );
}

String _androidReverseNameLabel(BuildContext context) {
  return openHandNameLabel(context);
}

String _androidReverseNoOutputLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '(命令无输出)',
    zhHant: '（指令無輸出）',
    en: '(no output)',
    fr: '(aucune sortie)',
    de: '(keine Ausgabe)',
    ja: '（出力なし）',
  );
}

String _androidReverseNoneLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '无',
    zhHant: '無',
    en: 'None',
    fr: 'Aucune',
    de: 'Keine',
    ja: 'なし',
  );
}

String _androidReverseNotInstalledLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '未安装',
    zhHant: '未安裝',
    en: 'Not installed',
    fr: 'Non installé',
    de: 'Nicht installiert',
    ja: '未インストール',
  );
}

String _androidReverseReadArtifactsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '读取工件',
    zhHant: '讀取工件',
    en: 'Read artifacts',
    fr: 'Lire les artefacts',
    de: 'Artefakte lesen',
    ja: '成果物を読み込み',
  );
}

String _androidReverseRemotePathLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '设备路径',
    zhHant: '裝置路徑',
    en: 'remote path',
    fr: 'chemin distant',
    de: 'Remote-Pfad',
    ja: 'リモートパス',
  );
}

String _androidReverseRunningLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '执行中...',
    zhHant: '執行中...',
    en: 'Running...',
    fr: 'Exécution...',
    de: 'Wird ausgeführt...',
    ja: '実行中...',
  );
}

String _androidReverseStatusLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '状态',
    zhHant: '狀態',
    en: 'Status',
    fr: 'État',
    de: 'Status',
    ja: '状態',
  );
}

String _androidReverseUninstallLabel(BuildContext context) {
  return openHandUninstallLabel(context);
}
