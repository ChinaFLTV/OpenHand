import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../app/theme/openhand_theme.dart';
import '../../../app/theme/openhand_theme_preset.dart';
import '../../../shared/util/localized_text.dart';
import '../ai_model_proxy_controller.dart';
import '../model/ai_model_proxy_models.dart';

String buildAiModelProxyStatusPage({
  required AiModelProxyController controller,
  required ThemeMode themeMode,
  required OpenHandThemePreset themePreset,
}) {
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
    name: openHandAmbientText(zh: '中转网关', en: 'Gateway'),
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
        name: openHandAmbientText(zh: '状态页', en: 'Status page'),
        days: statusDays,
      ),
    ],
  );
  final models = _StatusComponent(
    id: 'models',
    name: openHandAmbientText(zh: '暴露模型', en: 'Exposed models'),
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
  final banner = _bannerCopy(overall, controller);
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
            'detail': _htmlEscape(_daySummary(component.days[i])),
          },
  ];
  final payload = <String, Object?>{
    'ok': _healthCss(OpenHandStatusColors.success),
    'warn': _healthCss(OpenHandStatusColors.warning),
    'bad': _healthCss(OpenHandStatusColors.error),
    'idle': _cssHex(cs.onSurfaceVariant),
    'components': [for (final component in components) component.toJson(days)],
    'incidents': incidents,
  };
  final lang = openHandAmbientLocale.languageCode.toLowerCase().startsWith('zh')
      ? 'zh'
      : 'en';
  return '''<!DOCTYPE html>
<html lang="$lang">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="${dark ? 'dark' : 'light'}">
<title>OpenHand · ${openHandAmbientText(zh: '模型中转状态', en: 'Model proxy status')}</title>
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
}
* { box-sizing: border-box; }
html, body { margin: 0; min-height: 100%; }
body {
  font-family: "SF Pro Text", "Segoe UI", "PingFang SC", "Hiragino Sans GB", "Noto Sans SC", sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.45;
}
.wrap { width: min(920px, calc(100% - 32px)); margin: 0 auto; padding: 28px 0 64px; }
.top {
  display: flex; align-items: center; justify-content: space-between;
  gap: 16px; margin-bottom: 22px;
}
.brand { display: flex; align-items: center; gap: 10px; font-weight: 800; font-size: 22px; letter-spacing: -.03em; }
.brand small { display: block; font-size: 12px; font-weight: 600; color: var(--muted); letter-spacing: 0; }
.mark {
  width: 36px; height: 36px; border-radius: 12px;
  background: var(--primary);
  box-shadow: 0 8px 18px color-mix(in srgb, var(--primary) 28%, transparent);
}
.copy-btn, .ghost-btn {
  border: 1px solid var(--outline); background: var(--text); color: var(--bg);
  border-radius: 999px; padding: 9px 16px; font-weight: 700; cursor: pointer;
  transition: transform 180ms cubic-bezier(.22,1.2,.36,1), box-shadow 180ms ease;
}
.ghost-btn { background: var(--card); color: var(--text); }
.copy-btn:hover, .ghost-btn:hover { transform: translateY(-1px) scale(1.02); box-shadow: 0 10px 24px var(--shadow); }
.banner {
  border: 1px solid var(--banner-edge); border-radius: var(--radius); overflow: hidden;
  background: var(--card); margin-bottom: 18px;
  animation: rise 420ms cubic-bezier(.22,1.2,.36,1);
}
.banner-head {
  display: flex; align-items: center; gap: 10px;
  padding: 16px 18px; background: var(--banner); font-weight: 800; font-size: 18px;
}
.banner-body { padding: 14px 18px 16px; color: var(--text); font-weight: 600; }
.card {
  background: var(--card); border: 1px solid var(--outline); border-radius: var(--radius);
  box-shadow: 0 16px 40px var(--shadow); overflow: hidden;
  animation: rise 520ms cubic-bezier(.22,1.2,.36,1);
}
.card-h {
  display: flex; align-items: center; justify-content: space-between; gap: 12px;
  padding: 18px 18px 8px;
}
.card-h h2 { margin: 0; font-size: 18px; }
.range { color: var(--muted); font-weight: 700; font-size: 13px; }
.row { border-top: 1px solid color-mix(in srgb, var(--outline) 80%, transparent); padding: 16px 18px 14px; }
.row-h { display: flex; align-items: center; gap: 10px; cursor: pointer; user-select: none; }
.row-h:hover .name { color: var(--primary); }
.dot {
  width: 22px; height: 22px; border-radius: 50%; display: grid; place-items: center;
  background: color-mix(in srgb, var(--tone) 18%, transparent); color: var(--tone); flex: none;
}
.name { font-weight: 800; }
.meta { color: var(--muted); font-size: 13px; font-weight: 650; margin-left: 6px; }
.uptime { margin-left: auto; color: var(--muted); font-weight: 700; font-size: 13px; }
.bars { display: flex; gap: 3px; margin-top: 10px; height: 34px; align-items: stretch; }
.bar {
  flex: 1; min-width: 4px; border-radius: 4px; background: var(--fill);
  transform-origin: bottom; transition: transform 160ms cubic-bezier(.22,1.2,.36,1), filter 160ms ease;
}
.bar:hover { transform: scaleY(1.18); filter: brightness(1.08); }
.children { display: none; padding: 4px 0 0 32px; }
.row.open .children { display: block; animation: rise 240ms ease; }
.child { padding: 12px 0 8px; }
.foot { display: flex; justify-content: center; margin-top: 22px; }
.history { display: none; margin-top: 18px; }
.history.open { display: block; animation: rise 280ms ease; }
.incident {
  display: grid; grid-template-columns: 110px 1fr auto; gap: 12px; padding: 12px 0;
  border-bottom: 1px solid color-mix(in srgb, var(--outline) 70%, transparent);
  font-size: 13px;
}
.note { margin-top: 28px; text-align: center; color: var(--muted); font-size: 12px; max-width: 640px; margin-left: auto; margin-right: auto; }
.tip {
  position: fixed; z-index: 20; min-width: 240px; max-width: 320px; pointer-events: none;
  background: var(--card); color: var(--text); border: 1px solid var(--outline);
  border-radius: 16px; box-shadow: 0 18px 40px var(--shadow); padding: 12px 14px;
  transform: translate(-50%, calc(-100% - 10px)) scale(.96); opacity: 0;
  transition: opacity 140ms ease, transform 180ms cubic-bezier(.22,1.2,.36,1);
}
.tip.show { opacity: 1; transform: translate(-50%, calc(-100% - 10px)) scale(1); }
.tip b { display: block; font-size: 13px; margin-bottom: 4px; }
.tip .badge { font-size: 11px; font-weight: 800; color: var(--tone); }
.tip p { margin: 8px 0 0; font-size: 12px; color: var(--muted); }
.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 8px; }
.tile { background: color-mix(in srgb, var(--tone) 10%, var(--bg-accent)); border-radius: 10px; padding: 7px 8px; }
.tile span { display: block; font-size: 10px; color: var(--muted); font-weight: 700; }
.tile strong { font-size: 13px; }
@keyframes rise { from { opacity: 0; transform: translateY(10px) scale(.98); } to { opacity: 1; transform: none; } }
@media (max-width: 640px) {
  .incident { grid-template-columns: 1fr; }
  .uptime { display: none; }
}
</style>
</head>
<body>
<div class="wrap">
  <div class="top">
    <div class="brand">
      <span class="mark"></span>
      <div>OpenHand<small>${openHandAmbientText(zh: 'AI 模型中转站状态', en: 'AI model proxy status')}</small></div>
    </div>
    <button class="copy-btn" id="copy-link" type="button">${openHandAmbientText(zh: '复制状态页链接', en: 'Copy status URL')}</button>
  </div>
  <section class="banner">
    <div class="banner-head">${_bannerIcon(overall)} ${banner.$1}</div>
    <div class="banner-body">${banner.$2}</div>
  </section>
  <section class="card">
    <div class="card-h">
      <h2>${openHandAmbientText(zh: '系统状态', en: 'System status')}</h2>
      <div class="range">$rangeLabel</div>
    </div>
    <div id="rows"></div>
  </section>
  <div class="foot">
    <button class="ghost-btn" id="toggle-history" type="button">${openHandAmbientText(zh: '查看历史事件', en: 'View history')}</button>
  </div>
  <section class="history card" id="history">
    <div class="card-h"><h2>${openHandAmbientText(zh: '历史事件', en: 'Incident history')}</h2></div>
    <div id="incidents" style="padding: 0 18px 12px;"></div>
  </section>
  <p class="note">${openHandAmbientText(zh: '可用性按近 90 个自然日、在本中转站实际处理过的请求汇总。空闲灰格表示当天没有流量，不代表事故。状态页访问会计入网关遥测，但不计入暴露模型的成功率。', en: 'Availability covers the last 90 calendar days of traffic this proxy actually served. Gray means idle, not an outage. Status-page hits are gateway telemetry and are excluded from exposed-model success rates.')}</p>
</div>
<div class="tip" id="tip"></div>
<script type="application/json" id="data">${_jsonForScript(payload)}</script>
<script>
const data = JSON.parse(document.getElementById('data').textContent);
const tone = {healthy:data.ok, degraded:data.warn, outage:data.bad, idle:data.idle};
const label = {
  healthy: ${jsonEncode(openHandAmbientText(zh: '正常运行', en: 'Operational'))},
  degraded: ${jsonEncode(openHandAmbientText(zh: '服务降级', en: 'Degraded'))},
  outage: ${jsonEncode(openHandAmbientText(zh: '服务中断', en: 'Outage'))},
  idle: ${jsonEncode(openHandAmbientText(zh: '空闲待命', en: 'Idle'))}
};
const tip = document.getElementById('tip');
function bars(days){
  return '<div class="bars">' + days.map((d,i) => {
    const fill = tone[d.h] || data.idle;
    const alpha = d.h === 'idle' ? '.28' : '1';
    return '<div class="bar" data-i="'+i+'" style="--fill:'+fill+';opacity:'+alpha+'"></div>';
  }).join('') + '</div>';
}
function row(c, nested){
  const count = c.children && c.children.length ? (c.children.length + ${jsonEncode(openHandAmbientText(zh: ' 个组件', en: ' components'))}) : '';
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
function bindTips(root, days){
  root.querySelectorAll(':scope > .bars .bar').forEach(bar => {
    const i = Number(bar.dataset.i);
    const d = days[i];
    if (!d) return;
    bar.addEventListener('pointerenter', ev => showTip(ev, d));
    bar.addEventListener('pointermove', ev => moveTip(ev));
    bar.addEventListener('pointerleave', () => tip.classList.remove('show'));
  });
  root.querySelectorAll(':scope > .children > .row').forEach((child, idx) => {
    const component = root.__comp && root.__comp.children ? root.__comp.children[idx] : null;
  });
}
function walk(el, component){
  el.__comp = component;
  bindTips(el, component.days);
  (component.children || []).forEach((child, i) => {
    const node = el.querySelectorAll(':scope > .children > .row')[i];
    if (node) walk(node, child);
  });
}
document.querySelectorAll('#rows > .row').forEach((el, i) => walk(el, data.components[i]));
function showTip(ev, d){
  tip.style.setProperty('--tone', tone[d.h] || data.idle);
  tip.innerHTML = '<b>'+d.d+'</b><span class="badge">'+(label[d.h]||d.h)+'</span>' +
    '<div class="grid"><div class="tile"><span>${openHandAmbientText(zh: '请求', en: 'Requests')}</span><strong>'+d.req+'</strong></div>' +
    '<div class="tile"><span>${openHandAmbientText(zh: '成功率', en: 'Success')}</span><strong>'+d.rate+'</strong></div>' +
    '<div class="tile"><span>${openHandAmbientText(zh: '失败', en: 'Failures')}</span><strong>'+d.fail+'</strong></div>' +
    '<div class="tile"><span>${openHandAmbientText(zh: '慢请求', en: 'Slow')}</span><strong>'+d.slow+'</strong></div></div>' +
    '<p>'+d.note+'</p>';
  moveTip(ev); tip.classList.add('show');
}
function moveTip(ev){
  const pad = 16; const w = tip.offsetWidth || 260;
  let x = ev.clientX, y = ev.clientY;
  x = Math.max(w/2 + pad, Math.min(window.innerWidth - w/2 - pad, x));
  tip.style.left = x + 'px'; tip.style.top = y + 'px';
}
document.getElementById('copy-link').addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(location.href); } catch (e) {}
});
const hist = document.getElementById('history');
document.getElementById('toggle-history').addEventListener('click', () => hist.classList.toggle('open'));
const inc = document.getElementById('incidents');
if (!data.incidents.length) {
  inc.innerHTML = '<p class="note" style="margin:8px 0 16px">${openHandAmbientText(zh: '近窗没有降级或中断事件。', en: 'No degraded or outage days in this window.')}</p>';
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
  String get uptime {
    if (requests <= 0) return '—';
    return '${(successRate * 100).toStringAsFixed(2)}% ${openHandAmbientText(zh: '可用', en: 'uptime')}';
  }

  double get successRate =>
      requests <= 0 ? 0 : (successes / requests).clamp(0.0, 1.0).toDouble();

  Map<String, Object?> toJson(List<_StatusDay> calendar) => <String, Object?>{
    'id': id,
    'name': _htmlEscape(name),
    'health': health.name,
    'uptime': uptime,
    'days': [
      for (var i = 0; i < days.length; i++) _dayJson(calendar[i].day, days[i]),
    ],
    if (children.isNotEmpty)
      'children': [for (final child in children) child.toJson(calendar)],
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

(String, String) _bannerCopy(
  AiModelProxyHealth health,
  AiModelProxyController controller,
) {
  final running = controller.lifecycle == AiModelProxyLifecycle.running;
  return switch (health) {
    AiModelProxyHealth.healthy => (
      openHandAmbientText(zh: '对外中转整体运行正常', en: 'Fully operational'),
      openHandAmbientText(
        zh: '当前没有已知故障。近窗有流量的组件均处于健康阈值内。',
        en: 'No known issues. Components with traffic are within the healthy band.',
      ),
    ),
    AiModelProxyHealth.degraded => (
      openHandAmbientText(zh: '部分组件出现服务降级', en: 'Partial degradation'),
      openHandAmbientText(
        zh: '部分模型或网关时段成功率偏低或尾延迟偏高，请求仍可完成。',
        en: 'Some models or gateway hours are slower or less successful, but requests still complete.',
      ),
    ),
    AiModelProxyHealth.outage => (
      openHandAmbientText(zh: '存在不可用组件', en: 'Incident in progress'),
      openHandAmbientText(
        zh: '至少一个组件在近窗出现了较高失败率，客户端可能已经感知中断。',
        en: 'At least one component had a high failure rate. Callers may have seen interruptions.',
      ),
    ),
    AiModelProxyHealth.idle => (
      running
          ? openHandAmbientText(
              zh: '中转站已启动，等待流量',
              en: 'Proxy is up, waiting for traffic',
            )
          : openHandAmbientText(zh: '暂无状态样本', en: 'No status samples yet'),
      openHandAmbientText(
        zh: '近 90 天还没有可汇总的对外请求。灰格表示空闲待命，不代表事故。',
        en: 'No public traffic in the last 90 days. Gray cells are idle, not an outage.',
      ),
    ),
  };
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

String _daySummary(AiModelProxyDailyComponent day) {
  if (day.requests <= 0) {
    return openHandAmbientText(zh: '无流量', en: 'No traffic');
  }
  return openHandAmbientText(
    zh: '成功率 ${_percent(day.successRate)} · ${day.requests} 次',
    en: '${_percent(day.successRate)} success · ${day.requests} calls',
  );
}

Map<String, Object?> _dayJson(String day, AiModelProxyDailyComponent stat) {
  final health = stat.health;
  final note = switch (health) {
    AiModelProxyHealth.idle => openHandAmbientText(
      zh: '这一天没有该组件的请求样本，灰格表示空闲。',
      en: 'No samples for this component that day. Gray means idle.',
    ),
    AiModelProxyHealth.healthy => openHandAmbientText(
      zh: '成功率与耗时都处于健康阈值内。',
      en: 'Success rate and latency stayed in the healthy band.',
    ),
    AiModelProxyHealth.degraded => openHandAmbientText(
      zh: '仍可响应，但成功率偏低或慢请求偏多。',
      en: 'Still serving, but success dipped or slow calls increased.',
    ),
    AiModelProxyHealth.outage => openHandAmbientText(
      zh: '失败过于集中，这一天应视为中断。',
      en: 'Failures were concentrated enough to count as an outage.',
    ),
  };
  return <String, Object?>{
    'd': day,
    'h': health.name,
    'req': stat.requests,
    'ok': stat.successes,
    'fail': stat.failures,
    'slow': stat.slowCount,
    'rate': stat.requests <= 0 ? '—' : _percent(stat.successRate),
    'note': note,
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
