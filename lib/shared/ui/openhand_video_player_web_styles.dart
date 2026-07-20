/// 生成内嵌视频播放器共用的控制栏样式。
String openHandVideoPlayerControlsCss({
  required int compactBreakpointPx,
  required int compactHorizontalInsetPx,
}) {
  return '''
$_openHandVideoPlayerControlsBaseCss
@media (max-width:${compactBreakpointPx}px){.seek-button{display:none}.control-bar{width:calc(100% - ${compactHorizontalInsetPx}px)}.time{min-width:40px}.progress{min-width:64px}.volume-popover{height:104px}.volume.vertical{width:84px}}
''';
}

const String _openHandVideoPlayerControlsBaseCss = '''
.media-shell video{width:100%;height:100%;object-fit:contain;background:#000;border-radius:10px}
.scrim{position:absolute;inset:auto 0 0;height:38%;background:linear-gradient(to top,rgba(0,0,0,.48),transparent);opacity:1;transition:opacity var(--oh-motion-duration) var(--oh-motion-curve);pointer-events:none}
.media-shell:not(.controls-visible) .scrim{opacity:0}
.control-bar{position:absolute;left:50%;bottom:12px;z-index:5;display:flex;align-items:center;gap:10px;width:calc(100% - 40px);max-width:820px;min-height:48px;padding:8px 14px;box-sizing:border-box;border:1px solid var(--oh-control-border);border-radius:999px;background:var(--oh-control-bg);color:var(--oh-control-text);box-shadow:0 18px 42px rgba(0,0,0,.36);backdrop-filter:blur(22px) saturate(1.24);-webkit-backdrop-filter:blur(22px) saturate(1.24);transform-origin:bottom center;transform:translateX(-50%) translateY(0) scale(1);opacity:1;filter:blur(0);transition:opacity var(--oh-motion-duration) var(--oh-motion-curve),transform var(--oh-motion-duration) var(--oh-motion-curve),filter var(--oh-motion-duration) var(--oh-motion-curve)}
.media-shell:not(.controls-visible) .control-bar{opacity:0;pointer-events:none;transform:translateX(-50%) translateY(24px) scale(.94);filter:blur(4px)}
.control-button{width:28px;height:28px;border:0;border-radius:999px;display:inline-flex;align-items:center;justify-content:center;background:transparent;color:#fff;cursor:pointer;transition:transform 160ms var(--oh-motion-curve),background-color 160ms ease-out,opacity 160ms ease-out}
.control-button:hover,.control-button:focus-visible{background:rgba(255,255,255,.14);transform:translateY(-1px) scale(1.06);outline:none}
.control-button.is-active{background:rgba(255,255,255,.20)}
.control-button:active{transform:scale(.92)}
.control-button svg{width:18px;height:18px;display:block;fill:currentColor}
.seek-button svg{width:21px;height:21px}
.time{min-width:48px;text-align:center;font-weight:700;font-variant-numeric:tabular-nums;color:rgba(255,255,255,.92);white-space:nowrap}
.progress{flex:1 1 180px;min-width:96px}
.volume-group{position:relative;display:inline-flex;align-items:center;justify-content:center}
.volume-popover{position:absolute;left:50%;bottom:38px;width:46px;height:136px;display:flex;align-items:center;justify-content:center;border:1px solid var(--oh-control-border);border-radius:999px;background:var(--oh-control-bg);box-shadow:0 18px 42px rgba(0,0,0,.34);backdrop-filter:blur(22px) saturate(1.24);-webkit-backdrop-filter:blur(22px) saturate(1.24);transform-origin:bottom center;transform:translateX(-50%) translateY(10px) scale(.88);opacity:0;pointer-events:none;filter:blur(3px);transition:opacity var(--oh-motion-duration) var(--oh-motion-curve),transform var(--oh-motion-duration) var(--oh-motion-curve),filter var(--oh-motion-duration) var(--oh-motion-curve)}
.volume-open .volume-popover,.volume-group:focus-within .volume-popover{opacity:1;pointer-events:auto;transform:translateX(-50%) translateY(0) scale(1);filter:blur(0)}
.volume.vertical{position:absolute;left:50%;top:50%;width:112px;transform:translate(-50%,-50%) rotate(-90deg);transform-origin:center}
input[type=range]{height:22px;margin:0;accent-color:#fff;cursor:pointer}
input[type=range]::-webkit-slider-runnable-track{height:7px;border-radius:999px;background:linear-gradient(to right,var(--oh-track-fill) 0%,var(--oh-track-fill) var(--value,0%),var(--oh-track) var(--value,0%),var(--oh-track) 100%)}
input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:18px;height:18px;margin-top:-5.5px;border-radius:50%;background:#fff;box-shadow:0 2px 10px rgba(0,0,0,.35);transition:transform 160ms var(--oh-motion-curve)}
input[type=range]:hover::-webkit-slider-thumb,input[type=range]:focus-visible::-webkit-slider-thumb{transform:scale(1.12)}
.no-motion *{transition-duration:0ms!important;animation:none!important}
@media (max-width:720px){.control-bar{gap:6px;padding:7px 10px;width:calc(100% - 28px)}.progress{min-width:72px}.time{min-width:42px}.volume-popover{height:116px}.volume.vertical{width:94px}}
''';
