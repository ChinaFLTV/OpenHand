import 'package:flutter/foundation.dart';

/// macOS 的 WebView 插件未实现背景不透明接口，调用会阻断播放器初始化。
bool openHandCanSetWebViewBackgroundColor(TargetPlatform platform) =>
    platform != TargetPlatform.macOS;

/// 生成内嵌视频播放器共用的控制栏结构。
String openHandVideoPlayerControlsHtml({
  required String trailingActionId,
  required String trailingActionLabel,
}) {
  return '''
  <div class="scrim"></div>
  <div class="control-bar" id="controls">
    <button id="rewind" class="control-button seek-button" type="button" aria-label="Back 15 seconds" title="Back 15 seconds"></button>
    <button id="play" class="control-button" type="button" aria-label="Play" title="Play"></button>
    <button id="forward" class="control-button seek-button" type="button" aria-label="Forward 15 seconds" title="Forward 15 seconds"></button>
    <span id="current" class="time">00:00</span>
    <input id="progress" class="progress" type="range" min="0" max="1000" step="1" value="0" aria-label="Progress">
    <span id="duration" class="time">00:00</span>
    <div class="volume-group" id="volumeGroup">
      <button id="mute" class="control-button" type="button" aria-label="Mute" title="Mute"></button>
      <div class="volume-popover">
        <input id="volume" class="volume vertical" type="range" min="0" max="1" step="0.01" value="1" aria-label="Volume" aria-orientation="vertical">
      </div>
    </div>
    <button id="playMode" class="control-button" type="button" aria-label="Stop after playback" title="Stop after playback"></button>
    <button id="$trailingActionId" class="control-button" type="button" aria-label="$trailingActionLabel" title="$trailingActionLabel"></button>
  </div>
''';
}

/// 生成播放器共用图标表；全屏页面使用退出图标，其余页面使用进入全屏图标。
String openHandVideoPlayerIconsJavaScript({bool exitFullscreen = false}) {
  final trailingIcon = exitFullscreen
      ? '''exit:'<svg viewBox="0 0 24 24"><path d="M9 5H5v4M15 5h4v4M19 15v4h-4M5 15v4h4" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M9 9l-5-5M15 9l5-5M15 15l5 5M9 15l-5 5" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>','''
      : '''fullscreen:'<svg viewBox="0 0 24 24"><path d="M5 9V5h4M15 5h4v4M19 15v4h-4M9 19H5v-4" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',''';
  return '''
const icon={
play:'<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>',
pause:'<svg viewBox="0 0 24 24"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>',
mute:'<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4z"/><path d="M18 9l4 4m0-4-4 4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
volume:'<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4z"/><path d="M16 8.5a5 5 0 010 7M18.5 6a8 8 0 010 12" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
rewind:'<svg viewBox="0 0 24 24"><path d="M11 7l-6 5 6 5V7zm8 0l-6 5 6 5V7z"/><text x="12" y="21" text-anchor="middle" font-size="7" fill="currentColor">15</text></svg>',
forward:'<svg viewBox="0 0 24 24"><path d="M13 7l6 5-6 5V7zM5 7l6 5-6 5V7z"/><text x="12" y="21" text-anchor="middle" font-size="7" fill="currentColor">15</text></svg>',
loop:'<svg viewBox="0 0 24 24"><path d="M17 2l4 4-4 4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 11V9a3 3 0 013-3h15" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M7 22l-4-4 4-4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M21 13v2a3 3 0 01-3 3H3" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
stopAfter:'<svg viewBox="0 0 24 24"><rect x="7" y="7" width="10" height="10" rx="2"/><path d="M4 12h1.5M18.5 12H20" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
$trailingIcon
};
''';
}

/// 播放器共用的时间与范围进度格式化脚本。
const String openHandVideoPlayerScriptUtilities = r'''
function formatTime(value){if(!Number.isFinite(value)||value<0)return'00:00';const total=Math.floor(value);const hours=Math.floor(total/3600);const minutes=Math.floor((total%3600)/60);const seconds=total%60;const pad=(number)=>String(number).padStart(2,'0');return hours>0?hours+':'+pad(minutes)+':'+pad(seconds):pad(minutes)+':'+pad(seconds);}
function setRangeFill(input,ratio){const value=Math.max(0,Math.min(100,ratio*100));input.style.setProperty('--value',value+'%');}
''';

/// 播放器共用的 DOM 元素绑定。
const String openHandVideoPlayerElementBindingsJavaScript = r'''
const shell=document.getElementById('shell');
const media=document.getElementById('media');
const play=document.getElementById('play');
const rewind=document.getElementById('rewind');
const forward=document.getElementById('forward');
const progress=document.getElementById('progress');
const current=document.getElementById('current');
const duration=document.getElementById('duration');
const volume=document.getElementById('volume');
const mute=document.getElementById('mute');
const volumeGroup=document.getElementById('volumeGroup');
const playMode=document.getElementById('playMode');
''';

/// 播放器共用的播放、进度与音量状态同步逻辑。
const String openHandVideoPlayerStateSyncJavaScript = r'''
function updatePlayState(){play.innerHTML=media.paused?icon.play:icon.pause;play.setAttribute('aria-label',media.paused?'Play':'Pause');play.setAttribute('title',media.paused?'Play':'Pause');if(media.paused||media.ended)showControls(true);else scheduleHide();}
function updateTime(){const mediaDuration=Number.isFinite(media.duration)?media.duration:0;const mediaTime=Number.isFinite(media.currentTime)?media.currentTime:0;current.textContent=formatTime(mediaTime);duration.textContent=formatTime(mediaDuration);const ratio=mediaDuration>0?mediaTime/mediaDuration:0;progress.value=String(Math.round(ratio*1000));setRangeFill(progress,ratio);}
function updateVolume(){const muted=media.muted||media.volume<=0;mute.innerHTML=muted?icon.mute:icon.volume;mute.setAttribute('aria-label',muted?'Unmute':'Mute');mute.setAttribute('title',muted?'Unmute':'Mute');volume.value=String(media.muted?0:media.volume);setRangeFill(volume,media.muted?0:media.volume);}
function updatePlayMode(){media.loop=looping;playMode.innerHTML=looping?icon.loop:icon.stopAfter;playMode.classList.toggle('is-active',looping);playMode.setAttribute('aria-label',looping?'Loop playback':'Stop after playback');playMode.setAttribute('title',looping?'Loop playback':'Stop after playback');}
''';

/// 控制栏的显示 / 自动隐藏与相对跳转，三个内嵌播放器共用。
///
/// 依赖调用方先声明 `AUTO_HIDE_MS` 常量与 `hideTimer` / `dragging` /
/// `volumeActive` 三个可变状态，并已注入
/// [openHandVideoPlayerElementBindingsJavaScript] 的 DOM 绑定。
const String openHandVideoPlayerVisibilityJavaScript = r'''
function clearHideTimer(){if(hideTimer)window.clearTimeout(hideTimer);hideTimer=0;}
function scheduleHide(){clearHideTimer();if(media.paused||dragging||volumeActive)return;hideTimer=window.setTimeout(()=>{if(!media.paused&&!dragging&&!volumeActive){shell.classList.remove('controls-visible');shell.classList.remove('volume-open');}},AUTO_HIDE_MS);}
function showControls(sticky){shell.classList.add('controls-visible');if(sticky){clearHideTimer();return;}scheduleHide();}
function seekBy(delta){const dur=Number.isFinite(media.duration)?media.duration:0;media.currentTime=Math.max(0,Math.min(dur||Number.MAX_SAFE_INTEGER,media.currentTime+delta));updateTime();showControls(false);}
''';

/// 指针移出播放器外壳后的延迟隐藏，以及随之变化的音量 / 进度拖拽交互。
///
/// 只有消息气泡内的两个播放器需要：媒体预览弹窗是模态的，指针不会移出外壳。
/// 依赖调用方先声明 `POINTER_LEAVE_HIDE_MS` 常量与 `pointerInsideShell` 状态，
/// 并已注入 [openHandVideoPlayerVisibilityJavaScript]。
const String openHandVideoPlayerPointerLeaveHideJavaScript = r'''
function hideControlsAfterPointerLeave(){clearHideTimer();if(dragging||volumeActive)return;hideTimer=window.setTimeout(()=>{if(!dragging&&!volumeActive){shell.classList.remove('controls-visible');shell.classList.remove('volume-open');}},POINTER_LEAVE_HIDE_MS);}
function setVolumeActive(active){volumeActive=active;shell.classList.toggle('volume-open',active);if(active)showControls(true);else if(pointerInsideShell)scheduleHide();else hideControlsAfterPointerLeave();}
function beginProgressDrag(event){dragging=true;progress.setPointerCapture?.(event.pointerId);showControls(true);}
function endProgressDrag(event){if(!dragging)return;dragging=false;progress.releasePointerCapture?.(event.pointerId);if(pointerInsideShell)showControls(false);else hideControlsAfterPointerLeave();}
''';

/// 停止播放并释放 WebView 媒体解码资源。
const String openHandVideoPlayerReleaseJavaScript =
    r'''try{var media=document.getElementById('media');if(media){try{media.pause();}catch(_){};try{media.muted=true;}catch(_){};try{media.removeAttribute('src');}catch(_){};try{while(media.firstChild)media.removeChild(media.firstChild);}catch(_){};try{media.load();}catch(_){};}}catch(_){}''';

/// 切换 WebView 视频播放状态；优先复用页面已暴露的媒体实例。
const String openHandVideoPlayerTogglePlaybackJavaScript =
    r'''try{var media=window.media||document.getElementById('media');if(media){if(media.paused){var pending=media.play();if(pending&&pending.catch)pending.catch(function(){});}else{media.pause();}}}catch(_){}''';

/// 生成内嵌视频播放器共用的控制栏样式。
String openHandVideoPlayerControlsCss({
  required int compactBreakpointPx,
  required int compactHorizontalInsetPx,
  bool fullscreen = false,
}) {
  final variantCss = fullscreen
      ? '''
.media-shell video{width:100vw;height:100vh;border-radius:0}
.scrim{background:linear-gradient(to top,rgba(0,0,0,.52),transparent)}
.control-bar{bottom:18px;width:calc(100% - 48px);max-width:900px;min-height:50px}
.media-shell:not(.controls-visible) .control-bar{transform:translateX(-50%) translateY(26px) scale(.94)}
.control-button{width:30px;height:30px;min-width:30px}
.progress{flex-basis:220px}
.volume-popover{bottom:40px}
'''
      : '';
  return '''
$_openHandVideoPlayerControlsBaseCss
$variantCss
$_openHandVideoPlayerControlsResponsiveCss
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
''';

const String _openHandVideoPlayerControlsResponsiveCss = '''
@media (max-width:720px){.control-bar{gap:6px;padding:7px 10px;width:calc(100% - 28px)}.progress{min-width:72px}.time{min-width:42px}.volume-popover{height:116px}.volume.vertical{width:94px}}
''';
