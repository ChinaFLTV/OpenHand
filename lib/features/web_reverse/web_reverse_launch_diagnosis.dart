import 'package:flutter/widgets.dart';

import '../../shared/util/localized_text.dart';

/// 把 launcher 抛出的原始错误（标题 + stderr 摘要）解析成结构化诊断：
///   - 现象 phenomenon
///   - 根因 cause（可能多条命中）
///   - 建议 suggestion（针对每条 cause 的可操作建议）
///
/// 调用方拿到结构化结果后，可以渲染成"现象/原因/建议"三段式 UI，
/// 而不只是甩一段长 stderr 给用户。所有匹配规则都来自 Chromium
/// 源码里 stderr 高频字串，覆盖 macOS / Windows / Linux。
///
/// 如果没有任何规则命中，会回退到一条默认建议（关闭已开 Chrome、
/// 清理 SingletonLock 后重试），保证用户至少能拿到一条 next step。
class WebReverseLaunchDiagnosis {
  /// 把 launcher 抛出的 String 走规则匹配，返回结构化诊断。
  factory WebReverseLaunchDiagnosis.parse(
    String fullText, {
    Locale locale = const Locale('zh'),
  }) {
    final lower = fullText.toLowerCase();
    final matched = <WebReverseLaunchCause>[];
    bool has(List<String> needles) =>
        needles.any((n) => lower.contains(n.toLowerCase()));
    String text({
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

    // ① profile 锁占用：另一个 Chrome 实例咬着同一个 user-data-dir。
    if (has(const [
      'profile is in use',
      'profile is locked',
      'singletonlock',
      'cannot create lock',
      'failed to create temp dir',
      'lock file is held by another process',
    ])) {
      matched.add(
        WebReverseLaunchCause(
          title: text(
            zh: 'Profile 锁被另一个 Chrome 实例占用',
            zhHant: 'Profile 鎖被另一個 Chrome 實例占用',
            en: 'Profile lock is held by another Chrome instance',
            fr: 'Le verrou du profil est utilise par une autre instance Chrome',
            de: 'Profilsperre wird von einer anderen Chrome-Instanz gehalten',
            ja: 'プロファイルロックが別の Chrome インスタンスに保持されています',
          ),
          suggestion: text(
            zh: '关闭所有 Chrome 进程后，点击"清理冲突 profile"按钮删除 SingletonLock 等残留锁文件，再重试。',
            zhHant:
                '關閉所有 Chrome 行程後，點擊「清理衝突 profile」刪除 SingletonLock 等殘留鎖檔，再重試。',
            en: 'Close all Chrome processes, then use the profile cleanup action to remove leftover SingletonLock files and retry.',
            fr: 'Fermez tous les processus Chrome, nettoyez le profil en conflit pour supprimer les fichiers SingletonLock restants, puis reessayez.',
            de: 'Schliessen Sie alle Chrome-Prozesse, bereinigen Sie das betroffene Profil, um restliche SingletonLock-Dateien zu entfernen, und versuchen Sie es erneut.',
            ja: 'すべての Chrome プロセスを閉じ、競合プロファイルのクリーンアップで残った SingletonLock ファイルを削除してから再試行してください。',
          ),
        ),
      );
    }

    // ② 端口被占：另一个 CDP 实例在 9222-9322 区间。
    if (has(const [
      'address already in use',
      'failed to bind',
      'eaddrinuse',
      'already bound',
      'remote debugging port unavailable',
    ])) {
      matched.add(
        WebReverseLaunchCause(
          title: text(
            zh: '远端调试端口被占用',
            zhHant: '遠端除錯連接埠被占用',
            en: 'Remote debugging port is already in use',
            fr: 'Le port de debogage distant est deja utilise',
            de: 'Remote-Debugging-Port wird bereits verwendet',
            ja: 'リモートデバッグポートはすでに使用中です',
          ),
          suggestion: text(
            zh: '退出已存在的 Chrome / Edge / Brave 实例，或用 lsof / netstat 找到占用 9222-9322 的进程后再启动。',
            zhHant:
                '退出既有的 Chrome / Edge / Brave 實例，或用 lsof / netstat 找出占用 9222-9322 的行程後再啟動。',
            en: 'Quit existing Chrome / Edge / Brave instances, or use lsof / netstat to find the process using ports 9222-9322 before starting again.',
            fr: 'Quittez les instances Chrome / Edge / Brave existantes, ou utilisez lsof / netstat pour trouver le processus qui occupe les ports 9222-9322.',
            de: 'Beenden Sie vorhandene Chrome-/Edge-/Brave-Instanzen, oder suchen Sie mit lsof / netstat den Prozess auf den Ports 9222-9322.',
            ja: '既存の Chrome / Edge / Brave インスタンスを終了するか、lsof / netstat で 9222-9322 を使用しているプロセスを確認してから再起動してください。',
          ),
        ),
      );
    }

    // ③ 企业策略 / Origin 被拒：常见于公司机器。
    if (has(const [
      'remote-allow-origins',
      'devtools_remote_origin',
      'enterprise policy',
      'managed by your organization',
    ])) {
      matched.add(
        WebReverseLaunchCause(
          title: text(
            zh: '企业策略拒绝远端调试',
            zhHant: '企業政策拒絕遠端除錯',
            en: 'Enterprise policy blocks remote debugging',
            fr: 'Une strategie d entreprise bloque le debogage distant',
            de: 'Unternehmensrichtlinie blockiert Remote-Debugging',
            ja: '企業ポリシーがリモートデバッグをブロックしています',
          ),
          suggestion: text(
            zh: '检查 /Library/Managed Preferences/com.google.Chrome.plist（macOS）或注册表 HKLM\\Software\\Policies\\Google\\Chrome 是否禁用了 RemoteDebuggingAllowed；如确认无影响，可临时换一个个人浏览器（Brave / Chrome Beta）。',
            zhHant:
                '檢查 /Library/Managed Preferences/com.google.Chrome.plist（macOS）或登錄檔 HKLM\\Software\\Policies\\Google\\Chrome 是否停用了 RemoteDebuggingAllowed；若確認無影響，可暫時改用個人瀏覽器（Brave / Chrome Beta）。',
            en: 'Check whether RemoteDebuggingAllowed is disabled in /Library/Managed Preferences/com.google.Chrome.plist on macOS or HKLM\\Software\\Policies\\Google\\Chrome on Windows. If safe, try a personal browser such as Brave or Chrome Beta.',
            fr: 'Verifiez si RemoteDebuggingAllowed est desactive dans /Library/Managed Preferences/com.google.Chrome.plist sur macOS ou HKLM\\Software\\Policies\\Google\\Chrome sous Windows. Si possible, essayez un navigateur personnel comme Brave ou Chrome Beta.',
            de: 'Prufen Sie, ob RemoteDebuggingAllowed unter macOS in /Library/Managed Preferences/com.google.Chrome.plist oder unter Windows in HKLM\\Software\\Policies\\Google\\Chrome deaktiviert ist. Falls moglich, testen Sie einen personlichen Browser wie Brave oder Chrome Beta.',
            ja: 'macOS の /Library/Managed Preferences/com.google.Chrome.plist、または Windows の HKLM\\Software\\Policies\\Google\\Chrome で RemoteDebuggingAllowed が無効化されていないか確認してください。問題なければ Brave や Chrome Beta など個人用ブラウザを試してください。',
          ),
        ),
      );
    }

    // ④ 沙箱 / SUID 失败：典型 Linux 用户 + 部分 macOS 升级后的环境。
    if (has(const [
      'sandbox',
      'no usable sandbox',
      'suid sandbox',
      'failed to launch',
      'crash_handler',
    ])) {
      matched.add(
        WebReverseLaunchCause(
          title: text(
            zh: '沙箱初始化失败',
            zhHant: '沙箱初始化失敗',
            en: 'Sandbox initialization failed',
            fr: 'Echec de l initialisation du bac a sable',
            de: 'Sandbox-Initialisierung fehlgeschlagen',
            ja: 'サンドボックスの初期化に失敗しました',
          ),
          suggestion: text(
            zh: '在 Linux 上确保 /usr/lib/chromium-browser/chrome-sandbox 设置了 SUID；或临时使用 --no-sandbox 启动（仅作排错，正式使用务必恢复）。',
            zhHant:
                '在 Linux 上確認 /usr/lib/chromium-browser/chrome-sandbox 已設定 SUID；或暫時使用 --no-sandbox 啟動（僅供排錯，正式使用務必恢復）。',
            en: 'On Linux, ensure /usr/lib/chromium-browser/chrome-sandbox has SUID set, or temporarily start with --no-sandbox for diagnosis only.',
            fr: 'Sous Linux, verifiez que /usr/lib/chromium-browser/chrome-sandbox a le bit SUID, ou lancez temporairement avec --no-sandbox uniquement pour diagnostiquer.',
            de: 'Stellen Sie unter Linux sicher, dass /usr/lib/chromium-browser/chrome-sandbox SUID gesetzt hat, oder starten Sie nur zur Diagnose vorubergehend mit --no-sandbox.',
            ja: 'Linux では /usr/lib/chromium-browser/chrome-sandbox に SUID が設定されているか確認するか、診断時のみ一時的に --no-sandbox で起動してください。',
          ),
        ),
      );
    }

    // ⑤ GPU / Metal 初始化崩溃：macOS 升级 / 显卡驱动差。
    if (has(const [
      'gpu process',
      'metal',
      'angle',
      'vulkan',
      'gpu init failed',
      'gl error',
    ])) {
      matched.add(
        WebReverseLaunchCause(
          title: text(
            zh: 'GPU 进程初始化失败',
            zhHant: 'GPU 行程初始化失敗',
            en: 'GPU process initialization failed',
            fr: 'Echec de l initialisation du processus GPU',
            de: 'GPU-Prozess konnte nicht initialisiert werden',
            ja: 'GPU プロセスの初期化に失敗しました',
          ),
          suggestion: text(
            zh: '尝试加 --disable-gpu 启动（需要 launcher 配合开放 extra args），或更新显卡驱动 / 系统版本后重试。',
            zhHant:
                '嘗試加上 --disable-gpu 啟動（需要 launcher 開放 extra args），或更新顯卡驅動 / 系統版本後重試。',
            en: 'Try starting with --disable-gpu if the launcher exposes extra args, or update the GPU driver / OS version and retry.',
            fr: 'Essayez de demarrer avec --disable-gpu si le lanceur expose les arguments supplementaires, ou mettez a jour le pilote GPU / le systeme.',
            de: 'Starten Sie testweise mit --disable-gpu, falls der Launcher Zusatzargumente erlaubt, oder aktualisieren Sie Grafiktreiber bzw. Betriebssystem.',
            ja: 'ランチャーが追加引数を許可している場合は --disable-gpu で起動するか、GPU ドライバーまたは OS を更新して再試行してください。',
          ),
        ),
      );
    }

    // ⑥ 安全软件拦截 127.0.0.1：常见于 360 / Norton / Kaspersky。
    if (has(const [
      'connection refused',
      'access denied',
      'permission denied',
      'firewall',
    ])) {
      matched.add(
        WebReverseLaunchCause(
          title: text(
            zh: '安全软件 / 防火墙拦截 127.0.0.1 监听',
            zhHant: '安全軟體 / 防火牆攔截 127.0.0.1 監聽',
            en: 'Security software or firewall blocks 127.0.0.1 listening',
            fr: 'Un antivirus ou pare-feu bloque l ecoute sur 127.0.0.1',
            de: 'Sicherheitssoftware oder Firewall blockiert 127.0.0.1',
            ja: 'セキュリティソフトまたはファイアウォールが 127.0.0.1 の待受をブロックしています',
          ),
          suggestion: text(
            zh: '把 OpenHand.app 与浏览器可执行文件加入安全软件信任列表，并允许其监听 9222-9322 端口；macOS 上同时检查"系统设置 → 网络 → 防火墙"。',
            zhHant:
                '將 OpenHand.app 與瀏覽器可執行檔加入安全軟體信任清單，並允許其監聽 9222-9322 連接埠；macOS 上也請檢查「系統設定 → 網路 → 防火牆」。',
            en: 'Add OpenHand.app and the browser executable to the security allowlist, allow listening on ports 9222-9322, and on macOS check System Settings > Network > Firewall.',
            fr: 'Ajoutez OpenHand.app et le navigateur a la liste de confiance, autorisez les ports 9222-9322 et, sur macOS, verifiez Reglages Systeme > Reseau > Pare-feu.',
            de: 'Fugen Sie OpenHand.app und die Browser-Datei zur Vertrauensliste hinzu, erlauben Sie Ports 9222-9322 und prufen Sie unter macOS Systemeinstellungen > Netzwerk > Firewall.',
            ja: 'OpenHand.app とブラウザ実行ファイルを信頼リストに追加し、9222-9322 ポートの待受を許可してください。macOS では「システム設定 > ネットワーク > ファイアウォール」も確認してください。',
          ),
        ),
      );
    }

    // ⑦ 探测请求超时但 stderr 为空：纯网络/系统代理拦截。
    if (has(const ['cdp 握手超时', '握手超时', 'http 4', 'http 5']) &&
        matched.isEmpty) {
      matched.add(
        WebReverseLaunchCause(
          title: text(
            zh: '/json/version 探测请求被系统代理拦截',
            zhHant: '/json/version 探測請求被系統代理攔截',
            en: '/json/version probe was blocked by a system proxy',
            fr: 'La requete /json/version a ete bloquee par un proxy systeme',
            de: '/json/version-Abfrage wurde von einem Systemproxy blockiert',
            ja: '/json/version の検出リクエストがシステムプロキシにブロックされました',
          ),
          suggestion: text(
            zh: '检查系统是否启用了透明代理 / VPN / Proxifier 等会拦 127.0.0.1 流量的工具；OpenHand 的探测走纯本地，请把 127.0.0.1 加入代理白名单。',
            zhHant:
                '檢查系統是否啟用了透明代理 / VPN / Proxifier 等會攔截 127.0.0.1 流量的工具；OpenHand 的探測走純本地，請將 127.0.0.1 加入代理白名單。',
            en: 'Check transparent proxy, VPN, Proxifier or similar tools that may intercept 127.0.0.1 traffic. OpenHand probes locally, so add 127.0.0.1 to the proxy allowlist.',
            fr: 'Verifiez les proxys transparents, VPN, Proxifier ou outils similaires qui interceptent 127.0.0.1. OpenHand sonde localement, ajoutez donc 127.0.0.1 a la liste blanche.',
            de: 'Prufen Sie transparente Proxys, VPN, Proxifier oder ahnliche Tools, die 127.0.0.1 abfangen. OpenHand pruft lokal, daher 127.0.0.1 zur Proxy-Ausnahmeliste hinzufugen.',
            ja: '127.0.0.1 の通信を遮る透明プロキシ、VPN、Proxifier などを確認してください。OpenHand の検出はローカル通信なので、127.0.0.1 をプロキシの許可リストに追加してください。',
          ),
        ),
      );
    }

    // 默认兜底：至少给一条可操作建议。
    if (matched.isEmpty) {
      matched.add(
        WebReverseLaunchCause(
          title: text(
            zh: '未匹配到具体子类型',
            zhHant: '未匹配到具體子類型',
            en: 'No specific subtype matched',
            fr: 'Aucun sous-type precis ne correspond',
            de: 'Kein genauer Untertyp erkannt',
            ja: '具体的なサブタイプに一致しませんでした',
          ),
          suggestion: text(
            zh: '请展开下方"原始报错"按钮把详情复制给开发者；可先尝试关闭所有 Chrome 实例 + 点"清理冲突 profile" + 重试。',
            zhHant:
                '請展開下方「原始報錯」按鈕將詳情複製給開發者；可先嘗試關閉所有 Chrome 實例、點擊「清理衝突 profile」後重試。',
            en: 'Expand the raw error action and share the details with the developer. You can first close all Chrome instances, clean the conflicting profile, and retry.',
            fr: 'Ouvrez l action d erreur brute et transmettez les details au developpeur. Vous pouvez d abord fermer Chrome, nettoyer le profil en conflit, puis reessayer.',
            de: 'Offnen Sie die Rohfehlermeldung und geben Sie die Details an den Entwickler weiter. Schliessen Sie zuerst alle Chrome-Instanzen, bereinigen Sie das Profil und versuchen Sie es erneut.',
            ja: '原始エラーを展開して詳細を開発者に共有してください。先にすべての Chrome インスタンスを閉じ、競合プロファイルをクリーンアップして再試行できます。',
          ),
        ),
      );
    }

    // 现象提取：取第一行（launcher 已经把"现象"放在标题）。
    final phenomenon = fullText.split('\n').first.trim();
    return WebReverseLaunchDiagnosis(
      phenomenon: phenomenon.isEmpty
          ? text(
              zh: '浏览器启动失败',
              zhHant: '瀏覽器啟動失敗',
              en: 'Browser launch failed',
              fr: 'Echec du lancement du navigateur',
              de: 'Browserstart fehlgeschlagen',
              ja: 'ブラウザの起動に失敗しました',
            )
          : phenomenon,
      causes: matched,
      fullText: fullText,
    );
  }

  const WebReverseLaunchDiagnosis({
    required this.phenomenon,
    required this.causes,
    required this.fullText,
  });

  /// 现象一句话，如「CDP 握手超时」。
  final String phenomenon;

  /// 命中的根因列表，按可能性从高到低排列；至少含一条兜底。
  final List<WebReverseLaunchCause> causes;

  /// 原始 launcher 抛出的完整错误文案，提供给"原始报错"折叠区。
  final String fullText;
}

class WebReverseLaunchCause {
  const WebReverseLaunchCause({required this.title, required this.suggestion});
  final String title;
  final String suggestion;
}
