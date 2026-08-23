import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../app/theme/openhand_theme.dart';
import '../../../app/theme/openhand_theme_preset.dart';
import '../../../shared/util/localized_text.dart';
import '../ai_model_proxy_controller.dart';
import '../model/ai_model_proxy_models.dart';

const int _kStatusCopyAckMs = 1600;
const int _kStatusPagePhoneMaxPx = 640;
const int _kStatusPageCompactMaxPx = 720;
const int _kStatusPageTapMinPx = 44;

String _statusPageLang(Locale locale) {
  final ui = openHandSupportedUiLocale(locale);
  if (ui.languageCode != 'zh') return ui.languageCode;
  return ui.scriptCode?.toLowerCase() == 'hant' ? 'zh-Hant' : 'zh-Hans';
}

class _StatusPageCopy {
  _StatusPageCopy(this._t);

  factory _StatusPageCopy.forLocale(Locale locale) {
    return _StatusPageCopy(
      openHandTextResolverForLocale(openHandSupportedUiLocale(locale)),
    );
  }

  final OpenHandLocalizedTextResolver _t;

  String get title => _t(
    zh: '模型中转状态',
    zhHant: '模型中轉狀態',
    en: 'Model proxy status',
    fr: 'État du relais de modèles',
    de: 'Modell-Proxy-Status',
    ja: 'モデル中継ステータス',
  );

  String get brandSubtitle => _t(
    zh: 'AI 模型中转站状态',
    zhHant: 'AI 模型中轉站狀態',
    en: 'AI model proxy status',
    fr: 'État du relais de modèles IA',
    de: 'KI-Modell-Proxy-Status',
    ja: 'AI モデル中継の稼働状況',
  );

  String get copyLink => _t(
    zh: '复制状态页链接',
    zhHant: '複製狀態頁連結',
    en: 'Copy status URL',
    fr: 'Copier le lien d’état',
    de: 'Status-URL kopieren',
    ja: 'ステータスページのリンクをコピー',
  );

  String get copied => _t(
    zh: '已复制',
    zhHant: '已複製',
    en: 'Copied',
    fr: 'Copié',
    de: 'Kopiert',
    ja: 'コピーしました',
  );

  String get copyFailed => _t(
    zh: '复制失败，请手动复制地址',
    zhHant: '複製失敗，請手動複製地址',
    en: 'Copy failed; copy the address manually',
    fr: 'Échec de la copie ; copiez l’adresse manuellement',
    de: 'Kopieren fehlgeschlagen; Adresse manuell kopieren',
    ja: 'コピーに失敗しました。アドレスを手動でコピーしてください',
  );

  String get systemStatus => _t(
    zh: '系统状态',
    zhHant: '系統狀態',
    en: 'System status',
    fr: 'État du système',
    de: 'Systemstatus',
    ja: 'システムステータス',
  );

  String get viewHistory => _t(
    zh: '查看历史事件',
    zhHant: '查看歷史事件',
    en: 'View history',
    fr: 'Voir l’historique',
    de: 'Verlauf anzeigen',
    ja: '履歴を表示',
  );

  String get hideHistory => _t(
    zh: '收起历史事件',
    zhHant: '收起歷史事件',
    en: 'Hide history',
    fr: 'Masquer l’historique',
    de: 'Verlauf ausblenden',
    ja: '履歴を隠す',
  );

  String get incidentHistory => _t(
    zh: '历史事件',
    zhHant: '歷史事件',
    en: 'Incident history',
    fr: 'Historique des incidents',
    de: 'Ereignisverlauf',
    ja: '障害履歴',
  );

  String get footnote => _t(
    zh: '可用性按近 90 个自然日、在本中转站实际处理过的请求汇总。空闲灰格表示当天没有流量，不代表事故。状态页访问会计入网关遥测，但不计入暴露模型的成功率。',
    zhHant:
        '可用性按近 90 個自然日、在本中轉站實際處理過的請求彙總。空閒灰格表示當天沒有流量，不代表事故。狀態頁造訪會計入閘道遙測，但不計入暴露模型的成功率。',
    en: 'Availability covers the last 90 calendar days of traffic this proxy actually served. Gray means idle, not an outage. Status-page hits are gateway telemetry and are excluded from exposed-model success rates.',
    fr: 'La disponibilité couvre les 90 derniers jours de trafic réellement traité par ce relais. Le gris signifie inactif, pas une panne. Les visites de la page d’état relèvent de la télémétrie de la passerelle, pas du taux de succès des modèles exposés.',
    de: 'Die Verfügbarkeit umfasst die letzten 90 Kalendertage des tatsächlich von diesem Proxy verarbeiteten Traffics. Grau bedeutet Leerlauf, keinen Ausfall. Aufrufe der Statusseite zählen zur Gateway-Telemetrie, nicht zur Erfolgsrate bereitgestellter Modelle.',
    ja: '可用性は直近 90 日、この中継が実際に処理したリクエストで集計します。灰色はアイドルであり障害ではありません。ステータスページへのアクセスはゲートウェイ計測に含まれ、公開モデルの成功率には含めません。',
  );

  String get healthy => _t(
    zh: '正常运行',
    zhHant: '正常運作',
    en: 'Operational',
    fr: 'Opérationnel',
    de: 'Betriebsbereit',
    ja: '正常',
  );

  String get degraded => _t(
    zh: '服务降级',
    zhHant: '服務降級',
    en: 'Degraded',
    fr: 'Dégradé',
    de: 'Eingeschränkt',
    ja: '劣化',
  );

  String get outage => _t(
    zh: '服务中断',
    zhHant: '服務中斷',
    en: 'Outage',
    fr: 'Panne',
    de: 'Ausfall',
    ja: '障害',
  );

  String get idle => _t(
    zh: '空闲待命',
    zhHant: '空閒待命',
    en: 'Idle',
    fr: 'Inactif',
    de: 'Leerlauf',
    ja: 'アイドル',
  );

  String get componentSuffix => _t(
    zh: ' 个组件',
    zhHant: ' 個元件',
    en: ' components',
    fr: ' composants',
    de: ' Komponenten',
    ja: ' 件のコンポーネント',
  );

  String get requests => _t(
    zh: '请求',
    zhHant: '請求',
    en: 'Requests',
    fr: 'Requêtes',
    de: 'Anfragen',
    ja: 'リクエスト',
  );

  String get successRate => _t(
    zh: '成功率',
    zhHant: '成功率',
    en: 'Success',
    fr: 'Succès',
    de: 'Erfolg',
    ja: '成功率',
  );

  String get failures => _t(
    zh: '失败',
    zhHant: '失敗',
    en: 'Failures',
    fr: 'Échecs',
    de: 'Fehler',
    ja: '失敗',
  );

  String get slow => _t(
    zh: '慢请求',
    zhHant: '慢請求',
    en: 'Slow',
    fr: 'Lents',
    de: 'Langsam',
    ja: '低速',
  );

  String get noIncidents => _t(
    zh: '近窗没有降级或中断事件。',
    zhHant: '近窗沒有降級或中斷事件。',
    en: 'No degraded or outage days in this window.',
    fr: 'Aucun jour dégradé ou en panne dans cette fenêtre.',
    de: 'Keine Beeinträchtigung oder Ausfälle in diesem Fenster.',
    ja: 'この期間に劣化・障害の日はありません。',
  );

  String get uptimeSuffix => _t(
    zh: '可用',
    zhHant: '可用',
    en: 'uptime',
    fr: 'dispo.',
    de: 'verfügbar',
    ja: '稼働',
  );

  String get gateway => _t(
    zh: '中转网关',
    zhHant: '中轉閘道',
    en: 'Gateway',
    fr: 'Passerelle',
    de: 'Gateway',
    ja: '中継ゲートウェイ',
  );

  String get statusPage => _t(
    zh: '状态页',
    zhHant: '狀態頁',
    en: 'Status page',
    fr: 'Page d’état',
    de: 'Statusseite',
    ja: 'ステータスページ',
  );

  String get exposedModels => _t(
    zh: '暴露模型',
    zhHant: '暴露模型',
    en: 'Exposed models',
    fr: 'Modèles exposés',
    de: 'Bereitgestellte Modelle',
    ja: '公開モデル',
  );

  String get unavailable => _t(
    zh: '状态页暂不可用',
    zhHant: '狀態頁暫無法使用',
    en: 'Status unavailable.',
    fr: 'Page d’état indisponible.',
    de: 'Statusseite nicht verfügbar.',
    ja: 'ステータスページは利用できません。',
  );

  String get noTraffic => _t(
    zh: '无流量',
    zhHant: '無流量',
    en: 'No traffic',
    fr: 'Aucun trafic',
    de: 'Kein Traffic',
    ja: 'トラフィックなし',
  );

  (String, String) banner(AiModelProxyHealth health, {required bool running}) {
    return switch (health) {
      AiModelProxyHealth.healthy => (
        _t(
          zh: '对外中转整体运行正常',
          zhHant: '對外中轉整體運作正常',
          en: 'Fully operational',
          fr: 'Relais entièrement opérationnel',
          de: 'Vollständig betriebsbereit',
          ja: '中継は正常に稼働しています',
        ),
        _t(
          zh: '当前没有已知故障。近窗有流量的组件均处于健康阈值内。',
          zhHant: '目前沒有已知故障。近窗有流量的元件均處於健康閾值內。',
          en: 'No known issues. Components with traffic are within the healthy band.',
          fr: 'Aucun incident connu. Les composants avec du trafic sont dans la plage saine.',
          de: 'Keine bekannten Störungen. Komponenten mit Traffic liegen im gesunden Bereich.',
          ja: '既知の障害はありません。トラフィックのあるコンポーネントは健全な閾値内です。',
        ),
      ),
      AiModelProxyHealth.degraded => (
        _t(
          zh: '部分组件出现服务降级',
          zhHant: '部分元件出現服務降級',
          en: 'Partial degradation',
          fr: 'Dégradation partielle',
          de: 'Teilweise eingeschränkt',
          ja: '一部のコンポーネントが劣化しています',
        ),
        _t(
          zh: '部分模型或网关时段成功率偏低或尾延迟偏高，请求仍可完成。',
          zhHant: '部分模型或閘道時段成功率偏低或尾延遲偏高，請求仍可完成。',
          en: 'Some models or gateway hours are slower or less successful, but requests still complete.',
          fr: 'Certains modèles ou créneaux de passerelle sont plus lents ou moins fiables, mais les requêtes aboutissent encore.',
          de: 'Einige Modelle oder Gateway-Stunden sind langsamer oder weniger erfolgreich, Anfragen werden aber noch abgeschlossen.',
          ja: '一部のモデルやゲートウェイ時間帯で成功率低下や尾遅延がありますが、リクエストは完了します。',
        ),
      ),
      AiModelProxyHealth.outage => (
        _t(
          zh: '存在不可用组件',
          zhHant: '存在無法使用的元件',
          en: 'Incident in progress',
          fr: 'Incident en cours',
          de: 'Störung läuft',
          ja: '利用できないコンポーネントがあります',
        ),
        _t(
          zh: '至少一个组件在近窗出现了较高失败率，客户端可能已经感知中断。',
          zhHant: '至少一個元件在近窗出現較高失敗率，用戶端可能已經感知中斷。',
          en: 'At least one component had a high failure rate. Callers may have seen interruptions.',
          fr: 'Au moins un composant a eu un taux d’échec élevé. Les clients ont pu voir des interruptions.',
          de: 'Mindestens eine Komponente hatte eine hohe Fehlerrate. Aufrufer haben möglicherweise Unterbrechungen gesehen.',
          ja: '少なくとも 1 件のコンポーネントで失敗率が高く、呼び出し側は中断を検知している可能性があります。',
        ),
      ),
      AiModelProxyHealth.idle => (
        running
            ? _t(
                zh: '中转站已启动，等待流量',
                zhHant: '中轉站已啟動，等待流量',
                en: 'Proxy is up, waiting for traffic',
                fr: 'Relais démarré, en attente de trafic',
                de: 'Proxy läuft, wartet auf Traffic',
                ja: '中継は起動済みで、トラフィック待ちです',
              )
            : _t(
                zh: '暂无状态样本',
                zhHant: '暫無狀態樣本',
                en: 'No status samples yet',
                fr: 'Aucun échantillon d’état',
                de: 'Noch keine Statusdaten',
                ja: 'ステータスサンプルはまだありません',
              ),
        _t(
          zh: '近 90 天还没有可汇总的对外请求。灰格表示空闲待命，不代表事故。',
          zhHant: '近 90 天還沒有可彙總的對外請求。灰格表示空閒待命，不代表事故。',
          en: 'No public traffic in the last 90 days. Gray cells are idle, not an outage.',
          fr: 'Aucun trafic public sur 90 jours. Les cases grises sont inactives, pas une panne.',
          de: 'Kein öffentlicher Traffic in den letzten 90 Tagen. Graue Zellen sind Leerlauf, kein Ausfall.',
          ja: '直近 90 日に集計できる公開リクエストはありません。灰色はアイドルであり障害ではありません。',
        ),
      ),
    };
  }

  String daySummary(AiModelProxyDailyComponent day) {
    if (day.requests <= 0) return noTraffic;
    final percent = _percent(day.successRate);
    return _t(
      zh: '成功率 $percent · ${day.requests} 次',
      zhHant: '成功率 $percent · ${day.requests} 次',
      en: '$percent success · ${day.requests} calls',
      fr: '$percent de succès · ${day.requests} appels',
      de: '$percent Erfolg · ${day.requests} Aufrufe',
      ja: '成功率 $percent · ${day.requests} 件',
    );
  }

  String dayNote(AiModelProxyHealth health) {
    return switch (health) {
      AiModelProxyHealth.idle => _t(
        zh: '这一天没有该组件的请求样本，灰格表示空闲。',
        zhHant: '這一天沒有該元件的請求樣本，灰格表示空閒。',
        en: 'No samples for this component that day. Gray means idle.',
        fr: 'Aucun échantillon pour ce composant ce jour-là. Le gris signifie inactif.',
        de: 'Keine Stichproben für diese Komponente an diesem Tag. Grau bedeutet Leerlauf.',
        ja: 'この日、当該コンポーネントのサンプルはありません。灰色はアイドルです。',
      ),
      AiModelProxyHealth.healthy => _t(
        zh: '成功率与耗时都处于健康阈值内。',
        zhHant: '成功率與耗時都處於健康閾值內。',
        en: 'Success rate and latency stayed in the healthy band.',
        fr: 'Le taux de succès et la latence sont restés dans la plage saine.',
        de: 'Erfolgsrate und Latenz blieben im gesunden Bereich.',
        ja: '成功率とレイテンシは健全な閾値内でした。',
      ),
      AiModelProxyHealth.degraded => _t(
        zh: '仍可响应，但成功率偏低或慢请求偏多。',
        zhHant: '仍可回應，但成功率偏低或慢請求偏多。',
        en: 'Still serving, but success dipped or slow calls increased.',
        fr: 'Toujours en service, mais le succès a baissé ou les appels lents ont augmenté.',
        de: 'Weiterhin erreichbar, aber die Erfolgsrate sank oder langsame Aufrufe nahmen zu.',
        ja: '応答は継続していますが、成功率が低い、または低速呼び出しが増えています。',
      ),
      AiModelProxyHealth.outage => _t(
        zh: '失败过于集中，这一天应视为中断。',
        zhHant: '失敗過於集中，這一天應視為中斷。',
        en: 'Failures were concentrated enough to count as an outage.',
        fr: 'Les échecs étaient assez concentrés pour compter comme une panne.',
        de: 'Die Fehler waren konzentriert genug, um als Ausfall zu zählen.',
        ja: '失敗が集中しており、この日は障害と見なします。',
      ),
    };
  }

  Map<String, String> get scriptLabels => <String, String>{
    'healthy': healthy,
    'degraded': degraded,
    'outage': outage,
    'idle': idle,
    'components': componentSuffix,
    'requests': requests,
    'success': successRate,
    'failures': failures,
    'slow': slow,
    'noIncidents': noIncidents,
    'copyIdle': copyLink,
    'copyDone': copied,
    'copyFailed': copyFailed,
    'historyOpen': viewHistory,
    'historyClose': hideHistory,
  };
}

String buildAiModelProxyStatusUnavailablePage(Locale locale) {
  final copy = _StatusPageCopy.forLocale(locale);
  final lang = _statusPageLang(locale);
  return '<!DOCTYPE html><html lang="$lang"><head><meta charset="utf-8"><title>OpenHand</title></head><body>${_htmlEscape(copy.unavailable)}</body></html>';
}

String buildAiModelProxyStatusPage({
  required AiModelProxyController controller,
  required ThemeMode themeMode,
  required OpenHandThemePreset themePreset,
  Locale? locale,
}) {
  final copy = _StatusPageCopy.forLocale(locale ?? openHandAmbientLocale);
  final lang = _statusPageLang(locale ?? openHandAmbientLocale);
  final settings = controller.settings;
  final dark = _statusPageDark(themeMode);
  final theme = dark
      ? OpenHandTheme.dark(themePreset)
      : OpenHandTheme.light(themePreset);
  final cs = theme.colorScheme;
  final days = _statusDays(settings);
  final gatewayDays = [for (final day in days) day.total];
  final statusDays = [for (final day in days) day.statusPage];
  final modelIds = <String>{
    for (final route in settings.routes)
      if (route.enabled) route.exposedModel.trim(),
    for (final day in days) ...day.models.keys,
  }..removeWhere((id) => id.isEmpty || id == aiModelProxyStatusModelId);
  final modelRows = [
    for (final id in modelIds)
      _StatusComponent(
        id: id,
        name: id,
        days: [
          for (final day in days)
            day.models[id] ?? const AiModelProxyDailyComponent(),
        ],
      ),
  ]..sort((a, b) => b.requests.compareTo(a.requests));
  final gateway = _StatusComponent(
    id: 'gateway',
    name: copy.gateway,
    days: gatewayDays,
    children: [
      _StatusComponent(
        id: 'api',
        name: settings.apiStyle.label,
        days: [
          for (final day in days) _subtractComponent(day.total, day.statusPage),
        ],
      ),
      _StatusComponent(
        id: 'status-page',
        name: copy.statusPage,
        days: statusDays,
      ),
    ],
  );
  final models = _StatusComponent(
    id: 'models',
    name: copy.exposedModels,
    days: [for (final day in days) _sumComponents(day.models.values)],
    children: modelRows,
  );
  final components = <_StatusComponent>[
    gateway,
    if (modelRows.isNotEmpty) models,
  ];
  final overall = _worstHealth([
    for (final component in components) component.health,
  ]);
  final banner = copy.banner(
    overall,
    running: controller.lifecycle == AiModelProxyLifecycle.running,
  );
  final start = days.isEmpty
      ? DateTime.now()
      : DateTime.tryParse(days.first.day);
  final end = days.isEmpty ? DateTime.now() : DateTime.tryParse(days.last.day);
  final rangeLabel =
      '${_displayDay(start ?? DateTime.now())} – ${_displayDay(end ?? DateTime.now())}';
  final incidents = <Map<String, String>>[
    for (final component in [...components, ...modelRows])
      for (var i = 0; i < component.days.length; i++)
        if (component.days[i].health == AiModelProxyHealth.degraded ||
            component.days[i].health == AiModelProxyHealth.outage)
          <String, String>{
            'day': days[i].day,
            'name': _htmlEscape(component.name),
            'level': component.days[i].health.name,
            'detail': _htmlEscape(copy.daySummary(component.days[i])),
          },
  ];
  final payload = <String, Object?>{
    'ok': _healthCss(OpenHandStatusColors.success),
    'warn': _healthCss(OpenHandStatusColors.warning),
    'bad': _healthCss(OpenHandStatusColors.error),
    'idle': _cssHex(cs.onSurfaceVariant),
    'components': [
      for (final component in components) component.toJson(days, copy),
    ],
    'incidents': incidents,
    'i18n': copy.scriptLabels,
    'copyAckMs': _kStatusCopyAckMs,
  };
  return '''<!DOCTYPE html>
<html lang="$lang">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="${dark ? 'dark' : 'light'}">
<meta name="theme-color" content="${_cssHex(cs.primary)}">
<link rel="icon" type="image/png" href="$aiModelProxyLogoPath">
<link rel="shortcut icon" type="image/png" href="$aiModelProxyFaviconPath">
<link rel="apple-touch-icon" href="$aiModelProxyLogoPath">
<title>OpenHand · ${_htmlEscape(copy.title)}</title>
<style>
:root {
  --bg: ${_cssHex(cs.surface)};
  --bg-accent: ${_cssHex(cs.surfaceContainerLow)};
  --card: ${_cssHex(cs.surfaceContainerLowest)};
  --text: ${_cssHex(cs.onSurface)};
  --muted: ${_cssHex(cs.onSurfaceVariant)};
  --primary: ${_cssHex(cs.primary)};
  --primary-container: ${_cssHex(cs.primaryContainer)};
  --on-primary: ${_cssHex(cs.onPrimary)};
  --outline: ${_cssHex(cs.outlineVariant)};
  --ok: ${_healthCss(OpenHandStatusColors.success)};
  --warn: ${_healthCss(OpenHandStatusColors.warning)};
  --bad: ${_healthCss(OpenHandStatusColors.error)};
  --idle: ${_cssHex(cs.onSurfaceVariant)};
  --banner: ${_cssHex(_bannerFill(cs, overall))};
  --banner-edge: ${_cssHex(_healthColor(overall))};
  --shadow: ${dark ? 'rgba(0,0,0,.28)' : 'rgba(15,23,42,.08)'};
  --radius: 18px;
  --pad: 18px;
  --bar-gap: 3px;
  --bar-h: 34px;
  --nest: 32px;
  --tip-shift-y: calc(-100% - 10px);
}
* { box-sizing: border-box; }
html, body { margin: 0; min-height: 100%; }
html {
  -webkit-text-size-adjust: 100%;
  text-size-adjust: 100%;
  overflow-x: hidden;
}
body {
  font-family: "SF Pro Text", "Segoe UI", "PingFang SC", "PingFang TC", "Hiragino Sans GB", "Hiragino Kaku Gothic ProN", "Noto Sans SC", "Noto Sans TC", "Noto Sans JP", "Yu Gothic UI", "Meiryo", sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.45;
  overflow-x: hidden;
}
.wrap {
  width: min(920px, 100%);
  margin: 0 auto;
  padding: max(28px, env(safe-area-inset-top, 0px)) max(16px, env(safe-area-inset-right, 0px)) max(56px, env(safe-area-inset-bottom, 0px)) max(16px, env(safe-area-inset-left, 0px));
}
.top {
  display: flex; align-items: center; justify-content: space-between;
  gap: 12px 16px; margin-bottom: 22px; flex-wrap: wrap;
}
.brand {
  display: flex; align-items: center; gap: 10px; font-weight: 800;
  font-size: clamp(18px, 4.2vw, 22px); letter-spacing: -.03em;
  min-width: 0; flex: 1 1 220px;
}
.brand > div { min-width: 0; }
.brand small {
  display: block; font-size: 12px; font-weight: 600; color: var(--muted);
  letter-spacing: 0; overflow-wrap: anywhere;
}
.logo {
  width: 36px; height: 36px; border-radius: 12px; object-fit: contain;
  display: block; background: var(--card); flex: none;
}
.copy-btn, .ghost-btn {
  border: 1px solid var(--outline); background: var(--text); color: var(--bg);
  border-radius: 999px; padding: 10px 16px; font: inherit; font-weight: 700;
  cursor: pointer; appearance: none; -webkit-appearance: none;
  touch-action: manipulation; min-height: ${_kStatusPageTapMinPx}px;
  transition: transform 180ms cubic-bezier(.22,1.2,.36,1), box-shadow 180ms ease;
  flex: 0 0 auto;
}
.ghost-btn { background: var(--card); color: var(--text); }
.copy-btn:focus-visible, .ghost-btn:focus-visible {
  outline: 2px solid var(--primary); outline-offset: 3px;
}
@media (hover: hover) and (pointer: fine) {
  .copy-btn:hover, .ghost-btn:hover { transform: translateY(-1px) scale(1.02); box-shadow: 0 10px 24px var(--shadow); }
}
.banner {
  border: 1px solid var(--banner-edge); border-radius: var(--radius); overflow: hidden;
  background: var(--card); margin-bottom: 18px;
  animation: rise 420ms cubic-bezier(.22,1.2,.36,1);
}
.banner-head {
  display: flex; align-items: flex-start; gap: 10px;
  padding: 16px var(--pad); background: var(--banner); font-weight: 800;
  font-size: clamp(16px, 3.6vw, 18px); overflow-wrap: anywhere;
}
.banner-body {
  padding: 14px var(--pad) 16px; color: var(--text); font-weight: 600;
  overflow-wrap: anywhere;
}
.card {
  background: var(--card); border: 1px solid var(--outline); border-radius: var(--radius);
  box-shadow: 0 16px 40px var(--shadow); overflow: hidden;
  animation: rise 520ms cubic-bezier(.22,1.2,.36,1);
}
.card-h {
  display: flex; align-items: baseline; justify-content: space-between;
  gap: 8px 12px; padding: 18px var(--pad) 8px; flex-wrap: wrap;
}
.card-h h2 { margin: 0; font-size: clamp(16px, 3.6vw, 18px); min-width: 0; }
.range { color: var(--muted); font-weight: 700; font-size: 13px; white-space: nowrap; }
.row { border-top: 1px solid color-mix(in srgb, var(--outline) 80%, transparent); padding: 16px var(--pad) 14px; }
.row-h {
  display: flex; align-items: center; gap: 8px 10px; cursor: pointer;
  user-select: none; flex-wrap: wrap;
}
@media (hover: hover) and (pointer: fine) {
  .row-h:hover .name { color: var(--primary); }
}
.dot {
  width: 22px; height: 22px; border-radius: 50%; display: grid; place-items: center;
  background: color-mix(in srgb, var(--tone) 18%, transparent); color: var(--tone); flex: none;
}
.name { font-weight: 800; min-width: 0; overflow-wrap: anywhere; flex: 1 1 140px; }
.meta { color: var(--muted); font-size: 13px; font-weight: 650; }
.uptime {
  margin-left: auto; color: var(--muted); font-weight: 700; font-size: 13px;
  white-space: nowrap;
}
.bars {
  display: flex; gap: var(--bar-gap); margin-top: 10px; height: var(--bar-h);
  align-items: stretch; width: 100%; touch-action: manipulation;
}
.bar {
  flex: 1 1 0; min-width: 0; border-radius: 3px; background: var(--fill);
  transform-origin: bottom;
  transition: transform 160ms cubic-bezier(.22,1.2,.36,1), filter 160ms ease;
}
.bar.on { transform: scaleY(1.18); filter: brightness(1.12); }
@media (hover: hover) and (pointer: fine) {
  .bar:hover { transform: scaleY(1.18); filter: brightness(1.08); }
}
.children { display: none; padding: 4px 0 0 var(--nest); }
.row.open .children { display: block; animation: rise 240ms ease; }
.child { padding: 12px 0 8px; }
.foot { display: flex; justify-content: center; margin-top: 22px; }
.foot .ghost-btn { max-width: 100%; }
.history { display: none; margin-top: 18px; }
.history.open { display: block; animation: rise 280ms ease; }
.incidents { padding: 0 var(--pad) 12px; }
.incident {
  display: grid; grid-template-columns: 110px minmax(0, 1fr) auto; gap: 8px 12px;
  padding: 12px 0; border-bottom: 1px solid color-mix(in srgb, var(--outline) 70%, transparent);
  font-size: 13px; overflow-wrap: anywhere;
}
.note {
  margin-top: 28px; text-align: center; color: var(--muted); font-size: 12px;
  max-width: 640px; margin-left: auto; margin-right: auto; overflow-wrap: anywhere;
  padding: 0 4px;
}
.tip {
  position: fixed; z-index: 20; width: max-content;
  min-width: min(240px, calc(100vw - 24px));
  max-width: min(320px, calc(100vw - 24px));
  pointer-events: none;
  background: var(--card); color: var(--text); border: 1px solid var(--outline);
  border-radius: 16px; box-shadow: 0 18px 40px var(--shadow); padding: 12px 14px;
  transform: translate(-50%, var(--tip-shift-y)) scale(.96); opacity: 0;
  transition: opacity 140ms ease, transform 180ms cubic-bezier(.22,1.2,.36,1);
}
.tip.show { opacity: 1; transform: translate(-50%, var(--tip-shift-y)) scale(1); }
.tip.below { --tip-shift-y: 10px; }
.tip b { display: block; font-size: 13px; margin-bottom: 4px; }
.tip .badge { font-size: 11px; font-weight: 800; color: var(--tone); }
.tip p { margin: 8px 0 0; font-size: 12px; color: var(--muted); overflow-wrap: anywhere; }
.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 8px; }
.tile { background: color-mix(in srgb, var(--tone) 10%, var(--bg-accent)); border-radius: 10px; padding: 7px 8px; min-width: 0; }
.tile span { display: block; font-size: 10px; color: var(--muted); font-weight: 700; }
.tile strong { font-size: 13px; overflow-wrap: anywhere; }
@keyframes rise { from { opacity: 0; transform: translateY(10px) scale(.98); } to { opacity: 1; transform: none; } }
@media (max-width: ${_kStatusPageCompactMaxPx}px) {
  :root { --pad: 14px; --nest: 20px; --bar-gap: 2px; }
  .top { flex-direction: column; align-items: stretch; }
  .copy-btn, .foot .ghost-btn { width: 100%; }
  .range { white-space: normal; }
}
@media (max-width: ${_kStatusPagePhoneMaxPx}px) {
  :root { --radius: 16px; --bar-h: 28px; --bar-gap: 1px; --nest: 14px; }
  .incident { grid-template-columns: 1fr; }
  .uptime { margin-left: 32px; }
}
@media (pointer: coarse) {
  :root { --bar-h: 40px; }
  .bars { cursor: pointer; }
}
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation: none !important; transition: none !important;
  }
  .bar.on, .bar:hover { transform: none; }
}
</style>
</head>
<body>
<div class="wrap">
  <div class="top">
    <div class="brand">
      <img class="logo" src="$aiModelProxyLogoPath" width="36" height="36" alt="OpenHand">
      <div>OpenHand<small>${_htmlEscape(copy.brandSubtitle)}</small></div>
    </div>
    <button class="copy-btn" id="copy-link" type="button">${_htmlEscape(copy.copyLink)}</button>
  </div>
  <section class="banner">
    <div class="banner-head">${_bannerIcon(overall)} ${_htmlEscape(banner.$1)}</div>
    <div class="banner-body">${_htmlEscape(banner.$2)}</div>
  </section>
  <section class="card">
    <div class="card-h">
      <h2>${_htmlEscape(copy.systemStatus)}</h2>
      <div class="range">$rangeLabel</div>
    </div>
    <div id="rows"></div>
  </section>
  <div class="foot">
    <button class="ghost-btn" id="toggle-history" type="button">${_htmlEscape(copy.viewHistory)}</button>
  </div>
  <section class="history card" id="history">
    <div class="card-h"><h2>${_htmlEscape(copy.incidentHistory)}</h2></div>
    <div class="incidents" id="incidents"></div>
  </section>
  <p class="note">${_htmlEscape(copy.footnote)}</p>
</div>
<div class="tip" id="tip"></div>
<script type="application/json" id="data">${_jsonForScript(payload)}</script>
<script>
const data = JSON.parse(document.getElementById('data').textContent);
const i18n = data.i18n || {};
const tone = {healthy:data.ok, degraded:data.warn, outage:data.bad, idle:data.idle};
const label = {healthy:i18n.healthy, degraded:i18n.degraded, outage:i18n.outage, idle:i18n.idle};
const tip = document.getElementById('tip');
function bars(days){
  return '<div class="bars">' + days.map((d,i) => {
    const fill = tone[d.h] || data.idle;
    const alpha = d.h === 'idle' ? '.28' : '1';
    return '<div class="bar" data-i="'+i+'" style="--fill:'+fill+';opacity:'+alpha+'"></div>';
  }).join('') + '</div>';
}
function row(c, nested){
  const count = c.children && c.children.length ? (c.children.length + (i18n.components || '')) : '';
  const openable = c.children && c.children.length;
  return '<article class="row'+(nested?' child':'')+'" style="--tone:'+(tone[c.health]||data.idle)+'">' +
    '<div class="row-h"'+(openable?' data-toggle="1"':'')+'>' +
      '<span class="dot">✓</span><span class="name">'+c.name+'</span>' +
      (count ? '<span class="meta">'+count+'</span>' : '') +
      '<span class="uptime">'+(c.uptime || '—')+'</span></div>' +
    bars(c.days) +
    (openable ? '<div class="children">'+c.children.map(ch => row(ch,true)).join('')+'</div>' : '') +
  '</article>';
}
document.getElementById('rows').innerHTML = data.components.map(c => row(c,false)).join('');
document.querySelectorAll('[data-toggle]').forEach(el => {
  el.addEventListener('click', () => el.closest('.row').classList.toggle('open'));
});
const coarse = window.matchMedia('(pointer: coarse)').matches;
let pinnedStrip = null;
function dayIndex(strip, ev, n){
  const r = strip.getBoundingClientRect();
  if (n <= 0 || r.width <= 0) return 0;
  return Math.max(0, Math.min(n - 1, Math.floor(((ev.clientX - r.left) / r.width) * n)));
}
function clearOn(strip){
  strip.querySelectorAll('.bar.on').forEach(el => el.classList.remove('on'));
}
function bindTips(root, days){
  const strip = root.querySelector(':scope > .bars');
  if (!strip || !days || !days.length) return;
  const reveal = (ev) => {
    const i = dayIndex(strip, ev, days.length);
    const d = days[i];
    const bar = strip.children[i];
    if (!d) return;
    clearOn(strip);
    if (bar) bar.classList.add('on');
    showTip(ev, d, bar || strip);
  };
  if (coarse) {
    strip.addEventListener('pointerdown', (ev) => {
      pinnedStrip = strip;
      reveal(ev);
    });
  } else {
    strip.addEventListener('pointerenter', reveal);
    strip.addEventListener('pointermove', reveal);
    strip.addEventListener('pointerleave', () => {
      clearOn(strip);
      tip.classList.remove('show');
    });
  }
}
function walk(el, component){
  bindTips(el, component.days);
  (component.children || []).forEach((child, i) => {
    const node = el.querySelectorAll(':scope > .children > .row')[i];
    if (node) walk(node, child);
  });
}
document.querySelectorAll('#rows > .row').forEach((el, i) => walk(el, data.components[i]));
if (coarse) {
  document.addEventListener('pointerdown', (ev) => {
    if (!pinnedStrip) return;
    if (pinnedStrip.contains(ev.target)) return;
    clearOn(pinnedStrip);
    tip.classList.remove('show');
    pinnedStrip = null;
  });
}
function showTip(ev, d, anchor){
  tip.style.setProperty('--tone', tone[d.h] || data.idle);
  tip.innerHTML = '<b>'+d.d+'</b><span class="badge">'+(label[d.h]||d.h)+'</span>' +
    '<div class="grid"><div class="tile"><span>'+i18n.requests+'</span><strong>'+d.req+'</strong></div>' +
    '<div class="tile"><span>'+i18n.success+'</span><strong>'+d.rate+'</strong></div>' +
    '<div class="tile"><span>'+i18n.failures+'</span><strong>'+d.fail+'</strong></div>' +
    '<div class="tile"><span>'+i18n.slow+'</span><strong>'+d.slow+'</strong></div></div>' +
    '<p>'+(d.note||'')+'</p>';
  tip.classList.add('show');
  moveTip(ev, anchor);
}
function moveTip(ev, anchor){
  const pad = 12;
  const w = tip.offsetWidth || 240;
  const h = tip.offsetHeight || 160;
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  let x = ev.clientX, y = ev.clientY, below = false;
  if (anchor && anchor.getBoundingClientRect) {
    const r = anchor.getBoundingClientRect();
    x = r.left + r.width / 2;
    const canAbove = r.top - h - 12 >= pad;
    const canBelow = r.bottom + 12 + h <= vh - pad;
    below = !canAbove && canBelow;
    y = below ? r.bottom : r.top;
  } else {
    below = y - h - 12 < pad && y + 12 + h <= vh - pad;
  }
  const minX = w / 2 + pad;
  const maxX = vw - w / 2 - pad;
  x = minX > maxX ? vw / 2 : Math.max(minX, Math.min(maxX, x));
  tip.classList.toggle('below', below);
  tip.style.left = x + 'px';
  tip.style.top = y + 'px';
}
window.addEventListener('resize', () => {
  tip.classList.remove('show');
  if (pinnedStrip) {
    clearOn(pinnedStrip);
    pinnedStrip = null;
  }
});
const copyBtn = document.getElementById('copy-link');
let copyTimer = 0;
async function copyText(value){
  if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
    try { await navigator.clipboard.writeText(value); return true; } catch (_) {}
  }
  const area = document.createElement('textarea');
  area.value = value;
  area.setAttribute('readonly', '');
  area.style.position = 'fixed'; area.style.opacity = '0';
  document.body.appendChild(area);
  area.select();
  try {
    return typeof document.execCommand === 'function' && document.execCommand('copy');
  } catch (_) {
    return false;
  } finally {
    area.remove();
  }
}
copyBtn.addEventListener('click', async () => {
  const copied = await copyText(location.href);
  copyBtn.textContent = copied
    ? (i18n.copyDone || copyBtn.textContent)
    : (i18n.copyFailed || copyBtn.textContent);
  window.clearTimeout(copyTimer);
  copyTimer = window.setTimeout(() => {
    copyBtn.textContent = i18n.copyIdle || copyBtn.textContent;
  }, Number(data.copyAckMs) || 1600);
});
const hist = document.getElementById('history');
const histBtn = document.getElementById('toggle-history');
histBtn.addEventListener('click', () => {
  hist.classList.toggle('open');
  histBtn.textContent = hist.classList.contains('open')
    ? (i18n.historyClose || histBtn.textContent)
    : (i18n.historyOpen || histBtn.textContent);
});
const inc = document.getElementById('incidents');
if (!data.incidents.length) {
  inc.innerHTML = '<p class="note" style="margin:8px 0 16px">'+(i18n.noIncidents||'')+'</p>';
} else {
  inc.innerHTML = data.incidents.map(item => '<div class="incident"><strong>'+item.day+'</strong><span>'+item.name+' · '+(label[item.level]||item.level)+'</span><span>'+item.detail+'</span></div>').join('');
}
</script>
</body>
</html>''';
}

bool _statusPageDark(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system =>
      PlatformDispatcher.instance.platformBrightness == Brightness.dark,
  };
}

class _StatusDay {
  const _StatusDay({
    required this.day,
    required this.total,
    required this.statusPage,
    required this.models,
  });
  final String day;
  final AiModelProxyDailyComponent total;
  final AiModelProxyDailyComponent statusPage;
  final Map<String, AiModelProxyDailyComponent> models;
}

class _StatusComponent {
  const _StatusComponent({
    required this.id,
    required this.name,
    required this.days,
    this.children = const <_StatusComponent>[],
  });
  final String id;
  final String name;
  final List<AiModelProxyDailyComponent> days;
  final List<_StatusComponent> children;

  int get requests => days.fold<int>(0, (sum, day) => sum + day.requests);
  int get successes => days.fold<int>(0, (sum, day) => sum + day.successes);
  AiModelProxyHealth get health =>
      _worstHealth([for (final day in days) day.health]);

  double get successRate =>
      requests <= 0 ? 0 : (successes / requests).clamp(0.0, 1.0).toDouble();

  String uptimeLabel(String suffix) {
    if (requests <= 0) return '—';
    return '${(successRate * 100).toStringAsFixed(2)}% $suffix';
  }

  Map<String, Object?> toJson(
    List<_StatusDay> calendar,
    _StatusPageCopy copy,
  ) => <String, Object?>{
    'id': id,
    'name': _htmlEscape(name),
    'health': health.name,
    'uptime': uptimeLabel(copy.uptimeSuffix),
    'days': [
      for (var i = 0; i < days.length; i++)
        _dayJson(calendar[i].day, days[i], copy),
    ],
    if (children.isNotEmpty)
      'children': [for (final child in children) child.toJson(calendar, copy)],
  };
}

List<_StatusDay> _statusDays(AiModelProxySettings settings) {
  final today = DateTime.now();
  final start = DateTime(
    today.year,
    today.month,
    today.day,
  ).subtract(const Duration(days: aiModelProxyStatusHistoryDays - 1));
  final byDay = <String, AiModelProxyDailyHealth>{
    for (final item in settings.dailyHealth)
      if (item.day.isNotEmpty) item.day: item,
  };
  final known = byDay.keys.toSet();
  for (final record in settings.recentRequests) {
    final key = aiModelProxyDayKey(record.startedAt);
    if (key.isEmpty || known.contains(key)) continue;
    final current = byDay[key] ?? AiModelProxyDailyHealth(day: key);
    byDay[key] = current.add(record);
  }
  return [
    for (var i = 0; i < aiModelProxyStatusHistoryDays; i++)
      () {
        final date = start.add(Duration(days: i));
        final key = aiModelProxyDayKey(date);
        final item = byDay[key];
        return _StatusDay(
          day: key,
          total: item?.total ?? const AiModelProxyDailyComponent(),
          statusPage: item?.statusPage ?? const AiModelProxyDailyComponent(),
          models: item?.models ?? const <String, AiModelProxyDailyComponent>{},
        );
      }(),
  ];
}

AiModelProxyDailyComponent _subtractComponent(
  AiModelProxyDailyComponent total,
  AiModelProxyDailyComponent other,
) {
  final requests = total.requests - other.requests;
  if (requests <= 0) return const AiModelProxyDailyComponent();
  return AiModelProxyDailyComponent(
    requests: requests,
    successes: (total.successes - other.successes).clamp(0, requests),
    durationMs: (total.durationMs - other.durationMs).clamp(0, 1 << 52),
    slowCount: (total.slowCount - other.slowCount).clamp(0, requests),
  );
}

AiModelProxyDailyComponent _sumComponents(
  Iterable<AiModelProxyDailyComponent> items,
) {
  var requests = 0, successes = 0, durationMs = 0, slowCount = 0;
  for (final item in items) {
    requests += item.requests;
    successes += item.successes;
    durationMs += item.durationMs;
    slowCount += item.slowCount;
  }
  if (requests <= 0) return const AiModelProxyDailyComponent();
  return AiModelProxyDailyComponent(
    requests: requests,
    successes: successes,
    durationMs: durationMs,
    slowCount: slowCount,
  );
}

AiModelProxyHealth _worstHealth(Iterable<AiModelProxyHealth> values) {
  var seen = false;
  var degraded = false;
  for (final value in values) {
    switch (value) {
      case AiModelProxyHealth.outage:
        return AiModelProxyHealth.outage;
      case AiModelProxyHealth.degraded:
        degraded = true;
        seen = true;
      case AiModelProxyHealth.healthy:
        seen = true;
      case AiModelProxyHealth.idle:
        break;
    }
  }
  if (degraded) return AiModelProxyHealth.degraded;
  if (seen) return AiModelProxyHealth.healthy;
  return AiModelProxyHealth.idle;
}

String _bannerIcon(AiModelProxyHealth health) => switch (health) {
  AiModelProxyHealth.outage => '●',
  AiModelProxyHealth.degraded => '●',
  _ => '●',
};

Color _healthColor(AiModelProxyHealth health) => switch (health) {
  AiModelProxyHealth.healthy => OpenHandStatusColors.success,
  AiModelProxyHealth.degraded => OpenHandStatusColors.warning,
  AiModelProxyHealth.outage => OpenHandStatusColors.error,
  AiModelProxyHealth.idle => OpenHandStatusColors.info,
};

Color _bannerFill(ColorScheme cs, AiModelProxyHealth health) {
  return Color.lerp(cs.surface, _healthColor(health), 0.22) ?? cs.surface;
}

Map<String, Object?> _dayJson(
  String day,
  AiModelProxyDailyComponent stat,
  _StatusPageCopy copy,
) {
  final health = stat.health;
  return <String, Object?>{
    'd': day,
    'h': health.name,
    'req': stat.requests,
    'ok': stat.successes,
    'fail': stat.failures,
    'slow': stat.slowCount,
    'rate': stat.requests <= 0 ? '—' : _percent(stat.successRate),
    'note': copy.dayNote(health),
  };
}

String _percent(double rate) => '${(rate * 100).toStringAsFixed(1)}%';

String _displayDay(DateTime value) => aiModelProxyDayKey(value);

String _cssHex(Color color) {
  final argb = color.toARGB32();
  return '#${(argb & 0x00FFFFFF).toRadixString(16).padLeft(6, '0')}';
}

String _healthCss(Color color) => _cssHex(color);

String _jsonForScript(Object value) {
  return jsonEncode(value).replaceAll('<', r'\u003c');
}

String _htmlEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
