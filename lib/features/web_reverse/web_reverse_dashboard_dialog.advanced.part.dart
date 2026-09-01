part of 'web_reverse_dashboard_dialog.dart';

/// 高级工具弹窗：列出"持久化 Header / CDP 命令面板 / 体检报告 / 反向脚本 /
/// 调用图聚合 / 对比模式 / Service Worker 干预"等低频但有用的入口。
const int _kWebcrackMaxInputChars = 2 * kBytesPerMiB;
const int _kWebcrackMaxOutputBytes = 8 * kBytesPerMiB;
const int _kWebcrackMaxOutputEntries = 512;
const Duration _kWebcrackTempWriteTimeout = Duration(seconds: 10);
const Duration _kWebcrackOutputReadTotalTimeout = Duration(seconds: 30);
const BoundedDeletePolicy _kWebcrackTempDeletePolicy = BoundedDeletePolicy(
  maxEntries: 4096,
  maxDepth: 32,
  operationTimeout: Duration(seconds: 5),
  totalTimeout: Duration(seconds: 30),
);

String _advancedTextForLocale(
  Locale locale, {
  required String zh,
  required String en,
  String? zhHant,
  String? fr,
  String? de,
  String? ja,
}) => openHandLocalizedTextForLocale(
  locale,
  zh: zh,
  zhHant: zhHant,
  en: en,
  fr: fr,
  de: de,
  ja: ja,
);

class _AdvancedMenuDialog extends StatelessWidget {
  const _AdvancedMenuDialog({
    required this.controller,
    required this.isZh,
    required this.hostContext,
  });

  final WebReverseSessionController controller;
  final bool isZh;
  final BuildContext hostContext;

  @override
  Widget build(BuildContext dialogContext) {
    final context = hostContext;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    String tr({
      required String zh,
      required String en,
      String? zhHant,
      String? fr,
      String? de,
      String? ja,
    }) => openHandLocalizedText(
      context,
      zh: zh,
      zhHant: zhHant,
      en: en,
      fr: fr,
      de: de,
      ja: ja,
    );
    final entries = <_AdvancedEntry>[
      _AdvancedEntry(
        icon: Icons.archive_rounded,
        title: tr(
          zh: '导出会话体检报告',
          zhHant: '匯出會話體檢報告',
          en: 'Export session bundle',
          fr: 'Exporter le bundle de session',
          de: 'Sitzungsbundle exportieren',
          ja: 'セッションバンドルをエクスポート',
        ),
        subtitle: tr(
          zh: '一键打包 HAR + console + 截图 + recorder 为 .zip',
          zhHant: '一鍵打包 HAR + console + 截圖 + recorder 為 .zip',
          en: 'Bundle HAR + console + screenshots + recorder as .zip',
          fr: 'Regroupe HAR, console, captures et recorder en .zip',
          de: 'Bundelt HAR, Konsole, Screenshots und Recorder als .zip',
          ja: 'HAR、console、スクリーンショット、recorder を .zip にまとめます',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          final path = await controller.exportSessionBundle();
          if (!context.mounted) return;
          if (path == null) {
            showOpenHandErrorSnack(
              context,
              tr(
                zh: '导出失败',
                zhHant: '匯出失敗',
                en: 'Export failed',
                fr: 'Échec de l’export',
                de: 'Export fehlgeschlagen',
                ja: 'エクスポートに失敗しました',
              ),
              duration: kOpenHandSnackBarNormalDuration,
            );
          } else {
            showOpenHandSuccessSnack(
              context,
              tr(
                zh: '已导出到 $path',
                zhHant: '已匯出到 $path',
                en: 'Exported to $path',
                fr: 'Exporte vers $path',
                de: 'Exportiert nach $path',
                ja: '$path にエクスポートしました',
              ),
              duration: kOpenHandSnackBarNormalDuration,
            );
          }
        },
      ),
      _AdvancedEntry(
        icon: Icons.add_link_rounded,
        title: tr(
          zh: '持久注入 Headers',
          zhHant: '持久注入 Headers',
          en: 'Persistent Headers',
          fr: 'Headers persistants',
          de: 'Persistente Header',
          ja: '永続 Headers 注入',
        ),
        subtitle: tr(
          zh: '所有请求自动追加 Header（X-Debug 等场景）',
          zhHant: '所有請求自動追加 Header（X-Debug 等場景）',
          en: 'Auto-append headers on every request',
          fr: 'Ajoute automatiquement des headers à chaque requête',
          de: 'Fugt jeder Anfrage automatisch Header hinzu',
          ja: 'すべてのリクエストに Header を自動追加します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await _showExtraHeadersDialog(context, controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.alt_route_rounded,
        title: tr(
          zh: '网络拦截规则',
          zhHant: '網路攔截規則',
          en: 'Network intercept rules',
          fr: 'Règles d’interception réseau',
          de: 'Netzwerk-Abfangregeln',
          ja: 'ネットワークインターセプト規則',
        ),
        subtitle: tr(
          zh: 'URL 通配 → block / 重写 URL / 追加 Header；命中即自动放行',
          zhHant: 'URL 通配 → block / 重寫 URL / 追加 Header；命中即自動放行',
          en: 'URL pattern → block / rewrite URL / inject headers',
          fr: 'Motif URL → bloquer / réécrire URL / injecter headers',
          de: 'URL-Muster → blockieren / URL umschreiben / Header einfugen',
          ja: 'URL パターン → block / URL 書き換え / Header 注入',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await _showInterceptRulesDialog(context, controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.code_rounded,
        title: tr(
          zh: 'CDP 命令面板',
          zhHant: 'CDP 命令面板',
          en: 'CDP Command Palette',
          fr: 'Palette de commandes CDP',
          de: 'CDP-Befehlspalette',
          ja: 'CDP コマンドパレット',
        ),
        subtitle: tr(
          zh: '原始 CDP method + JSON params；power-user 逃生通道',
          zhHant: '原始 CDP method + JSON params；power-user 逃生通道',
          en: 'Raw CDP method + JSON params; power-user escape hatch',
          fr: 'Method CDP brut + params JSON pour usages avances',
          de: 'Rohe CDP-Method + JSON-Parameter für Power-User',
          ja: 'Raw CDP method + JSON params の上級者向け入口',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await _showCdpPaletteDialog(context, controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.auto_awesome_rounded,
        title: tr(
          zh: 'AI 分析最近请求',
          zhHant: 'AI 分析最近請求',
          en: 'AI analyse latest requests',
          fr: 'Analyse IA des dernières requêtes',
          de: 'AI analysiert letzte Anfragen',
          ja: 'AI で最近のリクエストを分析',
        ),
        subtitle: tr(
          zh: '把最近 10 条请求摘要复制到剪贴板，粘贴回会话即由 AI 解读',
          zhHant: '將最近 10 筆請求摘要複製到剪貼簿，貼回會話即可由 AI 解讀',
          en: 'Copy last 10 request summaries; paste into chat for AI analysis',
          fr: 'Copie les 10 dernières requêtes pour les analyser dans le chat',
          de: 'Kopiert die letzten 10 Anfragen zur AI-Analyse in den Chat',
          ja: '直近 10 件の要約をコピーし、チャットへ貼り付けて AI 分析します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await _copyRecentRequestsForAi(context, controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.compare_arrows_rounded,
        title: tr(
          zh: '对比两个请求',
          zhHant: '對比兩個請求',
          en: 'Diff two requests',
          fr: 'Comparer deux requêtes',
          de: 'Zwei Anfragen vergleichen',
          ja: '2 つのリクエストを比較',
        ),
        subtitle: tr(
          zh: '选两条请求查 headers / body / response 字段差异',
          zhHant: '選兩筆請求查看 headers / body / response 欄位差異',
          en: 'Pick two requests to diff headers / body / response',
          fr: 'Compare headers, body et response de deux requêtes',
          de: 'Vergleicht Header, Body und Response zweier Anfragen',
          ja: '2 件の headers / body / response の差分を確認します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await _showDiffPicker(context, controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.cloud_off_rounded,
        title: tr(
          zh: 'Service Worker 列表',
          zhHant: 'Service Worker 清單',
          en: 'Service Workers',
          fr: 'Service Workers',
          de: 'Service Worker',
          ja: 'Service Worker 一覧',
        ),
        subtitle: tr(
          zh: '查看注册的 SW + 一键 unregister',
          zhHant: '查看已註冊 SW + 一鍵 unregister',
          en: 'Inspect registered SWs and unregister',
          fr: 'Inspecte les SW enregistrés et les désinscrit',
          de: 'Registrierte SWs ansehen und abmelden',
          ja: '登録済み SW の確認と unregister',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await _showServiceWorkersDialog(context, controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.dns_rounded,
        title: tr(
          zh: '启动 HAR 重放服务器',
          zhHant: '啟動 HAR 重放伺服器',
          en: 'Start HAR replay server',
          fr: 'Démarrer le serveur de replay HAR',
          de: 'HAR-Replay-Server starten',
          ja: 'HAR リプレイサーバーを起動',
        ),
        subtitle: tr(
          zh: '把当前 HAR 跑成本地 mock，复现脚本走 127.0.0.1:N',
          zhHant: '將目前 HAR 跑成本地 mock，重現腳本走 127.0.0.1:N',
          en: 'Mock current HAR on localhost; reproduce scripts can hit 127.0.0.1:N',
          fr: 'Expose le HAR courant en mock local sur 127.0.0.1:N',
          de: 'Mockt das aktuelle HAR lokal auf 127.0.0.1:N',
          ja: '現在の HAR を localhost mock として 127.0.0.1:N で再現します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await _toggleHarReplayServer(context, controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.swap_calls_rounded,
        title: controller.mitmproxyBridge == null
            ? tr(
                zh: '启动 mitmproxy 桥接',
                zhHant: '啟動 mitmproxy 橋接',
                en: 'Start mitmproxy bridge',
                fr: 'Démarrer le pont mitmproxy',
                de: 'mitmproxy-Bridge starten',
                ja: 'mitmproxy ブリッジを起動',
              )
            : tr(
                zh: '停止 mitmproxy 桥接（已抓 ${controller.mitmproxyCount}）',
                zhHant: '停止 mitmproxy 橋接（已抓 ${controller.mitmproxyCount}）',
                en: 'Stop mitmproxy bridge (${controller.mitmproxyCount})',
                fr: 'Arrêter le pont mitmproxy (${controller.mitmproxyCount})',
                de: 'mitmproxy-Bridge stoppen (${controller.mitmproxyCount})',
                ja: 'mitmproxy ブリッジを停止（${controller.mitmproxyCount} 件）',
              ),
        subtitle: tr(
          zh: '系统级抓包：把 App 内嵌 webview / 第三方应用流量也接入 dashboard',
          zhHant: '系統級抓包：將 App 內嵌 webview / 第三方應用流量也接入 dashboard',
          en: 'System-wide capture via mitmdump; routes 3rd-party app traffic into dashboard',
          fr: 'Capture système via mitmdump, y compris webview et apps tierces',
          de: 'Systemweite Erfassung per mitmdump, auch Webview- und Drittanbieter-Traffic',
          ja: 'mitmdump によるシステム全体キャプチャ。webview や他アプリの通信も dashboard へ送ります',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await _toggleMitmproxyBridge(context, controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.video_camera_back_rounded,
        title: tr(
          zh: 'WebRTC 资源捕获',
          zhHant: 'WebRTC 資源捕獲',
          en: 'WebRTC capture',
          fr: 'Capture WebRTC',
          de: 'WebRTC-Erfassung',
          ja: 'WebRTC キャプチャ',
        ),
        subtitle: tr(
          zh: '注入 RTCPeerConnection hook，抓 SDP / ICE / Track 事件',
          zhHant: '注入 RTCPeerConnection hook，抓 SDP / ICE / Track 事件',
          en: 'Hook RTCPeerConnection to capture SDP / ICE / Track events',
          fr: 'Hook RTCPeerConnection pour capturer SDP / ICE / Track',
          de: 'Hookt RTCPeerConnection für SDP-, ICE- und Track-Events',
          ja: 'RTCPeerConnection hook を注入し SDP / ICE / Track イベントを取得します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await _toggleWebRtcCapture(context, controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.code_off_rounded,
        title: tr(
          zh: 'JS 反混淆（webcrack）',
          zhHant: 'JS 反混淆（webcrack）',
          en: 'JS deobfuscate (webcrack)',
          fr: 'Désobfuscation JS (webcrack)',
          de: 'JS deobfuskieren (webcrack)',
          ja: 'JS 難読化解除（webcrack）',
        ),
        subtitle: tr(
          zh: '用 npx webcrack 把粘贴的 JS 还原成可读形式（需 Node.js）',
          zhHant: '用 npx webcrack 將貼上的 JS 還原成可讀形式（需 Node.js）',
          en: 'Run npx webcrack on pasted JS (Node.js required)',
          fr: 'Exécute npx webcrack sur le JS collé (Node.js requis)',
          de: 'Fuhrt npx webcrack auf eingefugtem JS aus (Node.js erforderlich)',
          ja: '貼り付けた JS を npx webcrack で読みやすくします（Node.js 必須）',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await _showWebcrackDialog(context);
        },
      ),
      _AdvancedEntry(
        icon: Icons.fingerprint_rounded,
        title: tr(
          zh: '签名字段变量定位器',
          zhHant: '簽名欄位變數定位器',
          en: 'Signature Field Locator',
          fr: 'Localisateur de champs de signature',
          de: 'Signaturfeld-Finder',
          ja: '署名フィールド変数ロケーター',
        ),
        subtitle: tr(
          zh: '同 endpoint 多次抓包后自动识别动态字段（sign / ts / nonce）',
          zhHant: '同 endpoint 多次抓包後自動識別動態欄位（sign / ts / nonce）',
          en: 'Identify dynamic fields (sign / ts / nonce) across repeated captures',
          fr: 'Détecte les champs dynamiques sign / ts / nonce sur captures répétées',
          de: 'Erkennt dynamische Felder wie sign / ts / nonce in wiederholten Captures',
          ja: '同じ endpoint の複数キャプチャから sign / ts / nonce などの動的フィールドを検出します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseSignatureDiffDialog(
            context,
            controller: controller,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.notifications_active_rounded,
        title: tr(
          zh: '报文条件断点',
          zhHant: '報文條件斷點',
          en: 'Request Breakpoints',
          fr: 'Breakpoints de requête',
          de: 'Request-Breakpoints',
          ja: 'リクエスト条件ブレークポイント',
        ),
        subtitle: tr(
          zh: 'URL/Body 子串命中 → 记录命中事件 + 可选触发 JS 表达式',
          zhHant: 'URL/Body 子字串命中 → 記錄命中事件 + 可選觸發 JS 表達式',
          en: 'URL/body substring match → log hits + optional JS eval',
          fr: 'Match URL/body → journalise et peut evaluer du JS',
          de: 'URL-/Body-Treffer → protokollieren und optional JS auswerten',
          ja: 'URL/body 部分一致でヒット記録と任意の JS 評価を実行します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseRequestBreakpointsDialog(
            context,
            controller: controller,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.switch_account_rounded,
        title: tr(
          zh: '多账号会话快照',
          zhHant: '多帳號會話快照',
          en: 'Account Snapshots',
          fr: 'Instantanés de comptes',
          de: 'Account-Snapshots',
          ja: '複数アカウントスナップショット',
        ),
        subtitle: tr(
          zh: '保存 cookies + storage → 一键在不同账号间切换',
          zhHant: '儲存 cookies + storage → 一鍵在不同帳號間切換',
          en: 'Save cookies + storage → one-click switch between accounts',
          fr: 'Sauve cookies + storage pour changer de compte en un clic',
          de: 'Speichert Cookies + Storage für Account-Wechsel per Klick',
          ja: 'cookies + storage を保存し、アカウントをワンクリックで切り替えます',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseAccountSnapshotsDialog(
            context,
            controller: controller,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.bar_chart_rounded,
        title: tr(
          zh: '代码覆盖率面板',
          zhHant: '程式碼覆蓋率面板',
          en: 'JS Coverage',
          fr: 'Couverture JS',
          de: 'JS-Abdeckung',
          ja: 'JS カバレッジ',
        ),
        subtitle: tr(
          zh: 'Start → 操作页面 → Take 查看哪些脚本被执行',
          zhHant: 'Start → 操作頁面 → Take 查看哪些腳本被執行',
          en: 'Start → use the page → Take to see which scripts ran',
          fr: 'Start → utilisez la page → Take pour voir les scripts exécutés',
          de: 'Start → Seite nutzen → Take zeigt ausgefuhrte Skripte',
          ja: 'Start → ページ操作 → Take で実行されたスクリプトを確認します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCoverageDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.ios_share_rounded,
        title: tr(
          zh: 'API 集合导出',
          zhHant: 'API 集合匯出',
          en: 'Export Collection',
          fr: 'Exporter la collection',
          de: 'Collection exportieren',
          ja: 'API コレクションをエクスポート',
        ),
        subtitle: tr(
          zh: 'Postman / Insomnia / Bruno / cURL / HAR 一键复制',
          zhHant: 'Postman / Insomnia / Bruno / cURL / HAR 一鍵複製',
          en: 'Postman / Insomnia / Bruno / cURL / HAR — copy to clipboard',
          fr: 'Copie Postman / Insomnia / Bruno / cURL / HAR',
          de: 'Kopiert Postman / Insomnia / Bruno / cURL / HAR',
          ja: 'Postman / Insomnia / Bruno / cURL / HAR をワンクリックコピー',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCollectionExportDialog(
            context,
            controller: controller,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.wifi_tethering_rounded,
        title: tr(
          zh: 'WebSocket 主动注入',
          zhHant: 'WebSocket 主動注入',
          en: 'WebSocket Inject',
          fr: 'Injection WebSocket',
          de: 'WebSocket-Injektion',
          ja: 'WebSocket 注入',
        ),
        subtitle: tr(
          zh: '代理 window.WebSocket → 选中连接 → 注入任意文本帧',
          zhHant: '代理 window.WebSocket → 選中連線 → 注入任意文字影格',
          en: 'Proxy window.WebSocket → pick a socket → inject any text frame',
          fr: 'Proxy window.WebSocket → choisir une connexion → injecter du texte',
          de: 'Proxy für window.WebSocket → Socket wählen → Text-Frame injizieren',
          ja: 'window.WebSocket をプロキシし、接続を選んで任意のテキストフレームを注入します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseWsInjectDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.alt_route_rounded,
        title: tr(
          zh: '本地 Mock 拦截',
          zhHant: '本地 Mock 攔截',
          en: 'Local Mock',
          fr: 'Mock local',
          de: 'Lokaler Mock',
          ja: 'ローカル Mock',
        ),
        subtitle: tr(
          zh: 'URL 通配命中 → 自定义 status/headers/body 直接返回',
          zhHant: 'URL 通配命中 → 自訂 status/headers/body 直接返回',
          en: 'URL match → return canned status/headers/body',
          fr: 'Match URL → renvoie status/headers/body définis',
          de: 'URL-Treffer → gibt vordefinierte status/headers/body zurück',
          ja: 'URL 一致でカスタム status/headers/body を直接返します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseMockRulesDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.visibility_rounded,
        title: tr(
          zh: '变量监视器',
          zhHant: '變數監視器',
          en: 'Watch Expressions',
          fr: 'Expressions surveillées',
          de: 'Watch-Ausdrücke',
          ja: '監視式',
        ),
        subtitle: tr(
          zh: '定时 Runtime.evaluate 任意 JS 表达式，记录历史采样',
          zhHant: '定時 Runtime.evaluate 任意 JS 表達式，記錄歷史採樣',
          en: 'Periodic Runtime.evaluate on JS expressions, history tracked',
          fr: 'Runtime.evaluate périodique sur expressions JS avec historique',
          de: 'Periodisches Runtime.evaluate für JS-Ausdrücke mit Historie',
          ja: '任意の JS 式を定期的に Runtime.evaluate し、履歴を記録します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseWatchDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.timeline_rounded,
        title: tr(
          zh: 'DOM Mutation 录制',
          zhHant: 'DOM Mutation 錄製',
          en: 'DOM Mutation Recorder',
          fr: 'Enregistreur DOM Mutation',
          de: 'DOM-Mutation-Recorder',
          ja: 'DOM Mutation レコーダー',
        ),
        subtitle: tr(
          zh: '注入 MutationObserver → attributes/characterData/childList 时间线',
          zhHant:
              '注入 MutationObserver → attributes/characterData/childList 時間線',
          en: 'Inject MutationObserver → timeline of all DOM changes',
          fr: 'Injecte MutationObserver pour une timeline des changements DOM',
          de: 'Injiziert MutationObserver für eine DOM-Änderungs-Timeline',
          ja: 'MutationObserver を注入し DOM 変更のタイムラインを記録します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseDomMutationDialog(
            context,
            controller: controller,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.public_rounded,
        title: tr(
          zh: '地理 / 时区 / 语言覆盖',
          zhHant: '地理 / 時區 / 語言覆寫',
          en: 'Geo / TZ / Locale Override',
          fr: 'Override geo / TZ / locale',
          de: 'Geo-/TZ-/Locale-Überschreibung',
          ja: '位置 / TZ / Locale 上書き',
        ),
        subtitle: tr(
          zh: '一键伪装当前 target 的 GPS / timezone / navigator.language',
          zhHant: '一鍵偽裝目前 target 的 GPS / timezone / navigator.language',
          en: 'Spoof current target GPS / timezone / navigator.language',
          fr: 'Simule GPS, timezone et navigator.language de la cible',
          de: 'Spooft GPS, timezone und navigator.language des Targets',
          ja: '現在の target の GPS / timezone / navigator.language を偽装します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseGeoOverrideDialog(
            context,
            controller: controller,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.fingerprint_rounded,
        title: tr(
          zh: 'WebAuthn 虚拟认证器',
          zhHant: 'WebAuthn 虛擬驗證器',
          en: 'WebAuthn Virtual Authenticator',
          fr: 'Authentificateur virtuel WebAuthn',
          de: 'Virtueller WebAuthn-Authenticator',
          ja: 'WebAuthn 仮想認証器',
        ),
        subtitle: tr(
          zh: '注入虚拟 FIDO2 设备，无物理密钥完成 navigator.credentials 流程',
          zhHant: '注入虛擬 FIDO2 裝置，無物理金鑰完成 navigator.credentials 流程',
          en: 'Inject virtual FIDO2 device, complete navigator.credentials without hardware',
          fr: 'Injecte un FIDO2 virtuel pour finir navigator.credentials sans clé physique',
          de: 'Injiziert virtuelles FIDO2-Gerät für navigator.credentials ohne Hardware',
          ja: '仮想 FIDO2 デバイスを注入し、物理キーなしで navigator.credentials を完了します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseWebAuthnDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.vpn_key_rounded,
        title: tr(
          zh: 'JWT 自动续期',
          zhHant: 'JWT 自動續期',
          en: 'JWT Auto Refresh',
          fr: 'Rafraîchissement auto JWT',
          de: 'JWT Auto-Refresh',
          ja: 'JWT 自動更新',
        ),
        subtitle: tr(
          zh: '扫描 cookies/localStorage/sessionStorage 中的 JWT，临近过期自动跑刷新脚本',
          zhHant: '掃描 cookies/localStorage/sessionStorage 中的 JWT，臨近過期自動跑刷新腳本',
          en: 'Scan JWT in cookies/storage, run refresh JS near expiry',
          fr: 'Scanne les JWT dans cookies/storage et lance le JS avant expiration',
          de: 'Scannt JWT in Cookies/Storage und fuhrt Refresh-JS vor Ablauf aus',
          ja: 'cookies/storage 内の JWT をスキャンし、期限前に更新 JS を実行します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseJwtRefreshDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.lock_open_rounded,
        title: tr(
          zh: 'AI 加密参数还原',
          zhHant: 'AI 加密參數還原',
          en: 'AI Crypto Param Recover',
          fr: 'Récupération IA des paramètres crypto',
          de: 'AI-Krypto-Parameter rekonstruieren',
          ja: 'AI 暗号パラメータ復元',
        ),
        subtitle: tr(
          zh: '同 endpoint 多次 diff + JS 全文搜索命中，复制成 AI 可吃的提示词',
          zhHant: '同 endpoint 多次 diff + JS 全文搜尋命中，複製成 AI 可用提示詞',
          en: 'Diff repeated endpoint hits + search JS, copy as AI-ready prompt',
          fr: 'Diffs répétés + recherche JS, puis copie un prompt prêt pour IA',
          de: 'Diff wiederholter Endpoint-Hits + JS-Suche als AI-fertiger Prompt',
          ja: '同 endpoint の diff と JS 全文検索から AI 用プロンプトを作成します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseAiCryptoDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.swap_horiz_rounded,
        title: tr(
          zh: 'postMessage 追踪',
          zhHant: 'postMessage 追蹤',
          en: 'postMessage Trace',
          fr: 'Trace postMessage',
          de: 'postMessage-Trace',
          ja: 'postMessage トレース',
        ),
        subtitle: tr(
          zh: '注入 hook 收录跨窗口消息，含发送方向与 iframe',
          zhHant: '注入 hook 收錄跨視窗訊息，含發送方向與 iframe',
          en: 'Inject hook to capture cross-window messages incl. iframe',
          fr: 'Capture les messages inter-fenêtres avec direction et iframe',
          de: 'Erfasst fensterubergreifende Messages inklusive Richtung und iframe',
          ja: 'hook を注入し、方向と iframe を含むウィンドウ間メッセージを取得します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReversePostMessageDialog(
            context,
            controller: controller,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.timeline_rounded,
        title: tr(
          zh: '请求瀑布图',
          zhHant: '請求瀑布圖',
          en: 'Network Waterfall',
          fr: 'Cascade réseau',
          de: 'Netzwerk-Wasserfall',
          ja: 'ネットワークウォーターフォール',
        ),
        subtitle: tr(
          zh: 'TTFB / 下载两段可视化，按耗时/大小/时间排序',
          zhHant: 'TTFB / 下載兩段可視化，按耗時/大小/時間排序',
          en: 'Visualize TTFB / download segments, sort by time/size/duration',
          fr: 'Visualise TTFB / téléchargement et trie par durée/taille/temps',
          de: 'Visualisiert TTFB/Download und sortiert nach Dauer/Große/Zeit',
          ja: 'TTFB / ダウンロード区間を可視化し、時間/サイズ/期間で並べ替えます',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseWaterfallDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.account_tree_rounded,
        title: tr(
          zh: 'JS 调用图',
          zhHant: 'JS 呼叫圖',
          en: 'JS Callgraph',
          fr: 'Graphe d’appels JS',
          de: 'JS-Aufrufgraph',
          ja: 'JS コールグラフ',
        ),
        subtitle: tr(
          zh: '启发式正则解析所有 frame 脚本，构造 caller→callees 邻接表',
          zhHant: '啟發式正則解析所有 frame 腳本，構造 caller→callees 鄰接表',
          en: 'Heuristic regex parsing of frame scripts; build caller→callees graph',
          fr: 'Parse les scripts de frames et construit le graphe caller→callees',
          de: 'Parst Frame-Skripte heuristisch und baut caller→callees-Graph',
          ja: 'frame スクリプトをヒューリスティック解析し caller→callees グラフを構築します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCallgraphDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.network_check_rounded,
        title: tr(
          zh: '网络限速模拟',
          zhHant: '網路限速模擬',
          en: 'Network Throttle',
          fr: 'Limitation réseau',
          de: 'Netzwerkdrosselung',
          ja: 'ネットワーク制限',
        ),
        subtitle: tr(
          zh: 'Network.emulateNetworkConditions 预设/自定义 kbps + 延迟 + 离线 + 禁用缓存',
          zhHant:
              'Network.emulateNetworkConditions 預設/自訂 kbps + 延遲 + 離線 + 停用快取',
          en: 'Network.emulateNetworkConditions presets/custom kbps + latency + offline + cache off',
          fr: 'Network.emulateNetworkConditions presets/personnalisé kbps + latence + hors ligne + cache off',
          de: 'Network.emulateNetworkConditions Presets/benutzerdefiniert kbps + Latenz + offline + Cache aus',
          ja: 'Network.emulateNetworkConditions プリセット/カスタム kbps + レイテンシ + オフライン + キャッシュ無効',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseThrottleDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.save_as_rounded,
        title: tr(
          zh: 'HAR 全量持久化',
          zhHant: 'HAR 全量持久化',
          en: 'HAR Persistence',
          fr: 'Persistance HAR',
          de: 'HAR-Persistenz',
          ja: 'HAR 永続化',
        ),
        subtitle: tr(
          zh: '立即落盘 / 反向加载 / 周期自动轮转',
          zhHant: '立即落盤 / 反向載入 / 週期自動輪轉',
          en: 'Save now / Load back / Periodic rotation',
          fr: 'Sauvegarder / recharger / rotation périodique',
          de: 'Sofort speichern / zuruckladen / periodische Rotation',
          ja: '即時保存 / 読み戻し / 定期ローテーション',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseHarPersistenceDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.cookie_rounded,
        title: tr(
          zh: 'Cookie 编辑器',
          zhHant: 'Cookie 編輯器',
          en: 'Cookie Editor',
          fr: 'Éditeur de cookies',
          de: 'Cookie-Editor',
          ja: 'Cookie エディタ',
        ),
        subtitle: tr(
          zh: 'Network.getCookies / setCookie / deleteCookies 常用字段编辑',
          zhHant: 'Network.getCookies / setCookie / deleteCookies 常用欄位編輯',
          en: 'Edit common cookie fields via Network.getCookies / setCookie / deleteCookies',
          fr: 'Modifier les champs courants via Network.getCookies / setCookie / deleteCookies',
          de: 'Gängige Cookie-Felder über Network.getCookies / setCookie / deleteCookies bearbeiten',
          ja: 'Network.getCookies / setCookie / deleteCookies で一般的な Cookie フィールドを編集',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCookieEditorDialog(
            context,
            controller: controller,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.miscellaneous_services_rounded,
        title: tr(
          zh: 'Service Worker 调试',
          zhHant: 'Service Worker 除錯',
          en: 'Service Worker Debug',
          fr: 'Debug Service Worker',
          de: 'Service-Worker-Debug',
          ja: 'Service Worker デバッグ',
        ),
        subtitle: tr(
          zh: '启停 / 强制更新 / 注销 / 触发 sync / 送 push',
          zhHant: '啟停 / 強制更新 / 註銷 / 觸發 sync / 送 push',
          en: 'Start/stop, force-update, unregister, dispatch sync, push',
          fr: 'Démarrer/arrêter, mise à jour forcée, unregister, sync, push',
          de: 'Start/Stop, Force-Update, unregister, sync und push auslosen',
          ja: '起動/停止、強制更新、unregister、sync、push を実行します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseSwDebugDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.timeline_rounded,
        title: tr(
          zh: 'Performance Trace',
          zhHant: 'Performance Trace',
          en: 'Performance Trace',
          fr: 'Trace de performance',
          de: 'Performance-Trace',
          ja: 'Performance Trace',
        ),
        subtitle: tr(
          zh: '录制 Tracing → chrome-trace JSON（Perfetto 可加载）',
          zhHant: '錄製 Tracing → chrome-trace JSON（Perfetto 可載入）',
          en: 'Record Tracing → chrome-trace JSON',
          fr: 'Enregistre Tracing vers JSON chrome-trace',
          de: 'Zeichnet Tracing als chrome-trace-JSON auf',
          ja: 'Tracing を記録して chrome-trace JSON を出力します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReversePerfTraceDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.memory_rounded,
        title: tr(
          zh: 'Heap Snapshot',
          zhHant: 'Heap Snapshot',
          en: 'Heap Snapshot',
          fr: 'Snapshot du tas',
          de: 'Heap-Snapshot',
          ja: 'Heap Snapshot',
        ),
        subtitle: tr(
          zh: 'HeapProfiler.takeHeapSnapshot → .heapsnapshot（DevTools Memory 可加载）',
          zhHant:
              'HeapProfiler.takeHeapSnapshot → .heapsnapshot（DevTools Memory 可載入）',
          en: 'HeapProfiler.takeHeapSnapshot → .heapsnapshot',
          fr: 'HeapProfiler.takeHeapSnapshot → .heapsnapshot',
          de: 'HeapProfiler.takeHeapSnapshot → .heapsnapshot',
          ja: 'HeapProfiler.takeHeapSnapshot → .heapsnapshot',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseHeapSnapshotDialog(
            context,
            controller: controller,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.terminal_rounded,
        title: tr(
          zh: 'Console REPL',
          zhHant: 'Console REPL',
          en: 'Console REPL',
          fr: 'Console REPL',
          de: 'Console REPL',
          ja: 'Console REPL',
        ),
        subtitle: tr(
          zh: 'Runtime.evaluate · 多行 JS · 历史记录 + 快捷键',
          zhHant: 'Runtime.evaluate · 多行 JS · 歷史記錄 + 快捷鍵',
          en: 'Runtime.evaluate · multi-line JS · history + shortcuts',
          fr: 'Runtime.evaluate · JS multi-ligne · historique + raccourcis',
          de: 'Runtime.evaluate · Mehrzeilen-JS · Verlauf + Shortcuts',
          ja: 'Runtime.evaluate · 複数行 JS · 履歴 + ショートカット',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseReplDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.account_tree_rounded,
        title: tr(
          zh: 'Frame 树查看器',
          zhHant: 'Frame 樹查看器',
          en: 'Frame Tree',
          fr: 'Arbre des frames',
          de: 'Frame-Baum',
          ja: 'Frame ツリー',
        ),
        subtitle: tr(
          zh: 'Page.getFrameTree · 主框架 + 嵌套 iframe 递归',
          zhHant: 'Page.getFrameTree · 主框架 + 巢狀 iframe 遞迴',
          en: 'Page.getFrameTree · main + nested iframes',
          fr: 'Page.getFrameTree · frame principal + iframes imbriqués',
          de: 'Page.getFrameTree · Hauptframe + verschachtelte iframes',
          ja: 'Page.getFrameTree · メイン + ネスト iframe を再帰表示',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseFrameTreeDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.style_rounded,
        title: tr(
          zh: 'CSS 规则使用率',
          zhHant: 'CSS 規則使用率',
          en: 'CSS Rule Coverage',
          fr: 'Couverture des règles CSS',
          de: 'CSS-Regelabdeckung',
          ja: 'CSS ルールカバレッジ',
        ),
        subtitle: tr(
          zh: 'CSS.startRuleUsageTracking · 找出未命中的死代码',
          zhHant: 'CSS.startRuleUsageTracking · 找出未命中的死碼',
          en: 'CSS.startRuleUsageTracking · find dead rules',
          fr: 'CSS.startRuleUsageTracking · trouve les règles mortes',
          de: 'CSS.startRuleUsageTracking · findet ungenutzte Regeln',
          ja: 'CSS.startRuleUsageTracking · 未使用ルールを検出します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCssCoverageDialog(
            context,
            controller: controller,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.animation_rounded,
        title: tr(
          zh: 'Animations 调试',
          zhHant: 'Animations 除錯',
          en: 'Animations',
          fr: 'Animations',
          de: 'Animationen',
          ja: 'Animations',
        ),
        subtitle: tr(
          zh: '全局倍速 + 暂停 / 继续 / 取消 + 活跃动画快照',
          zhHant: '全域倍速 + 暫停 / 繼續 / 取消 + 活躍動畫快照',
          en: 'global rate · pause/resume/cancel · live snapshot',
          fr: 'vitesse globale · pause/reprise/annulation · instantané',
          de: 'globale Rate · Pause/Fortsetzen/Abbrechen · Live-Snapshot',
          ja: '全体速度 · 一時停止/再開/取消 · アクティブアニメーションのスナップショット',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseAnimationsDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.layers_rounded,
        title: tr(
          zh: 'Rendering 调试',
          zhHant: 'Rendering 除錯',
          en: 'Rendering',
          fr: 'Rendu',
          de: 'Rendering',
          ja: 'Rendering',
        ),
        subtitle: tr(
          zh: 'Paint / Layout shift / Layers / FPS / 媒体仿真 / CPU 节流',
          zhHant: 'Paint / Layout shift / Layers / FPS / 媒體仿真 / CPU 節流',
          en: 'Paint · Layout shift · Layers · FPS · media · CPU throttle',
          fr: 'Paint · Layout shift · Layers · FPS · media · CPU throttle',
          de: 'Paint · Layout shift · Layers · FPS · Medien · CPU-Drossel',
          ja: 'Paint · Layout shift · Layers · FPS · media · CPU throttle',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseRenderingDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.report_problem_rounded,
        title: tr(
          zh: 'Issues 面板',
          zhHant: 'Issues 面板',
          en: 'Issues',
          fr: 'Issues',
          de: 'Issues',
          ja: 'Issues',
        ),
        subtitle: tr(
          zh: 'Audits.issueAdded · 安全 / Cookie / Mixed Content / Deprecation',
          zhHant:
              'Audits.issueAdded · 安全 / Cookie / Mixed Content / Deprecation',
          en: 'Audits.issueAdded · security / cookie / deprecation',
          fr: 'Audits.issueAdded · sécurité / cookie / deprecation',
          de: 'Audits.issueAdded · Sicherheit / Cookie / Deprecation',
          ja: 'Audits.issueAdded · security / cookie / deprecation',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseIssuesDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.speed_rounded,
        title: tr(
          zh: 'Web Vitals 报告',
          zhHant: 'Web Vitals 報告',
          en: 'Web Vitals',
          fr: 'Web Vitals',
          de: 'Web Vitals',
          ja: 'Web Vitals',
        ),
        subtitle: tr(
          zh: 'PerformanceObserver · LCP / CLS / INP / FCP / TTFB 实时采集',
          zhHant: 'PerformanceObserver · LCP / CLS / INP / FCP / TTFB 即時採集',
          en: 'PerformanceObserver · LCP / CLS / INP / FCP / TTFB',
          fr: 'PerformanceObserver · LCP / CLS / INP / FCP / TTFB',
          de: 'PerformanceObserver · LCP / CLS / INP / FCP / TTFB',
          ja: 'PerformanceObserver · LCP / CLS / INP / FCP / TTFB',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseVitalsDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.replay_circle_filled_rounded,
        title: tr(
          zh: '网络请求重放器',
          zhHant: '網路請求重放器',
          en: 'Network Replayer',
          fr: 'Relecteur réseau',
          de: 'Netzwerk-Replayer',
          ja: 'ネットワークリプレイヤー',
        ),
        subtitle: tr(
          zh: '多选请求 · 顺序重发 · 对比状态',
          zhHant: '多選請求 · 順序重發 · 對比狀態',
          en: 'multi-select · sequential replay · status diff',
          fr: 'sélection multiple · replay séquentiel · diff de statut',
          de: 'Mehrfachauswahl · sequenzielles Replay · Statusvergleich',
          ja: '複数選択 · 順次再送 · ステータス差分',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseReplayDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.ads_click_rounded,
        title: tr(
          zh: '输入事件模拟',
          zhHant: '輸入事件模擬',
          en: 'Input Simulator',
          fr: 'Simulateur d’entrée',
          de: 'Eingabe-Simulator',
          ja: '入力イベントシミュレーター',
        ),
        subtitle: tr(
          zh: 'dispatchMouseEvent / dispatchKeyEvent / insertText',
          zhHant: 'dispatchMouseEvent / dispatchKeyEvent / insertText',
          en: 'dispatchMouseEvent / dispatchKeyEvent / insertText',
          fr: 'dispatchMouseEvent / dispatchKeyEvent / insertText',
          de: 'dispatchMouseEvent / dispatchKeyEvent / insertText',
          ja: 'dispatchMouseEvent / dispatchKeyEvent / insertText',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseInputSimDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.devices_other_rounded,
        title: tr(
          zh: '设备模拟',
          zhHant: '裝置模擬',
          en: 'Device Emulation',
          fr: 'Émulation d’appareil',
          de: 'Gerateemulation',
          ja: 'デバイスエミュレーション',
        ),
        subtitle: tr(
          zh: '尺寸 / DPR / mobile flag / UA 覆写',
          zhHant: '尺寸 / DPR / mobile flag / UA 覆寫',
          en: 'metrics / DPR / mobile / UA override',
          fr: 'metrics / DPR / mobile / override UA',
          de: 'Metriken / DPR / mobile / UA-Überschreibung',
          ja: 'metrics / DPR / mobile / UA override',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseDeviceEmulationDialog(
            context,
            controller: controller,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.speed_rounded,
        title: tr(
          zh: 'CPU 限速',
          zhHant: 'CPU 限速',
          en: 'CPU Throttling',
          fr: 'Limitation CPU',
          de: 'CPU-Drosselung',
          ja: 'CPU スロットリング',
        ),
        subtitle: tr(
          zh: 'Emulation.setCPUThrottlingRate · 1×–20×',
          zhHant: 'Emulation.setCPUThrottlingRate · 1×–20×',
          en: 'Emulation.setCPUThrottlingRate · 1×–20×',
          fr: 'Emulation.setCPUThrottlingRate · 1×–20×',
          de: 'Emulation.setCPUThrottlingRate · 1×–20×',
          ja: 'Emulation.setCPUThrottlingRate · 1×–20×',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCpuThrottleDialog(
            context,
            controller: controller,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.travel_explore_rounded,
        title: tr(
          zh: 'DOM 选择器搜索',
          zhHant: 'DOM 選擇器搜尋',
          en: 'DOM Selector Search',
          fr: 'Recherche de sélecteur DOM',
          de: 'DOM-Selektorsuche',
          ja: 'DOM セレクター検索',
        ),
        subtitle: tr(
          zh: 'DOM.performSearch · CSS / text / XPath · 高亮',
          zhHant: 'DOM.performSearch · CSS / text / XPath · 高亮',
          en: 'DOM.performSearch · CSS / text / XPath · highlight',
          fr: 'DOM.performSearch · CSS / texte / XPath · surbrillance',
          de: 'DOM.performSearch · CSS / Text / XPath · Highlight',
          ja: 'DOM.performSearch · CSS / text / XPath · ハイライト',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseDomSearchDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.alt_route_rounded,
        title: tr(
          zh: 'SourceMap 反解析',
          zhHant: 'SourceMap 反解析',
          en: 'SourceMap Resolver',
          fr: 'Résolveur SourceMap',
          de: 'SourceMap-Resolver',
          ja: 'SourceMap リゾルバー',
        ),
        subtitle: tr(
          zh: 'min file:line:col → 原始 source:line:col',
          zhHant: 'min file:line:col → 原始 source:line:col',
          en: 'min file:line:col → original source:line:col',
          fr: 'min file:line:col → source original:line:col',
          de: 'min file:line:col → originale source:line:col',
          ja: 'min file:line:col → original source:line:col',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseSourceMapDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.swap_horiz_rounded,
        title: tr(
          zh: 'WebSocket 帧',
          zhHant: 'WebSocket 影格',
          en: 'WebSocket Frames',
          fr: 'Trames WebSocket',
          de: 'WebSocket-Frames',
          ja: 'WebSocket フレーム',
        ),
        subtitle: tr(
          zh: '查看帧 · 重放 sent 帧到新连接',
          zhHant: '查看影格 · 將 sent 影格重放到新連線',
          en: 'inspect frames · replay sent frames',
          fr: 'inspecter les trames · rejouer les trames envoyées',
          de: 'Frames prüfen · gesendete Frames wiederholen',
          ja: 'フレーム確認 · sent フレームをリプレイ',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseWebSocketDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.shield_moon_rounded,
        title: tr(
          zh: 'CORS Preflight 测试',
          zhHant: 'CORS Preflight 測試',
          en: 'CORS Preflight',
          fr: 'Preflight CORS',
          de: 'CORS-Preflight',
          ja: 'CORS Preflight',
        ),
        subtitle: tr(
          zh: 'OPTIONS · Allow-Origin / Methods / Headers 诊断',
          zhHant: 'OPTIONS · Allow-Origin / Methods / Headers 診斷',
          en: 'OPTIONS · diagnose Allow-Origin / Methods / Headers',
          fr: 'OPTIONS · diagnostic Allow-Origin / Methods / Headers',
          de: 'OPTIONS · Diagnose für Allow-Origin / Methods / Headers',
          ja: 'OPTIONS · Allow-Origin / Methods / Headers 診断',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCorsPreflightDialog(
            context,
            controller: controller,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.storage_rounded,
        title: tr(
          zh: '存储管理器',
          zhHant: '儲存管理器',
          en: 'Storage Manager',
          fr: 'Gestionnaire de stockage',
          de: 'Storage-Manager',
          ja: 'ストレージマネージャー',
        ),
        subtitle: tr(
          zh: 'Cookies / Local / Session / IndexedDB 浏览与编辑',
          zhHant: 'Cookies / Local / Session / IndexedDB 瀏覽與編輯',
          en: 'browse / edit Cookies / Local / Session / IndexedDB',
          fr: 'parcourir / éditer Cookies / Local / Session / IndexedDB',
          de: 'Cookies / Local / Session / IndexedDB ansehen und bearbeiten',
          ja: 'Cookies / Local / Session / IndexedDB の閲覧と編集',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseStorageDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.terminal_rounded,
        title: tr(
          zh: 'CDP Raw 控制台',
          zhHant: 'CDP Raw 主控台',
          en: 'CDP Raw Console',
          fr: 'Console CDP Raw',
          de: 'CDP-Raw-Konsole',
          ja: 'CDP Raw コンソール',
        ),
        subtitle: tr(
          zh: '带历史 · 快捷键 · 任意 CDP method/params',
          zhHant: '帶歷史 · 快捷鍵 · 任意 CDP method/params',
          en: 'history · shortcuts · arbitrary CDP method/params',
          fr: 'historique · raccourcis · CDP method/params arbitraires',
          de: 'Verlauf · Shortcuts · beliebige CDP method/params',
          ja: '履歴 · ショートカット · 任意の CDP method/params',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCdpConsoleDialog(context, controller: controller);
        },
      ),
      _AdvancedEntry(
        icon: Icons.bug_report_rounded,
        title: tr(
          zh: 'Console 错误聚类',
          zhHant: 'Console 錯誤聚類',
          en: 'Console Clusters',
          fr: 'Clusters console',
          de: 'Konsolen-Cluster',
          ja: 'Console クラスター',
        ),
        subtitle: tr(
          zh: '按 level + 归一化首行去重 · 展开原始条目',
          zhHant: '按 level + 正規化首行去重 · 展開原始條目',
          en: 'dedupe by level + normalized first line',
          fr: 'dédoublonne par level + première ligne normalisée',
          de: 'Dedupliziert nach Level + normalisierter erster Zeile',
          ja: 'level + 正規化した先頭行で重複排除します',
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseConsoleClusterDialog(
            context,
            controller: controller,
          );
        },
      ),
    ];
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthCompact,
      maxHeight: kOpenHandDialogHeightStandard,
      insetPadding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.tune_rounded,
            title: tr(
              zh: '高级工具',
              zhHant: '進階工具',
              en: 'Advanced tools',
              fr: 'Outils avances',
              de: 'Erweiterte Tools',
              ja: '高度なツール',
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: entries.length,
              separatorBuilder: (_, _) => kOpenHandGap4,
              itemBuilder: (_, idx) {
                final e = entries[idx];
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: e.onTap,
                    borderRadius: kOpenHandBorderRadius10,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(e.icon, size: 20, color: cs.primary),
                          kOpenHandHGap14,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.title,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                kOpenHandGap2,
                                Text(
                                  e.subtitle,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedEntry {
  _AdvancedEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

Future<void> _showExtraHeadersDialog(
  BuildContext context,
  WebReverseSessionController ctrl,
) async {
  final ctrlText = TextEditingController(
    text: _formatHeaderLines(ctrl.extraHeaders),
  );
  try {
    final ok = await showOpenHandFormDialog<bool>(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '持久注入 Headers',
        zhHant: '持久注入 Headers',
        en: 'Persistent Headers',
        fr: 'Headers persistants',
        de: 'Persistente Header',
        ja: '永続 Headers 注入',
      ),
      submitLabel: openHandSaveLabel(context),
      cancelLabel: openHandCancelLabel(context),
      maxWidth: 520,
      onSubmit: (_) => true,
      contentBuilder: (dialogContext) => SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              openHandLocalizedText(
                context,
                zh: '每行一个 Key: Value；保存后所有请求自动附带，留空则清空。',
                zhHant: '每行一個 Key: Value；儲存後所有請求自動附帶，留空則清空。',
                en: 'One header per line in `Key: Value` form; empty to clear.',
                fr: 'Un header par ligne au format `Key: Value`; vide pour effacer.',
                de: 'Ein Header pro Zeile im Format `Key: Value`; leer lassen zum Löschen.',
                ja: '`Key: Value` 形式で 1 行 1 Header。空にするとクリアします。',
              ),
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            kOpenHandGap8,
            TextField(
              controller: ctrlText,
              maxLength: WebReverseSessionController.maxRuleHeadersChars,
              maxLines: 10,
              minLines: 5,
              style: const TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 12.5,
              ),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final headers = _parseHeaderLines(ctrlText.text);
    final saved = await ctrl.setExtraHttpHeaders(headers);
    if (!context.mounted) return;
    if (saved) {
      final savedCount = ctrl.extraHeaders.length;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '已注入 $savedCount 个 Header',
          zhHant: '已注入 $savedCount 個 Header',
          en: 'Injected $savedCount headers',
          fr: '$savedCount headers injectés',
          de: '$savedCount Header injiziert',
          ja: '$savedCount 個の Header を注入しました',
        ),
      );
    } else {
      showOpenHandErrorSnack(
        context,
        webReverseSaveFailedMessage(context),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  } finally {
    ctrlText.dispose();
  }
}

Future<void> _showCdpPaletteDialog(
  BuildContext context,
  WebReverseSessionController ctrl,
) async {
  final method = TextEditingController();
  final params = TextEditingController(text: '{}');
  final result = ValueNotifier<String?>(null);
  final useSession = ValueNotifier<bool>(true);
  try {
    await webReverseToolDialogs.show<void>(
      context: context,
      builder: (dialogContext) => buildOpenHandAlertDialog(
        title: Text(
          openHandLocalizedText(
            dialogContext,
            zh: 'CDP 命令面板',
            zhHant: 'CDP 命令面板',
            en: 'CDP Command Palette',
            fr: 'Palette de commandes CDP',
            de: 'CDP-Befehlspalette',
            ja: 'CDP コマンドパレット',
          ),
        ),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: method,
                  decoration: const InputDecoration(
                    labelText: 'Method',
                    hintText: 'Network.getAllCookies / DOM.querySelector',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12.5,
                  ),
                ),
                kOpenHandGap8,
                TextField(
                  controller: params,
                  maxLines: 8,
                  minLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Params (JSON)',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12.5,
                  ),
                ),
                kOpenHandGap6,
                ValueListenableBuilder(
                  valueListenable: useSession,
                  builder: (_, v, _) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      openHandLocalizedText(
                        dialogContext,
                        zh: '在当前 Page 会话内执行（关掉则用 Browser 根 session）',
                        zhHant: '在目前 Page 會話內執行（關掉則用 Browser 根 session）',
                        en: 'Use current page session (off = browser root session)',
                        fr: 'Utiliser la session Page courante (désactivé = session racine Browser)',
                        de: 'Aktuelle Page-Session nutzen (aus = Browser-Root-Session)',
                        ja: '現在の Page セッションで実行（オフなら Browser root session）',
                      ),
                    ),
                    value: v,
                    onChanged: (n) => useSession.value = n,
                  ),
                ),
                kOpenHandGap6,
                ValueListenableBuilder(
                  valueListenable: result,
                  builder: (_, v, _) => v == null
                      ? const SizedBox.shrink()
                      : Container(
                          constraints: const BoxConstraints(maxHeight: 300),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              dialogContext,
                            ).colorScheme.surfaceContainerHigh,
                            borderRadius: kOpenHandBorderRadius8,
                            border: Border.all(
                              color: Theme.of(
                                dialogContext,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          padding: const EdgeInsets.all(10),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              v,
                              style: const TextStyle(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: openHandCloseLabel(dialogContext),
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () async {
              final m = method.text.trim();
              if (m.isEmpty) return;
              try {
                final r = await ctrl.sendRawCdp(
                  method: m,
                  paramsJson: params.text,
                  useSession: useSession.value,
                );
                if (!dialogContext.mounted) return;
                result.value = r == null ? '(null)' : prettyPrintJson(r);
              } catch (error, stack) {
                silentLog(
                  'web_reverse_dashboard_dialog',
                  '发送原始 CDP 命令',
                  error,
                  stack,
                );
                if (!dialogContext.mounted) return;
                result.value = openHandLocalizedText(
                  dialogContext,
                  zh: '执行失败：$error',
                  zhHant: '執行失敗：$error',
                  en: 'Run failed: $error',
                  fr: 'Échec de l’exécution : $error',
                  de: 'Ausführung fehlgeschlagen: $error',
                  ja: '実行に失敗しました: $error',
                );
              }
            },
            label: openHandLocalizedText(
              dialogContext,
              zh: '执行',
              zhHant: '執行',
              en: 'Run',
              fr: 'Exécuter',
              de: 'Ausführen',
              ja: '実行',
            ),
          ),
        ],
      ),
    );
  } finally {
    method.dispose();
    params.dispose();
    result.dispose();
    useSession.dispose();
  }
}

Future<void> _copyRecentRequestsForAi(
  BuildContext context,
  WebReverseSessionController ctrl,
) async {
  final entries = ctrl.networkRequests.reversed.take(10).toList();
  if (entries.isEmpty) {
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '当前无请求可分析',
        zhHant: '目前沒有請求可分析',
        en: 'No requests yet',
        fr: 'Aucune requête pour le moment',
        de: 'Noch keine Anfragen',
        ja: '分析できるリクエストがまだありません',
      ),
      duration: kOpenHandSnackBarBriefDuration,
    );
    return;
  }
  final buf = StringBuffer()
    ..writeln(
      openHandLocalizedText(
        context,
        zh: '请帮我分析这 ${entries.length} 条请求里哪些是关键加密参数（sign / token / encrypt 等），并指出可能的算法与种子。',
        zhHant:
            '請幫我分析這 ${entries.length} 筆請求裡哪些是關鍵加密參數（sign / token / encrypt 等），並指出可能的演算法與種子。',
        en: 'Please identify the encryption-relevant fields (sign / token / encrypt) in these ${entries.length} requests and guess the algorithm.',
        fr: 'Identifie les champs liés au chiffrement (sign / token / encrypt) dans ces ${entries.length} requêtes et estime l’algorithme.',
        de: 'Bitte identifiziere verschlusselungsrelevante Felder (sign / token / encrypt) in diesen ${entries.length} Anfragen und schatze den Algorithmus.',
        ja: 'この ${entries.length} 件のリクエストから暗号関連フィールド（sign / token / encrypt など）を特定し、可能なアルゴリズムを推測してください。',
      ),
    )
    ..writeln('---');
  for (final e in entries) {
    buf
      ..writeln('[${e.method}] ${e.url}')
      ..writeln('Status: ${e.statusCode ?? '-'}  Type: ${e.resourceType}');
    if (e.requestPostData != null && e.requestPostData!.isNotEmpty) {
      var body = e.requestPostData!;
      body = clipTextWithEllipsis(body, 1024);
      buf.writeln('Body: $body');
    }
    if (e.requestHeaders.isNotEmpty) {
      final keys = e.requestHeaders.keys
          .where(
            (k) =>
                k.toLowerCase().contains('sign') ||
                k.toLowerCase().contains('token') ||
                k.toLowerCase().contains('auth') ||
                k.toLowerCase().contains('x-'),
          )
          .toList();
      if (keys.isNotEmpty) {
        for (final k in keys) {
          buf.writeln('  $k: ${e.requestHeaders[k]}');
        }
      }
    }
    buf.writeln('---');
  }
  await copyWebReverseTextToClipboard(
    context: context,
    text: buf.toString(),
    successBase: openHandLocalizedText(
      context,
      zh: '请求摘要已复制，回到会话粘贴即可让 AI 分析',
      zhHant: '請求摘要已複製，回到會話貼上即可讓 AI 分析',
      en: 'Summary copied; paste in chat',
      fr: 'Résumé copié ; collez-le dans le chat',
      de: 'Zusammenfassung kopiert; im Chat einfugen',
      ja: '要約をコピーしました。チャットに貼り付けて分析できます',
    ),
    logTag: 'web_reverse_advanced_menu',
    logAction: '复制最近请求',
    successDuration: const Duration(seconds: 3),
  );
}

Future<void> _showDiffPicker(
  BuildContext context,
  WebReverseSessionController ctrl,
) async {
  final all = ctrl.networkRequests;
  if (all.length < 2) {
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '请求数不足，无法对比',
        zhHant: '請求數不足，無法對比',
        en: 'Need at least 2 requests',
        fr: 'Au moins 2 requêtes sont nécessaires',
        de: 'Mindestens 2 Anfragen erforderlich',
        ja: '比較には 2 件以上のリクエストが必要です',
      ),
      duration: kOpenHandSnackBarBriefDuration,
    );
    return;
  }
  CdpNetworkEntry? a;
  CdpNetworkEntry? b;
  await showOpenHandStatefulDialog<void>(
    context: context,
    builder: (dialogContext, setState) => buildOpenHandAlertDialog(
      title: Text(
        openHandLocalizedText(
          dialogContext,
          zh: '选择两个请求对比',
          zhHant: '選擇兩個請求對比',
          en: 'Pick two requests',
          fr: 'Choisir deux requêtes',
          de: 'Zwei Anfragen auswahlen',
          ja: '比較する 2 件のリクエストを選択',
        ),
      ),
      content: SizedBox(
        width: 640,
        height: 460,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: all.length,
                itemBuilder: (_, idx) {
                  final e = all[all.length - 1 - idx];
                  final selectedAs = identical(e, a)
                      ? 'A'
                      : (identical(e, b) ? 'B' : null);
                  return ListTile(
                    dense: true,
                    title: Text(
                      '${e.method} ${e.url}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: kOpenHandMonospaceFontFamily,
                        fontSize: 12,
                      ),
                    ),
                    subtitle: Text(
                      '${e.statusCode ?? '-'} · ${e.resourceType}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: selectedAs == null
                        ? null
                        : Text(
                            selectedAs,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                    onTap: () {
                      setState(() {
                        if (a == null) {
                          a = e;
                        } else if (b == null && !identical(e, a)) {
                          b = e;
                        } else {
                          a = e;
                          b = null;
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(dialogContext).pop(),
          label: openHandCancelLabel(dialogContext),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: (a == null || b == null)
              ? null
              : () {
                  Navigator.of(dialogContext).pop();
                  webReverseToolDialogs.show<void>(
                    context: context,
                    builder: (_) => _DiffViewerDialog(a: a!, b: b!),
                  );
                },
          label: openHandLocalizedText(
            dialogContext,
            zh: '对比',
            zhHant: '對比',
            en: 'Diff',
            fr: 'Comparer',
            de: 'Vergleichen',
            ja: '比較',
          ),
        ),
      ],
    ),
  );
}

class _DiffViewerDialog extends StatelessWidget {
  const _DiffViewerDialog({required this.a, required this.b});

  final CdpNetworkEntry a;
  final CdpNetworkEntry b;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget col(String label, CdpNetworkEntry e) => Expanded(
      child: Container(
        decoration: webReverseSurfaceCardDecoration(cs, radius: 8),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label: ${e.method} ${e.url}',
              style: const TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            kOpenHandGap6,
            Text('status=${e.statusCode ?? '-'} mime=${e.mimeType ?? '-'}'),
            const Divider(),
            Text(
              openHandLocalizedText(
                context,
                zh: '请求 Headers:',
                zhHant: '請求 Headers:',
                en: 'Request headers:',
                fr: 'Headers de requête :',
                de: 'Request-Header:',
                ja: 'リクエスト Headers:',
              ),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  e.requestHeaders.entries
                      .map((kv) => '${kv.key}: ${kv.value}')
                      .join('\n'),
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthPanel,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Expanded(
              child: Row(children: [col('A', a), kOpenHandHGap12, col('B', b)]),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showServiceWorkersDialog(
  BuildContext context,
  WebReverseSessionController ctrl,
) async {
  final list = await ctrl.listServiceWorkers();
  if (!context.mounted) return;
  await webReverseToolDialogs.show<void>(
    context: context,
    builder: (dialogContext) => buildOpenHandAlertDialog(
      title: Text(
        openHandLocalizedText(
          dialogContext,
          zh: 'Service Workers',
          zhHant: 'Service Workers',
          en: 'Service Workers',
          fr: 'Service Workers',
          de: 'Service Worker',
          ja: 'Service Workers',
        ),
      ),
      content: SizedBox(
        width: 560,
        child: list.isEmpty
            ? Text(
                openHandLocalizedText(
                  dialogContext,
                  zh: '当前 origin 无 SW 注册',
                  zhHant: '目前 origin 無 SW 註冊',
                  en: 'No service workers',
                  fr: 'Aucun service worker',
                  de: 'Keine Service Worker',
                  ja: 'Service Worker はありません',
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final w in list)
                    ListTile(
                      dense: true,
                      title: Text(
                        '${w['scriptURL'] ?? w['url'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          fontSize: 12,
                        ),
                      ),
                      subtitle: Text(
                        'state=${w['runningStatus'] ?? w['status'] ?? '-'}',
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(dialogContext).pop(),
          label: openHandCloseLabel(dialogContext),
        ),
        if (list.isNotEmpty)
          OpenHandDialogActionButton.destructive(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              // 用 Runtime.evaluate 调 navigator.serviceWorker.getRegistrations 一键 unregister。
              final r = await ctrl.runReplExpression(
                'navigator.serviceWorker.getRegistrations().then(rs => Promise.all(rs.map(r => r.unregister()))).then(rs => rs.length)',
              );
              if (!context.mounted) return;
              if (r == null) {
                showOpenHandErrorSnack(
                  context,
                  openHandLocalizedText(
                    context,
                    zh: '反注册失败',
                    zhHant: '反註冊失敗',
                    en: 'Unregister failed',
                    fr: 'Échec du unregister',
                    de: 'Unregister fehlgeschlagen',
                    ja: '登録解除に失敗しました',
                  ),
                  duration: kOpenHandSnackBarBriefDuration,
                );
              } else {
                showOpenHandSuccessSnack(
                  context,
                  openHandLocalizedText(
                    context,
                    zh: '已反注册 $r 个 SW',
                    zhHant: '已反註冊 $r 個 SW',
                    en: 'Unregistered $r SWs',
                    fr: '$r SW désinscrits',
                    de: '$r SWs abgemeldet',
                    ja: '$r 個の SW を登録解除しました',
                  ),
                );
              }
            },
            label: openHandLocalizedText(
              dialogContext,
              zh: '全部反注册',
              zhHant: '全部反註冊',
              en: 'Unregister all',
              fr: 'Tout unregister',
              de: 'Alle abmelden',
              ja: 'すべて登録解除',
            ),
          ),
      ],
    ),
  );
}

Future<void> _toggleHarReplayServer(
  BuildContext context,
  WebReverseSessionController ctrl,
) async {
  final running = ctrl.harReplayServer;
  if (running != null) {
    await ctrl.stopHarReplayServer();
    if (!context.mounted) return;
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '已停止 HAR 重放服务器',
        zhHant: '已停止 HAR 重放伺服器',
        en: 'HAR replay server stopped',
        fr: 'Serveur de replay HAR arrêté',
        de: 'HAR-Replay-Server gestoppt',
        ja: 'HAR リプレイサーバーを停止しました',
      ),
      duration: kOpenHandSnackBarBriefDuration,
    );
    return;
  }
  final r = await ctrl.startHarReplayServer();
  if (!context.mounted) return;
  if (r == null) {
    showOpenHandErrorSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '启动失败：HAR 不可用或端口被占',
        zhHant: '啟動失敗：HAR 不可用或連接埠被占用',
        en: 'Failed to start',
        fr: 'Échec du démarrage',
        de: 'Start fehlgeschlagen',
        ja: '起動に失敗しました',
      ),
      duration: kOpenHandSnackBarNormalDuration,
    );
    return;
  }
  showOpenHandInfoSnack(
    context,
    openHandLocalizedText(
      context,
      zh: 'HAR 重放服务器已启动：http://127.0.0.1:${r.port}/  · 已加载 ${r.entryCount} 条',
      zhHant:
          'HAR 重放伺服器已啟動：http://127.0.0.1:${r.port}/  · 已載入 ${r.entryCount} 筆',
      en: 'Replay server up at http://127.0.0.1:${r.port}/  · ${r.entryCount} entries',
      fr: 'Serveur de replay actif sur http://127.0.0.1:${r.port}/  · ${r.entryCount} entrées',
      de: 'Replay-Server lauft unter http://127.0.0.1:${r.port}/  · ${r.entryCount} Eintrage',
      ja: 'リプレイサーバー起動: http://127.0.0.1:${r.port}/  · ${r.entryCount} 件',
    ),
    duration: kOpenHandSnackBarLongReadDuration,
    action: SnackBarAction(
      label: openHandLocalizedText(
        context,
        zh: '复制端口',
        zhHant: '複製連接埠',
        en: 'Copy port',
        fr: 'Copier le port',
        de: 'Port kopieren',
        ja: 'ポートをコピー',
      ),
      onPressed: () => unawaited(_copyHarReplayPort(context, r.port)),
    ),
  );
}

Future<void> _copyHarReplayPort(BuildContext context, int port) async {
  await copyWebReverseTextToClipboard(
    context: context,
    text: '$port',
    logTag: 'web_reverse_advanced_menu',
    logAction: '复制 HAR 重放端口',
    showSuccess: false,
  );
}

Future<void> _toggleMitmproxyBridge(
  BuildContext context,
  WebReverseSessionController ctrl,
) async {
  if (ctrl.mitmproxyBridge != null) {
    await ctrl.stopMitmproxyBridge();
    if (!context.mounted) return;
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '已停止 mitmproxy 桥接',
        zhHant: '已停止 mitmproxy 橋接',
        en: 'mitmproxy bridge stopped',
        fr: 'Pont mitmproxy arrêté',
        de: 'mitmproxy-Bridge gestoppt',
        ja: 'mitmproxy ブリッジを停止しました',
      ),
      duration: kOpenHandSnackBarBriefDuration,
    );
    return;
  }
  // 先确认 mitmdump 在 PATH。
  final exe = await WebReverseMitmproxyBridge.detectMitmdump();
  if (exe == null) {
    if (!context.mounted) return;
    await showOpenHandInfoDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '未检测到 mitmdump',
        zhHant: '未偵測到 mitmdump',
        en: 'mitmdump not found',
        fr: 'mitmdump introuvable',
        de: 'mitmdump nicht gefunden',
        ja: 'mitmdump が見つかりません',
      ),
      closeLabel: openHandCloseLabel(context),
      message: openHandLocalizedText(
        context,
        zh:
            '请先安装 mitmproxy（macOS：brew install mitmproxy；Linux：sudo apt install mitmproxy；Windows：从 https://mitmproxy.org 下载），'
            '并把 mitmdump 加入 PATH。\n\n'
            '装好后在客户端把代理指向 127.0.0.1:8080，并访问 http://mitm.it 安装根证书。',
        zhHant:
            '請先安裝 mitmproxy（macOS：brew install mitmproxy；Linux：sudo apt install mitmproxy；Windows：從 https://mitmproxy.org 下載），'
            '並把 mitmdump 加入 PATH。\n\n'
            '裝好後在客戶端把代理指向 127.0.0.1:8080，並訪問 http://mitm.it 安裝根憑證。',
        en:
            'Install mitmproxy (macOS: brew install mitmproxy; Linux: sudo apt install mitmproxy; Windows: https://mitmproxy.org), '
            'then set client proxy to 127.0.0.1:8080 and trust the root cert via http://mitm.it.',
        fr:
            'Installez mitmproxy (macOS : brew install mitmproxy ; Linux : sudo apt install mitmproxy ; Windows : https://mitmproxy.org), '
            'puis configurez le proxy client sur 127.0.0.1:8080 et faites confiance au certificat via http://mitm.it.',
        de:
            'Installieren Sie mitmproxy (macOS: brew install mitmproxy; Linux: sudo apt install mitmproxy; Windows: https://mitmproxy.org), '
            'setzen Sie danach den Client-Proxy auf 127.0.0.1:8080 und vertrauen Sie dem Zertifikat über http://mitm.it.',
        ja:
            'mitmproxy をインストールしてください（macOS: brew install mitmproxy、Linux: sudo apt install mitmproxy、Windows: https://mitmproxy.org）。'
            'その後、クライアントのプロキシを 127.0.0.1:8080 に設定し、http://mitm.it でルート証明書を信頼してください。',
      ),
    );
    return;
  }
  // 提示用户配置代理。
  if (!context.mounted) return;
  final go = await showOpenHandConfirmDialog(
    context: context,
    title: openHandLocalizedText(
      context,
      zh: '即将启动 mitmproxy 桥接',
      zhHant: '即將啟動 mitmproxy 橋接',
      en: 'Start mitmproxy bridge',
      fr: 'Démarrer le pont mitmproxy',
      de: 'mitmproxy-Bridge starten',
      ja: 'mitmproxy ブリッジを起動',
    ),
    message: openHandLocalizedText(
      context,
      zh: '将以 mitmdump -p 8080 启动；启动后请把目标客户端代理指向 127.0.0.1:8080。\n\n首次使用须信任根证书：访问 http://mitm.it 按平台说明安装。\n\n所有抓到的请求会以 mitmproxy 资源类型出现在 Network 列表。',
      zhHant:
          '將以 mitmdump -p 8080 啟動；啟動後請把目標客戶端代理指向 127.0.0.1:8080。\n\n首次使用須信任根憑證：訪問 http://mitm.it 按平台說明安裝。\n\n所有抓到的請求會以 mitmproxy 資源類型出現在 Network 清單。',
      en: 'Will run mitmdump -p 8080; route your client proxy to 127.0.0.1:8080.\n\nFirst time? Trust the CA via http://mitm.it.\n\nCaptured traffic shows up under the mitmproxy resource type.',
      fr: 'Lance mitmdump -p 8080 ; pointez le proxy client vers 127.0.0.1:8080.\n\nPremière utilisation ? Faites confiance à la CA via http://mitm.it.\n\nLe trafic capturé apparaîtra comme ressource mitmproxy dans Network.',
      de: 'Startet mitmdump -p 8080; richten Sie den Client-Proxy auf 127.0.0.1:8080.\n\nZum ersten Mal? CA über http://mitm.it vertrauen.\n\nErfasster Traffic erscheint als mitmproxy-Ressource in Network.',
      ja: 'mitmdump -p 8080 で起動します。起動後、対象クライアントのプロキシを 127.0.0.1:8080 に向けてください。\n\n初回は http://mitm.it で CA を信頼してください。\n\n取得した通信は Network リストに mitmproxy リソースとして表示されます。',
    ),
    cancelLabel: openHandCancelLabel(context),
    confirmLabel: openHandStartLabel(context),
  );
  if (go != true || !context.mounted) return;
  final r = await ctrl.startMitmproxyBridge();
  if (!context.mounted) return;
  if (r == null) {
    showOpenHandErrorSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '启动失败（端口 8080 可能已被占）',
        zhHant: '啟動失敗（連接埠 8080 可能已被占用）',
        en: 'Failed (port 8080 in use?)',
        fr: 'Échec (port 8080 déjà utilisé ?)',
        de: 'Fehlgeschlagen (Port 8080 belegt?)',
        ja: '失敗しました（ポート 8080 が使用中の可能性があります）',
      ),
      duration: kOpenHandSnackBarNormalDuration,
    );
    return;
  }
  showOpenHandSuccessSnack(
    context,
    openHandLocalizedText(
      context,
      zh: 'mitmproxy 桥接已启动：客户端代理 127.0.0.1:${r.mitmPort}（回调 :${r.callbackPort}）',
      zhHant:
          'mitmproxy 橋接已啟動：客戶端代理 127.0.0.1:${r.mitmPort}（回調 :${r.callbackPort}）',
      en: 'mitmproxy up: proxy via 127.0.0.1:${r.mitmPort} (callback :${r.callbackPort})',
      fr: 'mitmproxy actif : proxy 127.0.0.1:${r.mitmPort} (callback :${r.callbackPort})',
      de: 'mitmproxy aktiv: Proxy 127.0.0.1:${r.mitmPort} (Callback :${r.callbackPort})',
      ja: 'mitmproxy 起動: proxy 127.0.0.1:${r.mitmPort}（callback :${r.callbackPort}）',
    ),
    duration: kOpenHandSnackBarLongReadDuration,
  );
}

Future<void> _toggleWebRtcCapture(
  BuildContext context,
  WebReverseSessionController ctrl,
) async {
  final ok = await ctrl.installWebRtcCapture();
  if (!context.mounted) return;
  if (!ok) {
    showOpenHandErrorSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '注入失败（page 可能尚未就绪）',
        zhHant: '注入失敗（page 可能尚未就緒）',
        en: 'Install failed',
        fr: 'Échec de l’injection',
        de: 'Installation fehlgeschlagen',
        ja: '注入に失敗しました',
      ),
      duration: kOpenHandSnackBarBriefDuration,
    );
    return;
  }
  await webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _WebRtcLiveDialog(controller: ctrl),
  );
}

/// WebRTC 实时调试面板：每秒 poll readWebRtcLog 拉新增日志，分两个 tab：
/// ① 实时图表：按 PeerConnection id 维护 _RtcSeries（最近 60 个采样的
///    bytesSent / bytesReceived / packetsLost / rtt），用 _RtcChart 渲染
///    四条折线 + 当前值 chip；② 事件流：完整 JSON 日志 SelectableText。
class _WebRtcLiveDialog extends StatefulWidget {
  const _WebRtcLiveDialog({required this.controller});

  final WebReverseSessionController controller;

  @override
  State<_WebRtcLiveDialog> createState() => _WebRtcLiveDialogState();
}

class _WebRtcLiveDialogState extends State<_WebRtcLiveDialog> {
  Timer? _pollTimer;
  final Map<int, _RtcSeries> _series = <int, _RtcSeries>{};
  final List<Map<String, Object?>> _events = <Map<String, Object?>>[];
  static const int _maxEvents = 200;
  static const int _maxConnections = kWebReverseMaxWebRtcConnections;
  static const int _maxIceEntriesPerConnection = 200;
  static const int _maxSdpChars = 128 * kBytesPerKiB;
  static const int _maxSdpTotalChars = 2 * kBytesPerMiB;
  final List<int> _connectionOrder = <int>[];
  int _sdpChars = 0;
  bool _disposed = false;
  bool _pollInFlight = false;
  String? _targetId;
  int _selected = 0;
  // 0 = 图表，1 = ICE 拓扑，2 = SDP Diff，3 = 事件流。
  int _tab = 0;
  // 按连接维护 ICE 候选项与状态历史。
  final Map<int, List<_IceEntry>> _iceLog = <int, List<_IceEntry>>{};
  // SDP 历史：每个 PC 维护 local / remote 各两份（最新 + 上一份），用于 diff。
  final Map<int, _SdpPair> _sdps = <int, _SdpPair>{};
  // ICE tab 的「时序 / 图」视图切换。默认时序列表，用户切到
  // 图模式后用 _IceTopologyGraph 渲染当前 PC 的有向拓扑。
  bool _iceGraphMode = false;

  @override
  void initState() {
    super.initState();
    _pollTimer = startNonOverlappingPeriodicTimer(
      const Duration(seconds: 1),
      (_) => _poll(),
      onError: _reportPollError,
    );
    unawaited(_poll().catchError(_reportPollError));
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_pollInFlight || _disposed) return;
    _pollInFlight = true;
    try {
      await _pollOnce();
    } finally {
      _pollInFlight = false;
    }
  }

  void _reportPollError(Object error, StackTrace stack) {
    silentLog('web_reverse_dashboard_dialog', '轮询 WebRTC 日志', error, stack);
  }

  Future<void> _pollOnce() async {
    final controller = widget.controller;
    final targetId = controller.currentPageTargetId;
    if (targetId == null) return;
    final targetChanged = _targetId != targetId;
    if (targetChanged) {
      if (!mounted) return;
      setState(() {
        _targetId = targetId;
        _selected = 0;
        _connectionOrder.clear();
        _series.clear();
        _events.clear();
        _iceLog.clear();
        _sdps.clear();
        _sdpChars = 0;
      });
    }
    if (targetChanged && !await controller.installWebRtcCapture()) return;
    final entries = await controller.readWebRtcLog();
    if (_disposed || !mounted || controller.currentPageTargetId != targetId) {
      return;
    }
    if (!targetChanged && entries.isEmpty) return;
    setState(() {
      for (final e in entries) {
        final kind = '${e['kind'] ?? ''}';
        if (kind == 'stats') {
          final id = nonNegativeIntFromValue(e['id'], fallback: 0);
          if (id <= 0) continue;
          _retainConnection(id);
          final s = _series.putIfAbsent(id, () => _RtcSeries());
          s.push(
            bytesSent: optionalNonNegativeDoubleFromValue(e['bytesSent']) ?? 0,
            bytesReceived:
                optionalNonNegativeDoubleFromValue(e['bytesReceived']) ?? 0,
            packetsLost:
                optionalNonNegativeDoubleFromValue(e['packetsLost']) ?? 0,
            rttMs: (optionalNonNegativeDoubleFromValue(e['rtt']) ?? 0) * 1000.0,
          );
          if (_selected == 0 && _series.isNotEmpty) {
            _selected = _series.keys.first;
          }
        } else {
          // 控制平面事件分类写入 ICE 与 SDP 历史，原始数据保留给事件流。
          final id = nonNegativeIntFromValue(e['id'], fallback: 0);
          if (id > 0) {
            _retainConnection(id);
            if (kind == 'icecandidate' ||
                kind == 'pc.create' ||
                kind == 'track' ||
                kind == 'datachannel' ||
                kind == 'connectionstatechange' ||
                kind == 'iceconnectionstatechange') {
              final iceEntries = _iceLog.putIfAbsent(id, () => <_IceEntry>[]);
              iceEntries.add(_IceEntry(kind: kind, payload: e));
              if (iceEntries.length > _maxIceEntriesPerConnection) {
                iceEntries.removeRange(
                  0,
                  iceEntries.length - _maxIceEntriesPerConnection,
                );
              }
            }
            if (kind == 'setLocalDescription:result' ||
                kind == 'setRemoteDescription:result') {
              final sdp = e['sdp'] is String ? e['sdp'] as String : '';
              final type = '${e['type'] ?? ''}';
              _updateSdp(id: id, kind: kind, type: type, sdp: sdp);
            }
          }
          _events.add(e);
          if (_events.length > _maxEvents) {
            _events.removeRange(0, _events.length - _maxEvents);
          }
        }
      }
    });
  }

  void _retainConnection(int id) {
    _connectionOrder.remove(id);
    _connectionOrder.add(id);
    while (_connectionOrder.length > _maxConnections) {
      final removed = _connectionOrder.removeAt(0);
      _series.remove(removed);
      _iceLog.remove(removed);
      final pair = _sdps.remove(removed);
      if (pair != null) _sdpChars -= _sdpPairChars(pair);
      if (_selected == removed) _selected = 0;
    }
  }

  void _updateSdp({
    required int id,
    required String kind,
    required String type,
    required String sdp,
  }) {
    final pair = _sdps.putIfAbsent(id, () => _SdpPair());
    _sdpChars -= _sdpPairChars(pair);
    final version = _SdpVersion(
      type: clipText(type, 32, suffix: ''),
      sdp: clipText(sdp, _maxSdpChars, suffix: ''),
    );
    if (kind == 'setLocalDescription:result') {
      pair.prevLocal = pair.local;
      pair.local = version;
    } else {
      pair.prevRemote = pair.remote;
      pair.remote = version;
    }
    _sdpChars += _sdpPairChars(pair);
    while (_sdpChars > _maxSdpTotalChars && _sdps.isNotEmpty) {
      final evictId = _connectionOrder.firstWhere(
        _sdps.containsKey,
        orElse: () => _sdps.keys.first,
      );
      final evicted = _sdps.remove(evictId);
      if (evicted != null) _sdpChars -= _sdpPairChars(evicted);
    }
  }

  int _sdpPairChars(_SdpPair pair) {
    return (pair.local?.sdp.length ?? 0) +
        (pair.prevLocal?.sdp.length ?? 0) +
        (pair.remote?.sdp.length ?? 0) +
        (pair.prevRemote?.sdp.length ?? 0);
  }

  /// 把当前 _series 的全部 PC 拼成 CSV 并交给 file_selector 落盘。
  /// CSV schema：pc_id,bucket_seconds_ago,bytes_sent,bytes_received,
  /// packets_lost,rtt_ms。每行一个 sample，buckets 0 = 当前秒。
  Future<void> _exportSeriesCsv() async {
    if (_series.isEmpty) return;
    final buf = StringBuffer()
      ..writeln(
        'pc_id,bucket_seconds_ago,bytes_sent,bytes_received,'
        'packets_lost,rtt_ms',
      );
    final ids = _series.keys.toList()..sort();
    for (final id in ids) {
      final samples = _series[id]!.samples;
      // samples[i] 表示第 i 次采集（按 push 顺序，最后一次是最新）。
      // bucket_seconds_ago = (n - 1 - i)，让最新一行 = 0。
      for (var i = 0; i < samples.length; i++) {
        final s = samples[i];
        buf.writeln(
          '$id,${samples.length - 1 - i},${s.bytesSent.toStringAsFixed(0)},'
          '${s.bytesReceived.toStringAsFixed(0)},'
          '${s.packetsLost.toStringAsFixed(0)},'
          '${s.rttMs.toStringAsFixed(2)}',
        );
      }
    }
    const typeGroup = XTypeGroup(label: 'CSV', extensions: <String>['csv']);
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    FileSaveLocation? loc;
    try {
      loc = await getSaveLocation(
        suggestedName: 'webrtc-stats-$ts.csv',
        acceptedTypeGroups: const [typeGroup],
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        '选择 RTC CSV 保存位置',
        error,
        stack,
      );
    }
    if (loc == null) return;
    try {
      await writeFileAtomically(File(loc.path), buf.toString());
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'CSV 已保存',
          zhHant: 'CSV 已儲存',
          en: 'CSV saved',
          fr: 'CSV enregistré',
          de: 'CSV gespeichert',
          ja: 'CSV を保存しました',
        ),
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '写入 RTC CSV', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        webReverseSaveFailedMessage(context),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthWide,
      maxHeight: kOpenHandDialogHeightStandard,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.video_camera_back_rounded,
            title: openHandLocalizedText(
              context,
              zh: 'WebRTC 实时面板',
              zhHant: 'WebRTC 即時面板',
              en: 'WebRTC live panel',
              fr: 'Panneau WebRTC live',
              de: 'WebRTC-Live-Panel',
              ja: 'WebRTC ライブパネル',
            ),
            actions: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: kOpenHandBorderRadius8,
                ),
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '${_series.length} 连接 · 1s 采样',
                    zhHant: '${_series.length} 連線 · 1s 採樣',
                    en: '${_series.length} pc · 1s sample',
                    fr: '${_series.length} pc · échantillon 1s',
                    de: '${_series.length} PC · 1s Sample',
                    ja: '${_series.length} PC · 1s サンプル',
                  ),
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                _RtcTab(
                  label: openHandLocalizedText(
                    context,
                    zh: '实时图表',
                    zhHant: '即時圖表',
                    en: 'Live charts',
                    fr: 'Graphiques live',
                    de: 'Live-Charts',
                    ja: 'ライブチャート',
                  ),
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                kOpenHandHGap8,
                _RtcTab(
                  label: openHandLocalizedText(
                    context,
                    zh: 'ICE 拓扑',
                    zhHant: 'ICE 拓撲',
                    en: 'ICE topology',
                    fr: 'Topologie ICE',
                    de: 'ICE-Topologie',
                    ja: 'ICE トポロジー',
                  ),
                  selected: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
                kOpenHandHGap8,
                _RtcTab(
                  label: openHandLocalizedText(
                    context,
                    zh: 'SDP Diff',
                    zhHant: 'SDP Diff',
                    en: 'SDP diff',
                    fr: 'Diff SDP',
                    de: 'SDP-Diff',
                    ja: 'SDP diff',
                  ),
                  selected: _tab == 2,
                  onTap: () => setState(() => _tab = 2),
                ),
                kOpenHandHGap8,
                _RtcTab(
                  label: openHandLocalizedText(
                    context,
                    zh: '事件流',
                    zhHant: '事件流',
                    en: 'Events',
                    fr: 'Événements',
                    de: 'Events',
                    ja: 'イベント',
                  ),
                  selected: _tab == 3,
                  onTap: () => setState(() => _tab = 3),
                ),
                const Spacer(),
                if (_tab == 0 && _series.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _exportSeriesCsv,
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: Text(_wrExportCsvLabel(context)),
                  ),
                if (_tab == 3 && _events.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await copyWebReverseTextToClipboard(
                        context: context,
                        text: prettyPrintJson(_events),
                        successBase: openHandCopiedLabel(context),
                        logTag: 'web_reverse_webrtc_dialog',
                        logAction: '复制事件',
                        successDuration: const Duration(seconds: 1),
                      );
                    },
                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                    label: Text(
                      openHandLocalizedText(
                        context,
                        zh: '复制事件',
                        zhHant: '複製事件',
                        en: 'Copy events',
                        fr: 'Copier les événements',
                        de: 'Events kopieren',
                        ja: 'イベントをコピー',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          kOpenHandGap8,
          const Divider(height: 1),
          Flexible(
            child: AnimatedSwitcher(
              duration: openHandMotionDuration(context, kOpenHandMotion220),
              child: switch (_tab) {
                0 => _buildChartsTab(theme),
                1 => _buildIceTab(theme),
                2 => _buildSdpDiffTab(theme),
                _ => _buildEventsTab(theme),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartsTab(ThemeData theme) {
    final cs = theme.colorScheme;
    if (_series.isEmpty) {
      return Padding(
        key: const ValueKey('empty-charts'),
        padding: const EdgeInsets.all(36),
        child: OpenHandInlineEmptyState(
          message: openHandLocalizedText(
            context,
            zh: '当前页面尚未发起 WebRTC。\n触发音视频通话或 datachannel 后会自动出现采样曲线。',
            zhHant: '目前頁面尚未發起 WebRTC。\n觸發音視訊通話或 datachannel 後會自動出現採樣曲線。',
            en: 'No WebRTC yet. Trigger a call/datachannel; samples will appear automatically.',
            fr: 'Aucun WebRTC pour l’instant. Lancez un appel ou datachannel pour voir les échantillons.',
            de: 'Noch kein WebRTC. Starten Sie einen Call oder datachannel, dann erscheinen Samples automatisch.',
            ja: 'まだ WebRTC はありません。通話または datachannel を開始するとサンプル曲線が表示されます。',
          ),
          dense: true,
        ),
      );
    }
    final ids = _series.keys.toList()..sort();
    final selectedId = _series.containsKey(_selected) ? _selected : ids.first;
    final s = _series[selectedId]!;
    final last = s.last;
    return Padding(
      key: const ValueKey('charts'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final id in ids)
                ChoiceChip(
                  label: Text('PC #$id'),
                  selected: id == selectedId,
                  onSelected: (_) => setState(() => _selected = id),
                ),
            ],
          ),
          kOpenHandGap12,
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _RtcStatChip(
                label: openHandLocalizedText(
                  context,
                  zh: '已发送',
                  zhHant: '已傳送',
                  en: 'Sent',
                  fr: 'Envoye',
                  de: 'Gesendet',
                  ja: '送信済み',
                ),
                value: formatByteSize(last?.bytesSent ?? 0),
                color: cs.primary,
              ),
              _RtcStatChip(
                label: openHandLocalizedText(
                  context,
                  zh: '已接收',
                  zhHant: '已接收',
                  en: 'Recv',
                  fr: 'Reçu',
                  de: 'Empfangen',
                  ja: '受信済み',
                ),
                value: formatByteSize(last?.bytesReceived ?? 0),
                color: cs.tertiary,
              ),
              _RtcStatChip(
                label: openHandLocalizedText(
                  context,
                  zh: '丢包',
                  zhHant: '遺失封包',
                  en: 'Lost',
                  fr: 'Perdus',
                  de: 'Verloren',
                  ja: 'ロスト',
                ),
                value: '${(last?.packetsLost ?? 0).toInt()}',
                color: cs.error,
              ),
              _RtcStatChip(
                label: 'RTT',
                value: '${(last?.rttMs ?? 0).toStringAsFixed(0)} ms',
                color: cs.secondary,
              ),
            ],
          ),
          kOpenHandGap14,
          Expanded(
            child: CustomPaint(
              painter: _RtcChartPainter(
                series: s,
                primary: cs.primary,
                tertiary: cs.tertiary,
                error: cs.error,
                secondary: cs.secondary,
                grid: cs.outlineVariant.withValues(alpha: 0.45),
                onSurface: cs.onSurfaceVariant,
              ),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }

  /// ICE 拓扑 tab：把每个 PC 的 pc.create / track / datachannel /
  /// icecandidate / connectionstatechange / iceconnectionstatechange 事件按
  /// 时间序列垂直列出来；左侧是 ChoiceChip 切 PC，右侧滚动列。本地候选
  /// （typ host）用 primary 色点；srflx / relay 用 tertiary；远端候选不
  /// 区分单独标 secondary。datachannel / track 单列前缀图标。
  ///
  /// 顶部加「时序 / 图」切换：图模式用 CustomPainter 把
  /// candidate / track / datachannel 节点按 typ 分组围着 PC 节点展开成有
  /// 向图，箭头由 candidate 指向 PC、track 由 PC 指向 stream，让用户一眼
  /// 看清拓扑。
  Widget _buildIceTab(ThemeData theme) {
    final cs = theme.colorScheme;
    final ids = _iceLog.keys.toList()..sort();
    if (ids.isEmpty) {
      return Padding(
        key: const ValueKey('empty-ice'),
        padding: const EdgeInsets.all(36),
        child: OpenHandInlineEmptyState(
          message: openHandLocalizedText(
            context,
            zh: '暂无 ICE 事件',
            zhHant: '暫無 ICE 事件',
            en: 'No ICE events',
            fr: 'Aucun événement ICE',
            de: 'Keine ICE-Events',
            ja: 'ICE イベントはありません',
          ),
          dense: true,
        ),
      );
    }
    final selectedId = _iceLog.containsKey(_selected) ? _selected : ids.first;
    final entries = _iceLog[selectedId] ?? const <_IceEntry>[];
    return Padding(
      key: const ValueKey('ice'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final id in ids)
                    ChoiceChip(
                      label: Text('PC #$id · ${_iceLog[id]!.length}'),
                      selected: id == selectedId,
                      onSelected: (_) => setState(() => _selected = id),
                    ),
                ],
              ),
              const Spacer(),
              SegmentedButton<bool>(
                segments: <ButtonSegment<bool>>[
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.list_rounded, size: 14),
                    label: Text(
                      openHandLocalizedText(
                        context,
                        zh: '时序',
                        zhHant: '時序',
                        en: 'List',
                        fr: 'Liste',
                        de: 'Liste',
                        ja: 'リスト',
                      ),
                    ),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.hub_rounded, size: 14),
                    label: Text(
                      openHandLocalizedText(
                        context,
                        zh: '图',
                        zhHant: '圖',
                        en: 'Graph',
                        fr: 'Graphe',
                        de: 'Graph',
                        ja: 'グラフ',
                      ),
                    ),
                  ),
                ],
                selected: {_iceGraphMode},
                onSelectionChanged: (s) =>
                    setState(() => _iceGraphMode = s.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          kOpenHandGap10,
          Expanded(
            child: _iceGraphMode
                ? _IceTopologyGraph(
                    pcId: selectedId,
                    entries: entries,
                    primary: cs.primary,
                    tertiary: cs.tertiary,
                    secondary: cs.secondary,
                    error: cs.error,
                    onSurface: cs.onSurface,
                    surfaceContainer: cs.surfaceContainerHigh,
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      // 倒序展示：最新事件在顶部更易观察。
                      final entry = entries[entries.length - 1 - i];
                      final summary = _summarizeIce(entry);
                      final color = _iceTone(entry.kind, cs);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(top: 5, right: 8),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                summary,
                                style: const TextStyle(
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _iceTone(String kind, ColorScheme cs) {
    switch (kind) {
      case 'icecandidate':
        return cs.tertiary;
      case 'track':
      case 'datachannel':
        return cs.primary;
      case 'pc.create':
        return cs.secondary;
      case 'connectionstatechange':
      case 'iceconnectionstatechange':
        return cs.error;
    }
    return cs.onSurfaceVariant;
  }

  String _summarizeIce(_IceEntry entry) {
    final p = entry.payload;
    switch (entry.kind) {
      case 'pc.create':
        return 'pc.create · cfg=${jsonEncode(p['config'])}';
      case 'track':
        return 'track · ${p['trackKind']} state=${p['readyState']} '
            'streams=${p['streamIds']}';
      case 'datachannel':
        return 'datachannel · label=${p['label']} ordered=${p['ordered']}';
      case 'icecandidate':
        final cand = '${p['candidate'] ?? ''}';
        // candidate 字符串通常是 "candidate:foundation comp transport prio
        //  ip port typ <type> ..."；提取 typ 后单字。
        final m = RegExp(r'\btyp (\w+)').firstMatch(cand);
        final typ = m?.group(1) ?? '?';
        return 'icecandidate · typ=$typ · ${clipTextWithEllipsis(cand, 100)}';
      case 'connectionstatechange':
        return 'connection → ${p['state']}';
      case 'iceconnectionstatechange':
        return 'ice → ${p['state']}';
    }
    return '${entry.kind} · ${jsonEncode(p)}';
  }

  /// SDP Diff tab：左右双列展示当前 PC 的 local SDP / remote SDP。每列
  /// 头部还显示 type（offer/answer），下方按"上一份 vs 当前"做行级 diff
  /// （绿 = 新增，红 = 删除，灰 = 不变）。第一次接到 SDP 时只渲染单列。
  Widget _buildSdpDiffTab(ThemeData theme) {
    final ids = _sdps.keys.toList()..sort();
    if (ids.isEmpty) {
      return Padding(
        key: const ValueKey('empty-sdp'),
        padding: const EdgeInsets.all(36),
        child: OpenHandInlineEmptyState(
          message: openHandLocalizedText(
            context,
            zh: '暂无 SDP。\n触发 setLocalDescription / setRemoteDescription 后会出现。',
            zhHant:
                '暫無 SDP。\n觸發 setLocalDescription / setRemoteDescription 後會出現。',
            en: 'No SDP yet.',
            fr: 'Aucun SDP pour l’instant.',
            de: 'Noch kein SDP.',
            ja: 'SDP はまだありません。',
          ),
          dense: true,
        ),
      );
    }
    final selectedId = _sdps.containsKey(_selected) ? _selected : ids.first;
    final pair = _sdps[selectedId]!;
    return Padding(
      key: const ValueKey('sdp'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final id in ids)
                ChoiceChip(
                  label: Text('PC #$id'),
                  selected: id == selectedId,
                  onSelected: (_) => setState(() => _selected = id),
                ),
            ],
          ),
          kOpenHandGap12,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SdpDiffColumn(
                    title: openHandLocalizedText(
                      context,
                      zh: '本地 SDP',
                      zhHant: '本地 SDP',
                      en: 'Local SDP',
                      fr: 'SDP local',
                      de: 'Lokales SDP',
                      ja: 'ローカル SDP',
                    ),
                    current: pair.local,
                    previous: pair.prevLocal,
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: _SdpDiffColumn(
                    title: openHandLocalizedText(
                      context,
                      zh: '远端 SDP',
                      zhHant: '遠端 SDP',
                      en: 'Remote SDP',
                      fr: 'SDP distant',
                      de: 'Remote-SDP',
                      ja: 'リモート SDP',
                    ),
                    current: pair.remote,
                    previous: pair.prevRemote,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsTab(ThemeData theme) {
    if (_events.isEmpty) {
      return Padding(
        key: const ValueKey('empty-events'),
        padding: const EdgeInsets.all(36),
        child: OpenHandInlineEmptyState(
          message: openHandLocalizedText(
            context,
            zh: '暂无事件',
            zhHant: '暫無事件',
            en: 'No events',
            fr: 'Aucun événement',
            de: 'Keine Events',
            ja: 'イベントはありません',
          ),
          dense: true,
        ),
      );
    }
    return Padding(
      key: const ValueKey('events'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: ListView.builder(
        reverse: true,
        itemCount: _events.length,
        itemBuilder: (_, i) {
          final e = _events[_events.length - 1 - i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: SelectableText(
              '[${e['kind']}] ${jsonEncode(e)}',
              style: const TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RtcSeries {
  static const int _capacity = 60;
  final List<_RtcSample> samples = <_RtcSample>[];

  _RtcSample? get last => samples.isEmpty ? null : samples.last;

  void push({
    required double bytesSent,
    required double bytesReceived,
    required double packetsLost,
    required double rttMs,
  }) {
    samples.add(
      _RtcSample(
        bytesSent: bytesSent,
        bytesReceived: bytesReceived,
        packetsLost: packetsLost,
        rttMs: rttMs,
      ),
    );
    if (samples.length > _capacity) {
      samples.removeRange(0, samples.length - _capacity);
    }
  }
}

class _RtcSample {
  const _RtcSample({
    required this.bytesSent,
    required this.bytesReceived,
    required this.packetsLost,
    required this.rttMs,
  });

  final double bytesSent;
  final double bytesReceived;
  final double packetsLost;
  final double rttMs;
}

class _RtcTab extends StatelessWidget {
  const _RtcTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: kOpenHandBorderRadius10,
      onTap: onTap,
      child: AnimatedContainer(
        duration: openHandMotionDuration(context, kOpenHandMotion220),
        curve: kOpenHandSwitchInCurve,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer.withValues(alpha: 0.6)
              : Colors.transparent,
          borderRadius: kOpenHandBorderRadius10,
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.4)
                : cs.outlineVariant,
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: openHandMotionDuration(context, kOpenHandMotion220),
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? cs.primary : cs.onSurfaceVariant,
            fontSize: 13,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _RtcStatChip extends StatelessWidget {
  const _RtcStatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: kOpenHandBorderRadius10,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          kOpenHandHGap6,
          Text(label, style: theme.textTheme.labelSmall),
          kOpenHandHGap6,
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFamily: kOpenHandMonospaceFontFamily,
            ),
          ),
        ],
      ),
    );
  }
}

class _RtcChartPainter extends CustomPainter {
  _RtcChartPainter({
    required this.series,
    required this.primary,
    required this.tertiary,
    required this.error,
    required this.secondary,
    required this.grid,
    required this.onSurface,
  });

  final _RtcSeries series;
  final Color primary;
  final Color tertiary;
  final Color error;
  final Color secondary;
  final Color grid;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.samples.isEmpty) return;
    // 留 28px 左侧给 y 轴标签，14px 底部给 x 轴。
    const left = 28.0, bottom = 18.0;
    final w = size.width - left, h = size.height - bottom;
    const origin = Offset(left, 0);
    // 网格。
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = h * i / 4;
      canvas.drawLine(Offset(origin.dx, y), Offset(origin.dx + w, y), gp);
    }
    // 计算两组 axis：bytes 和 rtt/packets。
    var maxBytes = 1.0;
    var maxRtt = 1.0;
    var maxLost = 1.0;
    for (final s in series.samples) {
      if (s.bytesSent > maxBytes) maxBytes = s.bytesSent;
      if (s.bytesReceived > maxBytes) maxBytes = s.bytesReceived;
      if (s.rttMs > maxRtt) maxRtt = s.rttMs;
      if (s.packetsLost > maxLost) maxLost = s.packetsLost;
    }
    final n = series.samples.length;
    Offset xy(int i, double v, double maxV) {
      final x = origin.dx + (n == 1 ? w / 2 : w * i / (n - 1));
      final y = h - (v / maxV) * h;
      return Offset(x, y);
    }

    void drawLine(List<Offset> pts, Color c, {double sw = 1.6}) {
      if (pts.isEmpty) return;
      final p = Paint()
        ..color = c
        ..strokeWidth = sw
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, p);
    }

    drawLine([
      for (var i = 0; i < n; i++) xy(i, series.samples[i].bytesSent, maxBytes),
    ], primary);
    drawLine([
      for (var i = 0; i < n; i++)
        xy(i, series.samples[i].bytesReceived, maxBytes),
    ], tertiary);
    drawLine([
      for (var i = 0; i < n; i++) xy(i, series.samples[i].rttMs, maxRtt),
    ], secondary);
    drawLine(
      [
        for (var i = 0; i < n; i++)
          xy(i, series.samples[i].packetsLost, maxLost),
      ],
      error,
      sw: 1.2,
    );

    // 左侧 y 轴最大值标签。
    final tp = TextPainter(
      text: TextSpan(
        text: formatByteSize(maxBytes),
        style: TextStyle(color: onSurface, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(2, 0));
  }

  @override
  bool shouldRepaint(covariant _RtcChartPainter old) => old.series != series;
}

Future<void> _showWebcrackDialog(BuildContext context) async {
  final input = TextEditingController();
  final output = ValueNotifier<String?>(null);
  final running = ValueNotifier<bool>(false);
  try {
    await webReverseToolDialogs.show<void>(
      context: context,
      builder: (dialogContext) => buildOpenHandAlertDialog(
        title: Text(
          openHandLocalizedText(
            dialogContext,
            zh: 'JS 反混淆（webcrack）',
            zhHant: 'JS 反混淆（webcrack）',
            en: 'JS deobfuscate (webcrack)',
            fr: 'Désobfuscation JS (webcrack)',
            de: 'JS deobfuskieren (webcrack)',
            ja: 'JS 難読化解除（webcrack）',
          ),
        ),
        content: SizedBox(
          width: 760,
          height: 520,
          child: Column(
            children: [
              Text(
                openHandLocalizedText(
                  dialogContext,
                  zh: '把混淆后的 JS 粘到这里 → 点"反混淆"将自动写到 /tmp 并跑 npx webcrack。需要本机已装 Node.js 与 npm。',
                  zhHant:
                      '把混淆後的 JS 貼到這裡 → 點「反混淆」會自動寫到 /tmp 並跑 npx webcrack。需要本機已安裝 Node.js 與 npm。',
                  en: 'Paste obfuscated JS, then click Deobfuscate. Requires Node.js + npm; uses npx webcrack.',
                  fr: 'Collez le JS obfusqué puis cliquez sur Désobfuscation. Requiert Node.js + npm et utilise npx webcrack.',
                  de: 'Obfuskiertes JS einfugen und Deobfuskieren klicken. Erfordert Node.js + npm und nutzt npx webcrack.',
                  ja: '難読化された JS を貼り付けて「難読化解除」を押します。Node.js と npm が必要で、npx webcrack を使用します。',
                ),
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              kOpenHandGap8,
              Expanded(
                child: TextField(
                  controller: input,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'paste obfuscated js…',
                  ),
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 11.5,
                  ),
                ),
              ),
              kOpenHandGap8,
              Expanded(
                child: ValueListenableBuilder<String?>(
                  valueListenable: output,
                  builder: (_, v, _) => Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        dialogContext,
                      ).colorScheme.surfaceContainerHigh,
                      borderRadius: kOpenHandBorderRadius8,
                      border: Border.all(
                        color: Theme.of(
                          dialogContext,
                        ).colorScheme.outlineVariant,
                      ),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        v ??
                            openHandLocalizedText(
                              dialogContext,
                              zh: '反混淆结果会显示在这里。',
                              zhHant: '反混淆結果會顯示在這裡。',
                              en: 'Deobfuscated result appears here.',
                              fr: 'Le résultat désobfusqué apparaît ici.',
                              de: 'Das deobfuskierte Ergebnis erscheint hier.',
                              ja: '難読化解除の結果がここに表示されます。',
                            ),
                        style: const TextStyle(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: openHandCloseLabel(dialogContext),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: running,
            builder: (_, busy, _) => OpenHandDialogActionButton.primary(
              onPressed: busy
                  ? null
                  : () async {
                      if (input.text.trim().isEmpty) return;
                      running.value = true;
                      final result = await _runWebcrack(
                        input.text,
                        locale: Localizations.localeOf(dialogContext),
                      );
                      if (!dialogContext.mounted) return;
                      running.value = false;
                      output.value = result;
                    },
              label: busy
                  ? openHandLocalizedText(
                      dialogContext,
                      zh: '处理中…',
                      zhHant: '處理中…',
                      en: 'Working…',
                      fr: 'Traitement…',
                      de: 'Wird verarbeitet…',
                      ja: '処理中…',
                    )
                  : openHandLocalizedText(
                      dialogContext,
                      zh: '反混淆',
                      zhHant: '反混淆',
                      en: 'Deobfuscate',
                      fr: 'Désobfusquer',
                      de: 'Deobfuskieren',
                      ja: '難読化解除',
                    ),
            ),
          ),
        ],
      ),
    );
  } finally {
    input.dispose();
    output.dispose();
    running.dispose();
  }
}

Future<String> _runWebcrack(String src, {required Locale locale}) async {
  // 写入 temp 文件 + 跑 `npx -y webcrack@latest -o <outDir> <inFile>`，
  // 完成后读 outDir/deobfuscated.js（或 webcrack 默认输出）回显。
  if (src.length > _kWebcrackMaxInputChars) {
    return _advancedTextForLocale(
      locale,
      zh: '[webcrack 输入过大：${src.length} chars，limit $_kWebcrackMaxInputChars chars]',
      zhHant:
          '[webcrack 輸入過大：${src.length} chars，limit $_kWebcrackMaxInputChars chars]',
      en: '[webcrack input too large: ${src.length} chars, limit $_kWebcrackMaxInputChars chars]',
      fr: '[entrée webcrack trop volumineuse : ${src.length} chars, limite $_kWebcrackMaxInputChars chars]',
      de: '[webcrack-Eingabe zu gross: ${src.length} chars, Limit $_kWebcrackMaxInputChars chars]',
      ja: '[webcrack 入力が大きすぎます: ${src.length} chars, limit $_kWebcrackMaxInputChars chars]',
    );
  }
  Directory? tmpDir;
  try {
    final input = await writeNewTemporaryFileTextBounded(
      directoryPrefix: 'oh-webcrack-',
      fileName: 'input.js',
      text: src,
      timeout: _kWebcrackTempWriteTimeout,
      onSecondaryError: (error, stack) => silentLog(
        'web_reverse_dashboard_dialog',
        '清理 webcrack 输入文件',
        error,
        stack,
      ),
    );
    tmpDir = input.parent;
    // npx 第一次需要联网拉包；--yes 跳过提示。
    final result = await runTrackedProcessOrFailed(
      'npx',
      <String>['--yes', 'webcrack@latest', input.path, '-o', tmpDir.path],
      runInShell: Platform.isWindows,
      timeout: const Duration(minutes: 5),
      tag: 'web_reverse.webcrack',
      environment: SystemProxyResolver.instance.resolveSubprocessEnvironment(),
    );
    if (result.exitCode != 0) {
      return _advancedTextForLocale(
        locale,
        zh: '[webcrack 失败 exit=${result.exitCode}]\n${result.stderr}',
        zhHant: '[webcrack 失敗 exit=${result.exitCode}]\n${result.stderr}',
        en: '[webcrack failed exit=${result.exitCode}]\n${result.stderr}',
        fr: '[échec webcrack exit=${result.exitCode}]\n${result.stderr}',
        de: '[webcrack fehlgeschlagen exit=${result.exitCode}]\n${result.stderr}',
        ja: '[webcrack 失敗 exit=${result.exitCode}]\n${result.stderr}',
      );
    }
    final outputDeadline = MonotonicDeadline(
      _kWebcrackOutputReadTotalTimeout,
      timeoutMessage: '读取 webcrack 输出超过总时限。',
    );
    try {
      // webcrack 默认输出 deobfuscated.js + 其他文件；优先取它。
      final out = File('${tmpDir.path}/deobfuscated.js');
      if (await out.exists().timeout(
        outputDeadline.limit(_kWebcrackTempWriteTimeout),
      )) {
        return await _readWebcrackOutputFile(
          out,
          locale: locale,
          totalTimeout: outputDeadline.remaining(),
        );
      }
      // 兜底：把整个 outDir 下所有 .js 拼起来。
      final buf = StringBuffer();
      var totalBytes = 0;
      final listing = await listDirectoryBounded(
        tmpDir,
        maxEntries: _kWebcrackMaxOutputEntries,
        recursive: true,
        totalTimeout: outputDeadline.remaining(),
      );
      for (final entity in listing.entries) {
        if (entity is File && entity.path.endsWith('.js')) {
          final bytes = await entity.length().timeout(
            outputDeadline.limit(_kWebcrackTempWriteTimeout),
          );
          if (totalBytes + bytes > _kWebcrackMaxOutputBytes) {
            buf.writeln(
              _advancedTextForLocale(
                locale,
                zh: '[webcrack 输出已按上限停止：$totalBytes/$_kWebcrackMaxOutputBytes bytes]',
                zhHant:
                    '[webcrack 輸出已依上限停止：$totalBytes/$_kWebcrackMaxOutputBytes bytes]',
                en: '[webcrack output stopped at limit: $totalBytes/$_kWebcrackMaxOutputBytes bytes]',
                fr: '[sortie webcrack arrêtée à la limite : $totalBytes/$_kWebcrackMaxOutputBytes bytes]',
                de: '[webcrack-Ausgabe am Limit gestoppt: $totalBytes/$_kWebcrackMaxOutputBytes bytes]',
                ja: '[webcrack 出力を上限で停止しました: $totalBytes/$_kWebcrackMaxOutputBytes bytes]',
              ),
            );
            break;
          }
          totalBytes += bytes;
          buf
            ..writeln('// ─── ${entity.path} ───')
            ..writeln(
              await _readWebcrackOutputFile(
                entity,
                locale: locale,
                totalTimeout: outputDeadline.remaining(),
              ),
            )
            ..writeln();
        }
      }
      if (listing.truncated) {
        buf.writeln(
          _advancedTextForLocale(
            locale,
            zh: '[webcrack 输出目录扫描达到安全上限，结果可能不完整]',
            zhHant: '[webcrack 輸出目錄掃描達到安全上限，結果可能不完整]',
            en: '[webcrack output scan reached its safety limit; results may be incomplete]',
            fr: '[l’analyse de la sortie webcrack a atteint sa limite de sécurité ; le résultat peut être incomplet]',
            de: '[Die webcrack-Ausgabesuche hat ihr Sicherheitslimit erreicht; das Ergebnis kann unvollständig sein]',
            ja: '[webcrack 出力の走査が安全上限に達したため、結果が不完全な可能性があります]',
          ),
        );
      }
      final s = buf.toString();
      return s.isEmpty
          ? _advancedTextForLocale(
              locale,
              zh: '[webcrack 无输出]',
              zhHant: '[webcrack 無輸出]',
              en: '[webcrack produced no output]',
              fr: '[webcrack n’a produit aucune sortie]',
              de: '[webcrack hat keine Ausgabe erzeugt]',
              ja: '[webcrack の出力はありません]',
            )
          : s;
    } finally {
      outputDeadline.stop();
    }
  } catch (error, stack) {
    silentLog('web_reverse_dashboard_dialog', '执行 webcrack', error, stack);
    return _advancedTextForLocale(
      locale,
      zh: '[执行异常]\n$error',
      zhHant: '[執行異常]\n$error',
      en: '[execution error]\n$error',
      fr: '[erreur d’exécution]\n$error',
      de: '[Ausfuhrungsfehler]\n$error',
      ja: '[実行エラー]\n$error',
    );
  } finally {
    final directory = tmpDir;
    if (directory != null) {
      try {
        await deletePathBounded(
          p.absolute(directory.path),
          policy: _kWebcrackTempDeletePolicy,
          allowedRoot: p.absolute(Directory.systemTemp.path),
        );
      } catch (error, stack) {
        silentLog(
          'web_reverse_dashboard_dialog',
          '删除 webcrack 临时文件',
          error,
          stack,
        );
      }
    }
  }
}

Future<String> _readWebcrackOutputFile(
  File file, {
  required Locale locale,
  required Duration totalTimeout,
}) async {
  final deadline = MonotonicDeadline(
    totalTimeout,
    timeoutMessage: '读取 webcrack 输出文件超过总时限。',
  );
  try {
    final bytes = await file.length().timeout(
      deadline.limit(_kWebcrackTempWriteTimeout),
    );
    if (bytes > _kWebcrackMaxOutputBytes) {
      return _advancedTextForLocale(
        locale,
        zh: '[webcrack 输出过大：$bytes bytes，limit $_kWebcrackMaxOutputBytes bytes]',
        zhHant:
            '[webcrack 輸出過大：$bytes bytes，limit $_kWebcrackMaxOutputBytes bytes]',
        en: '[webcrack output too large: $bytes bytes, limit $_kWebcrackMaxOutputBytes bytes]',
        fr: '[sortie webcrack trop volumineuse : $bytes bytes, limite $_kWebcrackMaxOutputBytes bytes]',
        de: '[webcrack-Ausgabe zu gross: $bytes bytes, Limit $_kWebcrackMaxOutputBytes bytes]',
        ja: '[webcrack 出力が大きすぎます: $bytes bytes, limit $_kWebcrackMaxOutputBytes bytes]',
      );
    }
    return await readBoundedFileString(
      file,
      maxBytes: _kWebcrackMaxOutputBytes,
      totalTimeout: deadline.remaining(),
    );
  } finally {
    deadline.stop();
  }
}

Future<void> _showInterceptRulesDialog(
  BuildContext context,
  WebReverseSessionController controller,
) async {
  await webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _InterceptRulesDialog(controller: controller),
  );
}

class _InterceptRulesDialog extends StatefulWidget {
  const _InterceptRulesDialog({required this.controller});
  final WebReverseSessionController controller;

  @override
  State<_InterceptRulesDialog> createState() => _InterceptRulesDialogState();
}

class _InterceptRulesDialogState extends State<_InterceptRulesDialog> {
  late List<WebReverseInterceptRule> _rules;

  @override
  void initState() {
    super.initState();
    _rules = [...widget.controller.interceptRules];
  }

  void _save() {
    widget.controller.setInterceptRules(_rules);
    context
        .findAncestorStateOfType<_WebReverseDashboardDialogState>()
        ?.persistInterceptRules();
    Navigator.of(context).pop();
  }

  Future<void> _editRule(int? index) async {
    if (index == null &&
        _rules.length >= WebReverseSessionController.maxInterceptRules) {
      return;
    }
    final initial = index == null
        ? const WebReverseInterceptRule(urlPattern: '')
        : _rules[index];
    final updated = await webReverseToolDialogs.show<WebReverseInterceptRule>(
      context: context,
      builder: (_) => _InterceptRuleEditor(initial: initial),
    );
    if (updated == null || !mounted) return;
    setState(() {
      if (index == null) {
        _rules.add(updated);
      } else {
        _rules[index] = updated;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthStandard,
      maxHeight: kOpenHandDialogHeightStandard,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.alt_route_rounded,
            title: openHandLocalizedText(
              context,
              zh: '网络拦截规则',
              zhHant: '網路攔截規則',
              en: 'Network intercept rules',
              fr: 'Règles d’interception réseau',
              de: 'Netzwerk-Abfangregeln',
              ja: 'ネットワークインターセプト規則',
            ),
            actions: [
              TextButton.icon(
                onPressed:
                    _rules.length >=
                        WebReverseSessionController.maxInterceptRules
                    ? null
                    : () => _editRule(null),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(
                  openHandLocalizedText(
                    context,
                    zh: '新增规则',
                    zhHant: '新增規則',
                    en: 'Add rule',
                    fr: 'Ajouter une règle',
                    de: 'Regel hinzufügen',
                    ja: '規則を追加',
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          Flexible(
            child: _rules.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      openHandLocalizedText(
                        context,
                        zh: '无规则。点「新增规则」开始：URL 通配 → block / 改写。\n命中规则的请求会自动放行/改写，不再走拦截队列。',
                        zhHant:
                            '無規則。點「新增規則」開始：URL 通配 → block / 改寫。\n命中規則的請求會自動放行/改寫，不再走攔截佇列。',
                        en: 'No rules. Click Add rule to start: URL pattern → block / rewrite.',
                        fr: 'Aucune règle. Ajoutez une règle : motif URL → block / rewrite.',
                        de: 'Keine Regeln. Regel hinzufügen: URL-Muster → block / rewrite.',
                        ja: '規則はありません。「規則を追加」から URL パターン → block / rewrite を設定します。',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _rules.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (_, i) {
                      final r = _rules[i];
                      return ListTile(
                        dense: true,
                        leading: Switch(
                          value: r.enabled,
                          onChanged: (v) {
                            setState(() {
                              _rules[i] = r.copyWith(enabled: v);
                            });
                          },
                        ),
                        title: Text(
                          r.urlPattern,
                          style: const TextStyle(
                            fontFamily: kOpenHandMonospaceFontFamily,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          r.block
                              ? openHandLocalizedText(
                                  context,
                                  zh: '动作: 屏蔽',
                                  zhHant: '動作: 屏蔽',
                                  en: 'Action: block',
                                  fr: 'Action : bloquer',
                                  de: 'Aktion: blockieren',
                                  ja: 'アクション: ブロック',
                                )
                              : r.replaceUrl != null && r.replaceUrl!.isNotEmpty
                              ? openHandLocalizedText(
                                  context,
                                  zh: '动作: 重定向到 ${r.replaceUrl}',
                                  zhHant: '動作: 重新導向到 ${r.replaceUrl}',
                                  en: 'Action: redirect → ${r.replaceUrl}',
                                  fr: 'Action : rediriger → ${r.replaceUrl}',
                                  de: 'Aktion: weiterleiten → ${r.replaceUrl}',
                                  ja: 'アクション: リダイレクト → ${r.replaceUrl}',
                                )
                              : r.headerOverrides.isEmpty
                              ? openHandLocalizedText(
                                  context,
                                  zh: '动作: 仅标记',
                                  zhHant: '動作: 僅標記',
                                  en: 'Action: tag only',
                                  fr: 'Action : marquer seulement',
                                  de: 'Aktion: nur markieren',
                                  ja: 'アクション: タグのみ',
                                )
                              : openHandLocalizedText(
                                  context,
                                  zh: '动作: 注入 ${r.headerOverrides.length} 个 header',
                                  zhHant:
                                      '動作: 注入 ${r.headerOverrides.length} 個 header',
                                  en: 'Action: inject ${r.headerOverrides.length} headers',
                                  fr: 'Action : injecter ${r.headerOverrides.length} headers',
                                  de: 'Aktion: ${r.headerOverrides.length} Header injizieren',
                                  ja: 'アクション: ${r.headerOverrides.length} 個の header を注入',
                                ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _wrEditLabel(context),
                              visualDensity: VisualDensity.compact,
                              iconSize: 18,
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 30,
                              ),
                              icon: const Icon(Icons.edit_rounded),
                              onPressed: () => _editRule(i),
                            ),
                            kOpenHandHGap4,
                            IconButton(
                              tooltip: openHandDeleteLabel(context),
                              visualDensity: VisualDensity.compact,
                              iconSize: 18,
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 30,
                              ),
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: cs.error,
                              ),
                              onPressed: () {
                                setState(() => _rules.removeAt(i));
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.secondary(
                  onPressed: () => Navigator.of(context).pop(),
                  label: openHandCancelLabel(context),
                ),
                kOpenHandHGap8,
                OpenHandDialogActionButton.primary(
                  onPressed: _save,
                  label: openHandSaveLabel(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InterceptRuleEditor extends StatefulWidget {
  const _InterceptRuleEditor({required this.initial});
  final WebReverseInterceptRule initial;

  @override
  State<_InterceptRuleEditor> createState() => _InterceptRuleEditorState();
}

class _InterceptRuleEditorState extends State<_InterceptRuleEditor> {
  late TextEditingController _patternCtrl;
  late TextEditingController _replaceCtrl;
  late TextEditingController _headersCtrl;
  late bool _enabled;
  late bool _block;

  @override
  void initState() {
    super.initState();
    _patternCtrl = TextEditingController(text: widget.initial.urlPattern);
    _replaceCtrl = TextEditingController(text: widget.initial.replaceUrl ?? '');
    _headersCtrl = TextEditingController(
      text: _formatHeaderLines(widget.initial.headerOverrides),
    );
    _enabled = widget.initial.enabled;
    _block = widget.initial.block;
  }

  @override
  void dispose() {
    _patternCtrl.dispose();
    _replaceCtrl.dispose();
    _headersCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return buildOpenHandAlertDialog(
      title: Text(
        openHandLocalizedText(
          context,
          zh: '编辑规则',
          zhHant: '編輯規則',
          en: 'Edit rule',
          fr: 'Modifier la règle',
          de: 'Regel bearbeiten',
          ja: '規則を編集',
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _patternCtrl,
                maxLength: WebReverseSessionController.maxBreakpointTextChars,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: 'URL 通配（* / ?）',
                    zhHant: 'URL 通配（* / ?）',
                    en: 'URL pattern (* / ?)',
                    fr: 'Motif URL (* / ?)',
                    de: 'URL-Muster (* / ?)',
                    ja: 'URL パターン（* / ?）',
                  ),
                  hintText: '*://api.example.com/v1/*',
                ),
              ),
              SwitchListTile(
                title: Text(
                  openHandLocalizedText(
                    context,
                    zh: '启用',
                    zhHant: '啟用',
                    en: 'Enabled',
                    fr: 'Active',
                    de: 'Aktiviert',
                    ja: '有効',
                  ),
                ),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              SwitchListTile(
                title: Text(
                  openHandLocalizedText(
                    context,
                    zh: '屏蔽请求 (Block)',
                    zhHant: '屏蔽請求 (Block)',
                    en: 'Block request',
                    fr: 'Bloquer la requête',
                    de: 'Anfrage blockieren',
                    ja: 'リクエストをブロック',
                  ),
                ),
                value: _block,
                onChanged: (v) => setState(() => _block = v),
              ),
              kOpenHandGap10,
              TextField(
                controller: _replaceCtrl,
                maxLength: WebReverseSessionController.maxBreakpointTextChars,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: '重写 URL（可选）',
                    zhHant: '重寫 URL（可選）',
                    en: 'Replace URL (optional)',
                    fr: 'Remplacer URL (optionnel)',
                    de: 'URL ersetzen (optional)',
                    ja: 'URL を置換（任意）',
                  ),
                  hintText: 'https://mock.local/v1/',
                ),
              ),
              kOpenHandGap10,
              TextField(
                controller: _headersCtrl,
                maxLength: WebReverseSessionController.maxRuleHeadersChars,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: 'Header 覆盖（每行 Key: Value）',
                    zhHant: 'Header 覆寫（每行 Key: Value）',
                    en: 'Header overrides (Key: Value per line)',
                    fr: 'Overrides headers (Key: Value par ligne)',
                    de: 'Header-Überschreibungen (Key: Value pro Zeile)',
                    ja: 'Header 上書き（1 行に Key: Value）',
                  ),
                  hintText: 'X-Debug: 1\nAuthorization: Bearer xxx',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: openHandCancelLabel(context),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () {
            Navigator.of(context).pop(
              WebReverseInterceptRule(
                urlPattern: _patternCtrl.text.trim(),
                enabled: _enabled,
                block: _block,
                replaceUrl: _replaceCtrl.text.trim().isEmpty
                    ? null
                    : _replaceCtrl.text.trim(),
                headerOverrides: _parseHeaderLines(_headersCtrl.text),
              ),
            );
          },
          label: openHandSaveLabel(context),
        ),
      ],
    );
  }
}

/// 单条 ICE 控制平面事件。kind = pc.create / track / datachannel /
/// icecandidate / (ice)connectionstatechange，payload 是原始 JSON 行。
class _IceEntry {
  const _IceEntry({required this.kind, required this.payload});
  final String kind;
  final Map<String, Object?> payload;
}

/// 一个 PeerConnection 的 local + remote SDP 当前 / 上一版本。Diff tab
/// 拿来做行级对比。
class _SdpPair {
  _SdpVersion? local;
  _SdpVersion? prevLocal;
  _SdpVersion? remote;
  _SdpVersion? prevRemote;
}

class _SdpVersion {
  const _SdpVersion({required this.type, required this.sdp});
  final String type;
  final String sdp;
}

/// SDP Diff 单列：上方标题 + 类型徽标，下方按行 diff 展示。
/// previous 为 null 时按全行"=="渲染，避免初次握手就一片绿洪水。
class _SdpDiffColumn extends StatelessWidget {
  const _SdpDiffColumn({
    required this.title,
    required this.current,
    required this.previous,
  });

  final String title;
  final _SdpVersion? current;
  final _SdpVersion? previous;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (current == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: webReverseSurfaceCardDecoration(cs),
        child: Text(
          title,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }
    final cur = current!;
    final prev = previous;
    final curLines = cur.sdp.split('\n');
    final prevLines = prev?.sdp.split('\n') ?? const <String>[];
    // 简化 diff：行级集合差。复杂度 O(n+m)，对 SDP 这种 ~50 行内容够用。
    final prevSet = prevLines.toSet();
    final curSet = curLines.toSet();
    final rows = <_SdpDiffRow>[];
    for (final ln in curLines) {
      rows.add(
        _SdpDiffRow(
          line: ln,
          kind: prevSet.contains(ln) ? _DiffKind.same : _DiffKind.added,
        ),
      );
    }
    if (prev != null) {
      for (final ln in prevLines) {
        if (!curSet.contains(ln)) {
          rows.add(_SdpDiffRow(line: ln, kind: _DiffKind.removed));
        }
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: webReverseSurfaceCardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              kOpenHandHGap8,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: kOpenHandBorderRadius6,
                ),
                child: Text(cur.type, style: theme.textTheme.labelSmall),
              ),
            ],
          ),
          kOpenHandGap8,
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                final color = switch (r.kind) {
                  _DiffKind.added => Colors.green.withValues(alpha: 0.18),
                  _DiffKind.removed => cs.error.withValues(alpha: 0.18),
                  _DiffKind.same => Colors.transparent,
                };
                final prefix = switch (r.kind) {
                  _DiffKind.added => '+ ',
                  _DiffKind.removed => '- ',
                  _DiffKind.same => '  ',
                };
                return Container(
                  color: color,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  child: SelectableText(
                    '$prefix${r.line}',
                    style: const TextStyle(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum _DiffKind { added, removed, same }

class _SdpDiffRow {
  const _SdpDiffRow({required this.line, required this.kind});
  final String line;
  final _DiffKind kind;
}

/// ICE 拓扑有向图：把当前 PC 收到的 candidate / track / datachannel 节
/// 点围着 PC 中心节点摆成放射状，根据来源画箭头。candidate 按 typ
/// 分组（host / srflx / relay / 其它）；track 按 media kind（audio /
/// video）；datachannel 单独一组。
/// 性能上限：candidate 取最近 12 条；track / datachannel 全量但通常不
/// 多，可放心整体绘制。InteractiveViewer 包外面，鼠标可缩放拖动查看。
class _IceTopologyGraph extends StatelessWidget {
  const _IceTopologyGraph({
    required this.pcId,
    required this.entries,
    required this.primary,
    required this.tertiary,
    required this.secondary,
    required this.error,
    required this.onSurface,
    required this.surfaceContainer,
  });

  final int pcId;
  final List<_IceEntry> entries;
  final Color primary;
  final Color tertiary;
  final Color secondary;
  final Color error;
  final Color onSurface;
  final Color surfaceContainer;

  @override
  Widget build(BuildContext context) {
    final nodes = _layoutNodes();
    return Container(
      decoration: BoxDecoration(
        color: surfaceContainer.withValues(alpha: 0.4),
        borderRadius: kOpenHandBorderRadius10,
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: kOpenHandBorderRadius10,
        child: InteractiveViewer(
          maxScale: 4,
          minScale: 0.5,
          child: SizedBox(
            width: 720,
            height: 420,
            child: CustomPaint(
              painter: _IceTopologyPainter(
                pcId: pcId,
                nodes: nodes,
                primary: primary,
                tertiary: tertiary,
                secondary: secondary,
                error: error,
                onSurface: onSurface,
                surfaceContainer: surfaceContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 把 entries 折叠成 _IceGraphNode 列表，附上分组信息让 painter 决定
  /// 角度 / 半径。candidate 取最近 12 条避免拥挤；同类型按时序排列。
  List<_IceGraphNode> _layoutNodes() {
    final out = <_IceGraphNode>[];
    final candidates = <_IceGraphNode>[];
    final tracks = <_IceGraphNode>[];
    final datachannels = <_IceGraphNode>[];
    String? lastConnState;
    for (final e in entries) {
      final p = e.payload;
      switch (e.kind) {
        case 'icecandidate':
          final cand = '${p['candidate'] ?? ''}';
          final m = RegExp(r'\btyp (\w+)').firstMatch(cand);
          final typ = m?.group(1) ?? '?';
          final m2 = RegExp(
            r'\b(udp|tcp)\s+\d+\s+(\S+)\s+(\d+)',
            caseSensitive: false,
          ).firstMatch(cand);
          final ip = m2?.group(2) ?? '?';
          final port = m2?.group(3) ?? '';
          candidates.add(
            _IceGraphNode(
              kind: _IceNodeKind.candidate,
              label: '$typ\n$ip:$port',
              typ: typ,
            ),
          );
        case 'track':
          tracks.add(
            _IceGraphNode(
              kind: _IceNodeKind.track,
              label: 'track\n${p['kind'] ?? '?'}',
              typ: '${p['kind'] ?? ''}',
            ),
          );
        case 'datachannel':
          datachannels.add(
            _IceGraphNode(
              kind: _IceNodeKind.datachannel,
              label: 'dc\n${p['label'] ?? ''}',
              typ: '',
            ),
          );
        case 'connectionstatechange':
        case 'iceconnectionstatechange':
          lastConnState = '${p['state'] ?? ''}';
      }
    }
    // 取最近 12 条 candidate 防图爆炸。
    final tail = candidates.length > 12
        ? candidates.sublist(candidates.length - 12)
        : candidates;
    out.addAll(tail);
    out.addAll(tracks);
    out.addAll(datachannels);
    return [
      _IceGraphNode(
        kind: _IceNodeKind.pc,
        label: 'PC #$pcId\n${lastConnState ?? "?"}',
        typ: lastConnState ?? '',
      ),
      ...out,
    ];
  }
}

enum _IceNodeKind { pc, candidate, track, datachannel }

class _IceGraphNode {
  const _IceGraphNode({
    required this.kind,
    required this.label,
    required this.typ,
  });
  final _IceNodeKind kind;
  final String label;
  final String typ;
}

class _IceTopologyPainter extends CustomPainter {
  _IceTopologyPainter({
    required this.pcId,
    required this.nodes,
    required this.primary,
    required this.tertiary,
    required this.secondary,
    required this.error,
    required this.onSurface,
    required this.surfaceContainer,
  });

  final int pcId;
  final List<_IceGraphNode> nodes;
  final Color primary;
  final Color tertiary;
  final Color secondary;
  final Color error;
  final Color onSurface;
  final Color surfaceContainer;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final pc = nodes.first;
    final others = nodes.skip(1).toList();
    final center = Offset(size.width / 2, size.height / 2);
    // 分组排布：candidate / track / datachannel 各自一段角度区间。
    final candidates = others
        .where((n) => n.kind == _IceNodeKind.candidate)
        .toList();
    final tracks = others.where((n) => n.kind == _IceNodeKind.track).toList();
    final datachannels = others
        .where((n) => n.kind == _IceNodeKind.datachannel)
        .toList();
    final positions = <_IceGraphNode, Offset>{};
    final radius = math.min(size.width, size.height) * 0.4;
    void place(List<_IceGraphNode> g, double startAngle, double endAngle) {
      if (g.isEmpty) return;
      if (g.length == 1) {
        final ang = (startAngle + endAngle) / 2;
        positions[g.first] =
            center + Offset(math.cos(ang) * radius, math.sin(ang) * radius);
        return;
      }
      final span = endAngle - startAngle;
      for (var i = 0; i < g.length; i++) {
        final ang = startAngle + span * i / (g.length - 1);
        positions[g[i]] =
            center + Offset(math.cos(ang) * radius, math.sin(ang) * radius);
      }
    }

    place(candidates, math.pi * 0.6, math.pi * 1.4);
    place(tracks, -math.pi * 0.45, math.pi * 0.45);
    place(datachannels, math.pi * 0.45, math.pi * 0.55);

    // 1) 先画连线：candidate → PC（蓝），PC → track / datachannel（橙 / 紫）。
    for (final entry in positions.entries) {
      final node = entry.key;
      final pos = entry.value;
      final color = switch (node.kind) {
        _IceNodeKind.candidate => primary.withValues(alpha: 0.7),
        _IceNodeKind.track => tertiary.withValues(alpha: 0.85),
        _IceNodeKind.datachannel => secondary.withValues(alpha: 0.85),
        _ => onSurface,
      };
      final from = node.kind == _IceNodeKind.candidate ? pos : center;
      final to = node.kind == _IceNodeKind.candidate ? center : pos;
      _drawArrow(canvas, from, to, color);
    }
    // 2) 画 PC 中心节点（圆形）。
    _drawPcNode(canvas, center, pc);
    // 3) 画外围节点。
    for (final entry in positions.entries) {
      final node = entry.key;
      final pos = entry.value;
      _drawNode(canvas, pos, node);
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dir = to - from;
    final dist = dir.distance;
    if (dist <= 1) return;
    // 箭头从节点边缘起，避免被节点 box 盖住。两端各留 26px。
    final unit = dir / dist;
    final start = from + unit * 26;
    final end = to - unit * 26;
    canvas.drawLine(start, end, paint);
    // 箭头三角。
    final ang = math.atan2(unit.dy, unit.dx);
    const arrowLen = 8.0;
    const arrowAng = 0.5;
    final p1 =
        end -
        Offset(math.cos(ang - arrowAng), math.sin(ang - arrowAng)) * arrowLen;
    final p2 =
        end -
        Offset(math.cos(ang + arrowAng), math.sin(ang + arrowAng)) * arrowLen;
    final tri = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(tri, Paint()..color = color);
  }

  void _drawPcNode(Canvas canvas, Offset center, _IceGraphNode node) {
    const r = 38.0;
    canvas.drawCircle(
      center,
      r,
      Paint()..color = primary.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = primary
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: node.label,
        style: TextStyle(
          color: onSurface,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          fontFamily: kOpenHandMonospaceFontFamily,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: r * 2 - 6);
    tp.paint(canvas, center + Offset(-tp.width / 2, -tp.height / 2));
  }

  void _drawNode(Canvas canvas, Offset pos, _IceGraphNode node) {
    final color = switch (node.kind) {
      _IceNodeKind.candidate => switch (node.typ) {
        'host' => primary,
        'srflx' => tertiary,
        'relay' => error,
        _ => secondary,
      },
      _IceNodeKind.track => tertiary,
      _IceNodeKind.datachannel => secondary,
      _ => onSurface,
    };
    final box = Rect.fromCenter(center: pos, width: 110, height: 36);
    final rrect = RRect.fromRectAndRadius(
      box,
      const Radius.circular(kOpenHandRadius8),
    );
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.22));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: node.label,
        style: TextStyle(
          color: onSurface,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          fontFamily: kOpenHandMonospaceFontFamily,
        ),
      ),
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 100);
    tp.paint(canvas, pos + Offset(-tp.width / 2, -tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _IceTopologyPainter old) =>
      old.nodes != nodes || old.pcId != pcId;
}
