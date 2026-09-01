import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:openhand/shared/util/text_normalization.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_delete.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/physical_path_safety.dart';
import '../../../shared/util/platform_shell.dart';
import '../../../shared/util/version_compare.dart';
import 'managed_service_defaults.dart';
import 'plugin_environment_probe.dart';
import 'plugin_toolchain_shell.dart';

const Duration _pluginLifecycleDefaultTimeout = Duration(minutes: 3);
const Duration _pluginLifecycleProbeTimeout = Duration(seconds: 5);
const Duration _pluginLifecycleVerifyTimeout = Duration(seconds: 8);
const Duration _fnmSetDefaultTimeout = Duration(seconds: 10);
const Duration _pluginLifecycleStreamDrainTimeout = Duration(milliseconds: 800);
const Duration _googleChromeRemovalPollInterval = Duration(milliseconds: 250);
const Duration _dockerDaemonPollInterval = Duration(seconds: 5);
const int _googleChromeRemovalMaxPollAttempts = 20;
const int _googleChromeInstallerDirectoryMaxEntries = 64;
const int _dockerDaemonMaxPollAttempts = 24;
const int _pluginLifecycleMaxCapturedLines = 500;
final RegExp _pluginLifecycleNodeVersionPattern = RegExp(
  r'(v\d+\.\d+(?:\.\d+)?)',
);
final RegExp _pluginLifecyclePlaywrightVersionPrefixPattern = RegExp(
  r'^Version\s+',
  caseSensitive: false,
);
final RegExp _pluginLifecyclePyenvVersionPathPattern = RegExp(
  r'/.pyenv/versions/([^/]+)/',
);
final RegExp _pluginLifecycleBrewPythonFormulaPathPattern = RegExp(
  r'/(python(?:@[\d.]+)?)(?:/|$)',
);

String? _homebrewStableVersionFromDecoded(Object? decoded) {
  final root = stringKeyedMapFromValue(decoded);
  final formulae = stringKeyedMapListFromValue(root['formulae']);
  if (formulae.isEmpty) return null;
  final versions = stringKeyedMapFromValue(formulae.first['versions']);
  final stable = '${versions['stable'] ?? ''}'.trim();
  return stable.isEmpty ? null : stable;
}

/// 插件生命周期操作结果。
class PluginOperationResult {
  const PluginOperationResult({
    required this.success,
    this._message,
    this.newVersion,
  });

  final bool success;
  final String? _message;
  final String? newVersion;

  String? get message => _localizedPluginLifecycleMessage(_message);
}

String? _localizedPluginLifecycleMessage(String? message) {
  if (message == null || message.trim().isEmpty) {
    return message;
  }
  final locale = Platform.localeName;
  if (locale.toLowerCase().startsWith('zh')) {
    return message;
  }

  String text({required String en, String? fr, String? de, String? ja}) {
    return openHandAmbientText(zh: message, en: en, fr: fr, de: de, ja: ja);
  }

  Match? match;
  match = RegExp(
    r'^(.+?) 已通过 (nvm|fnm|pyenv|volta|Homebrew) 安装$',
  ).firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final manager = match.group(2)!;
    return text(
      en: '$item was installed with $manager',
      fr: '$item a été installé avec $manager',
      de: '$item wurde mit $manager installiert',
      ja: '$item は $manager でインストールされました',
    );
  }
  match = RegExp(
    r'^(.+?) 已通过 (nvm|fnm|pyenv|volta|Homebrew) 更新(?:到 (.+))?$',
  ).firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final manager = match.group(2)!;
    final version = match.group(3);
    final suffix = version == null ? '' : ' to $version';
    return text(
      en: '$item was updated$suffix with $manager',
      fr: '$item a été mis à jour$suffix avec $manager',
      de: '$item wurde$suffix mit $manager aktualisiert',
      ja: '$item は $manager で更新されました${version == null ? '' : ' ($version)'}',
    );
  }
  match = RegExp(r'^(.+?) 已通过 (pyenv|Homebrew) 卸载$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final manager = match.group(2)!;
    return text(
      en: '$item was uninstalled with $manager',
      fr: '$item a été désinstallé avec $manager',
      de: '$item wurde mit $manager deinstalliert',
      ja: '$item は $manager でアンインストールされました',
    );
  }
  match = RegExp(
    r'^(nvm|fnm|pyenv|volta|Homebrew) (安装|更新|卸载)失败: (.+)$',
  ).firstMatch(message);
  if (match != null) {
    final manager = match.group(1)!;
    final action = match.group(2)!;
    final detail = match.group(3)!;
    final actionEn = switch (action) {
      '安装' => 'install',
      '更新' => 'update',
      _ => 'uninstall',
    };
    return text(
      en: '$manager $actionEn failed: $detail',
      fr: 'Échec $actionEn de $manager : $detail',
      de: '$manager $actionEn fehlgeschlagen: $detail',
      ja: '$manager の $actionEn に失敗しました: $detail',
    );
  }
  match = RegExp(r'^Homebrew (安装|更新|卸载) (.+?) 失败: (.+)$').firstMatch(message);
  if (match != null) {
    final action = match.group(1)!;
    final item = match.group(2)!;
    final detail = match.group(3)!;
    final actionEn = switch (action) {
      '安装' => 'install',
      '更新' => 'update',
      _ => 'uninstall',
    };
    return text(
      en: 'Homebrew $actionEn of $item failed: $detail',
      fr: 'Échec $actionEn de $item avec Homebrew : $detail',
      de: 'Homebrew $actionEn von $item fehlgeschlagen: $detail',
      ja: 'Homebrew による $item の $actionEn に失敗しました: $detail',
    );
  }
  match = RegExp(r'^未找到 Homebrew，无法自动(安装|更新|卸载) (.+)。$').firstMatch(message);
  if (match != null) {
    final action = match.group(1)!;
    final item = match.group(2)!;
    final actionEn = switch (action) {
      '安装' => 'install',
      '更新' => 'update',
      _ => 'uninstall',
    };
    return text(
      en: 'Homebrew was not found, so $item cannot be $actionEn automatically.',
      fr: 'Homebrew est introuvable ; $item ne peut pas être traité automatiquement.',
      de: 'Homebrew wurde nicht gefunden; $item kann nicht automatisch verarbeitet werden.',
      ja: 'Homebrew が見つからないため、$item を自動処理できません。',
    );
  }
  match = RegExp(r'^(.+?) 已安装或更新(?::|：)?(.+)?$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final path = (match.group(2) ?? '').trim();
    final suffix = path.isEmpty ? '' : ': $path';
    return text(
      en: '$item installed or updated$suffix',
      fr: '$item installé ou mis à jour$suffix',
      de: '$item installiert oder aktualisiert$suffix',
      ja: '$item をインストールまたは更新しました$suffix',
    );
  }
  match = RegExp(r'^(.+?) 已更新(?:到 (.+))?$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final version = match.group(2);
    final suffix = version == null ? '' : ' to $version';
    return text(
      en: '$item updated$suffix',
      fr: '$item mis à jour$suffix',
      de: '$item aktualisiert$suffix',
      ja: '$item を更新しました${version == null ? '' : ' ($version)'}',
    );
  }
  match = RegExp(r'^(.+?) 已卸载$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    return text(
      en: '$item uninstalled',
      fr: '$item désinstallé',
      de: '$item deinstalliert',
      ja: '$item をアンインストールしました',
    );
  }
  match = RegExp(r'^(.+?) (安装|更新|卸载|安装/启动|引导|升级)失败: (.+)$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final action = match.group(2)!;
    final detail = match.group(3)!;
    final actionEn = switch (action) {
      '安装' => 'installation',
      '更新' => 'update',
      '卸载' => 'uninstall',
      '引导' => 'bootstrap',
      '升级' => 'upgrade',
      _ => 'install/start',
    };
    return text(
      en: '$item $actionEn failed: $detail',
      fr: 'Échec $actionEn de $item : $detail',
      de: '$item $actionEn fehlgeschlagen: $detail',
      ja: '$item の $actionEn に失敗しました: $detail',
    );
  }
  match = RegExp(
    r'^(.+?) (依赖|需要) (Node\.js|npm|Python|pip)，(.+)$',
  ).firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final dependency = match.group(3)!;
    return text(
      en: '$item requires $dependency. Install $dependency first.',
      fr: '$item nécessite $dependency. Installez d’abord $dependency.',
      de: '$item benötigt $dependency. Installiere zuerst $dependency.',
      ja: '$item には $dependency が必要です。先にインストールしてください。',
    );
  }
  match = RegExp(r'^未检测到 (Python|npm)，无法(.+?) (.+)。$').firstMatch(message);
  if (match != null) {
    final dependency = match.group(1)!;
    final action = match.group(2)!;
    final item = match.group(3)!;
    return text(
      en: '$dependency was not detected, so $item cannot be $action.',
      fr: '$dependency est introuvable ; $item ne peut pas être traité.',
      de: '$dependency wurde nicht gefunden; $item kann nicht verarbeitet werden.',
      ja: '$dependency が見つからないため、$item を処理できません。',
    );
  }
  match = RegExp(r'^(.+?) 已就绪$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    return text(
      en: '$item is ready',
      fr: '$item est prêt',
      de: '$item ist bereit',
      ja: '$item の準備ができました',
    );
  }
  match = RegExp(r'^(.+?) 后验证失败$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    return text(
      en: '$item verification failed',
      fr: 'La vérification de $item a échoué',
      de: '$item-Verifizierung fehlgeschlagen',
      ja: '$item の検証に失敗しました',
    );
  }
  match = RegExp(r'^(.+?) 未检测到可执行命令，无需卸载。$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    return text(
      en: '$item has no executable command detected; uninstall is not needed.',
      fr: 'Aucune commande exécutable détectée pour $item ; désinstallation inutile.',
      de: 'Für $item wurde kein ausführbarer Befehl gefunden; Deinstallation ist nicht nötig.',
      ja: '$item の実行コマンドが見つからないため、アンインストールは不要です。',
    );
  }
  match = RegExp(r'^(.+?) 已启动，数据目录：(.+)$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final dir = match.group(2)!;
    return text(
      en: '$item started. Data directory: $dir',
      fr: '$item a démarré. Dossier de données : $dir',
      de: '$item gestartet. Datenverzeichnis: $dir',
      ja: '$item を起動しました。データディレクトリ: $dir',
    );
  }
  match = RegExp(r'^(.+?) 容器已移除，数据目录已保留：(.+)$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final dir = match.group(2)!;
    return text(
      en: '$item container removed. Data directory kept: $dir',
      fr: 'Conteneur $item supprimé. Dossier de données conservé : $dir',
      de: '$item-Container entfernt. Datenverzeichnis behalten: $dir',
      ja: '$item コンテナを削除しました。データディレクトリは保持されています: $dir',
    );
  }
  match = RegExp(r'^(更新|卸载)失败: (.+)$').firstMatch(message);
  if (match != null) {
    final action = match.group(1)!;
    final detail = match.group(2)!;
    final actionEn = action == '更新' ? 'Update' : 'Uninstall';
    return text(
      en: '$actionEn failed: $detail',
      fr: 'Échec de l’opération : $detail',
      de: '$actionEn fehlgeschlagen: $detail',
      ja: '$actionEn に失敗しました: $detail',
    );
  }

  match = RegExp(r'^(.+?) 安装后验证失败：未找到可执行命令。$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    return text(
      en: 'Verification after installing $item failed: executable not found.',
      fr: "Échec de la vérification après l'installation de $item : exécutable introuvable.",
      de: 'Prüfung nach der Installation von $item fehlgeschlagen: Programm nicht gefunden.',
      ja: '$item のインストール後の検証に失敗しました：実行ファイルが見つかりません。',
    );
  }
  match = RegExp(
    r'^Playwright (安装|更新)后(未找到 npm 全局安装目标|版本校验失败|验证失败)$',
  ).firstMatch(message);
  if (match != null) {
    final actionEn = match.group(1) == '安装' ? 'install' : 'update';
    final reason = match.group(2)!;
    final reasonEn = switch (reason) {
      '未找到 npm 全局安装目标' => 'the npm global install target was not found',
      '版本校验失败' => 'the version check failed',
      _ => 'verification failed',
    };
    final reasonFr = switch (reason) {
      '未找到 npm 全局安装目标' => "la cible d'installation globale npm est introuvable",
      '版本校验失败' => 'la vérification de version a échoué',
      _ => 'la vérification a échoué',
    };
    final reasonDe = switch (reason) {
      '未找到 npm 全局安装目标' =>
        'das globale npm-Installationsziel wurde nicht gefunden',
      '版本校验失败' => 'die Versionsprüfung ist fehlgeschlagen',
      _ => 'die Prüfung ist fehlgeschlagen',
    };
    final reasonJa = switch (reason) {
      '未找到 npm 全局安装目标' => 'npm のグローバルインストール先が見つかりませんでした',
      '版本校验失败' => 'バージョン検証に失敗しました',
      _ => '検証に失敗しました',
    };
    return text(
      en: 'After the Playwright $actionEn, $reasonEn.',
      fr: "Après l'$actionEn de Playwright, $reasonFr.",
      de: 'Nach dem Playwright-$actionEn: $reasonDe.',
      ja: 'Playwright の$actionEn後、$reasonJa。',
    );
  }
  match = RegExp(r'^Playwright (安装|更新)失败: (.+)$').firstMatch(message);
  if (match != null) {
    final actionEn = match.group(1) == '安装' ? 'install' : 'update';
    final detail = match.group(2)!;
    return text(
      en: 'Playwright $actionEn failed: $detail',
      fr: "Échec de l'$actionEn de Playwright : $detail",
      de: 'Playwright-$actionEn fehlgeschlagen: $detail',
      ja: 'Playwright の$actionEnに失敗しました: $detail',
    );
  }
  match = RegExp(r'^Playwright 已(更新到|安装) (.+)$').firstMatch(message);
  if (match != null) {
    final updated = match.group(1) == '更新到';
    final version = match.group(2)!;
    return text(
      en: updated
          ? 'Playwright updated to $version'
          : 'Playwright $version installed',
      fr: updated
          ? 'Playwright mis à jour vers $version'
          : 'Playwright $version installé',
      de: updated
          ? 'Playwright auf $version aktualisiert'
          : 'Playwright $version installiert',
      ja: updated
          ? 'Playwright を $version に更新しました'
          : 'Playwright $version をインストールしました',
    );
  }
  match = RegExp(r'^Python 已是最新版本 (.+)$').firstMatch(message);
  if (match != null) {
    final version = match.group(1)!;
    return text(
      en: 'Python is already up to date at $version',
      fr: 'Python est déjà à jour en $version',
      de: 'Python ist mit $version bereits aktuell',
      ja: 'Python はすでに最新版 $version です',
    );
  }
  match = RegExp(r'^(npm|pip) (安装|卸载) (.+?) 失败: (.+)$').firstMatch(message);
  if (match != null) {
    final manager = match.group(1)!;
    final actionEn = match.group(2) == '安装' ? 'install' : 'uninstall';
    final item = match.group(3)!;
    final detail = match.group(4)!;
    return text(
      en: '$manager $actionEn of $item failed: $detail',
      fr: 'Échec $actionEn de $item avec $manager : $detail',
      de: '$manager $actionEn von $item fehlgeschlagen: $detail',
      ja: '$manager による $item の $actionEn に失敗しました: $detail',
    );
  }
  switch (message) {
    case 'Docker Desktop 已卸载。':
      return text(
        en: 'Docker Desktop was uninstalled.',
        fr: 'Docker Desktop a été désinstallé.',
        de: 'Docker Desktop wurde deinstalliert.',
        ja: 'Docker Desktop をアンインストールしました。',
      );
    case 'Qdrant 依赖 Docker，请先安装 Docker。':
      return text(
        en: 'Qdrant needs Docker. Install Docker first.',
        fr: "Qdrant nécessite Docker. Installez d'abord Docker.",
        de: 'Qdrant benötigt Docker. Installiere zuerst Docker.',
        ja: 'Qdrant には Docker が必要です。先に Docker をインストールしてください。',
      );
    case '未检测到可用的 Python 运行时，请先安装 Python。':
    case '未检测到可用的 Python 运行时。':
      return text(
        en: 'No usable Python runtime was detected. Install Python first.',
        fr: 'Aucun runtime Python utilisable n’a été détecté. Installez Python d’abord.',
        de: 'Keine nutzbare Python-Laufzeit gefunden. Installiere zuerst Python.',
        ja: '利用可能な Python ランタイムが見つかりません。先に Python をインストールしてください。',
      );
    case '当前 pip 由 Homebrew Python 管理，请通过 Homebrew 更新对应 Python。':
      return text(
        en: 'The current pip is managed by Homebrew Python. Update the matching Python via Homebrew.',
        fr: 'Le pip actuel est géré par Homebrew Python. Mettez à jour le Python correspondant via Homebrew.',
        de: 'Das aktuelle pip wird von Homebrew Python verwaltet. Aktualisiere das passende Python über Homebrew.',
        ja: '現在の pip は Homebrew Python によって管理されています。対応する Python を Homebrew で更新してください。',
      );
    case 'pip 安装后验证失败':
      return text(
        en: 'pip verification failed after installation',
        fr: 'La vérification de pip a échoué après installation',
        de: 'pip-Verifizierung nach Installation fehlgeschlagen',
        ja: 'pip インストール後の検証に失敗しました',
      );
    case 'pip 升级后验证失败':
      return text(
        en: 'pip verification failed after upgrade',
        fr: 'La vérification de pip a échoué après la mise à niveau',
        de: 'pip-Verifizierung nach Upgrade fehlgeschlagen',
        ja: 'pip アップグレード後の検証に失敗しました',
      );
    case '无法识别当前 pyenv Python 版本。':
      return text(
        en: 'Could not identify the current pyenv Python version.',
        fr: 'Impossible d’identifier la version Python pyenv actuelle.',
        de: 'Aktuelle pyenv-Python-Version konnte nicht erkannt werden.',
        ja: '現在の pyenv Python バージョンを識別できません。',
      );
    case '无法查询 pyenv 的最新 Python 版本。':
      return text(
        en: 'Could not query the latest Python version from pyenv.',
        fr: 'Impossible de consulter la dernière version Python via pyenv.',
        de: 'Neueste Python-Version konnte über pyenv nicht abgefragt werden.',
        ja: 'pyenv から最新の Python バージョンを取得できません。',
      );
    case '当前 Python 来自系统环境，暂不支持自动升级，请手动维护。':
      return text(
        en: 'The current Python comes from the system environment. Automatic upgrade is not supported; maintain it manually.',
        fr: 'Le Python actuel vient de l’environnement système. Mise à niveau automatique non prise en charge.',
        de: 'Das aktuelle Python stammt aus der Systemumgebung. Automatisches Upgrade wird nicht unterstützt.',
        ja: '現在の Python はシステム環境由来です。自動アップグレードには対応していません。',
      );
    case '当前 Python 安装来源未知，暂不支持自动升级，请手动维护。':
      return text(
        en: 'The current Python installation source is unknown. Automatic upgrade is not supported; maintain it manually.',
        fr: 'La source d’installation Python est inconnue. Mise à niveau automatique non prise en charge.',
        de: 'Die Python-Installationsquelle ist unbekannt. Automatisches Upgrade wird nicht unterstützt.',
        ja: '現在の Python のインストール元が不明です。自動アップグレードには対応していません。',
      );
    case '当前 Python 来自系统环境，暂不支持自动卸载。':
      return text(
        en: 'The current Python comes from the system environment and cannot be uninstalled automatically.',
        fr: 'Le Python actuel vient de l’environnement système et ne peut pas être désinstallé automatiquement.',
        de: 'Das aktuelle Python stammt aus der Systemumgebung und kann nicht automatisch deinstalliert werden.',
        ja: '現在の Python はシステム環境由来のため、自動アンインストールできません。',
      );
    case '当前 Python 安装来源未知，暂不支持自动卸载。':
      return text(
        en: 'The current Python installation source is unknown and cannot be uninstalled automatically.',
        fr: 'La source d’installation Python est inconnue ; désinstallation automatique non prise en charge.',
        de: 'Die Python-Installationsquelle ist unbekannt; automatische Deinstallation wird nicht unterstützt.',
        ja: '現在の Python のインストール元が不明なため、自動アンインストールできません。',
      );
    case 'Playwright 依赖 Node.js，请先安装 Node.js':
    case 'Playwright 依赖 Node.js，请先卸载 Playwright':
      return text(
        en: 'Playwright requires Node.js. Install Node.js first.',
        fr: 'Playwright nécessite Node.js. Installez d’abord Node.js.',
        de: 'Playwright benötigt Node.js. Installiere zuerst Node.js.',
        ja: 'Playwright には Node.js が必要です。先に Node.js をインストールしてください。',
      );
    case 'Playwright 安装后验证失败':
      return text(
        en: 'Playwright verification failed after installation',
        fr: 'La vérification de Playwright a échoué après installation',
        de: 'Playwright-Verifizierung nach Installation fehlgeschlagen',
        ja: 'Playwright インストール後の検証に失敗しました',
      );
    case '当前平台不支持自动安装 Docker。':
      return text(
        en: 'Automatic Docker installation is not supported on this platform.',
        fr: 'L’installation automatique de Docker n’est pas prise en charge sur cette plateforme.',
        de: 'Automatische Docker-Installation wird auf dieser Plattform nicht unterstützt.',
        ja: 'このプラットフォームでは Docker の自動インストールに対応していません。',
      );
    case 'Docker daemon 未运行，请先启动 Docker。':
      return text(
        en: 'Docker daemon is not running. Start Docker first.',
        fr: 'Le daemon Docker ne fonctionne pas. Démarrez Docker d’abord.',
        de: 'Der Docker-Daemon läuft nicht. Starte zuerst Docker.',
        ja: 'Docker daemon が実行されていません。先に Docker を起動してください。',
      );
    case 'Docker CLI 与 daemon 已就绪。':
      return text(
        en: 'Docker CLI and daemon are ready.',
        fr: 'Docker CLI et daemon sont prêts.',
        de: 'Docker CLI und Daemon sind bereit.',
        ja: 'Docker CLI と daemon の準備ができました。',
      );
    case 'Docker Desktop 已安装。首次使用可能需要手动打开并完成授权。':
      return text(
        en: 'Docker Desktop is installed. First use may require opening it manually and completing authorization.',
        fr: 'Docker Desktop est installé. La première utilisation peut nécessiter une ouverture manuelle et une autorisation.',
        de: 'Docker Desktop ist installiert. Beim ersten Start kann manuelles Öffnen und Autorisierung nötig sein.',
        ja: 'Docker Desktop はインストール済みです。初回利用時は手動で開いて認証を完了する必要があります。',
      );
    case 'Docker Desktop 已启动，daemon 可用。':
      return text(
        en: 'Docker Desktop started and the daemon is available.',
        fr: 'Docker Desktop a démarré et le daemon est disponible.',
        de: 'Docker Desktop wurde gestartet und der Daemon ist verfügbar.',
        ja: 'Docker Desktop が起動し、daemon を利用できます。',
      );
    case 'docker CLI 已安装，但 daemon 未运行。请启动 Docker Desktop 后重新扫描。':
      return text(
        en: 'docker CLI is installed, but the daemon is not running. Start Docker Desktop and rescan.',
        fr: 'docker CLI est installé, mais le daemon ne fonctionne pas. Démarrez Docker Desktop puis relancez le scan.',
        de: 'docker CLI ist installiert, aber der Daemon läuft nicht. Starte Docker Desktop und scanne erneut.',
        ja: 'docker CLI はインストール済みですが daemon が実行されていません。Docker Desktop を起動して再スキャンしてください。',
      );
    case 'Docker Desktop 已更新或已经是最新版本。':
      return text(
        en: 'Docker Desktop was updated or is already current.',
        fr: 'Docker Desktop a été mis à jour ou est déjà à jour.',
        de: 'Docker Desktop wurde aktualisiert oder ist bereits aktuell.',
        ja: 'Docker Desktop は更新済み、またはすでに最新です。',
      );
    case '无法自动更新 Docker。请通过 Docker Desktop 或系统包管理器更新。':
      return text(
        en: 'Docker cannot be updated automatically. Update it through Docker Desktop or your system package manager.',
        fr: 'Docker ne peut pas être mis à jour automatiquement. Utilisez Docker Desktop ou le gestionnaire système.',
        de: 'Docker kann nicht automatisch aktualisiert werden. Nutze Docker Desktop oder den Paketmanager.',
        ja: 'Docker を自動更新できません。Docker Desktop またはシステムのパッケージマネージャーで更新してください。',
      );
    case '无法自动卸载 Docker。请通过 Docker Desktop 或系统包管理器卸载。':
      return text(
        en: 'Docker cannot be uninstalled automatically. Use Docker Desktop or your system package manager.',
        fr: 'Docker ne peut pas être désinstallé automatiquement. Utilisez Docker Desktop ou le gestionnaire système.',
        de: 'Docker kann nicht automatisch deinstalliert werden. Nutze Docker Desktop oder den Paketmanager.',
        ja: 'Docker を自動アンインストールできません。Docker Desktop またはシステムのパッケージマネージャーを使用してください。',
      );
    case 'docker CLI 不存在，Qdrant 容器无需卸载。':
      return text(
        en: 'docker CLI is not present. No Qdrant container uninstall is needed.',
        fr: 'docker CLI est absent. Aucun conteneur Qdrant à désinstaller.',
        de: 'docker CLI ist nicht vorhanden. Qdrant-Container muss nicht deinstalliert werden.',
        ja: 'docker CLI が存在しないため、Qdrant コンテナのアンインストールは不要です。',
      );
    case 'Docker daemon 未运行，无法安全检查并卸载 Qdrant 容器。':
      return text(
        en: 'Docker daemon is not running, so the Qdrant container cannot be safely checked and removed.',
        fr: 'Le daemon Docker ne fonctionne pas ; le conteneur Qdrant ne peut pas être vérifié et supprimé en sécurité.',
        de: 'Der Docker-Daemon läuft nicht; der Qdrant-Container kann nicht sicher geprüft und entfernt werden.',
        ja: 'Docker daemon が実行されていないため、Qdrant コンテナを安全に確認して削除できません。',
      );
    case 'Qdrant 镜像已更新，容器已安全重建并保留数据目录。':
      return text(
        en: 'Qdrant image updated. The container was safely rebuilt and the data directory was kept.',
        fr: 'Image Qdrant mise à jour. Le conteneur a été reconstruit et les données conservées.',
        de: 'Qdrant-Image aktualisiert. Container sicher neu erstellt, Datenverzeichnis behalten.',
        ja: 'Qdrant イメージを更新しました。コンテナは安全に再作成され、データディレクトリは保持されています。',
      );
    case '未找到可用的包管理器来卸载 Node.js，请手动卸载':
      return text(
        en: 'No package manager is available to uninstall Node.js. Uninstall it manually.',
        fr: 'Aucun gestionnaire de paquets disponible pour désinstaller Node.js. Désinstallez-le manuellement.',
        de: 'Kein Paketmanager zum Deinstallieren von Node.js verfügbar. Bitte manuell entfernen.',
        ja: 'Node.js をアンインストールできるパッケージマネージャーがありません。手動でアンインストールしてください。',
      );
    case 'pip 不支持卸载，仅支持安装与升级。':
      return text(
        en: 'pip cannot be uninstalled here. Only install and update are supported.',
        fr: 'pip ne peut pas être désinstallé ici. Seules installation et mise à jour sont prises en charge.',
        de: 'pip kann hier nicht deinstalliert werden. Nur Installation und Update werden unterstützt.',
        ja: 'ここでは pip をアンインストールできません。インストールと更新のみ対応しています。',
      );
  }
  return message;
}

/// 管理插件的安装、更新、卸载操作。
///
/// 处理依赖关系：
/// - 安装 Playwright 前自动检查 NodeJS 是否已安装
/// - 卸载 NodeJS 前检查 Playwright 是否仍在使用
/// - Python / pip 仅自动管理 pyenv 与 Homebrew 来源
class PluginLifecycleService {
  // ── 插件操作时长预算 ───────────────────────────────────────────────────
  // 按下载与构建体量分档，同档共用一个常量：调整某类组件的预算只需改一处，
  // 不必在几十个调用点里逐个找同一个字面量。

  /// 包管理器的安装 / 更新 / 卸载：brew、pip、Python 包与 Docker 容器操作。
  static const Duration _packageOperationTimeout = Duration(minutes: 8);

  /// Node.js 与 Playwright 工具链：下载量中等，短于常规包操作。
  static const Duration _nodeToolchainTimeout = Duration(minutes: 5);

  /// npm 全局包：需要落地 node_modules，略长于工具链本体。
  static const Duration _npmGlobalPackageTimeout = Duration(minutes: 6);

  /// 需要源码构建的 Python 组件：编译耗时明显高于安装预编译包。
  static const Duration _pythonBuildTimeout = Duration(minutes: 12);

  /// Docker Desktop：安装包体量最大，单独给最长预算。
  static const Duration _dockerDesktopTimeout = Duration(minutes: 15);

  static const String _qdrantContainerName =
      ManagedServiceDefaults.qdrantContainerName;
  static const String _qdrantImage = ManagedServiceDefaults.qdrantImage;
  static const int _qdrantRestPort = ManagedServiceDefaults.qdrantRestPort;
  static const int _qdrantGrpcPort = ManagedServiceDefaults.qdrantGrpcPort;

  static Map<String, String> _npmGlobalPackageEnv() {
    final proxy = pluginProxyEnvironment();
    final env = <String, String>{
      ...proxy,
      'PIP_DISABLE_PIP_VERSION_CHECK': '1',
      'PIP_RETRIES': '2',
      'PIP_DEFAULT_TIMEOUT': '60',
      'npm_config_fetch_retries': '2',
      'npm_config_fetch_retry_maxtimeout': '30000',
      'npm_config_fetch_timeout': '120000',
    };

    final httpProxy = proxy['HTTP_PROXY'] ?? proxy['http_proxy'];
    final httpsProxy = proxy['HTTPS_PROXY'] ?? proxy['https_proxy'];
    final noProxy = proxy['NO_PROXY'] ?? proxy['no_proxy'];
    if (httpProxy != null && httpProxy.isNotEmpty) {
      env['npm_config_proxy'] = httpProxy;
    }
    if (httpsProxy != null && httpsProxy.isNotEmpty) {
      env['npm_config_https_proxy'] = httpsProxy;
    }
    if (noProxy != null && noProxy.isNotEmpty) {
      env['npm_config_noproxy'] = noProxy;
    }

    return env;
  }

  Future<ProcessResult> _runManagedToolchainCommand(
    String executable,
    List<String> arguments, {
    Duration timeout = _pluginLifecycleVerifyTimeout,
    String? tag,
    Map<String, String>? environment,
  }) {
    return runPluginToolchainCommandOrFailed(
      executable,
      arguments,
      timeout: timeout,
      tag: tag ?? 'plugin_lifecycle.command.$executable',
      environment: environment ?? pluginProxyEnvironment(),
    );
  }

  /// fnm 安装 LTS 后需要显式设为默认版本，否则新开的 shell 仍指向旧版本。
  Future<void> _promoteFnmLtsDefault() {
    return _runManagedToolchainCommand('fnm', const [
      'default',
      'lts-latest',
    ], timeout: _fnmSetDefaultTimeout);
  }

  /// 用 `node --version` 校验工具链命令是否真的换上了新版本。
  ///
  /// 命令失败或版本号为空都视为未生效，返回 null 交由调用方走失败分支，
  /// 避免把 "Node.js  安装成功" 这种缺版本号的文案报给用户。
  Future<PluginOperationResult?> _verifyInstalledNodeVersion({
    required String Function(String version) progressMessage,
    required String Function(String version) resultMessage,
    void Function(String line)? onProgress,
  }) async {
    final verify = await _runManagedToolchainCommand('node', const [
      '--version',
    ]);
    if (verify.exitCode != 0) return null;
    final version = verify.stdout.toString().trim();
    if (version.isEmpty) return null;
    onProgress?.call(progressMessage(version));
    return PluginOperationResult(
      success: true,
      message: resultMessage(version),
      newVersion: version,
    );
  }

  Future<_SimpleProcessResult> _runManagedToolchainCommandWithProgress(
    String executable,
    List<String> arguments, {
    void Function(String line)? onProgress,
    Duration timeout = _pluginLifecycleDefaultTimeout,
    Map<String, String>? environment,
  }) {
    return _runWithProgress(
      pluginShellExecutable(),
      ['-c', pluginToolchainManagedCommandScript(executable, arguments)],
      onProgress: onProgress,
      timeout: timeout,
      environment: environment ?? pluginProxyEnvironment(),
    );
  }

  Future<String?> _resolveManagedToolchainCommandPath(
    String executable, {
    Map<String, String>? environment,
  }) async {
    final result = await runTrackedProcessOrFailed(
      pluginShellExecutable(),
      [
        '-c',
        pluginToolchainCommandPathScript(
          executable,
          includeNpmGlobalBinFallback: true,
        ),
      ],
      timeout: _pluginLifecycleProbeTimeout,
      tag: 'plugin_lifecycle.command_path.$executable',
      environment: environment ?? pluginProxyEnvironment(),
    );
    if (result.exitCode != 0) return null;
    return extractPluginAbsolutePath(result.stdout.toString());
  }

  Future<_SimpleProcessResult> _runDingtalkNpmCommandWithProgress(
    List<String> arguments, {
    void Function(String line)? onProgress,
    Duration timeout = _npmGlobalPackageTimeout,
  }) {
    if (!Platform.isWindows) {
      return _runManagedToolchainCommandWithProgress(
        'npm',
        arguments,
        onProgress: onProgress,
        timeout: timeout,
        environment: _npmGlobalPackageEnv(),
      );
    }
    return _runWithProgress(
      'npm.cmd',
      arguments,
      onProgress: onProgress,
      timeout: timeout,
      environment: _npmGlobalPackageEnv(),
    );
  }

  Future<_SimpleProcessResult> _runDingtalkCommandWithProgress(
    List<String> arguments, {
    void Function(String line)? onProgress,
    Duration timeout = _packageOperationTimeout,
  }) async {
    final executable = await resolvePluginDingtalkWorkspaceCliExecutable(
      tag: 'plugin_lifecycle.dingtalk_workspace_cli_path',
    );
    if (executable == null) {
      return const _SimpleProcessResult(
        exitCode: -1,
        stdout: '',
        stderr: '未找到 dws 可执行文件。',
      );
    }
    return _runWithProgress(
      executable,
      arguments,
      onProgress: onProgress,
      timeout: timeout,
      environment: pluginProxyEnvironment(),
    );
  }

  Future<void> _removeDingtalkWorkspaceCliSkills(
    void Function(String line)? onProgress,
  ) async {
    final home = OpenHandPaths.homeDirectoryPath();
    const relativeSkillDirectories = <String>[
      '.agents/skills/dws',
      '.claude/skills/dws',
      '.cursor/skills/dws',
      '.qoder/skills/dws',
      '.qoderwork/skills/dws',
      '.gemini/skills/dws',
      '.codex/skills/dws',
      '.github/skills/dws',
      '.windsurf/skills/dws',
      '.augment/skills/dws',
      '.cline/skills/dws',
      '.amp/skills/dws',
      '.kiro/skills/dws',
      '.trae/skills/dws',
      '.openclaw/skills/dws',
      '.hermes/skills/dws',
      '.dws/skills/dws',
    ];
    for (final relativePath in relativeSkillDirectories) {
      final target = p.joinAll(<String>[home, ...relativePath.split('/')]);
      try {
        await deletePathBounded(
          target,
          allowedRoot: home,
          policy: const BoundedDeletePolicy(
            maxEntries: 20000,
            maxDepth: 32,
            totalTimeout: Duration(seconds: 12),
          ),
        );
      } catch (error, stack) {
        silentLog('plugin_lifecycle', '清理钉钉 CLI 技能目录', error, stack);
        onProgress?.call('技能目录清理失败: $target');
      }
    }
  }

  Future<PluginNpmPackageInstallation?> _resolveGlobalNpmPackage(
    String packageName,
  ) async {
    final rootResult = await _runManagedToolchainCommand('npm', const [
      'root',
      '-g',
    ]);
    return resolvePluginGlobalNpmPackage(
      exitCode: rootResult.exitCode,
      stdout: rootResult.stdout.toString(),
      packageName: packageName,
    );
  }

  Future<bool> _isExecutableAvailable(String executable) async {
    final result = await runTrackedProcessOrFailed(
      pluginShellExecutable(),
      ['-c', pluginToolchainExecutableAvailabilityScript(executable)],
      timeout: _pluginLifecycleProbeTimeout,
      tag: 'plugin_lifecycle.command_probe.$executable',
      environment: pluginProxyEnvironment(),
    );
    return result.exitCode == 0;
  }

  Future<bool> _isDockerDaemonAvailable() async {
    final result = await runPluginToolchainCommandOrFailed(
      'docker',
      ['info'],
      timeout: _pluginLifecycleVerifyTimeout,
      tag: 'plugin_lifecycle.docker_info',
      environment: pluginProxyEnvironment(),
    );
    return result.exitCode == 0;
  }

  String _qdrantDataDirectory() {
    return p.join(
      OpenHandPaths.defaultRootDirectoryPath(),
      'knowledge',
      'qdrant',
    );
  }

  /// 校验既有 Qdrant 容器确由 OpenHand 托管，不是则以 3 退出。
  ///
  /// 启动与更新两条脚本共用。片段停在 `fi` 之前，调用方接上各自的后续分支：
  /// 启动走 `docker start`，更新走 `docker stop` + `docker rm`。
  String _qdrantManagedContainerGuard() {
    final name = posixShellQuote(_qdrantContainerName);
    return '''
if docker inspect $name >/dev/null 2>&1; then
  LABEL="\$(docker inspect -f '{{ index .Config.Labels "openhand.managed" }}' $name 2>/dev/null || true)"
  if [ "\$LABEL" != "true" ]; then
    echo "检测到同名但非 OpenHand 托管的容器：$_qdrantContainerName" >&2
    exit 3
  fi''';
  }

  /// 创建 Qdrant 容器的 `docker run`：端口、标签与挂载点在此单点维护。
  ///
  /// [indent] 为整条命令的缩进空格数，用于嵌入不同层级的 shell 分支。
  String _qdrantDockerRunCommand(String dataDir, {required int indent}) {
    final head = ' ' * indent;
    final pad = ' ' * (indent + 2);
    return '''
${head}docker run -d \\
$pad--name ${posixShellQuote(_qdrantContainerName)} \\
$pad--label openhand.managed=true \\
$pad--label com.openhand.managed=true \\
$pad--restart unless-stopped \\
$pad-p $_qdrantRestPort:6333 \\
$pad-p $_qdrantGrpcPort:6334 \\
$pad-v ${posixShellQuote(dataDir)}:/qdrant/storage \\
$pad${posixShellQuote(_qdrantImage)}''';
  }

  /// 轮询 REST 端点直到 Qdrant 就绪，30 秒内未就绪则以 4 退出。
  String _qdrantHealthWaitScript() {
    return '''
for i in \$(seq 1 30); do
  if curl -fsS http://127.0.0.1:$_qdrantRestPort/ >/dev/null 2>&1; then
    docker ps --filter name=^/$_qdrantContainerName\$ --format '容器={{.ID}} 镜像={{.Image}} 状态={{.Status}}'
    exit 0
  fi
  sleep 1
done
echo "Qdrant 健康检查端点未就绪" >&2
exit 4''';
  }

  String _managedDatabaseDataDirectory(String service) {
    return p.join(
      OpenHandPaths.defaultRootDirectoryPath(),
      'services',
      service,
    );
  }

  String _managedDatabaseGuard(String containerName) {
    final name = posixShellQuote(containerName);
    return '''
if docker inspect $name >/dev/null 2>&1; then
  LABEL="\$(docker inspect -f '{{ index .Config.Labels "openhand.managed" }}' $name 2>/dev/null || true)"
  if [ "\$LABEL" != "true" ]; then
    echo "检测到同名但非 OpenHand 托管的容器：$containerName" >&2
    exit 3
  fi
fi''';
  }

  String _managedDatabaseRunCommand({
    required String containerName,
    required String image,
    required int port,
    required String dataDir,
    required String dataDestination,
    List<String> dockerArguments = const <String>[],
    List<String> containerArguments = const <String>[],
  }) {
    final args = <String>[
      'docker run -d',
      '--name ${posixShellQuote(containerName)}',
      '--label openhand.managed=true',
      '--label com.openhand.managed=true',
      '--restart unless-stopped',
      '-p 127.0.0.1:$port:$port',
      '-v ${posixShellQuote(dataDir)}:${posixShellQuote(dataDestination)}',
      ...dockerArguments.map(posixShellQuote),
      posixShellQuote(image),
      ...containerArguments.map(posixShellQuote),
    ];
    return args.join(' ${String.fromCharCode(92)}\n  ');
  }

  String _managedDatabaseHealthWaitScript({
    required String containerName,
    required String healthCommand,
    required String label,
  }) {
    final name = posixShellQuote(containerName);
    final command = posixShellQuote(healthCommand);
    return '''
for i in \$(seq 1 30); do
  if docker exec $name sh -c $command >/dev/null 2>&1; then
    echo "$label 已就绪"
    exit 0
  fi
  sleep 1
done
echo "$label 健康检查超时" >&2
exit 4''';
  }

  /// nvm 是 shell 函数而非可执行文件，需要先 source 初始化脚本。
  static String _nvmSourcePrefix() {
    final nvmDirectory = posixShellQuote(pluginNvmDirectoryPath());
    return '''
export NVM_DIR=$nvmDirectory
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
''';
  }

  static String _pythonShellPrefix() {
    final pyenvRoot = posixShellQuote(pluginPyenvRootDirectoryPath());
    return '''
export PYENV_ROOT=$pyenvRoot
export PATH="\$PYENV_ROOT/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH"
if command -v pyenv >/dev/null 2>&1; then
  eval "\$(pyenv init -)"
fi
''';
  }

  Future<_SimpleProcessResult> _runNvmCommand(
    String nvmCommand, {
    void Function(String line)? onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) {
    final script = '${_nvmSourcePrefix()}$nvmCommand';
    return _runWithProgress(
      pluginShellExecutable(),
      ['-c', script],
      onProgress: onProgress,
      timeout: timeout,
      environment: pluginProxyEnvironment(),
    );
  }

  Future<_SimpleProcessResult> _runPythonShellCommand(
    String command, {
    void Function(String line)? onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) {
    final script = '${_pythonShellPrefix()}$command';
    return _runWithProgress(
      pluginShellExecutable(),
      ['-c', script],
      onProgress: onProgress,
      timeout: timeout,
      environment: pluginProxyEnvironment(),
    );
  }

  Future<_SimpleProcessResult> _runBoundPythonCommand(
    String executable,
    List<String> arguments, {
    void Function(String line)? onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) {
    return _runWithProgress(
      executable,
      arguments,
      onProgress: onProgress,
      timeout: timeout,
      environment: pluginProxyEnvironment(),
    );
  }

  Future<bool> _isNvmAvailable() async {
    final nvmSh = File(p.join(pluginNvmDirectoryPath(), 'nvm.sh'));
    return isRegularFilePath(nvmSh.path, followLinks: true);
  }

  Future<bool> _isPyenvAvailable() async {
    if (await pluginPyenvInstallationExists()) return true;
    final result = await runTrackedProcessOrFailed(
      pluginShellExecutable(),
      ['-c', '${_pythonShellPrefix()}command -v pyenv'],
      timeout: _pluginLifecycleProbeTimeout,
      tag: 'plugin_lifecycle.pyenv_check',
    );
    return result.exitCode == 0;
  }

  Future<_PythonRuntimeContext?> _detectPythonRuntimeContext() async {
    final pyenvContext = await _detectPyenvContext();
    if (pyenvContext != null) return pyenvContext;
    final brewContext = await _detectBrewPythonContext();
    if (brewContext != null) return brewContext;
    final pythonPath = await _resolveActivePythonPath();
    if (pythonPath == null) return null;
    return _PythonRuntimeContext(
      source: pluginLooksLikeSystemPythonPath(pythonPath)
          ? _PythonRuntimeSource.system
          : _PythonRuntimeSource.unknown,
      executablePath: pythonPath,
      version: await _readPythonVersion(pythonPath),
    );
  }

  Future<_PythonRuntimeContext?> _detectPyenvContext() async {
    if (!await _isPyenvAvailable()) return null;
    final versionNameResult = await runTrackedProcessOrFailed(
      pluginShellExecutable(),
      ['-c', '${_pythonShellPrefix()}pyenv version-name'],
      timeout: _pluginLifecycleProbeTimeout,
      tag: 'plugin_lifecycle.pyenv_version_name',
    );
    final selected = versionNameResult.exitCode == 0
        ? versionNameResult.stdout
              .toString()
              .trim()
              .split(kInlineWhitespacePattern)
              .first
        : null;
    final executable = await _resolvePyenvPythonPath();
    if (executable == null) return null;
    final managedPyenvVersion =
        selected != null && isStrictSemanticVersionText(selected)
        ? selected
        : _extractPyenvVersionFromPath(executable);
    if (managedPyenvVersion == null) return null;
    final version = await _readPythonVersion(executable);
    return _PythonRuntimeContext(
      source: _PythonRuntimeSource.pyenv,
      executablePath: executable,
      version: version,
      pyenvVersion: managedPyenvVersion,
    );
  }

  Future<_PythonRuntimeContext?> _detectBrewPythonContext() async {
    final executable = await _resolveActivePythonPath();
    if (executable == null || !pluginLooksLikeHomebrewPythonPath(executable)) {
      return null;
    }
    final version = await _readPythonVersion(executable);
    return _PythonRuntimeContext(
      source: _PythonRuntimeSource.homebrew,
      executablePath: executable,
      version: version,
      brewFormula: _extractBrewPythonFormulaFromPath(executable) ?? 'python',
    );
  }

  Future<String?> _resolveActivePythonPath() async {
    final result = await runTrackedProcessOrFailed(
      pluginShellExecutable(),
      ['-c', '${_pythonShellPrefix()}command -v python3 || command -v python'],
      timeout: _pluginLifecycleProbeTimeout,
      tag: 'plugin_lifecycle.python_path',
    );
    if (result.exitCode != 0) return null;
    for (final line in result.stdout.toString().split('\n').reversed) {
      final trimmed = line.trim();
      if (trimmed.startsWith('/')) return trimmed;
    }
    return null;
  }

  Future<String?> _resolvePyenvPythonPath() async {
    for (final command in const ['python3', 'python']) {
      final result = await runTrackedProcessOrFailed(
        pluginShellExecutable(),
        ['-c', '${_pythonShellPrefix()}pyenv which $command'],
        timeout: _pluginLifecycleProbeTimeout,
        tag: 'plugin_lifecycle.pyenv_which',
      );
      if (result.exitCode != 0) continue;
      for (final line in result.stdout.toString().split('\n').reversed) {
        final trimmed = line.trim();
        if (trimmed.startsWith('/')) return trimmed;
      }
    }
    return null;
  }

  Future<String?> _readPythonVersion(String executable) async {
    final result = await runTrackedProcessOrFailed(
      executable,
      ['--version'],
      timeout: _pluginLifecycleProbeTimeout,
      tag: 'plugin_lifecycle.python_version',
    );
    if (result.exitCode != 0) return null;
    return extractPythonVersion('${result.stdout}\n${result.stderr}');
  }

  Future<String?> _readPipVersion(String executable) async {
    final result = await runTrackedProcessOrFailed(
      executable,
      ['-m', 'pip', '--version'],
      timeout: _pluginLifecycleVerifyTimeout,
      tag: 'plugin_lifecycle.pip_version',
    );
    if (result.exitCode != 0) return null;
    return extractPipVersion('${result.stdout}\n${result.stderr}');
  }

  bool _isExternallyManagedPipError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('externally-managed-environment') ||
        normalized.contains('externally managed') ||
        normalized.contains('pep 668');
  }

  String _pipManagedEnvironmentMessage(_PythonRuntimeContext context) {
    return switch (context.source) {
      _PythonRuntimeSource.homebrew =>
        '当前 pip 由 Homebrew Python 管理，不能在插件中直接自升级。请通过 Homebrew 更新对应 Python。',
      _PythonRuntimeSource.system =>
        '当前 pip 绑定的是系统 Python，不能在插件中直接自升级。若需安装第三方库，请使用虚拟环境。',
      _PythonRuntimeSource.unknown =>
        '当前 pip 绑定的 Python 来源未知，不能安全地在插件中直接自升级。若需安装第三方库，请使用虚拟环境。',
      _ => '当前 pip 所在环境不支持在插件中直接自升级。',
    };
  }

  Future<String?> _queryLatestPyenvPatch(String currentVersion) async {
    final parts = currentVersion.split('.');
    if (parts.length < 2) return null;
    final majorMinor = '${parts[0]}.${parts[1]}';
    final proxyEnv = pluginProxyEnvironment();
    final latestResult = await runTrackedProcessOrFailed(
      pluginShellExecutable(),
      [
        '-c',
        '${_pythonShellPrefix()}pyenv latest -k $majorMinor 2>/dev/null || true',
      ],
      timeout: _pluginLifecycleVerifyTimeout,
      tag: 'plugin_lifecycle.pyenv_latest',
      environment: proxyEnv,
    );
    final quickVersion = extractPluginFirstSemver(
      '${latestResult.stdout}\n${latestResult.stderr}',
      prefix: '$majorMinor.',
    );
    if (quickVersion != null) return quickVersion;

    final listResult = await runTrackedProcessOrFailed(
      pluginShellExecutable(),
      ['-c', '${_pythonShellPrefix()}pyenv install --list'],
      timeout: const Duration(seconds: 15),
      tag: 'plugin_lifecycle.pyenv_list',
      environment: proxyEnv,
    );
    if (listResult.exitCode != 0) return null;
    final versions = extractPluginStableVersionLines(
      listResult.stdout.toString(),
      prefix: '$majorMinor.',
    );
    if (versions.isEmpty) return null;
    versions.sort(compareSemanticVersions);
    return versions.last;
  }

  Future<String?> _queryLatestHomebrewVersion(String formula) async {
    final result = await runTrackedProcessOrFailed(
      pluginShellExecutable(),
      ['-c', '${_pythonShellPrefix()}brew info --json=v2 $formula'],
      timeout: const Duration(seconds: 10),
      tag: 'plugin_lifecycle.brew_info',
      environment: pluginProxyEnvironment(),
    );
    if (result.exitCode != 0) return null;
    try {
      final decoded = jsonDecode(result.stdout.toString());
      return _homebrewStableVersionFromDecoded(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<PluginOperationResult> installNodeJs({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测可用的包管理器…');

    if (await _isNvmAvailable()) {
      onProgress?.call('使用 nvm 安装 Node.js…');
      final result = await _runNvmCommand(
        'nvm install node && nvm alias default node && node --version',
        onProgress: onProgress,
      );
      if (result.exitCode == 0) {
        final version = _extractNodeVersion(result.stdout);
        if (version != null) {
          onProgress?.call('Node.js $version 安装成功');
          return PluginOperationResult(
            success: true,
            message: 'Node.js $version 已通过 nvm 安装',
            newVersion: version,
          );
        }
        return const PluginOperationResult(
          success: true,
          message: 'Node.js 已通过 nvm 安装',
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'nvm 安装失败: ${result.stderr}',
      );
    }

    if (await _isExecutableAvailable('fnm')) {
      onProgress?.call('使用 fnm 安装 Node.js LTS…');
      final result = await _runManagedToolchainCommandWithProgress(
        'fnm',
        ['install', '--lts'],
        onProgress: onProgress,
        timeout: _nodeToolchainTimeout,
      );
      if (result.exitCode == 0) {
        await _promoteFnmLtsDefault();
        final verified = await _verifyInstalledNodeVersion(
          progressMessage: (version) => 'Node.js $version 安装成功',
          resultMessage: (version) => 'Node.js $version 已通过 fnm 安装',
          onProgress: onProgress,
        );
        if (verified != null) return verified;
      }
      return PluginOperationResult(
        success: false,
        message: 'fnm 安装失败: ${result.stderr}',
      );
    }

    if (await _isExecutableAvailable('brew')) {
      onProgress?.call('使用 Homebrew 安装 Node.js…');
      final result = await _runManagedToolchainCommandWithProgress(
        'brew',
        ['install', 'node'],
        onProgress: onProgress,
        timeout: _nodeToolchainTimeout,
      );
      if (result.exitCode == 0) {
        final verified = await _verifyInstalledNodeVersion(
          progressMessage: (version) => 'Node.js $version 安装成功',
          resultMessage: (version) => 'Node.js $version 已通过 Homebrew 安装',
          onProgress: onProgress,
        );
        if (verified != null) return verified;
      }
      return PluginOperationResult(
        success: false,
        message: 'Homebrew 安装 Node.js 失败: ${result.stderr}',
      );
    }

    return const PluginOperationResult(
      success: false,
      message:
          '未找到可用的包管理器 (nvm / fnm / brew)。请手动安装 Node.js: https://nodejs.org',
    );
  }

  Future<PluginOperationResult> installPython({
    void Function(String line)? onProgress,
  }) async {
    if (await _isPyenvAvailable()) {
      onProgress?.call('检测到 pyenv，准备安装 Python…');
      final latest = await _queryLatestPyenvPatch('3.12.0') ?? '3.12.11';
      final result = await _runPythonShellCommand(
        'pyenv install -s $latest && pyenv global $latest && python3 --version',
        onProgress: onProgress,
        timeout: _pythonBuildTimeout,
      );
      if (result.exitCode == 0) {
        final version =
            extractPythonVersion('${result.stdout}\n${result.stderr}') ??
            latest;
        onProgress?.call('Python $version 安装成功');
        return PluginOperationResult(
          success: true,
          message: 'Python $version 已通过 pyenv 安装',
          newVersion: version,
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'pyenv 安装失败: ${result.stderr}',
      );
    }

    if (await _isExecutableAvailable('brew')) {
      onProgress?.call('使用 Homebrew 安装 Python…');
      final result = await _runManagedToolchainCommandWithProgress(
        'brew',
        ['install', 'python'],
        onProgress: onProgress,
        timeout: _packageOperationTimeout,
      );
      if (result.exitCode == 0) {
        final versionResult = await runTrackedProcessOrFailed(
          pluginShellExecutable(),
          ['-c', '${_pythonShellPrefix()}python3 --version'],
          timeout: _pluginLifecycleVerifyTimeout,
          tag: 'plugin_lifecycle.python_install_verify',
        );
        final version = extractPythonVersion(
          '${versionResult.stdout}\n${versionResult.stderr}',
        );
        if (version != null) {
          onProgress?.call('Python $version 安装成功');
          return PluginOperationResult(
            success: true,
            message: 'Python $version 已通过 Homebrew 安装',
            newVersion: version,
          );
        }
        return const PluginOperationResult(
          success: true,
          message: 'Python 已通过 Homebrew 安装',
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'Homebrew 安装 Python 失败: ${result.stderr}',
      );
    }

    return const PluginOperationResult(
      success: false,
      message:
          '未找到可自动管理 Python 的包管理器（pyenv / brew）。请先安装 pyenv 或 Homebrew，或手动安装 Python。',
    );
  }

  Future<PluginOperationResult> installPip({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python 运行时…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return const PluginOperationResult(
        success: false,
        message: '未检测到可用的 Python 运行时，请先安装 Python。',
      );
    }

    final existingVersion = await _readPipVersion(context.executablePath);
    if (existingVersion != null &&
        context.source == _PythonRuntimeSource.homebrew) {
      onProgress?.call('检测到 Homebrew 管理的 pip，跳过插件内自升级。');
      return PluginOperationResult(
        success: true,
        message: '当前 pip 由 Homebrew Python 管理，请通过 Homebrew 更新对应 Python。',
        newVersion: existingVersion,
      );
    }

    onProgress?.call('正在引导 pip…');
    final ensureResult = await _runBoundPythonCommand(
      context.executablePath,
      ['-m', 'ensurepip', '--upgrade'],
      onProgress: onProgress,
      timeout: _packageOperationTimeout,
    );
    if (ensureResult.exitCode != 0) {
      final ensureMessage = ensureResult.stderr.isNotEmpty
          ? ensureResult.stderr
          : ensureResult.stdout;
      if (_isExternallyManagedPipError(ensureMessage)) {
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'pip 引导失败: $ensureMessage',
      );
    }

    if (context.source == _PythonRuntimeSource.pyenv) {
      onProgress?.call('正在升级 pip…');
      final upgradeResult = await _runBoundPythonCommand(
        context.executablePath,
        ['-m', 'pip', 'install', '--upgrade', 'pip'],
        onProgress: onProgress,
        timeout: _packageOperationTimeout,
      );
      if (upgradeResult.exitCode != 0) {
        final upgradeMessage = upgradeResult.stderr.isNotEmpty
            ? upgradeResult.stderr
            : upgradeResult.stdout;
        if (_isExternallyManagedPipError(upgradeMessage)) {
          return PluginOperationResult(
            success: false,
            message: _pipManagedEnvironmentMessage(context),
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'pip 升级失败: $upgradeMessage',
        );
      }
    }

    final version = await _readPipVersion(context.executablePath);
    if (version == null) {
      return const PluginOperationResult(
        success: false,
        message: 'pip 安装后验证失败',
      );
    }
    onProgress?.call('pip $version 安装成功');
    return PluginOperationResult(
      success: true,
      message: 'pip $version 已就绪',
      newVersion: version,
    );
  }

  Future<PluginOperationResult> installPlaywright({
    void Function(String line)? onProgress,
  }) async {
    final nodeCheck = await _runManagedToolchainCommand('node', ['--version']);
    if (nodeCheck.exitCode != 0) {
      return const PluginOperationResult(
        success: false,
        message: 'Playwright 依赖 Node.js，请先安装 Node.js',
      );
    }
    return _installOrUpdatePlaywright(onProgress: onProgress);
  }

  Future<PluginOperationResult> _installOrUpdatePlaywright({
    required void Function(String line)? onProgress,
    bool updating = false,
  }) async {
    final action = updating ? '更新' : '安装';
    onProgress?.call('正在$action Playwright…');
    final installResult = await _runManagedToolchainCommandWithProgress(
      'npm',
      const ['install', '-g', 'playwright@latest'],
      onProgress: onProgress,
      timeout: _nodeToolchainTimeout,
      environment: _npmGlobalPackageEnv(),
    );
    if (installResult.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: 'Playwright $action失败: ${_processErrorMessage(installResult)}',
      );
    }
    final installation = await _resolveGlobalNpmPackage('playwright');
    if (installation == null) {
      return PluginOperationResult(
        success: false,
        message: 'Playwright $action后未找到 npm 全局安装目标',
      );
    }
    onProgress?.call('正在${updating ? '更新' : '安装'} Playwright 浏览器…');
    final browserInstall = await _runManagedToolchainCommandWithProgress(
      'node',
      [installation.executablePath, 'install'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 10),
    );
    if (browserInstall.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message:
            'Playwright 浏览器${updating ? '更新' : '安装'}失败: '
            '${_processErrorMessage(browserInstall)}',
      );
    }
    final verify = await _runManagedToolchainCommand('node', [
      installation.executablePath,
      '--version',
    ], timeout: const Duration(seconds: 15));
    if (verify.exitCode == 0) {
      final version = _normalizePlaywrightVersion(verify.stdout);
      if (extractPluginFirstSemver(version) == null) {
        return PluginOperationResult(
          success: false,
          message: 'Playwright $action后版本校验失败',
        );
      }
      onProgress?.call('Playwright $version $action成功');
      return PluginOperationResult(
        success: true,
        message: 'Playwright 已${updating ? '更新到' : '安装'} $version',
        newVersion: version,
      );
    }
    return PluginOperationResult(
      success: false,
      message: 'Playwright $action后验证失败',
    );
  }

  Future<PluginOperationResult> installDingtalkWorkspaceCli({
    void Function(String line)? onProgress,
  }) async {
    final url = pluginDingtalkWorkspaceCliInstallScriptUrl();
    final target = pluginDingtalkWorkspaceCliTargetOs();
    onProgress?.call('按当前平台 $target 安装 DingTalk Workspace CLI…');
    final result = Platform.isWindows
        ? await _runWithProgress(
            'powershell.exe',
            <String>[
              '-NoLogo',
              '-NoProfile',
              '-NonInteractive',
              '-ExecutionPolicy',
              'Bypass',
              '-Command',
              "irm '$url' | iex",
            ],
            onProgress: onProgress,
            timeout: _packageOperationTimeout,
          )
        : await _runWithProgress(
            pluginShellExecutable(),
            <String>['-c', 'curl -fsSL ${posixShellQuote(url)} | sh'],
            onProgress: onProgress,
            timeout: _packageOperationTimeout,
          );
    if (result.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: 'DingTalk Workspace CLI 安装失败: ${_processErrorMessage(result)}',
      );
    }
    final executable = await resolvePluginDingtalkWorkspaceCliExecutable(
      tag: 'plugin_lifecycle.dingtalk_workspace_cli_install_path',
    );
    if (executable == null) {
      return const PluginOperationResult(
        success: false,
        message: 'DingTalk Workspace CLI 安装后未找到 dws 可执行文件。',
      );
    }
    final verify = await runTrackedProcessOrFailed(
      executable,
      const <String>['--version'],
      timeout: _pluginLifecycleVerifyTimeout,
      tag: 'plugin_lifecycle.dingtalk_workspace_cli_install_verify',
      environment: pluginProxyEnvironment(),
    );
    final version = verify.exitCode == 0
        ? extractPluginFirstSemver('${verify.stdout}\n${verify.stderr}')
        : null;
    if (version == null) {
      return const PluginOperationResult(
        success: false,
        message: 'DingTalk Workspace CLI 安装后版本校验失败。',
      );
    }
    onProgress?.call('DingTalk Workspace CLI $version 安装成功');
    return PluginOperationResult(
      success: true,
      message: 'DingTalk Workspace CLI 已安装到 $target',
      newVersion: version,
    );
  }

  Future<PluginOperationResult> _installBrewFormula({
    required String formula,
    required String label,
    required String verifyCommand,
    void Function(String line)? onProgress,
  }) async {
    if (!await _isExecutableAvailable('brew')) {
      return PluginOperationResult(
        success: false,
        message: '未找到 Homebrew，无法自动安装 $label。',
      );
    }
    onProgress?.call('使用 Homebrew 安装 $label…');
    final result = await _runManagedToolchainCommandWithProgress(
      'brew',
      ['install', formula],
      onProgress: onProgress,
      timeout: _packageOperationTimeout,
    );
    if (result.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: 'Homebrew 安装 $label 失败: ${_processErrorMessage(result)}',
      );
    }
    final verify = await runTrackedProcessOrFailed(
      pluginShellExecutable(),
      ['-c', '${_pythonShellPrefix()}command -v $verifyCommand'],
      timeout: _pluginLifecycleVerifyTimeout,
      tag: 'plugin_lifecycle.verify.$verifyCommand',
    );
    onProgress?.call('$label 安装完成');
    return PluginOperationResult(
      success: true,
      message: verify.exitCode == 0
          ? '$label 已安装：${verify.stdout.toString().trim()}'
          : '$label 已通过 Homebrew 安装；如命令不可见，请检查 shell PATH。',
    );
  }

  Future<PluginOperationResult> _updateBrewFormula({
    required String formula,
    required String label,
    void Function(String line)? onProgress,
  }) async {
    if (!await _isExecutableAvailable('brew')) {
      return PluginOperationResult(
        success: false,
        message: '未找到 Homebrew，无法自动更新 $label。',
      );
    }
    onProgress?.call('使用 Homebrew 更新 $label…');
    final result = await _runManagedToolchainCommandWithProgress(
      'brew',
      ['upgrade', formula],
      onProgress: onProgress,
      timeout: _packageOperationTimeout,
    );
    if (result.exitCode == 0 ||
        _processErrorMessage(result).contains('already installed') ||
        _processErrorMessage(result).contains('not outdated')) {
      onProgress?.call('$label 更新完成');
      return PluginOperationResult(success: true, message: '$label 已更新');
    }
    return PluginOperationResult(
      success: false,
      message: 'Homebrew 更新 $label 失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> _uninstallBrewFormula({
    required String formula,
    required String label,
    void Function(String line)? onProgress,
  }) async {
    if (!await _isExecutableAvailable('brew')) {
      return PluginOperationResult(
        success: false,
        message: '未找到 Homebrew，无法自动卸载 $label。',
      );
    }
    onProgress?.call('使用 Homebrew 卸载 $label…');
    final result = await _runManagedToolchainCommandWithProgress(
      'brew',
      ['uninstall', formula],
      onProgress: onProgress,
      timeout: _packageOperationTimeout,
    );
    if (result.exitCode == 0) {
      onProgress?.call('$label 已卸载');
      return PluginOperationResult(success: true, message: '$label 已卸载');
    }
    return PluginOperationResult(
      success: false,
      message: 'Homebrew 卸载 $label 失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> _installOrUpdatePythonPackage({
    required String packageName,
    required String label,
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python / pip 环境…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return PluginOperationResult(
        success: false,
        message: '$label 需要 Python，请先安装 Python。',
      );
    }
    final pipVersion = await _readPipVersion(context.executablePath);
    if (pipVersion == null) {
      return PluginOperationResult(
        success: false,
        message: '$label 需要 pip，请先安装 pip。',
      );
    }
    onProgress?.call('通过 pip 安装/更新 $label…');
    final result = await _runBoundPythonCommand(
      context.executablePath,
      ['-m', 'pip', 'install', '--upgrade', packageName],
      onProgress: onProgress,
      timeout: _packageOperationTimeout,
    );
    if (result.exitCode != 0) {
      final message = _processErrorMessage(result);
      if (_isExternallyManagedPipError(message)) {
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'pip 安装 $label 失败: $message',
      );
    }
    onProgress?.call('$label 已就绪');
    return PluginOperationResult(success: true, message: '$label 已安装或更新');
  }

  Future<PluginOperationResult> _uninstallPythonPackage({
    required String packageName,
    required String label,
    void Function(String line)? onProgress,
  }) async {
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return PluginOperationResult(
        success: false,
        message: '未检测到 Python，无法卸载 $label。',
      );
    }
    onProgress?.call('通过 pip 卸载 $label…');
    final result = await _runBoundPythonCommand(context.executablePath, [
      '-m',
      'pip',
      'uninstall',
      '-y',
      packageName,
    ], onProgress: onProgress);
    if (result.exitCode == 0) {
      onProgress?.call('$label 已卸载');
      return PluginOperationResult(success: true, message: '$label 已卸载');
    }
    return PluginOperationResult(
      success: false,
      message: 'pip 卸载 $label 失败: ${_processErrorMessage(result)}',
    );
  }

  String _androidReverseToolRoot() {
    return p.absolute(OpenHandPaths.defaultAndroidReverseToolsDirectoryPath());
  }

  String _androidReverseToolBinDir() =>
      p.join(_androidReverseToolRoot(), 'bin');

  Future<void> _prepareAndroidReverseToolDirectories(
    Iterable<String> directories,
  ) async {
    final appRoot = p.absolute(OpenHandPaths.defaultRootDirectoryPath());
    final toolRoot = _androidReverseToolRoot();
    await createDirectoryBounded(Directory(appRoot));
    if (!await isPhysicalPathWithinOrEqual(appRoot, toolRoot)) {
      throw StateError('Android 逆向工具目录超出 OpenHand 数据根目录。');
    }
    await createDirectoryBounded(Directory(toolRoot));
    if (!await isPhysicalPathWithinOrEqual(appRoot, toolRoot)) {
      throw StateError('Android 逆向工具目录超出 OpenHand 数据根目录。');
    }

    for (final directory in directories) {
      if (!await isPhysicalPathWithinOrEqual(toolRoot, directory)) {
        throw StateError('Android 逆向工具子目录超出受管目录。');
      }
      await createDirectoryBounded(Directory(directory));
      if (!await isPhysicalPathWithinOrEqual(toolRoot, directory)) {
        throw StateError('Android 逆向工具子目录超出受管目录。');
      }
    }
  }

  Future<void> _validateAndroidReverseToolFileDestination(String path) async {
    final toolRoot = _androidReverseToolRoot();
    final type = await FileSystemEntity.type(
      path,
      followLinks: false,
    ).timeout(_pluginLifecycleProbeTimeout);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw StateError('Android 逆向工具文件目标类型不安全。');
    }
    if (!await isPhysicalPathWithinOrEqual(toolRoot, path)) {
      throw StateError('Android 逆向工具文件目标超出受管目录。');
    }
  }

  PluginOperationResult _androidReversePathFailure({
    required String label,
    required String action,
    required Object error,
  }) {
    final detail = switch (error) {
      TimeoutException() => '工具目录操作超时。',
      StateError() => error.message,
      _ => '无法安全访问或清理 OpenHand 托管工具目录。',
    };
    return PluginOperationResult(
      success: false,
      message: '$label $action失败: $detail',
    );
  }

  Future<PluginOperationResult> _installOrUpdateGitPythonTool({
    required String label,
    required String repoUrl,
    required String directoryName,
    required String shimName,
    required String entrypoint,
    required List<String> pipPackages,
    String? macosBrewPackages,
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在安装/更新 $label…');
    if (!await _isExecutableAvailable('git')) {
      return PluginOperationResult(
        success: false,
        message: '$label 安装失败: 未找到 git。',
      );
    }
    if (!await _isExecutableAvailable('python3')) {
      return PluginOperationResult(
        success: false,
        message: '$label 安装失败: 未找到 python3。',
      );
    }
    final root = _androidReverseToolRoot();
    final target = p.join(root, directoryName);
    final binDir = _androidReverseToolBinDir();
    final shimPath = p.join(binDir, shimName);
    final entrypointPath = p.join(target, entrypoint);
    late final bool updateExisting;
    try {
      await _prepareAndroidReverseToolDirectories(<String>[binDir]);
      await _validateAndroidReverseToolFileDestination(shimPath);
      final targetType = await FileSystemEntity.type(
        target,
        followLinks: false,
      ).timeout(_pluginLifecycleProbeTimeout);
      final gitDirectory = p.join(target, '.git');
      final gitType = targetType == FileSystemEntityType.directory
          ? await FileSystemEntity.type(
              gitDirectory,
              followLinks: false,
            ).timeout(_pluginLifecycleProbeTimeout)
          : FileSystemEntityType.notFound;
      updateExisting =
          targetType == FileSystemEntityType.directory &&
          gitType == FileSystemEntityType.directory &&
          await isPhysicalPathWithinOrEqual(root, target) &&
          await isPhysicalPathWithinOrEqual(root, gitDirectory);
      if (!updateExisting && targetType != FileSystemEntityType.notFound) {
        await deletePathBounded(target, allowedRoot: root);
      }
      if (!updateExisting && !await isPhysicalPathWithinOrEqual(root, target)) {
        throw StateError('Android 逆向工具安装目录超出受管目录。');
      }
    } catch (error) {
      if (error is! FileSystemException &&
          error is! TimeoutException &&
          error is! StateError) {
        rethrow;
      }
      return _androidReversePathFailure(
        label: label,
        action: '安装',
        error: error,
      );
    }
    final shim =
        '#!/usr/bin/env bash\n'
        'exec python3 ${posixShellQuote(entrypointPath)} "\$@"\n';
    final brewStep = macosBrewPackages == null || macosBrewPackages.isEmpty
        ? ''
        : '''
if [ "\$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
  brew install $macosBrewPackages || true
fi
''';
    final pipStep = pipPackages.isEmpty
        ? ''
        : 'python3 -m pip install --user --upgrade ${pipPackages.map(posixShellQuote).join(' ')}';
    final sourceStep = updateExisting
        ? 'git -C ${posixShellQuote(target)} pull --ff-only'
        : 'git clone --depth 1 ${posixShellQuote(repoUrl)} ${posixShellQuote(target)}';
    final script =
        '''
set -euo pipefail
if ! command -v git >/dev/null 2>&1; then echo "未找到 git" >&2; exit 127; fi
if ! command -v python3 >/dev/null 2>&1; then echo "未找到 python3" >&2; exit 127; fi
$brewStep
$sourceStep
$pipStep
printf %s ${posixShellQuote(shim)} > ${posixShellQuote(shimPath)}
chmod +x ${posixShellQuote(shimPath)}
printf '%s\\n' ${posixShellQuote('$label 命令入口：$shimPath')}
''';
    final result = await _runWithProgress(
      pluginShellExecutable(),
      ['-c', script],
      onProgress: onProgress,
      timeout: _pythonBuildTimeout,
      environment: pluginProxyEnvironment(),
    );
    if (result.exitCode == 0) {
      return PluginOperationResult(
        success: true,
        message: '$label 已安装或更新：$shimPath',
      );
    }
    return PluginOperationResult(
      success: false,
      message: '$label 安装失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> _uninstallOpenHandTool({
    required String label,
    required String directoryName,
    required String shimName,
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在卸载 $label…');
    final root = _androidReverseToolRoot();
    try {
      final rootType = await FileSystemEntity.type(
        root,
        followLinks: false,
      ).timeout(_pluginLifecycleProbeTimeout);
      if (rootType == FileSystemEntityType.notFound) {
        return PluginOperationResult(success: true, message: '$label 已卸载');
      }
      final appRoot = p.absolute(OpenHandPaths.defaultRootDirectoryPath());
      if (!await isPhysicalPathWithinOrEqual(appRoot, root)) {
        throw StateError('Android 逆向工具目录超出 OpenHand 数据根目录。');
      }
      await deletePathBounded(p.join(root, directoryName), allowedRoot: root);
      await deletePathBounded(
        p.join(_androidReverseToolBinDir(), shimName),
        allowedRoot: root,
      );
      return PluginOperationResult(success: true, message: '$label 已卸载');
    } catch (error) {
      if (error is! FileSystemException &&
          error is! TimeoutException &&
          error is! StateError) {
        rethrow;
      }
      return _androidReversePathFailure(
        label: label,
        action: '卸载',
        error: error,
      );
    }
  }

  Future<PluginOperationResult> _installOrUpdateAnythingAnalyzer({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在下载 Anything Analyzer 最新发布包…');
    final root = _androidReverseToolRoot();
    final target = p.join(root, 'anything-analyzer');
    final binDir = _androidReverseToolBinDir();
    final shimPath = p.join(binDir, 'anything-analyzer');
    final current = p.join(target, 'current');
    late final Directory stagingDirectory;
    late final String stagingCurrent;
    try {
      await _prepareAndroidReverseToolDirectories(<String>[target, binDir]);
      await _validateAndroidReverseToolFileDestination(shimPath);
      stagingDirectory = await Directory(root)
          .createTemp('anything-analyzer-install-')
          .timeout(_pluginLifecycleProbeTimeout);
      if (!await isPhysicalPathWithinOrEqual(root, stagingDirectory.path)) {
        throw StateError('Anything Analyzer 临时安装目录超出受管目录。');
      }
      stagingCurrent = p.join(stagingDirectory.path, 'current');
      await createDirectoryBounded(Directory(stagingCurrent));
    } catch (error) {
      if (error is! FileSystemException &&
          error is! TimeoutException &&
          error is! StateError) {
        rethrow;
      }
      return _androidReversePathFailure(
        label: 'Anything Analyzer',
        action: '安装',
        error: error,
      );
    }
    final script =
        '''
set -euo pipefail
if ! command -v curl >/dev/null 2>&1; then echo "未找到 curl" >&2; exit 127; fi
if ! command -v python3 >/dev/null 2>&1; then echo "未找到 python3" >&2; exit 127; fi
META="\$(curl -fsSL https://api.github.com/repos/Mouseww/anything-analyzer/releases/latest)"
ASSET="\$(printf '%s' "\$META" | python3 -c '
import json, platform, sys
data = json.load(sys.stdin)
assets = data.get("assets", [])
system = platform.system().lower()
machine = platform.machine().lower()
patterns = []
if system == "darwin":
    if "arm" in machine or "aarch" in machine:
        patterns += ["arm64.dmg", "arm64.zip"]
    patterns += ["x64.dmg", "x64.zip", "mac"]
elif system == "linux":
    patterns += [".AppImage", "linux"]
elif system == "windows":
    patterns += [".exe", "Setup"]
for pattern in patterns:
    for asset in assets:
        name = asset.get("name", "")
        if pattern.lower() in name.lower():
            print(asset.get("browser_download_url", ""))
            raise SystemExit(0)
raise SystemExit(3)
')"
if [ -z "\$ASSET" ]; then echo "未找到兼容的 Anything Analyzer 发布包" >&2; exit 3; fi
NAME="\${ASSET##*/}"
PKG="${posixShellQuote(stagingDirectory.path)}/\$NAME"
curl -fL "\$ASSET" -o "\$PKG"
case "\$NAME" in
  *.dmg)
    MOUNT=${posixShellQuote(p.join(stagingDirectory.path, 'mount'))}
    mkdir -p "\$MOUNT"
    trap 'hdiutil detach "\$MOUNT" >/dev/null 2>&1 || true; rmdir "\$MOUNT" >/dev/null 2>&1 || true' EXIT
    hdiutil attach -nobrowse -readonly -mountpoint "\$MOUNT" "\$PKG" >/dev/null
    APP="\$(find "\$MOUNT" -maxdepth 2 -name '*.app' -type d | head -1)"
    if [ -z "\$APP" ]; then echo "安装包中未找到 Anything Analyzer 应用" >&2; exit 5; fi
    cp -R "\$APP" ${posixShellQuote(stagingCurrent)}/
    hdiutil detach "\$MOUNT" >/dev/null
    rmdir "\$MOUNT"
    trap - EXIT
    ;;
  *.zip)
    if ! command -v unzip >/dev/null 2>&1; then echo "未找到 unzip" >&2; exit 127; fi
    unzip -q "\$PKG" -d ${posixShellQuote(stagingCurrent)}
    ;;
  *.AppImage)
    cp "\$PKG" ${posixShellQuote(stagingCurrent)}/Anything-Analyzer.AppImage
    chmod +x ${posixShellQuote(stagingCurrent)}/Anything-Analyzer.AppImage
    ;;
  *.exe)
    cp "\$PKG" ${posixShellQuote(stagingCurrent)}/
    ;;
  *)
    echo "不支持的安装包：\$NAME" >&2
    exit 4
    ;;
esac
cat > ${posixShellQuote(shimPath)} <<'SHIM'
#!/usr/bin/env bash
ROOT=${posixShellQuote(current)}
APP="\$(find "\$ROOT" -maxdepth 2 -name '*.app' -type d 2>/dev/null | head -1)"
if [ -n "\$APP" ]; then
  exec open -a "\$APP" --args "\$@"
fi
APPIMAGE="\$(find "\$ROOT" -maxdepth 2 -name '*.AppImage' -type f 2>/dev/null | head -1)"
if [ -n "\$APPIMAGE" ]; then
  exec "\$APPIMAGE" "\$@"
fi
echo "在 \$ROOT 下未找到 Anything Analyzer 应用" >&2
exit 2
SHIM
chmod +x ${posixShellQuote(shimPath)}
printf '安装包=%s\\n命令入口=%s\\n' "\$ASSET" ${posixShellQuote(shimPath)}
''';
    final result = await _runWithProgress(
      pluginShellExecutable(),
      ['-c', script],
      onProgress: onProgress,
      timeout: _packageOperationTimeout,
      environment: pluginProxyEnvironment(),
    );
    if (result.exitCode != 0) {
      try {
        await deletePathBounded(stagingDirectory.path, allowedRoot: root);
      } catch (error) {
        if (error is! FileSystemException &&
            error is! TimeoutException &&
            error is! StateError) {
          rethrow;
        }
        return _androidReversePathFailure(
          label: 'Anything Analyzer',
          action: '安装',
          error: error,
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'Anything Analyzer 安装失败: ${_processErrorMessage(result)}',
      );
    }

    try {
      final backup = p.join(target, 'current.previous');
      await deletePathBounded(backup, allowedRoot: root);
      final currentType = await FileSystemEntity.type(
        current,
        followLinks: false,
      ).timeout(_pluginLifecycleProbeTimeout);
      var hasBackup = false;
      if (currentType == FileSystemEntityType.directory) {
        if (!await isPhysicalPathWithinOrEqual(root, current)) {
          throw StateError('Anything Analyzer 当前安装目录超出受管目录。');
        }
        await Directory(
          current,
        ).rename(backup).timeout(_pluginLifecycleProbeTimeout);
        hasBackup = true;
      } else if (currentType != FileSystemEntityType.notFound) {
        await deletePathBounded(current, allowedRoot: root);
      }
      try {
        await Directory(
          stagingCurrent,
        ).rename(current).timeout(_pluginLifecycleProbeTimeout);
      } catch (error, stack) {
        if (hasBackup) {
          await Directory(
            backup,
          ).rename(current).timeout(_pluginLifecycleProbeTimeout);
        }
        Error.throwWithStackTrace(error, stack);
      }
      await deletePathBounded(backup, allowedRoot: root);
      await deletePathBounded(stagingDirectory.path, allowedRoot: root);
      return PluginOperationResult(
        success: true,
        message: 'Anything Analyzer 已安装或更新：$shimPath',
      );
    } catch (error) {
      if (error is! FileSystemException &&
          error is! TimeoutException &&
          error is! StateError) {
        rethrow;
      }
      try {
        await deletePathBounded(stagingDirectory.path, allowedRoot: root);
      } catch (cleanupError) {
        if (cleanupError is! FileSystemException &&
            cleanupError is! TimeoutException &&
            cleanupError is! StateError) {
          rethrow;
        }
        return _androidReversePathFailure(
          label: 'Anything Analyzer',
          action: '安装',
          error: cleanupError,
        );
      }
      return _androidReversePathFailure(
        label: 'Anything Analyzer',
        action: '安装',
        error: error,
      );
    }
  }

  Future<PluginOperationResult> installJava({
    void Function(String line)? onProgress,
  }) => _installBrewFormula(
    formula: 'openjdk',
    label: 'Java',
    verifyCommand: 'java',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installFrida({
    void Function(String line)? onProgress,
  }) => _installOrUpdatePythonPackage(
    packageName: 'frida-tools',
    label: 'Frida',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installMitmproxy({
    void Function(String line)? onProgress,
  }) => _installBrewFormula(
    formula: 'mitmproxy',
    label: 'mitmproxy',
    verifyCommand: 'mitmdump',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installApktool({
    void Function(String line)? onProgress,
  }) => _installBrewFormula(
    formula: 'apktool',
    label: 'apktool',
    verifyCommand: 'apktool',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installJadx({
    void Function(String line)? onProgress,
  }) => _installBrewFormula(
    formula: 'jadx',
    label: 'jadx',
    verifyCommand: 'jadx',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installRadare2({
    void Function(String line)? onProgress,
  }) => _installBrewFormula(
    formula: 'radare2',
    label: 'radare2',
    verifyCommand: 'r2',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installBlutter({
    void Function(String line)? onProgress,
  }) => _installOrUpdateGitPythonTool(
    label: 'blutter',
    repoUrl: 'https://github.com/worawit/blutter.git',
    directoryName: 'blutter',
    shimName: 'blutter',
    entrypoint: 'blutter.py',
    pipPackages: const <String>['pyelftools', 'requests'],
    macosBrewPackages: 'cmake ninja pkg-config icu4c capstone',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installDoldrums({
    void Function(String line)? onProgress,
  }) => _installOrUpdateGitPythonTool(
    label: 'Doldrums',
    repoUrl: 'https://github.com/rscloura/Doldrums.git',
    directoryName: 'doldrums',
    shimName: 'doldrums',
    entrypoint: 'src/main.py',
    pipPackages: const <String>['pyelftools'],
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installAnythingAnalyzer({
    void Function(String line)? onProgress,
  }) => _installOrUpdateAnythingAnalyzer(onProgress: onProgress);

  Future<PluginOperationResult> installDocker({
    void Function(String line)? onProgress,
    OpenHandAsyncContinuePredicate? shouldContinue,
  }) async {
    onProgress?.call('正在检测 Docker…');
    if (await _isExecutableAvailable('docker')) {
      if (await _isDockerDaemonAvailable()) {
        return const PluginOperationResult(
          success: true,
          message: 'Docker CLI 与 daemon 已就绪。',
        );
      }
      if (await pluginDockerDesktopInstallationExists()) {
        onProgress?.call('Docker Desktop 已安装，正在尝试启动…');
        await _runWithProgress(
          'open',
          ['-a', 'Docker'],
          onProgress: onProgress,
          timeout: const Duration(seconds: 20),
        );
        for (
          var attempt = 1;
          attempt <= _dockerDaemonMaxPollAttempts;
          attempt++
        ) {
          if (shouldContinue?.call() == false) {
            return const PluginOperationResult(
              success: false,
              message: 'Docker 启动等待已取消。',
            );
          }
          if (await _isDockerDaemonAvailable()) {
            return const PluginOperationResult(
              success: true,
              message: 'Docker Desktop 已启动，daemon 可用。',
            );
          }
          if (attempt == _dockerDaemonMaxPollAttempts) break;
          onProgress?.call(
            '等待 Docker daemon 启动… $attempt/$_dockerDaemonMaxPollAttempts',
          );
          final stillActive = await delayWhileContinuing(
            _dockerDaemonPollInterval,
            () => shouldContinue?.call() ?? true,
          );
          if (!stillActive) {
            return const PluginOperationResult(
              success: false,
              message: 'Docker 启动等待已取消。',
            );
          }
        }
      }
      return const PluginOperationResult(
        success: false,
        message: 'docker CLI 已安装，但 daemon 未运行。请启动 Docker Desktop 后重新扫描。',
      );
    }

    if (Platform.isMacOS && await _isExecutableAvailable('brew')) {
      onProgress?.call('使用 Homebrew Cask 安装 Docker Desktop…');
      final result = await _runManagedToolchainCommandWithProgress(
        'brew',
        ['install', '--cask', 'docker'],
        onProgress: onProgress,
        timeout: _dockerDesktopTimeout,
      );
      if (result.exitCode != 0) {
        return PluginOperationResult(
          success: false,
          message: 'Docker Desktop 安装失败: ${_processErrorMessage(result)}',
        );
      }
      onProgress?.call('Docker Desktop 已安装，请根据系统提示完成首次启动授权。');
      return const PluginOperationResult(
        success: true,
        message: 'Docker Desktop 已安装。首次使用可能需要手动打开并完成授权。',
      );
    }

    if (Platform.isWindows) {
      return const PluginOperationResult(
        success: false,
        message:
            'Windows 暂不支持静默安装 Docker。请安装 Docker Desktop: https://www.docker.com/products/docker-desktop/',
      );
    }
    if (Platform.isLinux) {
      return const PluginOperationResult(
        success: false,
        message:
            'Linux 暂不执行自动安装 Docker。请按发行版安装 docker engine 与 compose plugin，并确认当前用户可访问 docker daemon。',
      );
    }
    return const PluginOperationResult(
      success: false,
      message: '当前平台不支持自动安装 Docker。',
    );
  }

  Future<PluginOperationResult> installQdrant({
    void Function(String line)? onProgress,
  }) async {
    if (!await _isExecutableAvailable('docker')) {
      return const PluginOperationResult(
        success: false,
        message: 'Qdrant 依赖 Docker，请先安装 Docker。',
      );
    }
    if (!await _isDockerDaemonAvailable()) {
      return const PluginOperationResult(
        success: false,
        message: 'Docker daemon 未运行，请先启动 Docker。',
      );
    }
    final dataDir = _qdrantDataDirectory();
    final script =
        '''
set -euo pipefail
mkdir -p ${posixShellQuote(dataDir)}
docker pull ${posixShellQuote(_qdrantImage)}
${_qdrantManagedContainerGuard()}
  docker start ${posixShellQuote(_qdrantContainerName)} >/dev/null
else
${_qdrantDockerRunCommand(dataDir, indent: 2)}
fi
${_qdrantHealthWaitScript()}
''';
    final result = await _runWithProgress(
      pluginShellExecutable(),
      ['-c', script],
      onProgress: onProgress,
      timeout: _packageOperationTimeout,
      environment: pluginProxyEnvironment(),
    );
    if (result.exitCode == 0) {
      return PluginOperationResult(
        success: true,
        message: 'Qdrant 已启动，数据目录：$dataDir',
      );
    }
    return PluginOperationResult(
      success: false,
      message: 'Qdrant 安装/启动失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> installPostgresql({
    void Function(String line)? onProgress,
  }) => _installManagedDatabase(
    label: 'PostgreSQL',
    containerName: ManagedServiceDefaults.postgresqlContainerName,
    image: ManagedServiceDefaults.postgresqlImage,
    port: ManagedServiceDefaults.postgresqlPort,
    dataDir: _managedDatabaseDataDirectory('postgresql'),
    dataDestination: ManagedServiceDefaults.postgresqlDataDestination,
    dockerArguments: const <String>[
      '-e',
      'POSTGRES_USER=${ManagedServiceDefaults.postgresqlUser}',
      '-e',
      'POSTGRES_PASSWORD=${ManagedServiceDefaults.postgresqlPassword}',
      '-e',
      'POSTGRES_DB=${ManagedServiceDefaults.postgresqlDatabase}',
    ],
    healthCommand:
        'pg_isready -U ${ManagedServiceDefaults.postgresqlUser} -d ${ManagedServiceDefaults.postgresqlDatabase}',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installRedis({
    void Function(String line)? onProgress,
  }) => _installManagedDatabase(
    label: 'Redis',
    containerName: ManagedServiceDefaults.redisContainerName,
    image: ManagedServiceDefaults.redisImage,
    port: ManagedServiceDefaults.redisPort,
    dataDir: _managedDatabaseDataDirectory('redis'),
    dataDestination: ManagedServiceDefaults.redisDataDestination,
    containerArguments: const <String>['redis-server', '--appendonly', 'yes'],
    healthCommand: 'redis-cli ping',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> _installManagedDatabase({
    required String label,
    required String containerName,
    required String image,
    required int port,
    required String dataDir,
    required String dataDestination,
    required String healthCommand,
    List<String> dockerArguments = const <String>[],
    List<String> containerArguments = const <String>[],
    void Function(String line)? onProgress,
  }) async {
    if (!await _isExecutableAvailable('docker')) {
      return PluginOperationResult(
        success: false,
        message: '$label 依赖 Docker，请先安装 Docker。',
      );
    }
    if (!await _isDockerDaemonAvailable()) {
      return const PluginOperationResult(
        success: false,
        message: 'Docker daemon 未运行，请先启动 Docker。',
      );
    }
    onProgress?.call('正在准备 $label 容器…');
    final name = posixShellQuote(containerName);
    final script =
        '''
set -euo pipefail
mkdir -p ${posixShellQuote(dataDir)}
${_managedDatabaseGuard(containerName)}
if docker inspect $name >/dev/null 2>&1; then
  docker start $name >/dev/null
else
  docker pull ${posixShellQuote(image)}
  ${_managedDatabaseRunCommand(containerName: containerName, image: image, port: port, dataDir: dataDir, dataDestination: dataDestination, dockerArguments: dockerArguments, containerArguments: containerArguments)}
fi
${_managedDatabaseHealthWaitScript(containerName: containerName, healthCommand: healthCommand, label: label)}
''';
    final result = await _runWithProgress(
      pluginShellExecutable(),
      ['-c', script],
      onProgress: onProgress,
      timeout: _packageOperationTimeout,
      environment: pluginProxyEnvironment(),
    );
    if (result.exitCode == 0) {
      return PluginOperationResult(
        success: true,
        message: '$label 已启动，数据目录：$dataDir',
      );
    }
    return PluginOperationResult(
      success: false,
      message: '$label 安装/启动失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> updateNodeJs({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Node.js 安装方式…');
    final nodePath = await _resolveManagedToolchainCommandPath('node') ?? '';

    final isNvm = nodePath.contains('.nvm/');
    final isFnm = nodePath.contains('.fnm/') || nodePath.contains('/fnm/');
    final isVolta = nodePath.contains('.volta/');
    final isBrew =
        nodePath.contains('/homebrew/') ||
        nodePath.contains('/Cellar/') ||
        nodePath.startsWith('/opt/homebrew/') ||
        nodePath.startsWith('/usr/local/bin/');

    if (isNvm) {
      onProgress?.call('检测到 nvm 管理的 Node.js，使用 nvm 更新…');
      final result = await _runNvmCommand(
        'nvm install node --reinstall-packages-from=current && nvm alias default node && node --version',
        onProgress: onProgress,
      );
      if (result.exitCode == 0) {
        final version = _extractNodeVersion(result.stdout);
        if (version != null) {
          onProgress?.call('Node.js 已更新到 $version');
          return PluginOperationResult(
            success: true,
            message: 'Node.js 已通过 nvm 更新到 $version',
            newVersion: version,
          );
        }
        onProgress?.call('Node.js 更新完成');
        return const PluginOperationResult(
          success: true,
          message: 'Node.js 已通过 nvm 更新',
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'nvm 更新失败: ${result.stderr}',
      );
    }

    if (isFnm) {
      onProgress?.call('检测到 fnm 管理的 Node.js，使用 fnm 更新…');
      final result = await _runManagedToolchainCommandWithProgress(
        'fnm',
        ['install', '--lts'],
        onProgress: onProgress,
        timeout: _nodeToolchainTimeout,
      );
      if (result.exitCode == 0) {
        await _promoteFnmLtsDefault();
        final verified = await _verifyInstalledNodeVersion(
          progressMessage: (version) => 'Node.js 已更新到 $version',
          resultMessage: (version) => 'Node.js 已通过 fnm 更新到 $version',
          onProgress: onProgress,
        );
        if (verified != null) return verified;
      }
      return PluginOperationResult(
        success: false,
        message: 'fnm 更新失败: ${result.stderr}',
      );
    }

    if (isVolta) {
      onProgress?.call('检测到 volta 管理的 Node.js，使用 volta 更新…');
      final result = await _runManagedToolchainCommandWithProgress(
        'volta',
        ['install', 'node@latest'],
        onProgress: onProgress,
        timeout: _nodeToolchainTimeout,
      );
      if (result.exitCode == 0) {
        final verified = await _verifyInstalledNodeVersion(
          progressMessage: (version) => 'Node.js 已更新到 $version',
          resultMessage: (version) => 'Node.js 已通过 volta 更新到 $version',
          onProgress: onProgress,
        );
        if (verified != null) return verified;
      }
      return PluginOperationResult(
        success: false,
        message: 'volta 更新失败: ${result.stderr}',
      );
    }

    if (isBrew) {
      onProgress?.call('检测到 Homebrew 管理的 Node.js，使用 brew 更新…');
      final result = await _runManagedToolchainCommandWithProgress(
        'brew',
        ['upgrade', 'node'],
        onProgress: onProgress,
        timeout: _nodeToolchainTimeout,
      );
      if (result.exitCode == 0) {
        final verified = await _verifyInstalledNodeVersion(
          progressMessage: (version) => 'Node.js 已更新到 $version',
          resultMessage: (version) => 'Node.js 已通过 Homebrew 更新到 $version',
          onProgress: onProgress,
        );
        if (verified != null) return verified;
      }
      return PluginOperationResult(
        success: false,
        message: 'Homebrew 更新失败: ${result.stderr}',
      );
    }

    onProgress?.call('未能确定安装方式，尝试可用的包管理器…');
    if (await _isExecutableAvailable('fnm')) {
      final result = await _runManagedToolchainCommandWithProgress(
        'fnm',
        ['install', '--lts'],
        onProgress: onProgress,
        timeout: _nodeToolchainTimeout,
      );
      if (result.exitCode == 0) {
        await _promoteFnmLtsDefault();
        final verified = await _verifyInstalledNodeVersion(
          progressMessage: (version) => 'Node.js 已更新到 $version',
          resultMessage: (version) => 'Node.js 已更新到 $version',
          onProgress: onProgress,
        );
        if (verified != null) return verified;
      }
    }
    return const PluginOperationResult(
      success: false,
      message:
          '未找到可用的包管理器来更新 Node.js。\n'
          '请根据您的安装方式手动更新：\n'
          '  · nvm: nvm install --lts\n'
          '  · fnm: fnm install --lts\n'
          '  · brew: brew upgrade node\n'
          '  · volta: volta install node@latest',
    );
  }

  Future<PluginOperationResult> updatePython({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python 安装方式…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return const PluginOperationResult(
        success: false,
        message: '未检测到可用的 Python 运行时。',
      );
    }

    switch (context.source) {
      case _PythonRuntimeSource.pyenv:
        final currentVersion = context.version ?? context.pyenvVersion;
        if (currentVersion == null) {
          return const PluginOperationResult(
            success: false,
            message: '无法识别当前 pyenv Python 版本。',
          );
        }
        final latest = await _queryLatestPyenvPatch(currentVersion);
        if (latest == null) {
          return const PluginOperationResult(
            success: false,
            message: '无法查询 pyenv 的最新 Python 版本。',
          );
        }
        if (latest == currentVersion || latest == context.pyenvVersion) {
          return PluginOperationResult(
            success: true,
            message: 'Python 已是最新版本 $currentVersion',
            newVersion: currentVersion,
          );
        }
        onProgress?.call('使用 pyenv 将 Python 更新到 $latest…');
        final result = await _runPythonShellCommand(
          'pyenv install -s $latest && pyenv global $latest && python3 --version',
          onProgress: onProgress,
          timeout: _pythonBuildTimeout,
        );
        if (result.exitCode == 0) {
          final version =
              extractPythonVersion('${result.stdout}\n${result.stderr}') ??
              latest;
          onProgress?.call('Python 已更新到 $version');
          return PluginOperationResult(
            success: true,
            message: 'Python 已通过 pyenv 更新到 $version',
            newVersion: version,
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'pyenv 更新失败: ${result.stderr}',
        );
      case _PythonRuntimeSource.homebrew:
        final formula = context.brewFormula ?? 'python';
        final targetVersion = await _queryLatestHomebrewVersion(formula);
        onProgress?.call('使用 Homebrew 更新 Python…');
        final result = await _runManagedToolchainCommandWithProgress(
          'brew',
          ['upgrade', formula],
          onProgress: onProgress,
          timeout: _packageOperationTimeout,
        );
        if (result.exitCode == 0) {
          final version =
              await _readPythonVersion(context.executablePath) ?? targetVersion;
          onProgress?.call(
            version == null ? 'Python 更新完成' : 'Python 已更新到 $version',
          );
          return PluginOperationResult(
            success: true,
            message: version == null
                ? 'Python 已通过 Homebrew 更新'
                : 'Python 已通过 Homebrew 更新到 $version',
            newVersion: version,
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'Homebrew 更新 Python 失败: ${result.stderr}',
        );
      case _PythonRuntimeSource.system:
        return const PluginOperationResult(
          success: false,
          message: '当前 Python 来自系统环境，暂不支持自动升级，请手动维护。',
        );
      case _PythonRuntimeSource.unknown:
        return const PluginOperationResult(
          success: false,
          message: '当前 Python 安装来源未知，暂不支持自动升级，请手动维护。',
        );
    }
  }

  Future<PluginOperationResult> updatePip({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python 运行时…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return const PluginOperationResult(
        success: false,
        message: '未检测到可用的 Python 运行时。',
      );
    }

    switch (context.source) {
      case _PythonRuntimeSource.pyenv:
        onProgress?.call('正在升级 pip…');
        final result = await _runBoundPythonCommand(
          context.executablePath,
          ['-m', 'pip', 'install', '--upgrade', 'pip'],
          onProgress: onProgress,
          timeout: _packageOperationTimeout,
        );
        if (result.exitCode != 0) {
          final updateMessage = result.stderr.isNotEmpty
              ? result.stderr
              : result.stdout;
          if (_isExternallyManagedPipError(updateMessage)) {
            return PluginOperationResult(
              success: false,
              message: _pipManagedEnvironmentMessage(context),
            );
          }
          return PluginOperationResult(
            success: false,
            message: 'pip 升级失败: $updateMessage',
          );
        }
        final version = await _readPipVersion(context.executablePath);
        if (version == null) {
          return const PluginOperationResult(
            success: false,
            message: 'pip 升级后验证失败',
          );
        }
        onProgress?.call('pip 已更新到 $version');
        return PluginOperationResult(
          success: true,
          message: 'pip 已更新到 $version',
          newVersion: version,
        );
      case _PythonRuntimeSource.homebrew:
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
      case _PythonRuntimeSource.system:
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
      case _PythonRuntimeSource.unknown:
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
    }
  }

  Future<PluginOperationResult> updatePlaywright({
    void Function(String line)? onProgress,
  }) => _installOrUpdatePlaywright(onProgress: onProgress, updating: true);

  Future<PluginOperationResult> updateDingtalkWorkspaceCli({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在使用 dws 自升级能力更新 DingTalk Workspace CLI…');
    final result = await _runDingtalkCommandWithProgress(const <String>[
      'upgrade',
      '-y',
    ], onProgress: onProgress);
    if (result.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: 'DingTalk Workspace CLI 更新失败: ${_processErrorMessage(result)}',
      );
    }
    final executable = await resolvePluginDingtalkWorkspaceCliExecutable(
      tag: 'plugin_lifecycle.dingtalk_workspace_cli_update_path',
    );
    if (executable == null) {
      return const PluginOperationResult(
        success: false,
        message: 'DingTalk Workspace CLI 更新后未找到 dws 可执行文件。',
      );
    }
    final verify = await runTrackedProcessOrFailed(
      executable,
      const <String>['--version'],
      timeout: _pluginLifecycleVerifyTimeout,
      tag: 'plugin_lifecycle.dingtalk_workspace_cli_update_verify',
      environment: pluginProxyEnvironment(),
    );
    final version = verify.exitCode == 0
        ? extractPluginFirstSemver('${verify.stdout}\n${verify.stderr}')
        : null;
    if (version == null) {
      return const PluginOperationResult(
        success: false,
        message: 'DingTalk Workspace CLI 更新后版本校验失败。',
      );
    }
    onProgress?.call('DingTalk Workspace CLI 已更新到 $version');
    return PluginOperationResult(
      success: true,
      message: 'DingTalk Workspace CLI 已更新到 $version',
      newVersion: version,
    );
  }

  Future<PluginOperationResult> updateJava({
    void Function(String line)? onProgress,
  }) => _updateBrewFormula(
    formula: 'openjdk',
    label: 'Java',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateFrida({
    void Function(String line)? onProgress,
  }) => _installOrUpdatePythonPackage(
    packageName: 'frida-tools',
    label: 'Frida',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateMitmproxy({
    void Function(String line)? onProgress,
  }) => _updateBrewFormula(
    formula: 'mitmproxy',
    label: 'mitmproxy',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateApktool({
    void Function(String line)? onProgress,
  }) => _updateBrewFormula(
    formula: 'apktool',
    label: 'apktool',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateJadx({
    void Function(String line)? onProgress,
  }) => _updateBrewFormula(
    formula: 'jadx',
    label: 'jadx',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateRadare2({
    void Function(String line)? onProgress,
  }) => _updateBrewFormula(
    formula: 'radare2',
    label: 'radare2',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateBlutter({
    void Function(String line)? onProgress,
  }) => installBlutter(onProgress: onProgress);

  Future<PluginOperationResult> updateDoldrums({
    void Function(String line)? onProgress,
  }) => installDoldrums(onProgress: onProgress);

  Future<PluginOperationResult> updateAnythingAnalyzer({
    void Function(String line)? onProgress,
  }) => _installOrUpdateAnythingAnalyzer(onProgress: onProgress);

  Future<PluginOperationResult> updateDocker({
    void Function(String line)? onProgress,
  }) async {
    if (Platform.isMacOS && await _isExecutableAvailable('brew')) {
      onProgress?.call('使用 Homebrew Cask 更新 Docker Desktop…');
      final result = await _runManagedToolchainCommandWithProgress(
        'brew',
        ['upgrade', '--cask', 'docker'],
        onProgress: onProgress,
        timeout: _dockerDesktopTimeout,
      );
      final message = _processErrorMessage(result);
      if (result.exitCode == 0 ||
          message.contains('already installed') ||
          message.contains('not outdated')) {
        return const PluginOperationResult(
          success: true,
          message: 'Docker Desktop 已更新或已经是最新版本。',
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'Docker Desktop 更新失败: $message',
      );
    }
    return const PluginOperationResult(
      success: false,
      message: '无法自动更新 Docker。请通过 Docker Desktop 或系统包管理器更新。',
    );
  }

  Future<PluginOperationResult> updateQdrant({
    void Function(String line)? onProgress,
  }) async {
    if (!await _isDockerDaemonAvailable()) {
      return const PluginOperationResult(
        success: false,
        message: 'Docker daemon 未运行，请先启动 Docker。',
      );
    }
    final dataDir = _qdrantDataDirectory();
    final script =
        '''
set -euo pipefail
docker pull ${posixShellQuote(_qdrantImage)}
${_qdrantManagedContainerGuard()}
  docker stop ${posixShellQuote(_qdrantContainerName)} >/dev/null || true
  docker rm ${posixShellQuote(_qdrantContainerName)} >/dev/null || true
fi
mkdir -p ${posixShellQuote(dataDir)}
${_qdrantDockerRunCommand(dataDir, indent: 0)}
${_qdrantHealthWaitScript()}
''';
    final result = await _runWithProgress(
      pluginShellExecutable(),
      ['-c', script],
      onProgress: onProgress,
      timeout: _packageOperationTimeout,
      environment: pluginProxyEnvironment(),
    );
    if (result.exitCode == 0) {
      return const PluginOperationResult(
        success: true,
        message: 'Qdrant 镜像已更新，容器已安全重建并保留数据目录。',
      );
    }
    return PluginOperationResult(
      success: false,
      message: 'Qdrant 更新失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> updatePostgresql({
    void Function(String line)? onProgress,
  }) => _updateManagedDatabase(
    label: 'PostgreSQL',
    containerName: ManagedServiceDefaults.postgresqlContainerName,
    image: ManagedServiceDefaults.postgresqlImage,
    port: ManagedServiceDefaults.postgresqlPort,
    dataDir: _managedDatabaseDataDirectory('postgresql'),
    dataDestination: ManagedServiceDefaults.postgresqlDataDestination,
    dockerArguments: const <String>[
      '-e',
      'POSTGRES_USER=${ManagedServiceDefaults.postgresqlUser}',
      '-e',
      'POSTGRES_PASSWORD=${ManagedServiceDefaults.postgresqlPassword}',
      '-e',
      'POSTGRES_DB=${ManagedServiceDefaults.postgresqlDatabase}',
    ],
    healthCommand:
        'pg_isready -U ${ManagedServiceDefaults.postgresqlUser} -d ${ManagedServiceDefaults.postgresqlDatabase}',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateRedis({
    void Function(String line)? onProgress,
  }) => _updateManagedDatabase(
    label: 'Redis',
    containerName: ManagedServiceDefaults.redisContainerName,
    image: ManagedServiceDefaults.redisImage,
    port: ManagedServiceDefaults.redisPort,
    dataDir: _managedDatabaseDataDirectory('redis'),
    dataDestination: ManagedServiceDefaults.redisDataDestination,
    containerArguments: const <String>['redis-server', '--appendonly', 'yes'],
    healthCommand: 'redis-cli ping',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> _updateManagedDatabase({
    required String label,
    required String containerName,
    required String image,
    required int port,
    required String dataDir,
    required String dataDestination,
    required String healthCommand,
    List<String> dockerArguments = const <String>[],
    List<String> containerArguments = const <String>[],
    void Function(String line)? onProgress,
  }) async {
    if (!await _isDockerDaemonAvailable()) {
      return const PluginOperationResult(
        success: false,
        message: 'Docker daemon 未运行，请先启动 Docker。',
      );
    }
    onProgress?.call('正在更新 $label 镜像并重建容器…');
    final name = posixShellQuote(containerName);
    final script =
        '''
set -euo pipefail
docker pull ${posixShellQuote(image)}
${_managedDatabaseGuard(containerName)}
if ! docker inspect $name >/dev/null 2>&1; then
  echo "未找到 OpenHand 托管的 $label 容器" >&2
  exit 2
fi
docker stop $name >/dev/null || true
docker rm $name >/dev/null || true
mkdir -p ${posixShellQuote(dataDir)}
${_managedDatabaseRunCommand(containerName: containerName, image: image, port: port, dataDir: dataDir, dataDestination: dataDestination, dockerArguments: dockerArguments, containerArguments: containerArguments)}
${_managedDatabaseHealthWaitScript(containerName: containerName, healthCommand: healthCommand, label: label)}
''';
    final result = await _runWithProgress(
      pluginShellExecutable(),
      ['-c', script],
      onProgress: onProgress,
      timeout: _packageOperationTimeout,
      environment: pluginProxyEnvironment(),
    );
    if (result.exitCode == 0) {
      return PluginOperationResult(
        success: true,
        message: '$label 镜像已更新，数据目录保持不变。',
      );
    }
    return PluginOperationResult(
      success: false,
      message: '$label 更新失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> uninstallNodeJs({
    required bool playwrightInstalled,
    void Function(String line)? onProgress,
  }) async {
    if (playwrightInstalled) {
      return const PluginOperationResult(
        success: false,
        message: 'Playwright 依赖 Node.js，请先卸载 Playwright',
      );
    }
    onProgress?.call('正在卸载 Node.js…');
    if (await _isExecutableAvailable('brew')) {
      final result = await _runManagedToolchainCommandWithProgress('brew', [
        'uninstall',
        'node',
      ], onProgress: onProgress);
      if (result.exitCode == 0) {
        onProgress?.call('Node.js 已卸载');
        return const PluginOperationResult(
          success: true,
          message: 'Node.js 已通过 Homebrew 卸载',
        );
      }
      return PluginOperationResult(
        success: false,
        message: '卸载失败: ${result.stderr}',
      );
    }
    return const PluginOperationResult(
      success: false,
      message: '未找到可用的包管理器来卸载 Node.js，请手动卸载',
    );
  }

  Future<PluginOperationResult> uninstallPython({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python 安装方式…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return const PluginOperationResult(
        success: false,
        message: '未检测到可用的 Python 运行时。',
      );
    }

    switch (context.source) {
      case _PythonRuntimeSource.pyenv:
        final version = context.pyenvVersion ?? context.version;
        if (version == null) {
          return const PluginOperationResult(
            success: false,
            message: '无法识别当前 pyenv Python 版本。',
          );
        }
        onProgress?.call('使用 pyenv 卸载 Python $version…');
        final script = StringBuffer()..writeln('pyenv uninstall -f $version');
        final remaining = await _remainingPyenvVersions(excluding: version);
        if (remaining.isNotEmpty) {
          remaining.sort(compareSemanticVersions);
          script.writeln('pyenv global ${remaining.last}');
        } else {
          script.writeln('pyenv global system');
        }
        final result = await _runPythonShellCommand(
          script.toString(),
          onProgress: onProgress,
          timeout: _packageOperationTimeout,
        );
        if (result.exitCode == 0) {
          onProgress?.call('Python $version 已卸载');
          return PluginOperationResult(
            success: true,
            message: 'Python $version 已通过 pyenv 卸载',
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'pyenv 卸载失败: ${result.stderr}',
        );
      case _PythonRuntimeSource.homebrew:
        final formula = context.brewFormula ?? 'python';
        onProgress?.call('使用 Homebrew 卸载 Python…');
        final result = await _runManagedToolchainCommandWithProgress(
          'brew',
          ['uninstall', formula],
          onProgress: onProgress,
          timeout: _packageOperationTimeout,
        );
        if (result.exitCode == 0) {
          onProgress?.call('Python 已卸载');
          return const PluginOperationResult(
            success: true,
            message: 'Python 已通过 Homebrew 卸载',
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'Homebrew 卸载 Python 失败: ${result.stderr}',
        );
      case _PythonRuntimeSource.system:
        return const PluginOperationResult(
          success: false,
          message: '当前 Python 来自系统环境，暂不支持自动卸载。',
        );
      case _PythonRuntimeSource.unknown:
        return const PluginOperationResult(
          success: false,
          message: '当前 Python 安装来源未知，暂不支持自动卸载。',
        );
    }
  }

  Future<PluginOperationResult> uninstallPip({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('pip 不支持独立卸载');
    return const PluginOperationResult(
      success: false,
      message: 'pip 不支持卸载，仅支持安装与升级。',
    );
  }

  Future<PluginOperationResult> uninstallPlaywright({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在卸载 Playwright…');
    final result = await _runManagedToolchainCommandWithProgress(
      'npm',
      const ['uninstall', '-g', 'playwright'],
      onProgress: onProgress,
      environment: _npmGlobalPackageEnv(),
    );
    if (result.exitCode == 0) {
      onProgress?.call('Playwright 已卸载');
      return const PluginOperationResult(
        success: true,
        message: 'Playwright 已卸载',
      );
    }
    return PluginOperationResult(
      success: false,
      message: '卸载失败: ${result.stderr}',
    );
  }

  Future<PluginOperationResult> uninstallDingtalkWorkspaceCli({
    void Function(String line)? onProgress,
  }) async {
    final npmInstallation = await resolvePluginDingtalkWorkspaceCliNpmPackage(
      tag: 'plugin_lifecycle.dingtalk_workspace_cli_npm_root',
    );
    if (npmInstallation != null) {
      onProgress?.call('通过 npm 卸载 DingTalk Workspace CLI…');
      final npmResult = await _runDingtalkNpmCommandWithProgress(const <String>[
        'uninstall',
        '-g',
        pluginDingtalkWorkspaceCliPackage,
      ], onProgress: onProgress);
      if (npmResult.exitCode != 0) {
        return PluginOperationResult(
          success: false,
          message:
              'npm 卸载 DingTalk Workspace CLI 失败: ${_processErrorMessage(npmResult)}',
        );
      }
    }

    final executable = await resolvePluginDingtalkWorkspaceCliExecutable(
      tag: 'plugin_lifecycle.dingtalk_workspace_cli_uninstall_path',
    );
    if (executable != null) {
      try {
        await File(executable).delete().timeout(_pluginLifecycleVerifyTimeout);
        onProgress?.call('已删除 dws 可执行文件: $executable');
      } on FileSystemException catch (error) {
        return PluginOperationResult(
          success: false,
          message: '删除 dws 可执行文件失败: ${error.message}',
        );
      } on TimeoutException {
        return const PluginOperationResult(
          success: false,
          message: '删除 dws 可执行文件超时。',
        );
      }
    }
    await _removeDingtalkWorkspaceCliSkills(onProgress);
    onProgress?.call('DingTalk Workspace CLI 已卸载');
    return const PluginOperationResult(
      success: true,
      message: 'DingTalk Workspace CLI 已卸载',
    );
  }

  Future<PluginOperationResult> uninstallGoogleChrome({
    required String executablePath,
    String? installedVersion,
    void Function(String line)? onProgress,
  }) async {
    final executable = p.normalize(executablePath.trim());
    if (executable.isEmpty || !p.isAbsolute(executable)) {
      return const PluginOperationResult(
        success: false,
        message: 'Google Chrome 可执行文件路径无效，无法安全卸载。',
      );
    }
    if (Platform.isMacOS) {
      return _uninstallGoogleChromeMacOs(executable, onProgress: onProgress);
    }
    if (Platform.isWindows) {
      return _uninstallGoogleChromeWindows(
        executable,
        installedVersion: installedVersion,
        onProgress: onProgress,
      );
    }
    if (Platform.isLinux) {
      return _uninstallGoogleChromeLinux(executable, onProgress: onProgress);
    }
    return const PluginOperationResult(
      success: false,
      message: '当前操作系统不支持自动卸载 Google Chrome。',
    );
  }

  Future<PluginOperationResult> _uninstallGoogleChromeMacOs(
    String executable, {
    void Function(String line)? onProgress,
  }) async {
    const suffix = '/Contents/MacOS/Google Chrome';
    if (!executable.endsWith(suffix)) {
      return const PluginOperationResult(
        success: false,
        message: '当前 Chrome 不是标准 macOS 应用安装，无法安全移至废纸篓。',
      );
    }
    final application = executable.substring(
      0,
      executable.length - suffix.length,
    );
    if (p.basename(application) != 'Google Chrome.app') {
      return const PluginOperationResult(
        success: false,
        message: 'Chrome 应用目录校验失败，已取消卸载。',
      );
    }
    if (await _isExecutableAvailable('brew')) {
      final cask = await _runManagedToolchainCommand('brew', const <String>[
        'list',
        '--cask',
        'google-chrome',
      ]);
      if (cask.exitCode == 0) {
        onProgress?.call('正在通过 Homebrew Cask 卸载 Google Chrome…');
        final result = await _runManagedToolchainCommandWithProgress(
          'brew',
          const <String>['uninstall', '--cask', 'google-chrome'],
          onProgress: onProgress,
          timeout: _packageOperationTimeout,
        );
        if (result.exitCode != 0) {
          return PluginOperationResult(
            success: false,
            message: 'Google Chrome 卸载失败: ${_processErrorMessage(result)}',
          );
        }
        if (!await _waitForGoogleChromeRemoval(executable)) {
          return const PluginOperationResult(
            success: false,
            message: 'Homebrew 已结束卸载，但 Chrome 仍可检测到，请稍后重新扫描。',
          );
        }
        onProgress?.call('Google Chrome 已通过 Homebrew 卸载，用户资料保持不变。');
        return const PluginOperationResult(
          success: true,
          message: 'Google Chrome 已卸载，用户资料已保留。',
        );
      }
    }
    onProgress?.call('正在将 Google Chrome 移至废纸篓…');
    final result = await _runWithProgress(
      '/usr/bin/osascript',
      <String>[
        '-e',
        'on run argv',
        '-e',
        'tell application "Finder" to delete POSIX file (item 1 of argv)',
        '-e',
        'end run',
        application,
      ],
      onProgress: onProgress,
      timeout: _packageOperationTimeout,
    );
    if (result.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: 'Google Chrome 卸载失败: ${_processErrorMessage(result)}',
      );
    }
    if (!await _waitForGoogleChromeRemoval(executable)) {
      return const PluginOperationResult(
        success: false,
        message: 'Chrome 已提交到废纸篓，但可执行文件仍然存在，请稍后重新扫描。',
      );
    }
    onProgress?.call('Google Chrome 已移至废纸篓，用户资料保持不变。');
    return const PluginOperationResult(
      success: true,
      message: 'Google Chrome 已移至废纸篓，用户资料已保留。',
    );
  }

  Future<PluginOperationResult> _uninstallGoogleChromeWindows(
    String executable, {
    required String? installedVersion,
    void Function(String line)? onProgress,
  }) async {
    final applicationDirectory = p.dirname(executable);
    final candidates = <String>[
      if (nullIfBlank(installedVersion) case final version?)
        p.join(applicationDirectory, version, 'Installer', 'setup.exe'),
    ];
    try {
      final listing = await listDirectoryBounded(
        Directory(applicationDirectory),
        maxEntries: _googleChromeInstallerDirectoryMaxEntries,
      );
      for (final entry in listing.entries) {
        if (entry is Directory) {
          candidates.add(p.join(entry.path, 'Installer', 'setup.exe'));
        }
      }
    } catch (error, stack) {
      silentLog('plugin_lifecycle', '定位 Chrome 官方卸载程序', error, stack);
    }
    String? setup;
    for (final candidate in candidates) {
      if (await isRegularFilePath(candidate, followLinks: true)) {
        setup = candidate;
        break;
      }
    }
    if (setup == null) {
      return const PluginOperationResult(
        success: false,
        message: '未找到 Chrome 官方卸载程序，请通过 Windows 应用设置卸载。',
      );
    }
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final systemLevel =
        localAppData.isEmpty ||
        !executable.toLowerCase().startsWith(localAppData.toLowerCase());
    onProgress?.call('正在调用 Chrome 官方卸载程序…');
    final result = await _runWithProgress(
      setup,
      <String>[
        '--uninstall',
        '--channel=stable',
        '--force-uninstall',
        '--verbose-logging',
        if (systemLevel) '--system-level',
      ],
      onProgress: onProgress,
      timeout: _packageOperationTimeout,
    );
    if (result.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: 'Google Chrome 卸载失败: ${_processErrorMessage(result)}',
      );
    }
    if (!await _waitForGoogleChromeRemoval(executable)) {
      return const PluginOperationResult(
        success: false,
        message: 'Chrome 卸载程序已结束，但浏览器仍可检测到，请检查 Windows 应用设置。',
      );
    }
    onProgress?.call('Google Chrome 已卸载，用户资料保持不变。');
    return const PluginOperationResult(
      success: true,
      message: 'Google Chrome 已卸载，用户资料已保留。',
    );
  }

  Future<PluginOperationResult> _uninstallGoogleChromeLinux(
    String executable, {
    void Function(String line)? onProgress,
  }) async {
    String? manager;
    List<String>? arguments;
    for (final candidate in <(String, List<String>)>[
      ('apt-get', const <String>['remove', '--yes', 'google-chrome-stable']),
      ('dnf', const <String>['remove', '-y', 'google-chrome-stable']),
      ('yum', const <String>['remove', '-y', 'google-chrome-stable']),
      (
        'zypper',
        const <String>['--non-interactive', 'remove', 'google-chrome-stable'],
      ),
      ('pacman', const <String>['-Rns', '--noconfirm', 'google-chrome']),
    ]) {
      if (await _isExecutableAvailable(candidate.$1)) {
        manager = await _resolveManagedToolchainCommandPath(candidate.$1);
        arguments = candidate.$2;
        break;
      }
    }
    if (manager == null || arguments == null) {
      return const PluginOperationResult(
        success: false,
        message: '未找到支持的 Linux 包管理器，无法自动卸载 Google Chrome。',
      );
    }
    final isRoot = Platform.environment['USER'] == 'root';
    final pkexec = isRoot
        ? null
        : await _resolveManagedToolchainCommandPath('pkexec');
    if (!isRoot && pkexec == null) {
      return const PluginOperationResult(
        success: false,
        message: '未找到 pkexec，无法请求系统权限卸载 Google Chrome。',
      );
    }
    onProgress?.call('正在通过系统包管理器卸载 Google Chrome…');
    final result = await _runWithProgress(
      pkexec ?? manager,
      <String>[if (pkexec != null) manager, ...arguments],
      onProgress: onProgress,
      timeout: _packageOperationTimeout,
    );
    if (result.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: 'Google Chrome 卸载失败: ${_processErrorMessage(result)}',
      );
    }
    if (!await _waitForGoogleChromeRemoval(executable)) {
      return const PluginOperationResult(
        success: false,
        message: '包管理器已结束，但 Chrome 仍可检测到，请重新扫描后检查安装来源。',
      );
    }
    onProgress?.call('Google Chrome 已卸载，用户资料保持不变。');
    return const PluginOperationResult(
      success: true,
      message: 'Google Chrome 已卸载，用户资料已保留。',
    );
  }

  Future<bool> _waitForGoogleChromeRemoval(String executable) async {
    for (
      var attempt = 0;
      attempt < _googleChromeRemovalMaxPollAttempts;
      attempt++
    ) {
      if (!await isRegularFilePath(executable, followLinks: true)) return true;
      if (attempt + 1 < _googleChromeRemovalMaxPollAttempts) {
        await Future<void>.delayed(_googleChromeRemovalPollInterval);
      }
    }
    return false;
  }

  Future<PluginOperationResult> uninstallJava({
    void Function(String line)? onProgress,
  }) => _uninstallBrewFormula(
    formula: 'openjdk',
    label: 'Java',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallFrida({
    void Function(String line)? onProgress,
  }) => _uninstallPythonPackage(
    packageName: 'frida-tools',
    label: 'Frida',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallMitmproxy({
    void Function(String line)? onProgress,
  }) => _uninstallBrewFormula(
    formula: 'mitmproxy',
    label: 'mitmproxy',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallApktool({
    void Function(String line)? onProgress,
  }) => _uninstallBrewFormula(
    formula: 'apktool',
    label: 'apktool',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallJadx({
    void Function(String line)? onProgress,
  }) => _uninstallBrewFormula(
    formula: 'jadx',
    label: 'jadx',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallRadare2({
    void Function(String line)? onProgress,
  }) => _uninstallBrewFormula(
    formula: 'radare2',
    label: 'radare2',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallBlutter({
    void Function(String line)? onProgress,
  }) => _uninstallOpenHandTool(
    label: 'blutter',
    directoryName: 'blutter',
    shimName: 'blutter',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallDoldrums({
    void Function(String line)? onProgress,
  }) => _uninstallOpenHandTool(
    label: 'Doldrums',
    directoryName: 'doldrums',
    shimName: 'doldrums',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallAnythingAnalyzer({
    void Function(String line)? onProgress,
  }) => _uninstallOpenHandTool(
    label: 'Anything Analyzer',
    directoryName: 'anything-analyzer',
    shimName: 'anything-analyzer',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallDocker({
    void Function(String line)? onProgress,
  }) async {
    if (Platform.isMacOS && await _isExecutableAvailable('brew')) {
      onProgress?.call('使用 Homebrew Cask 卸载 Docker Desktop…');
      final result = await _runManagedToolchainCommandWithProgress(
        'brew',
        ['uninstall', '--cask', 'docker'],
        onProgress: onProgress,
        timeout: _packageOperationTimeout,
      );
      if (result.exitCode == 0) {
        return const PluginOperationResult(
          success: true,
          message: 'Docker Desktop 已卸载。',
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'Docker Desktop 卸载失败: ${_processErrorMessage(result)}',
      );
    }
    return const PluginOperationResult(
      success: false,
      message: '无法自动卸载 Docker。请通过 Docker Desktop 或系统包管理器卸载。',
    );
  }

  Future<PluginOperationResult> uninstallQdrant({
    void Function(String line)? onProgress,
  }) async {
    if (!await _isExecutableAvailable('docker')) {
      return const PluginOperationResult(
        success: true,
        message: 'docker CLI 不存在，Qdrant 容器无需卸载。',
      );
    }
    if (!await _isDockerDaemonAvailable()) {
      return const PluginOperationResult(
        success: false,
        message: 'Docker daemon 未运行，无法安全检查并卸载 Qdrant 容器。',
      );
    }
    final dataDir = _qdrantDataDirectory();
    final script =
        '''
set -euo pipefail
if ! docker inspect ${posixShellQuote(_qdrantContainerName)} >/dev/null 2>&1; then
  echo "Qdrant 容器不存在"
  exit 0
fi
LABEL="\$(docker inspect -f '{{ index .Config.Labels "openhand.managed" }}' ${posixShellQuote(_qdrantContainerName)} 2>/dev/null || true)"
if [ "\$LABEL" != "true" ]; then
  echo "检测到同名但非 OpenHand 托管的容器：$_qdrantContainerName" >&2
  exit 3
fi
docker stop ${posixShellQuote(_qdrantContainerName)} >/dev/null || true
docker rm ${posixShellQuote(_qdrantContainerName)} >/dev/null || true
echo "已保留 Qdrant 数据目录：${posixShellQuote(dataDir)}"
''';
    final result = await _runWithProgress(
      pluginShellExecutable(),
      ['-c', script],
      onProgress: onProgress,
      environment: pluginProxyEnvironment(),
    );
    if (result.exitCode == 0) {
      return PluginOperationResult(
        success: true,
        message: 'Qdrant 容器已移除，数据目录已保留：$dataDir',
      );
    }
    return PluginOperationResult(
      success: false,
      message: 'Qdrant 卸载失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> startQdrant({
    void Function(String line)? onProgress,
  }) => _setManagedContainerRunning(
    label: 'Qdrant',
    containerName: _qdrantContainerName,
    healthWaitScript: _qdrantHealthWaitScript(),
    running: true,
    onProgress: onProgress,
  );

  Future<PluginOperationResult> stopQdrant({
    void Function(String line)? onProgress,
  }) => _setManagedContainerRunning(
    label: 'Qdrant',
    containerName: _qdrantContainerName,
    healthWaitScript: _qdrantHealthWaitScript(),
    running: false,
    onProgress: onProgress,
  );

  Future<PluginOperationResult> startPostgresql({
    void Function(String line)? onProgress,
  }) => _setManagedContainerRunning(
    label: 'PostgreSQL',
    containerName: ManagedServiceDefaults.postgresqlContainerName,
    healthWaitScript: _managedDatabaseHealthWaitScript(
      containerName: ManagedServiceDefaults.postgresqlContainerName,
      healthCommand:
          'pg_isready -U ${ManagedServiceDefaults.postgresqlUser} -d ${ManagedServiceDefaults.postgresqlDatabase}',
      label: 'PostgreSQL',
    ),
    running: true,
    onProgress: onProgress,
  );

  Future<PluginOperationResult> stopPostgresql({
    void Function(String line)? onProgress,
  }) => _setManagedContainerRunning(
    label: 'PostgreSQL',
    containerName: ManagedServiceDefaults.postgresqlContainerName,
    healthWaitScript: _managedDatabaseHealthWaitScript(
      containerName: ManagedServiceDefaults.postgresqlContainerName,
      healthCommand:
          'pg_isready -U ${ManagedServiceDefaults.postgresqlUser} -d ${ManagedServiceDefaults.postgresqlDatabase}',
      label: 'PostgreSQL',
    ),
    running: false,
    onProgress: onProgress,
  );

  Future<PluginOperationResult> startRedis({
    void Function(String line)? onProgress,
  }) => _setManagedContainerRunning(
    label: 'Redis',
    containerName: ManagedServiceDefaults.redisContainerName,
    healthWaitScript: _managedDatabaseHealthWaitScript(
      containerName: ManagedServiceDefaults.redisContainerName,
      healthCommand: 'redis-cli ping',
      label: 'Redis',
    ),
    running: true,
    onProgress: onProgress,
  );

  Future<PluginOperationResult> stopRedis({
    void Function(String line)? onProgress,
  }) => _setManagedContainerRunning(
    label: 'Redis',
    containerName: ManagedServiceDefaults.redisContainerName,
    healthWaitScript: _managedDatabaseHealthWaitScript(
      containerName: ManagedServiceDefaults.redisContainerName,
      healthCommand: 'redis-cli ping',
      label: 'Redis',
    ),
    running: false,
    onProgress: onProgress,
  );

  Future<PluginOperationResult> _setManagedContainerRunning({
    required String label,
    required String containerName,
    required String healthWaitScript,
    required bool running,
    void Function(String line)? onProgress,
  }) async {
    if (!await _isDockerDaemonAvailable()) {
      return const PluginOperationResult(
        success: false,
        message: 'Docker daemon 未运行，无法切换容器状态。',
      );
    }
    onProgress?.call('正在${running ? '启动' : '停止'} $label…');
    final name = posixShellQuote(containerName);
    final script =
        '''
set -euo pipefail
${_managedDatabaseGuard(containerName)}
if ! docker inspect $name >/dev/null 2>&1; then
  echo "未找到 OpenHand 托管的 $label 容器" >&2
  exit 2
fi
docker ${running ? 'start' : 'stop'} $name >/dev/null
${running ? healthWaitScript : 'echo "$label 已停止"'}
''';
    final result = await _runWithProgress(
      pluginShellExecutable(),
      ['-c', script],
      onProgress: onProgress,
      environment: pluginProxyEnvironment(),
    );
    if (result.exitCode == 0) {
      return PluginOperationResult(
        success: true,
        message: '$label 已${running ? '启动' : '停止'}。',
      );
    }
    return PluginOperationResult(
      success: false,
      message:
          '$label ${running ? '启动' : '停止'}失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> uninstallPostgresql({
    void Function(String line)? onProgress,
  }) => _uninstallManagedDatabase(
    label: 'PostgreSQL',
    containerName: ManagedServiceDefaults.postgresqlContainerName,
    dataDir: _managedDatabaseDataDirectory('postgresql'),
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallRedis({
    void Function(String line)? onProgress,
  }) => _uninstallManagedDatabase(
    label: 'Redis',
    containerName: ManagedServiceDefaults.redisContainerName,
    dataDir: _managedDatabaseDataDirectory('redis'),
    onProgress: onProgress,
  );

  Future<PluginOperationResult> _uninstallManagedDatabase({
    required String label,
    required String containerName,
    required String dataDir,
    void Function(String line)? onProgress,
  }) async {
    if (!await _isExecutableAvailable('docker')) {
      return PluginOperationResult(
        success: true,
        message: 'docker CLI 不存在，$label 容器无需卸载。',
      );
    }
    if (!await _isDockerDaemonAvailable()) {
      return PluginOperationResult(
        success: false,
        message: 'Docker daemon 未运行，无法安全检查并卸载 $label 容器。',
      );
    }
    onProgress?.call('正在卸载 $label 容器…');
    final name = posixShellQuote(containerName);
    final script =
        '''
set -euo pipefail
if ! docker inspect $name >/dev/null 2>&1; then
  echo "$label 容器不存在"
  exit 0
fi
${_managedDatabaseGuard(containerName)}
docker stop $name >/dev/null || true
docker rm $name >/dev/null || true
echo "已保留 $label 数据目录：${posixShellQuote(dataDir)}"
''';
    final result = await _runWithProgress(
      pluginShellExecutable(),
      ['-c', script],
      onProgress: onProgress,
      environment: pluginProxyEnvironment(),
    );
    if (result.exitCode == 0) {
      return PluginOperationResult(
        success: true,
        message: '$label 容器已移除，数据目录已保留：$dataDir',
      );
    }
    return PluginOperationResult(
      success: false,
      message: '$label 卸载失败: ${_processErrorMessage(result)}',
    );
  }

  Future<List<String>> _remainingPyenvVersions({
    required String excluding,
  }) async {
    final result = await runTrackedProcessOrFailed(
      pluginShellExecutable(),
      ['-c', '${_pythonShellPrefix()}pyenv versions --bare'],
      timeout: _pluginLifecycleVerifyTimeout,
      tag: 'plugin_lifecycle.pyenv_versions',
    );
    if (result.exitCode != 0) return const [];
    final versions = <String>[];
    for (final line in result.stdout.toString().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed == excluding) continue;
      if (isStrictSemanticVersionText(trimmed)) versions.add(trimmed);
    }
    return versions;
  }

  Future<_SimpleProcessResult> _runWithProgress(
    String executable,
    List<String> arguments, {
    void Function(String line)? onProgress,
    Duration timeout = _pluginLifecycleDefaultTimeout,
    Map<String, String>? environment,
  }) async {
    try {
      final mergedEnv = <String, String>{
        ...?environment,
        ...pluginProxyEnvironment(),
      };
      final effectiveTimeout = timeout <= Duration.zero
          ? _pluginLifecycleDefaultTimeout
          : timeout;
      final result = await runTrackedProcessWithLineLogging(
        executable,
        arguments,
        environment: mergedEnv,
        timeout: effectiveTimeout,
        tag: 'plugin_lifecycle',
        streamDrainTimeout: _pluginLifecycleStreamDrainTimeout,
        trimStdoutLines: true,
        maxCapturedLinesPerStream: _pluginLifecycleMaxCapturedLines,
        onStdoutLine: onProgress,
        onStderrLine: onProgress,
      );

      return _SimpleProcessResult(
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.timedOut && result.stderr.isEmpty
            ? _timeoutMessage(effectiveTimeout)
            : result.stderr,
      );
    } catch (error, stack) {
      silentLog(
        'plugin_lifecycle',
        '执行 $executable ${arguments.take(1).join(' ')}',
        error,
        stack,
      );
      return _SimpleProcessResult(exitCode: -1, stdout: '', stderr: '$error');
    }
  }
}

String _timeoutMessage(Duration timeout) {
  final seconds = timeout.inSeconds;
  if (seconds > 0) {
    return '命令在 $seconds 秒内未完成，已终止子进程树。';
  }
  return '命令超时，已终止子进程树。';
}

String _processErrorMessage(_SimpleProcessResult result) {
  if (result.stderr.trim().isNotEmpty) return result.stderr.trim();
  if (result.stdout.trim().isNotEmpty) return result.stdout.trim();
  return '进程退出码 ${result.exitCode}';
}

class _SimpleProcessResult {
  const _SimpleProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

enum _PythonRuntimeSource { pyenv, homebrew, system, unknown }

class _PythonRuntimeContext {
  const _PythonRuntimeContext({
    required this.source,
    required this.executablePath,
    this.version,
    this.pyenvVersion,
    this.brewFormula,
  });

  final _PythonRuntimeSource source;
  final String executablePath;
  final String? version;
  final String? pyenvVersion;
  final String? brewFormula;
}

String? _extractNodeVersion(String output) {
  final matches = _pluginLifecycleNodeVersionPattern.allMatches(output);
  String? version;
  for (final match in matches) {
    version = match.group(1);
  }
  return version;
}

String _normalizePlaywrightVersion(Object? output) {
  return '$output'.trim().replaceFirst(
    _pluginLifecyclePlaywrightVersionPrefixPattern,
    '',
  );
}

String? _extractPyenvVersionFromPath(String path) {
  final match = _pluginLifecyclePyenvVersionPathPattern.firstMatch(path);
  final value = match?.group(1);
  if (value != null && isStrictSemanticVersionText(value)) return value;
  return null;
}

String? _extractBrewPythonFormulaFromPath(String path) {
  final matches = _pluginLifecycleBrewPythonFormulaPathPattern.allMatches(path);
  if (matches.isEmpty) return null;
  return matches.last.group(1);
}
