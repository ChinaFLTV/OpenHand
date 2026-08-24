import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../../../app/model/dialog_animation_settings.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../app/theme/openhand_theme.dart';
import '../../../app/theme/openhand_theme_preset.dart';
import '../../../shared/ui/dialog_motion_css.dart';
import '../../../shared/util/localized_text.dart';
import '../ai_model_proxy_controller.dart';
import '../model/ai_model_proxy_models.dart';

const int _kStatusPagePhoneMaxPx = 640;
const int _kStatusPageCompactMaxPx = 720;
const int _kStatusPageTapMinPx = 44;
const int _kStatusHistoryMaxPx = 360;
const int _kStatusBarHeightPx = 34;
const int _kStatusBarPhoneHeightPx = 28;
const int _kStatusBarCoarseHeightPx = 40;
const double _kStatusBarHoverScale = 1.22;
const int _kStatusDotSizePx = 22;
const int _kStatusBannerDotSizePx = 26;
const int _kStatusMarkStrokePx = 2;

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
    zh: '可用性指标在所有层、模型和错误类型的聚合级别上报告。个别客户的可用性可能因其订阅层以及所使用的特定模型和API特性而异。',
    zhHant: '可用性指標在所有層、模型和錯誤類型的聚合層級上報告。個別客戶的可用性可能因其訂閱層以及所使用的特定模型和 API 特性而異。',
    en: 'Availability metrics are reported at an aggregate level across all tiers, models, and error types. Individual customer availability may vary depending on their subscription tier and the specific models and API features they use.',
    fr: 'Les indicateurs de disponibilité sont rapportés au niveau agrégé, tous paliers, modèles et types d’erreur confondus. La disponibilité individuelle d’un client peut varier selon son palier d’abonnement ainsi que les modèles et fonctionnalités d’API utilisés.',
    de: 'Verfügbarkeitskennzahlen werden aggregiert über alle Stufen, Modelle und Fehlertypen hinweg ausgewiesen. Die Verfügbarkeit einzelner Kunden kann je nach Abonnementstufe sowie den verwendeten Modellen und API-Funktionen abweichen.',
    ja: '可用性指標は、すべての階層・モデル・エラー種別を集約したレベルで報告されます。個別のお客様の可用性は、契約階層およびご利用のモデルや API 機能によって異なる場合があります。',
  );

  String get healthy => _t(
    zh: '正常运行',
    zhHant: '正常運作',
    en: 'Operational',
    fr: 'Opérationnel',
    de: 'Betriebsbereit',
    ja: '正常',
  );

  String get warning => _t(
    zh: '轻微波动',
    zhHant: '輕微波動',
    en: 'Minor disruption',
    fr: 'Perturbation légère',
    de: 'Leichte Beeinträchtigung',
    ja: '軽微な変動',
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
    zh: '近窗没有波动、降级或中断事件。',
    zhHant: '近窗沒有波動、降級或中斷事件。',
    en: 'No warning, degraded, or outage days in this window.',
    fr: 'Aucun jour perturbé, dégradé ou en panne dans cette fenêtre.',
    de: 'Keine Warnungen, Beeinträchtigungen oder Ausfälle in diesem Zeitraum.',
    ja: 'この期間に警告・劣化・障害の日はありません。',
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
      AiModelProxyHealth.warning => (
        _t(
          zh: '部分组件出现轻微波动',
          zhHant: '部分元件出現輕微波動',
          en: 'Minor service disruption',
          fr: 'Légère perturbation du service',
          de: 'Leichte Dienstbeeinträchtigung',
          ja: '一部のコンポーネントに軽微な変動があります',
        ),
        _t(
          zh: '部分组件成功率略低于健康线，或尾延迟开始升高，服务仍稳定可用。',
          zhHant: '部分元件成功率略低於健康線，或尾延遲開始升高，服務仍穩定可用。',
          en: 'Some components dipped slightly below the healthy band or showed rising tail latency, while service remains available.',
          fr: 'Certains composants passent légèrement sous la plage saine ou montrent une hausse de latence, mais le service reste disponible.',
          de: 'Einige Komponenten liegen knapp unter dem gesunden Bereich oder zeigen höhere Endlatenzen; der Dienst bleibt verfügbar.',
          ja: '一部のコンポーネントで成功率が健全域をわずかに下回るか、テールレイテンシが上昇していますが、サービスは利用可能です。',
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
          zh: '部分模型或网关成功率明显下降，或延迟持续偏高，部分请求可能失败或明显变慢。',
          zhHant: '部分模型或閘道成功率明顯下降，或延遲持續偏高，部分請求可能失敗或明顯變慢。',
          en: 'Some models or gateway periods have materially lower success or sustained latency. Requests may fail or slow down noticeably.',
          fr: 'Certains modèles ou créneaux de passerelle ont nettement moins de succès ou une latence durable. Des requêtes peuvent échouer ou ralentir sensiblement.',
          de: 'Einige Modelle oder Gateway-Zeiträume zeigen deutlich weniger Erfolg oder anhaltend hohe Latenz. Anfragen können fehlschlagen oder merklich langsamer werden.',
          ja: '一部のモデルやゲートウェイで成功率が大きく低下するか、高遅延が続いており、一部のリクエストが失敗または著しく遅くなる可能性があります。',
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
      AiModelProxyHealth.warning => _t(
        zh: '整体仍可用，但成功率略有回落或出现一定慢请求。',
        zhHant: '整體仍可用，但成功率略有回落或出現一定慢請求。',
        en: 'Service remained available, with a small success dip or some slow calls.',
        fr: 'Le service est resté disponible, avec une légère baisse du succès ou quelques appels lents.',
        de: 'Der Dienst blieb verfügbar, mit leicht gesunkener Erfolgsrate oder einigen langsamen Aufrufen.',
        ja: 'サービスは利用可能ですが、成功率がわずかに低下したか、低速リクエストが見られました。',
      ),
      AiModelProxyHealth.degraded => _t(
        zh: '成功率明显偏低或慢请求集中，用户体验已经受到影响。',
        zhHant: '成功率明顯偏低或慢請求集中，使用者體驗已經受到影響。',
        en: 'Success was materially lower or slow calls concentrated enough to affect users.',
        fr: 'Le succès a nettement baissé ou les appels lents se sont concentrés au point d’affecter les utilisateurs.',
        de: 'Die Erfolgsrate war deutlich niedriger oder langsame Aufrufe häuften sich spürbar.',
        ja: '成功率が大きく低下するか低速リクエストが集中し、利用体験に影響しています。',
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

  String get live => _t(
    zh: '实时',
    zhHant: '即時',
    en: 'Live',
    fr: 'En direct',
    de: 'Live',
    ja: 'ライブ',
  );

  String get liveHidden => _t(
    zh: '后台同步',
    zhHant: '背景同步',
    en: 'Syncing in background',
    fr: 'Sync. en arrière-plan',
    de: 'Hintergrundsync',
    ja: 'バックグラウンド同期',
  );

  String get liveError => _t(
    zh: '实时同步暂时中断，将自动重试。',
    zhHant: '即時同步暫時中斷，將自動重試。',
    en: 'Live sync paused. Retrying automatically.',
    fr: 'Sync. en pause. Nouvelle tentative automatique.',
    de: 'Live-Sync unterbrochen. Wiederholung folgt.',
    ja: 'ライブ同期が一時停止しました。自動で再試行します。',
  );

  String get justNow => _t(
    zh: '刚刚',
    zhHant: '剛剛',
    en: 'Just now',
    fr: 'À l’instant',
    de: 'Gerade eben',
    ja: 'たった今',
  );

  String get updatedAgo => _t(
    zh: '{n} 秒前',
    zhHant: '{n} 秒前',
    en: '{n}s ago',
    fr: 'il y a {n} s',
    de: 'vor {n} s',
    ja: '{n} 秒前',
  );

  String get updatedMinutesAgo => _t(
    zh: '{n} 分钟前',
    zhHant: '{n} 分鐘前',
    en: '{n}m ago',
    fr: 'il y a {n} min',
    de: 'vor {n} Min.',
    ja: '{n} 分前',
  );

  Map<String, String> get scriptLabels => <String, String>{
    'healthy': healthy,
    'warning': warning,
    'degraded': degraded,
    'outage': outage,
    'idle': idle,
    'components': componentSuffix,
    'requests': requests,
    'success': successRate,
    'failures': failures,
    'slow': slow,
    'noIncidents': noIncidents,
    'historyOpen': viewHistory,
    'historyClose': hideHistory,
    'live': live,
    'liveHidden': liveHidden,
    'liveError': liveError,
    'justNow': justNow,
    'updatedAgo': updatedAgo,
    'updatedMinutesAgo': updatedMinutesAgo,
  };
}

String buildAiModelProxyStatusUnavailablePage(Locale locale) {
  final copy = _StatusPageCopy.forLocale(locale);
  final lang = _statusPageLang(locale);
  return '<!DOCTYPE html><html lang="$lang"><head><meta charset="utf-8"><title>OpenHand</title></head><body>${_htmlEscape(copy.unavailable)}</body></html>';
}

Map<String, Object?> buildAiModelProxyStatusSnapshot({
  required AiModelProxyController controller,
  required ThemeMode themeMode,
  required OpenHandThemePreset themePreset,
  Locale? locale,
}) {
  return _assembleAiModelProxyStatusPage(
    controller: controller,
    themeMode: themeMode,
    themePreset: themePreset,
    locale: locale,
  ).toPayload();
}

String buildAiModelProxyStatusPage({
  required AiModelProxyController controller,
  required ThemeMode themeMode,
  required OpenHandThemePreset themePreset,
  Locale? locale,
  DialogAnimationSettings? dialogAnimation,
  bool reduceMotion = false,
}) {
  final view = _assembleAiModelProxyStatusPage(
    controller: controller,
    themeMode: themeMode,
    themePreset: themePreset,
    locale: locale,
  );
  final copy = view.copy;
  final lang = view.lang;
  final dark = view.dark;
  final cs = view.cs;
  final overall = view.overall;
  final banner = view.banner;
  final rangeLabel = view.rangeLabel;
  final payload = view.toPayload();
  final dialogMotion = dialogAnimation ?? OpenHandMotionDefaults.dialog;
  final motionRootAttrs = openHandDialogMotionHtmlRootAttributes(
    dialogMotion,
    reduceMotion: reduceMotion,
  );
  final motionCssVars = openHandDialogMotionCssCustomProperties(
    dialogMotion,
    reduceMotion: reduceMotion,
  );
  return '''<!DOCTYPE html>
<html lang="$lang" $motionRootAttrs>
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
  --caution: ${_healthCss(OpenHandStatusColors.caution)};
  --warn: ${_healthCss(OpenHandStatusColors.warning)};
  --bad: ${_healthCss(OpenHandStatusColors.error)};
  --idle: ${_cssHex(cs.onSurfaceVariant)};
  --banner: ${_cssHex(_bannerFill(cs, overall))};
  --banner-edge: ${_cssHex(_healthColor(overall))};
  --shadow: ${dark ? 'rgba(0,0,0,.28)' : 'rgba(15,23,42,.08)'};
  --radius: 18px;
  --pad: 18px;
  --bar-gap: 3px;
  --bar-h: ${_kStatusBarHeightPx}px;
  --bar-pop: $_kStatusBarHoverScale;
  --nest: 32px;
  --history-max: ${_kStatusHistoryMaxPx}px;
  --tip-shift-y: calc(-100% - 10px);
$motionCssVars
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
  background:
    radial-gradient(1100px 520px at 0% -10%, color-mix(in srgb, var(--ok) 14%, transparent), transparent 58%),
    radial-gradient(900px 460px at 100% 0%, color-mix(in srgb, var(--primary) 16%, transparent), transparent 52%),
    radial-gradient(720px 380px at 88% 100%, color-mix(in srgb, var(--caution) 10%, transparent), transparent 62%),
    var(--bg);
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
  gap: 12px; margin-bottom: 22px; flex-wrap: wrap;
}
.brand {
  display: flex; align-items: center; gap: 10px; font-weight: 800;
  font-size: clamp(18px, 4.2vw, 22px); letter-spacing: -.03em;
  min-width: 0;
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
.live {
  display: flex; align-items: center; gap: 8px;
  padding: 7px 12px 7px 10px; border-radius: 999px;
  border: 1px solid color-mix(in srgb, var(--ok) 42%, var(--outline));
  background:
    linear-gradient(135deg, color-mix(in srgb, var(--ok) 22%, var(--card)), color-mix(in srgb, var(--primary) 10%, var(--card)));
  box-shadow: 0 10px 24px color-mix(in srgb, var(--ok) 16%, transparent);
  min-height: ${_kStatusPageTapMinPx}px;
  flex: none;
}
.live-copy { display: flex; flex-direction: column; line-height: 1.15; min-width: 0; }
.live-label { font-size: 11px; font-weight: 800; letter-spacing: .08em; text-transform: uppercase; }
.live-time { font-size: 11px; font-weight: 700; color: var(--muted); }
.live-dot {
  width: 9px; height: 9px; border-radius: 50%; flex: none;
  background: var(--ok);
  box-shadow: 0 0 0 0 color-mix(in srgb, var(--ok) 55%, transparent);
  animation: live-pulse 1.8s var(--oh-spring) infinite;
}
.live[data-state="err"] {
  border-color: color-mix(in srgb, var(--bad) 48%, var(--outline));
  background: linear-gradient(135deg, color-mix(in srgb, var(--bad) 18%, var(--card)), var(--card));
  box-shadow: 0 10px 24px color-mix(in srgb, var(--bad) 16%, transparent);
}
.live[data-state="err"] .live-dot {
  background: var(--bad);
  animation: none;
  box-shadow: 0 0 0 4px color-mix(in srgb, var(--bad) 22%, transparent);
}
.live[data-state="idle"] {
  border-color: color-mix(in srgb, var(--caution) 40%, var(--outline));
  background: linear-gradient(135deg, color-mix(in srgb, var(--caution) 16%, var(--card)), var(--card));
}
.live[data-state="idle"] .live-dot {
  background: var(--caution);
  animation: live-pulse 2.4s var(--oh-spring) infinite;
}
.ghost-btn {
  border: 1px solid var(--outline); background: var(--card); color: var(--text);
  border-radius: 999px; padding: 10px 16px; font: inherit; font-weight: 700;
  cursor: pointer; appearance: none; -webkit-appearance: none;
  touch-action: manipulation; min-height: ${_kStatusPageTapMinPx}px;
  transition: transform var(--oh-hover-duration) var(--oh-spring), box-shadow var(--oh-hover-duration) var(--oh-dialog-curve), border-color var(--oh-hover-duration) ease;
}
.ghost-btn:focus-visible {
  outline: 2px solid var(--primary); outline-offset: 3px;
}
.ghost-btn:active { transform: scale(.96); }
@media (hover: hover) and (pointer: fine) {
  .ghost-btn:hover { transform: translateY(-2px) scale(1.03); box-shadow: 0 12px 28px var(--shadow); }
}
.banner {
  --tone: var(--banner-edge);
  border: 1px solid var(--banner-edge); border-radius: var(--radius); overflow: hidden;
  background:
    linear-gradient(135deg, color-mix(in srgb, var(--banner-edge) 18%, var(--card)), var(--card) 62%);
  margin-bottom: 18px;
  transform-origin: center;
  animation: rise var(--oh-dialog-enter-duration) var(--oh-dialog-curve) both;
  transition:
    border-color var(--oh-dialog-enter-duration) var(--oh-dialog-curve),
    background var(--oh-dialog-enter-duration) var(--oh-dialog-curve),
    box-shadow var(--oh-dialog-enter-duration) var(--oh-dialog-curve);
}
.banner.pulse { animation: banner-pulse var(--oh-dialog-enter-duration) var(--oh-spring); }
.banner[data-health="outage"] {
  box-shadow: 0 16px 36px color-mix(in srgb, var(--bad) 22%, transparent);
}
.banner-head {
  display: flex; align-items: center; gap: 10px;
  padding: 16px var(--pad); background: var(--banner); font-weight: 800;
  font-size: clamp(16px, 3.6vw, 18px); overflow-wrap: anywhere;
  transition: background var(--oh-dialog-enter-duration) var(--oh-dialog-curve);
}
.banner-body {
  padding: 14px var(--pad) 16px; color: var(--text); font-weight: 600;
  overflow-wrap: anywhere;
}
.card {
  background: var(--card); border: 1px solid var(--outline); border-radius: var(--radius);
  box-shadow: 0 16px 40px var(--shadow); overflow: hidden;
  animation: rise var(--oh-dialog-enter-duration) var(--oh-dialog-curve) backwards;
  animation-delay: 60ms;
}
.card-h {
  display: flex; align-items: baseline; justify-content: space-between;
  gap: 8px 12px; padding: 18px var(--pad) 14px; flex-wrap: wrap;
}
.card-h h2 { margin: 0; font-size: clamp(16px, 3.6vw, 18px); min-width: 0; }
.range { color: var(--muted); font-weight: 700; font-size: 13px; white-space: nowrap; }
.row {
  border-top: 1px solid color-mix(in srgb, var(--outline) 80%, transparent);
  padding: 16px var(--pad) 14px;
  overflow: visible;
}
#rows > .row.fresh,
.row.fresh {
  animation: rise var(--oh-dialog-enter-duration) var(--oh-dialog-curve) both;
  animation-delay: calc(var(--i, 0) * 40ms);
}
#rows > .row.exiting,
.row.exiting {
  animation: row-out var(--oh-dialog-exit-duration) var(--oh-dialog-exit-curve) both;
  pointer-events: none;
}
.row-h {
  display: flex; align-items: center; gap: 8px 10px;
  user-select: none; flex-wrap: wrap;
  transition: transform var(--oh-hover-duration) var(--oh-spring);
}
.row-h[data-toggle] { cursor: pointer; }
.row-h[data-toggle]::after {
  content: '';
  width: 8px; height: 8px; margin-left: 2px; flex: none;
  border-right: 2px solid var(--muted); border-bottom: 2px solid var(--muted);
  transform: rotate(45deg);
  opacity: .5;
  transition: transform var(--oh-dialog-enter-duration) var(--oh-spring), opacity var(--oh-hover-duration) ease;
}
.row.open > .row-h[data-toggle]::after {
  transform: rotate(225deg);
  opacity: .9;
}
.row-h[data-toggle]:focus-visible {
  outline: 2px solid var(--primary); outline-offset: 4px; border-radius: 10px;
}
@media (hover: hover) and (pointer: fine) {
  .row-h:hover .name { color: var(--primary); }
  .row-h[data-toggle]:hover { transform: translateX(2px); }
}
.dot {
  --dot-size: ${_kStatusDotSizePx}px;
  --mark-stroke: ${_kStatusMarkStrokePx}px;
  width: var(--dot-size); height: var(--dot-size); border-radius: 50%;
  position: relative; flex: none; line-height: 0;
  background: color-mix(in srgb, var(--tone) 18%, transparent); color: var(--tone);
  transform-origin: center;
  transition: background var(--oh-hover-duration) ease, color var(--oh-hover-duration) ease;
}
.dot.pulse { animation: dot-pulse var(--oh-dialog-enter-duration) var(--oh-spring); }
.banner-head .dot { --dot-size: ${_kStatusBannerDotSizePx}px; }
.dot::before, .dot::after {
  content: none; position: absolute; left: 50%; top: 50%;
  background: currentColor; pointer-events: none;
}
.dot[data-h="outage"]::before, .dot[data-h="outage"]::after {
  content: ''; width: 52%; height: var(--mark-stroke); border-radius: 999px;
}
.dot[data-h="outage"]::before { transform: translate(-50%, -50%) rotate(45deg); }
.dot[data-h="outage"]::after { transform: translate(-50%, -50%) rotate(-45deg); }
.dot[data-h="healthy"]::before {
  content: ''; width: 34%; height: 54%; background: none;
  border-right: var(--mark-stroke) solid currentColor;
  border-bottom: var(--mark-stroke) solid currentColor;
  border-radius: 0.5px;
  transform: translate(-50%, -58%) rotate(45deg);
}
.dot[data-h="warning"]::before, .dot[data-h="degraded"]::before {
  content: ''; width: var(--mark-stroke); height: 36%; border-radius: 999px;
  transform: translate(-50%, calc(-50% - 12%));
}
.dot[data-h="warning"]::after, .dot[data-h="degraded"]::after {
  content: ''; width: var(--mark-stroke); height: var(--mark-stroke); border-radius: 50%;
  transform: translate(-50%, calc(-50% + 26%));
}
.dot[data-h="idle"]::before {
  content: ''; width: 24%; height: 24%; border-radius: 50%;
  transform: translate(-50%, -50%);
}
.name { font-weight: 800; min-width: 0; overflow-wrap: anywhere; flex: 1 1 140px; }
.meta { color: var(--muted); font-size: 13px; font-weight: 650; }
.uptime {
  margin-left: auto; color: var(--muted); font-weight: 700; font-size: 13px;
  white-space: nowrap;
}
.tick { display: inline-block; animation: tick-pop var(--oh-dialog-enter-duration) var(--oh-spring); }
.bars {
  display: flex; gap: var(--bar-gap); margin-top: 10px;
  height: var(--bar-h);
  align-items: stretch; width: 100%; touch-action: manipulation;
  overflow: visible;
}
.bar {
  flex: 1 1 0; min-width: 0; height: 100%;
  position: relative;
  transform-origin: bottom center;
  cursor: pointer;
  transition: transform var(--oh-hover-duration) var(--oh-spring);
}
.bar-fill {
  display: block; width: 100%; height: 100%; border-radius: 3px;
  background: var(--fill); transform-origin: bottom center;
  pointer-events: none;
  animation: bar-in var(--oh-dialog-enter-duration) var(--oh-spring) backwards;
  animation-delay: calc(var(--i, 0) * 3ms);
  transition:
    background var(--oh-dialog-enter-duration) var(--oh-spring),
    opacity var(--oh-hover-duration) ease,
    box-shadow var(--oh-hover-duration) var(--oh-spring),
    filter var(--oh-hover-duration) ease;
}
.bar.pulse .bar-fill {
  animation: bar-pulse var(--oh-dialog-enter-duration) var(--oh-spring);
}
.bar.on {
  transform: scaleY(var(--bar-pop));
  z-index: 1;
}
.bar.on .bar-fill {
  filter: brightness(1.12);
  box-shadow: 0 10px 18px color-mix(in srgb, var(--fill) 36%, transparent);
}
@media (hover: hover) and (pointer: fine) {
  .bar:hover {
    transform: scaleY(var(--bar-pop));
    z-index: 1;
  }
  .bar:hover .bar-fill {
    filter: brightness(1.12);
    box-shadow: 0 10px 18px color-mix(in srgb, var(--fill) 36%, transparent);
  }
}
.children {
  display: grid;
  grid-template-rows: 0fr;
  opacity: 0;
  transform: translate3d(0, -8px, 0) scale(.985);
  padding: 0 0 0 var(--nest);
  transition:
    grid-template-rows var(--oh-dialog-exit-duration) var(--oh-dialog-exit-curve),
    opacity var(--oh-dialog-exit-duration) var(--oh-dialog-exit-curve),
    transform var(--oh-dialog-exit-duration) var(--oh-dialog-exit-curve),
    padding var(--oh-dialog-exit-duration) var(--oh-dialog-exit-curve);
}
.row.open > .children {
  grid-template-rows: 1fr;
  opacity: 1;
  transform: none;
  padding: 4px 0 0 var(--nest);
  transition:
    grid-template-rows var(--oh-dialog-enter-duration) var(--oh-spring),
    opacity var(--oh-dialog-enter-duration) var(--oh-dialog-curve),
    transform var(--oh-dialog-enter-duration) var(--oh-spring),
    padding var(--oh-dialog-enter-duration) var(--oh-dialog-curve);
}
.children > .reveal-inner { overflow: hidden; min-height: 0; }
.child { padding: 18px 0 8px; }
.foot { display: flex; justify-content: center; margin-top: 22px; }
.foot .ghost-btn { max-width: 100%; }
.reveal {
  display: grid;
  grid-template-rows: 0fr;
  opacity: 0;
  transform: translate3d(0, -10px, 0) scale(.98);
  margin-top: 0;
  transition:
    grid-template-rows var(--oh-dialog-exit-duration) var(--oh-dialog-exit-curve),
    opacity var(--oh-dialog-exit-duration) var(--oh-dialog-exit-curve),
    transform var(--oh-dialog-exit-duration) var(--oh-dialog-exit-curve),
    margin-top var(--oh-dialog-exit-duration) var(--oh-dialog-exit-curve);
}
.reveal.open {
  grid-template-rows: 1fr;
  opacity: 1;
  transform: none;
  margin-top: 18px;
  transition:
    grid-template-rows var(--oh-dialog-enter-duration) var(--oh-spring),
    opacity var(--oh-dialog-enter-duration) var(--oh-dialog-curve),
    transform var(--oh-dialog-enter-duration) var(--oh-spring),
    margin-top var(--oh-dialog-enter-duration) var(--oh-dialog-curve);
}
.reveal-inner { overflow: hidden; min-height: 0; }
.history { margin-top: 0; }
.incidents {
  padding: 0 var(--pad) 12px;
  max-height: min(var(--history-max), 52vh);
  overflow-x: hidden;
  overflow-y: auto;
  overscroll-behavior: contain;
  -webkit-overflow-scrolling: touch;
  scrollbar-gutter: stable;
  scrollbar-width: thin;
  scrollbar-color: color-mix(in srgb, var(--muted) 55%, transparent) transparent;
}
.incidents::-webkit-scrollbar { width: 8px; }
.incidents::-webkit-scrollbar-thumb {
  background: color-mix(in srgb, var(--muted) 45%, transparent);
  border-radius: 999px;
}
.incidents::-webkit-scrollbar-track { background: transparent; }
.incident {
  display: grid; grid-template-columns: 110px minmax(0, 1fr) auto; gap: 8px 12px;
  padding: 12px 10px; border-bottom: 1px solid color-mix(in srgb, var(--outline) 70%, transparent);
  border-left: 3px solid var(--tone, var(--outline));
  border-radius: 0 12px 12px 0;
  font-size: 13px; overflow-wrap: anywhere;
  transition: transform var(--oh-hover-duration) var(--oh-spring), background-color var(--oh-hover-duration) ease;
}
.incident:last-child { border-bottom: none; }
@media (hover: hover) and (pointer: fine) {
  .incident:hover {
    transform: translateX(4px);
    background: color-mix(in srgb, var(--tone, var(--primary)) 8%, transparent);
  }
}
.note {
  margin-top: 28px; text-align: center; color: var(--muted); font-size: 12px;
  max-width: 640px; margin-left: auto; margin-right: auto; overflow-wrap: anywhere;
  padding: 0 4px;
  animation: rise var(--oh-dialog-enter-duration) var(--oh-dialog-curve) both;
  animation-delay: 180ms;
}
.tip {
  position: fixed; z-index: 40; width: max-content;
  min-width: min(240px, calc(100vw - 24px));
  max-width: min(320px, calc(100vw - 24px));
  pointer-events: none; visibility: hidden;
  transform: translate(-50%, var(--tip-shift-y));
}
.tip.show { visibility: visible; }
.tip.below { --tip-shift-y: 10px; }
.tip-card {
  background: var(--card); color: var(--text); border: 1px solid var(--outline);
  border-radius: 16px; box-shadow: 0 18px 40px var(--shadow); padding: 12px 14px;
}
.tip b { display: block; font-size: 13px; margin-bottom: 4px; }
.tip .badge { font-size: 11px; font-weight: 800; color: var(--tone); }
.tip p { margin: 8px 0 0; font-size: 12px; color: var(--muted); overflow-wrap: anywhere; }
.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 8px; }
.tile { background: color-mix(in srgb, var(--tone) 10%, var(--bg-accent)); border-radius: 10px; padding: 7px 8px; min-width: 0; }
.tile span { display: block; font-size: 10px; color: var(--muted); font-weight: 700; }
.tile strong { font-size: 13px; overflow-wrap: anywhere; }
.sync-toast {
  position: fixed; left: 50%; bottom: max(20px, env(safe-area-inset-bottom, 0px));
  z-index: 50; width: max-content; max-width: min(420px, calc(100vw - 24px));
  transform: translateX(-50%);
  pointer-events: none; visibility: hidden;
}
.sync-toast.show { visibility: visible; }
.sync-card {
  background:
    linear-gradient(135deg, color-mix(in srgb, var(--bad) 16%, var(--card)), color-mix(in srgb, var(--warn) 10%, var(--card)));
  color: var(--text); border: 1px solid color-mix(in srgb, var(--bad) 40%, var(--outline));
  border-radius: 16px; box-shadow: 0 18px 40px var(--shadow);
  padding: 12px 16px; font-size: 13px; font-weight: 700;
  overflow-wrap: anywhere;
}
@keyframes rise { from { opacity: 0; transform: translateY(10px) scale(.98); } to { opacity: 1; transform: none; } }
@keyframes row-out { from { opacity: 1; transform: none; } to { opacity: 0; transform: translateY(-8px) scale(.98); } }
@keyframes bar-in { from { transform: scaleY(.12); opacity: .4; } to { transform: none; opacity: 1; } }
@keyframes bar-pulse {
  0% { transform: scaleY(1); }
  46% { transform: scaleY(1.22); }
  100% { transform: scaleY(1); }
}
@keyframes dot-pulse {
  0% { transform: scale(1); }
  48% { transform: scale(1.18); }
  100% { transform: scale(1); }
}
@keyframes banner-pulse {
  0% { transform: scale(1); }
  42% { transform: scale(1.012); }
  100% { transform: scale(1); }
}
@keyframes tick-pop {
  0% { transform: scale(1); }
  40% { transform: scale(1.06); }
  100% { transform: scale(1); }
}
@keyframes live-pulse {
  0% { box-shadow: 0 0 0 0 color-mix(in srgb, var(--ok) 50%, transparent); }
  70% { box-shadow: 0 0 0 8px transparent; }
  100% { box-shadow: 0 0 0 0 transparent; }
}
$kOpenHandDialogMotionStandaloneCss
@media (max-width: ${_kStatusPageCompactMaxPx}px) {
  :root { --pad: 14px; --nest: 20px; --bar-gap: 2px; }
  .foot .ghost-btn { width: 100%; }
  .range { white-space: normal; }
}
@media (max-width: ${_kStatusPagePhoneMaxPx}px) {
  :root { --radius: 16px; --bar-h: ${_kStatusBarPhoneHeightPx}px; --bar-gap: 1px; --nest: 14px; }
  .incident { grid-template-columns: 1fr; }
  .uptime { margin-left: 32px; }
  .live { width: 100%; justify-content: flex-start; }
}
@media (pointer: coarse) {
  :root { --bar-h: ${_kStatusBarCoarseHeightPx}px; }
  .bars { cursor: pointer; }
}
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation: none !important; transition: none !important;
  }
  .bar.on .bar-fill, .bar:hover .bar-fill { box-shadow: none; }
}
html[data-motion='reduced'] *,
html[data-motion='reduced'] *::before,
html[data-motion='reduced'] *::after {
  animation: none !important; transition: none !important;
}
html[data-motion='reduced'] .bar.on .bar-fill,
html[data-motion='reduced'] .bar:hover .bar-fill { box-shadow: none; }
</style>
</head>
<body>
<div class="wrap">
  <div class="top">
    <div class="brand">
      <img class="logo" src="$aiModelProxyLogoPath" width="36" height="36" alt="OpenHand">
      <div>OpenHand<small>${_htmlEscape(copy.brandSubtitle)}</small></div>
    </div>
    <div class="live" id="live" data-state="ok">
      <span class="live-dot" aria-hidden="true"></span>
      <span class="live-copy">
        <span class="live-label" id="live-label">${_htmlEscape(copy.live)}</span>
        <span class="live-time" id="live-time">${_htmlEscape(copy.justNow)}</span>
      </span>
    </div>
  </div>
  <section class="banner" id="banner" data-health="${overall.name}">
    <div class="banner-head">${_statusDotMarkup(overall)}<span id="banner-title">${_htmlEscape(banner.$1)}</span></div>
    <div class="banner-body" id="banner-body">${_htmlEscape(banner.$2)}</div>
  </section>
  <section class="card">
    <div class="card-h">
      <h2>${_htmlEscape(copy.systemStatus)}</h2>
      <div class="range" id="range">$rangeLabel</div>
    </div>
    <div id="rows"></div>
  </section>
  <div class="foot">
    <button class="ghost-btn" id="toggle-history" type="button" aria-controls="history-reveal" aria-expanded="false">${_htmlEscape(copy.viewHistory)}</button>
  </div>
  <div class="reveal" id="history-reveal" inert>
    <div class="reveal-inner">
      <section class="history card" id="history">
        <div class="card-h"><h2>${_htmlEscape(copy.incidentHistory)}</h2></div>
        <div class="incidents" id="incidents"></div>
      </section>
    </div>
  </div>
  <p class="note">${_htmlEscape(copy.footnote)}</p>
</div>
<div class="tip" id="tip" aria-hidden="true"><div class="tip-card" id="tip-card"></div></div>
<div class="sync-toast" id="sync-toast" aria-live="polite" aria-hidden="true"><div class="sync-card" id="sync-card"></div></div>
<script type="application/json" id="data">${_jsonForScript(payload)}</script>
<script>
let data = JSON.parse(document.getElementById('data').textContent);
const POLL_MS = $aiModelProxyStatusLivePollMs;
const POLL_HIDDEN_MS = $aiModelProxyStatusLivePollHiddenMs;
const POLL_TIMEOUT_MS = $aiModelProxyStatusLivePollTimeoutMs;
const POLL_BACKOFF_MAX_MS = $aiModelProxyStatusLivePollBackoffMaxMs;
const STATUS_JSON = '$aiModelProxyStatusJsonPath';
const rowsEl = document.getElementById('rows');
const tip = document.getElementById('tip');
const tipCard = document.getElementById('tip-card');
const inc = document.getElementById('incidents');
const histReveal = document.getElementById('history-reveal');
const histBtn = document.getElementById('toggle-history');
const coarse = window.matchMedia('(pointer: coarse)').matches;
let tipExitToken = 0;
let pinnedStrip = null;
let activeStrip = null;
let incidentSig = '';
let generatedAt = Date.parse(data.generatedAt) || Date.now();
let pollTimer = 0;
let clockTimer = 0;
let pollAbort = null;
let inflight = false;
let stopped = false;
let backoff = POLL_MS;
let etag = '';
let syncShown = false;

function i18n(){ return data.i18n || {}; }
function fillOf(h){
  const map = {healthy:data.ok, warning:data.caution, degraded:data.warn, outage:data.bad, idle:data.idle};
  return map[h] || data.idle;
}
function textOf(h){
  const labels = i18n();
  const map = {healthy:labels.healthy, warning:labels.warning, degraded:labels.degraded, outage:labels.outage, idle:labels.idle};
  return map[h] || h;
}
function attr(value){
  return String(value == null ? '' : value)
    .replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;').replace(/'/g,'&#39;');
}
function motionMs(kind){
  const root = document.documentElement;
  if (root.getAttribute('data-motion') === 'reduced') return 0;
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return 0;
  const attrName = kind === 'enter' ? 'data-dialog-enter' : 'data-dialog-exit';
  if (root.getAttribute(attrName) === 'none') return 0;
  const prop = kind === 'enter' ? '--oh-dialog-enter-duration' : '--oh-dialog-exit-duration';
  return parseFloat(getComputedStyle(root).getPropertyValue(prop)) || 0;
}
function afterMotion(el, kind, done){
  const ms = motionMs(kind);
  if (ms <= 0) { done(); return; }
  let finished = false;
  const finish = () => {
    if (finished) return;
    finished = true;
    el.removeEventListener('animationend', onEnd);
    clearTimeout(timer);
    done();
  };
  const onEnd = (ev) => { if (ev.target === el) finish(); };
  el.addEventListener('animationend', onEnd);
  const timer = setTimeout(finish, ms + 80);
}
function playDialog(el, kind){
  el.classList.remove('oh-dialog-pop-in', 'oh-dialog-pop-out');
  if (motionMs(kind) <= 0) return;
  void el.offsetWidth;
  el.classList.add(kind === 'enter' ? 'oh-dialog-pop-in' : 'oh-dialog-pop-out');
}
function bump(el, cls){
  if (!el) return;
  el.classList.remove(cls);
  if (motionMs('enter') <= 0) return;
  void el.offsetWidth;
  el.classList.add(cls);
  afterMotion(el, 'enter', () => el.classList.remove(cls));
}
function findComponent(id, list){
  const items = list || data.components || [];
  for (let i = 0; i < items.length; i++) {
    const c = items[i];
    if (!c) continue;
    if (c.id === id) return c;
    const hit = findComponent(id, c.children);
    if (hit) return hit;
  }
  return null;
}
function bars(days){
  return '<div class="bars">' + (days || []).map((d,i) => {
    const fill = fillOf(d.h);
    const alpha = d.h === 'idle' ? '.28' : '1';
    return '<div class="bar" data-i="'+i+'" style="--fill:'+fill+';--i:'+i+'"><span class="bar-fill" style="opacity:'+alpha+'"></span></div>';
  }).join('') + '</div>';
}
function row(c, nested){
  const labels = i18n();
  const count = c.children && c.children.length ? (c.children.length + (labels.components || '')) : '';
  const openable = c.children && c.children.length;
  return '<article class="row'+(nested?' child':'')+'" data-id="'+attr(c.id)+'" style="--tone:'+fillOf(c.health)+'">' +
    '<div class="row-h"'+(openable?' data-toggle="1" role="button" tabindex="0" aria-expanded="false"':'')+'>' +
      '<span class="dot" data-h="'+(c.health||'idle')+'" aria-hidden="true"></span><span class="name">'+c.name+'</span>' +
      (count ? '<span class="meta">'+count+'</span>' : '') +
      '<span class="uptime">'+(c.uptime || '—')+'</span></div>' +
    bars(c.days) +
    (openable ? '<div class="children" inert><div class="reveal-inner">'+c.children.map(ch => row(ch,true)).join('')+'</div></div>' : '') +
  '</article>';
}
function liveRows(container){
  return [...container.children].filter((el) => el.classList.contains('row') && !el.classList.contains('exiting'));
}
function mountRow(c, nested){
  const wrap = document.createElement('div');
  wrap.innerHTML = row(c, nested);
  return wrap.firstElementChild;
}
function patchBars(el, days){
  let strip = el.querySelector(':scope > .bars');
  const list = days || [];
  if (!list.length) {
    if (strip) strip.remove();
    return;
  }
  if (!strip) {
    const head = el.querySelector(':scope > .row-h');
    if (head) head.insertAdjacentHTML('afterend', bars(list));
    else el.insertAdjacentHTML('beforeend', bars(list));
    return;
  }
  if (strip.children.length !== list.length) {
    strip.outerHTML = bars(list);
    return;
  }
  for (let i = 0; i < list.length; i++) {
    const d = list[i];
    const bar = strip.children[i];
    const fill = fillOf(d.h);
    bar.setAttribute('data-i', String(i));
    if (bar.style.getPropertyValue('--fill') !== fill) {
      bar.style.setProperty('--fill', fill);
      bump(bar, 'pulse');
    }
    const span = bar.querySelector('.bar-fill');
    if (span) span.style.opacity = d.h === 'idle' ? '.28' : '1';
  }
}
function patchRow(el, c){
  const health = c.health || 'idle';
  el.style.setProperty('--tone', fillOf(health));
  const head = el.querySelector(':scope > .row-h');
  const dot = head && head.querySelector(':scope > .dot');
  if (dot && dot.getAttribute('data-h') !== health) {
    dot.setAttribute('data-h', health);
    bump(dot, 'pulse');
  }
  const name = head && head.querySelector(':scope > .name');
  if (name && name.innerHTML !== c.name) name.innerHTML = c.name;
  const count = c.children && c.children.length ? (c.children.length + (i18n().components || '')) : '';
  let meta = head && head.querySelector(':scope > .meta');
  if (count) {
    if (!meta && head) {
      meta = document.createElement('span');
      meta.className = 'meta';
      const uptimeEl = head.querySelector(':scope > .uptime');
      head.insertBefore(meta, uptimeEl);
    }
    if (meta && meta.textContent !== count) {
      meta.textContent = count;
      bump(meta, 'tick');
    }
  } else if (meta) {
    meta.remove();
  }
  const uptime = head && head.querySelector(':scope > .uptime');
  const nextUptime = c.uptime || '—';
  if (uptime && uptime.textContent !== nextUptime) {
    uptime.textContent = nextUptime;
    bump(uptime, 'tick');
  }
  const openable = !!(c.children && c.children.length);
  if (head) {
    if (openable) {
      if (!head.hasAttribute('data-toggle')) {
        head.setAttribute('data-toggle', '1');
        head.setAttribute('role', 'button');
        head.tabIndex = 0;
        head.setAttribute('aria-expanded', el.classList.contains('open') ? 'true' : 'false');
      }
    } else {
      head.removeAttribute('data-toggle');
      head.removeAttribute('role');
      head.removeAttribute('tabindex');
      head.removeAttribute('aria-expanded');
      el.classList.remove('open');
    }
  }
  patchBars(el, c.days || []);
  let kids = el.querySelector(':scope > .children');
  if (openable) {
    if (!kids) {
      kids = document.createElement('div');
      kids.className = 'children';
      kids.setAttribute('inert', '');
      kids.innerHTML = '<div class="reveal-inner"></div>';
      el.appendChild(kids);
    }
    const inner = kids.querySelector(':scope > .reveal-inner');
    if (inner) patchList(inner, c.children, true);
  } else if (kids) {
    kids.remove();
  }
}
function patchList(container, components, nested){
  const incoming = components || [];
  const prev = new Map();
  liveRows(container).forEach((el) => prev.set(el.getAttribute('data-id'), el));
  const used = new Set();
  incoming.forEach((c, index) => {
    used.add(c.id);
    let el = prev.get(c.id);
    const created = !el;
    if (!el) el = mountRow(c, nested);
    else patchRow(el, c);
    const current = liveRows(container);
    const ref = current[index];
    if (ref !== el) container.insertBefore(el, ref || null);
    if (created) {
      el.style.setProperty('--i', String(index));
      bump(el, 'fresh');
    }
  });
  prev.forEach((el, id) => {
    if (used.has(id)) return;
    if (activeStrip && el.contains(activeStrip)) releaseStrip();
    el.classList.add('exiting');
    afterMotion(el, 'exit', () => { if (el.parentNode) el.remove(); });
  });
}
function patchBanner(next){
  const banner = document.getElementById('banner');
  if (!banner) return;
  const health = next.health || 'idle';
  const prev = banner.getAttribute('data-health');
  banner.setAttribute('data-health', health);
  if (next.bannerFill) banner.style.setProperty('--banner', next.bannerFill);
  if (next.bannerEdge) banner.style.setProperty('--banner-edge', next.bannerEdge);
  const root = document.documentElement;
  ['ok','caution','warn','bad','idle'].forEach((key) => {
    if (next[key]) root.style.setProperty('--'+key, next[key]);
  });
  const dot = banner.querySelector('.banner-head > .dot');
  if (dot && dot.getAttribute('data-h') !== health) {
    dot.setAttribute('data-h', health);
    bump(dot, 'pulse');
  }
  const title = document.getElementById('banner-title');
  const body = document.getElementById('banner-body');
  const b = next.banner || {};
  if (title && b.title != null && title.textContent !== b.title) {
    title.textContent = b.title;
    bump(title, 'tick');
  }
  if (body && b.body != null && body.textContent !== b.body) body.textContent = b.body;
  if (prev && prev !== health) bump(banner, 'pulse');
}
function renderIncidents(items){
  const list = items || [];
  const sig = JSON.stringify(list);
  if (sig === incidentSig) return;
  incidentSig = sig;
  const labels = i18n();
  if (!list.length) {
    inc.innerHTML = '<p class="note" style="margin:8px 0 16px">'+(labels.noIncidents||'')+'</p>';
  } else {
    inc.innerHTML = list.map((item) => '<div class="incident" style="--tone:'+fillOf(item.level)+'"><strong>'+item.day+'</strong><span>'+item.name+' · '+textOf(item.level)+'</span><span>'+item.detail+'</span></div>').join('');
  }
  bump(inc, 'tick');
}
function applySnapshot(next){
  data = next;
  generatedAt = Date.parse(next.generatedAt) || Date.now();
  patchBanner(next);
  const range = document.getElementById('range');
  if (range && next.range && range.textContent !== next.range) {
    range.textContent = next.range;
    bump(range, 'tick');
  }
  patchList(rowsEl, next.components || [], false);
  renderIncidents(next.incidents || []);
  const labels = i18n();
  histBtn.textContent = histReveal.classList.contains('open')
    ? (labels.historyClose || histBtn.textContent)
    : (labels.historyOpen || histBtn.textContent);
  refreshOpenTip();
  renderLiveTime();
}
function toggleRow(el){
  const rowEl = el.closest('.row');
  const open = !rowEl.classList.contains('open');
  rowEl.classList.toggle('open', open);
  el.setAttribute('aria-expanded', open ? 'true' : 'false');
  const kids = rowEl.querySelector(':scope > .children');
  if (kids) kids.toggleAttribute('inert', !open);
  if (!open && activeStrip && rowEl.contains(activeStrip)) releaseStrip();
}
rowsEl.addEventListener('click', (ev) => {
  const toggle = ev.target.closest('[data-toggle]');
  if (!toggle || !rowsEl.contains(toggle)) return;
  toggleRow(toggle);
});
rowsEl.addEventListener('keydown', (ev) => {
  if (ev.key !== 'Enter' && ev.key !== ' ') return;
  const toggle = ev.target.closest('[data-toggle]');
  if (!toggle || !rowsEl.contains(toggle)) return;
  ev.preventDefault();
  toggleRow(toggle);
});
function dayIndex(strip, ev, n){
  const hit = ev.target && ev.target.closest ? ev.target.closest('.bar') : null;
  if (hit && strip.contains(hit)) {
    const i = parseInt(hit.getAttribute('data-i'), 10);
    if (Number.isFinite(i)) return Math.max(0, Math.min(n - 1, i));
  }
  const r = strip.getBoundingClientRect();
  if (n <= 0 || r.width <= 0) return 0;
  return Math.max(0, Math.min(n - 1, Math.floor(((ev.clientX - r.left) / r.width) * n)));
}
function clearOn(strip){
  if (!strip) return;
  strip.querySelectorAll('.bar.on').forEach((el) => el.classList.remove('on'));
}
function releaseStrip(){
  clearOn(activeStrip);
  activeStrip = null;
  pinnedStrip = null;
  hideTip();
}
function fillTip(d){
  const labels = i18n();
  tip.style.setProperty('--tone', fillOf(d.h));
  tipCard.innerHTML = '<b>'+d.d+'</b><span class="badge">'+(textOf(d.h))+'</span>' +
    '<div class="grid"><div class="tile"><span>'+labels.requests+'</span><strong>'+d.req+'</strong></div>' +
    '<div class="tile"><span>'+labels.success+'</span><strong>'+d.rate+'</strong></div>' +
    '<div class="tile"><span>'+labels.failures+'</span><strong>'+d.fail+'</strong></div>' +
    '<div class="tile"><span>'+labels.slow+'</span><strong>'+d.slow+'</strong></div></div>' +
    '<p>'+(d.note||'')+'</p>';
}
function revealFromEvent(ev){
  const strip = ev.target.closest && ev.target.closest('.bars');
  if (!strip || !rowsEl.contains(strip)) return;
  const rowEl = strip.closest('.row');
  const component = rowEl && findComponent(rowEl.getAttribute('data-id'));
  const days = (component && component.days) || [];
  const i = dayIndex(strip, ev, days.length);
  const d = days[i];
  const bar = strip.children[i];
  if (!d) return;
  if (activeStrip && activeStrip !== strip) clearOn(activeStrip);
  clearOn(strip);
  if (bar) bar.classList.add('on');
  activeStrip = strip;
  showTip(ev, d, bar || strip);
}
if (coarse) {
  rowsEl.addEventListener('pointerdown', (ev) => {
    const strip = ev.target.closest && ev.target.closest('.bars');
    if (!strip || !rowsEl.contains(strip)) return;
    pinnedStrip = strip;
    revealFromEvent(ev);
  });
  document.addEventListener('pointerdown', (ev) => {
    if (!pinnedStrip) return;
    if (pinnedStrip.contains(ev.target)) return;
    releaseStrip();
  });
} else {
  rowsEl.addEventListener('pointermove', revealFromEvent);
  rowsEl.addEventListener('pointerout', (ev) => {
    const strip = ev.target.closest && ev.target.closest('.bars');
    if (!strip || activeStrip !== strip) return;
    if (ev.relatedTarget && strip.contains(ev.relatedTarget)) return;
    releaseStrip();
  });
}
function showTip(ev, d, anchor){
  const leaving = tipCard.classList.contains('oh-dialog-pop-out');
  const wasHidden = !tip.classList.contains('show');
  tipExitToken += 1;
  fillTip(d);
  tip.classList.add('show');
  tip.setAttribute('aria-hidden', 'false');
  if (wasHidden || leaving) playDialog(tipCard, 'enter');
  moveTip(ev, anchor);
}
function hideTip(){
  if (!tip.classList.contains('show')) return;
  const token = ++tipExitToken;
  playDialog(tipCard, 'exit');
  afterMotion(tipCard, 'exit', () => {
    if (token !== tipExitToken) return;
    tip.classList.remove('show');
    tip.setAttribute('aria-hidden', 'true');
    tipCard.classList.remove('oh-dialog-pop-out');
  });
}
function refreshOpenTip(){
  if (!tip.classList.contains('show') || !activeStrip) return;
  const rowEl = activeStrip.closest('.row');
  const c = rowEl && findComponent(rowEl.getAttribute('data-id'));
  const i = [...activeStrip.children].findIndex((el) => el.classList.contains('on'));
  const d = c && c.days && c.days[i];
  if (!d) { hideTip(); return; }
  fillTip(d);
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
window.addEventListener('resize', () => { releaseStrip(); });
histBtn.addEventListener('click', () => {
  const open = !histReveal.classList.contains('open');
  histReveal.classList.toggle('open', open);
  histReveal.toggleAttribute('inert', !open);
  histBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
  const labels = i18n();
  histBtn.textContent = open ? (labels.historyClose || histBtn.textContent) : (labels.historyOpen || histBtn.textContent);
});
function formatAgo(from){
  const labels = i18n();
  const sec = Math.max(0, Math.round((Date.now() - from) / 1000));
  if (sec < 5) return labels.justNow || '';
  if (sec < 60) return String(labels.updatedAgo || '{n}').replace('{n}', String(sec));
  const min = Math.max(1, Math.round(sec / 60));
  return String(labels.updatedMinutesAgo || '{n}').replace('{n}', String(min));
}
function renderLiveTime(){
  const timeEl = document.getElementById('live-time');
  if (timeEl) timeEl.textContent = formatAgo(generatedAt);
}
function setSyncError(on){
  const toast = document.getElementById('sync-toast');
  const card = document.getElementById('sync-card');
  if (!toast || !card) return;
  if (on) {
    card.textContent = i18n().liveError || '';
    if (!syncShown) {
      toast.classList.add('show');
      toast.setAttribute('aria-hidden', 'false');
      playDialog(card, 'enter');
    }
    syncShown = true;
    return;
  }
  if (!syncShown) return;
  playDialog(card, 'exit');
  afterMotion(card, 'exit', () => {
    toast.classList.remove('show');
    toast.setAttribute('aria-hidden', 'true');
    card.classList.remove('oh-dialog-pop-out');
  });
  syncShown = false;
}
function markLive(ok){
  const live = document.getElementById('live');
  const labelEl = document.getElementById('live-label');
  const labels = i18n();
  if (live) live.setAttribute('data-state', ok ? (document.hidden ? 'idle' : 'ok') : 'err');
  if (labelEl) {
    labelEl.textContent = ok
      ? (document.hidden ? (labels.liveHidden || labels.live || '') : (labels.live || ''))
      : (labels.live || '');
  }
  setSyncError(!ok);
  renderLiveTime();
}
function nextDelay(ok){
  if (document.hidden) return Math.max(POLL_HIDDEN_MS, ok ? POLL_MS : backoff);
  return ok ? POLL_MS : backoff;
}
function schedule(delay){
  if (stopped) return;
  clearTimeout(pollTimer);
  pollTimer = setTimeout(tick, Math.max(250, delay || POLL_MS));
}
function stopPoll(){
  stopped = true;
  clearTimeout(pollTimer);
  clearTimeout(clockTimer);
  pollTimer = 0;
  clockTimer = 0;
  if (pollAbort) pollAbort.abort();
}
async function tick(){
  if (stopped || inflight) return;
  inflight = true;
  const ac = new AbortController();
  pollAbort = ac;
  const timeoutId = setTimeout(() => ac.abort(), POLL_TIMEOUT_MS);
  let ok = false;
  try {
    const headers = {};
    if (etag) headers['If-None-Match'] = etag;
    const res = await fetch(STATUS_JSON, {cache:'no-store', credentials:'same-origin', signal: ac.signal, headers: headers});
    if (res.status === 304) {
      ok = true;
      backoff = POLL_MS;
      markLive(true);
    } else {
      if (!res.ok) throw new Error('bad-status');
      const next = await res.json();
      if (!next || !Array.isArray(next.components)) throw new Error('bad-payload');
      const nextTag = res.headers.get('ETag') || '';
      if (nextTag) etag = nextTag;
      applySnapshot(next);
      ok = true;
      backoff = POLL_MS;
      markLive(true);
    }
  } catch (err) {
    if (!stopped) {
      backoff = Math.min(Math.max(backoff * 2, POLL_MS), POLL_BACKOFF_MAX_MS);
      markLive(false);
    }
  } finally {
    clearTimeout(timeoutId);
    inflight = false;
    if (pollAbort === ac) pollAbort = null;
    if (!stopped) schedule(nextDelay(ok));
  }
}
function startClock(){
  if (stopped) return;
  clockTimer = setTimeout(() => {
    renderLiveTime();
    startClock();
  }, 1000);
}
document.addEventListener('visibilitychange', () => {
  if (stopped) return;
  if (document.hidden) {
    const live = document.getElementById('live');
    if (live && live.getAttribute('data-state') !== 'err') markLive(true);
    return;
  }
  backoff = POLL_MS;
  markLive(true);
  if (!inflight) {
    clearTimeout(pollTimer);
    tick();
  }
});
window.addEventListener('pagehide', stopPoll);
window.addEventListener('beforeunload', stopPoll);
patchList(rowsEl, data.components || [], false);
renderIncidents(data.incidents || []);
markLive(true);
startClock();
schedule(POLL_MS);
</script>

</body>
</html>''';
}

class _StatusPageView {
  const _StatusPageView({
    required this.copy,
    required this.lang,
    required this.dark,
    required this.cs,
    required this.overall,
    required this.running,
    required this.rangeLabel,
    required this.banner,
    required this.components,
    required this.incidents,
    required this.days,
  });

  final _StatusPageCopy copy;
  final String lang;
  final bool dark;
  final ColorScheme cs;
  final AiModelProxyHealth overall;
  final bool running;
  final String rangeLabel;
  final (String, String) banner;
  final List<_StatusComponent> components;
  final List<Map<String, String>> incidents;
  final List<_StatusDay> days;

  Map<String, Object?> toPayload() => <String, Object?>{
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'health': overall.name,
    'running': running,
    'range': rangeLabel,
    'banner': <String, String>{'title': banner.$1, 'body': banner.$2},
    'bannerFill': _cssHex(_bannerFill(cs, overall)),
    'bannerEdge': _cssHex(_healthColor(overall)),
    'ok': _healthCss(OpenHandStatusColors.success),
    'caution': _healthCss(OpenHandStatusColors.caution),
    'warn': _healthCss(OpenHandStatusColors.warning),
    'bad': _healthCss(OpenHandStatusColors.error),
    'idle': _cssHex(cs.onSurfaceVariant),
    'components': [
      for (final component in components) component.toJson(days, copy),
    ],
    'incidents': incidents,
    'i18n': copy.scriptLabels,
  };
}

_StatusPageView _assembleAiModelProxyStatusPage({
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
  final apiDays = [
    for (final day in days) _subtractComponent(day.total, day.statusPage),
  ];
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
    days: apiDays,
    children: [
      _StatusComponent(
        id: 'api',
        name: settings.apiStyle.label,
        days: apiDays,
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
  final running = controller.lifecycle == AiModelProxyLifecycle.running;
  final overall = _worstHealth(<AiModelProxyHealth>[
    gateway.health,
    if (modelRows.isNotEmpty) models.health,
  ]);
  final start = days.isEmpty
      ? DateTime.now()
      : DateTime.tryParse(days.first.day);
  final end = days.isEmpty ? DateTime.now() : DateTime.tryParse(days.last.day);
  final incidentSources = <_StatusComponent>[
    gateway,
    ...gateway.children.where((child) => child.id == 'status-page'),
    if (modelRows.isNotEmpty) models,
    ...modelRows,
  ];
  return _StatusPageView(
    copy: copy,
    lang: lang,
    dark: dark,
    cs: cs,
    overall: overall,
    running: running,
    rangeLabel:
        '${_displayDay(start ?? DateTime.now())} – ${_displayDay(end ?? DateTime.now())}',
    banner: copy.banner(overall, running: running),
    components: components,
    incidents: [
      for (final component in incidentSources)
        for (var i = 0; i < component.days.length; i++)
          if (component.days[i].health == AiModelProxyHealth.warning ||
              component.days[i].health == AiModelProxyHealth.degraded ||
              component.days[i].health == AiModelProxyHealth.outage)
            <String, String>{
              'day': days[i].day,
              'name': _htmlEscape(component.name),
              'level': component.days[i].health.name,
              'detail': _htmlEscape(copy.daySummary(component.days[i])),
            },
    ],
    days: days,
  );
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
  int get slowCount => days.fold<int>(0, (sum, day) => sum + day.slowCount);
  AiModelProxyHealth get health => classifyAiModelProxyHealth(
    requests: requests,
    successes: successes,
    slowCount: slowCount,
  );

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
  var warning = false;
  var degraded = false;
  for (final value in values) {
    switch (value) {
      case AiModelProxyHealth.outage:
        return AiModelProxyHealth.outage;
      case AiModelProxyHealth.degraded:
        degraded = true;
        seen = true;
      case AiModelProxyHealth.warning:
        warning = true;
        seen = true;
      case AiModelProxyHealth.healthy:
        seen = true;
      case AiModelProxyHealth.idle:
        break;
    }
  }
  if (degraded) return AiModelProxyHealth.degraded;
  if (warning) return AiModelProxyHealth.warning;
  if (seen) return AiModelProxyHealth.healthy;
  return AiModelProxyHealth.idle;
}

String _statusDotMarkup(AiModelProxyHealth health) =>
    '<span class="dot" data-h="${health.name}" aria-hidden="true"></span>';

Color _healthColor(AiModelProxyHealth health) => switch (health) {
  AiModelProxyHealth.healthy => OpenHandStatusColors.success,
  AiModelProxyHealth.warning => OpenHandStatusColors.caution,
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
