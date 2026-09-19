import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/model/dialog_animation_settings.dart';
import '../../../app/theme/openhand_theme.dart';
import '../../../app/theme/openhand_theme_preset.dart';

enum McpOAuthCallbackStatus { received, cancelled, invalid, alreadyReceived }

/// 授权发起时的主题快照；页面完全自包含，不向外部加载资源。
class McpOAuthCallbackPage {
  const McpOAuthCallbackPage({
    required this.colors,
    this.animation = DialogAnimationSettings.defaults,
  });

  final ColorScheme colors;
  final DialogAnimationSettings animation;

  static McpOAuthCallbackPage get fallback => McpOAuthCallbackPage(
    colors: OpenHandTheme.light(OpenHandThemePreset.deepSeaBlue).colorScheme,
  );

  static final Future<String> _logoDataUri = rootBundle
      .load('assets/branding/openhand_logo.png')
      .then(
        (data) =>
            'data:image/png;base64,${base64Encode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))}',
      );

  Future<String> render({
    required McpOAuthCallbackStatus status,
    required String serverName,
    required String nonce,
  }) async {
    final logoDataUri = await _logoDataUri;
    final received =
        status == McpOAuthCallbackStatus.received ||
        status == McpOAuthCallbackStatus.alreadyReceived;
    final title = switch (status) {
      McpOAuthCallbackStatus.received => '授权信息已接收',
      McpOAuthCallbackStatus.alreadyReceived => '授权信息已交回应用',
      McpOAuthCallbackStatus.cancelled => '本次授权未完成',
      McpOAuthCallbackStatus.invalid => '此授权回调无效',
    };
    final description = received
        ? '浏览器中的操作已完成。请回到 OpenHand 查看验证与连接结果。'
        : status == McpOAuthCallbackStatus.cancelled
        ? '你可以回到 OpenHand，准备好后再重新发起授权。'
        : '此链接未通过验证。请回到 OpenHand，重新发起授权。';
    final safeName = const HtmlEscape().convert(serverName);
    String css(Color color) =>
        '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
    final accent = received ? colors.primary : colors.error;
    final accentContainer = received
        ? colors.primaryContainer
        : colors.errorContainer;
    final onAccentContainer = received
        ? colors.onPrimaryContainer
        : colors.onErrorContainer;
    final transform = switch (animation.entranceStyle) {
      DialogAnimationStyle.none || DialogAnimationStyle.fade => 'none',
      DialogAnimationStyle.slideUp => 'translateY(24px)',
      DialogAnimationStyle.slideDown => 'translateY(-24px)',
      DialogAnimationStyle.slideLeft => 'translateX(24px)',
      DialogAnimationStyle.slideRight => 'translateX(-24px)',
      DialogAnimationStyle.rotateScale => 'rotate(-3deg) scale(.94)',
      DialogAnimationStyle.flipX => 'perspective(900px) rotateX(12deg)',
      DialogAnimationStyle.expand => 'scale(.96,.9)',
      _ => 'translateY(12px) scale(.94)',
    };
    final spring =
        animation.entranceStyle == DialogAnimationStyle.springScale ||
        animation.entranceStyle == DialogAnimationStyle.elastic;
    final curve = spring
        ? 'cubic-bezier(.2,1.3,.35,1)'
        : switch (animation.curve) {
            DialogAnimationCurve.easeInOut => 'ease-in-out',
            DialogAnimationCurve.easeOut => 'ease-out',
            DialogAnimationCurve.elasticOut ||
            DialogAnimationCurve.bounceOut => 'cubic-bezier(.2,1.3,.35,1)',
            DialogAnimationCurve.decelerate => 'cubic-bezier(0,0,.2,1)',
            _ => 'cubic-bezier(.16,1,.3,1)',
          };
    final duration = animation.effectiveEntranceDurationMs;
    final iconPath = received
        ? '<path d="m7 12 3.2 3.2L17 8.5"/>'
        : '<path d="M12 7v6m0 4h.01"/>';
    return '''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><title>$title · OpenHand</title>
<style nonce="$nonce">
:root{color-scheme:${colors.brightness == Brightness.dark ? 'dark' : 'light'};--bg:${css(colors.surface)};--panel:${css(colors.surfaceContainerLow)};--ink:${css(colors.onSurface)};--muted:${css(colors.onSurfaceVariant)};--line:${css(colors.outlineVariant)};--accent:${css(accent)};--soft:${css(accentContainer)};--on-soft:${css(onAccentContainer)};--primary:${css(colors.primary)};--on-primary:${css(colors.onPrimary)};--duration:${duration}ms}
*{box-sizing:border-box}body{margin:0;min-height:100vh;min-height:100svh;display:grid;place-items:center;padding:40px 24px;background:var(--bg);color:var(--ink);font-family:system-ui,-apple-system,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif;-webkit-font-smoothing:antialiased;line-height:1.6;isolation:isolate}
main{width:min(100%,700px)}.brand{display:flex;align-items:center;gap:10px;margin:0 0 22px 6px;font-size:18px;font-weight:750;letter-spacing:-.5px}.brand-mark{display:block;width:32px;height:32px;object-fit:contain;border-radius:8px}.brand span:last-child{margin-left:auto;font-size:12px;letter-spacing:.08em;color:var(--muted);font-weight:550}
.card{position:relative;overflow:hidden;padding:44px;border:1px solid color-mix(in srgb,var(--accent) 18%,var(--line));border-radius:32px;background:var(--panel);box-shadow:0 24px 72px color-mix(in srgb,var(--ink) 8%,transparent);animation:enter var(--duration) $curve both}
.status-icon{width:76px;height:76px;display:grid;place-items:center;border-radius:25px;color:var(--on-soft);background:var(--soft);box-shadow:0 0 0 9px color-mix(in srgb,var(--soft) 35%,transparent);margin:8px 0 32px}.status-icon svg{width:40px;height:40px;stroke:currentColor;stroke-width:1.8;fill:none;stroke-linecap:round;stroke-linejoin:round}
.eyebrow{margin:0 0 8px;color:var(--accent);font-size:12px;font-weight:750;letter-spacing:.13em}h1{margin:0;font-size:clamp(26px,5vw,36px);line-height:1.3;letter-spacing:-.04em;font-weight:750}.description{max-width:490px;margin:16px 0 26px;color:var(--muted);font-size:15px;line-height:1.85}
.service{display:flex;align-items:center;gap:10px;min-width:0;padding:14px 18px;border:1px solid var(--line);border-radius:16px;font-size:14px;background:color-mix(in srgb,var(--bg) 55%,var(--panel))}.service svg{width:18px;height:18px;flex:none;color:var(--accent)}.service-label{color:var(--muted);flex:none}.service-name{min-width:0;overflow-wrap:anywhere;font-weight:650}
.next{margin:24px 0 28px;display:flex;gap:12px;align-items:flex-start;color:var(--muted);font-size:14px}.next-dot{margin-top:8px;width:7px;height:7px;background:var(--accent);border-radius:50%;flex:none}.next strong{display:block;color:var(--ink);font-weight:650;margin-bottom:3px}
button{display:inline-flex;justify-content:center;align-items:center;gap:10px;min-height:52px;padding:14px 24px;border:0;border-radius:18px;background:var(--primary);color:var(--on-primary);font:inherit;font-size:15px;font-weight:650;line-height:1.5;cursor:pointer;transition:transform var(--duration) $curve,box-shadow var(--duration) ease}button:hover{transform:translateY(-2px);box-shadow:0 8px 20px color-mix(in srgb,var(--primary) 20%,transparent)}button:active{transform:scale(.97)}button:focus-visible{outline:3px solid var(--accent);outline-offset:4px}button svg{width:18px;height:18px}.hint{max-height:0;overflow:hidden;opacity:0;margin:0;color:var(--muted);font-size:13px;transition:max-height var(--duration) ease,opacity var(--duration) ease,margin var(--duration) ease}.hint.visible{max-height:140px;opacity:1;margin-top:14px}footer{margin:22px 8px 0;color:var(--muted);font-size:12px;text-align:center}
@keyframes enter{from{opacity:0;transform:$transform}to{opacity:1;transform:none}}
@media(max-width:480px){body{padding:24px 16px}.card{padding:28px 24px;border-radius:26px}.brand{font-size:16px}.brand span:last-child{font-size:11px}button{width:100%}.status-icon{width:64px;height:64px;border-radius:22px}.service{padding:12px}.description{font-size:14px}}
${duration == 0 ? 'button:hover,button:active{transform:none}' : ''}
@media(prefers-reduced-motion:reduce){*,*::before{animation:none!important;transition:none!important}button:hover,button:active{transform:none}}
</style>
<script nonce="$nonce">history.replaceState(null,'',location.pathname);</script>
</head>
<body><main>
<header class="brand"><img class="brand-mark" src="$logoDataUri" alt="" width="32" height="32"><span>OpenHand</span><span>MCP 授权</span></header>
<section class="card" aria-labelledby="title">
<div class="status-icon" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M12 3 3.5 6v5.5c0 5 4 8 8.5 10 4.5-2 8.5-5 8.5-10V6Z"/>$iconPath</svg></div>
<p class="eyebrow">${received ? '已交回应用' : '等待重新授权'}</p><h1 id="title">$title</h1>
<p class="description">$description</p>
<div class="service"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><path d="M14 17.5h7m-3.5-3.5v7"/></svg><span class="service-label">服务</span><span class="service-name">$safeName</span></div>
<div class="next"><span class="next-dot" aria-hidden="true"></span><div><strong>${received ? '接下来，回到 OpenHand' : '回到 OpenHand 后重试'}</strong>${received ? '连接状态与可用工具会在应用中更新。' : '在服务卡片中点击“重新授权”，开始新的授权流程。'}</div></div>
<button id="close" type="button"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="${received ? 'm6 12 4 4 8-8' : 'm6 6 12 12M6 18 18 6'}"/></svg>${received ? '完成，关闭此页' : '关闭此页'}</button>
<p id="hint" class="hint" role="status" aria-hidden="true">浏览器未允许自动关闭，请手动关闭此标签页并切回 OpenHand。</p>
</section><footer>由本机 OpenHand 接收 · 此页面不展示授权凭证</footer>
</main><script nonce="$nonce">document.getElementById('close').addEventListener('click',()=>{window.close();const hint=document.getElementById('hint');hint.classList.add('visible');hint.removeAttribute('aria-hidden');});</script></body></html>''';
  }
}
