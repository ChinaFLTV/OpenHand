// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'OpenHand';

  @override
  String get appTagline => 'オープンで安定した拡張可能なデスクトップワークスペース';

  @override
  String get newThread => '新規スレッド';

  @override
  String get skills => 'スキル';

  @override
  String get memory => 'メモリ';

  @override
  String get mcp => 'MCP';

  @override
  String get settings => '設定';

  @override
  String get threads => 'スレッド';

  @override
  String get threadsLoadMore => 'さらにスレッドを読み込む';

  @override
  String get composerHint => 'OpenHand に質問し、/ でアクション、@ でコンテキストを指定します';

  @override
  String get composerSend => '送信';

  @override
  String get chatSending => '送信中';

  @override
  String get chatRequestFailed =>
      'モデルリクエストに失敗しました。モデル設定、ネットワーク接続、またはプロトコル種別を確認してください。';

  @override
  String get placeholderComingSoon => '追加モジュールはここに段階的に追加されます。';

  @override
  String get settingsTitle => '設定センター';

  @override
  String get settingsSubtitle => 'ここでテーマ、言語、アプリ情報を管理します。';

  @override
  String get settingsFilePathLabel => '設定ファイル';

  @override
  String get themeSectionTitle => 'アプリテーマ';

  @override
  String get themeSectionBody => '現在の作業環境に合う画面の明るさスタイルを選択します。';

  @override
  String get themeSystem => 'システム';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeDark => 'ダーク';

  @override
  String get themePaletteSectionTitle => 'テーマパレット';

  @override
  String get themePaletteSectionBody =>
      '全体に適用するカラープリセットを選択します。OpenHand はそこから Material 3 Expressive のサーフェスとアクセントを生成します。';

  @override
  String get themePresetDarkNightPurple => 'ダークナイトパープル';

  @override
  String get themePresetDeepSeaBlue => 'ディープシーブルー';

  @override
  String get themePresetMistGray => 'ミストグレー';

  @override
  String get themePresetObsidianBlack => 'オブシディアンブラック';

  @override
  String get themePresetPolarWhite => 'ポーラーホワイト';

  @override
  String get themePresetFrostMorningBlue => 'フロストモーニングブルー';

  @override
  String get themePresetDuskMountainGreen => 'ダスクマウンテングリーン';

  @override
  String get themePresetNebulaPurple => 'ネビュラパープル';

  @override
  String get themePresetEmberOrange => 'エンバーオレンジ';

  @override
  String get themePresetTundraGreen => 'ツンドラグリーン';

  @override
  String get themePresetMoonShadowSilver => 'ムーンシャドウシルバー';

  @override
  String get themePresetAmberGold => 'アンバーゴールド';

  @override
  String get themePresetRainyCyan => 'レイニーシアン';

  @override
  String get themePresetGraphiteGray => 'グラファイトグレー';

  @override
  String get themePresetGlacierBlue => 'グレーシャーブルー';

  @override
  String get themePresetBlazeRed => 'ブレイズレッド';

  @override
  String get themePresetNightfallBlue => 'ナイトフォールブルー';

  @override
  String get themePresetColdMoonWhite => 'コールドムーンホワイト';

  @override
  String get themePresetPineInk => 'パインインク';

  @override
  String get themePresetSkyCyan => 'スカイシアン';

  @override
  String get languageSectionTitle => 'アプリ言語';

  @override
  String get languageSectionBody => '画面表示言語を切り替えるとすぐに反映されます。';

  @override
  String get languageSimplifiedChinese => '簡体字中国語';

  @override
  String get languageTraditionalChinese => '繁体字中国語';

  @override
  String get languageEnglish => '英語';

  @override
  String get languageFrench => 'フランス語';

  @override
  String get languageGerman => 'ドイツ語';

  @override
  String get languageJapanese => '日本語';

  @override
  String get aboutSectionTitle => 'アプリについて';

  @override
  String get aboutSectionBody =>
      'OpenHand は現在、安定したデスクトップ構造、視覚基盤、拡張可能な設計に重点を置いた基礎段階です。';

  @override
  String get aboutVersion => 'バージョン';

  @override
  String get aboutPackage => 'パッケージ';

  @override
  String get aboutPlatforms => '対応プラットフォーム';

  @override
  String get aboutPlatformsValue => 'macOS 15+ / Windows 10+';

  @override
  String get aboutBuild => 'ビルド';

  @override
  String get commonCancel => 'キャンセル';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '削除';

  @override
  String get commonEdit => '編集';

  @override
  String get exportProgressCancelling => 'キャンセル中…';

  @override
  String get readerFileTypeText => 'プレーンテキスト';

  @override
  String get readerFileTypeCode => 'コード';

  @override
  String knowledgeReaderNoModelForType(Object type) {
    return '$type を読み取れる reader モデルがありません。';
  }

  @override
  String get permissionLabel => 'フルアクセス';

  @override
  String get settingsCategoryGeneral => '一般';

  @override
  String get settingsCategoryAi => 'AI';

  @override
  String get settingsCategorySkills => 'スキル';

  @override
  String get settingsCategoryMemory => 'メモリ';

  @override
  String get mcpSectionTitle => 'MCP サービス';

  @override
  String get mcpSectionBody =>
      'MCP のグローバルスイッチとサービス設定ファイルパスを管理します。サービスの作成・更新・削除・有効化はすべて MCP JSON ファイルに同期されます。';

  @override
  String get mcpEnabledLabel => 'MCP サービスを有効化';

  @override
  String get mcpEnabledBody => '無効にすると、保存済みのサーバー設定は残りますが、実行時に MCP の機能はオフになります。';

  @override
  String get mcpFilePathLabel => 'MCP 設定ファイル';

  @override
  String get mcpOpenDirectory => 'ディレクトリを開く';

  @override
  String get mcpStdioCacheResetAction => 'stdio パッケージキャッシュをリセット';

  @override
  String get mcpStdioCacheResetConfirmTitle => 'stdio の隔離パッケージキャッシュをリセットしますか？';

  @override
  String get mcpStdioCacheResetConfirmBody =>
      '~/.openhand/mcp/package-cache 下の npm / uv / pip キャッシュを削除します。次回 stdio MCP 起動時に依存関係が再ダウンロードされます。グローバルの ~/.npm には影響しません。';

  @override
  String get mcpStdioCacheResetConfirm => 'リセット';

  @override
  String get mcpStdioCacheResetCancel => 'キャンセル';

  @override
  String get mcpStdioCacheResetDone => '隔離キャッシュをクリアしました。';

  @override
  String get mcpStdioCacheResetFailed =>
      'リセットに失敗しました。~/.openhand/mcp/package-cache を手動で削除してください。';

  @override
  String get pluginServiceTitle => 'プラグイン';

  @override
  String get pluginServiceSubtitle =>
      '任意プラグインのインストール、更新、削除を管理します。プラグインは OpenHand に追加の実行時機能を提供します。';

  @override
  String get pluginServiceRescan => '再スキャン';

  @override
  String get pluginServiceScanning => 'ローカルのプラグイン環境をスキャン中…';

  @override
  String get pluginServiceScanFailed => 'プラグインのスキャンに失敗しました';

  @override
  String get pluginServiceActionInstall => 'インストール';

  @override
  String get pluginServiceActionUpdate => '更新';

  @override
  String get pluginServiceActionUninstall => 'アンインストール';

  @override
  String get pluginServiceActionEnable => '有効化';

  @override
  String get pluginServiceActionDisable => '無効化';

  @override
  String get pluginServiceStatusInstalled => 'インストール済み';

  @override
  String get pluginServiceStatusNotInstalled => '未インストール';

  @override
  String get pluginServiceStatusInstalling => 'インストール中…';

  @override
  String get pluginServiceStatusUpdating => '更新中…';

  @override
  String get pluginServiceStatusUninstalling => 'アンインストール中…';

  @override
  String get pluginServiceStatusError => 'エラー';

  @override
  String get pluginServiceCheckUpdates => '更新を確認';

  @override
  String get pluginServiceMcpService => 'MCP サービス';

  @override
  String pluginServiceInstallDependencyRequired(Object dependency) {
    return '$dependency を先にインストールしてください';
  }

  @override
  String pluginServiceInstallConfirmTitle(Object plugin) {
    return '$plugin をインストールしますか？';
  }

  @override
  String pluginServiceInstallConfirmMessage(Object plugin) {
    return '$plugin をインストールします。依存ファイルをダウンロードする場合があります。';
  }

  @override
  String pluginServiceInstallSuccess(Object plugin) {
    return '$plugin をインストールしました';
  }

  @override
  String pluginServiceInstallFailure(Object plugin) {
    return '$plugin のインストールに失敗しました';
  }

  @override
  String pluginServiceUpdateConfirmTitle(Object plugin) {
    return '$plugin を更新しますか？';
  }

  @override
  String pluginServiceUpdateConfirmMessage(
    Object plugin,
    Object currentVersion,
    Object latestVersion,
  ) {
    return '$plugin を $currentVersion から $latestVersion に更新します。';
  }

  @override
  String pluginServiceUpdateSuccess(Object plugin) {
    return '$plugin を更新しました';
  }

  @override
  String pluginServiceUpdateFailure(Object plugin) {
    return '$plugin の更新に失敗しました';
  }

  @override
  String get pluginServiceCheckUpdateFailed => '更新の確認に失敗しました';

  @override
  String pluginServiceNewVersionAvailable(Object version) {
    return '新しいバージョンがあります: $version';
  }

  @override
  String get pluginServiceNoUpdatesAvailable => '利用可能な更新はありません';

  @override
  String pluginServiceUninstallBlocked(Object dependent, Object plugin) {
    return '$dependent は $plugin に依存しています。先にアンインストールしてください。';
  }

  @override
  String pluginServiceUninstallConfirmTitle(Object plugin) {
    return '$plugin をアンインストールしますか？';
  }

  @override
  String pluginServiceUninstallConfirmMessage(Object plugin) {
    return '$plugin を削除します。この操作は元に戻せません。';
  }

  @override
  String pluginServiceUninstallSuccess(Object plugin) {
    return '$plugin をアンインストールしました';
  }

  @override
  String pluginServiceUninstallFailure(Object plugin) {
    return '$plugin のアンインストールに失敗しました';
  }

  @override
  String pluginServiceOperationTitle(Object action, Object plugin) {
    return '$plugin の$action';
  }

  @override
  String get pluginServiceRuntimePid => 'PID';

  @override
  String get pluginServiceRuntimeOs => 'OS';

  @override
  String get pluginServiceRuntimeArch => 'アーキテクチャ';

  @override
  String pluginServiceLogLineCount(Object count) {
    return 'ログ: $count 行';
  }

  @override
  String get pluginServiceWaitingForOutput => '出力待ち…';

  @override
  String get pluginServiceExecuting => '実行中…';

  @override
  String get pluginServiceCompleted => '完了';

  @override
  String get pluginServiceVersion => 'バージョン';

  @override
  String get pluginServiceUpdateAvailable => '更新先';

  @override
  String get pluginServiceDependsOn => '依存先';

  @override
  String get pluginServiceRequiredBy => '依存元';

  @override
  String get pluginServiceNone => 'なし';

  @override
  String pluginServiceDetailTitle(Object plugin) {
    return '$plugin の詳細';
  }

  @override
  String get pluginServiceDetailBasicInfo => '基本情報';

  @override
  String get pluginServiceDetailName => '名前';

  @override
  String get pluginServiceDetailDescription => '説明';

  @override
  String get pluginServiceDetailStatus => '状態';

  @override
  String get pluginServiceDetailEnvironment => '環境情報';

  @override
  String get pluginServiceDetailFileSystem => 'ファイルシステム';

  @override
  String get pluginServiceDetailDependencies => '依存関係';

  @override
  String get pluginServiceThreadTemplates => 'スレッドテンプレート';

  @override
  String get pluginServiceTemplates => 'テンプレート';

  @override
  String get pluginServiceMcpPackage => 'MCP パッケージ';

  @override
  String get pluginServiceMcpBrowserDescription => 'ブラウザ自動化用の MCP サービス';

  @override
  String get pluginServiceDetailProcessors => 'プロセッサ数';

  @override
  String get pluginServiceDetailInstallPath => 'インストールパス';

  @override
  String get pluginServiceDetailInstallationTarget => 'インストール先';

  @override
  String get pluginServiceDetailInstallMethod => 'インストール方法';

  @override
  String get pluginServiceDetailTargetOs => '対象 OS';

  @override
  String get pluginServiceDetailSupportedPlatforms => '対応プラットフォーム';

  @override
  String get pluginServiceDetailPackageName => 'パッケージ名';

  @override
  String get pluginServiceDetailBinaryName => 'コマンド名';

  @override
  String get pluginServiceDetailRepository => 'リポジトリ';

  @override
  String get pluginServiceDetailDocumentation => '公式ドキュメント';

  @override
  String get pluginServiceDetailInstallCommand => 'インストールコマンド';

  @override
  String get pluginServiceDetailUpgradeCommand => 'アップグレードコマンド';

  @override
  String get pluginServiceDetailUninstallCommand => 'アンインストールコマンド';

  @override
  String get pluginServiceDetailExecutablePath => '実行エントリ';

  @override
  String get pluginServiceDetailCacheDirectory => 'キャッシュディレクトリ';

  @override
  String get pluginServiceDetailNpmGlobalRoot => 'npm グローバルディレクトリ';

  @override
  String get pluginServiceDetailCurrentVersion => '現在のバージョン';

  @override
  String get pluginServiceDetailLatestVersion => '最新バージョン';

  @override
  String get pluginServiceDetailBoundPython => '紐付け Python';

  @override
  String get pluginServiceDetailDesktopAppDetected => 'デスクトップアプリを検出';

  @override
  String get pluginServiceDetailDaemonRunning => 'Daemon 実行中';

  @override
  String get pluginServiceDetailCliAvailable => 'CLI 利用可能';

  @override
  String get pluginServiceDetailDockerContext => 'Docker コンテキスト';

  @override
  String get pluginServiceDetailServerVersion => 'サーバーバージョン';

  @override
  String get pluginServiceDetailDockerOs => 'Docker OS';

  @override
  String get pluginServiceDetailDockerRootDir => 'Docker ルート';

  @override
  String get pluginServiceDetailDaemonName => 'Daemon 名';

  @override
  String get pluginServiceDetailOsType => 'OS タイプ';

  @override
  String get pluginServiceDetailArchitecture => 'アーキテクチャ';

  @override
  String get pluginServiceDetailComposeVersion => 'Compose バージョン';

  @override
  String get pluginServiceDetailDockerDaemonRunning => 'Docker daemon 実行中';

  @override
  String get pluginServiceDetailOpenHandManaged => 'OpenHand 管理';

  @override
  String get pluginServiceDetailContainerId => 'コンテナ ID';

  @override
  String get pluginServiceDetailContainerName => 'コンテナ名';

  @override
  String get pluginServiceDetailContainerStatus => 'コンテナ状態';

  @override
  String get pluginServiceDetailRunning => '実行中';

  @override
  String get pluginServiceDetailStartedAt => '開始時刻';

  @override
  String get pluginServiceDetailFinishedAt => '終了時刻';

  @override
  String get pluginServiceDetailRestartCount => '再起動回数';

  @override
  String get pluginServiceDetailExitCode => '終了コード';

  @override
  String get pluginServiceDetailImage => 'イメージ';

  @override
  String get pluginServiceDetailImageId => 'イメージ ID';

  @override
  String get pluginServiceDetailPorts => 'ポート';

  @override
  String get pluginServiceDetailRestartPolicy => '再起動ポリシー';

  @override
  String get pluginServiceDetailRestEndpoint => 'REST エンドポイント';

  @override
  String get pluginServiceDetailGrpcEndpoint => 'gRPC エンドポイント';

  @override
  String get pluginServiceDetailDataDirectory => 'データディレクトリ';

  @override
  String get pluginServiceDetailHealthResponse => 'ヘルスレスポンス';

  @override
  String get pluginServiceDetailHealthTitle => 'ヘルスタイトル';

  @override
  String get pluginServiceDetailCollectionCount => 'コレクション数';

  @override
  String pluginServiceMcpInstalledVersion(Object version) {
    return 'インストール済み v$version';
  }

  @override
  String get pluginServiceMcpOperationTimeout =>
      '[timeout] 操作がタイムアウトし、プロセスを終了しました';

  @override
  String pluginServiceMcpOperationCompleted(Object action, Object exitCode) {
    return '✓ $action 完了 (exit code: $exitCode)';
  }

  @override
  String pluginServiceMcpOperationFailed(Object action, Object exitCode) {
    return '✗ $action 失敗 (exit code: $exitCode)';
  }

  @override
  String pluginServiceMcpOperationError(Object error) {
    return '✗ エラー: $error';
  }

  @override
  String get pluginServiceMcpVerificationFailed => 'MCP 操作後の状態確認に失敗しました';

  @override
  String get pluginServiceDescriptionNodejs =>
      'JS/TS スクリプトとツールチェーン向けの JavaScript ランタイム';

  @override
  String get pluginServiceDescriptionPlaywright =>
      'Chromium / Firefox / WebKit に対応したブラウザ自動化テストフレームワーク';

  @override
  String get pluginServiceDescriptionHermesAgent =>
      'エージェント編成、自己学習、スキル洗練のための Hermes Agent ランタイム';

  @override
  String get pluginServiceDescriptionPython =>
      'スクリプト、ライブラリ、拡張機能向けの Python ランタイム';

  @override
  String get pluginServiceDescriptionPip =>
      'Python ライブラリのインストール、更新、管理に使うパッケージ管理ツール';

  @override
  String get pluginServiceDescriptionJava =>
      'apktool / jadx などの Android 静的解析ツール向け JDK ランタイム';

  @override
  String get pluginServiceDescriptionFrida =>
      'Android 実行時検証向けの動的インストルメンテーションと Hook ツールチェーン';

  @override
  String get pluginServiceDescriptionMitmproxy =>
      'Web / Android トラフィック調査向けの HTTP(S) プロキシキャプチャツール';

  @override
  String get pluginServiceDescriptionApktool => 'APK 展開と smali 解析ツール';

  @override
  String get pluginServiceDescriptionJadx => 'DEX / APK Java デコンパイラ';

  @override
  String get pluginServiceDescriptionRadare2 =>
      'バイナリ静的解析と ELF / native so リバースエンジニアリングツール';

  @override
  String get pluginServiceDescriptionBlutter =>
      'libapp.so 解析向け Flutter Dart AOT 復元ツール';

  @override
  String get pluginServiceDescriptionDoldrums =>
      'Flutter snapshot / ELF 補助解析ツール';

  @override
  String get pluginServiceDescriptionAnythingAnalyzer =>
      'キャプチャ、解析、Agent 連携向けのプロトコル解析・MCP Server ツール';

  @override
  String get pluginServiceDescriptionDocker =>
      'ローカル Qdrant ベクトルデータベースサービス向けのコンテナランタイム';

  @override
  String get pluginServiceDescriptionQdrant =>
      'ナレッジベースの embedding ベクトル索引と検索に使うローカルベクトルデータベース';

  @override
  String get pluginServiceDescriptionPostgresql =>
      '关系型数据库服务，供 AI 暴露面扫描保存任务与审计数据';

  @override
  String get pluginServiceDescriptionRedis => '内存数据存储服务，供 AI 暴露面扫描执行缓存与任务队列';

  @override
  String get pluginServiceDescriptionDingtalkWorkspaceCli =>
      'DingTalk の AI Agent ワークフロー向け DingTalk Workspace CLI';

  @override
  String get pluginServiceDetailExternalService => '外部服务';

  @override
  String get pluginServiceDetailServiceRunning => '服务运行中';

  @override
  String get pluginServiceDetailEndpoint => '服务端点';

  @override
  String get pluginServiceTemplateWebReverseExpert => 'Web リバースエキスパート';

  @override
  String get pluginServiceTemplateAndroidReverseExpert => 'Android リバースエキスパート';

  @override
  String get pluginServiceTemplateHermesTalker => 'Hermes Talker';

  @override
  String get mcpStdioMirrorModeLabel => 'ミラーレジストリモード';

  @override
  String get mcpStdioMirrorModeBody =>
      'stdio MCP コールドスタート時、中国ミラー (npmmirror / Tsinghua PyPI) を注入するか。auto = システム言語に従う。強制 ON / OFF = locale を無視。OPENHAND_MCP_MIRROR=on/off 环境変数はいつでも上書きします。';

  @override
  String get mcpStdioMirrorModeAuto => '言語に従う';

  @override
  String get mcpStdioMirrorModeForceOn => '強制 ON';

  @override
  String get mcpStdioMirrorModeForceOff => '強制 OFF';

  @override
  String get mcpStdioMirrorModeStatusInjected =>
      '現在有効：npmmirror / Tsinghua PyPI を注入';

  @override
  String get mcpStdioMirrorModeStatusBypassed => '現在有効：ミラー未注入、公式 registry を使用';

  @override
  String mcpStdioMirrorModeStatusReason(Object reason) {
    return '根拠：$reason';
  }

  @override
  String get mcpStdioMirrorModeReasonEnv => 'OPENHAND_MCP_MIRROR 環境変数';

  @override
  String get mcpStdioMirrorModeReasonSetting => '設定で強制';

  @override
  String mcpStdioMirrorModeReasonLocale(Object locale) {
    return 'システム言語 ($locale)';
  }

  @override
  String get mcpStdioMirrorModeReconnectAction => '新しい設定で有効 server を再接続';

  @override
  String get mcpStdioMirrorModeReconnectDone =>
      '再接続をトリガーしました。次回呼び出し時に新しいミラーでプロセスを再起動します。';

  @override
  String mcpStdioDialogLogsTitle(Object name) {
    return '$name ログ';
  }

  @override
  String mcpStdioDialogRuntimeDetailsTitle(Object name) {
    return '$name ランタイム詳細';
  }

  @override
  String mcpStdioDialogRunningPid(Object pid) {
    return '実行中 · PID $pid';
  }

  @override
  String get mcpStdioDialogStopped => '停止済み';

  @override
  String get mcpStdioDialogAutoScroll => '自動スクロール';

  @override
  String get mcpStdioDialogCopyLogs => 'ログをコピー';

  @override
  String get mcpStdioDialogClearLogs => 'ログを消去';

  @override
  String get mcpStdioDialogCopiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get mcpStdioDialogNoLogOutput => 'ログ出力はまだありません';

  @override
  String mcpStdioDialogLineCount(int count) {
    return '$count 行';
  }

  @override
  String mcpStdioDialogUptime(Object uptime) {
    return '稼働 $uptime';
  }

  @override
  String get mcpStdioDialogRefresh => '更新';

  @override
  String get settingsScraplingRuntimeActionInstall => 'インストール';

  @override
  String get settingsScraplingRuntimeActionUninstall => 'アンインストール';

  @override
  String settingsScraplingRuntimeCommand(Object action) {
    return '$action Scrapling ランタイム';
  }

  @override
  String get settingsScraplingRuntimeInstallTitle => 'Scrapling ランタイムをインストール';

  @override
  String get settingsScraplingRuntimeUninstallTitle =>
      'Scrapling ランタイムをアンインストール';

  @override
  String get settingsScraplingRuntimeInstalling => 'インストール中…';

  @override
  String get settingsScraplingRuntimeUninstalling => 'アンインストール中…';

  @override
  String get settingsScraplingRuntimeInstalled => 'インストール済み';

  @override
  String get settingsScraplingRuntimeUninstalled => 'アンインストール済み';

  @override
  String get settingsScraplingRuntimeFailed => '実行に失敗しました';

  @override
  String get settingsScraplingRuntimeCertificateDiagnosis =>
      '診断: 現在の環境の Python / pip は PyPI の証明書チェーンを検証できません。システムの CA 証明書、プロキシの傍受証明書を確認するか、Python に有効な証明書ファイルを設定してください。';

  @override
  String get settingsScraplingRuntimeCopiedAllLogs => 'すべてのログをコピーしました';

  @override
  String get settingsScraplingRuntimeCopyLogs => 'ログをコピー';

  @override
  String get mcpStdioDialogProcessStatus => 'プロセス状態';

  @override
  String get mcpStdioDialogServiceConfig => 'サービス設定';

  @override
  String get mcpStdioDialogType => '種類';

  @override
  String get mcpStdioDialogCommand => 'コマンド';

  @override
  String get mcpStdioDialogArgs => '引数';

  @override
  String get mcpStdioDialogEnabled => '有効';

  @override
  String get mcpStdioDialogYes => 'はい';

  @override
  String get mcpStdioDialogNo => 'いいえ';

  @override
  String get mcpStdioDialogEnvironment => '環境情報';

  @override
  String get mcpStdioDialogError => 'エラー情報';

  @override
  String get mcpStdioDialogDepsTitle => '依存関係管理';

  @override
  String get mcpStdioDialogNoDepsToManage =>
      'このサービスはパッケージ管理型（npx / uvx）ではないため、管理する依存関係はありません。';

  @override
  String mcpStdioDialogInstalledVersion(Object version) {
    return 'インストール済み v$version';
  }

  @override
  String get mcpStdioDialogUnknownVersion => '?';

  @override
  String get mcpStdioDialogNotGloballyInstalled => 'グローバル未インストール';

  @override
  String get mcpStdioDialogInstall => 'インストール';

  @override
  String get mcpStdioDialogUpdate => '更新';

  @override
  String get mcpStdioDialogUninstall => 'アンインストール';

  @override
  String mcpStdioDialogLatestVersion(Object version) {
    return '最新バージョン: $version';
  }

  @override
  String get mcpStdioDialogUpdateAvailableSuffix => '（更新可能）';

  @override
  String get mcpStdioDialogOperationTimeout =>
      '[timeout] 操作がタイムアウトしたため、プロセスを終了しました';

  @override
  String mcpStdioDialogOperationCompleted(
    Object time,
    Object action,
    int exitCode,
  ) {
    return '[$time] ✓ $action 完了 (exit code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationFailed(
    Object time,
    Object action,
    int exitCode,
  ) {
    return '[$time] ✗ $action 失敗 (exit code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationFailedPlain(Object action, int exitCode) {
    return '$action 失敗 (exit code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationException(Object time, Object error) {
    return '[$time] ✗ 例外: $error';
  }

  @override
  String mcpStdioDialogWarmCache(Object time) {
    return '[$time] 分離キャッシュを事前準備中…';
  }

  @override
  String mcpStdioDialogWarmCacheDone(Object time) {
    return '[$time] ✓ キャッシュ準備完了';
  }

  @override
  String mcpStdioDialogWarmCacheSkipped(Object time, Object error) {
    return '[$time] キャッシュ準備をスキップ: $error';
  }

  @override
  String get mcpAutoProbeConcurrencyLabel => 'MCP チェック/取得の並列数';

  @override
  String get mcpAutoProbeConcurrencyBody =>
      'MCP ヘルスチェックまたは Tools 取得を同時に実行するサービス数の上限です。既定は 5。下げるとリソース使用量を抑え、上げると多数のサービス更新を速くできます。';

  @override
  String get mcpAutoProbeConcurrencySave => '並列数を保存';

  @override
  String get mcpAutoProbeConcurrencySaved => 'MCP チェック/取得の並列数を保存しました。';

  @override
  String get mcpAutoProbeConcurrencyInvalid => '1 から 32 までの整数を入力してください。';

  @override
  String get mcpProbeDetailsTitle => 'MCP プローブ詳細';

  @override
  String get mcpProbePoolActive => 'プローブプール稼働中';

  @override
  String get mcpProbePoolIdle => 'プローブプール待機中';

  @override
  String get mcpProbePoolStatusTitle => 'プローブプール状態';

  @override
  String mcpProbeSlots(int active, int total) {
    return 'スロット $active/$total';
  }

  @override
  String mcpProbeQueued(int count) {
    return 'キュー $count';
  }

  @override
  String get mcpProbeStateRunning => '実行中';

  @override
  String get mcpProbeStateIdle => '待機中';

  @override
  String mcpProbeToolsStatus(Object status) {
    return 'ツール $status';
  }

  @override
  String mcpProbeHealthStatus(Object status) {
    return 'ヘルス $status';
  }

  @override
  String mcpProbeLastRun(Object time) {
    return '前回 $time';
  }

  @override
  String mcpProbeNextRun(Object time) {
    return '次回 $time';
  }

  @override
  String get mcpProbeControlsTitle => 'プローブ制御';

  @override
  String get mcpProbeForceProbe => 'プローブを強制実行';

  @override
  String get mcpProbeStopProbing => '現在のプローブを停止';

  @override
  String get mcpProbeReloadServers => 'サービス一覧を再読み込み';

  @override
  String mcpProbeServerStatusTitle(int count) {
    return 'サーバープローブ状態 ($count 件)';
  }

  @override
  String get mcpProbeNoServers => 'サービスなし';

  @override
  String get mcpProbeHealthHealthy => '正常';

  @override
  String get mcpProbeHealthUnhealthy => '異常';

  @override
  String get mcpProbeHealthChecking => '確認中';

  @override
  String get mcpProbeHealthIdle => '未確認';

  @override
  String get mcpProbeDisableServerTooltip => 'このサービスのプローブを無効化';

  @override
  String get mcpProbeEnableServerTooltip => 'このサービスのプローブを有効化';

  @override
  String get mcpProbeNoProbe => 'プローブなし';

  @override
  String mcpProbeToolCount(int count) {
    return '$count 個のツール';
  }

  @override
  String get mcpProbeThisServer => 'このサービスをプローブ';

  @override
  String get mcpRelativeJustNow => 'たった今';

  @override
  String mcpRelativeSecondsAgo(int seconds) {
    return '$seconds 秒前';
  }

  @override
  String mcpRelativeMinutesAgo(int minutes) {
    return '$minutes 分前';
  }

  @override
  String mcpRelativeHoursAgo(int hours) {
    return '$hours 時間前';
  }

  @override
  String mcpRelativeDaysAgo(int days) {
    return '$days 日前';
  }

  @override
  String get mcpRelativeImminent => 'まもなく';

  @override
  String mcpRelativeInSeconds(int seconds) {
    return '約 $seconds 秒後';
  }

  @override
  String mcpRelativeInMinutes(int minutes) {
    return '約 $minutes 分後';
  }

  @override
  String mcpRelativeInHours(int hours) {
    return '約 $hours 時間後';
  }

  @override
  String mcpRelativeInDays(int days) {
    return '約 $days 日後';
  }

  @override
  String get mcpKeywordIndexUpdateModeLabel => 'キーワードインデックスの更新モード';

  @override
  String get mcpKeywordIndexUpdateModeBody =>
      'MCP ツールのキーワード転置インデックスを再構築するタイミングを制御します。コールドスタート：起動時にディスクキャッシュを読み込むのみ。手動更新は「キーワードインデックスを構築」ボタンから。定期間隔：設定した「値＋単位」の周期で再構築し、キャッシュを丸ごと上書きします。毎日定刻：指定時刻に毎日 1 回再構築します。後者 2 つは同じシステム cron タスクを共有し、タスクの断片化を防ぎます。';

  @override
  String get mcpKeywordIndexUpdateModeColdStart => 'コールドスタート';

  @override
  String get mcpKeywordIndexUpdateModeInterval => '定期間隔';

  @override
  String get mcpKeywordIndexUpdateModeScheduled => '毎日定刻';

  @override
  String get mcpKeywordIndexUpdateModeColdStartHint =>
      'コールドスタートモード：起動時にディスク上のキーワードインデックスを読み込むのみ。更新が必要な場合は「キーワードインデックスを構築」を手動で押してください。システム cron タスクは無効のままです。';

  @override
  String get mcpKeywordIndexIntervalValueLabel => '間隔';

  @override
  String get mcpKeywordIndexIntervalUnitLabel => '単位';

  @override
  String get mcpKeywordIndexIntervalUnitMinute => '分';

  @override
  String get mcpKeywordIndexIntervalUnitHour => '時間';

  @override
  String get mcpKeywordIndexIntervalUnitDay => '日';

  @override
  String mcpKeywordIndexScheduledLabel(String time) {
    return '毎日 $time に再構築';
  }

  @override
  String get mcpKeywordIndexScheduledPickAction => '時刻を選択';

  @override
  String get commonClose => '閉じる';

  @override
  String get commonRunInBackground => 'バックグラウンドで実行';

  @override
  String get mcpBuildKeywordIndex => 'キーワード索引を構築';

  @override
  String get mcpKeywordIndexBuildTitle => 'キーワード逆引き索引を構築中';

  @override
  String get mcpKeywordIndexBuildStarting => '準備中…';

  @override
  String mcpKeywordIndexBuildProgress(
    int idx,
    int count,
    Object server,
    int tools,
  ) {
    return '$idx/$count: $server（$tools 件のツールをスキャン）';
  }

  @override
  String mcpKeywordIndexBuildSummary(
    int servers,
    int tools,
    int keys,
    Object sec,
  ) {
    return '$servers サーバ・$tools ツール・$keys キーワードを索引化（${sec}s）';
  }

  @override
  String mcpKeywordIndexBuildSkipped(int n) {
    return '未準備の $n サーバをスキップ';
  }

  @override
  String get mcpKeywordIndexBuildFailed => '構築失敗：';

  @override
  String get mcpLazyLoadingModeLabel => 'MCPツールの遅延読み込み';

  @override
  String get mcpLazyLoadingModeBody =>
      'システムプロンプト内でMCPツールの説明を折り畳むかを制御します。オフ＝常に展開、オン＝常に折り畳みToolSearchで取得、自動＝推定トークン数がしきい値を超えた場合のみ折り畳みます。';

  @override
  String get mcpLazyLoadingModeDisabled => 'オフ';

  @override
  String get mcpLazyLoadingModeAuto => '自動';

  @override
  String get mcpLazyLoadingModeEnabled => 'オン';

  @override
  String get mcpLazyLoadingThresholdLabel => 'MCPツール圧縮しきい値';

  @override
  String get mcpLazyLoadingThresholdBody =>
      '自動モードで、MCPツール説明の推定総トークン数がこの値を超えた場合に遅延読み込みを有効化します。';

  @override
  String get mcpLazyLoadingThresholdSave => 'しきい値を保存';

  @override
  String get mcpLazyLoadingThresholdSaved => 'MCP遅延読み込みのしきい値を保存しました。';

  @override
  String get mcpLazyLoadingThresholdInvalid => '1000～1000000の整数を入力してください。';

  @override
  String get settingsHarnessToolSearchHistoryCapLabel =>
      'Harness ToolSearch 履歴の保持上限';

  @override
  String get settingsHarnessToolSearchHistoryCapBody =>
      'ToolSearch 読み込み済みダイアログが保持する Harness phase の最大件数。超えた分は LRU で逆出されます。';

  @override
  String settingsHarnessToolSearchHistoryCapValue(int cap) {
    return '現在 $cap 件の phase を保持中';
  }

  @override
  String settingsHarnessToolSearchHistoryCapRange(int min, int max) {
    return '範囲: $min–$max（デフォルト 8）';
  }

  @override
  String settingsHarnessToolSearchHistoryCapResetTooltip(int defaultCap) {
    return 'デフォルトにリセット（$defaultCap）';
  }

  @override
  String get harnessCliLoginNoOutputHint =>
      '[ヒント] CLI はまだ出力していません。初期化中か、外部ブラウザでの認証を待っている可能性があります。\n';

  @override
  String harnessCliLoginTimedOut(int minutes) {
    return 'ログインは $minutes 分後にタイムアウトしました。プロセスを停止しました。';
  }

  @override
  String get harnessCliLoginTtyRequiredHint =>
      '[ヒント] この CLI は対話型ログインに実端末 (TTY) が必要な場合があります。\n下の「ターミナルで開く」ボタンからシステムターミナルでログインを完了してください。\n';

  @override
  String harnessCliLoginStreamError(Object error) {
    return '[ストリームエラー: $error]';
  }

  @override
  String harnessCliLoginFailedToStartProcess(Object message) {
    return 'プロセスを開始できません: $message';
  }

  @override
  String harnessCliLoginOpenTerminalError(Object error) {
    return '[ターミナルを開けません: $error]';
  }

  @override
  String get harnessCliLoginStatusFailed => '起動に失敗しました';

  @override
  String get harnessCliLoginStatusStarting => 'ログインフローを開始しています...';

  @override
  String get harnessCliLoginStatusFinished => 'プロセスが終了しました';

  @override
  String harnessCliLoginStatusFinishedWithExit(int exitCode) {
    return 'プロセスが終了しました · 終了コード $exitCode';
  }

  @override
  String get harnessCliLoginStatusWaiting => 'CLI の操作待ちです...';

  @override
  String harnessCliLoginTitle(Object name) {
    return '$name ログイン';
  }

  @override
  String get harnessCliLoginDescription =>
      'このダイアログはアプリ内で CLI ログインフローを実行します。認証中に CLI が外部ブラウザを開く場合があります。';

  @override
  String get harnessCliLoginCopyCommandTooltip => 'コマンドをコピー';

  @override
  String get harnessCliLoginEmptyOutput => 'CLI 出力を待機中...';

  @override
  String get harnessCliLoginInputLabel => '入力を送信';

  @override
  String get harnessCliLoginInputHint => '返信を入力して Enter。空のままなら Enter のみ送信します';

  @override
  String get harnessCliLoginSend => '送信';

  @override
  String get harnessCliLoginSendEsc => 'Esc を送信';

  @override
  String get harnessCliLoginOpenInTerminal => 'ターミナルで開く';

  @override
  String get harnessCliInstallLogSuccess => '✓ インストール成功';

  @override
  String harnessCliInstallLogSuccessWithPath(Object path) {
    return '✓ インストール成功（パス: $path）';
  }

  @override
  String harnessCliInstallLogFailureExitCode(int exitCode) {
    return '✗ インストール失敗（終了コード: $exitCode）';
  }

  @override
  String harnessCliInstallLogStartProcessFailed(Object message) {
    return '✗ インストールプロセスを開始できません: $message';
  }

  @override
  String harnessCliInstallLogGenericError(Object error) {
    return '✗ エラー: $error';
  }

  @override
  String get harnessCliInstallHintInstallNode =>
      '  → 先に Node.js をインストールしてください: https://nodejs.org';

  @override
  String get harnessCliInstallHintRetryAdminButton =>
      '  → 下の「管理者権限で再試行」ボタンをクリックしてください';

  @override
  String harnessCliInstallHintTrySudo(Object command) {
    return '  → 試してください: sudo $command';
  }

  @override
  String get harnessCliInstallHintCheckNetworkDocs =>
      '  → ネットワーク接続を確認するか公式ドキュメントを参照してください';

  @override
  String get harnessCliInstallHintInstallPipx =>
      '  → 先に pipx をインストールしてください: https://pipx.pypa.io/stable/installation/';

  @override
  String get harnessCliInstallHintUsePipInstallUserAider =>
      '    または使用: pip install --user aider-chat';

  @override
  String get harnessCliInstallHintHomebrewNoSudo =>
      '  → Homebrew は通常 sudo でインストールしません。ディレクトリ権限を確認してください';

  @override
  String get harnessCliInstallHintHomebrewFix =>
      '  → 修正案: https://docs.brew.sh/FAQ#why-does-homebrew-say-sudo-is-not-allowed';

  @override
  String get harnessCliInstallHintInstallPython =>
      '  → 先に Python をインストールしてください: https://www.python.org';

  @override
  String harnessCliInstallHintPipInstallUser(Object packageName) {
    return '  → 試してください: pip install --user $packageName';
  }

  @override
  String harnessCliInstallHintOfficialDocs(Object url) {
    return '  → 公式ドキュメント: $url';
  }

  @override
  String get harnessCliInstallLogCancelled => '⚠ インストールはキャンセルされました';

  @override
  String get harnessCliInstallWindowsAdminManual =>
      '管理者権限の PowerShell で手動実行してください:';

  @override
  String harnessCliInstallAdminCommand(Object command) {
    return '> [管理者] $command';
  }

  @override
  String get harnessCliInstallAdminTimeout =>
      '✗ 管理者認証ダイアログがタイムアウトしたか起動に失敗したため、osascript 子プロセスを強制終了しました';

  @override
  String get harnessCliInstallUserCancelledAuth => '⚠ 認証がキャンセルされました';

  @override
  String get harnessCliInstallAdminPermissionFailed => '✗ 管理者権限を取得できません';

  @override
  String harnessCliInstallPathMissingWarning(Object executable) {
    return '⚠ インストールは完了しましたが、現在の PATH で $executable が見つかりません';
  }

  @override
  String get harnessCliInstallRestartPathHint =>
      '  → OpenHand を再起動するか、ターミナルから起動して新しい PATH を読み込んでください';

  @override
  String get harnessCliInstallTimeoutManual =>
      '✗ インストールがタイムアウトしました（5 分超）。手動で実行してください:';

  @override
  String harnessCliInstallOsascriptStartFailed(Object message) {
    return '✗ osascript を開始できません: $message';
  }

  @override
  String get harnessCliInstallLinuxSudoManual =>
      'ターミナルで手動実行してください（root 権限が必要）:';

  @override
  String get harnessCliInstallStatusInstalling => 'インストール中...';

  @override
  String get harnessCliInstallStatusSuccess => 'インストール成功';

  @override
  String get harnessCliInstallStatusCancelled => 'キャンセル済み';

  @override
  String get harnessCliInstallStatusFailed => 'インストール失敗';

  @override
  String harnessCliInstallTitle(Object name) {
    return '$name をインストール';
  }

  @override
  String get harnessCliInstallCopyDocUrl => 'ドキュメント URL をコピー';

  @override
  String get harnessCliInstallCancel => 'インストールをキャンセル';

  @override
  String get harnessCliInstallRetryAdmin => '管理者権限で再試行';

  @override
  String get harnessCliInstallDoneContinue => '完了して続行';

  @override
  String get settingsToolSearchReplayCancelWindowLabel => 'リプレイキャンセルされるまでの待ち時間';

  @override
  String get settingsToolSearchReplayCancelWindowBody =>
      'snackbar が送信するまでの秒数。期間中にキャンセルを押すとキャンセルされます。';

  @override
  String settingsToolSearchReplayCancelWindowValue(int seconds) {
    return 'ウィンドウ：$seconds 秒';
  }

  @override
  String settingsToolSearchReplayCancelWindowRange(int min, int max) {
    return '範囲：$min–$max 秒（デフォルト 3）';
  }

  @override
  String settingsToolSearchReplayCancelWindowResetTooltip(int defaultSeconds) {
    return 'デフォルトにリセット（$defaultSeconds 秒）';
  }

  @override
  String get mcpLazyLoadingHowItWorks =>
      '遅延読み込みが有効な間、MCP ツールの説明は名前インデックスに折りたたまれ、組み込みの ToolSearch ツールが必要に応じて完全な JSON Schema を取得します。3 つのクエリ形式に対応：\n• select:NAME（直接選択、空白区切りで複数指定可）\n• キーワード（name/description にスコアリング）\n• +KEYWORD（ノイズ除去のための必須語）\n一致後は、正確な tool_name と Schema に準拠した arguments を ToolSearch に渡します。ネイティブツール一覧は固定され、プロンプトキャッシュが維持されます。';

  @override
  String get settingsGeneralSubtitle => 'テーマ、言語、アプリの基本情報を管理します。';

  @override
  String get settingsAiSubtitle => 'チャットモデル、認証、プロトコルアダプターを管理します。';

  @override
  String get settingsActiveToolCallsTitle => '実行中のツール呼び出し';

  @override
  String get settingsActiveToolCallsBody =>
      'ディスパッチされた全てのツール呼び出しをリアルタイム表示します。PID、種別、属するセッション、経過時間を含み、Stop でその呼び出しだけを中止できます。';

  @override
  String get settingsActiveToolCallsEmpty => '現在実行中のツール呼び出しはありません。';

  @override
  String get settingsActiveToolCallsCancel => '停止';

  @override
  String get settingsActiveToolKindBuiltin => '内蔵';

  @override
  String get settingsActiveToolKindMcp => 'MCP';

  @override
  String get settingsActiveToolKindSkill => 'Skill';

  @override
  String get settingsActiveToolSessionLabel => 'セッション';

  @override
  String get settingsToolHardeningTitle => 'ツール保護パラメータ';

  @override
  String get settingsToolHardeningBody =>
      'サブプロセスの graceful shutdown 時間、bash 出力上限、同時ツール呼び出し上限。';

  @override
  String get settingsSubprocessGracefulShutdownLabel =>
      'サブプロセス graceful shutdown（ミリ秒）';

  @override
  String get settingsSubprocessGracefulShutdownBody =>
      'SIGTERM と SIGKILL の間の待機時間。大きいほど丁寧だが、Stop の反応が遅くなります。範囲 100–5000。';

  @override
  String get settingsBashOutputMaxBytesLabel => 'Bash キャプチャ上限（文字）';

  @override
  String get settingsBashOutputMaxBytesBody =>
      '1 回の bash 呼び出しで取得する stdout+stderr の合計上限。超えると中央を切り詰め、頭と末尾を保持します。範囲 16000–4000000。';

  @override
  String get settingsMaxConcurrentToolsLabel => '並行ツール呼び出し上限';

  @override
  String get settingsMaxConcurrentToolsBody =>
      '同一セッションで並行してディスパッチされるツール呼び出しの最大数。範囲 1–64。';

  @override
  String get settingsToolHardeningInvalid => '範囲内の整数を入力してください';

  @override
  String get settingsSkillsSubtitle =>
      'ローカルのスキルディレクトリ、テンプレート作成、インストール済みスキルを管理します。';

  @override
  String get settingsMemorySubtitle => 'ユーザーメモリのスイッチと永続化ファイルパスを管理します。';

  @override
  String get settingsPersistenceInvalidTitle => '設定データが破損しています';

  @override
  String get settingsPersistenceInvalidBody =>
      'データベースのレコードを解析できません。元のデータを上書きせず、安全な既定値を表示します。';

  @override
  String get settingsPersistenceLoadFailedTitle => '設定の読み込みに失敗しました';

  @override
  String get settingsPersistenceLoadFailedBody =>
      'ローカルデータベースを読み込めません。既存データを保護するため、一時的に既定値を表示し保存を停止します。';

  @override
  String get settingsPersistenceSaveFailedTitle => '設定の保存に失敗';

  @override
  String get settingsPersistenceSaveFailedBody =>
      '設定データベースへの書き込みに失敗しました。UI は最後に有効だった設定へ戻されました。データベースのアクセス権とディスク状態を確認してください。';

  @override
  String get settingsPersistenceDismiss => '閉じる';

  @override
  String get settingsAnimationRestoreDefaultsTitle => '既定のアニメーションに戻す';

  @override
  String get settingsAnimationRestoreDefaultsSubtitle =>
      'ダイアログ、メニュー、ページ/モジュール、ワークスペースパネル、チップ、リスト項目の入場/退場スタイル、時間、カーブを OpenHand 推奨値に戻します。';

  @override
  String get settingsAnimationRestoreDefaultsButton => '既定に戻す';

  @override
  String get settingsAnimationRestoreConfirmTitle => '既定のアニメーションに戻しますか？';

  @override
  String get settingsAnimationRestoreConfirmMessage =>
      'ダイアログ、メニュー、ページ/モジュール、ワークスペースパネル、チップ、リスト項目のアニメーションをすべて既定値に戻します。カスタム値は上書きされます。';

  @override
  String get settingsAnimationRestoreConfirm => '戻す';

  @override
  String get settingsAnimationRestoreSuccess => '既定のアニメーションに戻しました';

  @override
  String get settingsDialogAnimationTitle => 'ダイアログアニメーション';

  @override
  String get settingsDialogAnimationSubtitle =>
      'すべてのダイアログの入場/退場スタイル、時間、カーブを設定します。';

  @override
  String get settingsMenuAnimationTitle => 'メニューアニメーション';

  @override
  String get settingsMenuAnimationSubtitle =>
      'ポップアップ、コンテキスト、ドロップダウンメニューの入場/退場スタイル、時間、カーブを設定します。';

  @override
  String get settingsPanelAnimationTitle => 'ワークスペースパネルアニメーション';

  @override
  String get settingsPanelAnimationSubtitle =>
      '左側のナビ/ファイル、右側の会話/エディタなど、ワークスペースパネルの切り替えを設定します。右側モジュールはページアニメーションで制御します。';

  @override
  String get settingsPageAnimationTitle => 'ページ / モジュールアニメーション';

  @override
  String get settingsPageAnimationSubtitle =>
      'Workspace、設定、MCP、メモリ、Hooks、Crons、スキル、自動化など、右側メインコンテンツの切り替えを設定します。';

  @override
  String get settingsChipAnimationTitle => 'チップアニメーション';

  @override
  String get settingsChipAnimationSubtitle =>
      '選択スキル、添付、プロジェクト参照、キュー内メッセージ、編集ピルなど、閉じられるチップの入場/退場アニメーションを設定します。';

  @override
  String get settingsListItemAnimationTitle => 'リスト項目アニメーション';

  @override
  String get settingsListItemAnimationSubtitle =>
      'MCP サーバー、メモリ、指示カード、サイドバーのスレッド、ツール呼び出しカードなど、リスト項目の入場アニメーションを設定します。';

  @override
  String get settingsAnimationEnter => '入場';

  @override
  String get settingsAnimationExit => '退場';

  @override
  String get settingsAnimationDuration => '時間';

  @override
  String get settingsAnimationCurve => 'カーブ';

  @override
  String get dialogAnimationStyleNone => 'なし';

  @override
  String get dialogAnimationStyleFade => 'フェード';

  @override
  String get dialogAnimationStyleFadeScale => 'フェード + スケール';

  @override
  String get dialogAnimationStyleSlideUp => '下からスライド';

  @override
  String get dialogAnimationStyleSlideDown => '上からスライド';

  @override
  String get dialogAnimationStyleSlideLeft => '左からスライド';

  @override
  String get dialogAnimationStyleSlideRight => '右からスライド';

  @override
  String get dialogAnimationStyleExpand => '展開';

  @override
  String get dialogAnimationStyleRotateScale => '回転 + スケール';

  @override
  String get dialogAnimationStyleElastic => 'エラスティック';

  @override
  String get dialogAnimationStyleSpringScale => 'スプリングスケール';

  @override
  String get dialogAnimationStyleFlipX => 'Flip X';

  @override
  String get dialogAnimationCurveEaseInOut => 'Ease In-Out';

  @override
  String get dialogAnimationCurveEaseOut => 'Ease Out';

  @override
  String get dialogAnimationCurveEaseOutCubic => 'Ease Out Cubic';

  @override
  String get dialogAnimationCurveEaseInOutCubicEmphasized => 'Cubic 強調';

  @override
  String get dialogAnimationCurveElasticOut => 'Elastic Out';

  @override
  String get dialogAnimationCurveBounceOut => 'Bounce Out';

  @override
  String get dialogAnimationCurveDecelerate => '減速';

  @override
  String get commonOptional => '任意';

  @override
  String get cronScriptTypeCommand => 'コマンド';

  @override
  String get cronScriptTypeScript => 'スクリプト';

  @override
  String get cronScriptTypeAgent => 'Agent';

  @override
  String get cronJobStatusRunning => '実行中';

  @override
  String get cronJobStatusPaused => '一時停止';

  @override
  String get cronJobStatusFailed => '失敗';

  @override
  String get cronJobStatusError => 'エラー';

  @override
  String get cronJobStatusIdle => '待機中';

  @override
  String get cronNotifyTypeNone => 'なし';

  @override
  String get cronNotifyTypeLog => 'ログのみ';

  @override
  String get cronNotifyTypeSystem => 'システム通知';

  @override
  String get cronNotifyTypeAppNotification => 'アプリ内通知';

  @override
  String get cronNotifySeverityInfo => '情報';

  @override
  String get cronNotifySeveritySuccess => '成功';

  @override
  String get cronNotifySeverityWarning => '警告';

  @override
  String get cronNotifySeverityError => 'エラー';

  @override
  String get cronNotifySeverityCritical => '重大';

  @override
  String get cronParserFieldCountError =>
      'Cron 式は 5 フィールド（分 時 日 月 曜日）である必要があります';

  @override
  String get cronParserFieldMinute => '分';

  @override
  String get cronParserFieldHour => '時';

  @override
  String get cronParserFieldDayOfMonth => '日';

  @override
  String get cronParserFieldDayOfMonthShort => '日';

  @override
  String get cronParserFieldMonth => '月';

  @override
  String get cronParserFieldDayOfWeek => '曜日';

  @override
  String get cronParserFieldDayOfWeekShort => '曜';

  @override
  String cronParserInvalidField(String field, String value) {
    return '$field フィールド \"$value\" が無効です';
  }

  @override
  String get cronsViewDescription =>
      'スケジュールタスクを設定、管理します。Cron 式、タイムアウト、自動再試行、実行履歴に対応します。';

  @override
  String get cronsNewCronJob => '新規 Cron ジョブ';

  @override
  String get cronsEditCronJob => 'Cron ジョブを編集';

  @override
  String get cronsDeleteCronJobTitle => 'Cron ジョブを削除';

  @override
  String cronsDeleteCronJobMessage(String name) {
    return '\"$name\" を削除しますか？この操作は元に戻せません。実行履歴も削除されます。';
  }

  @override
  String get cronsEmptyTitle => 'Cron ジョブはまだありません';

  @override
  String get cronsEmptyBody => '上の「新規 Cron ジョブ」から設定を開始します。';

  @override
  String get cronsCronExpressionTooltip => 'Cron 式';

  @override
  String get cronsTimeoutTooltip => 'タイムアウト';

  @override
  String get cronsRetryCountTooltip => '再試行回数';

  @override
  String get cronsMcpKeywordIndexLockedTooltip =>
      '設定 -> MCP -> キーワードインデックス更新モードで制御されます';

  @override
  String get cronsRunOnceNow => '今すぐ 1 回実行';

  @override
  String get cronsHistory => '履歴';

  @override
  String cronsLastRunAt(String time) {
    return '前回: $time';
  }

  @override
  String get cronsFieldName => '名前';

  @override
  String get cronsFieldNameHint => '例: 毎日バックアップ';

  @override
  String get cronsFieldDescription => '説明';

  @override
  String get cronsFieldType => '種類';

  @override
  String get cronsFieldScriptFilePath => 'スクリプトファイルパス';

  @override
  String get cronsFieldScriptFilePathHint => '.sh / .ps1 / .bat ファイルを選択';

  @override
  String get cronsBrowse => '参照';

  @override
  String get cronsFieldCommand => 'コマンド';

  @override
  String get cronsFieldCommandHintWindows => 'PowerShell / BAT コマンドを入力';

  @override
  String get cronsFieldCommandHintShell => 'Shell コマンドを入力';

  @override
  String get cronsCronSchedule => 'Cron スケジュール';

  @override
  String get cronsCronScheduleHelper =>
      '秒フィールドは 0 固定です。最小粒度は分です。形式: 分 時 日 月 曜日';

  @override
  String get cronsTimeoutSeconds => 'タイムアウト（秒）';

  @override
  String get cronsRetries => '再試行';

  @override
  String get cronsMaxRetryDelaySeconds => '最大再試行間隔（秒）';

  @override
  String get cronsRunAsUser => '実行ユーザー';

  @override
  String get cronsDefaultCurrentUser => 'デフォルト（現在のユーザー）';

  @override
  String get cronsDefault => 'デフォルト';

  @override
  String get cronsTagsCommaSeparated => 'タグ（カンマ区切り）';

  @override
  String get cronsTagsHint => '例: backup, cleanup';

  @override
  String get cronsWorkingDirectory => '作業ディレクトリ';

  @override
  String get cronsWorkingDirectoryHint => '任意。未指定時はアプリのディレクトリ';

  @override
  String get cronsEnvironmentVariables => '環境変数';

  @override
  String get cronsEnvironmentVariablesHint => '1 行に 1 つ、形式: KEY=VALUE';

  @override
  String get cronsExecutionContextCollection => '実行コンテキスト収集';

  @override
  String get cronsCollectAppMetadata => 'アプリ情報を収集';

  @override
  String get cronsCollectAppMetadataSubtitle => 'アプリバージョン、PID、実行ファイルパスなどを記録します';

  @override
  String get cronsCollectHostMetadata => 'ホスト情報を収集';

  @override
  String get cronsCollectHostMetadataSubtitle =>
      'OS バージョン、ホスト名、CPU コア数などを記録します';

  @override
  String get cronsCollectEnvironmentSnapshot => '環境スナップショットを収集';

  @override
  String get cronsCollectEnvironmentSnapshotSubtitle =>
      '実行時の有効な環境変数を記録します（機密情報を含む場合があります）。';

  @override
  String get cronsSensitive => '機密';

  @override
  String get cronsNotificationSettings => '通知設定';

  @override
  String get cronsTestNotification => '通知をテスト';

  @override
  String get cronsTestSuccessNotification => '成功通知をテスト';

  @override
  String get cronsTestFailureNotification => '失敗通知をテスト';

  @override
  String get cronsTestTimeoutNotification => 'タイムアウト通知をテスト';

  @override
  String get cronsTestAllNotifications => 'すべてテスト（順番）';

  @override
  String get cronsNotificationSettingsHelper =>
      'イベントごとに通知チャネル、重要度、音、振動を個別に設定できます。';

  @override
  String get cronsOnSuccess => '成功時';

  @override
  String get cronsOnFailure => '失敗時';

  @override
  String get cronsOnTimeout => 'タイムアウト時';

  @override
  String get cronsEnabled => '有効';

  @override
  String get cronsCustomNotificationMessageHint => 'カスタム通知内容（任意）';

  @override
  String get cronsVibrationUnsupportedHint =>
      'このプラットフォームは振動に対応していないため、オンでも無視されます。';

  @override
  String get cronsValidationNameRequired => 'Cron ジョブ名を入力してください。';

  @override
  String get cronsValidationScriptRequired => 'スクリプトファイルを選択してください。';

  @override
  String get cronsValidationCommandRequired => 'コマンドを入力してください。';

  @override
  String cronsValidationInvalidEnvironment(String lines) {
    return '環境変数の形式が無効です。$lines 行目を確認してください。形式は KEY=VALUE です。';
  }

  @override
  String get cronsNotificationSequentialStartTitle => '順次テストを開始';

  @override
  String get cronsNotificationSequentialStartBody =>
      '成功、失敗、タイムアウト通知を順番にテストします。';

  @override
  String get cronsNotificationVibrationIgnoredTitle => '振動を無視しました';

  @override
  String get cronsNotificationSequentialVibrationIgnoredBody =>
      'このプラットフォームは振動に対応していないため、順次テスト中に無視されました。';

  @override
  String get cronsNotificationSequentialCompletedTitle => '順次テスト完了';

  @override
  String get cronsNotificationSequentialCompletedBody =>
      '成功、失敗、タイムアウトの通知テストが完了しました。';

  @override
  String get cronsNotificationScenarioSuccess => '成功';

  @override
  String get cronsNotificationScenarioFailure => '失敗';

  @override
  String get cronsNotificationScenarioTimeout => 'タイムアウト';

  @override
  String get cronsNotificationScenarioAll => 'すべて';

  @override
  String cronsNotificationTestTitle(String label) {
    return 'Cron 通知テスト - $label';
  }

  @override
  String get cronsNotificationTestDefaultBodySuccess => '成功シナリオの通知テストメッセージです。';

  @override
  String get cronsNotificationTestDefaultBodyFailure => '失敗シナリオの通知テストメッセージです。';

  @override
  String get cronsNotificationTestDefaultBodyTimeout =>
      'タイムアウトシナリオの通知テストメッセージです。';

  @override
  String get cronsNotificationNoEmitBody =>
      '現在の設定は「なし」または「ログのみ」のため、通知は送信されません。';

  @override
  String get cronsSystemNotificationUnavailableTitle => 'システム通知を利用できません';

  @override
  String get cronsSystemNotificationFallbackBody =>
      'システム通知に失敗したため、アプリ内通知に切り替えました。';

  @override
  String get cronsNotificationVibrationIgnoredBody =>
      'このプラットフォームは振動に対応していないため、無視されました。';

  @override
  String get cronsUnknownPlatform => '不明なプラットフォーム';

  @override
  String get cronsToggleOn => 'オン';

  @override
  String get cronsToggleOff => 'オフ';

  @override
  String get cronsSupportBestEffortSystemSound => '対応（可能な範囲でシステム音）';

  @override
  String get cronsSupportSupported => '対応';

  @override
  String get cronsSupportNotSupportedOnPlatform => 'このプラットフォームでは非対応';

  @override
  String get cronsSupportNotSupportedWillBeIgnored => '非対応（無視されます）';

  @override
  String get cronsSoundLabel => '音';

  @override
  String get cronsVibrationLabel => '振動';

  @override
  String get cronsPlatformLabel => 'プラットフォーム';

  @override
  String get cronsSupportLabel => '対応状況';

  @override
  String get cronsExecutionHistoryTitle => '定時タスク実行履歴';

  @override
  String get cronsClearAllExecutionHistory => 'すべての実行履歴を消去';

  @override
  String get cronsNoExecutionRecords => '実行記録はまだありません';

  @override
  String get cronsClearExecutionHistoryTitle => '実行履歴を消去';

  @override
  String cronsClearExecutionHistoryMessage(String name) {
    return '「$name」の実行履歴をすべて消去しますか？この操作は元に戻せません。';
  }

  @override
  String get cronsClear => '消去';

  @override
  String get cronsDeleteExecutionRecordTitle => '実行記録を削除';

  @override
  String get cronsDeleteExecutionRecordMessage => 'この実行記録を削除しますか？';

  @override
  String get cronsExecutionStatusSuccess => '成功';

  @override
  String get cronsExecutionStatusFailed => '失敗';

  @override
  String get cronsExecutionStatusTimedOut => 'タイムアウト';

  @override
  String get cronsExecutionStatusRunning => '実行中';

  @override
  String get cronsExecutionStatusKilled => '終了済み';

  @override
  String get cronsTriggerManual => '手動';

  @override
  String get cronsTriggerScheduled => 'スケジュール';

  @override
  String get cronsDeleteThisRecord => 'この記録を削除';

  @override
  String get cronsRetryAttempt => '再試行回数';

  @override
  String get cronsRunAs => '実行ユーザー';

  @override
  String get cronsWorkingDir => '作業ディレクトリ';

  @override
  String get cronsScriptEnvironmentOverrides => 'スクリプト環境の上書き:';

  @override
  String get cronsEnvironmentSnapshot => '環境スナップショット:';

  @override
  String get cronsErrorReason => 'エラー:';

  @override
  String get cronsStdout => '標準出力 (stdout):';

  @override
  String get cronsStderr => '標準エラー (stderr):';

  @override
  String get cronsExecutionContext => '実行コンテキスト:';

  @override
  String get cronsHermesTalkerReportTitle => 'Hermes Talker レポート';

  @override
  String get cronsHermesNoEligibleSessions => '今回の実行では学習対象のセッションはありませんでした。';

  @override
  String cronsHermesAffectedSessions(int count) {
    return '影響を受けたセッション ($count)';
  }

  @override
  String cronsHermesStatsLine(
    int scanned,
    int triggered,
    int skipped,
    int errors,
  ) {
    return 'スキャン $scanned · トリガー $triggered · スキップ $skipped · エラー $errors';
  }

  @override
  String get cronsHermesUntitledSession => '(無題のセッション)';

  @override
  String cronsHermesMemoryUpdates(int count) {
    return '記憶 +$count';
  }

  @override
  String cronsHermesMemoryErrors(int count) {
    return '記憶エラー $count';
  }

  @override
  String cronsHermesSkillUpdates(int count) {
    return 'スキル +$count';
  }

  @override
  String cronsHermesSkillErrors(int count) {
    return 'スキルエラー $count';
  }

  @override
  String cronsHermesProfileChanges(int count) {
    return 'プロフィール $count';
  }

  @override
  String cronsHermesToolRounds(int count) {
    return 'ツールラウンド $count';
  }

  @override
  String get cronsHermesModelLabel => 'モデル';

  @override
  String get cronsHermesProviderLabel => 'プロバイダー';

  @override
  String get cronsHermesTerminatedLabel => '終了理由';

  @override
  String get cronsHermesUserProfileChanges => 'ユーザープロフィールの変更';

  @override
  String get cronsHermesMemoryChanges => '記憶の変更';

  @override
  String get cronsHermesSkillChanges => 'スキルの変更';

  @override
  String get cronsHermesAiReasoningOnScene => '当時の AI 推論';

  @override
  String get cronsHermesAiResponseOnScene => '当時の AI 応答';

  @override
  String get cronsHermesNoFurtherDetails => '追加の詳細はありません。';

  @override
  String get cronsHermesStatusError => 'エラー';

  @override
  String get cronsHermesStatusSkipped => 'スキップ';

  @override
  String get cronsHermesStatusOk => '完了';

  @override
  String get cronsHermesChangeBefore => '変更前';

  @override
  String get cronsHermesChangeAfter => '変更後';

  @override
  String get cronsHermesChangeValue => '値';

  @override
  String get cronsHermesChangeSource => 'ソース';

  @override
  String get cronsHermesChangeReason => '理由';

  @override
  String get cronsHermesChangeMetadata => 'メタデータ';

  @override
  String get cronsHermesChangeError => 'エラー';

  @override
  String get cronsCollapse => '折りたたむ';

  @override
  String get cronsExpand => '展開';

  @override
  String get aiModelAdd => 'プロバイダーを追加';

  @override
  String get aiModelsEmptyTitle => 'まだモデルプロバイダーがありません';

  @override
  String get aiModelsEmptyBody =>
      'ここで少なくとも 1 つのモデルプロバイダー設定を追加すると、スレッドの作成画面でそのまま再利用できます。';

  @override
  String get aiModelDialogCreateTitle => 'モデルプロバイダーを追加';

  @override
  String get aiModelDialogEditTitle => 'モデルプロバイダーを編集';

  @override
  String get aiModelBaseUrl => 'ベース URL';

  @override
  String get aiModelBaseUrlRequired => 'Base URL を入力してください。';

  @override
  String get aiModelBaseUrlInvalid => '有効な Base URL を入力してください。';

  @override
  String get aiModelOfficialWebsiteUrl => '公式サイト URL（任意）';

  @override
  String get aiModelOfficialWebsiteUrlHint => 'https://example.com';

  @override
  String get aiModelOfficialWebsiteUrlInvalid => '有効な公式サイト URL を入力してください。';

  @override
  String get aiModelOpenWebsiteFailure => '公式サイトを開けませんでした。';

  @override
  String get aiModelOpenWebsiteTooltip => '公式サイトを開く';

  @override
  String get aiModelAuthScheme => '認証方式';

  @override
  String get aiModelToken => 'トークン';

  @override
  String get aiModelProtocol => 'プロトコル';

  @override
  String get aiModelSaveSuccess => 'モデルプロバイダー設定を保存しました。';

  @override
  String get aiModelDeleteConfirmTitle => 'モデルプロバイダーを削除';

  @override
  String get aiModelDeleteConfirmBody => 'このモデルプロバイダー設定を削除しますか？';

  @override
  String get aiModelDeleteSuccess => 'モデルプロバイダー設定を削除しました。';

  @override
  String get aiModelMoveUp => '上へ移動';

  @override
  String get aiModelMoveDown => '下へ移動';

  @override
  String get aiModelSelected => 'アクティブなモデルプロバイダー';

  @override
  String get aiModelNoToken => 'トークン未設定';

  @override
  String get aiModelTest => 'テスト';

  @override
  String get aiModelTesting => 'テスト中';

  @override
  String aiModelTestSuccess(String modelName) {
    return '$modelName のテストに合格しました。';
  }

  @override
  String aiModelTestFailure(String modelName, String reason) {
    return '$modelName のテストに失敗しました：$reason';
  }

  @override
  String get aiModelSelectionRequired => 'まず設定で AI モデルプロバイダーを追加して選択してください。';

  @override
  String get aiModelScanButton => 'モデルをスキャン';

  @override
  String get aiModelScanning => '利用可能なモデルをスキャン中…';

  @override
  String get aiModelAvailableModels => '利用可能なモデル';

  @override
  String get aiModelManualIdHint => 'モデル ID を手動で追加';

  @override
  String get aiModelManualIdAdd => '追加';

  @override
  String aiModelCount(int count) {
    return '$count モデル';
  }

  @override
  String get chatModelButton => 'モデルを選択';

  @override
  String get aiAuthNone => 'なし';

  @override
  String get aiAuthBearer => 'ベアラー';

  @override
  String get aiAuthToken => 'トークン';

  @override
  String get aiAuthApiKey => 'API キー';

  @override
  String get aiProtocolOpenAi => 'オープンAI';

  @override
  String get aiProtocolDots => 'Dots (小紅書)';

  @override
  String get aiProtocolClaude => 'クロード';

  @override
  String get aiProtocolGemini => 'ジェミニ';

  @override
  String get aiProtocolDeepSeek => 'ディープシーク';

  @override
  String get aiProtocolKimi => 'キミ';

  @override
  String get aiProtocolGlm => 'GLM';

  @override
  String get aiProtocolGrok => 'グロック';

  @override
  String get aiProtocolOllama => 'オラマ';

  @override
  String get aiProtocolVllm => 'vLLM';

  @override
  String get aiProtocolSglang => 'SGLang';

  @override
  String get aiProtocolQwen => 'クウェン';

  @override
  String get aiProtocolSeed => 'シード（豆包）';

  @override
  String get aiProtocolStepFun => 'ステップファン';

  @override
  String get aiProtocolMinimax => 'ミニマックス';

  @override
  String get aiProtocolLongCat => 'ロングキャット';

  @override
  String get aiProtocolAgnes => 'Agnes';

  @override
  String get aiProtocolJoyCode => 'ジョイコード';

  @override
  String get aiProtocolWenxin => '文心 / ERNIE';

  @override
  String get aiProtocolMeta => 'Meta AI / ラマ';

  @override
  String get aiProtocolMimo => 'MIMO';

  @override
  String get aiProtocolHunyuan => '混元';

  @override
  String get skillsPageTitle => 'スキル';

  @override
  String get skillsPageSubtitle =>
      'OpenHand の拡張性を高めるため、ローカルにインストールされたスキルとテンプレートを一元管理します。';

  @override
  String get skillsSearchHint => 'スキルを検索';

  @override
  String get skillsRefresh => '更新';

  @override
  String get skillsOpenDirectory => 'ディレクトリを開く';

  @override
  String get skillsImport => 'スキルを取り込む';

  @override
  String get skillsNewSkill => '新規スキル';

  @override
  String get skillsEmptyTitle => 'まだスキルがありません';

  @override
  String get skillsEmptyBody =>
      '現在のスキルディレクトリに SKILL.md が見つかりません。テンプレートを作成するか、既存のスキルディレクトリに切り替えてください。';

  @override
  String get skillsNoResultsTitle => '一致するスキルが見つかりません';

  @override
  String get skillsNoResultsBody => '検索キーワードを変更するか、検索をクリアしてすべてのスキルを再表示してください。';

  @override
  String get skillTemplateCreated => '新しいスキルテンプレートを作成しました';

  @override
  String get skillOperationFailed => 'スキル操作に失敗しました。しばらくしてから再試行してください。';

  @override
  String get skillsImportSuccess => 'スキルを取り込みました';

  @override
  String get skillsEdit => 'スキルを編集';

  @override
  String get skillsDelete => 'スキルを削除';

  @override
  String get skillsPreviewClose => '閉じる';

  @override
  String get skillsEditorLabel => 'SKILL.md の内容';

  @override
  String get skillsCreateDialogTitle => 'スキルを作成';

  @override
  String get skillsCreateNameLabel => 'スキル名';

  @override
  String get skillsCreateNameRequired => 'スキル名を入力してください。';

  @override
  String get skillsCreateIconLabel => 'スキルのアイコン';

  @override
  String get skillsCreateIconHint => '絵文字またはローカル画像を選択してください。';

  @override
  String get skillsCreateIconRequired => 'アイコンを選択してください。';

  @override
  String get skillsCreateIconChoose => '絵文字を選択';

  @override
  String get skillsCreateIconChange => '変更';

  @override
  String get skillsCreateImageChoose => '画像を選択';

  @override
  String get skillsCreateImageChange => '画像を置き換え';

  @override
  String get skillsCreateImageSelected => 'ローカル画像を選択しました';

  @override
  String get skillsCreateDescriptionLabel => '短い説明';

  @override
  String get skillsCreateDescriptionRequired => '短い説明を入力してください。';

  @override
  String get skillsCreateContentRequired => 'SKILL.md の内容を入力してください。';

  @override
  String get imageEditorTitle => '画像を編集';

  @override
  String get imageEditorCropHint =>
      '画像をドラッグして正方形のクロップ範囲を移動し、ズーム・回転・明るさ・コントラストを調整します。';

  @override
  String get imageEditorZoomLabel => 'ズーム';

  @override
  String get imageEditorBrightnessLabel => '明るさ';

  @override
  String get imageEditorContrastLabel => 'コントラスト';

  @override
  String get imageEditorRotateLeft => '左に回転';

  @override
  String get imageEditorRotateRight => '右に回転';

  @override
  String get imageEditorReset => 'リセット';

  @override
  String get imageEditorLoadFailed => '選択した画像を読み込めませんでした。';

  @override
  String get imageEditorProcessFailed => '選択した画像を処理できませんでした。';

  @override
  String get imageEditorSectionColor => '色（色温度／ティント／ガンマ）';

  @override
  String get imageEditorSectionSplitToning => 'スプリットトーン (HSL)';

  @override
  String get imageEditorSectionDetail => 'ディテール（明瞭度／シャープネス／ノイズ除去／粒子）';

  @override
  String get imageEditorSectionEffects => 'エフェクト（色収差／歪み／周辺減光）';

  @override
  String get imageEditorSectionWatermark => 'テキスト透かし／マーク';

  @override
  String get imageEditorTemperatureLabel => '色温度';

  @override
  String get imageEditorTintLabel => 'ティントシフト';

  @override
  String get imageEditorGammaLabel => 'ガンマ（カーブ）';

  @override
  String get imageEditorShadowHueLabel => 'シャドウの色相';

  @override
  String get imageEditorShadowStrengthLabel => 'シャドウの強さ';

  @override
  String get imageEditorHighlightHueLabel => 'ハイライトの色相';

  @override
  String get imageEditorHighlightStrengthLabel => 'ハイライトの強さ';

  @override
  String get imageEditorClarityLabel => '明瞭度';

  @override
  String get imageEditorSharpnessLabel => 'シャープネス';

  @override
  String get imageEditorDenoiseLabel => 'ノイズ除去';

  @override
  String get imageEditorGrainLabel => '粒子';

  @override
  String get imageEditorDispersionLabel => '分散';

  @override
  String get imageEditorDistortLabel => '歪み（正：膨張／負：伸縮）';

  @override
  String get imageEditorWatermarkTextLabel => '透かしテキスト';

  @override
  String get imageEditorWatermarkTextHint => 'オーバーレイするテキストを入力（空欄でスキップ）';

  @override
  String get imageEditorWatermarkSizeLabel => 'テキストサイズ';

  @override
  String get imageEditorWatermarkOpacityLabel => '不透明度';

  @override
  String get imageEditorWatermarkPositionLabel => '位置';

  @override
  String get imageEditorAdvancedApplyHint => '展開パネル内の調整は、保存時に元の画像へ適用されます。';

  @override
  String get skillsEditorSave => '保存';

  @override
  String get skillsEditorCancel => 'キャンセル';

  @override
  String get skillsEditSuccess => 'スキル内容を保存しました';

  @override
  String get skillsDeleteConfirmTitle => 'スキルを削除';

  @override
  String get skillsDeleteConfirmBody =>
      '削除すると、スキルディレクトリとその SKILL.md 内容は完全に取り除かれます。';

  @override
  String get skillsDeleteConfirmAction => '削除する';

  @override
  String get skillsDeleteSuccess => 'スキルを削除しました';

  @override
  String get skillsStorageSectionBody =>
      'OpenHand がスキルをスキャンするローカルディレクトリを設定します。既定では ~/.openhand/skills を使用し、必要に応じて自動作成します。';

  @override
  String get skillsStorageDefaultPath => '既定のパス';

  @override
  String get skillsStorageCurrentPath => '現在のパス';

  @override
  String get skillsStorageSave => '保存場所を保存';

  @override
  String get skillsStorageBrowse => 'ディレクトリを選択';

  @override
  String get skillsStorageReset => '既定に戻す';

  @override
  String get skillsStorageOpen => '場所を開く';

  @override
  String get skillsStorageStatusError => 'スキルディレクトリを読み込めません';

  @override
  String get skillsPathSaved => 'スキル保存場所を更新しました';

  @override
  String get instructionPageTitle => '指示';

  @override
  String get instructionPageSubtitle =>
      '再利用できるプロンプト断片を管理します。有効な指示は現在の順序で各スレッドの system prompt に注入され、送信ごとに切り替えられるチップとして入力欄の上に表示されます。';

  @override
  String get instructionRefresh => '更新';

  @override
  String get instructionNewEntry => '新規指示';

  @override
  String get instructionEmptyTitle => '指示はまだありません';

  @override
  String get instructionEmptyBody =>
      '最初の再利用可能な指示を作成すると、OpenHand がローカルの指示ストアに保存します。';

  @override
  String get instructionLoadFailedTitle => '指示ストアを読み込めませんでした';

  @override
  String get instructionDeleteConfirmTitle => '指示を削除';

  @override
  String get instructionDeleteConfirmBody => 'この指示を削除しますか？この操作は元に戻せません。';

  @override
  String get instructionEnabledStatus => '有効・注入中';

  @override
  String get instructionDisabledStatus => '無効';

  @override
  String get instructionApplyToChipLabel => '適用先';

  @override
  String get instructionNotesChipLabel => 'メモ';

  @override
  String get instructionDialogCreateTitle => '新規指示';

  @override
  String get instructionDialogEditTitle => '指示を編集';

  @override
  String get instructionEnabledLabel => '有効';

  @override
  String get instructionEnabledBody => 'この指示を現在のプロンプトチェーンへ注入します。';

  @override
  String get instructionNameField => '名前 *';

  @override
  String get instructionNameRequired => '名前を入力してください。';

  @override
  String get instructionDescriptionField => '説明';

  @override
  String get instructionVersionField => 'バージョン';

  @override
  String get instructionApplyToField => '適用先（この指示を読み込む条件）';

  @override
  String get instructionTaskTypesField => 'トリガーするタスク種別（カンマ区切り）';

  @override
  String get instructionKeywordsField => 'トリガーするキーワード（カンマ区切り）';

  @override
  String get instructionNotesField => 'メモ（1行に1件）';

  @override
  String get instructionBodyField => '指示本文 *（Markdown）';

  @override
  String get instructionBodyRequired => '指示本文を入力してください。';

  @override
  String get instructionCreateAction => '作成';

  @override
  String get instructionSaveFailed => '保存に失敗しました。必須項目が空でないか確認してください。';

  @override
  String get memoryPageTitle => 'メモリ';

  @override
  String get memoryPageSubtitle => 'ローカルデータベースに保存されたユーザーメモリを管理します。';

  @override
  String get memoryRefresh => '更新';

  @override
  String get memoryNewEntry => '新規メモリ';

  @override
  String get memoryEmptyTitle => 'まだユーザーメモリがありません';

  @override
  String get memoryEmptyBody => 'ユーザーメモリを追加すると、ローカルデータベースに保存されます。';

  @override
  String get memoryLoadFailedTitle => 'メモリデータの読み込みに失敗';

  @override
  String get memoryLoadFailedBody =>
      'メモリデータが無効か利用できません。保存内容を修復または消去してから再試行してください。';

  @override
  String get memoryQuotaRecoveryTitle => 'メモリストレージが上限を超えています';

  @override
  String get memoryQuotaRecoveryBody =>
      '制限されたスナップショットのみ表示しています。項目を削除または縮小してください。新規追加は一時的に無効です。';

  @override
  String get memoryOperationFailed => 'メモリ操作に失敗しました。もう一度お試しください。';

  @override
  String get memoryDialogCreateTitle => 'ユーザーメモリを追加';

  @override
  String get memoryDialogEditTitle => 'ユーザーメモリを編集';

  @override
  String get memoryContentField => 'メモリ内容';

  @override
  String get memoryContentRequired => 'メモリ内容を入力してください。';

  @override
  String get memoryTagsField => 'タグ';

  @override
  String get memoryTagsHint => 'タグを入力して Enter キーで追加';

  @override
  String get memoryTagLimitExceeded => '1 件のメモリに追加できるタグは最大 32 個です。';

  @override
  String get memoryDeleteConfirmTitle => 'ユーザーメモリを削除';

  @override
  String get memoryDeleteConfirmBody => 'このユーザーメモリを削除しますか？この操作は取り消せません。';

  @override
  String get memoryTypeUser => 'ユーザー編集';

  @override
  String get memoryEntryCreated => 'ユーザーメモリを作成しました。';

  @override
  String get memoryEntryUpdated => 'ユーザーメモリを更新しました。';

  @override
  String get memoryEntryDeleted => 'ユーザーメモリを削除しました。';

  @override
  String get memoryEnabledLabel => 'メモリを有効化';

  @override
  String get memoryEnabledBody =>
      '無効にすると、保存済みのユーザーメモリはディスク上に残りますが、実行時には使用されません。';

  @override
  String get userMemoryFileLabel => 'メモリデータベース';

  @override
  String get memoryFileBody => 'ユーザーメモリは OpenHand のローカル SQLite データベースに保存されます。';

  @override
  String get memoryFileDefaultPath => 'データベースの場所';

  @override
  String get memoryOpenDirectory => 'データベースフォルダを開く';

  @override
  String get memoryDisabledTitle => 'メモリは現在無効です';

  @override
  String get memoryDisabledBody =>
      'ここでもユーザーメモリを管理できます。実行時に利用するには、設定 > メモリ でメモリを有効化してください。';

  @override
  String get memoryCreatedAtLabel => '作成日時';

  @override
  String get memoryPersistenceSaveFailedTitle => 'メモリの保存に失敗';

  @override
  String get memoryPersistenceSaveFailedBody =>
      'メモリデータベースへの書き込みに失敗しました。未確定の変更は適用されていません。データベースのアクセス権とディスク状態を確認してください。';

  @override
  String get mcpPageTitle => 'MCP';

  @override
  String get mcpPageSubtitle =>
      'Cursor 風レイアウトを OpenHand 向けに調整したローカル MCP サーバー設定の管理画面です。';

  @override
  String get mcpRefresh => '更新';

  @override
  String get mcpNewServer => '新規サーバー';

  @override
  String get mcpEmptyTitle => 'まだ MCP サービスが構成されていません';

  @override
  String get mcpEmptyBody =>
      'まず MCP サーバーを追加してください。OpenHand は ~/.openhand/mcp/mcp_servers.json に保存します。';

  @override
  String get mcpLoadFailedTitle => 'MCP 設定の読み込みに失敗';

  @override
  String get mcpOperationFailed => 'MCP 操作に失敗しました。もう一度お試しください。';

  @override
  String get mcpDialogCreateTitle => 'MCP サービスを追加';

  @override
  String get mcpDialogEditTitle => 'MCP サービスを編集';

  @override
  String get mcpNameField => 'サービス名';

  @override
  String get mcpNameRequired => 'サービス名を入力してください。';

  @override
  String get mcpNameDuplicate => 'そのサービス名は既に存在します。';

  @override
  String get mcpTypeField => 'サービスタイプ';

  @override
  String get mcpUrlField => 'サービス URL';

  @override
  String get mcpUrlRequired => 'サービス URL を入力してください。';

  @override
  String get mcpUrlInvalid => '有効なサービス URL を入力してください。';

  @override
  String get mcpCommandField => '起動コマンド';

  @override
  String get mcpCommandRequired => '起動コマンドを入力してください。';

  @override
  String get mcpArgsField => 'コマンド引数';

  @override
  String get mcpArgsHint => '1 行に 1 つの引数を入力します';

  @override
  String get mcpServerEnabledLabel => 'このサービスを有効化';

  @override
  String get mcpServerEnabledBody => '無効にするとサービス設定は保持されますが、実行時にはサーバーは有効化されません。';

  @override
  String get mcpServerStatusEnabled => '有効';

  @override
  String get mcpServerStatusDisabled => '無効';

  @override
  String get mcpServerCreated => 'MCP サービスを作成しました。';

  @override
  String get mcpServerUpdated => 'MCP サービスを更新しました。';

  @override
  String get mcpServerDeleted => 'MCP サービスを削除しました。';

  @override
  String get mcpDeleteConfirmTitle => 'MCP サービスを削除';

  @override
  String get mcpDeleteConfirmBody => 'この MCP サービス設定を削除しますか？';

  @override
  String mcpDeleteAlsoUninstallPackage(String packageName) {
    return '基盤パッケージもアンインストール（$packageName）';
  }

  @override
  String get mcpDeleteAlsoUninstallPackageBody =>
      'グローバルパッケージをアンインストールし、隔離キャッシュを削除します。';

  @override
  String mcpDependencyCleanedUp(String packageName) {
    return '$packageName の依存関係をクリーンアップしました';
  }

  @override
  String mcpDependencyCleanupFailed(String packageName, String error) {
    return '$packageName のクリーンアップに失敗しました: $error';
  }

  @override
  String mcpDependencyCleanupError(String packageName, String error) {
    return '$packageName のクリーンアップエラー: $error';
  }

  @override
  String get mcpTemplateSessionManaged => 'セッション管理';

  @override
  String mcpTemplateSessionOn(String status) {
    return 'セッション有効 · $status';
  }

  @override
  String mcpTemplateSessionOff(String status) {
    return 'セッション無効 · $status';
  }

  @override
  String get mcpTemplateNotRegistered => '未登録';

  @override
  String mcpTemplateRuntimeEnabledCount(int count) {
    return '$count セッション有効';
  }

  @override
  String get mcpDisabledTitle => 'MCP サービスは現在無効です';

  @override
  String get mcpDisabledBody =>
      'ここでサービス設定の管理は引き続き可能です。実行時に有効化するには、設定 > MCP のスイッチをオンにしてください。';

  @override
  String get mcpTransportStreamableHttp => 'ストリーマブル HTTP';

  @override
  String get mcpTransportSse => 'SSE';

  @override
  String get mcpTransportStdio => 'STDIO';

  @override
  String get mcpPersistenceSaveFailedTitle => 'MCP 設定の保存に失敗';

  @override
  String get mcpPersistenceSaveFailedBody =>
      'MCP 設定ファイルの書き込みに失敗しました。UI は最後の有効な構成にロールバックされています。ファイルの権限やディスクの状態を確認してください。';

  @override
  String get threadsEmptyBody => 'まだスレッドがありません。新規スレッドを作成して開始してください。';

  @override
  String get threadTemplateDialogTitle => 'スレッドテンプレートを選択';

  @override
  String get threadTemplateDialogBody =>
      '以下の組み込み機能テンプレートからひとつ選んで新しいスレッドを開始します。';

  @override
  String get threadCompressionNotice =>
      'このスレッドの古いメッセージは要約チェックポイントに圧縮され、アクティブなプロンプトを集中した状態に保ちます。';

  @override
  String get threadCompressionCheckpointLabel => '要約チェックポイント';

  @override
  String get aiCompressionThresholdLabel => 'メッセージ圧縮の閾値';

  @override
  String get aiCompressionThresholdBody =>
      '現在のスレッドの未圧縮履歴メッセージがこの文字数閾値を超えると、OpenHand は古い区間を要約して圧縮チェックポイントを作成し、最新の区間をアクティブのまま保持します。';

  @override
  String get aiCompressionThresholdSave => '閾値を保存';

  @override
  String get aiCompressionThresholdSaved => 'AI メッセージ圧縮の閾値を更新しました。';

  @override
  String get aiCompressionThresholdInvalid => '有効な正の整数の閾値を入力してください。';

  @override
  String get aiToolResultCompressionThresholdLabel => 'ツール呼び出し出力の圧縮閾値';

  @override
  String get aiToolResultCompressionThresholdSave => '閾値を保存';

  @override
  String get aiToolResultCompressionThresholdSaved => 'ツール呼び出し出力の圧縮閾値を更新しました。';

  @override
  String get aiToolResultCompressionThresholdInvalid => '有効な正の整数の閾値を入力してください。';

  @override
  String get aiToolResultCompressionEnabledLabel => 'ツール呼び出し出力の圧縮を有効化';

  @override
  String get aiToolResultCompressionEnabledBody =>
      '圧縮チェックポイントの作成時に長いツール出力を要約するかを制御します。通常の会話では常に完全な結果をモデルへ渡します。無効にするとチェックポイントでも原文を保持するため、圧縮コストが増える可能性があります。';

  @override
  String get aiMicroCompressionEnabledLabel => '微圧縮';

  @override
  String get aiMicroCompressionEnabledBody =>
      '有効にすると、古い消費済みツール結果は圧縮チェックポイント用プロンプト内でのみコンパクト化されます。要約コストを下げつつ、通常の会話履歴はキャッシュに安定した形で保ちます。無効にしても、長い古い結果は上のしきい値に従って要約されます。';

  @override
  String get aiMessageContentSectionLabel => 'メッセージ内容';

  @override
  String get aiMessageContentFormatLabel => '内容フォーマット';

  @override
  String get aiMessageContentFormatBody =>
      'AI アシスタントメッセージの表示方法を制御します。Markdown が既定、PlainText が最も高速、HTML はサードパーティライブラリによるレンダリングで token がやや多め、レンダリング失敗時は以下のフォールバックでダウングレードします。';

  @override
  String get aiMessageContentFormatMarkdown => 'Markdown';

  @override
  String get aiMessageContentFormatPlainText => 'プレーンテキスト';

  @override
  String get aiMessageContentFormatHtml => 'HTML';

  @override
  String get aiMessageContentFormatHtmlTokenWarning =>
      'HTML モードは毎ターンのプロンプトに追加の制約を注入します。token コストがやや高めです。';

  @override
  String get aiHtmlRenderFallbackLabel => 'HTML レンダリング失敗フォールバック';

  @override
  String get aiHtmlRenderFallbackBody =>
      'HTML の解析またはレンダリングが失敗したときのダウングレード戦略。Markdown は Markdown として再解析、PlainText は生テキストをそのまま表示します。';

  @override
  String get aiHtmlRenderFallbackMarkdown => 'Markdown';

  @override
  String get aiHtmlRenderFallbackPlainText => 'プレーンテキスト';

  @override
  String get aiHtmlContentRichnessLabel => 'HTML コンテンツ豊富度';

  @override
  String get aiHtmlContentRichnessBody =>
      'HTML モードでモデルに注入する視覚スタイルの強度を制御します。バランスがデフォルト（抑制されたモノクロ）；リッチは色とカードを解放；ビビッドはグラデーション、ガラスモーフィズム、ヒーローブロックを最大化し、トークンコストが最も高くなります。';

  @override
  String get aiHtmlContentRichnessBalanced => 'バランス';

  @override
  String get aiHtmlContentRichnessRich => 'リッチ';

  @override
  String get aiHtmlContentRichnessVivid => 'ビビッド';

  @override
  String get aiToolResultCompressionHeadTailWindowLabel => '圧縮の先頭/末尾ウィンドウ';

  @override
  String get aiToolResultCompressionHeadTailWindowBody =>
      '圧縮サマリに保持する生出力の先頭/末尾文字数。既定値 256、0 で先頭/末尾スニペットを無効化、範囲は 0–8192。';

  @override
  String get aiToolResultCompressionHeadTailWindowSave => 'ウィンドウを保存';

  @override
  String get aiToolResultCompressionHeadTailWindowSaved => '先頭/末尾ウィンドウを更新しました。';

  @override
  String get aiToolResultCompressionHeadTailWindowInvalid =>
      '0 から 8192 までの整数を入力してください。';

  @override
  String get aiToolResultCompressionMaxPathHitsLabel => '圧縮のパス抽出上限';

  @override
  String get aiToolResultCompressionMaxPathHitsBody =>
      'サマリに抽出する影響ファイルパスの最大数。既定値 12、0 で抽出を無効化、範囲は 0–200。';

  @override
  String get aiToolResultCompressionMaxPathHitsSave => '上限を保存';

  @override
  String get aiToolResultCompressionMaxPathHitsSaved => 'パス抽出上限を更新しました。';

  @override
  String get aiToolResultCompressionMaxPathHitsInvalid =>
      '0 から 200 までの整数を入力してください。';

  @override
  String get aiWriteToolSummaryMaxCharsLabel => 'Write 系ツールのサマリ文字数上限';

  @override
  String get aiWriteToolSummaryMaxCharsBody =>
      'write/edit/multiedit/notebookedit などの書き込み系ツールサマリで保持する result_text の最大文字数。既定値 280、0 でサマリを省略、範囲は 0–8192。';

  @override
  String get aiWriteToolSummaryMaxCharsSave => '上限を保存';

  @override
  String get aiWriteToolSummaryMaxCharsSaved => 'Write 系ツールのサマリ文字数上限を更新しました。';

  @override
  String get aiWriteToolSummaryMaxCharsInvalid => '0 から 8192 までの整数を入力してください。';

  @override
  String get aiMaxRecentErrorsLabel => 'セッションの最近エラー保持数';

  @override
  String get aiMaxRecentErrorsBody =>
      'AI セッション状態に保持する最近のエラー記録数。既定値 20、範囲は 0-1000。';

  @override
  String get aiMaxRecentErrorsSave => '上限を保存';

  @override
  String get aiMaxRecentErrorsSaved => 'セッションの最近エラー保持数を更新しました。';

  @override
  String get aiMaxRecentErrorsInvalid => '0 から 1000 までの整数を入力してください。';

  @override
  String get aiMaxPlanHistoryEntriesLabel => 'プラン履歴の保持件数';

  @override
  String get aiMaxPlanHistoryEntriesBody =>
      'プランモードで plan_history に保持する最大エントリ数。既定値 20、範囲は 0-1000。';

  @override
  String get aiMaxPlanHistoryEntriesSave => '上限を保存';

  @override
  String get aiMaxPlanHistoryEntriesSaved => 'プラン履歴の保持件数を更新しました。';

  @override
  String get aiMaxPlanHistoryEntriesInvalid => '0 から 1000 までの整数を入力してください。';

  @override
  String get aiMaxTruncationContinuationsLabel => '自動継続上限';

  @override
  String get aiMaxTruncationContinuationsBody =>
      'モデル出力が打ち切られた (finish_reason=length) 後の連続自動継続の最大回数。既定値 5、範囲は 0-100。';

  @override
  String get aiMaxTruncationContinuationsSave => '上限を保存';

  @override
  String get aiMaxTruncationContinuationsSaved => '自動継続上限を更新しました。';

  @override
  String get aiMaxTruncationContinuationsInvalid => '0 から 100 までの整数を入力してください。';

  @override
  String get aiEstimatedCharactersPerTokenLabel => 'トークン文字数推定比';

  @override
  String get aiEstimatedCharactersPerTokenBody =>
      '1 トークンあたりのおおよその文字数。コンテキスト予算の見積もりに使用します。既定値 4、範囲は 1-32。';

  @override
  String get aiEstimatedCharactersPerTokenSave => '比率を保存';

  @override
  String get aiEstimatedCharactersPerTokenSaved => 'トークン文字数推定比を更新しました。';

  @override
  String get aiEstimatedCharactersPerTokenInvalid => '1 から 32 までの整数を入力してください。';

  @override
  String get aiImageSizeLimitBody =>
      'ユーザーがこの上限を超える画像を添付すると、OpenHand は自動的に圧縮（品質＋解像度）して送信します。MB 単位の小数値を受け付け、範囲は 0.0625 MB (64 KB) から 64 MB です。';

  @override
  String get aiImageSizeLimitFieldLabel => '上限 (MB)';

  @override
  String get aiImageSizeLimitSave => '上限を保存';

  @override
  String get aiImageSizeLimitSaved => '画像添付サイズの上限を更新しました。';

  @override
  String get aiImageSizeLimitInvalid => '有効な正の MB 数を入力してください。';

  @override
  String get imageEditorAspectFree => '自由';

  @override
  String get imageEditorAspectOriginal => 'オリジナル';

  @override
  String get imageEditorAspectSquare => '1:1';

  @override
  String get imageEditorAspect4x3 => '4:3';

  @override
  String get imageEditorAspect3x4 => '3:4';

  @override
  String get imageEditorAspect16x9 => '16:9';

  @override
  String get imageEditorAspect9x16 => '9:16';

  @override
  String get imageEditorAspectCircle => '円形';

  @override
  String get imageEditorFlipHorizontal => '左右反転';

  @override
  String get imageEditorFlipVertical => '上下反転';

  @override
  String get imageEditorSaturationLabel => '彩度';

  @override
  String get imageEditorExposureLabel => '露出';

  @override
  String get imageEditorHueLabel => '色相';

  @override
  String get imageEditorVignetteLabel => '周辺減光';

  @override
  String get imageEditorFineRotationLabel => '微調整 (°)';

  @override
  String get imageEditorSaveToFile => 'ファイルに保存';

  @override
  String get imageEditorCopyToClipboard => 'クリップボードにコピー';

  @override
  String imageEditorSavedTo(String path) {
    return '保存しました：$path';
  }

  @override
  String imageEditorSaveFailed(String error) {
    return '保存に失敗しました：$error';
  }

  @override
  String get imageEditorClipboardCopiedBitmap =>
      '画像をクリップボードにコピーしました。ファイルパスもテキストとしてコピーされました。';

  @override
  String imageEditorClipboardCopiedPath(String path) {
    return '画像ファイルパスをクリップボードにコピーしました：$path';
  }

  @override
  String get imageEditorApplyButton => '適用';

  @override
  String get imageEditorUndoButton => '元に戻す';

  @override
  String get imageEditorResetAllButton => 'すべてリセット';

  @override
  String get imageEditorCompareHold => '長押しで比較';

  @override
  String get imageEditorCompareRelease => '離す';

  @override
  String get imageEditorCompareOriginal => 'オリジナル';

  @override
  String get imageEditorWatermarkColorLabel => 'テキストの色';

  @override
  String get imageEditorWatermarkColorHue => '色相';

  @override
  String get imageEditorWatermarkColorSaturation => '彩度';

  @override
  String get imageEditorWatermarkColorLightness => '明度';

  @override
  String get imageEditorApplySuccess => '調整を適用しました';

  @override
  String get imageEditorProcessing => '処理中...';

  @override
  String get builtinToolTimeoutLabel => 'タイムアウト (秒)';

  @override
  String builtinToolTimeoutHint(int seconds) {
    return '既定 $seconds 秒';
  }

  @override
  String builtinToolTimeoutHelper(int seconds) {
    return '空欄＝既定 $seconds 秒。副作用のないツールの実行時ガードです。Task/Bash/書き込みツールは独自の制限を使います。';
  }

  @override
  String get builtinToolRetryLabel => '失敗 / タイムアウト時に再試行';

  @override
  String get builtinToolRetryBody =>
      '既定はオフ。副作用のないツールで実際の failed/timed_out の場合のみ再試行します。引数不正、拒否された呼び出し、Task、書き込みコマンド、ファイル編集、バックグラウンドプロセス、スキル変更、メモリ書き込みは再試行しません。';

  @override
  String builtinToolMaxRetriesLabel(int max) {
    return '最大再試行回数 (0–$max)';
  }

  @override
  String builtinToolMaxRetriesHelper(int max) {
    return '初回試行を除く。$max で上限';
  }

  @override
  String get builtinToolBackoffLabel => '再試行バックオフのベース (ms)';

  @override
  String builtinToolBackoffHint(int ms) {
    return '既定 ${ms}ms';
  }

  @override
  String builtinToolBackoffHelper(int max) {
    return '指数：N 回目はベース × 2^(N-1) ms 待機、${max}ms で上限';
  }

  @override
  String selfLearningFlushIntervalLabel(int ms) {
    return 'ストリームフラッシュ間隔: ${ms}ms';
  }

  @override
  String selfLearningFlushIntervalHelper(int min, int max) {
    return '自己学習カードのストリーミング出力の永続化間隔 ($min–${max}ms)。小さいほどリアルタイム性が高いがレイアウトのジッターが増えます。大きいほどスムーズですがチャンクごとのレイテンシが増えます。既定値は 600ms。';
  }

  @override
  String get tsmRenameThreadTitle => 'スレッドの名前を変更';

  @override
  String get tsmRenameHint => 'スレッドのタイトルを入力';

  @override
  String get tsmRenameFailed => '名前の変更に失敗しました';

  @override
  String get tsmDeleteThreadTitle => 'スレッドを削除';

  @override
  String get tsmDeleteSelectedTitle => '選択したスレッドを削除';

  @override
  String tsmDeleteSelectedConfirm(int count) {
    return '$count 件のスレッドとそのメッセージを完全に削除します。この操作は取り消せません。';
  }

  @override
  String tsmDeleteFailedCount(int count) {
    return '$count 件のスレッドの削除に失敗しました';
  }

  @override
  String get tsmSessionMissing => 'セッションが見つからないか削除されています';

  @override
  String get tsmExportSessionDataTitle => 'セッションデータをエクスポート';

  @override
  String tsmExportingSession(String title) {
    return '「$title」をエクスポート中…';
  }

  @override
  String get tsmExportComplete => 'エクスポート完了';

  @override
  String get tsmExportFailed => 'エクスポートに失敗しました';

  @override
  String get tsmChooseExportFolder => 'エクスポート先フォルダを選択';

  @override
  String get tsmBatchExportTitle => '一括エクスポート';

  @override
  String tsmBatchExportSubtitle(int count) {
    return '$count 件のスレッドをエクスポートします…';
  }

  @override
  String tsmBatchExportDone(int ok, int failed) {
    return '一括エクスポート完了：成功 $ok 件 / 失敗 $failed 件';
  }

  @override
  String get tsmMenuPreview => 'プレビュー';

  @override
  String get tsmMenuRename => '名前を変更';

  @override
  String get tsmMenuExportSession => 'セッションをエクスポート';

  @override
  String get tsmMenuPin => 'ピン留め';

  @override
  String get tsmMenuUnpin => 'ピン留めを解除';

  @override
  String get tsmMenuArchive => 'アーカイブ';

  @override
  String get tsmMenuUnarchive => 'アーカイブから戻す';

  @override
  String get tsmMenuDelete => '削除';

  @override
  String get tsmPinUpdateFailed => 'ピン留めの更新に失敗しました';

  @override
  String get tsmArchiveUpdateFailed => 'アーカイブ状態の更新に失敗しました';

  @override
  String get tsmUntitledThread => '(無題のスレッド)';

  @override
  String tsmPreviewMessageCount(int count) {
    return '$count 件のメッセージ';
  }

  @override
  String get tsmClosePreview => 'プレビューを閉じる';

  @override
  String get tsmNoMessages => 'メッセージがありません';

  @override
  String get tsmEmptyMessage => '(空)';

  @override
  String get tsmSearchHint => 'タイトルまたは ID で検索';

  @override
  String get tsmDensityComfortable => '標準';

  @override
  String get tsmDensityCompact => 'コンパクト';

  @override
  String get tsmAllTemplates => 'すべてのテンプレート';

  @override
  String tsmSortDisabledHint(String mode) {
    return '「$mode」で並び替え中です。ドラッグハンドルは無効化されています。並べ替えるには「手動の順序」に戻してください。';
  }

  @override
  String get tsmSortManual => '手動の順序';

  @override
  String get tsmSortUpdated => '更新が新しい順';

  @override
  String get tsmSortCreated => '作成が新しい順';

  @override
  String get tsmSortSize => 'サイズ順';

  @override
  String get tsmSortMessages => 'メッセージ数順';

  @override
  String get tsmSortToken => 'トークン数順';

  @override
  String get tsmHideArchived => 'アーカイブを非表示';

  @override
  String get tsmShowArchived => 'アーカイブを表示';

  @override
  String get tsmExitSelection => '選択を終了';

  @override
  String get tsmEnterSelection => '複数選択';

  @override
  String get tsmClose => '閉じる';

  @override
  String get tsmTitle => 'スレッドセッション管理';

  @override
  String tsmHeaderSubtitle(int count) {
    return '$count 件のスレッド · 長押しまたはハンドルをドラッグして並び替え、ダブルクリックまたは右クリックでメニューを表示';
  }

  @override
  String tsmSelectedCount(int count) {
    return '$count 件選択中';
  }

  @override
  String get tsmBatchExportButton => '一括エクスポート';

  @override
  String get tsmDeleteSelectedButton => '選択を削除';

  @override
  String get tsmEmptyState => 'スレッドセッションがまだありません';

  @override
  String get tsmCancel => 'キャンセル';

  @override
  String get settingsThreadSessionManagementTitle => 'スレッドセッション管理';

  @override
  String get settingsThreadSessionManagementSubtitle =>
      'すべてのスレッドのタイトル、作成・更新時刻、ストレージ使用量、メッセージ構成、トークン統計を確認できます。ドラッグでの並べ替え、複数選択での削除、ダブルクリックまたは右クリックメニューでの名称変更・エクスポート・削除に対応します。ダイアログの開閉アニメーションはグローバル設定のダイアログアニメーションに従います。';

  @override
  String get settingsThreadSessionManagementOpen => '管理画面を開く';

  @override
  String get settingsMessageGatewayTitle => 'メッセージゲートウェイ';

  @override
  String get settingsMessageGatewayDescription =>
      '内蔵 Web 汎用メッセージプラットフォームのリスナー、認証、セッション、Web チャット、ヘルスチェック、ログ、運用機能を設定します。';

  @override
  String get tsmRowUnknown => '不明';

  @override
  String get tsmRowCreated => '作成';

  @override
  String get tsmRowUpdated => '更新';

  @override
  String get tsmRowSize => 'サイズ';

  @override
  String get tsmRowMessages => 'メッセージ';

  @override
  String get tsmRowToken => 'トークン';

  @override
  String get tsmRowByKind => '種類別';

  @override
  String get inputRepairTitle => '入力修復';

  @override
  String get inputRepairBody =>
      '残存する子プロセス（osascript / LSP / MCP など）を回収し、macOS の入力コンテキストをリセット — グローバル TextField の入力・コピー/ペースト・ESC が効かない問題を修復します。';

  @override
  String get inputRepairButton => '入力を修復';

  @override
  String get inputRepairDone => '入力コンテキストをリセットしました';

  @override
  String inputRepairDoneDetail(int count) {
    return '入力コンテキストをリセットし、$count 個の子プロセスを回収しました';
  }

  @override
  String get proxySectionTitle => 'システム';

  @override
  String get proxySectionBody =>
      'OpenHand のすべての内部 HTTP クライアント（WebSearch / WebFetch など）は、ここで選択したプロキシ設定に従ってルーティングされます。保存後すぐに反映され、再起動は不要です。';

  @override
  String get proxyModeLabel => 'プロキシモード';

  @override
  String get proxyModeBody =>
      '内部 HTTP クライアント（WebSearch / WebFetch など）がプロキシをどのように選択するかを制御します。';

  @override
  String get proxyModeDisabled => 'プロキシなし';

  @override
  String get proxyModeAutomatic => '自動検出（既定）';

  @override
  String get proxyModeManual => '手動設定';

  @override
  String get proxyProtocolsLabel => 'プロトコル';

  @override
  String get proxyProtocolsBody =>
      '複数選択可。最低 1 つは残す必要があります。すべて解除すると HTTP + HTTPS に戻ります。';

  @override
  String get proxyHostLabel => 'サーバー（IP またはホスト名）';

  @override
  String get proxyPortLabel => 'ポート';

  @override
  String get proxyAuthLabel => 'プロキシ認証を有効化';

  @override
  String get proxyAuthBody => '有効化したときのみ、下のユーザー名 / パスワードが使用されます（HTTP Basic）。';

  @override
  String get proxyUsernameLabel => 'ユーザー名';

  @override
  String get proxyPasswordLabel => 'パスワード';

  @override
  String get proxyExceptionsLabel => 'これらのホスト・ドメインではプロキシを無視';

  @override
  String get proxyExceptionsBody =>
      '1 行に 1 件。対応：IP（127.0.0.1）、IPv4 CIDR（192.168.0.0/16）、ドメイン（example.com はサブドメインを含む）、glob（*.example.com）、正規表現（/^api\\d+\\.example\\.com\$/i）。localhost / 127.0.0.1 / ::1 は常に直接接続。';

  @override
  String get proxyExceptionsHint =>
      '例：\n*.local\n10.0.0.0/8\n/^api\\d+\\.example\\.com\$/i';

  @override
  String get proxyTestButton => 'プロキシ接続をテスト';

  @override
  String get proxyTesting => 'テスト中…';

  @override
  String proxyTestSuccess(int latency, String via) {
    return 'OK ($latency ms、$via 経由)';
  }

  @override
  String proxyTestFailure(String reason) {
    return '失敗：$reason';
  }

  @override
  String get proxyTestEndpointLabel => 'テスト URL';

  @override
  String get proxyTestEndpointHint => '既定：https://www.google.com/generate_204';

  @override
  String get proxyTestVerdictDirect => '直接';

  @override
  String proxyTestVerdictProxy(String endpoint) {
    return 'プロキシ $endpoint';
  }

  @override
  String get proxyTestEndpointInvalid =>
      'テスト URL が無効です（http:// または https:// で始まる必要があります）';

  @override
  String get proxyTestConsoleTitle => 'プロキシ接続診断';

  @override
  String get proxyTestConsoleRunning => 'ルートを調査中…';

  @override
  String get proxyTestConsoleSucceeded => '完了：ルートは正常';

  @override
  String get proxyTestConsoleFailed => '完了：問題を検出';

  @override
  String get proxyTestConsoleCopy => 'ログをコピー';

  @override
  String get proxyTestConsoleCopied => 'ログをクリップボードにコピーしました';

  @override
  String get proxyTestConsoleClose => '閉じる';

  @override
  String get proxyTestConsoleRerun => '再実行';

  @override
  String get proxyTestConsoleMaximize => '最大化';

  @override
  String get proxyTestConsoleRestore => '元のサイズに戻す';

  @override
  String get proxyTestConsoleClear => 'コンソールをクリア';

  @override
  String get tokenPopupCostHeading => 'コスト';

  @override
  String get tokenPopupCostInput => '入力';

  @override
  String get tokenPopupCostOutput => '出力';

  @override
  String get tokenPopupCostCacheRead => 'キャッシュ読込';

  @override
  String get tokenPopupCostCacheWrite => 'キャッシュ書込';

  @override
  String get tokenPopupCostTotal => '合計';

  @override
  String get tokenDialUnit => 'トークン';

  @override
  String get tokenPopupInputHeading => '入力';

  @override
  String get tokenPopupPrompt => 'プロンプト';

  @override
  String get tokenPopupAudioInput => '音声入力';

  @override
  String get tokenPopupImageInput => '画像入力';

  @override
  String get tokenPopupVideoInput => '動画入力';

  @override
  String get tokenPopupCacheRead => 'キャッシュ読込';

  @override
  String get tokenPopupCacheWrite => 'キャッシュ書込';

  @override
  String get tokenPopupOutputHeading => '出力';

  @override
  String get tokenPopupCompletion => '応答';

  @override
  String get tokenPopupReasoning => '推論';

  @override
  String get tokenPopupWebSearchHeading => 'ウェブ検索';

  @override
  String get tokenPopupWebSearchCalls => '呼び出し回数';

  @override
  String get tokenPopupWebSearchPages => '参照ページ';

  @override
  String get tokenPopupGrandTotal => '合計';

  @override
  String get tokenPopupContextOverview => 'コンテキストデータ概要';

  @override
  String get tokenPopupContextMeasured => '合計は実測 · 分類は按分';

  @override
  String get tokenPopupContextEstimated => 'リクエスト内容から推定';

  @override
  String get tokenPopupContextEmpty => '次のメッセージ送信後に概要を生成します';

  @override
  String get tokenPopupContextSystemPrompt => 'システムプロンプト';

  @override
  String get tokenPopupContextBuiltinTools => '組み込みツール';

  @override
  String get tokenPopupContextMcp => 'MCP';

  @override
  String get tokenPopupContextInstructions => '指示';

  @override
  String get tokenPopupContextMemory => 'メモリ';

  @override
  String get tokenPopupContextSkills => 'スキル';

  @override
  String get tokenPopupContextHooks => 'Hooks';

  @override
  String get tokenPopupContextConversation => '会話';

  @override
  String get tokenPopupContextRuntime => 'ランタイム';

  @override
  String get tokenPopupContextWindow => 'コンテキストウィンドウ';

  @override
  String get tokenPopupCompactNow => '今すぐ圧縮';

  @override
  String get tokenPopupCompacting => '圧縮中…';

  @override
  String get tokenPopupSessionHeading => 'セッション';

  @override
  String get tokenPopupMessages => 'メッセージ';

  @override
  String get tokenPopupPromptBuilds => 'プロンプト生成';

  @override
  String get tokenPopupPromptChars => 'プロンプト文字数';

  @override
  String get tokenPopupCacheHitModeExcludeExpired => '期限切れ異常を除外';

  @override
  String get tokenPopupCacheHitModeIncludeExpired => '期限切れ異常を含む';

  @override
  String tokenPopupExcludedRounds(int count) {
    return '$count 件除外';
  }

  @override
  String get tokenPopupPrefixReuse => 'プレフィックス再利用';

  @override
  String tokenPopupTooltipFreshReuse(String fresh, int reuse) {
    return '新規 $fresh · 再利用 $reuse%';
  }

  @override
  String get tokenPopupFirstRequestShort => '初回除外';

  @override
  String get tokenPopupFirstRequestNotAveraged => '平均外';

  @override
  String get tokenPopupTrendNoData => 'キャッシュ命中率データはまだありません。メッセージ送信後に推移を表示します。';

  @override
  String get tokenPopupTrendOnlyFirstIgnored =>
      '初回リクエストは平均外です。次の通常リクエスト後に表示します。';

  @override
  String get tokenPopupTrendFirstReferenceOnly => '初回は参考表示のみで、平均には含めません。';

  @override
  String get tokenPopupUncached => '未キャッシュ';

  @override
  String get toolbarSessionMetadata => 'セッションメタデータ';

  @override
  String get toolbarShowPlan => 'プラン展開';

  @override
  String get toolbarHidePlan => 'プラン折畳';

  @override
  String get toolbarPlanAwaitingApproval => 'プラン承認待ち';

  @override
  String get toolbarPlanNeedsReview => 'プラン要再確認';

  @override
  String get toolbarPlanNeedsAttention => 'プラン要対応';

  @override
  String get toolbarPlanCompleted => 'プラン完了';

  @override
  String get toolbarPlanInProgress => 'プラン進行中';

  @override
  String get toolbarPlanConfirmToBegin => '確認後に実行を開始してください';

  @override
  String get toolbarPlanInspectBeforeResume => '再開前に完了済ステップ・成果物・Todo を確認';

  @override
  String get toolbarPlanStepFailed => 'ステップ失敗。確認のうえ続行してください。';

  @override
  String get toolbarPlanPending => '承認待ち';

  @override
  String get toolbarPlanReview => '要確認';

  @override
  String get toolbarToolsProtocolUnsupported => '現在のモデルプロトコルはツール呼出に未対応';

  @override
  String get toolbarRuntimeNoSnapshot => 'ランタイムツールのスナップショット未生成';

  @override
  String get toolbarToolsCatalogStale => 'ツールカタログ期限切れ。次のラウンドで更新';

  @override
  String get toolbarRuntimeCatalogSynced => 'ランタイムツールカタログ同期済';

  @override
  String get toolbarPlanAwaitingNoExecTools => 'プラン承認待ちのため、実行ツールは非表示';

  @override
  String get toolbarPlanReviewBeforeResume => '完了済ステップ・成果物・Todo を確認してください';

  @override
  String get toolbarPlanApprovedExecOpen => 'プラン承認済。実行ツール開放';

  @override
  String get toolbarPlanOnlyPlanningExitAllowed => '計画ツールのみ開放。準備でき次第実行計画を提出';

  @override
  String get toolbarPlanOnlyPlanningOnly => '現在は計画ツールのみ開放';

  @override
  String get toolbarModeJustSwitched => 'モード切替直後。次のラウンドでツールカタログ更新';

  @override
  String get toolbarChatModeNoTools => 'チャットモードでは現在ツール無し';

  @override
  String get toolbarChatModeAllTools => 'チャットモードは完全なランタイムカタログを開放';

  @override
  String get toolbarRuntimeNoSnapshotPrompt => 'ランタイムスナップショット未取得。先にリクエストを送信';

  @override
  String get toolbarGateNoReason => 'ゲート理由なし';

  @override
  String get toolbarGateProtocolUnsupportedSwitchPlan =>
      '現在のモデルプロトコルはツール呼出に未対応。タップで計画モードへ。';

  @override
  String get toolbarGateChatActiveSwitchPlan => 'チャットモード中。タップで計画モードへ切替';

  @override
  String get toolbarGatePlanActiveSwitchChat => '計画モード中。タップでチャットへ切替';

  @override
  String get toolbarGateProtocolUnsupportedSwitchChat =>
      'モデルプロトコル未対応。計画モードでステップ整理は可能だが実行は不可。タップでチャットへ。';

  @override
  String get toolbarGatePlanJustSwitchedToChat =>
      '計画モード切替直後。次のラウンドでツール更新。タップでチャットへ。';

  @override
  String get toolbarGatePlanAwaitingSwitchChat =>
      'プラン承認待ち。承認まで実行ツール非表示。タップでチャットへ。';

  @override
  String get toolbarGatePlanReviewSwitchChat =>
      'プラン要再確認。続行前にステップ・成果物・Todo を確認。タップでチャットへ。';

  @override
  String get toolbarGatePlanExecutingSwitchChat =>
      'プラン実行中。ランタイムカタログに従いツール開放。タップでチャットへ。';

  @override
  String get toolbarGatePlanModeSwitchChat => '計画モード中。計画後、承認を経て実行。タップでチャットへ。';

  @override
  String get toolbarFilesShow => 'プロジェクト';

  @override
  String get toolbarFilesHide => 'プロジェクト隠す';

  @override
  String get toolbarRuntimeModeChat => 'チャットモード';

  @override
  String get toolbarRuntimeModeChatCompact => 'チャット';

  @override
  String get toolbarRuntimeModePlan => '計画モード';

  @override
  String get toolbarRuntimeModePlanCompact => '計画';

  @override
  String get toolbarRuntimeModePlanAwaiting => 'プラン承認待ち';

  @override
  String get toolbarRuntimeModePlanAwaitingCompact => '承認待ち';

  @override
  String get toolbarRuntimeModePlanReview => 'プラン要再確認';

  @override
  String get toolbarRuntimeModePlanReviewCompact => '要確認';

  @override
  String get toolbarRuntimeModePlanExecution => 'プラン実行';

  @override
  String get toolbarRuntimeModePlanExecutionCompact => '実行';

  @override
  String get toolbarRuntimeModePlanDrafting => 'プラン策定中';

  @override
  String get toolbarRuntimeModePlanDraftCompact => '策定中';

  @override
  String toolbarRuntimeNotices(int count) {
    return '$count 件のランタイム通知';
  }

  @override
  String toolbarMcpLazyLoading(int loaded, int total) {
    return 'MCP $loaded/$total ロード済';
  }

  @override
  String snackToolSearchLoaded(int loaded, int total) {
    return 'ToolSearch が MCP ツールを $loaded/$total 件ロードしました';
  }

  @override
  String get snackToolSearchLoadedAction => '一覧を表示';

  @override
  String get snackToolSearchLoadedDialogTitle => 'ToolSearch がロードした MCP ツール';

  @override
  String get snackToolSearchLoadedDialogClose => '閉じる';

  @override
  String get snackToolSearchLoadedCopyAction => 'select: をコピー';

  @override
  String get snackToolSearchLoadedCopiedToast => 'コピー済み';

  @override
  String get snackToolSearchLoadedClearAction => 'ロード済み一覧をクリア';

  @override
  String get snackToolSearchLoadedClearedToast => 'ロード済み一覧をクリアしました';

  @override
  String get snackToolSearchLoadedGroupOther => 'その他（server 不明）';

  @override
  String get snackToolSearchLoadedCopyGroupAction => 'グループ全体をコピー';

  @override
  String get snackToolSearchLoadedTabLoaded => 'ロード済み';

  @override
  String get snackToolSearchLoadedTabHistory => '履歴';

  @override
  String get snackToolSearchLoadedHistoryEmpty =>
      'このセッションにはまだ ToolSearch の履歴がありません';

  @override
  String get snackToolSearchLoadedHistoryQueryPrefix => 'クエリ: ';

  @override
  String get snackToolSearchLoadedFilterHint => '名前でフィルタ…';

  @override
  String get snackToolSearchLoadedHistoryFilterHint => '名前またはクエリでフィルタ…';

  @override
  String get snackToolSearchLoadedSourceAi => 'AI セッション';

  @override
  String get snackToolSearchLoadedSourceHarness => 'Harness フェーズ';

  @override
  String get snackToolSearchLoadedReplayedToast => '以前の選択で ToolSearch を再実行しました';

  @override
  String get snackToolSearchLoadedReplayPendingToast => '送信予定です — キャンセルをタップで中止';

  @override
  String get snackToolSearchLoadedReplayCancelAction => 'キャンセル';

  @override
  String get snackToolSearchLoadedReplayCancelledToast =>
      '送信をキャンセル — composer をクリア';

  @override
  String get snackToolSearchLoadedSourceFilterAll => '全て';

  @override
  String get snackToolSearchLoadedSourceFilterAi => 'AI のみ';

  @override
  String get snackToolSearchLoadedSourceFilterHarness => 'Harness のみ';

  @override
  String snackToolSearchLoadedSummary(int queries, int tools) {
    return 'このセッションで $queries 個のクエリから $tools 個の MCP ツールをロード';
  }

  @override
  String get snackToolSearchLoadedHistoryReplayAction =>
      'このバッチを select:… としてコピー';

  @override
  String get snackToolSearchLoadedHistoryClearAction => '履歴をクリア';

  @override
  String get snackToolSearchLoadedHistoryExportTooltip => '履歴をエクスポート';

  @override
  String get snackToolSearchLoadedHistoryExportCsv => 'CSV としてコピー';

  @override
  String get snackToolSearchLoadedHistoryExportMarkdown => 'Markdown としてコピー';

  @override
  String get snackToolSearchLoadedHistoryExportJson => 'JSON としてコピー';

  @override
  String get snackToolSearchLoadedHistoryExportSaveCsv => 'CSV として保存…';

  @override
  String get snackToolSearchLoadedHistoryExportSaveMarkdown =>
      'Markdown として保存…';

  @override
  String get snackToolSearchLoadedHistoryExportSaveJson => 'JSON として保存…';

  @override
  String get snackToolSearchLoadedHistoryExportCsvHint =>
      '表計算ソフト向け。クエリ1件ごとに1行。';

  @override
  String get snackToolSearchLoadedHistoryExportMarkdownHint =>
      'GitHub 風のテーブル。Issue やドキュメントに最適。';

  @override
  String get snackToolSearchLoadedHistoryExportJsonHint =>
      '構造化データ。OpenHand に再インポート可能。';

  @override
  String get toolSearchLoadedHistoryImportTooltip => 'JSON ダンプをインポート';

  @override
  String get toolSearchLoadedHistoryImportDialogTitle =>
      'ToolSearch 履歴インポートプレビュー';

  @override
  String toolSearchLoadedHistoryImportDialogCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件',
      zero: 'エントリなし',
    );
    return '$_temp0';
  }

  @override
  String get toolSearchLoadedHistoryImportDialogEmpty =>
      'ファイルにエントリは見つかりませんでした。';

  @override
  String get toolSearchLoadedHistoryImportDialogClose => '閉じる';

  @override
  String snackToolSearchLoadedHistoryExportSavedToast(int count, String path) {
    return '$count 件を $path に保存しました';
  }

  @override
  String snackToolSearchLoadedHistoryExportSaveFailedToast(String error) {
    return '保存に失敗しました：$error';
  }

  @override
  String get snackToolSearchLoadedHistoryExportRevealAction => 'Finder で表示';

  @override
  String get snackToolSearchLoadedHistoryExportEmptyToast =>
      'フィルター適用後の履歴が空です。エクスポートできません。';

  @override
  String snackToolSearchLoadedHistoryExportedToast(int count) {
    return '$count 件の履歴をクリップボードにコピーしました。';
  }

  @override
  String get snackToolSearchLoadedHistoryClearedToast => 'ロード履歴をクリアしました';

  @override
  String get mcpLazyLoadingViewLoadedAction => '現在のセッションのロード済み一覧を表示';

  @override
  String get mcpToolSearchExportLastDirResetAction => '保存されたエクスポート先をリセット';

  @override
  String get mcpToolSearchExportLastDirResetToast => 'エクスポート先の記憶をクリアしました';

  @override
  String get mcpLazyLoadingNoActiveSession => '現在アクティブなセッションがありません';

  @override
  String toolbarPlanStepsCompleted(int completed, int total) {
    return '$completed/$total 完了';
  }

  @override
  String get mdlEdEnterAValidBaseUrlFirst => '有効な Base URL を先に入力してください';

  @override
  String get mdlEdNoModelsFoundFromThisProvider => 'このプロバイダーからはモデルが見つかりませんでした。';

  @override
  String get mdlEdProviderName => 'プロバイダー名';

  @override
  String get mdlEdOptionalEGDeepseekLocalOllama => '任意。例：DeepSeek、ローカル Ollama';

  @override
  String get mdlEdCurrentlyActiveModel => '現在アクティブなモデル';

  @override
  String get mdlEdClickToSetAsActiveModel => 'クリックでアクティブモデルに設定';

  @override
  String get mdlEdTapScanModelsToDiscoverModels =>
      '「モデルをスキャン」をタップして自動検出するか、下のフォームから手動で追加します。';

  @override
  String get mdlEdActiveModelId => 'アクティブモデル ID';

  @override
  String get mdlEdTheModelUsedForConversationsSelect =>
      '会話に使用するモデル。上のリストから選択するか、直接入力します。';

  @override
  String get mdlEdMaxContextTokens => '最大コンテキストトークン数';

  @override
  String get mdlEdOptionalLimitsTheHistorySliceUsed =>
      '任意。圧縮時に使用する履歴区間サイズを制限します。';

  @override
  String get mdlEdEnterAWholeNumberGreaterThan => '0 より大きい整数を入力してください';

  @override
  String get mdlEdRequestMethod => 'リクエスト方式';

  @override
  String get mdlEdOutputMode => '出力モード';

  @override
  String get mdlEdStreaming => 'ストリーミング';

  @override
  String get mdlEdNonStreaming => '非ストリーミング';

  @override
  String get mdlEdMaxOutputTokens => '最大出力トークン数';

  @override
  String get mdlEdOptionalUsesAdapterDefaultIfUnset =>
      '任意。未設定の場合はアダプターの既定値を使用します。';

  @override
  String get mdlEdTemperature => '温度';

  @override
  String get mdlEd0020Default0 => '0.0 ～ 2.0、既定値 0.7';

  @override
  String get mdlEdEnterANumberBetween00 => '0.0 から 2.0 までの数値を入力してください';

  @override
  String get mdlEdCustomHeaders => 'カスタムヘッダー';

  @override
  String get mdlEdAdd => '追加';

  @override
  String get mdlEdNoCustomHeadersTapAddTo =>
      'カスタムヘッダーはありません。「追加」をタップして作成してください。';

  @override
  String get mdlEdHeaderName => 'ヘッダー名';

  @override
  String get mdlEdHeaderValue => 'ヘッダー値';

  @override
  String get mdlEdEditModelProfile => 'モデルプロファイルを編集';

  @override
  String get mdlEdDisplayName => '表示名';

  @override
  String get mdlEdOptionalShownInTheUi => '任意。UI に表示されます';

  @override
  String get mdlEdDescription => '説明';

  @override
  String get mdlEdMultimodalSupport => 'マルチモーダル対応';

  @override
  String get mdlEdAutoDetect => '自動検出';

  @override
  String get mdlEdYes => 'はい';

  @override
  String get mdlEdNo => 'いいえ';

  @override
  String get mdlEdSupportsAttachments => '添付ファイル対応';

  @override
  String get mdlEdReasoningEcho => '思考履歴を引き継ぐ';

  @override
  String get mdlEdReasoningEchoHint =>
      'このモデルで、過去のターンの思考／推論内容を以降のプロンプト履歴に再投入するかどうかを制御します。';

  @override
  String get mdlEdSupportedModalities => '対応モダリティ';

  @override
  String get mdlEdText => 'テキスト';

  @override
  String get mdlEdImage => '画像';

  @override
  String get mdlEdVideo => '動画';

  @override
  String get mdlEdAudio => '音声';

  @override
  String get mdlEdGenerationCapabilities => '生成機能';

  @override
  String get mdlEdPdf => 'PDF';

  @override
  String get mdlEdPpt => 'PPT';

  @override
  String get mdlEdTokenLimits => 'トークン上限';

  @override
  String get mdlEdContextLength => 'コンテキスト長';

  @override
  String get mdlEdSummaryLength => 'サマリ長';

  @override
  String get mdlEdOutputLength => '出力長';

  @override
  String get mdlEdThinkingLength => '思考長';

  @override
  String get mdlEdTokenPricingUsd1mTokensLeave =>
      'トークン料金 (USD / 100 万トークン、未設定の場合は空欄)';

  @override
  String get mdlEdInput => '入力';

  @override
  String get mdlEdOutput => '出力';

  @override
  String get mdlEdCacheRead => 'キャッシュ読み込み';

  @override
  String get mdlEdCacheWrite => 'キャッシュ書き込み';

  @override
  String get mdlEdReset => 'リセット';

  @override
  String get mdlEdCancel => 'キャンセル';

  @override
  String get mdlEdOk => 'OK';

  @override
  String get tlCallDir => 'ディレクトリ';

  @override
  String get tlCallElapsed => '経過時間';

  @override
  String get tlCallExit => '終了';

  @override
  String get tlCallToolInput => 'ツール入力';

  @override
  String get tlCallCommand => 'コマンド';

  @override
  String get tlCallArguments => '引数';

  @override
  String get tlCallToolOutput => 'ツール出力';

  @override
  String get tlCallNoOutputYet => '出力なし';

  @override
  String get tlCallResult => '結果';

  @override
  String get tlCallStdout => '標準出力';

  @override
  String get tlCallStderr => '標準エラー';

  @override
  String get tlCallArgumentsConstructing => '引数を構築中…';

  @override
  String get tlCallArgumentsConstructingHint =>
      '引数はモデルからストリーミング中です。構築が完了すると通常のカード表示に切り替わります。';

  @override
  String get tlCallCollectedParameters => '取得済み';

  @override
  String get tlCallNoParametersYet => '引数はまだ解析されていません';

  @override
  String get tlCallSubmitting => '送信中…';

  @override
  String get tlCallSubmittingHint => 'パラメータの収集が完了し、エグゼキューターに引き継いでいます';

  @override
  String get tlCallThereIsNoToolOutputYet => 'まだツール出力はありません。';

  @override
  String get tlCallViewInDialog => 'ダイアログで表示';

  @override
  String get tlCallEmptyContent => '内容なし';

  @override
  String get fileMutationSection => 'ファイル変更';

  @override
  String fileMutationFilesChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のファイルを変更しました',
    );
    return '$_temp0';
  }

  @override
  String fileMutationFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のファイル',
    );
    return '$_temp0';
  }

  @override
  String get fileMutationUndoAll => 'すべて元に戻す';

  @override
  String get fileMutationRefresh => '更新';

  @override
  String get fileMutationCopyAllDiff => 'すべての diff をコピー';

  @override
  String get fileMutationCopyAllDiffDone => 'すべての diff をクリップボードにコピーしました';

  @override
  String get fileMutationRevealLedger => 'ファイルマネージャーで ledger.jsonl を表示';

  @override
  String get fileMutationCopyPath => 'ファイルパスをコピー';

  @override
  String get fileMutationPathCopied => 'パスをコピーしました';

  @override
  String fileMutationRevealMore(int count) {
    return '残り $count 件の変更があります — タップして次のバッチを表示';
  }

  @override
  String get fileMutationRevealAll => 'すべて表示';

  @override
  String get fileMutationHistoryInspector => '履歴インスペクター';

  @override
  String get fileMutationHistoryInspectorTitle => 'セッションのファイル履歴';

  @override
  String get fileMutationHistoryInspectorFilterHint => 'パスで絞り込み…';

  @override
  String get fileMutationHistoryInspectorEmpty => 'フィルターに一致するファイル変更はありません。';

  @override
  String get fileMutationHistoryInspectorZoomIn => 'このパスだけ表示';

  @override
  String get fileMutationHistoryInspectorZoomOut => 'すべてのパスに戻る';

  @override
  String get fileMutationUndone => '元に戻し済み';

  @override
  String get fileMutationCascadeUndone => '連動して無効化';

  @override
  String get fileMutationUndoThis => 'この変更を元に戻す';

  @override
  String get fileMutationRedo => 'やり直し';

  @override
  String get fileMutationUndoFailed => '元に戻すのに失敗';

  @override
  String get fileMutationRedoFailed => 'やり直しに失敗';

  @override
  String get fileMutationSnapshotUnavailable => 'コンテンツのスナップショットがありません';

  @override
  String get tlCallTool => 'ツール';

  @override
  String get tlCallSkill => 'スキル';

  @override
  String get tlCallStopped => '停止';

  @override
  String get tlCallStopRequest => 'このツール呼び出しを停止';

  @override
  String get tlCallBlocked => 'ブロック';

  @override
  String get tlCallRejected => '却下';

  @override
  String get tlCallInvalid => '無効';

  @override
  String get tlCallToolCall => 'ツール呼び出し';

  @override
  String get tlCallRunning => '実行中';

  @override
  String get tlCallSucceeded => '成功';

  @override
  String get tlCallDenied => '拒否';

  @override
  String get tlCallTimedOut => 'タイムアウト';

  @override
  String get tlCallFailed => '失敗';

  @override
  String get tlCallToolIsRunningWaitingForOutput => 'ツール実行中。出力を待機中...';

  @override
  String get tlCallExpandToInspectToolOutput => '展開してツール出力を確認';

  @override
  String get tlCallSelfLearning => '自己学習';

  @override
  String get tlCallNudgeRecovered => 'ナッジで復旧';

  @override
  String get tlCallProfileChanges => 'プロファイル変更';

  @override
  String get tlCallMemoryChanges => 'メモリ変更';

  @override
  String get tlCallSkillChanges => 'スキル変更';

  @override
  String get tlCallProfileDiff => 'プロファイル差分';

  @override
  String get tlCallNoChanges => '変更なし';

  @override
  String get tlCallUnnamed => '（名称未設定）';

  @override
  String get tlCallJustNow => 'たった今';

  @override
  String get sessMetaCacheHitTrend => 'キャッシュヒット率トレンド';

  @override
  String get sessMetaCacheHitLast => '最新';

  @override
  String get sessMetaCacheHitAvg => '平均';

  @override
  String get sessMetaCacheHitMax => '最大';

  @override
  String get sessMetaCacheHitOverlayOn => '別の式を重ねる';

  @override
  String get sessMetaCacheHitOverlayOff => '重ね表示を隠す';

  @override
  String get sessMetaCacheHitFormulaClaude => 'Claude 式';

  @override
  String get sessMetaCacheHitFormulaOpenAi => 'OpenAI 式';

  @override
  String sessMetaCacheHitPoint(int index) {
    return '第 $index ターン';
  }

  @override
  String get sessMetaMessages => 'メッセージ';

  @override
  String get sessMetaPromptBuilds => 'プロンプト構築回数';

  @override
  String get sessMetaCompressions => '圧縮回数';

  @override
  String get sessMetaTotalTokens => '合計トークン';

  @override
  String get sessMetaMode => 'モード';

  @override
  String get sessMetaRuntimeTools => 'ランタイムツール';

  @override
  String get sessMetaPending => '保留中';

  @override
  String get sessMetaCurrentSessionMetadata => '現在のセッションメタデータ';

  @override
  String get sessMetaSessionOverview => 'セッション概要';

  @override
  String get sessMetaExtendedMetadata => '拡張メタデータ';

  @override
  String get sessMetaStatistics => '統計';

  @override
  String get sessMetaUser => 'ユーザー';

  @override
  String get sessMetaAssistant => 'アシスタント';

  @override
  String get sessMetaTool => 'ツール';

  @override
  String get sessMetaSkill => 'スキル';

  @override
  String get sessMetaCompression => '圧縮';

  @override
  String get sessMetaEnvironment => '環境';

  @override
  String get sessMetaCommandPolicy => 'コマンドポリシー';

  @override
  String get sessMetaPromptMetadataIsNotAvailableYet => 'プロンプトメタデータはまだ利用できません。';

  @override
  String get sessMetaWriteConfirmation => '書き込み確認';

  @override
  String get sessMetaRequired => '必須';

  @override
  String get sessMetaNotRequired => '不要';

  @override
  String get sessMetaAllowRules => '許可ルール';

  @override
  String get sessMetaThereAreNoSurfacedAllowCommand => '表示する許可コマンドルールはありません。';

  @override
  String get sessMetaRuntimeOrchestration => 'ランタイムオーケストレーション';

  @override
  String get sessMetaStateSource => '状態ソース';

  @override
  String get sessMetaGeneratedFromTheCurrentModelMcp =>
      '現在のモデル、MCP/スキル、プラン状態から生成';

  @override
  String get sessMetaTheLastPersistedRuntimeSnapshot =>
      '最後に永続化されたランタイムスナップショット';

  @override
  String get sessMetaToolCatalogState => 'ツールカタログ状態';

  @override
  String get sessMetaGateReason => 'ゲート理由';

  @override
  String get sessMetaRuntimeToolCount => 'ランタイムツール数';

  @override
  String get sessMetaRefreshesNextRound => '次のラウンドで更新';

  @override
  String get sessMetaRuntimeNotices => 'ランタイム通知';

  @override
  String get sessMetaCurrentRuntimeTools => '現在のランタイムツール';

  @override
  String get sessMetaTaskTracking => 'タスク追跡';

  @override
  String get sessMetaCurrentTodos => '現在の TODO';

  @override
  String get sessMetaPlanRecords => 'プラン記録';

  @override
  String get sessMetaTodowriteReminder => 'TodoWrite リマインダー';

  @override
  String get sessMetaTriggered => '発動';

  @override
  String get sessMetaNotTriggered => '未発動';

  @override
  String get sessMetaUnavailable => '利用不可';

  @override
  String get sessMetaReminderReason => 'リマインダー理由';

  @override
  String get sessMetaPlanHistory => 'プラン履歴';

  @override
  String get sessMetaRecentErrors => '最近のエラー';

  @override
  String get sessMetaThereAreNoSessionErrorsTo => '確認するセッションエラーはありません。';

  @override
  String get sessMetaLastPromptMetadata => '最後のプロンプトメタデータ';

  @override
  String get sessMetaClose => '閉じる';

  @override
  String get sessMetaPendingApproval => '承認待ち';

  @override
  String get sessMetaInProgress => '進行中';

  @override
  String get sessMetaCompleted => '完了';

  @override
  String get sessMetaFailed => '失敗';

  @override
  String get sessMetaCancelled => 'キャンセル';

  @override
  String get sessMetaCreated => '作成日時';

  @override
  String get sessMetaUpdated => '更新日時';

  @override
  String get sessMetaErrorDetail => 'エラー詳細';

  @override
  String get commonDetails => '詳細';

  @override
  String get commonCopy => 'コピー';

  @override
  String get commonViewDetails => '詳細を表示';

  @override
  String get commonCopiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get structuredErrorWhy => '理由:';

  @override
  String get structuredErrorTry => '試すこと:';

  @override
  String get structuredErrorServerSays => 'サーバー応答:';

  @override
  String get structuredErrorRaw => '元のエラー:';

  @override
  String get sessMetaPresented => '表示';

  @override
  String get sessMetaThisSessionEndedEarlyRetryThe =>
      'このセッションは途中で終了しました。リクエストをリトライするか、より具体的な指示で続行してください。';

  @override
  String get sessMetaToolCallsStoppedForSafety => '安全のためツール呼び出しを停止';

  @override
  String get sessMetaOpenhandStoppedThisSessionForSafety =>
      '連続ツールラウンドが多すぎたため、OpenHand は安全のためこのセッションを停止しました。この停止は次のツールが実行される前にセッションコントローラで発生したものであり、特定のツール実行が失敗したわけではありません。アシスタントに現在の進捗を要約させるか、より具体的な次のステップを指示してください。';

  @override
  String get sessMetaResponseInterrupted => '応答が中断されました';

  @override
  String get sessMetaTheResponseWasInterruptedWhileStreaming =>
      'ストリーミング中に応答が中断され、このセッションは停止しました。リクエストをリトライするか、新しいメッセージで続行してください。';

  @override
  String get sessMetaRequestFailed => 'リクエストが失敗しました';

  @override
  String get sessMetaTheRequestFailedBeforeTheAssistant =>
      'アシスタントが続行する前にリクエストが失敗しました。設定を確認してリトライするか、新しいメッセージを送ってください。';

  @override
  String get sessMetaContinuationFailed => '継続が失敗しました';

  @override
  String get sessMetaTheSessionFailedWhileRequestingThe =>
      '実行を継続した後、次のアシスタントラウンドのリクエスト中にセッションが失敗しました。完了したステップとツール結果は保持されています。「continue/retry」と返信するか、設定を確認してから再度お試しください。';

  @override
  String get sessMetaSafetyStop => '安全停止';

  @override
  String get sessMetaStreamError => 'ストリームエラー';

  @override
  String get sessMetaRequestError => 'リクエストエラー';

  @override
  String get sessMetaContinuationError => '継続エラー';

  @override
  String get sessMetaToolExecutionError => 'ツール実行エラー';

  @override
  String get sessMetaCompressionError => '圧縮エラー';

  @override
  String get sessMetaPromptBlocked => 'プロンプトブロック';

  @override
  String get sessMetaTitleGenerationError => 'タイトル生成エラー';

  @override
  String get sessMetaSessionError => 'セッションエラー';

  @override
  String get auditNoData => 'データなし';

  @override
  String get auditCopyJson => 'JSON をコピー';

  @override
  String get auditCopiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get auditMessageAudit => 'メッセージ監査';

  @override
  String get auditClose => '閉じる';

  @override
  String get auditOverview => '概要';

  @override
  String get auditMessageId => 'メッセージ ID';

  @override
  String get auditSessionId => 'セッション ID';

  @override
  String get auditRole => 'ロール';

  @override
  String get auditKind => '種別';

  @override
  String get auditCharacterCount => '文字数';

  @override
  String get auditStreaming => 'ストリーミング';

  @override
  String get auditDeleted => '削除済み';

  @override
  String get auditHasError => 'エラーあり';

  @override
  String get auditTiming => 'タイミング';

  @override
  String get auditStartedCreated => '開始 / 作成';

  @override
  String get auditEnded => '終了';

  @override
  String get auditDurationMs => '所要時間 (ms)';

  @override
  String get auditModelTokens => 'モデルとトークン';

  @override
  String get auditModelId => 'モデル ID';

  @override
  String get auditModelLabel => 'モデルラベル';

  @override
  String get auditTotalTokens => '合計トークン';

  @override
  String get auditCacheHitRatio => 'キャッシュヒット率';

  @override
  String get auditPromptTokens => 'プロンプトトークン';

  @override
  String get auditCompletionTokens => '応答トークン';

  @override
  String get auditTokenBreakdown => 'トークン内訳';

  @override
  String get auditError => 'エラー';

  @override
  String get auditContent => 'コンテンツ';

  @override
  String get auditFullComposedPromptThatWasActually =>
      'このラウンドで実際に AI に送信された完全な合成プロンプト（システム指示、ツールカタログ、メモリ、履歴、ユーザー入力）。';

  @override
  String get auditWaitingForComposedPromptInjectionAuto =>
      '合成プロンプトの注入を待っています（ストリーミング中に自動更新）。';

  @override
  String get auditUserRawInput => 'ユーザーの生入力';

  @override
  String get auditStructuredPromptTurns => '構造化プロンプトターン';

  @override
  String get auditNone => 'なし';

  @override
  String get auditPromptMetadata => 'プロンプトメタデータ';

  @override
  String get auditRequest => 'リクエスト';

  @override
  String get auditMethod => 'メソッド';

  @override
  String get auditHeaders => 'ヘッダー';

  @override
  String get auditNotCapturedEnableSettingsAiTelemetry =>
      '未取得（設定 → AI → テレメトリデバッグを有効化してください）';

  @override
  String get auditBodyQueryPath => 'ボディ / クエリ / パス';

  @override
  String get auditRawAiResponse => 'AI 生レスポンス';

  @override
  String get auditExpandRawResponse => '生レスポンスを展開';

  @override
  String get auditNotCapturedDebugDisabledOrResponse =>
      '未取得：デバッグが無効、または応答が利用できません';

  @override
  String get auditAttachments => '添付ファイル';

  @override
  String get auditAttachmentList => '添付ファイル一覧';

  @override
  String get auditNoAttachments => '添付ファイルなし';

  @override
  String get auditFullMetadata => '完全なメタデータ';

  @override
  String get auditMessageMetadata => 'メッセージメタデータ';

  @override
  String get auditSessionEnvironment => 'セッション環境';

  @override
  String get auditEnvironmentSnapshot => '環境スナップショット';

  @override
  String get auditAuditSnapshotCopied => '監査スナップショットをコピーしました';

  @override
  String get auditCopyAuditSnapshot => '監査スナップショットをコピー';

  @override
  String get auditSessionMetadataSaved => 'セッションメタデータを保存しました';

  @override
  String get auditSessionAudit => 'セッション監査';

  @override
  String get auditTemplate => 'テンプレート';

  @override
  String get auditCreatedAt => '作成日時';

  @override
  String get auditUpdatedAt => '更新日時';

  @override
  String get auditMessages => 'メッセージ';

  @override
  String get auditLastModel => '最後のモデル';

  @override
  String get auditTitleEditable => 'タイトル（編集可）';

  @override
  String get auditSessionTitle => 'セッションタイトル';

  @override
  String get auditSaveTitle => 'タイトルを保存';

  @override
  String get auditSessionMetadataEditableJson => 'セッションメタデータ（編集可能 JSON）';

  @override
  String get auditSaveWritesBackThroughTheSession =>
      '保存はセッションコントローラ経由でライブ UI 差分とともに書き戻されます。削除されたキーはクリアされます。';

  @override
  String get auditSaveMetadata => 'メタデータを保存';

  @override
  String get auditRuntimePromptMetadataReadOnly => 'ランタイムプロンプトメタデータ（読み取り専用）';

  @override
  String get auditUsefulForPromptConstructionTroubleshooti =>
      'プロンプト構築のトラブルシューティングに有用です。ランタイムにより自動更新されます。';

  @override
  String get auditLastPromptMetadata => 'last_prompt_metadata';

  @override
  String get auditNoRuntimePromptMetadataYet => 'ランタイムプロンプトメタデータはまだありません';

  @override
  String get auditEnvironment => '環境';

  @override
  String get auditErrorList => 'エラー一覧';

  @override
  String get auditNoErrorsRecorded => '記録されたエラーはありません';

  @override
  String get auditTapARowToInspectA => '行をタップしてメッセージを確認します。削除でストレージから削除されます。';

  @override
  String get auditNoMessages => 'メッセージなし';

  @override
  String get auditAudit => '監査';

  @override
  String get auditDelete => '削除';

  @override
  String get progExpFESelectOpenedFile => '開いたファイルを選択';

  @override
  String get progExpFEExpandSelected => '選択を展開';

  @override
  String get progExpFECollapseAll => 'すべて折りたたむ';

  @override
  String get progExpFETypeASymbolNameToSearch =>
      'シンボル名を入力して、現在のワークスペースのファイル全体を検索します。';

  @override
  String get progExpFENoWorkspaceSymbolBackendIsAvailable =>
      '現在のファイルに対応するワークスペースシンボルバックエンドはありません。';

  @override
  String get progExpFENoMatchingWorkspaceSymbolsWereFound =>
      '一致するワークスペースシンボルは見つかりませんでした。';

  @override
  String get progExpFEFetchingWorkspaceSymbolsFailedConfirmTha =>
      'ワークスペースシンボルの取得に失敗しました。アクティブな言語サーバーが workspace/symbol をサポートしているか確認してください。';

  @override
  String get progExpFEThisFileIsStillInLarge =>
      'このファイルはまだ大きなファイルプレビューモードのため、シンボルバーは応答性を維持するためにローカル抽出を使用しています。';

  @override
  String get progExpFENoLspSymbolBackendIsAvailable =>
      'このファイルに対応する LSP シンボルバックエンドがないため、シンボルバーはローカル抽出にフォールバックしました。';

  @override
  String get progExpFETheLspServerReturnedAnEmpty =>
      'LSP サーバーは空のシンボルリストを返しました。';

  @override
  String get progExpFEFetchingLspSymbolsFailedSoThe =>
      'LSP シンボルの取得に失敗したため、シンボルバーはローカル抽出にフォールバックしました。';

  @override
  String get progExpFERenameSymbol => 'シンボル名を変更';

  @override
  String get progExpFEReviewTheDiffForThisRename =>
      '適用するかどうかを判断する前に、この名前変更の差分を確認してください。';

  @override
  String get progExpFETheRenameWasCancelledAndNo =>
      '名前変更はキャンセルされ、変更は適用されませんでした。';

  @override
  String get progExpFETheSymbolAtTheCurrentCursor =>
      '現在のカーソル位置のシンボルは名前変更できません。';

  @override
  String get progExpFETheLanguageServerDidNotReturn =>
      '言語サーバーは適用する編集を返しませんでした。';

  @override
  String get progExpFECodeActions => 'コードアクション';

  @override
  String get progExpFENoCodeActionsAreAvailableAt =>
      '現在のカーソル位置で利用可能なコードアクションはありません。';

  @override
  String get progExpFEReviewTheDiffFromThisCode =>
      'このコードアクションを適用する前に差分を確認してください。';

  @override
  String get progExpFEIfTheLanguageServerCommandRequests =>
      '実行中に言語サーバーコマンドが編集を要求した場合、それらの編集も先にプレビューされます。';

  @override
  String get progExpFETheCodeActionWasCancelledAnd =>
      'コードアクションはキャンセルされ、変更は適用されませんでした。';

  @override
  String get progExpFEExecutedTheLanguageServerCommand => '言語サーバーコマンドを実行しました。';

  @override
  String get progExpFESomeLanguageServerRequestedEditsWere =>
      '言語サーバーが要求した一部の編集はスキップされました。';

  @override
  String get progExpFEThisCodeActionDidNotReturn =>
      'このコードアクションは適用可能な編集を返しませんでした。';

  @override
  String get progExpFEQuickFix => 'クイックフィックス';

  @override
  String get progExpFENoQuickFixesAreAvailableFor =>
      'ホバーしている診断にはクイックフィックスがありません。';

  @override
  String get progExpFENoCodeActionsAreAvailableFor =>
      'ホバーしている診断にはコードアクションがありません。';

  @override
  String get progExpFENoQuickFixesAreAvailableFor2 => 'この診断行にはクイックフィックスがありません。';

  @override
  String get progExpFETheCurrentFileIsStillLoading =>
      '現在のファイルはまだ読み込み中のため、LSP アクションはまだ利用できません。';

  @override
  String get progExpFEThisFileIsStillInLarge2 =>
      'このファイルはまだ大きなファイルプレビューモードです。LSP ナビゲーションを実行する前にフルエディタを開いてください。';

  @override
  String get progExpFETheCurrentFileIsStillLoading2 =>
      '現在のファイルはまだ読み込み中のため、ドキュメントレベルの編集アクションはまだ利用できません。';

  @override
  String get progExpFEThisFileIsStillInLarge3 =>
      'このファイルはまだ大きなファイルプレビューモードです。フォーマットを実行する前にフルエディタを開いてください。';

  @override
  String get progExpFEFormatDocument => 'ドキュメントをフォーマット';

  @override
  String get progExpFETheCurrentFileIsNotReady =>
      '現在のファイルはまだ準備できていません。少し待ってから再試行してください。';

  @override
  String get progExpFETheFormatterDidNotReturnAny => 'フォーマッタは適用する編集を返しませんでした。';

  @override
  String get progExpFEFormattingProducedTheSameContentSo =>
      'フォーマット結果は同一内容のため、テキストは変更されませんでした。';

  @override
  String get progExpFEGoToDefinition => '定義へ移動';

  @override
  String get progExpFENoDefinitionWasFoundAtThe => '現在のカーソル位置には定義が見つかりませんでした。';

  @override
  String get progExpFEMultipleDefinitionsWereFoundChooseA =>
      '複数の定義が見つかりました。移動先を選択してください。';

  @override
  String get progExpFEFindReferences => '参照を検索';

  @override
  String get progExpFENoReferencesWereFoundAtThe => '現在のカーソル位置には参照が見つかりませんでした。';

  @override
  String get progExpFEHoverInfo => 'ホバー情報';

  @override
  String get progExpFEThereIsNoHoverInformationAt => '現在のカーソル位置にホバー情報はありません。';

  @override
  String get progExpFELspBackend => 'LSP バックエンド';

  @override
  String get progExpFEReResolveTheBackendForThe => '現在のファイルのバックエンドを再解決';

  @override
  String get progExpFEInspectBackendDetails => 'バックエンドの詳細を確認';

  @override
  String get progExpFECloseEsc => '閉じる (Esc)';

  @override
  String get progExpFEToggleComment => 'コメントをトグル';

  @override
  String get progExpFEThisLanguageDoesNotHaveA =>
      'この言語にはコメント戦略がまだ設定されていないため、コメントトグルは利用できません。';

  @override
  String get progExpFEGoToImplementation => '実装へ移動';

  @override
  String get progExpFESignatureHelp => 'シグネチャヘルプ';

  @override
  String get progExpFEThereIsNoSignatureHelpAvailable =>
      '現在のカーソル位置にはシグネチャヘルプはありません。';

  @override
  String get progExpFEPreviousMatch => '前の一致';

  @override
  String get progExpFENextMatch => '次の一致';

  @override
  String get progExpFEMatchCase => '大文字小文字を区別';

  @override
  String get progExpFEShowReplace => '置換を表示';

  @override
  String get progExpFEReplaceCurrent => '現在を置換';

  @override
  String get progExpFEReplaceAll => 'すべて置換';

  @override
  String get progExpFECurrentFileSymbols => '現在のファイルのシンボル';

  @override
  String get progExpFEWorkspaceSymbols => 'ワークスペースシンボル';

  @override
  String get progExpFERefreshDiagnostics => '診断を更新';

  @override
  String get progExpFESymbols => 'シンボル';

  @override
  String get progExpFESymbolNavigationShiftCmdCtrlO =>
      'シンボルナビゲーション (Shift+Cmd/Ctrl+O)';

  @override
  String get progExpFEWorkspace => 'ワークスペース';

  @override
  String get progExpFEWorkspaceSymbolSearchCmdCtrlT =>
      'ワークスペースシンボル検索 (Cmd/Ctrl+T)';

  @override
  String get progExpFEShowDiagnosticsForTheCurrentFile => '現在のファイルの診断を表示';

  @override
  String get progExpFEInspectTheLspBackendBoundTo =>
      '現在のファイルにバインドされている LSP バックエンドを確認';

  @override
  String get progExpFEDef => '定義';

  @override
  String get progExpFEGoToDefinitionF12CmdCtrl => '定義へ移動 (F12 / Cmd/Ctrl+B)';

  @override
  String get progExpFERefs => '参照';

  @override
  String get progExpFEFindReferencesShiftF12CmdCtrl =>
      '参照を検索 (Shift+F12 / Cmd/Ctrl+Shift+B)';

  @override
  String get progExpFEHover => 'ホバー';

  @override
  String get progExpFEHoverInfoCmdCtrlI => 'ホバー情報 (Cmd/Ctrl+I)';

  @override
  String get progExpFERename => '名前変更';

  @override
  String get progExpFERenameSymbolF2 => 'シンボル名を変更 (F2)';

  @override
  String get progExpFEActions => 'アクション';

  @override
  String get progExpFECodeActionsCmdCtrl => 'コードアクション (Cmd/Ctrl+.)';

  @override
  String get progExpFEFormat => 'フォーマット';

  @override
  String get progExpFENoImplementationWasFoundAtThe =>
      '現在のカーソル位置には実装が見つかりませんでした。';

  @override
  String get progExpFEMultipleImplementationsFoundChooseATarge =>
      '複数の実装が見つかりました。移動先を選択してください。';

  @override
  String get progExpFERefactor => 'リファクタリング';

  @override
  String get progExpFEReviewTheChangesBeforeApplying => '適用する前に変更を確認してください。';

  @override
  String get progExpFESaveFile => 'ファイルを保存';

  @override
  String get progExpFECloseEditorReturnToSession => 'エディタを閉じてセッションに戻る';

  @override
  String get progExpFEShowQuickFixesForThisDiagnostic => 'この診断行のクイックフィックスを表示';

  @override
  String get progExpFELargeFilePerformanceModeIsActive =>
      '大きなファイルのパフォーマンスモードが有効：完全なドキュメントレイアウトの停滞を避けるため、仮想化された読み取り専用プレビューを使用しています。';

  @override
  String get progExpFEOpenFullEditorAnyway => 'それでもフルエディタを開く';

  @override
  String get settingsShortcuts => 'ショートカット';

  @override
  String get settingsConfigureKeyCombinationsForCommonActions =>
      '一般的な操作のキー組み合わせを設定します。OpenHand は最大 4 キーの同時押しに対応しています。';

  @override
  String get settingsBuiltInTools => '組み込みツール';

  @override
  String get settingsCrons => 'Cron';

  @override
  String get settingsControlsRetentionAndColdStartCleanup =>
      'Cron 実行履歴の保持期間とコールドスタート時のクリーンアップを制御します。クリーンアップワーカーはコールドスタートごとに 1 回だけ実行され、ハードタイムアウト、シングルフライトロック、silentLog のみの失敗で、リソースリークや無限ループを防ぎます。';

  @override
  String get settingsHermesTalker => 'ヘルメストーカー';

  @override
  String get settingsConfigureHermesTalkerSelfLearningEvery =>
      'Hermes Talker の自己学習を設定：5 分ごとにシステム Cron が過去 7 日間のセッションをスキャンし、制限されたサブエージェントをディスパッチしてバックグラウンドでメモリとスキルを更新します。';

  @override
  String get settingsEditor => 'エディタ';

  @override
  String get settingsManagePerLanguageLspBackendsInstall =>
      '言語別の LSP バックエンド、インストールルート、ダウンロードアシスタント設定を管理します。保存されたマッピングはエディタのナビゲーション、診断、名前変更、コードアクションに直接適用されます。';

  @override
  String get settingsAppData => 'アプリデータ';

  @override
  String get settingsPerResponseToolCallLimit => '応答ごとのツール呼び出し上限';

  @override
  String get settingsSaveLimit => '上限を保存';

  @override
  String get settingsSequentialToolRoundLimit => '連続ツールラウンド上限';

  @override
  String get settingsSessionSettings => 'セッション設定';

  @override
  String get settingsConfigureDefaultBehaviourForNewSessions =>
      '新しいセッションのデフォルト動作（タイムアウト、タイトル取得、デフォルトモード、権限など）を設定します。';

  @override
  String get settingsSendTimeoutS => '送信タイムアウト (秒)';

  @override
  String get settingsMaximumWaitTimeToEstablishThe =>
      'HTTP 接続を確立してリクエストを送信するための最大待機時間。既定値：60 秒。';

  @override
  String get settingsSaveTimeout => 'タイムアウトを保存';

  @override
  String get settingsResponseTimeoutS => '応答タイムアウト (秒)';

  @override
  String get settingsMaximumWaitForACompleteResponse =>
      '非ストリーミングモードで完全な応答を待つ最大時間。既定値：120 秒。';

  @override
  String get settingsStreamIdleTimeoutS => 'ストリームアイドルタイムアウト (秒)';

  @override
  String get settingsMaximumIdleWaitBetweenStreamChunks =>
      'ストリームチャンク間の最大アイドル待機時間。これを超えると「Request timed out.」となります。既定値：120 秒。';

  @override
  String get settingsAutoTitle => 'タイトルの自動取得';

  @override
  String get settingsWhenEnabledATitleIsAutomatically =>
      '有効にすると、新しいセッションの最初の有効なテキストメッセージ後にセッションタイトルを自動取得します。';

  @override
  String get settingsTitleFetchMode => 'タイトル取得方式';

  @override
  String get settingsTitleFetchModeDescription =>
      '非同期は最初の返信をブロックしません。同期は最初の AI リクエストを送信する前にタイトルを取得します。';

  @override
  String get settingsTitleFetchModeAsync => '非同期';

  @override
  String get settingsTitleFetchModeSync => '同期';

  @override
  String get settingsDefaultSessionMode => 'デフォルトセッションモード';

  @override
  String get settingsDefaultInteractionModeForNewSessions =>
      '新しいセッションのデフォルトのインタラクションモード：チャットまたはプラン。';

  @override
  String get settingsChat => 'チャット';

  @override
  String get settingsPlan => 'プラン';

  @override
  String get settingsDefaultFullAccess => 'デフォルトでフルアクセス';

  @override
  String get settingsWhenEnabledNewSessionsStartIn =>
      '有効にすると、新しいセッションはフルアクセスモードで開始され、AI はアクションごとの確認なしにファイルとコマンドの操作を実行できます。';

  @override
  String get settingsUserProfile => 'ユーザープロファイル';

  @override
  String get settingsMaintainAGlobalUserProfileLanguage =>
      'グローバルなユーザープロファイル（言語スタイル、関心領域、コミュニケーションの好み）を維持します。空でない場合、プロファイルはすべてのスレッドテンプレートのシステムプロンプトに織り込まれ、AI がパーソナライズされた印象を与えます。自己学習が段階的に洗練します。';

  @override
  String get settingsModelProviderManagement => 'モデルプロバイダー管理';

  @override
  String get settingsAddSelectTestAndMaintainModel =>
      'モデルプロバイダー設定を追加、選択、テスト、維持します。各プロバイダーは複数のモデルを提供できます。';

  @override
  String get settingsCompressionTrigger => '圧縮トリガー';

  @override
  String get settingsOnceTheUncompressedHistoryInA =>
      'スレッドの未圧縮履歴がこの値を超えると、OpenHand は新しい要約チェックポイントを作成します。';

  @override
  String get settingsToolCallOutputCompressionThreshold => 'ツール呼び出し出力の圧縮閾値';

  @override
  String get settingsWhenAToolCallReturnsMore =>
      '圧縮チェックポイントの作成時のみ使用します。このしきい値を超える過去のツール結果は構造化サマリになります。通常の会話では常に完全な結果をモデルへ渡します。既定値は 1024。';

  @override
  String get settingsDefaultsTo40IfOneAssistant =>
      '既定値 40。アシスタント応答 1 回のツール呼び出しがこの数を超えると、OpenHand は警告メッセージを投稿し、安全にラウンドを停止します。';

  @override
  String get settingsDefaultsTo24RoundsIfThe =>
      '既定値 24 ラウンド。各実行後にアシスタントが別のツールラウンドを要求し続けた場合、OpenHand はこのラウンド上限に達したら停止し、暴走するツールループを防ぎます。';

  @override
  String get settingsImageSizeLimit => '画像サイズ上限';

  @override
  String get settingsDefaultsTo1mbImageAttachmentsLarger =>
      '既定値 1MB。この上限を超える画像添付ファイルはエディタを開く前に自動圧縮され、上限内に格納されます。これによりセッションとプロンプトをコンパクトに保ちます。';

  @override
  String get settingsCostControl => 'コスト制御';

  @override
  String get settingsReduceTokenCostsByFreezingThe =>
      'Prompt の静的プレフィックスを安定させ、プロトコルレベルのキャッシュヒントを適用して token コストを削減します。有効にすると、最初の有効なユーザーメッセージへの AI 応答が始まった時点でプロバイダー、モデル、推論強度をロックし、Prompt Builder はシステム指示、ツールカタログ、メモリ、ユーザー指示を可能な限り安定した先頭セクションに保ちます。Anthropic は cache_control ブレークポイントを注入し、OpenAI 互換リクエストは安定したキャッシュアフィニティと messages を末尾に置く body レイアウトを使います。';

  @override
  String get settingsEnableInputCache => '入力キャッシュを有効化';

  @override
  String get settingsDisabledByDefaultWhenEnabledEvery =>
      '既定で有効です。無効にすると、プロトコルレベルのキャッシュヒント注入やモデルロックなどの入力キャッシュ保護は行われません。ヒット率を最大化するには、会話中にツール、スキル、MCP、メモリ、指示を頻繁に変更しないでください。';

  @override
  String get settingsCacheBreakpointUpdateMode => '履歴候補の更新モード';

  @override
  String get settingsChooseTheSlidingUnitForThe =>
      '安定アンカー、前回リクエスト末尾、現在末尾が優先されます。この設定は残りの履歴候補の選択方法のみを制御します。';

  @override
  String get settingsByMessageCountUserAssistant => 'メッセージ数（ユーザー＋アシスタント）';

  @override
  String get settingsByUserMessageCountOnly => 'ユーザーメッセージ数のみ';

  @override
  String get settingsByAccumulatedTokens => '累積トークン';

  @override
  String get settingsCacheBreakpointUpdateInterval => '履歴候補の更新間隔';

  @override
  String get settingsDefault10MeaningDependsOnThe =>
      '既定値 10。自動履歴候補にのみ使用され、単位は上記モードに従います。';

  @override
  String get settingsSave => '保存';

  @override
  String get settingsCacheBreakpointCount => 'キャッシュブレークポイント数';

  @override
  String get settingsDefault4Range14Anthropic =>
      '既定値 4、範囲 1-4。Anthropic は安定したシステム/ツールアンカー、前回リクエスト末尾、現在末尾、履歴候補の順に予算を使い、1 リクエストあたり最大 4 個の cache_control マーカーを設定します。OpenAI 互換プロバイダーにはこれらのマーカーを追加しません。';

  @override
  String get settingsCommandSafety => 'コマンドセーフティ';

  @override
  String get settingsControlWriteCommandConfirmationForBash =>
      'bash の書き込みコマンド確認を制御し、拒否ルールを一元管理します。';

  @override
  String get settingsWriteCommandConfirmation => '書き込みコマンドの確認';

  @override
  String get settingsEnabledByDefaultWhenTheAi =>
      '既定で有効。AI が書き込み系の bash コマンドを実行しようとすると、OpenHand は最初に確認を求めます。';

  @override
  String get settingsAllowCommandList => '許可コマンドリスト';

  @override
  String get settingsMatchingWriteLikeBashCommandsSkip =>
      '一致する書き込み系 bash コマンドは確認ダイアログをスキップして即座に実行されます。明示的に信頼する安定したコマンドパターンにのみ使用してください。';

  @override
  String get settingsAddAllowRule => '許可ルールを追加';

  @override
  String get settingsNoAllowRulesConfigured => '許可ルールは設定されていません';

  @override
  String get settingsAddARuleToLetMatching =>
      '一致する書き込みコマンドが確認をバイパスするルールを追加します。';

  @override
  String get settingsDenyCommandList => '拒否コマンドリスト';

  @override
  String get settingsMatchingBashCommandsAreBlockedBefore =>
      '一致する bash コマンドは実行前にブロックされ、代わりに拒否結果がモデルに返されます。`rm *` などの正規表現と単純なワイルドカードパターンに対応しています。';

  @override
  String get settingsAddRule => 'ルールを追加';

  @override
  String get settingsNoDenyRulesConfigured => '拒否ルールは設定されていません';

  @override
  String get settingsAddARuleToBlockMatching =>
      '一致する bash コマンドの実行前ブロックを行うルールを追加します。';

  @override
  String get settingsTelemetry => 'テレメトリ';

  @override
  String get settingsWhenEnabledOpenhandCapturesRawAi =>
      '有効にすると、OpenHand は AI の生応答、リクエストパラメータ、タイミング、エラーをキャプチャし、メッセージ／セッション監査ダイアログから確認できるようにします。';

  @override
  String get settingsDebugMode => 'デバッグモード';

  @override
  String get settingsOffByDefaultWhenEnabledEvery =>
      '既定でオフ。有効にすると、すべてのメッセージカードはホバー／フォーカス時に監査ピルを表示し、各セッションツールバーにセッションレベルの監査アクションが表示されます。';

  @override
  String get settingsCaptureRawPayload => '生ペイロードをキャプチャ';

  @override
  String get settingsEnabledByDefaultOnlyActiveWhen =>
      '既定で有効。デバッグモードがオンの場合のみ有効です。生の JSON/SSE チャンクをメッセージメタデータに添付して監査用に保存します。';

  @override
  String get settingsCaptureEnvironment => '環境情報をキャプチャ';

  @override
  String get settingsOffByDefaultOnlyActiveWhen =>
      '既定でオフ。デバッグモードがオンの場合のみ有効です。作業ディレクトリ、プラットフォーム詳細、プロセス環境変数（機密情報を含む可能性あり）をメッセージメタデータに添付します。注意してご使用ください。';

  @override
  String get settingsShortcutBindings => 'ショートカット割り当て';

  @override
  String get settingsClickRecordThenPressTheNew =>
      '録画をクリックし、新しいキー組み合わせを押してバインディングを更新します。モデルとセッションの切り替えは自動的にラップアラウンドします。';

  @override
  String get settingsShortcutRecord => '録画';

  @override
  String get settingsShortcutResetToDefault => '既定に戻す';

  @override
  String get settingsShortcutMaxKeysError => 'OpenHand は同時に最大 4 キーまで対応します。';

  @override
  String get settingsShortcutRecorderBody =>
      '新しいキー組み合わせを押すと、この割り当てを更新できます。OpenHand は同時に最大 4 キーまで対応します。';

  @override
  String get settingsShortcutRecorderTip =>
      'ヒント: Enter、P、矢印キーなど、修飾キー以外を少なくとも 1 つ含めてください。';

  @override
  String get settingsAutoCleanupExecutionHistory => '実行履歴の自動クリーンアップ';

  @override
  String get settingsOnEveryColdStartAnAsync =>
      'コールドスタートごとに非同期ワーカーが 1 回実行され、保持期間より古い履歴を削除します。ワーカーはシングルフライト、ハードタイムアウト付きで、サイレントログで失敗を記録するため、UI をブロックしたり無限ループしたりすることはありません。';

  @override
  String get settingsEnableSelfLearning => '自己学習を有効化';

  @override
  String get settingsWhenOffTheSchedulerSkipsEvery =>
      'オフの場合、スケジューラはすべての Hermes Talker セッションをスキップします。システム Cron エントリは保持されますが、サブエージェントはディスパッチされません。';

  @override
  String get settingsShowSelfLearningMessages => '自己学習メッセージを表示';

  @override
  String get settingsWhenOffSelfLearningCardsAre =>
      'オフの場合、「自己学習」カードはチャット画面から非表示になります（バックグラウンド学習は引き続き実行されます）。既定はオン。';

  @override
  String get settingsToolCatalogOverview => 'ツールカタログ概要';

  @override
  String get settingsResetAll => 'すべてリセット';

  @override
  String get settingsEnableAll => 'すべて有効化';

  @override
  String get settingsDisableAll => 'すべて無効化';

  @override
  String get settingsNoBuiltInToolConfigurations => '組み込みツールの設定はありません';

  @override
  String get settingsClickResetAllToRestoreThe =>
      '「すべてリセット」をクリックすると、デフォルトのツールリストが復元されます。';

  @override
  String get settingsResetBuiltInToolConfigs => '組み込みツール設定をリセット';

  @override
  String get settingsCancel => 'キャンセル';

  @override
  String get settingsReset => 'リセット';

  @override
  String get settingsDeleteCustomTool => 'カスタムツールを削除';

  @override
  String get settingsDelete => '削除';

  @override
  String get settingsSendTimeoutSaved => '送信タイムアウトを保存しました。';

  @override
  String get settingsResponseTimeoutSaved => '応答タイムアウトを保存しました。';

  @override
  String get settingsStreamIdleTimeoutSaved => 'ストリームアイドルタイムアウトを保存しました。';

  @override
  String get settingsCacheBreakpointUpdateIntervalSaved => '履歴候補の更新間隔を保存しました';

  @override
  String get settingsCacheBreakpointCountSaved => 'キャッシュブレークポイント数を保存しました';

  @override
  String get settingsCacheBreakpointPositions => '履歴キャッシュ候補';

  @override
  String get settingsCacheBreakpointPositionsSaved => '履歴キャッシュ候補を保存しました';

  @override
  String get cacheBarTopDescription =>
      '色付きバンドはプロンプト構造の参考表示です。P ピンはメッセージ履歴内の候補位置、右端の破線ピンは現在リクエストの末尾アンカーを示します。安定アンカーと連続末尾アンカーが優先されます。';

  @override
  String get cacheBarSectionSysLabel => '[0] システム';

  @override
  String get cacheBarSectionDevLabel => '[1] 開発者';

  @override
  String get cacheBarSectionToolsLabel => '[2] ツール';

  @override
  String get cacheBarSectionStateLabel => '[3s/3d] 状態';

  @override
  String get cacheBarSectionMemoryLabel => '[4] メモリ';

  @override
  String get cacheBarSectionUserInstLabel => '[4.5] 指示';

  @override
  String get cacheBarSectionSummaryLabel => '[5] 要約';

  @override
  String get cacheBarSectionHistoryLabel => '履歴';

  @override
  String get cacheBarSectionLatestLabel => '末尾 / 最新ターン';

  @override
  String get cacheBarSectionSysSummary =>
      'テンプレートシステム指示、ワークスペース指示、ランタイム環境スナップショット（OS / cwd / リポジトリ概要）。';

  @override
  String get cacheBarSectionSysCacheHint =>
      'キャッシュ向き：ターン間で非常に安定しており、最初のブレークポイントに最適。';

  @override
  String get cacheBarSectionDevSummary =>
      'アクティブなプロンプトテンプレートの動作ルール（出力フォーマットとガードレール）。';

  @override
  String get cacheBarSectionDevCacheHint => 'キャッシュ向き：セッション内ではほぼ変化しない。';

  @override
  String get cacheBarSectionToolsSummary =>
      '組み込みツールカタログ、MCP 機能、モデルが呼び出せるスキルローダー（DSML 呼び出しルール付き）。';

  @override
  String get cacheBarSectionToolsCacheHint =>
      '比較的安定：ツールレジストリが変わらない限りキャッシュにヒットしやすい。';

  @override
  String get cacheBarSectionStateSummary =>
      'セッションメタデータ JSON：カウンター、ToDo、計画フラグ、添付など。';

  @override
  String get cacheBarSectionStateCacheHint =>
      '変動的：毎ターンでカウンターが更新されるため、ここに置くとキャッシュミスしやすい。';

  @override
  String get cacheBarSectionMemorySummary => '長期ユーザーメモリの事実を暗黙知として統合。';

  @override
  String get cacheBarSectionMemoryCacheHint => '概ね安定：メモリ項目が編集されたときのみ変化する。';

  @override
  String get cacheBarSectionUserInstSummary =>
      'ユーザーが作成した再利用可能なプロンプト断片（プロジェクトレベルのガイダンス）。';

  @override
  String get cacheBarSectionUserInstCacheHint =>
      '安定：ほとんど編集されないため、この後ろにブレークポイントを置くと安全。';

  @override
  String get cacheBarSectionSummarySummary => '以前の会話の圧縮要約 + 最近のチャット抜粋。';

  @override
  String get cacheBarSectionSummaryCacheHint => '緩やかに進化：圧縮が再生成されたときのみ更新される。';

  @override
  String get cacheBarSectionHistorySummary =>
      '現在のセッション内の過去のユーザー / アシスタント / ツールターン。';

  @override
  String get cacheBarSectionHistoryCacheHint =>
      '追加のみ：履歴中央のブレークポイントは末尾の新ターンでも有効。';

  @override
  String get cacheBarSectionLatestSummary => '現在回答中のユーザーメッセージ（添付メタデータを含む）。';

  @override
  String get cacheBarSectionLatestCacheHint =>
      '毎ターン変化します。現在末尾アンカーがこの領域を覆い、前回末尾アンカーが連続性を維持します。';

  @override
  String get cacheBarDynamicTooltip => '現在リクエストの末尾アンカー — 常に最新メッセージに追従します。';

  @override
  String get cacheBarDynamicSuffix => '（現在末尾）';

  @override
  String get cacheBarResetEven => '均等にリセット';

  @override
  String get settingsAiBudgetUsdPerSession => 'セッションごとの予算（USD）';

  @override
  String get settingsAiBudgetUsdPerSessionBody =>
      '0 で警告を無効化します。セッションの累積推定コストがこの上限を超えると、セッションメタデータダイアログで警告色として表示されます。ソフトなリマインダーであり、会話を中断したり送信をブロックしたりはしません。';

  @override
  String get settingsAiBudgetUsdPerSessionInvalid => '0〜100000 の非負数を入力してください。';

  @override
  String get settingsAiBudgetUsdPerSessionSaved => 'セッション予算を保存しました';

  @override
  String sessionMetadataOverBudgetNotice(String total, String budget) {
    return '現在のセッションの推定コスト $total が予算 $budget を超えています。ソフトなリマインダーで、送信には影響しません。';
  }

  @override
  String get settingsEnterAToolCallLimitGreater => '0 より大きいツール呼び出し上限を入力してください。';

  @override
  String get settingsThePerResponseToolCallLimit => '応答ごとのツール呼び出し上限を保存しました。';

  @override
  String get settingsEnterASequentialToolRoundLimit =>
      '0 より大きい連続ツールラウンド上限を入力してください。';

  @override
  String get settingsTheSequentialToolRoundLimitHas => '連続ツールラウンド上限を保存しました。';

  @override
  String get settingsDeleteDenyRule => '拒否ルールを削除';

  @override
  String get settingsTheDenyCommandRuleHasBeen => '拒否コマンドルールを削除しました。';

  @override
  String get settingsDeleteAllowRule => '許可ルールを削除';

  @override
  String get settingsTheAllowCommandRuleHasBeen => '許可コマンドルールを削除しました。';

  @override
  String get settingsTheShortcutHasBeenUpdated => 'ショートカットを更新しました。';

  @override
  String get settingsTheEditorShortcutHasBeenUpdated => 'エディタショートカットを更新しました。';

  @override
  String get settingsSendMessage => 'メッセージを送信';

  @override
  String get settingsCollapseOrExpandComposer => '入力欄を折りたたむ／展開';

  @override
  String get settingsPreviousModel => '前のモデル';

  @override
  String get settingsNextModel => '次のモデル';

  @override
  String get settingsToggleAutoFollow => '自動追従をトグル';

  @override
  String get settingsPreviousSession => '前のセッション';

  @override
  String get settingsNextSession => '次のセッション';

  @override
  String get settingsSaveFile => 'ファイルを保存';

  @override
  String get settingsTriggerCompletion => '補完をトリガー';

  @override
  String get settingsShowSignatureHelp => 'シグネチャヘルプを表示';

  @override
  String get settingsFind => '検索';

  @override
  String get settingsFindAndReplace => '検索と置換';

  @override
  String get settingsGoToLine => '行へ移動';

  @override
  String get settingsDocumentSymbols => 'ドキュメントシンボル';

  @override
  String get settingsWorkspaceSymbols => 'ワークスペースシンボル';

  @override
  String get settingsGoToDefinition => '定義へ移動';

  @override
  String get settingsFindReferences => '参照を検索';

  @override
  String get settingsGoToImplementation => '実装へ移動';

  @override
  String get settingsShowHoverInfo => 'ホバー情報を表示';

  @override
  String get settingsRenameSymbol => 'シンボル名を変更';

  @override
  String get settingsCodeActions => 'コードアクション';

  @override
  String get settingsFormatDocument => 'ドキュメントをフォーマット';

  @override
  String get settingsDefaultsToCtrlEnterAndTriggers =>
      '既定は Ctrl + Enter で、チャット入力欄が準備できているときに送信ボタンをトリガーします。';

  @override
  String get settingsDefaultsToCtrlPForQuickly =>
      '既定は Ctrl + P で、入力欄を素早く折りたたむ／展開します。';

  @override
  String get settingsDefaultsToCtrlLeftAndWraps =>
      '既定は Ctrl + 左で、必要に応じて最後のモデルへラップアラウンドします。';

  @override
  String get settingsDefaultsToCtrlRightAndWraps =>
      '既定は Ctrl + 右で、必要に応じて最初のモデルへラップアラウンドします。';

  @override
  String get settingsDefaultsToCtrlSForToggling =>
      '既定は Ctrl + S で、自動追従をトグルします。';

  @override
  String get settingsDefaultsToCtrlUpAndWraps =>
      '既定は Ctrl + 上で、セッションリストの末尾へラップアラウンドします。';

  @override
  String get settingsDefaultsToCtrlDownAndWraps =>
      '既定は Ctrl + 下で、セッションリストの先頭へラップアラウンドします。';

  @override
  String get settingsUndoLastFileMutation => '最近のファイル変更を元に戻す';

  @override
  String get settingsDefaultsToCtrlShiftZForUndo =>
      '既定は Ctrl + Shift + Z。現在セッションの ledger で最新の元に戻せるファイル変更を取り消します。';

  @override
  String get auditDeleteMessage => 'メッセージを削除';

  @override
  String get auditDeleteThisMessageThisCannotBe => 'このメッセージを削除しますか？元に戻せません。';

  @override
  String get auditCancel => 'キャンセル';

  @override
  String get settingsManageTheBuiltInAiTools =>
      '組み込みの AI ツールを管理します。各ツールの有効状態、名前、説明、スキーマ、優先度などを調整します。';

  @override
  String get settingsManageTheLocalFilesAndDatabase =>
      'OpenHand がディスク上に保持するローカルファイルとデータベーステーブルを管理します。すべてのクリーンアップは UI をブロックしないようバックグラウンドのワーカーで実行されます。';

  @override
  String get settingsThisWillRestoreAllBuiltIn =>
      'これにより、すべての組み込みツール設定が工場出荷時のデフォルト（名前、説明、スキーマなどを含む）に復元されます。';

  @override
  String get tlCallUnwrap => '折り返しを解除';

  @override
  String get tlCallWrapLines => '行を折り返す';

  @override
  String get tlCallViewCompressedContent => '圧縮されたコンテンツを表示';

  @override
  String get tlCallViewFullContent => '完全なコンテンツを表示';

  @override
  String get tlCallPreparing => '準備中';

  @override
  String get tlCallPreparingAlt => '準備中';

  @override
  String get tlCallRunningAlt => '実行中';

  @override
  String get tlCallCompleted => '完了';

  @override
  String get tlCallCompletedAlt => '完了';

  @override
  String get tlCallTimedOutAlt => 'タイムアウト';

  @override
  String get tlCallFailedAlt => '失敗';

  @override
  String tlCallFailedToOpenFileLocationError(Object error) {
    return 'ファイルの場所を開けませんでした：$error';
  }

  @override
  String tlCallMemoryitemsLengthMemoriesUpdated(Object memoryItems_length) {
    return '$memoryItems_length 件のメモリを更新';
  }

  @override
  String tlCallProfileitemsLengthProfileChanges(Object profileItems_length) {
    return '$profileItems_length 件のプロファイル変更';
  }

  @override
  String tlCallSkillitemsLengthSkillsUpdated(Object skillItems_length) {
    return '$skillItems_length 件のスキルを更新';
  }

  @override
  String get tlCallAiThinkingStreaming => 'AI が思考中（ストリーミング）';

  @override
  String get tlCallAiThinking => 'AI が思考中';

  @override
  String get tlCallAiResponseStreaming => 'AI 応答（ストリーミング）';

  @override
  String get tlCallAiResponse => 'AI 応答';

  @override
  String tlCallAndItemsLength3More(Object items_length_3, Object items_length) {
    return ' 他 $items_length_3 件';
  }

  @override
  String tlCallSecondsSAgo(Object seconds) {
    return '$seconds 秒前';
  }

  @override
  String tlCallMinutesMAgo(Object minutes) {
    return '$minutes 分前';
  }

  @override
  String tlCallHoursHAgo(Object hours) {
    return '$hours 時間前';
  }

  @override
  String tlCallDaysDAgo(Object days) {
    return '$days 日前';
  }

  @override
  String sessMetaPlanPlanindex(Object planIndex) {
    return 'プラン #$planIndex';
  }

  @override
  String sessMetaTheCurrentSequentialToolRoundLimit(Object configuredLimit) {
    return '現在の連続ツールラウンド上限は $configuredLimit です。';
  }

  @override
  String auditInvalidJsonErrorMessage(Object error_message) {
    return '無効な JSON：$error_message';
  }

  @override
  String auditSaveFailedError(Object error) {
    return '保存に失敗しました：$error';
  }

  @override
  String auditRecentErrorsSessionRecenterrorsLength(
    Object session_recentErrors_length,
  ) {
    return '最近のエラー ($session_recentErrors_length)';
  }

  @override
  String auditMessagesSessionMessagesLength(Object session_messages_length) {
    return 'メッセージ ($session_messages_length)';
  }

  @override
  String progExpFEAppliedEditsLengthFormattingEdits(Object edits_length) {
    return '$edits_length 件のフォーマット編集を適用しました。';
  }

  @override
  String progExpFEFormatTheCurrentFileFormatshortcut(Object formatShortcut) {
    return '現在のファイルをフォーマット ($formatShortcut)';
  }

  @override
  String progExpFENoCodeactionkindRefactoringIsAvailableAt(
    Object codeActionKind,
  ) {
    return '現在の位置で「$codeActionKind」リファクタリングは利用できません。';
  }

  @override
  String get progExpFEHideFileBrowser => 'ファイルブラウザを隠す';

  @override
  String get progExpFEShowFileBrowser => 'ファイルブラウザを表示';

  @override
  String settingsRetentionWindowRetentionDayS(Object retention) {
    return '保持期間：$retention 日';
  }

  @override
  String settingsRangeMinrMaxrDaysDefault7(Object minR, Object maxR) {
    return '範囲 $minR–$maxR 日、既定値 7。次回のコールドスタートで反映されます。';
  }

  @override
  String settingsConcurrentWorkersConcurrency(Object concurrency) {
    return '同時実行ワーカー：$concurrency';
  }

  @override
  String settingsCapsHowManySessionsCanBe(Object minC, Object maxC) {
    return '1 ティックあたり並列にディスパッチできるセッション数の上限 ($minC–$maxC)。既定値 5。';
  }

  @override
  String settingsSortedLengthBuiltInToolsEnabledcount(
    Object sorted_length,
    Object enabledCount,
  ) {
    return '組み込みツール $sorted_length 件、有効化 $enabledCount 件。名前、説明、スキーマ、優先度などを調整できます。';
  }

  @override
  String settingsAreYouSureYouWantTo(Object config_effectiveName) {
    return '「$config_effectiveName」を削除してもよろしいですか？元に戻せません。';
  }

  @override
  String settingsEnterAValueBetweenMinAnd(Object min, Object max) {
    return '$min から $max 秒の間の値を入力してください。';
  }

  @override
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn(
    Object AppSettingsSnapshot_minAiInputCacheUpdateInterval,
    Object AppSettingsSnapshot_maxAiInputCacheUpdateInterval,
  ) {
    return '$AppSettingsSnapshot_minAiInputCacheUpdateInterval から $AppSettingsSnapshot_maxAiInputCacheUpdateInterval までの整数を入力してください。';
  }

  @override
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn2(
    Object AppSettingsSnapshot_minAiInputCacheBreakpointCount,
    Object AppSettingsSnapshot_maxAiInputCacheBreakpointCount,
  ) {
    return '$AppSettingsSnapshot_minAiInputCacheBreakpointCount から $AppSettingsSnapshot_maxAiInputCacheBreakpointCount までの整数を入力してください。';
  }

  @override
  String settingsDragTheThumbcountThumbsToPosition(Object thumbCount) {
    return '$thumbCount 個の点をドラッグして履歴候補を設定します（0%-100%）。安定アンカーと連続末尾アンカーが先に予算を使い、右端の点は現在リクエスト末尾に固定されます。';
  }

  @override
  String get settingsTheDenyCommandRuleHasBeen2 => '拒否コマンドルールを更新しました。';

  @override
  String get settingsTheAllowCommandRuleHasBeen2 => '許可コマンドルールを更新しました。';

  @override
  String settingsDefaultsToDefaultlabelAndSavesThe(Object defaultLabel) {
    return '既定は $defaultLabel で、現在のファイルを保存します。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndOpensThe(Object defaultLabel) {
    return '既定は $defaultLabel で、必要に応じて補完ポップアップを開きます。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsMethod(Object defaultLabel) {
    return '既定は $defaultLabel で、現在のシンボルのメソッドシグネチャ、パラメータ詳細、サマリドキュメントを表示します。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe(Object defaultLabel) {
    return '既定は $defaultLabel で、検索パネルをトグルします。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe2(Object defaultLabel) {
    return '既定は $defaultLabel で、置換パネルをトグルします。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe3(Object defaultLabel) {
    return '既定は $defaultLabel で、行へ移動パネルをトグルします。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe4(Object defaultLabel) {
    return '既定は $defaultLabel で、現在のファイルのシンボル一覧をトグルします。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe5(Object defaultLabel) {
    return '既定は $defaultLabel で、ワークスペースシンボル検索パネルをトグルします。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndJumpsTo(Object defaultLabel) {
    return '既定は $defaultLabel で、現在のシンボル定義へジャンプします。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndFindsReferences(Object defaultLabel) {
    return '既定は $defaultLabel で、現在のシンボルの参照を検索します。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndJumpsTo2(Object defaultLabel) {
    return '既定は $defaultLabel で、現在の実装へジャンプします。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsType(Object defaultLabel) {
    return '既定は $defaultLabel で、現在の位置の型またはドキュメント情報を表示します。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndStartsRename(Object defaultLabel) {
    return '既定は $defaultLabel で、現在のシンボルの名前変更を開始します。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsAvailable(Object defaultLabel) {
    return '既定は $defaultLabel で、利用可能なコードアクションを表示します。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndFormatsThe(Object defaultLabel) {
    return '既定は $defaultLabel で、現在のプログラミングファイルをフォーマットします。Shift+Tab は最初にインデントを下げます。';
  }

  @override
  String progExpFEResolvedLspBackendForCurrentFile(
    Object lspName,
    Object projLang,
    Object fileLang,
    Object modeLine,
    Object sdkSourceLine,
    Object lspSourceLine,
    Object rootPath,
    Object command,
  ) {
    return '現在のファイルに対して $lspName を解決しました。\nプロジェクト言語：$projLang\n現在のファイル言語：$fileLang\n$modeLine\n$sdkSourceLine\n$lspSourceLine\nワークスペース：$rootPath\nコマンド：$command';
  }

  @override
  String get settingsReduceMotionLabel => 'モーションを減らす';

  @override
  String get settingsReduceMotionBody =>
      '有効にすると、自社カスタムおよび Flutter 組み込みアニメーションの時間がゼロになります。OS の「視差効果を減らす」と併用できます。';

  @override
  String get mcpToolSearchReplayLastCancelAction => '直前のキャンセルを再実行';

  @override
  String get mcpToolSearchReplayLastCancelToastFired =>
      '直前のキャンセル済み読み込みを再実行しました';

  @override
  String get mcpToolSearchReplayLastCancelToastEmpty => '再実行できる項目はありません';

  @override
  String get aiThrottleSettingsLabel => 'スロットル設定';

  @override
  String get aiThrottleSettingsBody =>
      'ストリーミングスロットル一元管理：マスタースイッチ、自動モード、文字／カード速度、継続時間。';

  @override
  String get webReverseVitalsInstalling => 'Installing observers…';

  @override
  String get webReverseVitalsResetting => 'Resetting…';

  @override
  String get webReverseVitalsReportCopied => 'Report JSON copied';

  @override
  String get webReverseVitalsTitle => 'Web Vitals';

  @override
  String get webReverseVitalsSubtitle =>
      'PerformanceObserver · LCP / CLS / INP / FCP / TTFB · live';

  @override
  String get webReverseVitalsCopyJson => 'Copy JSON';

  @override
  String get webReverseVitalsReset => 'Reset';

  @override
  String get webReverseVitalsClose => 'Close';

  @override
  String get webReverseVitalsThresholdsHint =>
      'Thresholds per web.dev. After reset, reload or interact to retrigger LCP / event samples.';

  @override
  String get webReverseIssuesCopied => 'Issue JSON copied';

  @override
  String get webReverseIssuesTitle => 'Issues';

  @override
  String get webReverseIssuesSubtitle => 'Audits.issueAdded · live aggregator';

  @override
  String get webReverseIssuesClearBuffer => 'Clear buffer';

  @override
  String get webReverseIssuesClose => 'Close';

  @override
  String get webReverseIssuesFilterHint =>
      'Filter by code / URL / description…';

  @override
  String get webReverseIssuesEmptyBuffer =>
      'No issues reported yet. Interact with the page.';

  @override
  String get webReverseIssuesNoMatch => 'No matching issue.';

  @override
  String get webReverseIssuesCopyJson => 'Copy JSON';

  @override
  String get webReverseIssuesCollapse => 'Collapse';

  @override
  String get webReverseIssuesExpand => 'Expand';

  @override
  String get webReverseIssuesSubscribed => 'Subscribed to Audits.issueAdded';

  @override
  String get webReverseIssuesAuditsNotReady => 'Audits domain not ready';

  @override
  String get webReverseRenderingResetSuccess => 'Rendering overrides reset';

  @override
  String get webReverseRenderingTitle => 'Rendering';

  @override
  String get webReverseRenderingSubtitle =>
      'Paint · Layout shift · Layers · FPS · media · CPU throttle';

  @override
  String get webReverseRenderingResetAll => 'Reset all';

  @override
  String get webReverseRenderingClose => 'Close';

  @override
  String get webReverseRenderingSectionOverlays => 'Overlays';

  @override
  String get webReverseRenderingPaintFlashingDesc =>
      'Highlight repainted regions';

  @override
  String get webReverseRenderingLayoutShiftDesc => 'Visualize CLS regions';

  @override
  String get webReverseRenderingLayerBordersDesc => 'Composited layer borders';

  @override
  String get webReverseRenderingScrollBottleneckDesc => 'Slow-scroll regions';

  @override
  String get webReverseRenderingHitTestDesc => 'Element hit-test borders';

  @override
  String get webReverseRenderingFpsDesc => 'Live FPS overlay';

  @override
  String get webReverseRenderingWebVitalsDesc =>
      'LCP / CLS / INP floating layer';

  @override
  String get webReverseRenderingSectionPerf => 'Performance emulation';

  @override
  String get webReverseRenderingSectionMedia => 'Media emulation';

  @override
  String get webReverseRenderingLabelColorScheme => 'Color scheme';

  @override
  String get webReverseRenderingLabelReducedMotion => 'Reduced motion';

  @override
  String get webReverseRenderingLabelMediaType => 'Media type';

  @override
  String get webReverseRenderingCpuThrottling => 'CPU throttling';

  @override
  String get webReverseAnimationsTitle => 'Animations';

  @override
  String get webReverseAnimationsSubtitle =>
      'CDP Animation.setPlaybackRate + document.getAnimations() snapshot';

  @override
  String get webReverseAnimationsCopyJson => 'Copy JSON';

  @override
  String get webReverseAnimationsRefresh => 'Refresh';

  @override
  String get webReverseAnimationsGlobalRate => 'Global rate';

  @override
  String get webReverseAnimationsPauseSymbol => 'Pause';

  @override
  String get webReverseAnimationsBulkPause => 'Pause all';

  @override
  String get webReverseAnimationsBulkResume => 'Resume all';

  @override
  String get webReverseAnimationsBulkCancel => 'Cancel all';

  @override
  String get webReverseAnimationsEmptyState =>
      'No active animations. Trigger one and refresh.';

  @override
  String get webReverseAnimationsRowPause => 'Pause';

  @override
  String get webReverseAnimationsRowPlay => 'Play';

  @override
  String get webReverseAnimationsRowCancel => 'Cancel';

  @override
  String get webReverseAnimationsClose => 'Close';

  @override
  String get webReverseAnimationsNoSnapshot => 'no snapshot returned';

  @override
  String get webReverseAnimationsMalformedSnapshot => 'malformed snapshot';

  @override
  String get webReverseAnimationsJsonCopied => 'JSON copied';

  @override
  String webReverseAnimationsSetFailed(String error) {
    return 'setPlaybackRate failed: $error';
  }

  @override
  String webReverseAnimationsRateNow(String rate) {
    return 'global rate = ${rate}x';
  }

  @override
  String webReverseAnimationsSetError(String error) {
    return 'error: $error';
  }

  @override
  String webReverseAnimationsBrowserError(String error) {
    return 'browser error: $error';
  }

  @override
  String webReverseAnimationsSnapshotCount(int count) {
    return '$count active animation(s)';
  }

  @override
  String webReverseAnimationsSnapshotFailed(String error) {
    return 'snapshot failed: $error';
  }

  @override
  String webReverseAnimationsBulkInvoked(String method, int count) {
    return '$method invoked on $count animation(s)';
  }

  @override
  String webReverseAnimationsBulkError(String method, String error) {
    return '$method error: $error';
  }

  @override
  String get webReverseHarTitle => 'HAR Persistence';

  @override
  String get webReverseHarSubtitle =>
      'Save now / Load back / Periodic rotation';

  @override
  String get webReverseHarOpenSaveDialogFail => 'Failed to open save dialog';

  @override
  String get webReverseHarExporting => 'Exporting...';

  @override
  String get webReverseHarExportFailedNoDraft => 'Export failed (no HAR draft)';

  @override
  String get webReverseHarExportFailed => 'Export failed';

  @override
  String get webReverseHarWrotePrefix => 'Wrote: ';

  @override
  String get webReverseHarSaved => 'HAR saved';

  @override
  String get webReverseHarExportErrorShort => 'Export error';

  @override
  String get webReverseHarOpenFileDialogFail => 'Failed to open file dialog';

  @override
  String get webReverseHarParsing => 'Parsing HAR...';

  @override
  String get webReverseHarModeMerge => 'merge';

  @override
  String get webReverseHarModeReplace => 'replace';

  @override
  String get webReverseHarLoaded => 'HAR loaded';

  @override
  String get webReverseHarLoadErrorShort => 'Load error';

  @override
  String get webReverseHarSelect => 'Select';

  @override
  String get webReverseHarChooseFolderFirst => 'Choose a folder first';

  @override
  String get webReverseHarAutoStarted => 'Auto-rotate started';

  @override
  String get webReverseHarAutoStopped => 'Auto-rotate stopped';

  @override
  String get webReverseHarSessionStatus => 'Session status';

  @override
  String get webReverseHarManual => 'Manual';

  @override
  String get webReverseHarSaveNow => 'Save HAR now';

  @override
  String get webReverseHarLoadExternal => 'Load external HAR';

  @override
  String get webReverseHarMergeLabel => 'Merge (no clear)';

  @override
  String get webReverseHarLastHarPrefix => 'Last HAR: ';

  @override
  String get webReverseHarAutoRotate => 'Auto-rotate';

  @override
  String get webReverseHarIntervalLabel => 'Interval:';

  @override
  String get webReverseHarChooseFolder => 'Choose folder';

  @override
  String get webReverseHarFolderNotChosen => '(not chosen)';

  @override
  String get webReverseHarStart => 'Start';

  @override
  String get webReverseHarStop => 'Stop';

  @override
  String get webReverseHarNotes => 'Notes';

  @override
  String get webReverseHarClose => 'Close';

  @override
  String get webReverseHarLastFilePrefix => 'Last: ';

  @override
  String get webReverseHarNotesBody =>
      '· Save now: copy internal HAR draft to chosen .har path.\n· Load external HAR: parse HAR 1.2 and write back to networkRequests; merge optional.\n· Auto-rotate: writes current snapshot to folder with ISO-timestamped .har every N minutes; survives dialog close — stop manually.';

  @override
  String webReverseHarExportException(String error) {
    return 'Export error: $error';
  }

  @override
  String webReverseHarLoadException(String error) {
    return 'Load error: $error';
  }

  @override
  String webReverseHarLoadResult(int loaded, int skipped, String mode) {
    return 'Loaded: $loaded / skipped $skipped ($mode)';
  }

  @override
  String webReverseHarCapturedEntries(int count) {
    return 'Captured entries: $count';
  }

  @override
  String webReverseHarRunningInfo(int rotations, String remaining) {
    return 'Running · $rotations rotations · next in $remaining';
  }

  @override
  String get webReverseWaterfallTitle => 'Network Waterfall';

  @override
  String get webReverseWaterfallSubtitle =>
      'Blue = wait TTFB, Green = download; click row to copy URL';

  @override
  String get webReverseWaterfallRefresh => 'Refresh';

  @override
  String get webReverseWaterfallImportHar => 'Import HAR';

  @override
  String get webReverseWaterfallExportHar => 'Export HAR';

  @override
  String get webReverseWaterfallFilterHint => 'filter URL substring';

  @override
  String get webReverseWaterfallOnlyXhr => 'XHR/Fetch only';

  @override
  String get webReverseWaterfallSortTime => 'Time';

  @override
  String get webReverseWaterfallSortDuration => 'Duration';

  @override
  String get webReverseWaterfallSortSize => 'Size';

  @override
  String get webReverseWaterfallNoRequests => 'No requests';

  @override
  String get webReverseWaterfallHeaderRequest => 'Request';

  @override
  String get webReverseWaterfallUrlCopied => 'URL copied';

  @override
  String get webReverseWaterfallClose => 'Close';

  @override
  String get webReverseWaterfallNoInitiator => 'No initiator info';

  @override
  String get webReverseWaterfallInitiatorTitle => 'Request Initiator';

  @override
  String get webReverseWaterfallInitiatorTypeLabel => 'Type';

  @override
  String get webReverseWaterfallJumpToSources => 'Open in Sources';

  @override
  String get webReverseWaterfallNoJsStack =>
      'No JavaScript stack (typical for parser/preflight)';

  @override
  String get webReverseWaterfallLoadHarTitle => 'Load HAR';

  @override
  String get webReverseWaterfallCancel => 'Cancel';

  @override
  String get webReverseWaterfallMerge => 'Merge';

  @override
  String get webReverseWaterfallReplace => 'Replace';

  @override
  String get webReverseWaterfallHarParseFailed => 'HAR parse failed';

  @override
  String get webReverseWaterfallHarSaveFailed => 'HAR save failed or timed out';

  @override
  String webReverseWaterfallInitiatorTooltipWithUrl(String type, String url) {
    return 'Initiator: $type\n$url';
  }

  @override
  String webReverseWaterfallInitiatorTooltipNoUrl(String type) {
    return 'Initiator: $type';
  }

  @override
  String webReverseWaterfallLoadHarPrompt(int count) {
    return 'Network list has $count entries. Choose load mode:';
  }

  @override
  String webReverseWaterfallLoadMergedResult(int loaded, int skipped) {
    return 'Merged: $loaded; skipped $skipped';
  }

  @override
  String webReverseWaterfallLoadReplacedResult(int loaded, int skipped) {
    return 'Replaced: $loaded; skipped $skipped';
  }

  @override
  String webReverseWaterfallHarSavedTo(String path) {
    return 'HAR saved to $path';
  }

  @override
  String get webReverseCookieEditorTitle => 'Cookie Editor';

  @override
  String get webReverseCookieEditorSubtitle =>
      'Network.getCookies / setCookie / deleteCookies — full CRUD';

  @override
  String get webReverseCookieEditorRefresh => 'Refresh';

  @override
  String get webReverseCookieEditorCopyJson => 'Copy JSON';

  @override
  String get webReverseCookieEditorCopiedJson => 'JSON copied';

  @override
  String get webReverseCookieEditorFilterHint => 'Filter name / domain / value';

  @override
  String get webReverseCookieEditorNewBtn => 'New';

  @override
  String get webReverseCookieEditorEmptyCookies => 'No cookies';

  @override
  String get webReverseCookieEditorEdit => 'Edit';

  @override
  String get webReverseCookieEditorDelete => 'Delete';

  @override
  String get webReverseCookieEditorFetching => 'Fetching cookies...';

  @override
  String get webReverseCookieEditorDeleteFailed => 'Delete failed';

  @override
  String get webReverseCookieEditorWriteFailed => 'Write failed';

  @override
  String get webReverseCookieEditorSaved => 'Saved';

  @override
  String get webReverseCookieEditorNewCookie => 'New Cookie';

  @override
  String get webReverseCookieEditorFieldName => 'name *';

  @override
  String get webReverseCookieEditorFieldValue => 'value';

  @override
  String get webReverseCookieEditorFieldDomain => 'domain';

  @override
  String get webReverseCookieEditorFieldPath => 'path';

  @override
  String get webReverseCookieEditorFieldUrl => 'URL (optional)';

  @override
  String get webReverseCookieEditorFieldExpires => 'expires (unix sec)';

  @override
  String get webReverseCookieEditorSameSiteUnset => 'unset';

  @override
  String get webReverseCookieEditorCancel => 'Cancel';

  @override
  String get webReverseCookieEditorSave => 'Save';

  @override
  String get webReverseCookieEditorNameRequired => 'name required';

  @override
  String webReverseCookieEditorCookieCount(int count) {
    return '$count cookies';
  }

  @override
  String webReverseCookieEditorDeleted(String name) {
    return 'Deleted $name';
  }

  @override
  String webReverseCookieEditorEditCookie(String name) {
    return 'Edit $name';
  }

  @override
  String get webReverseInputSimTitle => 'Input Event Simulator';

  @override
  String get webReverseInputSimDispatchingClick => 'Dispatching click...';

  @override
  String get webReverseInputSimDispatched => 'Dispatched';

  @override
  String get webReverseInputSimDispatchingKey => 'Dispatching key...';

  @override
  String get webReverseInputSimKeyDispatched => 'Key dispatched';

  @override
  String get webReverseInputSimInsertingText => 'Inserting text...';

  @override
  String get webReverseInputSimInserted => 'Inserted';

  @override
  String get webReverseInputSimButton => 'Button';

  @override
  String get webReverseInputSimClickCount => 'Click count';

  @override
  String get webReverseInputSimModifiers => 'Modifiers';

  @override
  String get webReverseInputSimClickBtn => 'Click';

  @override
  String get webReverseInputSimWheelDown => 'Wheel ↓';

  @override
  String get webReverseInputSimWheelUp => 'Wheel ↑';

  @override
  String get webReverseInputSimKeyTextLabel => 'text (printable char)';

  @override
  String get webReverseInputSimDispatchKeyDownUp => 'Dispatch keyDown+keyUp';

  @override
  String get webReverseInputSimInsertTextLabel => 'insertText';

  @override
  String get webReverseInputSimInsertBtn => 'Insert';

  @override
  String get webReverseInputSimTabMouse => 'Mouse';

  @override
  String get webReverseInputSimTabKey => 'Key';

  @override
  String get webReverseInputSimTabText => 'Text';

  @override
  String get webReverseInputSimCloseBtn => 'Close';

  @override
  String webReverseInputSimClickedAt(String x, String y) {
    return 'Clicked ($x, $y)';
  }

  @override
  String webReverseInputSimWheelDy(String dy) {
    return 'Wheel dy=$dy';
  }

  @override
  String webReverseInputSimInsertedCount(int count) {
    return 'Inserted $count chars';
  }

  @override
  String get webReverseHeadlessBatchTitle => 'Headless batch capture';

  @override
  String get webReverseHeadlessBatchClose => 'Close';

  @override
  String get webReverseHeadlessBatchDesc =>
      'Open each URL in a background tab, then save network response index, console log and screenshot. Reuses the current browser process (cookies + hooks apply).';

  @override
  String get webReverseHeadlessBatchUrlsLabel => 'URL list (one per line)';

  @override
  String get webReverseHeadlessBatchOutputDirLabel => 'Output directory';

  @override
  String get webReverseHeadlessBatchNotSelected => '(not selected)';

  @override
  String get webReverseHeadlessBatchChoose => 'Choose';

  @override
  String get webReverseHeadlessBatchNetwork => 'Network';

  @override
  String get webReverseHeadlessBatchConsole => 'Console';

  @override
  String get webReverseHeadlessBatchScreenshot => 'Screenshot';

  @override
  String get webReverseHeadlessBatchStart => 'Start batch';

  @override
  String get webReverseHeadlessBatchStop => 'Stop';

  @override
  String get webReverseHeadlessBatchNoProgress => 'No progress yet';

  @override
  String get webReverseHeadlessBatchPickOutputDir => 'Pick output dir';

  @override
  String get webReverseHeadlessBatchNeedUrlAndDir =>
      'Need at least one http(s):// URL and an output directory';

  @override
  String get webReverseHeadlessBatchBrowserNotReady =>
      'Browser is not running yet — start a session first';

  @override
  String get webReverseHeadlessBatchPhaseStarting => 'Preparing';

  @override
  String get webReverseHeadlessBatchPhaseNavigating => 'Navigating';

  @override
  String get webReverseHeadlessBatchPhaseWaitingLoad => 'Waiting load';

  @override
  String get webReverseHeadlessBatchPhaseCapturingScreenshot =>
      'Capturing screenshot';

  @override
  String get webReverseHeadlessBatchPhaseDone => 'Done';

  @override
  String get webReverseHeadlessBatchPhaseFailed => 'Failed';

  @override
  String get webReverseHeadlessBatchPhaseCancelled => 'Cancelled';

  @override
  String webReverseHeadlessBatchFinished(int ok, int total) {
    return 'Batch finished: $ok/$total ok';
  }

  @override
  String webReverseHeadlessBatchEventCount(int events, int total) {
    return '$events / $total events';
  }

  @override
  String webReverseHeadlessBatchResultStats(int net, int log, String dir) {
    return '$net net · $log log · $dir';
  }

  @override
  String get webReverseResendRequestUrlEmpty => 'URL is required';

  @override
  String get webReverseResendRequestUrlInvalid => 'Invalid URL';

  @override
  String get webReverseResendRequestAborted => 'Aborted';

  @override
  String get webReverseResendRequestFooterNote =>
      'This dialog re-issues via Dart HttpClient (bypasses CSP/CORS).';

  @override
  String get webReverseResendRequestClose => 'Close';

  @override
  String get webReverseResendRequestAbort => 'Abort';

  @override
  String get webReverseResendRequestSend => 'Send';

  @override
  String get webReverseResendRequestTitle => 'Resend / Edit';

  @override
  String get webReverseResendRequestHeadersLabel => 'Headers';

  @override
  String get webReverseResendRequestAddRow => 'Add';

  @override
  String get webReverseResendRequestRemove => 'Remove';

  @override
  String get webReverseResendRequestBodyLabel => 'Body';

  @override
  String get webReverseResendRequestBeautifyJson => 'Beautify JSON';

  @override
  String get webReverseResendRequestInvalidJson => 'Body is not valid JSON';

  @override
  String get webReverseResendRequestExportAs => 'Export as:';

  @override
  String get webReverseResendRequestCopyResponse => 'Copy response';

  @override
  String get webReverseResendRequestResponseCopied => 'Response copied';

  @override
  String get webReverseResendRequestBase64Hint =>
      'Non-UTF8 response (base64 preview):';

  @override
  String get webReverseResendRequestBodyHint => 'Body:';

  @override
  String webReverseResendRequestCopiedAs(String kind) {
    return 'Copied as $kind';
  }

  @override
  String webReverseResendRequestHasNoBody(String method) {
    return '$method has no body';
  }

  @override
  String webReverseResendRequestHeadersWithCount(int count) {
    return 'Headers ($count)';
  }

  @override
  String get webReverseMockRulesTitle => 'Local Mock';

  @override
  String get webReverseMockRulesSubtitle =>
      'URL pattern match → Fetch.fulfillRequest returns a canned response';

  @override
  String get webReverseMockRulesExportJson => 'Export JSON';

  @override
  String get webReverseMockRulesImportJson => 'Import JSON';

  @override
  String get webReverseMockRulesListLabel => 'Rules';

  @override
  String get webReverseMockRulesAdd => 'Add';

  @override
  String get webReverseMockRulesEmptyRules => 'No rules';

  @override
  String get webReverseMockRulesDelete => 'Delete';

  @override
  String get webReverseMockRulesNewRule => 'New rule';

  @override
  String get webReverseMockRulesJsonCopied => 'JSON copied';

  @override
  String get webReverseMockRulesPickRule => 'Pick a rule on the left';

  @override
  String get webReverseMockRulesHits => 'Hits';

  @override
  String get webReverseMockRulesClear => 'Clear';

  @override
  String get webReverseMockRulesNoHits => 'No hits yet';

  @override
  String get webReverseMockRulesClose => 'Close';

  @override
  String get webReverseMockRulesSaveApply => 'Save & Apply';

  @override
  String get webReverseMockRulesRuleName => 'Name';

  @override
  String get webReverseMockRulesUrlPattern => 'URL pattern (* / ?)';

  @override
  String get webReverseMockRulesMethodLabel => 'Method (blank=ALL)';

  @override
  String get webReverseMockRulesExtraHeaders =>
      'Extra headers (Key: Value per line)';

  @override
  String get webReverseMockRulesResponseBody => 'Response body';

  @override
  String webReverseMockRulesSavedCount(int count) {
    return 'Saved $count rule(s)';
  }

  @override
  String webReverseMockRulesImportedCount(int count) {
    return 'Imported $count';
  }

  @override
  String webReverseMockRulesImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get webReverseStorageTitle => 'Storage Manager';

  @override
  String get webReverseStorageClose => 'Close';

  @override
  String get webReverseStorageCopied => 'Copied';

  @override
  String get webReverseStorageAddCookie => 'Add Cookie';

  @override
  String get webReverseStorageCancel => 'Cancel';

  @override
  String get webReverseStorageSave => 'Save';

  @override
  String get webReverseStorageCookieSaved => 'Cookie saved';

  @override
  String get webReverseStorageSaveFailed => 'Save failed';

  @override
  String get webReverseStorageAddEntry => 'Add entry';

  @override
  String get webReverseStorageEditEntry => 'Edit entry';

  @override
  String get webReverseStorageNoCookies => 'No cookies';

  @override
  String get webReverseStorageCopyJson => 'Copy JSON';

  @override
  String get webReverseStorageDelete => 'Delete';

  @override
  String get webReverseStorageAdd => 'Add';

  @override
  String get webReverseStorageEmpty => 'Empty';

  @override
  String get webReverseStorageNoDatabases => 'No databases';

  @override
  String get webReverseStoragePickDb => 'Pick DB';

  @override
  String get webReverseStoragePickStore => 'Pick store';

  @override
  String get webReverseStorageMoreRecords =>
      '… more records (showing first 50)';

  @override
  String get webReverseStorageRefresh => 'Refresh';

  @override
  String get webReverseCorsUrlRequired => 'URL required';

  @override
  String get webReverseCorsBadEval => 'Bad eval result';

  @override
  String get webReverseCorsMissing => 'missing';

  @override
  String get webReverseCorsMatchOrigin => 'matches current origin';

  @override
  String get webReverseCorsAllHeadersAllowed => 'all requested headers allowed';

  @override
  String get webReverseCorsCredsRule =>
      'must be true and Allow-Origin must not be *';

  @override
  String get webReverseCorsCacheSeconds => 'cache seconds';

  @override
  String get webReverseCorsResultCopied => 'Result copied';

  @override
  String get webReverseCorsTitle => 'CORS Preflight';

  @override
  String get webReverseCorsSubtitle =>
      'OPTIONS · diagnose Allow-Origin / Methods / Headers / Credentials';

  @override
  String get webReverseCorsCopyJson => 'Copy JSON';

  @override
  String get webReverseCorsTargetUrl => 'Target URL';

  @override
  String get webReverseCorsActualMethod => 'Actual Method';

  @override
  String get webReverseCorsOriginOverride =>
      'Origin override (optional, display only)';

  @override
  String get webReverseCorsCustomHeaders =>
      'Custom headers (one K: V per line; only names sent in preflight)';

  @override
  String get webReverseCorsRunButton => 'Run Preflight';

  @override
  String get webReverseCorsDiagnostics => 'Diagnostics';

  @override
  String get webReverseCorsAllHeaders => 'All response headers';

  @override
  String get webReverseCorsClose => 'Close';

  @override
  String webReverseCorsMustInclude(String method) {
    return 'must include $method';
  }

  @override
  String webReverseCorsMissingHeaders(String names) {
    return 'missing: $names';
  }

  @override
  String get webReverseCallgraphFetching => 'Fetching resources...';

  @override
  String get webReverseCallgraphFetchFailed => 'Fetch failed';

  @override
  String get webReverseCallgraphNoScripts => 'No JS scripts found';

  @override
  String get webReverseCallgraphTitle => 'JS Callgraph';

  @override
  String get webReverseCallgraphSubtitle =>
      'Heuristic regex parsing (noisy for minified bundles)';

  @override
  String get webReverseCallgraphScanBtn => 'Scan';

  @override
  String get webReverseCallgraphScriptLimit => 'Script limit';

  @override
  String get webReverseCallgraphPerScriptKb => 'Per script (KB)';

  @override
  String get webReverseCallgraphReverseHint => 'Reverse lookup: who calls …';

  @override
  String get webReverseCallgraphEmptyHint =>
      'Click Scan to parse current page JS';

  @override
  String get webReverseCallgraphFnsSuffix => 'fns';

  @override
  String get webReverseCallgraphPickScript => 'Pick a script';

  @override
  String get webReverseCallgraphClose => 'Close';

  @override
  String get webReverseCallgraphCopyGraph => 'Copy graph';

  @override
  String get webReverseCallgraphGraphCopied => 'Graph copied';

  @override
  String get webReverseCallgraphCalleesSuffix => 'callees';

  @override
  String get webReverseCallgraphNoDetectedCalls => '(no detected calls)';

  @override
  String webReverseCallgraphParsing(int done, int total, String url) {
    return 'Parsing $done/$total: $url';
  }

  @override
  String webReverseCallgraphDone(int scripts, int fns) {
    return 'Done: $scripts scripts, $fns functions';
  }

  @override
  String webReverseCallgraphScriptsCount(int count) {
    return 'Scripts ($count)';
  }

  @override
  String webReverseCallgraphHitsHeader(int count, String name) {
    return '$count hits calling \"$name\"';
  }

  @override
  String get webReverseSwDebugFetchingRegs => 'Fetching registrations...';

  @override
  String get webReverseSwDebugToggleFailed => 'Toggle failed';

  @override
  String get webReverseSwDebugForceUpdateOn => 'Force-update on';

  @override
  String get webReverseSwDebugForceUpdateOff => 'Force-update off';

  @override
  String get webReverseSwDebugTitle => 'Service Worker Debug';

  @override
  String get webReverseSwDebugSubtitle =>
      'ServiceWorker domain: start/stop/update/unregister/sync/push';

  @override
  String get webReverseSwDebugRefresh => 'Refresh';

  @override
  String get webReverseSwDebugForceUpdateLabel =>
      'Force update SW on every navigation';

  @override
  String get webReverseSwDebugEmptyList => 'No service workers';

  @override
  String get webReverseSwDebugPushDataLabel => 'push data (string)';

  @override
  String get webReverseSwDebugBtnStart => 'Start';

  @override
  String get webReverseSwDebugBtnStop => 'Stop';

  @override
  String get webReverseSwDebugBtnUpdate => 'Update';

  @override
  String get webReverseSwDebugBtnSync => 'Dispatch sync';

  @override
  String get webReverseSwDebugBtnPush => 'Deliver push';

  @override
  String get webReverseSwDebugBtnUnregister => 'Unregister';

  @override
  String webReverseSwDebugWorkersCount(int count) {
    return '$count Service Workers';
  }

  @override
  String webReverseSwDebugMethodFailed(String method, String err) {
    return '$method failed: $err';
  }

  @override
  String webReverseSwDebugMethodOk(String method) {
    return '$method ok';
  }

  @override
  String get webReverseSetupTargetUrl => 'ターゲット URL *';

  @override
  String get webReverseSetupObjective => '目的 *';

  @override
  String get webReverseSetupObjectiveHint =>
      '例: 壁紙ダウンロード API をリバースし curl スクリプトを出力';

  @override
  String get webReverseSetupTriggerActions => 'トリガー動作（任意）';

  @override
  String get webReverseSetupTriggerHint => '例: ログイン後「原画ダウンロード」をクリック';

  @override
  String get webReverseSetupLoginMode => 'ログインモード';

  @override
  String get webReverseSetupBrowser => 'ブラウザ（検出済み）';

  @override
  String get webReverseSetupProxy => 'プロキシ（任意）';

  @override
  String get webReverseSetupKeywords => 'キーワード（任意、カンマ区切り）';

  @override
  String get webReverseSetupCreateThread => 'スレッド作成';

  @override
  String get webReverseSetupHeaderTitle => '新規 Web リバースセッション';

  @override
  String get webReverseSetupHeaderSubtitle =>
      'セッション開始後、ブラウザがメインウィンドウの右側にドッキングします';

  @override
  String get webReverseSetupClose => '閉じる';

  @override
  String get webReverseSetupProfileDir => 'プロファイルディレクトリ';

  @override
  String get webReverseSetupLockDetected =>
      '残留した SingletonLock / lockfile を検出しました。次回起動を妨げる可能性があります。';

  @override
  String get webReverseSetupWorking => '処理中…';

  @override
  String webReverseSetupCooldown(int seconds) {
    return 'クールダウン ${seconds}s';
  }

  @override
  String get webReverseSetupResolveLock => 'プロファイル競合を解決';

  @override
  String get webReverseSignatureDiffHeaderTitle => '署名フィールド変数ロケータ';

  @override
  String get webReverseSignatureDiffHeaderSubtitle =>
      '同じエンドポイントを複数回キャプチャし、動的フィールド（sign / ts / nonce）と固定フィールドを自動識別';

  @override
  String get webReverseSignatureDiffRefresh => '更新';

  @override
  String get webReverseSignatureDiffSearchHint => 'エンドポイントを検索';

  @override
  String get webReverseSignatureDiffNoGroups => '解析可能なリクエストグループがありません（≥2 件必要）';

  @override
  String get webReverseSignatureDiffEmptyHint =>
      'Network パネルで同じ API を複数回呼び出してから、ここに戻って解析してください。';

  @override
  String get webReverseSignatureDiffCopyReport => 'レポートをコピー';

  @override
  String get webReverseSignatureDiffStable => '安定';

  @override
  String get webReverseSignatureDiffDynamic => '動的';

  @override
  String get webReverseSignatureDiffIncreasing => '増加';

  @override
  String get webReverseSignatureDiffFixedHash => '固定長ハッシュ';

  @override
  String get webReverseSignatureDiffSectionQuery => 'Query パラメータ';

  @override
  String get webReverseSignatureDiffSectionHeaders => 'リクエストヘッダー';

  @override
  String get webReverseSignatureDiffSectionBody => 'リクエストボディ JSON フィールド';

  @override
  String get webReverseSignatureDiffReportTitle => '署名フィールド解析';

  @override
  String get webReverseSignatureDiffReportSamples => 'サンプル数';

  @override
  String get webReverseSignatureDiffReportCopied => 'レポートをクリップボードにコピーしました';

  @override
  String get webReverseCoverageStartFailed => '起動失敗';

  @override
  String get webReverseCoverageCollecting => '収集中…';

  @override
  String get webReverseCoverageTakeFailed => 'サンプリング失敗';

  @override
  String get webReverseCoverageStopped => '停止しました';

  @override
  String get webReverseCoverageReportCopied => 'レポートをコピーしました';

  @override
  String get webReverseCoverageTitle => 'JS カバレッジ';

  @override
  String get webReverseCoverageSubtitle => '開始 → ページを操作 → サンプリングで実行されたスクリプトを確認';

  @override
  String get webReverseCoverageRecording => '収集中';

  @override
  String get webReverseCoverageStart => '開始';

  @override
  String get webReverseCoverageTake => 'サンプル';

  @override
  String get webReverseCoverageStop => '停止';

  @override
  String get webReverseCoverageFilterHint => 'URL でフィルター';

  @override
  String get webReverseCoverageCopyReport => 'レポートをコピー';

  @override
  String get webReverseCoverageNoData => 'データなし。Start → ページを操作 → Take。';

  @override
  String get webReverseCoverageClose => '閉じる';

  @override
  String get webReverseCoverageCopyUrl => 'URL をコピー';

  @override
  String get webReverseCoverageCopied => 'コピーしました';

  @override
  String webReverseCoverageSampledCount(int count) {
    return '$count 件のスクリプトをサンプリングしました';
  }

  @override
  String get webReverseDeviceEmuTitle => 'デバイスエミュレーション';

  @override
  String get webReverseDeviceEmuPresets => 'プリセット';

  @override
  String get webReverseDeviceEmuCustom => 'カスタム';

  @override
  String get webReverseDeviceEmuWidth => '幅';

  @override
  String get webReverseDeviceEmuHeight => '高さ';

  @override
  String get webReverseDeviceEmuMobileMode => 'モバイル (touch + meta viewport)';

  @override
  String get webReverseDeviceEmuUaHint => '空欄でデフォルト UA を維持';

  @override
  String get webReverseDeviceEmuApplyCustom => 'カスタムを適用';

  @override
  String get webReverseDeviceEmuReset => 'リセット';

  @override
  String get webReverseDeviceEmuClose => '閉じる';

  @override
  String get webReverseDeviceEmuMinSize => 'サイズは最低 100×100';

  @override
  String get webReverseDeviceEmuResetDone => 'デフォルトに戻しました';

  @override
  String get webReverseDeviceEmuApplied => '適用しました';

  @override
  String get webReverseDeviceEmuClearingOverrides => 'オーバーライドを解除中…';

  @override
  String get webReverseDeviceEmuApplyingCustom => 'カスタム指標を適用中…';

  @override
  String webReverseDeviceEmuApplyingPreset(String label) {
    return '$label を適用中…';
  }

  @override
  String webReverseDeviceEmuAppliedPreset(String label) {
    return '$label を適用しました';
  }

  @override
  String webReverseDeviceEmuAppliedCustomSize(int w, int h, String dpr) {
    return '$w×$h @ ${dpr}x を適用しました';
  }

  @override
  String get webReverseWatchCopiedJson => 'JSON をコピーしました';

  @override
  String get webReverseWatchTitle => 'ウォッチ式';

  @override
  String get webReverseWatchExportJson => 'JSON をエクスポート';

  @override
  String get webReverseWatchPause => '一時停止';

  @override
  String get webReverseWatchResume => '再開';

  @override
  String get webReverseWatchNoExpressions => '式がありません';

  @override
  String get webReverseWatchAwaiting => '評価待ち…';

  @override
  String get webReverseWatchDelete => '削除';

  @override
  String get webReverseWatchNameLabel => '名前（任意）';

  @override
  String get webReverseWatchExpressionLabel => 'JS 式';

  @override
  String get webReverseWatchAddWatch => 'ウォッチを追加';

  @override
  String get webReverseWatchPickWatch => '左で監視項目を選択';

  @override
  String get webReverseWatchClose => '閉じる';

  @override
  String get webReverseWatchInterval => 'ポーリング間隔';

  @override
  String get webReverseWatchNewestFirst => '新しい順';

  @override
  String get webReverseWatchAwaitingFirst => '初回評価を待機中…';

  @override
  String webReverseWatchSubtitleHint(int ms, int count) {
    return '${ms}ms ごとに Runtime.evaluate を実行し、直近 $count 件を記録';
  }

  @override
  String webReverseWatchHistory(int count) {
    return '履歴（$count）';
  }

  @override
  String get webReverseAccountSnapTitle => 'アカウントスナップショット';

  @override
  String get webReverseAccountSnapSubtitle =>
      'cookies + localStorage/sessionStorage を保存し、ワンクリックでアカウントを切り替え';

  @override
  String get webReverseAccountSnapNameLabel => '現在のアカウントの名前';

  @override
  String get webReverseAccountSnapNameHint => '例: main / test-001';

  @override
  String get webReverseAccountSnapCapture => '保存';

  @override
  String get webReverseAccountSnapExportAll => 'すべてエクスポート';

  @override
  String get webReverseAccountSnapImport => 'インポート';

  @override
  String get webReverseAccountSnapClose => '閉じる';

  @override
  String get webReverseAccountSnapEmptyHint =>
      'スナップショットはまだありません。上に名前を入力 → 「保存」をクリック。';

  @override
  String get webReverseAccountSnapApply => '適用';

  @override
  String get webReverseAccountSnapDelete => '削除';

  @override
  String get webReverseAccountSnapApplyFailedNoCdp => '適用失敗：CDP セッションがありません';

  @override
  String get webReverseAccountSnapNotSnapshotJson =>
      'クリップボードは有効なスナップショット JSON ではありません';

  @override
  String webReverseAccountSnapSavedSnapshot(String name, int count) {
    return '「$name」を保存しました（$count cookies）';
  }

  @override
  String webReverseAccountSnapAppliedSnapshot(String name) {
    return '「$name」を適用しました。ページを更新して JS に再読込させてください。';
  }

  @override
  String webReverseAccountSnapCopiedCount(int count) {
    return '$count 件のスナップショット JSON をクリップボードにコピーしました';
  }

  @override
  String webReverseAccountSnapImportedCount(int count) {
    return '$count 件のスナップショットをインポートしました';
  }

  @override
  String webReverseAccountSnapSnapshotsCount(int count) {
    return '合計 $count 件';
  }

  @override
  String get webReverseReqBpNewBreakpoint => '新規ブレークポイント';

  @override
  String get webReverseReqBpTitle => 'リクエスト条件ブレークポイント';

  @override
  String get webReverseReqBpSubtitle =>
      'URL/Body 部分一致でヒットを記録し JS 式を実行。先にツールバーの「リクエスト傍受」を有効化してください';

  @override
  String get webReverseReqBpInterceptOff => '傍受 OFF';

  @override
  String get webReverseReqBpAdd => '追加';

  @override
  String get webReverseReqBpEmptyHint => '右上の + で最初のブレークポイントを作成';

  @override
  String get webReverseReqBpUnnamed => '(無名)';

  @override
  String get webReverseReqBpPickHint => '左側でブレークポイントを選択して編集';

  @override
  String get webReverseReqBpClear => 'クリア';

  @override
  String get webReverseReqBpNoHits => 'ヒットなし';

  @override
  String get webReverseReqBpNameField => '名前';

  @override
  String get webReverseReqBpAnyMethod => '任意';

  @override
  String get webReverseReqBpUrlContains => 'URL 部分一致';

  @override
  String get webReverseReqBpBodyContains => 'ボディ部分一致';

  @override
  String get webReverseReqBpEvalOnHit => 'ヒット時に実行（任意）';

  @override
  String get webReverseReqBpEvalHint =>
      '例: debugger; や console.trace(\"hit\", new Error().stack)';

  @override
  String get webReverseReqBpDeleteBreakpoint => 'このブレークポイントを削除';

  @override
  String webReverseReqBpHitsCount(int count) {
    return 'ヒット (最近 $count)';
  }

  @override
  String get webReverseWsInjectTitle => 'WebSocket インジェクト';

  @override
  String get webReverseWsInjectSubtitle =>
      'ページ作成の WebSocket はすべてプロキシ経由 → 対象選択 → 任意テキストフレーム注入';

  @override
  String get webReverseWsInjectProxyOn => 'プロキシ稼働中';

  @override
  String get webReverseWsInjectInstallFailed => '注入インストール失敗';

  @override
  String get webReverseWsInjectRefresh => '更新';

  @override
  String get webReverseWsInjectNoLive =>
      'アクティブな WebSocket はありません。\nページを再読み込みしてプロキシに新規接続を取らせてください。';

  @override
  String get webReverseWsInjectPayloadLabel => '送信するテキストフレーム / JSON';

  @override
  String get webReverseWsInjectPaste => '貼り付け';

  @override
  String get webReverseWsInjectPickTarget => '対象接続を選択してください';

  @override
  String get webReverseWsInjectTargetLabel => '対象';

  @override
  String get webReverseWsInjectLogEmpty => '注入ログがここに表示されます';

  @override
  String get webReverseWsInjectClose => '閉じる';

  @override
  String get webReverseWsInjectSend => '送信';

  @override
  String get webReverseWsInjectInjected => '注入成功';

  @override
  String get webReverseWsInjectInjectFailed => '注入失敗';

  @override
  String webReverseWsInjectLiveCount(int count) {
    return '$count 個のライブ WebSocket';
  }

  @override
  String webReverseWsInjectSentBytes(int count) {
    return '$count バイト送信';
  }

  @override
  String webReverseWsInjectFailedReason(String reason) {
    return '失敗：$reason';
  }

  @override
  String get webReversePmTitle => 'postMessage 追跡';

  @override
  String get webReversePmSubtitle =>
      'hook 注入 → リングバッファ → 800ms ごとに取得（iframe 越境含む）';

  @override
  String get webReversePmHookInjected => 'postMessage hook を注入';

  @override
  String get webReversePmHookStopped => '停止しました（リロード後に hook 完全解除）';

  @override
  String get webReversePmStop => '停止';

  @override
  String get webReversePmInject => '注入開始';

  @override
  String get webReversePmClear => 'クリア';

  @override
  String get webReversePmCopyJson => 'JSON コピー';

  @override
  String get webReversePmFilterHint => 'origin/target/data の部分一致';

  @override
  String get webReversePmChipSend => '送信';

  @override
  String get webReversePmChipRecv => '受信';

  @override
  String get webReversePmWaiting => 'postMessage を待機中…';

  @override
  String get webReversePmClickToCapture => '「注入開始」をクリックすると報告が始まります';

  @override
  String get webReversePmTagSend => '送信';

  @override
  String get webReversePmTagRecv => '受信';

  @override
  String get webReversePmClose => '閉じる';

  @override
  String webReversePmCopiedCount(int count) {
    return '$count 件コピー';
  }

  @override
  String get webReverseThrottleEnableNetwork => 'Network ドメインを有効化…';

  @override
  String get webReverseThrottleApplyFailed => '適用失敗';

  @override
  String get webReverseThrottleConditionsApplied => 'ネットワーク条件を適用';

  @override
  String get webReverseThrottleTitle => 'ネットワーク条件シミュレーション';

  @override
  String get webReverseThrottleSubtitle =>
      'Network.emulateNetworkConditions：プリセット選択またはカスタム kbps/遅延';

  @override
  String get webReverseThrottlePresets => 'プリセット';

  @override
  String get webReverseThrottleCustom => 'カスタム';

  @override
  String get webReverseThrottleDownKbps => '下り kbps (0=無制限)';

  @override
  String get webReverseThrottleUpKbps => '上り kbps (0=無制限)';

  @override
  String get webReverseThrottleLatencyMs => '遅延 ms';

  @override
  String get webReverseThrottleOffline => 'オフライン';

  @override
  String get webReverseThrottleDisableCache => 'キャッシュ無効';

  @override
  String get webReverseThrottleApplyCustom => 'カスタム適用';

  @override
  String get webReverseThrottleReset => 'リセット（無制限）';

  @override
  String get webReverseThrottleNotes => 'メモ';

  @override
  String get webReverseThrottleNotesBody =>
      '・スロットルは現在 target の session 全体に適用、リセットまたは閉じれば解除。\n・kbps は *1024/8 で bytes/s に変換して送信、オフライン時はスループット無視。\n・キャッシュ無効は Fetch/Disk Cache 両方に適用、初回アクセス再現に便利。';

  @override
  String get webReverseThrottleClose => '閉じる';

  @override
  String get webReverseThrottleUnknownError => '不明';

  @override
  String webReverseThrottleStatusFailed(String reason) {
    return '失敗：$reason';
  }

  @override
  String webReverseThrottleStatusApplied(String summary) {
    return '適用済み：$summary';
  }

  @override
  String get webReverseDomMutTitle => 'DOM Mutation レコーダー';

  @override
  String get webReverseDomMutSubtitle => 'MutationObserver を注入 → ライブタイムライン';

  @override
  String get webReverseDomMutRecordingStarted => 'DOM 変更を記録中';

  @override
  String webReverseDomMutInstallFailed(String error) {
    return 'インストール失敗: $error';
  }

  @override
  String webReverseDomMutCopiedRecords(int count) {
    return '$count 件をコピーしました';
  }

  @override
  String get webReverseDomMutExportJson => 'JSON エクスポート';

  @override
  String get webReverseDomMutRecording => '記録中';

  @override
  String get webReverseDomMutStart => '開始';

  @override
  String get webReverseDomMutStop => '停止';

  @override
  String get webReverseDomMutClear => 'クリア';

  @override
  String get webReverseDomMutFilterHint => 'フィルタ（部分一致）';

  @override
  String get webReverseDomMutAutoFollow => '自動追従';

  @override
  String webReverseDomMutCounter(int count, int total) {
    return '$count / $total';
  }

  @override
  String get webReverseDomMutWaiting => 'DOM 変更を待機中…';

  @override
  String get webReverseDomMutPressStart => '開始を押してください';

  @override
  String get webReverseDomMutClose => '閉じる';

  @override
  String get webReverseSmTitle => 'SourceMap リゾルバ';

  @override
  String get webReverseSmSubtitle =>
      'minified file:line:col → 元の source:line:col';

  @override
  String get webReverseSmInvalidInput => 'URL と行番号が不正です';

  @override
  String get webReverseSmFetching => 'sourcemap を取得中...';

  @override
  String webReverseSmFetchFailed(String error) {
    return '取得失敗: $error';
  }

  @override
  String get webReverseSmBadEvalResult => '戻り値が不正です';

  @override
  String get webReverseSmNoMapping => '対応するマッピングなし';

  @override
  String get webReverseSmResolved => '解決済み';

  @override
  String get webReverseSmCopied => 'コピーしました';

  @override
  String get webReverseSmUrlLabel => 'minified ファイル URL';

  @override
  String get webReverseSmLineLabel => '行 (1-based)';

  @override
  String get webReverseSmColLabel => '列 (0-based)';

  @override
  String get webReverseSmResolve => '解決';

  @override
  String get webReverseSmEmptyHint => 'URL と位置を入力して解決を押してください';

  @override
  String get webReverseSmCopyTooltip => 'コピー';

  @override
  String get webReverseSmNameLabel => '名前';

  @override
  String get webReverseSmClose => '閉じる';

  @override
  String get webReverseCssCovStarting => 'CSS ドメインを有効化して追跡開始...';

  @override
  String webReverseCssCovStartFailed(String error) {
    return '開始失敗: $error';
  }

  @override
  String get webReverseCssCovTrackingActive => '追跡中 — ページを操作後、「停止と集計」をクリック。';

  @override
  String get webReverseCssCovStopping => '停止して集計中...';

  @override
  String webReverseCssCovStopFailed(String error) {
    return '停止失敗: $error';
  }

  @override
  String webReverseCssCovResultsTallied(int sheets, int rules) {
    return '$sheets シート、計 $rules ルール。';
  }

  @override
  String get webReverseCssCovJsonCopied => 'JSON をコピーしました';

  @override
  String get webReverseCssCovTitle => 'CSS ルール使用率';

  @override
  String get webReverseCssCovSubtitle =>
      'CSS.startRuleUsageTracking · デッドコードを集計';

  @override
  String get webReverseCssCovCopyJson => 'JSON をコピー';

  @override
  String get webReverseCssCovTracking => '追跡中';

  @override
  String get webReverseCssCovIdle => 'アイドル';

  @override
  String get webReverseCssCovStopAndTally => '停止と集計';

  @override
  String get webReverseCssCovStartTracking => '追跡開始';

  @override
  String get webReverseCssCovEmpty => '結果なし。追跡を開始してページを操作してください。';

  @override
  String webReverseCssCovRuleStats(
    int used,
    int total,
    String usedKb,
    String totalKb,
  ) {
    return '$used/$total ルール · $usedKb/$totalKb KB';
  }

  @override
  String get webReverseCssCovClose => '閉じる';

  @override
  String get webReverseAiCryptoStatusFetchResources => 'frame リソースを取得中...';

  @override
  String get webReverseAiCryptoStatusDetecting => '疑わしいフィールドを抽出中...';

  @override
  String get webReverseAiCryptoStatusDone => '完了';

  @override
  String get webReverseAiCryptoCopied => 'クリップボードにコピーしました';

  @override
  String get webReverseAiCryptoTitle => 'AI 暗号化パラメータ復元';

  @override
  String get webReverseAiCryptoSubtitle =>
      'endpoint を集約 → 変数 diff → JS ソースで特定 → プロンプトをコピー';

  @override
  String get webReverseAiCryptoRefresh => '再集約';

  @override
  String get webReverseAiCryptoEmpty =>
      '解析可能な endpoint がありません (同一エンドポイントで 2 回以上必要)';

  @override
  String get webReverseAiCryptoAnalyze => '解析';

  @override
  String get webReverseAiCryptoCopyPrompt => 'プロンプトをコピー';

  @override
  String get webReverseAiCryptoSuspectsLabel => '疑わしいフィールド:';

  @override
  String get webReverseAiCryptoPromptHint => '「解析」をクリックしてプロンプトを生成します。';

  @override
  String get webReverseAiCryptoClose => '閉じる';

  @override
  String webReverseAiCryptoStatusSearchProgress(int done, int total) {
    return 'フィールド検索 $done/$total';
  }

  @override
  String webReverseAiCryptoHits(int count) {
    return '$count 件';
  }

  @override
  String get webReverseCdpSendFailed => '送信失敗（未接続？）';

  @override
  String get webReverseCdpCopied => 'コピーしました';

  @override
  String get webReverseCdpTitle => 'CDP Raw コマンドコンソール';

  @override
  String get webReverseCdpMethodLabel => 'method (Domain.command)';

  @override
  String get webReverseCdpUseSession => 'page session を使用';

  @override
  String get webReverseCdpSend => '送信';

  @override
  String get webReverseCdpNoHistory => '履歴なし';

  @override
  String get webReverseCdpSendHint => 'コマンドを送信すると応答がここに表示されます';

  @override
  String get webReverseCdpClose => '閉じる';

  @override
  String get webReverseCdpCopyResponse => '応答 JSON をコピー';

  @override
  String get webReverseCdpParams => 'リクエストパラメータ';

  @override
  String get webReverseCdpResponse => '応答';

  @override
  String get webReverseCdpError => 'エラー';

  @override
  String webReverseCdpInvalidJson(String error) {
    return 'JSON 解析失敗: $error';
  }

  @override
  String webReverseCdpSubtitle(int count) {
    return '⌘/Ctrl+Enter 送信 · Ctrl+↑/↓ 履歴 · $count 件';
  }

  @override
  String get webReversePerfTitle => 'Performance Trace 録画';

  @override
  String get webReversePerfSubtitle => 'Tracing → chrome-trace JSON';

  @override
  String get webReversePerfDuration => '時間';

  @override
  String get webReversePerfCategories => 'Trace カテゴリ';

  @override
  String get webReversePerfCopyPath => 'パスをコピー';

  @override
  String get webReversePerfStop => '停止';

  @override
  String get webReversePerfStart => '開始';

  @override
  String get webReversePerfClose => '閉じる';

  @override
  String get webReversePerfTraceFailed => '録画失敗またはデータなし';

  @override
  String get webReversePerfStopping => '停止要求、終了処理中…';

  @override
  String get webReversePerfTraceSaved => 'Trace を保存しました';

  @override
  String get webReversePerfPathCopied => 'パスをコピーしました';

  @override
  String webReversePerfRecording(int seconds) {
    return '録画中（残り ${seconds}s）';
  }

  @override
  String webReversePerfSaved(String path, String kb) {
    return '保存しました: $path ($kb KB)';
  }

  @override
  String get webReverseReplayJsonCopied => 'JSON をコピーしました';

  @override
  String get webReverseReplayTitle => 'ネットワーク一括リプレイ';

  @override
  String get webReverseReplaySubtitle => '複数選択 → 順次再送 → 差分';

  @override
  String get webReverseReplayCopyResultsJson => '結果 JSON をコピー';

  @override
  String get webReverseReplayFilterByUrl => 'URL で絞り込み';

  @override
  String get webReverseReplaySelectAll => '全選択';

  @override
  String get webReverseReplayClear => 'クリア';

  @override
  String get webReverseReplayEmpty => 'セッションに HTTP リクエストなし';

  @override
  String get webReverseReplayRunBatch => '再送開始';

  @override
  String get webReverseReplayClose => '閉じる';

  @override
  String webReverseReplayDone(int ok, int total) {
    return '再送完了: $ok/$total 成功';
  }

  @override
  String webReverseReplayProgress(int done, int total) {
    return '再送中 $done / $total';
  }

  @override
  String webReverseReplaySelected(int count, int total) {
    return '選択 $count / $total';
  }

  @override
  String get webReverseGeoOverridesApplied => 'オーバーライド適用済';

  @override
  String get webReverseGeoEnvOverridesApplied => '環境オーバーライドを適用';

  @override
  String get webReverseGeoOverridesCleared => 'オーバーライドを解除';

  @override
  String get webReverseGeoEnvOverridesCleared => '環境オーバーライド解除';

  @override
  String get webReverseGeoTitle => '地理 / TZ / ロケール上書き';

  @override
  String get webReverseGeoCityPresets => '都市プリセット';

  @override
  String get webReverseGeoEnableGeo => '位置情報オーバーライドを有効化';

  @override
  String get webReverseGeoEnableTz => 'タイムゾーン上書きを有効化';

  @override
  String get webReverseGeoEnableLocale => 'ロケール上書きを有効化';

  @override
  String get webReverseGeoTip =>
      'ヒント: オーバーライドは現在のターゲットで即時適用され、リロード後も保持されます。navigator.geolocation、Intl.DateTimeFormat().resolvedOptions().timeZone、navigator.language で検証してください。検出結果をキャッシュするサイトはハードリロードを推奨。';

  @override
  String get webReverseGeoClear => 'クリア';

  @override
  String get webReverseGeoWorking => '処理中…';

  @override
  String get webReverseGeoApply => 'オーバーライド適用';

  @override
  String get webReverseCollectionExportNothing => 'エクスポート対象なし';

  @override
  String get webReverseCollectionExportTitle => 'APIコレクション エクスポート';

  @override
  String get webReverseCollectionExportSubtitle =>
      'Postman / Insomnia / Bruno / cURL / HAR — クリップボードへコピー';

  @override
  String get webReverseCollectionExportName => 'コレクション名';

  @override
  String get webReverseCollectionExportUrlFilter => 'URLフィルター';

  @override
  String get webReverseCollectionExportXhrOnly => 'XHR/Fetchのみ';

  @override
  String get webReverseCollectionExportPreview2 => 'プレビュー: 先頭2件';

  @override
  String get webReverseCollectionExportClose => '閉じる';

  @override
  String get webReverseCollectionExportCopyAction => 'コレクションをコピー';

  @override
  String get webReverseCollectionExportNoMatch =>
      '// 一致するリクエストがありません。\n// フィルターを調整するか「XHR/Fetchのみ」を解除してください。';

  @override
  String webReverseCollectionExportCopied(int count) {
    return '$count件のリクエストをクリップボードへコピー';
  }

  @override
  String webReverseCollectionExportMatchCount(int match, int total) {
    return '$match件一致 · 合計 $total';
  }

  @override
  String get webReverseJwtTitle => 'JWT 自動更新';

  @override
  String get webReverseJwtSubtitle => 'cookies/ストレージ内のJWTをスキャンし、期限間近で更新JSを実行';

  @override
  String get webReverseJwtScanNow => '今すぐスキャン';

  @override
  String get webReverseJwtRefreshNow => '今すぐ更新';

  @override
  String get webReverseJwtAuto => '自動';

  @override
  String get webReverseJwtIntervalSec => '間隔(秒)';

  @override
  String get webReverseJwtThresholdSec => '閾値(秒)';

  @override
  String get webReverseJwtRefreshExpr => '更新式 (async JS)';

  @override
  String get webReverseJwtNoneFound => 'JWT が見つかりません';

  @override
  String get webReverseJwtRefreshLog => '更新ログ';

  @override
  String get webReverseJwtClose => '閉じる';

  @override
  String webReverseJwtFoundCount(int count) {
    return '発見した JWT ($count)';
  }

  @override
  String get webReverseWebauthnTitle => 'WebAuthn 仮想認証器';

  @override
  String get webReverseWebauthnDisabledBody =>
      '右上のスイッチで WebAuthn 仮想ドメインを有効化すると、ハードウェアキー無しで navigator.credentials.create/get を完了できます。';

  @override
  String get webReverseWebauthnAdd => '仮想認証器を追加';

  @override
  String get webReverseWebauthnAddBtn => '追加';

  @override
  String get webReverseWebauthnNone => '仮想認証器なし';

  @override
  String get webReverseWebauthnClose => '閉じる';

  @override
  String get webReverseWebauthnRefreshCreds => '認証情報を更新';

  @override
  String get webReverseWebauthnRemove => '削除';

  @override
  String get webReverseWebauthnUserVerified => 'ユーザー検証済み';

  @override
  String webReverseWebauthnAdded(String id) {
    return 'authenticator $id を追加';
  }

  @override
  String webReverseWebauthnCreatedCount(int count) {
    return '作成済み ($count)';
  }

  @override
  String webReverseWebauthnCredentialsCount(int count) {
    return '認証情報 ($count)';
  }

  @override
  String get webReverseInstallTitle => 'Google Chrome が必要です';

  @override
  String get webReverseInstallClose => '閉じる';

  @override
  String get webReverseInstallBody =>
      'Web リバースエキスパートは外部の Chromium 系ブラウザ (Chrome / Edge / Brave / Chromium) を CDP 経由で制御します。現在のシステムでは見つかりませんでした。';

  @override
  String get webReverseInstallOpen => 'ブラウザで開く';

  @override
  String get webReverseInstallHint =>
      'Chrome をインストール後に再試行してください。Edge / Brave / Chromium をインストール済みの場合は「インストール済み、再検出」をクリック。';

  @override
  String get webReverseInstallInstalled => 'インストール済み';

  @override
  String get webReverseProfileEmptyPath => 'Profile パスが空です。何も実行されません';

  @override
  String get webReverseProfileNoResidual =>
      '残留ロックは見つかりません。起動できない場合は診断の他の原因をご確認ください。';

  @override
  String get webReverseProfileResetTitle => 'ロックが残っています — profile をリセットしますか？';

  @override
  String get webReverseProfileResetConfirm => 'リセット実行';

  @override
  String get webReverseProfileKept =>
      'Profile を保持しました。ロックにより次回起動が阻害される可能性があります。';

  @override
  String webReverseProfileCleanFailed(String error) {
    return 'クリーニング失敗：$error';
  }

  @override
  String webReverseProfileCleaned(int count) {
    return '$count 個のロックファイルを削除しました。profile は正常です';
  }

  @override
  String webReverseProfileResetBody(String path) {
    return 'SingletonLock などの残留を削除しましたが、ロックがまだ存在します。\n\n続行すると次のディレクトリを再帰的に削除します：\n$path\n\nこの profile 配下の Cookies / Login Data / 拡張機能 / 履歴 などはすべて失われ、次回起動時に新しい profile が再生成されます。';
  }

  @override
  String webReverseProfileResetDone(String path) {
    return 'profile をリセットしました：$path（60 秒のクールダウン）';
  }

  @override
  String webReverseProfileResetFailed(String error) {
    return 'リセット失敗：$error';
  }

  @override
  String get webReverseReplNoResult => '(結果なし)';

  @override
  String get webReverseReplCopied => 'コピーしました';

  @override
  String get webReverseReplTitle => 'Console REPL';

  @override
  String get webReverseReplSubtitle =>
      'Runtime.evaluate · ↑/↓ 履歴 · Ctrl/⌘+Enter 実行';

  @override
  String get webReverseReplClear => 'ログを消去';

  @override
  String get webReverseReplEmpty => '下に JS 式を入力 → Ctrl/⌘+Enter で実行';

  @override
  String get webReverseReplHint =>
      '例: document.title または await fetch(\"/api\").then(r=>r.json())';

  @override
  String get webReverseReplRun => '実行';

  @override
  String get webReverseConsoleEvalFailed => '評価失敗';

  @override
  String get webReverseConsoleEmpty => 'コンソール出力はまだありません。';

  @override
  String get webReverseConsolePausedHint =>
      'デバッガが一時停止中 · 式は最上位スタックフレームのスコープで評価されます';

  @override
  String get webReverseConsoleReplHint => 'JS 式を入力 ↵ で実行；↑↓ 履歴';

  @override
  String get webReverseConsoleClusterCopied => 'クラスタ JSON をコピーしました';

  @override
  String get webReverseConsoleClusterTitle => 'コンソールエラークラスタ';

  @override
  String get webReverseConsoleClusterRefresh => '更新';

  @override
  String get webReverseConsoleClusterFilterHint => 'キーワードで絞り込み';

  @override
  String get webReverseConsoleClusterNoMatch => '一致するコンソールエントリがありません';

  @override
  String get webReverseConsoleClusterCopyJson => 'JSON をコピー';

  @override
  String webReverseConsoleClusterSubtitle(int entries, int clusters) {
    return 'level + 正規化された先頭行で重複排除 · $entries 件 / $clusters クラスタ';
  }

  @override
  String webReverseConsoleClusterTimes(String first, String last) {
    return '初回: $first\n最新: $last';
  }

  @override
  String webReverseConsoleClusterMore(int count) {
    return '… ほか $count 件';
  }

  @override
  String get webReverseDomSearchTitle => 'DOM セレクタ検索';

  @override
  String get webReverseDomSearchSearching => '検索中...';

  @override
  String get webReverseDomSearchNoMatches => '一致なし';

  @override
  String get webReverseDomSearchHint => 'セレクタ／テキスト／XPath を入力、Enter で実行';

  @override
  String get webReverseDomSearchRun => '実行';

  @override
  String get webReverseDomSearchExample =>
      '例: button[data-action] · #login · //a[contains(@href,\"docs\")]';

  @override
  String get webReverseDomSearchHighlight => 'ページ内をハイライト';

  @override
  String webReverseDomSearchFailed(String error) {
    return '検索失敗: $error';
  }

  @override
  String webReverseDomSearchGetFailed(String error) {
    return '結果の取得に失敗: $error';
  }

  @override
  String webReverseDomSearchHitCount(int total, int shown) {
    return '$total 件ヒット、上位 $shown 件を表示';
  }

  @override
  String get webReverseFrameTreeTitle => 'フレームツリー';

  @override
  String get webReverseFrameTreeSubtitle =>
      'Page.getFrameTree · メイン + ネスト iframe';

  @override
  String get webReverseFrameTreeRefresh => '更新';

  @override
  String get webReverseFrameTreeCopyJson => 'JSON をコピー';

  @override
  String get webReverseFrameTreeCopied => 'コピーしました';

  @override
  String get webReverseFrameTreeEmpty => '現在のページにフレームがありません';

  @override
  String webReverseFrameTreeFailed(String error) {
    return '取得に失敗: $error';
  }

  @override
  String webReverseFrameTreeCount(int count) {
    return '$count フレーム';
  }

  @override
  String get webReverseCpuThrottleOff => 'CPU スロットル オフ';

  @override
  String get webReverseCpuThrottleResetDone => 'リセット完了';

  @override
  String get webReverseCpuThrottleTitle => 'CPU スロットリング';

  @override
  String get webReverseCpuThrottlePresets => 'プリセット';

  @override
  String get webReverseCpuThrottleNote =>
      'ダイアログを閉じてもスロットルは有効です。1× (off) または「リセット」で解除してください。';

  @override
  String get webReverseCpuThrottleReset => 'リセット (1×)';

  @override
  String webReverseCpuThrottleApplying(String rate) {
    return 'CPU スロットル $rate× を設定中...';
  }

  @override
  String webReverseCpuThrottleFailed(String error) {
    return '失敗: $error';
  }

  @override
  String webReverseCpuThrottleCurrent(String rate) {
    return '現在 CPU スロットル $rate×';
  }

  @override
  String webReverseCpuThrottleSliderLabel(String rate) {
    return 'スライダー $rate×';
  }

  @override
  String webReverseCpuThrottleApplied(String rate) {
    return '$rate× スロットルを適用';
  }

  @override
  String get webReverseHeapTaking => 'Heap Snapshot を取得中（数秒かかる場合があります）...';

  @override
  String get webReverseHeapFailed => '取得失敗または空';

  @override
  String get webReverseHeapSavedToast => 'Snapshot を保存しました';

  @override
  String get webReverseHeapPathCopied => 'パスをコピーしました';

  @override
  String get webReverseHeapSubtitle =>
      'HeapProfiler.takeHeapSnapshot → .heapsnapshot（DevTools Memory で読み込み可）';

  @override
  String get webReverseHeapEmptyHint =>
      '下のボタンで現在のページの V8 Heap Snapshot を取得します。\n大きなページは 50MB+ のファイルになることがあります。';

  @override
  String get webReverseHeapCopyPath => 'パスをコピー';

  @override
  String get webReverseHeapTake => 'スナップショット取得';

  @override
  String webReverseHeapSaved(String path, String mb) {
    return '保存しました: $path ($mb MB)';
  }

  @override
  String get webReverseRealtimeDirSent => '送信';

  @override
  String get webReverseRealtimeDirRecv => '受信';

  @override
  String get webReverseRealtimeDirError => 'エラー';

  @override
  String get webReverseRealtimePayloadCopied => 'ペイロードをコピーしました';

  @override
  String get webReverseRealtimeTitle => 'リアルタイム接続';

  @override
  String get webReverseRealtimeEmpty =>
      '現在のページに WebSocket / EventSource はありません。\n動作をトリガーするとここがリアルタイム更新されます。';

  @override
  String get webReverseRealtimePickPrompt => '左から接続を選んでフレームを表示します。';

  @override
  String get webReverseRealtimeFilterHint => 'ペイロードを絞り込み（部分文字列）';

  @override
  String get webReverseRealtimeAutoFollow => '自動追従';

  @override
  String get webReverseRealtimeNoMatching => '一致するフレームはありません。';

  @override
  String webReverseRealtimeFrameCount(int count) {
    return '$count フレーム';
  }

  @override
  String get webReverseMarkupTitle => 'スクリーンショット注釈';

  @override
  String get webReverseMarkupSaveWithout => '注釈なしで保存';

  @override
  String get webReverseMarkupExporting => 'エクスポート中…';

  @override
  String get webReverseMarkupDone => '完了';

  @override
  String get webReverseMarkupUndo => '元に戻す';

  @override
  String get webReverseMarkupClear => 'クリア';

  @override
  String get webReverseMarkupAddTextTitle => 'テキスト注釈を追加';

  @override
  String get webReverseMarkupLabelHint => 'ラベルを入力';

  @override
  String get webReverseMarkupAdd => '追加';

  @override
  String get webReverseElementsLoadFailed => '読み込み失敗：ブラウザ未起動または CDP 利用不可';

  @override
  String get webReverseElementsSelectorFailed => 'セレクター生成に失敗';

  @override
  String get webReverseElementsSelectorCopied => 'セレクターをコピーしました';

  @override
  String get webReverseElementsXPathFailed => 'XPath 生成に失敗';

  @override
  String get webReverseElementsXPathCopied => 'XPath をコピーしました';

  @override
  String get webReverseElementsReloadDom => 'DOM ルートを再読み込み';

  @override
  String get webReverseElementsCopySelector => 'セレクターをコピー';

  @override
  String get webReverseElementsCopyXPath => 'XPath をコピー';

  @override
  String get webReverseElementsScrollIntoView => 'ページに表示';

  @override
  String get webReverseElementsPickElement => '左の DOM ツリーから要素を選択';

  @override
  String get webReverseElementsNoAttrs => '属性なし';

  @override
  String get webReverseElementsNoComputed => '計算スタイルなし';

  @override
  String get webReverseElementsNoListeners => 'リスナーなし';

  @override
  String webReverseElementsAttrsTab(int count) {
    return '属性 ($count)';
  }

  @override
  String webReverseElementsComputedTab(int count) {
    return '計算 ($count)';
  }

  @override
  String webReverseElementsListenersTab(int count) {
    return 'リスナー ($count)';
  }

  @override
  String get webReverseCryptoSecEncode => 'エンコード';

  @override
  String get webReverseCryptoSecHash => 'ハッシュ';

  @override
  String get webReverseCryptoSecTime => 'タイムスタンプ';

  @override
  String get webReverseCryptoClear => 'クリア';

  @override
  String get webReverseCryptoInputHint => 'ここに貼り付け…';

  @override
  String get webReverseCryptoInputLabel => '入力';

  @override
  String get webReverseCryptoCopy => 'コピー';

  @override
  String get webReverseCryptoUseAsInput => '入力に戻す';

  @override
  String get webReverseCryptoLengthLabel => '長さ';

  @override
  String get webReverseCryptoTsToIso => 'タイムスタンプ → ISO';

  @override
  String get webReverseCryptoIsoToTs => 'ISO → タイムスタンプ';

  @override
  String get webReverseCryptoNow => '現在時刻';

  @override
  String get webReverseCryptoUuidHint => 'ランダム UUID v4（タップでコピー）';

  @override
  String get webReverseCryptoRegenerate => '再生成';

  @override
  String webReverseCryptoCopied(String label) {
    return '$label をコピーしました';
  }

  @override
  String webReverseCryptoLengthValue(int chars, int bytes) {
    return '文字 $chars / バイト $bytes';
  }

  @override
  String get webReverseHooksDefaultCode =>
      '各ドキュメント読込前に実行；window/fetch などを patch 可能';

  @override
  String get webReverseHooksSavedToast => '保存してホットリロードしました';

  @override
  String get webReverseHooksDeleteTitle => 'hook を削除しますか？';

  @override
  String get webReverseHooksDeleteContent => '即座にアンロードされ、取り消せません。';

  @override
  String get webReverseHooksDelete => '削除';

  @override
  String get webReverseHooksDiscardTitle => '未保存の変更を破棄しますか？';

  @override
  String get webReverseHooksKeepEditing => '編集を続ける';

  @override
  String get webReverseHooksDiscardConfirm => '破棄';

  @override
  String get webReverseHooksLibrary => 'Hook ライブラリ';

  @override
  String get webReverseHooksNew => '新規 hook';

  @override
  String get webReverseHooksEmpty => 'hook がありません。\n+ をタップして作成。';

  @override
  String get webReverseHooksPickPrompt => '左から hook を選ぶか新規作成してください。';

  @override
  String get webReverseHooksNameLabel => '名前';

  @override
  String get webReverseHooksSave => '保存 (⌘S)';

  @override
  String get webReverseHooksSaved => '保存済み';

  @override
  String get webReverseHooksInfo => '保存で即再装着。各ドキュメント読込前に実行；タブ切替/再読込後も有効。';

  @override
  String webReverseHooksNewName(String time) {
    return 'フック $time';
  }

  @override
  String get webReverseSnippetsDefaultCode => 'ここに JS を書く。ページコンテキストで実行されます。';

  @override
  String get webReverseSnippetsNoResult => '(戻り値なし)';

  @override
  String get webReverseSnippetsDeleteTitle => 'スニペットを削除しますか？';

  @override
  String get webReverseSnippetsDeleteContent => '取り消せません。';

  @override
  String get webReverseSnippetsDelete => '削除';

  @override
  String get webReverseSnippetsTitle => 'スニペットパッド';

  @override
  String get webReverseSnippetsNew => '新規スニペット';

  @override
  String get webReverseSnippetsEmpty => 'スニペットがありません。\n+ をタップして作成。';

  @override
  String get webReverseSnippetsPickPrompt => '左からスニペットを選ぶか新規作成してください。';

  @override
  String get webReverseSnippetsRun => '実行 (⌘R)';

  @override
  String get webReverseSnippetsSaveDirty => '保存 *';

  @override
  String webReverseSnippetsNewName(String time) {
    return 'スニペット $time';
  }

  @override
  String get servicesTitle => 'サービス';

  @override
  String get servicesSubtitle =>
      'OpenHand が独自開発した専門サービスで、安定し、制御可能で、監査可能な実行環境を提供します。';

  @override
  String get servicesProprietaryBadge => 'OpenHand 自社開発';

  @override
  String get servicesAiInfrastructureExposureScanTitle => 'AI インフラ露出面スキャン';

  @override
  String get servicesAiInfrastructureExposureScanDescription =>
      '認可された範囲で公開状態の AI サービスを検出し、漏えいした認証情報と危険な設定を特定して、監査可能な対応証跡を残します。';

  @override
  String get agentsTitle => 'エージェント';

  @override
  String get agentsSubtitle =>
      'Hermes Agent のデジタル従業員、権限、タスク、クラスタ、監査、KPI を管理します。';

  @override
  String get agentsCreateAgent => 'エージェントを作成';

  @override
  String get agentsEditAgent => 'エージェントを編集';

  @override
  String get agentsLoadFailed => 'エージェントを読み込めませんでした';

  @override
  String get agentsRetry => '再試行';

  @override
  String get agentsEmptyTitle => 'エージェントはまだありません';

  @override
  String get agentsEmptyBody => '作成から、範囲、権限、タスクデスク、ガバナンスを備えた最初のデジタル従業員を設定します。';

  @override
  String get agentsMentorLabel => 'メンター';

  @override
  String get agentsStopAgent => 'エージェントを停止';

  @override
  String get agentsStartAgent => 'エージェントを開始';

  @override
  String get agentsActivities => 'アクティビティ';

  @override
  String get agentsLogs => 'ログ';

  @override
  String get agentsCapabilityLogs => '機能ログ';

  @override
  String get agentsApprovals => '承認';

  @override
  String get agentsCluster => 'クラスタ';

  @override
  String get agentsMore => 'その他';

  @override
  String get agentsTaskDesk => 'タスクデスク';

  @override
  String get agentsAuditReport => '監査レポート';

  @override
  String get agentsKpi => 'KPI';

  @override
  String get agentsResources => 'リソース';

  @override
  String get agentsDeleteAgent => 'エージェントを削除';

  @override
  String agentsTasksCount(int running, int total) {
    return 'タスク $running/$total';
  }

  @override
  String agentsApprovalsCount(int count) {
    return '承認 $count';
  }

  @override
  String agentsWorkersCount(int count, int max) {
    return 'Worker $count/$max';
  }

  @override
  String agentsCapabilitySkillsCount(int count) {
    return 'スキル $count';
  }

  @override
  String agentsCapabilityKnowledgeCount(int count) {
    return 'ナレッジ $count';
  }

  @override
  String agentsCapabilityMemoryCount(int count) {
    return 'メモリ $count';
  }

  @override
  String agentsCapabilityToolsCount(int count) {
    return 'ツール $count';
  }

  @override
  String agentsCapabilityCronsCount(int count) {
    return 'Crons $count';
  }

  @override
  String agentsCapabilityHooksCount(int count) {
    return 'Hooks $count';
  }

  @override
  String get agentsSelfLearningOn => '自己学習オン';

  @override
  String get agentsNoCapabilityResources => '機能リソース未接続';

  @override
  String agentsDialogTitleWithName(String title, String name) {
    return '$title · $name';
  }

  @override
  String get agentsActivitiesEmptyTitle => 'アクティビティはまだありません。';

  @override
  String get agentsLogsEmptyTitle => 'Skill、メモリ、MCP、ツールのログはまだありません。';

  @override
  String get agentsApprovalsEmptyTitle => '承認リクエストはありません。';

  @override
  String get agentsListEmptyBody => 'エージェントが稼働するとここに記録されます。';

  @override
  String agentsMinWorkersCount(int count) {
    return '最小 $count';
  }

  @override
  String agentsMaxWorkersCount(int count) {
    return '最大 $count';
  }

  @override
  String get agentsNoWorkersTitle => 'Worker はありません';

  @override
  String get agentsNoWorkersBody => '設定した最小数に基づいて Worker が準備されます。';

  @override
  String agentsWorkerSubtitle(String status, int done, int priority) {
    return '$status · 完了 $done · 優先度 $priority';
  }

  @override
  String get agentsPublishTask => 'タスクを発行';

  @override
  String get agentsNoTasksTitle => 'タスクはありません';

  @override
  String get agentsNoTasksBody => 'ここでタスクを発行すると、Worker が実行して結果を返します。';

  @override
  String get agentsAuditRequests => 'リクエスト';

  @override
  String get agentsAuditCompleted => '完了';

  @override
  String get agentsAuditUtilization => '利用率';

  @override
  String get agentsRecentAuditEvents => '最近の監査イベント';

  @override
  String get agentsNoAuditData => '監査データはまだありません。';

  @override
  String get agentsNoKpiTitle => 'KPI はありません';

  @override
  String get agentsNoKpiBody => 'エディタで KPI を追加すると、エージェントがそれに沿って計画します。';

  @override
  String get agentsMetricMemory => 'メモリ';

  @override
  String get agentsMetricDisk => 'ディスク';

  @override
  String get agentsMetricPersisted => '永続化';

  @override
  String get agentsMetricHandles => 'ハンドル';

  @override
  String get agentsPublish => '発行';

  @override
  String get agentsTaskTitleLabel => 'タイトル';

  @override
  String get agentsDescriptionLabel => '説明';

  @override
  String get agentsContentLabel => '内容';

  @override
  String get agentsNoteLabel => 'メモ';

  @override
  String get agentsDeleteConfirmTitle => 'エージェントを削除';

  @override
  String agentsDeleteConfirmMessage(String name) {
    return '$name を削除しますか？関連付けたスキル、ナレッジ、MCP サーバーは保持されます。';
  }

  @override
  String get agentsTabProfile => 'プロフィール';

  @override
  String get agentsTabCapabilities => '機能';

  @override
  String get agentsTabRuntime => 'ランタイム';

  @override
  String get agentsTabGovernance => 'ガバナンス';

  @override
  String get agentsTabMetadata => 'メタデータ';

  @override
  String get agentsFieldAvatar => 'アバター';

  @override
  String get agentsFieldAvatarHint => 'テキスト、絵文字、画像マーカー';

  @override
  String get agentsFieldNameRequired => '名前 *';

  @override
  String get agentsFieldPosition => '役割';

  @override
  String get agentsFieldDepartment => '部門';

  @override
  String get agentsFieldLevel => 'レベル';

  @override
  String get agentsFieldIntroduction => '紹介';

  @override
  String get agentsFieldArchive => 'アーカイブ';

  @override
  String get agentsFieldRouteFrontMatter => 'ルート情報';

  @override
  String get agentsFieldWelcomeMessage => 'ウェルカムメッセージ';

  @override
  String get agentsFieldPersona => 'ペルソナ';

  @override
  String get agentsFieldResponsibilityBoundary => '責任範囲';

  @override
  String get agentsKnowledgeBase => 'ナレッジベース';

  @override
  String get agentsBuiltInTools => '組み込みツール';

  @override
  String get agentsModelLabel => 'モデル';

  @override
  String get agentsEnableAgentTitle => 'エージェントを有効化';

  @override
  String get agentsEnableAgentBody => 'エージェントループと組み込みツールを有効にします。';

  @override
  String get agentsSelfLearningTitle => '自己学習';

  @override
  String get agentsSelfLearningBody => 'Hermes Agent でスキル、メモリ、経験を蓄積します。';

  @override
  String get agentsFieldWorkspacePath => 'ワークスペースパス';

  @override
  String get agentsFieldWorkspaceScope => 'ワークスペース範囲';

  @override
  String get agentsCrons => 'Crons';

  @override
  String get agentsClusterScaling => 'クラスタスケーリング';

  @override
  String get agentsMinWorkersLabel => '最小 Worker';

  @override
  String get agentsMaxWorkersLabel => '最大 Worker';

  @override
  String get agentsMaxRetriesLabel => '最大リトライ';

  @override
  String get agentsSchedulerPolicyLabel => 'スケジューラーポリシー';

  @override
  String get agentsTaskLabelsLabel => 'タスクラベル';

  @override
  String get agentsFieldName => '名前';

  @override
  String get agentsFieldTarget => '目標';

  @override
  String get agentsMetadataInfoTitle => '権限とプロフィールメタデータ';

  @override
  String get agentsNoOptionsAvailable => '利用可能な項目はありません。';

  @override
  String get agentExecutionModeNormal => 'デフォルト';

  @override
  String get agentExecutionModeFullAccess => 'フルアクセス';

  @override
  String get agentLifecycleStopped => '停止中';

  @override
  String get agentLifecycleRunning => '実行中';

  @override
  String get agentLifecyclePaused => '一時停止';

  @override
  String get agentLifecycleDegraded => '低下中';

  @override
  String get agentTaskStatusBacklog => 'バックログ';

  @override
  String get agentTaskStatusReady => '準備完了';

  @override
  String get agentTaskStatusRunning => '実行中';

  @override
  String get agentTaskStatusWaitingApproval => '承認待ち';

  @override
  String get agentTaskStatusPaused => '一時停止';

  @override
  String get agentTaskStatusCompleted => '完了';

  @override
  String get agentTaskStatusFailed => '失敗';

  @override
  String get agentTaskStatusCanceled => 'キャンセル済み';

  @override
  String get agentApprovalStatusPending => '保留中';

  @override
  String get agentApprovalStatusApproved => '承認済み';

  @override
  String get agentApprovalStatusRejected => '却下';

  @override
  String get agentApprovalStatusExpired => '期限切れ';

  @override
  String get agentWorkerStatusIdle => 'アイドル';

  @override
  String get agentWorkerStatusBusy => 'ビジー';

  @override
  String get agentWorkerStatusDraining => 'ドレイン中';

  @override
  String get agentWorkerStatusOffline => 'オフライン';

  @override
  String get agentsActivityAgentStarted => 'エージェント開始';

  @override
  String get agentsActivityAgentStopped => 'エージェント停止';

  @override
  String get agentsActivityTaskPublished => 'タスク発行済み';

  @override
  String get agentsActivityTaskUpdated => 'タスク更新済み';

  @override
  String get agentsActivityTaskCanceled => 'タスクキャンセル済み';

  @override
  String get agentsActivityTaskPaused => 'タスク一時停止';

  @override
  String get agentsActivityTaskTerminated => 'タスク終了';

  @override
  String get agentsActivityTaskResumed => 'タスク再開';

  @override
  String get hookEventSessionStart => 'セッション開始';

  @override
  String get hookEventUserPromptSubmit => 'ユーザープロンプト送信';

  @override
  String get hookEventPreToolUse => 'ツール使用前';

  @override
  String get hookEventPostToolUse => 'ツール使用後';

  @override
  String get hookEventSubagentStart => 'サブエージェント開始';

  @override
  String get hookEventSubagentStop => 'サブエージェント停止';

  @override
  String get hookEventStop => '停止';

  @override
  String get hookEventPreCompact => '圧縮前';

  @override
  String get hookEventSessionEnd => 'セッション終了';

  @override
  String get hookEventErrorOccurred => 'エラー発生';

  @override
  String get builtinToolLoadStrategyEagerShort => '即時';

  @override
  String get builtinToolLoadStrategyLazy => '遅延';

  @override
  String get builtinToolLoadStrategyDeferred => '後回し';

  @override
  String get builtinToolLoadStrategyEagerFull => '即時読み込み';

  @override
  String get builtinToolCustomBadge => 'カスタム';

  @override
  String get builtinToolForceBadge => '強制';

  @override
  String get builtinToolMoveUp => '上へ移動';

  @override
  String get builtinToolMoveDown => '下へ移動';

  @override
  String builtinToolEditorTitle(String kind) {
    return 'ツールを編集 — $kind';
  }

  @override
  String get builtinToolEnableTitle => 'ツールを有効化';

  @override
  String get builtinToolEnableBody => '無効にすると、このツールはモデルのツールカタログに表示されません。';

  @override
  String get builtinToolDisplayNameLabel => '表示名（任意）';

  @override
  String get builtinToolDisplayNameHelper => '既定のツール名を上書きします。空欄なら組み込み既定値を使います。';

  @override
  String get builtinToolSummaryLabel => '概要（任意）';

  @override
  String get builtinToolSummaryHelper => 'ツール一覧で用途を素早く確認するために表示されます。';

  @override
  String get builtinToolPromptOverrideLabel => 'プロンプト追記（任意）';

  @override
  String get builtinToolPromptOverrideHelper => 'ツール説明の末尾に追加され、モデルの使い方を微調整します。';

  @override
  String get builtinToolSchemaOverrideLabel => 'スキーマ上書き（JSON、任意）';

  @override
  String get builtinToolSchemaOverrideHelper =>
      '入力パラメータ定義を上書きする完全な JSON Schema。空欄なら既定値です。';

  @override
  String get builtinToolPriorityLabel => '優先度 (0–9999)';

  @override
  String get builtinToolPriorityHelper => '小さいほど優先';

  @override
  String get builtinToolLoadStrategyLabel => '読み込み戦略';

  @override
  String get builtinToolForceLoadTitle => '強制読み込み';

  @override
  String get builtinToolForceLoadBody =>
      '有効にすると、組み込み遅延読み込みが Auto/On でもこのスキーマを直接送ります。';

  @override
  String get builtinToolMaxOutputLabel => '最大出力（文字）';

  @override
  String get builtinToolGlobalDefaultHint => 'グローバル既定値';

  @override
  String get builtinToolTagsLabel => 'タグ（カンマ区切り）';

  @override
  String get builtinToolTagsHelper => '例: io, file, dangerous';

  @override
  String get builtinToolRequireConfirmationTitle => '実行確認';

  @override
  String get builtinToolRequireConfirmationBody =>
      '実行前にユーザー確認を求めるかどうか。「既定」はツール本来の動作を使います。';

  @override
  String get builtinToolConfirmationDefault => '既定';

  @override
  String get builtinToolConfirmationYes => 'はい';

  @override
  String get builtinToolConfirmationNo => 'いいえ';

  @override
  String get memoryTitleField => 'タイトル（任意）';

  @override
  String get memoryTitleHint => 'このメモリの要点を一文で要約します。空欄なら本文プレビューを使います';

  @override
  String get commonRetry => '再試行';

  @override
  String get commonOk => 'OK';

  @override
  String get commonExport => 'エクスポート';

  @override
  String get appUpdateDialogTitle => '更新を確認';

  @override
  String get appUpdateChecking => '更新を確認しています...';

  @override
  String appUpdateCurrentVersion(Object version) {
    return '現在のバージョン: $version';
  }

  @override
  String appUpdateNewVersion(Object version) {
    return '新しいバージョン: v$version';
  }

  @override
  String appUpdatePublished(Object date) {
    return '公開日: $date';
  }

  @override
  String appUpdateFileSize(Object size) {
    return 'サイズ: $size';
  }

  @override
  String get appUpdateAlreadyLatestTitle => '最新版です';

  @override
  String appUpdateAlreadyLatestBody(Object version) {
    return 'OpenHand $version は最新バージョンです。';
  }

  @override
  String get appUpdateDownloadComplete => 'ダウンロード完了';

  @override
  String get appUpdateDownloading => 'ダウンロード中...';

  @override
  String get appUpdateCheckFailed => '更新確認に失敗';

  @override
  String get appUpdateLater => '後で';

  @override
  String get appUpdateDownload => 'ダウンロード';

  @override
  String get exportRangeInvalid => '有効な範囲を入力してください (1 ≤ 開始 ≤ 終了)';

  @override
  String get exportRangeStart => '開始';

  @override
  String get exportRangeEnd => '終了';

  @override
  String get exportSessionSettingsTitle => 'セッション設定をエクスポート';

  @override
  String exportTotalMessages(Object count) {
    return 'エクスポート可能なメッセージ: $count';
  }

  @override
  String get exportRolesSection => 'ロール';

  @override
  String get exportAllRoles => 'すべてのロール';

  @override
  String get exportMessageKindsSection => 'メッセージ種別';

  @override
  String get exportAllKinds => 'すべての種別';

  @override
  String get exportMessageRangeSection => 'メッセージ範囲';

  @override
  String get exportOnlyRange => '指定範囲のみエクスポート (1 始まり、両端含む)';

  @override
  String get exportOtherOptions => 'その他のオプション';

  @override
  String get exportIncludeDeleted => '削除済みメッセージを含める';

  @override
  String get exportPickOneRole => 'ロールを少なくとも 1 つ選択してください。';

  @override
  String get exportPickOneMessageKind => 'メッセージ種別を少なくとも 1 つ選択してください。';

  @override
  String get exportRoleSystem => 'システム';

  @override
  String get exportRoleUser => 'ユーザー';

  @override
  String get exportRoleAssistant => 'アシスタント';

  @override
  String get exportRoleTool => 'ツール';

  @override
  String get exportKindUser => 'ユーザーメッセージ';

  @override
  String get exportKindAssistant => 'アシスタント応答';

  @override
  String get exportKindReasoning => '推論';

  @override
  String get exportKindToolCall => 'ツール呼び出し';

  @override
  String get exportKindTool => 'ツール結果';

  @override
  String get exportKindCompressionPoint => '圧縮ポイント';

  @override
  String get exportKindMcp => 'MCP イベント';

  @override
  String get exportKindSkill => 'スキルイベント';

  @override
  String get exportKindHook => 'Hook イベント';

  @override
  String get exportKindSelfLearning => '自己学習';

  @override
  String get exportKindFileMutationSummary => 'ファイル変更サマリー';

  @override
  String get exportKindStatus => 'ステータスメッセージ';

  @override
  String get exportPhaseLogRangeSection => 'フェーズログ範囲';

  @override
  String exportTotalPhaseLogs(Object count) {
    return 'エクスポート可能なフェーズログ: $count';
  }

  @override
  String get modelSearchHint => 'モデルを検索…';

  @override
  String modelSearchResultCount(Object filtered, Object total) {
    return '$filtered / $total モデル';
  }

  @override
  String get modelSearchNoAvailableModels => '利用可能なモデルがありません';

  @override
  String get modelSearchNoMatchingModels => '一致するモデルがありません';

  @override
  String get modelSearchRecent => '最近使用';

  @override
  String get nativeAudioLoadFailed => '音声を読み込めません。システムプレーヤーで開いてください。';

  @override
  String get nativeAudioPlaybackFailed => '再生に失敗しました。再試行するか、システムプレーヤーで開いてください。';

  @override
  String get nativeAudioBack15Seconds => '15 秒戻る';

  @override
  String get nativeAudioPause => '一時停止';

  @override
  String get nativeAudioPlay => '再生';

  @override
  String get nativeAudioForward15Seconds => '15 秒進む';

  @override
  String get nativeAudioMute => 'ミュート';

  @override
  String get nativeAudioUnmute => 'ミュート解除';

  @override
  String get nativeAudioSystemPlayer => 'システムプレーヤー';

  @override
  String get nativeAudioSequencePlayback => '順番に再生';

  @override
  String get nativeAudioRepeatOne => '1 曲リピート';

  @override
  String get nativeAudioShufflePlayback => 'シャッフル再生';

  @override
  String nativeAudioEffectTooltip(Object effect) {
    return 'エフェクト: $effect';
  }

  @override
  String get nativeAudioEffectStandard => '標準';

  @override
  String get nativeAudioEffectSpatial => '3D';

  @override
  String get nativeAudioEffectVocal => 'ボーカル';

  @override
  String get nativeAudioEffectWarm => 'ウォーム';

  @override
  String get hooksTitle => 'Hooks';

  @override
  String get hooksSubtitle =>
      'AI Agent のライフサイクル段階ごとに実行するスクリプトを設定します。対応するイベントが発生すると、Hook は順番に実行されます。';

  @override
  String get hooksNew => '新規 Hook';

  @override
  String get hooksDeleteTitle => 'Hook を削除';

  @override
  String hooksDeleteMessage(Object label) {
    return '「$label」を削除しますか？この操作は元に戻せません。';
  }

  @override
  String get hooksEmptyTitle => 'Hook はまだ設定されていません';

  @override
  String get hooksEmptyBody => '上の「新規 Hook」をクリックして設定を開始します。';

  @override
  String get hooksTimeoutTooltip => 'タイムアウト';

  @override
  String hooksInlineScriptDescription(Object firstLine) {
    return 'インライン: $firstLine';
  }

  @override
  String get hooksNoScriptConfigured => 'スクリプト未設定';

  @override
  String get hooksEditTitle => 'Hook を編集';

  @override
  String get hooksLabelField => 'ラベル';

  @override
  String get hooksLabelHint => '例: ログ記録';

  @override
  String get hooksTriggerEvent => 'トリガーイベント';

  @override
  String get hooksScriptSource => 'スクリプトソース';

  @override
  String get hooksScriptSourceFile => 'ファイル';

  @override
  String get hooksScriptSourceInline => 'インライン';

  @override
  String get hooksScriptFilePath => 'スクリプトファイルパス';

  @override
  String get hooksScriptFileHint => '.sh / .ps1 / .bat ファイルを選択';

  @override
  String get hooksBrowse => '参照';

  @override
  String get hooksScriptContextFileHelp =>
      'コンテキスト JSON は 2 つの安全な方法で渡されます（どちらも jq で使用可能）：\n① 一時ファイル: jq -r .session_id \"\$OPENHAND_HOOK_CONTEXT_FILE\"\n② stdin の生バイト: jq -r .session_id\nフィールド: session_id、session_file_path、environment など。';

  @override
  String get hooksInlineWindowsHint => 'PowerShell / BAT スクリプトを入力';

  @override
  String get hooksInlineShellHint => 'シェルスクリプトを入力 (#!/bin/bash は不要)';

  @override
  String get hooksScriptContextInlineHelp =>
      'コンテキスト JSON は 2 つの安全な方法で渡されます（どちらも jq で使用可能）：\n① 一時ファイル: SID=\$(jq -r .session_id \"\$OPENHAND_HOOK_CONTEXT_FILE\")\n② stdin の生バイト: SID=\$(jq -r .session_id)\nフィールド: session_id、session_file_path、environment、statistics など。';

  @override
  String get hooksTimeoutSeconds => 'タイムアウト（秒）';

  @override
  String get hooksEnabled => '有効';

  @override
  String get hooksValidationLabelRequired => 'Hook ラベルを入力してください。';

  @override
  String get hooksValidationScriptFileRequired => 'スクリプトファイルを選択してください。';

  @override
  String get hooksValidationInlineScriptRequired => 'インラインスクリプトの内容を入力してください。';

  @override
  String get hooksFileTypeScripts => 'スクリプト';

  @override
  String get hooksFileTypeShellScripts => 'シェルスクリプト';

  @override
  String get hooksFileTypeAllFiles => 'すべてのファイル';

  @override
  String get commonConfirm => '確定';

  @override
  String get choiceInputCustomOptionLabel => 'カスタム入力';

  @override
  String get choiceInputCustomInputHint => 'ここに回答を入力…';

  @override
  String get choiceInputCustomOptionDescription => '自分の回答を入力するにはこれを選択';

  @override
  String get mediaPreviewImageCopied => '画像をクリップボードにコピーしました。';

  @override
  String get mediaPreviewImageFileOrPathCopied =>
      '画像ファイルまたはパスをクリップボードにコピーしました。';

  @override
  String get mediaPreviewMediaFileCopied => 'メディアファイルをクリップボードにコピーしました。';

  @override
  String get mediaPreviewDirectCopyUnavailablePathCopied =>
      'このプラットフォームではメディアファイルを直接コピーできません。ファイルパスをコピーしました。';

  @override
  String get mediaPreviewMediaUrlCopied => 'メディア URL をコピーしました。';

  @override
  String get mediaPreviewDirectCopyUnavailableTempPathCopied =>
      'このプラットフォームではメディアファイルを直接コピーできません。一時ファイルパスをコピーしました。';

  @override
  String get mediaPreviewDataCopyFailedUrlCopied =>
      'メディアデータをコピーできません。ソース URL をコピーしました。';

  @override
  String mediaPreviewCopyFailed(Object error) {
    return 'コピーに失敗しました: $error';
  }

  @override
  String get mediaPreviewNoSource => 'メディアソースを利用できません。';

  @override
  String get knowledgeVectorDistributionTitle => 'ベクトル分布';

  @override
  String get knowledgeVectorDistributionLoading => 'ベクトルをサンプリングして投影しています。';

  @override
  String get knowledgeVectorDistributionEmpty =>
      '現在の collection には表示できるベクトルがありません。';

  @override
  String get knowledgeVectorProjectionSection => '投影';

  @override
  String get knowledgeVectorAlgorithm => 'アルゴリズム';

  @override
  String get knowledgeVectorOriginalDimensions => '元の次元';

  @override
  String get knowledgeVectorVisiblePoints => '表示点数';

  @override
  String get knowledgeVectorSampled => 'サンプリング';

  @override
  String get knowledgeVectorDurationMs => '所要時間 (ms)';

  @override
  String get knowledgeVectorResample => '再サンプリング';

  @override
  String get qdrantStatusRefreshIncomplete => 'Qdrant ステータス更新で不完全なデータが返されました。';

  @override
  String get qdrantStatusRawVectorEmpty => '先に raw vector を入力してください。';

  @override
  String qdrantStatusRawVectorInvalid(Object value) {
    return '無効なベクトル値: $value';
  }

  @override
  String qdrantStatusRawVectorDimensionMismatch(int actual, int expected) {
    return 'raw vector は $actual 次元ですが、現在の設定では $expected 次元が必要です。';
  }

  @override
  String get qdrantStatusPointIdsEmpty => '先に point/chunk ID を入力してください。';

  @override
  String get qdrantStatusPayloadIndexesSubmitted =>
      '既定の Payload インデックス作成を送信しました。';

  @override
  String get qdrantStatusDangerousOpsDisabled =>
      '先にナレッジベース設定で危険な管理操作を有効にしてください。';

  @override
  String get qdrantStatusDeletePointIdsEmpty => '先に削除するポイント ID を入力してください。';

  @override
  String get qdrantStatusDeletePointsTitle => 'Qdrant ポイントを削除しますか？';

  @override
  String qdrantStatusDeletePointsMessage(int count) {
    return '現在のコレクションから $count 件のポイントを削除します。この操作は元に戻せません。';
  }

  @override
  String get qdrantStatusDeletePointsConfirm => 'ポイントを削除';

  @override
  String get qdrantStatusPointsDeleted => 'ポイントを削除しました。';

  @override
  String get qdrantStatusDeleteCollectionTitle => 'Qdrant コレクションを削除しますか？';

  @override
  String qdrantStatusDeleteCollectionMessage(Object collection) {
    return 'コレクション「$collection」とその中の全ポイントを削除します。この操作は元に戻せません。';
  }

  @override
  String get qdrantStatusDeleteCollectionConfirm => 'コレクションを削除';

  @override
  String get qdrantStatusCollectionDeleted => 'コレクションを削除しました。';

  @override
  String get qdrantStatusDiagnosticsCopied => '診断情報をコピーしました。';

  @override
  String get qdrantStatusTitle => 'Qdrant 運用';

  @override
  String get qdrantStatusTabOverview => '概要';

  @override
  String get qdrantStatusTabCollections => 'コレクション';

  @override
  String get qdrantStatusTabPoints => 'ポイント';

  @override
  String get qdrantStatusTabDiagnostics => '診断';

  @override
  String get qdrantStatusRefresh => '更新';

  @override
  String get qdrantStatusCopyDiagnostics => '診断をコピー';

  @override
  String get qdrantStatusHeaderTitle => 'ローカルベクトル DB の状態';

  @override
  String get qdrantStatusMetricCollections => 'コレクション';

  @override
  String get qdrantStatusMetricPoints => 'ポイント';

  @override
  String get qdrantStatusMetricIndexedVectors => 'インデックス済みベクトル';

  @override
  String get qdrantStatusMetricChunks => 'チャンク';

  @override
  String get qdrantStatusMetricPendingJobs => '保留中ジョブ';

  @override
  String get qdrantStatusMetricWalCapacity => 'WAL 容量';

  @override
  String get qdrantStatusSmoothTrend => '平滑トレンド';

  @override
  String get qdrantStatusNoCollections => 'コレクションがないか、Qdrant を利用できません。';

  @override
  String get qdrantStatusPointsSectionTitle => 'ポイント / 検索 / スクロール';

  @override
  String get qdrantStatusPointIdsLabel => 'ポイント / チャンク ID';

  @override
  String get qdrantStatusSourceFilterLabel => 'ソース ID フィルタ';

  @override
  String get qdrantStatusTagFilterLabel => 'タグフィルタ';

  @override
  String get qdrantStatusLimitLabel => '上限';

  @override
  String get qdrantStatusRawVectorLabel => 'raw vector（カンマまたは空白区切り、次元数一致が必要）';

  @override
  String get qdrantStatusQueryIds => 'ID で照会';

  @override
  String get qdrantStatusScrollFilter => 'スクロール / フィルタ';

  @override
  String get qdrantStatusRawVectorSearch => 'raw vector 検索';

  @override
  String get qdrantStatusRebuildPayloadIndexes => 'Payload インデックスを再構築';

  @override
  String get qdrantStatusDeletePoints => 'ポイントを削除';

  @override
  String get qdrantStatusOperationResult => '操作結果';

  @override
  String get qdrantStatusRawDiagnosticsJson => '生の診断 JSON';

  @override
  String get qdrantStatusNoDiagnostics => '診断データはまだありません。';

  @override
  String get qdrantStatusLatestOperationResult => '最新の操作結果';

  @override
  String get qdrantStatusOperationLog => '操作ログ';

  @override
  String get qdrantStatusNoOperations => '操作はまだありません。';

  @override
  String get qdrantStatusCollectingSamples => 'トレンド表示用のサンプルを収集中です。';

  @override
  String get qdrantStatusTrendPoints => 'ポイント';

  @override
  String get qdrantStatusTrendChunks => 'チャンク';

  @override
  String get qdrantStatusTrendPendingFailed => '保留/失敗';

  @override
  String qdrantStatusTrendSampleCount(int count) {
    return '$count 点';
  }

  @override
  String get qdrantSectionOverview => '概要';

  @override
  String get qdrantSectionDockerContainer => 'Docker / コンテナ';

  @override
  String get qdrantSectionApiMetrics => 'Qdrant API メトリクス';

  @override
  String get qdrantSectionCollectionConfig => 'コレクション設定';

  @override
  String get qdrantSectionStorageOptimizer => 'ストレージ / オプティマイザ';

  @override
  String get qdrantSectionTelemetry => 'テレメトリ';

  @override
  String get qdrantSectionOpenHandKnowledge => 'OpenHand ナレッジ';

  @override
  String get qdrantMetricServiceStatus => 'サービス状態';

  @override
  String get qdrantMetricRestEndpoint => 'REST エンドポイント';

  @override
  String get qdrantMetricGrpcEndpoint => 'gRPC エンドポイント';

  @override
  String get qdrantMetricQdrantVersion => 'Qdrant バージョン';

  @override
  String get qdrantMetricCurrentCollection => '現在のコレクション';

  @override
  String get qdrantMetricCollectionStatus => 'コレクション状態';

  @override
  String get qdrantMetricOptimizerStatus => 'オプティマイザ状態';

  @override
  String get qdrantMetricLastHealthCheck => '最終ヘルスチェック';

  @override
  String get qdrantMetricDockerDaemon => 'Docker デーモン';

  @override
  String get qdrantMetricContainerCpu => 'コンテナ CPU';

  @override
  String get qdrantMetricContainerMemory => 'コンテナメモリ';

  @override
  String get qdrantMetricNetworkIo => 'ネットワーク I/O';

  @override
  String get qdrantMetricBlockIo => 'ブロック I/O';

  @override
  String get qdrantMetricRestartCount => '再起動回数';

  @override
  String get qdrantMetricLatestLogSummary => '最新ログ要約';

  @override
  String get qdrantMetricCollectionsTotal => 'コレクション総数';

  @override
  String get qdrantMetricPointsTotal => 'ポイント総数';

  @override
  String get qdrantMetricVectorsTotal => 'ベクトル総数';

  @override
  String get qdrantMetricIndexedVectorsTotal => 'インデックス済みベクトル総数';

  @override
  String get qdrantMetricSegmentsTotal => 'セグメント';

  @override
  String get qdrantMetricPayloadSchemaFields => 'Payload schema フィールド数';

  @override
  String get qdrantMetricPayloadSchemaNames => 'Payload schema 名';

  @override
  String get qdrantMetricVectorSize => 'ベクトル次元';

  @override
  String get qdrantMetricDistance => '距離';

  @override
  String get qdrantMetricSingleNodeMode => 'シングルノードモード';

  @override
  String get qdrantMetricPayloadIndexStatus => 'Payload インデックス状態';

  @override
  String get qdrantMetricClusterStatus => 'クラスタ状態';

  @override
  String get qdrantMetricHnswM => 'HNSW M';

  @override
  String get qdrantMetricHnswEfConstruct => 'HNSW ef_construct';

  @override
  String get qdrantMetricHnswFullScanThreshold => 'HNSW フルスキャンしきい値';

  @override
  String get qdrantMetricHnswMaxIndexingThreads => 'HNSW 最大インデックススレッド';

  @override
  String get qdrantMetricOnDiskPayload => 'ディスク上 Payload';

  @override
  String get qdrantMetricShardNumber => 'シャード数';

  @override
  String get qdrantMetricReplicationFactor => 'レプリケーション係数';

  @override
  String get qdrantMetricWriteConsistencyFactor => '書き込み整合性係数';

  @override
  String get qdrantMetricReadFanOutFactor => '読み取り fan-out 係数';

  @override
  String get qdrantMetricOptimizerDeletedThreshold => 'オプティマイザ削除しきい値';

  @override
  String get qdrantMetricOptimizerVacuumMinVectorNumber => 'Vacuum 最小ベクトル数';

  @override
  String get qdrantMetricOptimizerDefaultSegmentNumber => '既定セグメント数';

  @override
  String get qdrantMetricOptimizerMaxSegmentSize => '最大セグメントサイズ';

  @override
  String get qdrantMetricOptimizerIndexingThreshold => 'インデックスしきい値';

  @override
  String get qdrantMetricOptimizerFlushIntervalSeconds => 'flush 間隔秒';

  @override
  String get qdrantMetricWalCapacityMb => 'WAL 容量 MB';

  @override
  String get qdrantMetricWalSegmentsAhead => 'WAL 先行セグメント';

  @override
  String get qdrantMetricQuantization => '量子化';

  @override
  String get qdrantMetricStrictMode => '厳格モード';

  @override
  String get qdrantMetricTelemetryStatus => 'テレメトリ状態';

  @override
  String get qdrantMetricAppVersion => 'アプリバージョン';

  @override
  String get qdrantMetricAppName => 'アプリ名';

  @override
  String get qdrantMetricTelemetryCollections => 'コレクションテレメトリ';

  @override
  String get qdrantMetricTelemetryRequests => 'リクエストテレメトリ';

  @override
  String get qdrantMetricSourceCount => 'ソース数';

  @override
  String get qdrantMetricChunkCount => 'チャンク数';

  @override
  String get qdrantMetricPendingEmbeddingJobs => '保留中の埋め込みジョブ';

  @override
  String get qdrantMetricFailedEmbeddingJobs => '失敗した埋め込みジョブ';

  @override
  String get qdrantMetricEmbeddingModel => '現在の埋め込みモデル';

  @override
  String get qdrantMetricEmbeddingDimensions => '現在の次元数';

  @override
  String get qdrantMetricRetrievalTopN => '検索 topN';

  @override
  String get qdrantMetricRetrievalTopK => '最終 topK';

  @override
  String get qdrantMetricMinSimilarity => '最小類似度';

  @override
  String get qdrantMetricPromptChunkBudget => 'Prompt チャンク予算';

  @override
  String get qdrantMetricPromptTokenBudget => 'Prompt token 予算';

  @override
  String get qdrantValueYes => 'はい';

  @override
  String get qdrantValueNo => 'いいえ';

  @override
  String get qdrantValueHealthy => '正常';

  @override
  String get qdrantValueUnknown => '不明';

  @override
  String get qdrantValueLoading => '読み込み中';

  @override
  String get qdrantValueAvailable => '利用可能';

  @override
  String get qdrantValueUnavailable => '利用不可';

  @override
  String get qdrantValuePluginServiceScan => 'プラグインサービスがスキャン';

  @override
  String get qdrantValuePluginRuntimeMetric => 'プラグインランタイムが提供';

  @override
  String get qdrantValuePluginDetailsLogs => 'プラグイン詳細で確認可能';

  @override
  String get qdrantValueLocalSingleNodeOrUnavailable => 'ローカル単一ノード / 利用不可';

  @override
  String get qdrantValueClusterInfoAvailable => 'クラスタ情報を取得済み';

  @override
  String get qdrantValuePayloadSchemaConfigured => 'Payload schema 設定済み';

  @override
  String get qdrantValuePayloadSchemaMissing => 'Payload schema が見つかりません';
}
