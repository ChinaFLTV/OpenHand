// Web 通用消息平台 — 旧版内联 SPA 模板。
//
// 这是 Stage 3 之前 GPT-5.5 一次性塞进来的 Telegram 风格单页客户端，
// 通过模板替换 `{{primary}}/{{onPrimary}}/...` 注入主题色。
// 后续会被独立的 Vite + Preact 子项目（`web/`）取代——届时整个文件
// 都会删除，因此这里不要再追加任何业务逻辑。
library;

const String webMessagePlatformLegacyClientHtml = r'''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>Web通用消息平台</title>
<style>
:root {
  color-scheme: light dark;
  --primary: {{primary}};
  --on-primary: {{onPrimary}};
  --surface: {{surface}};
  --surface-container: {{surfaceContainer}};
  --on-surface: {{onSurface}};
  --on-surface-variant: {{onSurfaceVariant}};
  --outline: {{outline}};
  --error: {{error}};
  --surface-low: color-mix(in srgb, var(--surface) 88%, white);
  --surface-high: color-mix(in srgb, var(--surface-container) 84%, var(--surface));
  --surface-highest: color-mix(in srgb, var(--surface-container) 92%, var(--primary) 8%);
  --primary-container: color-mix(in srgb, var(--primary) 18%, var(--surface));
  --primary-state: color-mix(in srgb, var(--primary) 12%, transparent);
  --primary-state-strong: color-mix(in srgb, var(--primary) 22%, transparent);
  --error-container: color-mix(in srgb, var(--error) 14%, var(--surface));
  --outline-soft: color-mix(in srgb, var(--outline) 64%, transparent);
  --shadow: rgba(18, 18, 18, .14);
  --elevation-1: 0 2px 8px rgba(18,18,18,.08), 0 1px 3px rgba(18,18,18,.06);
  --elevation-2: 0 10px 24px rgba(18,18,18,.12), 0 3px 8px rgba(18,18,18,.08);
  --elevation-3: 0 18px 44px rgba(18,18,18,.16), 0 8px 18px rgba(18,18,18,.10);
  --radius-xs: 10px;
  --radius-sm: 14px;
  --radius-md: 18px;
  --radius-lg: 24px;
  --radius-xl: 28px;
  --radius-full: 999px;
  --motion: cubic-bezier(.2, 0, 0, 1);
  --motion-spring: cubic-bezier(.2, 1.4, .2, 1);
}
* { box-sizing: border-box; }
html, body { height: 100%; margin: 0; }
body {
  font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background:
    linear-gradient(180deg, color-mix(in srgb, var(--surface) 92%, var(--primary) 8%), var(--surface));
  color: var(--on-surface);
  overflow: hidden;
}
button, input, select, textarea { font: inherit; }
button { border: 0; cursor: pointer; user-select: none; }
button:disabled { cursor: default; opacity: .46; transform: none !important; }
button, .session, .file-row, input, select, textarea, .panel, .msg {
  transition: background .2s var(--motion), border-color .2s var(--motion), box-shadow .2s var(--motion), transform .18s var(--motion-spring), opacity .2s var(--motion);
}
button:not(:disabled):active { transform: scale(.96); }
.app { height: 100%; display: grid; grid-template-columns: minmax(292px, 380px) minmax(0, 1fr); }
.sidebar { min-width: 0; display: flex; flex-direction: column; gap: 10px; padding: 12px; border-right: 1px solid var(--outline-soft); background: var(--surface-high); }
.side-head { padding: 12px; display: flex; gap: 12px; align-items: center; border: 1px solid var(--outline-soft); border-radius: var(--radius-xl); background: var(--surface); box-shadow: var(--elevation-1); }
.brand { width: 44px; height: 44px; border-radius: var(--radius-md); background: var(--primary); color: var(--on-primary); display: grid; place-items: center; font-weight: 850; letter-spacing: 0; box-shadow: var(--elevation-1); }
.side-title { font-size: 17px; font-weight: 780; line-height: 1.2; }
.side-subtitle { font-size: 12px; color: var(--on-surface-variant); }
.toolbar { display: flex; gap: 8px; padding: 4px 2px 0; }
.icon-btn, .text-btn { min-height: 40px; border-radius: var(--radius-full); color: var(--primary); background: var(--primary-state); padding: 0 16px; display: inline-flex; align-items: center; justify-content: center; gap: 8px; font-weight: 680; }
.icon-btn { width: 40px; min-width: 40px; padding: 0; font-size: 20px; }
.icon-btn:not(:disabled):hover, .text-btn:not(:disabled):hover, .session-action:not(:disabled):hover { background: var(--primary-state-strong); box-shadow: var(--elevation-1); }
.text-btn.primary { background: var(--primary); color: var(--on-primary); box-shadow: var(--elevation-1); }
.text-btn.primary:not(:disabled):hover { box-shadow: var(--elevation-2); }
.text-btn.danger { color: var(--error); background: var(--error-container); }
.text-btn.danger.primary { color: white; background: var(--error); }
.session-filters { display: grid; grid-template-columns: 1fr; gap: 8px; padding: 2px 0 6px; }
.session-list { overflow: auto; padding: 0 2px 8px; display: flex; flex-direction: column; gap: 10px; }
.session { text-align: left; padding: 14px; border-radius: var(--radius-lg); background: color-mix(in srgb, var(--surface) 82%, transparent); color: var(--on-surface); border: 1px solid transparent; box-shadow: none; }
.session.active { background: var(--primary-container); border-color: color-mix(in srgb, var(--primary) 44%, var(--outline)); box-shadow: var(--elevation-1); }
.session:hover { background: color-mix(in srgb, var(--primary) 10%, var(--surface)); border-color: color-mix(in srgb, var(--primary) 28%, var(--outline)); }
.session-main { width: 100%; padding: 0; border-radius: 0; background: transparent; color: inherit; text-align: left; }
.session-actions { display: flex; gap: 8px; margin-top: 10px; }
.session-action { min-height: 32px; min-width: 48px; border-radius: var(--radius-full); color: var(--primary); background: var(--primary-state); font-size: 12px; font-weight: 650; }
.session-action.danger { color: var(--error); background: var(--error-container); }
.session-title { font-weight: 760; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.session-meta, .session-preview { color: var(--on-surface-variant); font-size: 12px; margin-top: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.chat { min-width: 0; display: flex; flex-direction: column; background: color-mix(in srgb, var(--surface) 96%, var(--primary) 4%); }
.topbar { min-height: 72px; display: flex; align-items: center; gap: 12px; padding: 10px 18px; border-bottom: 1px solid var(--outline-soft); background: color-mix(in srgb, var(--surface) 86%, transparent); backdrop-filter: blur(18px); }
.topbar-main { flex: 1; min-width: 0; }
.mobile-menu { display: none; }
.thread-title { font-size: 18px; font-weight: 780; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.thread-subtitle { font-size: 12px; color: var(--on-surface-variant); }
.messages { flex: 1; overflow: auto; padding: 20px; display: flex; flex-direction: column; gap: 14px; scroll-behavior: smooth; }
.msg { max-width: min(760px, 86%); padding: 14px 16px; border-radius: var(--radius-xl); box-shadow: var(--elevation-1); white-space: pre-wrap; overflow-wrap: anywhere; line-height: 1.5; animation: messageIn .24s var(--motion-spring); }
.msg.user { align-self: flex-end; border-bottom-right-radius: var(--radius-xs); background: var(--primary); color: var(--on-primary); }
.msg.assistant, .msg.tool, .msg.status { align-self: flex-start; border-bottom-left-radius: var(--radius-xs); background: var(--surface-highest); color: var(--on-surface); border: 1px solid var(--outline-soft); }
.msg .meta { margin-top: 8px; opacity: .72; font-size: 11px; }
.composer { display: grid; grid-template-columns: auto minmax(0, 1fr) auto; gap: 10px; align-items: end; padding: 12px 16px 16px; border-top: 1px solid var(--outline-soft); background: color-mix(in srgb, var(--surface) 90%, transparent); backdrop-filter: blur(18px); }
textarea { min-height: 46px; max-height: 150px; resize: vertical; border: 1px solid var(--outline-soft); border-radius: var(--radius-lg); padding: 12px 14px; background: var(--surface); color: var(--on-surface); outline: none; box-shadow: inset 0 0 0 1px transparent; }
input, select { height: 44px; border: 1px solid var(--outline-soft); border-radius: var(--radius-lg); padding: 0 14px; background: var(--surface); color: var(--on-surface); outline: none; }
textarea:focus, input:focus, select:focus { border-color: var(--primary); box-shadow: 0 0 0 4px color-mix(in srgb, var(--primary) 18%, transparent); }
.empty { flex: 1; display: grid; place-items: center; color: var(--on-surface-variant); text-align: center; padding: 24px; }
.login { height: 100%; display: grid; place-items: center; padding: 18px; }
.panel { width: min(420px, 100%); border: 1px solid var(--outline-soft); border-radius: var(--radius-xl); padding: 24px; background: var(--surface-high); box-shadow: var(--elevation-3); }
.panel h1 { margin: 0 0 8px; font-size: 24px; font-weight: 780; }
.field { display: grid; gap: 7px; margin-top: 14px; }
.field span { font-size: 12px; color: var(--on-surface-variant); font-weight: 640; }
.modal { position: fixed; inset: 0; display: grid; place-items: center; background: rgba(0,0,0,.32); padding: 18px; z-index: 5; opacity: 0; visibility: hidden; pointer-events: none; transition: opacity .22s var(--motion), visibility .22s var(--motion); }
.modal.open { opacity: 1; visibility: visible; pointer-events: auto; }
.modal .panel { width: min(560px, 100%); transform: translateY(12px) scale(.98); transition: transform .28s var(--motion-spring), opacity .22s var(--motion); }
.modal.open .panel { transform: translateY(0) scale(1); }
.modal .panel.wide { width: min(980px, 100%); max-height: min(780px, calc(100vh - 36px)); display: flex; flex-direction: column; }
.dialog-message { margin: 10px 0 0; color: var(--on-surface-variant); line-height: 1.45; }
.dialog-actions { display: flex; gap: 10px; margin-top: 18px; justify-content: flex-end; }
.file-tools { display: grid; grid-template-columns: minmax(180px, 1fr) minmax(180px, 1fr) 140px; gap: 10px; }
.file-layout { min-height: 0; display: grid; grid-template-columns: minmax(220px, 320px) 1fr; gap: 12px; margin-top: 12px; }
.file-list { min-height: 320px; max-height: 58vh; overflow: auto; border: 1px solid var(--outline-soft); border-radius: var(--radius-lg); padding: 8px; background: color-mix(in srgb, var(--surface) 70%, transparent); }
.file-row { width: 100%; min-height: 38px; border-radius: var(--radius-md); background: transparent; color: var(--on-surface); text-align: left; padding: 8px 10px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.file-row:hover { background: var(--primary-state); }
.file-editor { display: flex; min-height: 320px; flex-direction: column; gap: 8px; }
.file-editor textarea { flex: 1; min-height: 320px; max-height: 58vh; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 13px; }
.fab { position: fixed; right: 24px; bottom: 88px; width: 64px; height: 64px; border-radius: var(--radius-lg); background: var(--primary); color: var(--on-primary); font-size: 30px; box-shadow: var(--elevation-3); }
.fab:not(:disabled):hover { transform: translateY(-2px); }
.toast { position: fixed; left: 50%; bottom: 18px; transform: translateX(-50%) translateY(8px); background: color-mix(in srgb, #222 86%, var(--primary)); color: white; border-radius: var(--radius-lg); padding: 11px 16px; opacity: 0; pointer-events: none; transition: opacity .2s var(--motion), transform .2s var(--motion); z-index: 8; max-width: min(640px, calc(100vw - 32px)); box-shadow: var(--elevation-2); }
.toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
.hidden { display: none !important; }
@keyframes messageIn { from { opacity: 0; transform: translateY(8px) scale(.98); } to { opacity: 1; transform: translateY(0) scale(1); } }
@media (max-width: 860px) {
  .app { grid-template-columns: 1fr; }
  .sidebar { position: fixed; inset: 0 auto 0 0; width: min(88vw, 360px); z-index: 3; transform: translateX(-105%); transition: transform .26s var(--motion); box-shadow: var(--elevation-3); border-radius: 0 var(--radius-xl) var(--radius-xl) 0; }
  .sidebar.open { transform: translateX(0); }
  .mobile-menu { display: inline-flex; }
  .messages { padding: 12px; }
  .msg { max-width: 94%; }
  .composer { grid-template-columns: auto 1fr auto; padding: 10px; }
  .file-tools { grid-template-columns: 1fr; }
  .file-layout { grid-template-columns: 1fr; }
  .text-btn span { display: none; }
  .fab { right: 16px; bottom: 82px; }
}
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { transition-duration: .01ms !important; animation-duration: .01ms !important; scroll-behavior: auto !important; }
}
</style>
</head>
<body>
<div id="login" class="login hidden">
  <form class="panel" id="loginForm">
    <h1>Web通用消息平台</h1>
    <p class="side-subtitle">登录后继续访问此设备可见的 OpenHand 线程会话。</p>
    <label class="field"><span>用户名</span><input id="username" autocomplete="username" value="openhand" /></label>
    <label class="field"><span>密码</span><input id="password" type="password" autocomplete="current-password" /></label>
    <button class="text-btn primary" style="width:100%;margin-top:18px" type="submit">登录</button>
  </form>
</div>
<div id="app" class="app hidden">
  <aside id="sidebar" class="sidebar">
    <div class="side-head"><div class="brand">OH</div><div><div class="side-title">Web通用消息平台</div><div id="serviceLine" class="side-subtitle">连接中</div></div></div>
    <div class="toolbar"><button id="refresh" class="icon-btn" title="刷新">↻</button><button id="loadMore" class="text-btn"><span>更多</span></button></div>
    <div class="session-filters"><select id="sourceFilter"><option value="">全部来源</option><option value="WEB_PC">WEB_PC</option><option value="WEB_MOBILE">WEB_MOBILE</option><option value="APP_PC">APP_PC</option><option value="APP_MOBILE">APP_MOBILE</option><option value="APP_TABLET">APP_TABLET</option></select><input id="deviceFilter" placeholder="设备 ID 过滤" /></div>
    <div id="sessions" class="session-list"></div>
  </aside>
  <main class="chat">
    <div class="topbar"><button id="menu" class="icon-btn mobile-menu">☰</button><div class="topbar-main"><div id="threadTitle" class="thread-title">选择一个线程</div><div id="threadSub" class="thread-subtitle">下拉刷新，上滑加载更多线程</div></div><button id="files" class="icon-btn" title="项目文件">▣</button></div>
    <div id="messages" class="messages"><div class="empty">选择或新建一个线程会话。</div></div>
    <form id="composer" class="composer"><input id="file" type="file" multiple hidden /><button id="attach" type="button" class="icon-btn" title="附件">＋</button><textarea id="input" placeholder="输入消息"></textarea><button class="text-btn primary" type="submit">发送</button></form>
  </main>
  <button id="newSession" class="fab" title="新建线程">＋</button>
</div>
<div id="newModal" class="modal"><form id="newForm" class="panel"><h1>新建线程</h1><label class="field"><span>线程名称</span><input id="newTitle" placeholder="新会话" /></label><label class="field"><span>线程模板</span><select id="template"></select></label><label class="field"><span>对话模式</span><select id="mode"></select></label><label class="field"><span>模型</span><select id="model"></select></label><div style="display:flex;gap:10px;margin-top:18px"><button type="button" id="cancelNew" class="text-btn">取消</button><button class="text-btn primary" style="flex:1" type="submit">创建</button></div></form></div>
<div id="fileModal" class="modal"><div class="panel wide"><div style="display:flex;gap:10px;align-items:center"><h1 style="flex:1">项目文件</h1><button id="closeFiles" class="icon-btn">×</button></div><div class="file-tools"><label class="field"><span>路径</span><input id="filePath" value="" /></label><label class="field"><span>搜索</span><input id="fileSearch" placeholder="文件名或相对路径" /></label><label class="field"><span>类型</span><select id="fileType"><option value="all">全部</option><option value="directory">文件夹</option><option value="file">文件</option></select></label></div><div id="filePolicy" class="side-subtitle" style="margin-top:8px"></div><div class="file-layout"><div id="fileList" class="file-list"></div><div class="file-editor"><input id="editingPath" readonly placeholder="选择文本文件" /><textarea id="fileContent" spellcheck="false"></textarea><div style="display:flex;gap:10px"><button id="saveFile" class="text-btn primary" style="flex:1">保存文件</button><button id="reloadFile" class="text-btn">重载</button></div></div></div></div></div>
<div id="dialogModal" class="modal"><form id="dialogForm" class="panel"><h1 id="dialogTitle"></h1><p id="dialogMessage" class="dialog-message"></p><label id="dialogInputWrap" class="field hidden"><span id="dialogInputLabel"></span><input id="dialogInput" /></label><div class="dialog-actions"><button type="button" id="dialogCancel" class="text-btn">取消</button><button id="dialogOk" class="text-btn primary" type="submit">确认</button></div></form></div>
<div id="toast" class="toast"></div>
<script>
const state = { meta:null, token:localStorage.getItem('oh_token') || '', deviceId: localStorage.getItem('oh_device_id') || '', source:'WEB_PC', sessionSource:'', sessionDevice:'', sessionManagement:true, page:1, hasMore:true, sessions:[], active:null, poll:null, modelKey:'', filePath:'', fileSearch:'', fileType:'all', editingPath:'', workspaceFiles:{enabled:true,write:true,maxBytes:1048576,allowedExtensions:[]} };
if(!state.deviceId){ state.deviceId = crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random(); localStorage.setItem('oh_device_id', state.deviceId); }
function detectSource(){ const w = Math.min(innerWidth, screen.width || innerWidth); state.source = w < 760 ? 'WEB_MOBILE' : 'WEB_PC'; }
function headers(){ const h = {'content-type':'application/json','x-openhand-device-id':state.deviceId,'x-openhand-source':state.source,'x-openhand-device-platform':navigator.platform || ''}; if(state.token) h.authorization = 'Bearer '+state.token; return h; }
function toast(msg){ const el=document.getElementById('toast'); el.textContent=msg; el.classList.add('show'); setTimeout(()=>el.classList.remove('show'),2200); }
function openDialog(options){ return new Promise(resolve=>{ const modal=document.getElementById('dialogModal'); const form=document.getElementById('dialogForm'); const input=document.getElementById('dialogInput'); const wrap=document.getElementById('dialogInputWrap'); const ok=document.getElementById('dialogOk'); document.getElementById('dialogTitle').textContent=options.title||'确认'; document.getElementById('dialogMessage').textContent=options.message||''; document.getElementById('dialogInputLabel').textContent=options.inputLabel||''; input.value=options.value||''; input.placeholder=options.placeholder||''; wrap.classList.toggle('hidden',!options.input); ok.textContent=options.confirmText||'确认'; ok.className='text-btn primary'+(options.danger?' danger':''); const close=value=>{ modal.classList.remove('open'); form.onsubmit=null; document.getElementById('dialogCancel').onclick=null; resolve(value); }; document.getElementById('dialogCancel').onclick=()=>close(null); form.onsubmit=e=>{ e.preventDefault(); if(options.requiredText && input.value!==options.requiredText){ toast('请输入 '+options.requiredText+' 以确认'); input.focus(); return; } close(options.input?input.value:true); }; modal.classList.add('open'); setTimeout(()=> options.input ? input.focus() : ok.focus(), 0); }); }
async function api(path, opts={}){ const res = await fetch(path,{...opts,headers:{...headers(),...(opts.headers||{})}}); const json = await res.json().catch(()=>({})); if(!res.ok) throw Object.assign(new Error(json.message||json.error||res.statusText),{status:res.status,json}); return json; }
async function boot(){ detectSource(); state.meta = await api('/api/meta'); applyMeta(); if(state.meta.service.auth_enabled && !state.token){ showLogin(); } else { if(!state.token) await anonymousLogin(); showApp(); await loadSessions(true); } }
function applyMeta(){ document.getElementById('serviceLine').textContent = state.meta.service.auth_enabled ? '鉴权已开启' : '免鉴权本地访问'; state.sessionManagement=state.meta.service.session_management_enabled!==false; const wf=state.meta.workspace_files||{}; state.workspaceFiles={enabled:wf.enabled!==false,write:wf.write_enabled!==false,maxBytes:wf.max_file_bytes||1048576,allowedExtensions:wf.allowed_extensions||[]}; const filesBtn=document.getElementById('files'); filesBtn.disabled=!state.workspaceFiles.enabled; fill('template', state.meta.templates.map(t=>[t.id,t.name])); fill('mode', state.meta.conversation_modes.map(m=>[m,m])); fill('model', state.meta.models.map(m=>[m.key,m.label])); state.modelKey = state.meta.models[0]?.key || ''; syncFilePolicy(); }
function fill(id, rows){ const el=document.getElementById(id); el.innerHTML=''; rows.forEach(([v,l])=>{ const o=document.createElement('option'); o.value=v; o.textContent=l; el.appendChild(o); }); }
function showLogin(){ document.getElementById('login').classList.remove('hidden'); document.getElementById('app').classList.add('hidden'); }
async function anonymousLogin(){ const j = await api('/api/login',{method:'POST',body:JSON.stringify(devicePayload())}); state.token=j.token; if(j.token !== 'anonymous') localStorage.setItem('oh_token',j.token); }
function showApp(){ document.getElementById('login').classList.add('hidden'); document.getElementById('app').classList.remove('hidden'); }
function devicePayload(){ return {source:state.source,device_id:state.deviceId,device_name:navigator.userAgent,device_platform:navigator.platform || '',device_mac_address:''}; }
document.getElementById('loginForm').onsubmit = async e => { e.preventDefault(); try{ const j=await api('/api/login',{method:'POST',body:JSON.stringify({...devicePayload(),username:username.value,password:password.value})}); state.token=j.token; localStorage.setItem('oh_token',j.token); showApp(); await loadSessions(true); }catch(err){ toast('登录失败'); }};
async function loadSessions(reset=false){ if(reset){state.page=1;state.sessions=[];state.hasMore=true;} if(!state.hasMore) return; state.sessionSource=sourceFilter.value; state.sessionDevice=deviceFilter.value.trim(); const params=new URLSearchParams({page:String(state.page),page_size:'10'}); if(state.sessionSource) params.set('source',state.sessionSource); if(state.sessionDevice) params.set('device_id',state.sessionDevice); const j=await api('/api/sessions?'+params.toString()); state.sessions.push(...j.items); state.hasMore=j.has_more; state.page++; renderSessions(); }
function renderSessions(){ const box=document.getElementById('sessions'); box.innerHTML=''; if(!state.sessions.length){ const empty=document.createElement('div'); empty.className='side-subtitle'; empty.style.padding='12px'; empty.textContent='没有匹配的线程'; box.appendChild(empty); return; } state.sessions.forEach(s=>{ const row=document.createElement('div'); row.className='session'+(state.active===s.id?' active':''); const main=document.createElement('button'); main.className='session-main'; main.innerHTML=`<div class="session-title"></div><div class="session-preview"></div><div class="session-meta"></div>`; main.children[0].textContent=s.title; main.children[1].textContent=s.last_message_preview||'暂无消息'; main.children[2].textContent=`${s.source||'UNKNOWN'} · ${s.device_id||'unknown'} · ${s.message_count} 条 · ${s.send_phase}`; main.onclick=()=>openSession(s.id); row.append(main); if(state.sessionManagement){ const actions=document.createElement('div'); actions.className='session-actions'; const rename=document.createElement('button'); rename.className='session-action'; rename.textContent='改名'; rename.onclick=()=>renameSession(s); const del=document.createElement('button'); del.className='session-action danger'; del.textContent='删除'; del.onclick=()=>deleteSession(s); actions.append(rename,del); row.append(actions); } box.appendChild(row); }); }
async function renameSession(session){ const title=await openDialog({title:'重命名线程',message:'更新 Web 侧展示的线程标题。',input:true,inputLabel:'线程名称',value:session.title||'',confirmText:'保存'}); if(title===null) return; const next=title.trim(); if(!next) return toast('标题不能为空'); try{ const j=await api('/api/sessions/'+session.id,{method:'PATCH',body:JSON.stringify({title:next})}); const idx=state.sessions.findIndex(s=>s.id===session.id); if(idx>=0) state.sessions[idx]=j.session; if(state.active===session.id) document.getElementById('threadTitle').textContent=j.session.title; renderSessions(); toast('线程已重命名'); }catch(err){ toast(err.message); } }
async function deleteSession(session){ const typed=await openDialog({title:'删除线程',message:'删除线程「'+session.title+'」不可恢复。输入 DELETE 确认。',input:true,inputLabel:'确认文本',placeholder:'DELETE',confirmText:'删除',requiredText:'DELETE',danger:true}); if(typed===null) return; try{ await api('/api/sessions/'+session.id,{method:'DELETE'}); state.sessions=state.sessions.filter(s=>s.id!==session.id); if(state.active===session.id){ state.active=null; clearInterval(state.poll); document.getElementById('threadTitle').textContent='选择一个线程'; document.getElementById('threadSub').textContent='线程已删除'; document.getElementById('messages').innerHTML='<div class="empty">线程已删除，请选择其他会话。</div>'; } renderSessions(); toast('线程已删除'); }catch(err){ toast(err.message); } }
async function openSession(id){ state.active=id; document.getElementById('sidebar').classList.remove('open'); renderSessions(); await refreshThread(); clearInterval(state.poll); state.poll=setInterval(refreshThread,1800); }
async function refreshThread(){ if(!state.active) return; try{ const s=await api('/api/sessions/'+state.active); document.getElementById('threadTitle').textContent=s.session.title; document.getElementById('threadSub').textContent=`${s.session.template_name} · ${s.runtime.send_phase}`; const j=await api('/api/sessions/'+state.active+'/messages?limit=120&offset=0'); renderMessages(j.items); }catch(err){ if(err.status===404){ toast('线程已在 APP 端删除'); state.active=null; clearInterval(state.poll); await loadSessions(true); document.getElementById('messages').innerHTML='<div class="empty">线程已删除，请选择其他会话。</div>'; } } }
function renderMessages(items){ const box=document.getElementById('messages'); box.innerHTML=''; if(!items.length){ box.innerHTML='<div class="empty">还没有消息。</div>'; return; } items.forEach(m=>{ const div=document.createElement('div'); const cls=m.role==='user'?'user':(m.kind||'assistant'); div.className='msg '+cls; const text=document.createElement('div'); text.textContent=m.content||' '; const meta=document.createElement('div'); meta.className='meta'; meta.textContent=`${m.kind} · ${new Date(m.created_at).toLocaleString()}`; div.append(text,meta); box.appendChild(div); }); box.scrollTop=box.scrollHeight; }
document.getElementById('refresh').onclick=()=>loadSessions(true).catch(e=>toast(e.message));
document.getElementById('loadMore').onclick=()=>loadSessions(false).catch(e=>toast(e.message));
document.getElementById('sourceFilter').onchange=()=>loadSessions(true).catch(e=>toast(e.message));
document.getElementById('deviceFilter').onkeydown=e=>{ if(e.key==='Enter') loadSessions(true).catch(err=>toast(err.message)); };
document.getElementById('menu').onclick=()=>document.getElementById('sidebar').classList.toggle('open');
document.getElementById('newSession').onclick=()=>document.getElementById('newModal').classList.add('open');
document.getElementById('cancelNew').onclick=()=>document.getElementById('newModal').classList.remove('open');
document.getElementById('newForm').onsubmit=async e=>{ e.preventDefault(); try{ const j=await api('/api/sessions',{method:'POST',body:JSON.stringify({title:newTitle.value,template_id:template.value,mode:mode.value==='normal'?'chat':'chat'})}); document.getElementById('newModal').classList.remove('open'); await loadSessions(true); await openSession(j.session.id); }catch(err){ toast(err.message); }};
document.getElementById('files').onclick=()=>{ if(!state.workspaceFiles.enabled) return toast('项目文件访问已关闭'); document.getElementById('fileModal').classList.add('open'); syncFilePolicy(); loadFiles(state.filePath).catch(e=>toast(e.message)); };
document.getElementById('closeFiles').onclick=()=>document.getElementById('fileModal').classList.remove('open');
document.getElementById('filePath').onkeydown=e=>{ if(e.key==='Enter') loadFiles(filePath.value).catch(err=>toast(err.message)); };
document.getElementById('fileSearch').onkeydown=e=>{ if(e.key==='Enter'){ state.fileSearch=fileSearch.value.trim(); loadFiles(state.filePath).catch(err=>toast(err.message)); }};
document.getElementById('fileType').onchange=()=>{ state.fileType=fileType.value||'all'; loadFiles(state.filePath).catch(err=>toast(err.message)); };
document.getElementById('reloadFile').onclick=()=> state.editingPath ? readFile(state.editingPath).catch(e=>toast(e.message)) : loadFiles(state.filePath).catch(e=>toast(e.message));
document.getElementById('saveFile').onclick=async()=>{ if(!state.workspaceFiles.write) return toast('当前为只读模式'); if(!state.editingPath) return toast('请选择文件'); try{ await api('/api/workspace/file',{method:'PUT',body:JSON.stringify({path:state.editingPath,content:fileContent.value})}); toast('文件已保存'); }catch(err){ toast(err.message); } };
function bytesLabel(bytes){ if(bytes<1024) return bytes+' B'; const kb=bytes/1024; if(kb<1024) return kb.toFixed(1)+' KB'; const mb=kb/1024; return mb.toFixed(1)+' MB'; }
function syncFilePolicy(){ const ext=state.workspaceFiles.allowedExtensions.length?state.workspaceFiles.allowedExtensions.join(', '):'全部文本'; filePolicy.textContent=`${state.workspaceFiles.write?'读写':'只读'} · 单文件 ${bytesLabel(state.workspaceFiles.maxBytes)} · 扩展名 ${ext}`; saveFile.disabled=!state.workspaceFiles.write||!state.editingPath; fileContent.readOnly=!state.workspaceFiles.write; }
async function loadFiles(path=''){ state.fileSearch=fileSearch.value.trim(); state.fileType=fileType.value||'all'; const params=new URLSearchParams({path:path||'',q:state.fileSearch,type:state.fileType}); const j=await api('/api/workspace/files?'+params.toString()); state.filePath=j.path||''; filePath.value=state.filePath; renderFiles(j); syncFilePolicy(); }
function parentPath(path){ const parts=String(path||'').split('/').filter(Boolean); parts.pop(); return parts.join('/'); }
function renderFiles(data){ const box=document.getElementById('fileList'); box.innerHTML=''; if(data.path){ const up=document.createElement('button'); up.className='file-row'; up.textContent='..'; up.onclick=()=>loadFiles(parentPath(data.path)).catch(e=>toast(e.message)); box.appendChild(up); } if(!data.items.length){ const empty=document.createElement('div'); empty.className='side-subtitle'; empty.style.padding='12px'; empty.textContent='没有匹配的文件'; box.appendChild(empty); return; } data.items.forEach(item=>{ const b=document.createElement('button'); b.className='file-row'; b.textContent=(item.type==='directory'?'▸ ':'  ')+item.name+(item.type==='file'&&item.editable===false?' · 过大':''); b.title=item.path; b.onclick=()=> item.type==='directory' ? loadFiles(item.path).catch(e=>toast(e.message)) : readFile(item.path).catch(e=>toast(e.message)); box.appendChild(b); }); }
async function readFile(path){ const j=await api('/api/workspace/file?path='+encodeURIComponent(path)); state.editingPath=j.path; editingPath.value=j.path; fileContent.value=j.content||''; syncFilePolicy(); }
document.getElementById('attach').onclick=()=>document.getElementById('file').click();
document.getElementById('composer').onsubmit=async e=>{ e.preventDefault(); if(!state.active) return toast('请先选择线程'); const files=[...document.getElementById('file').files]; const attachments=[]; for(const f of files){ const data=await new Promise((resolve,reject)=>{ const r=new FileReader(); r.onload=()=>resolve(String(r.result).split(',')[1]||''); r.onerror=reject; r.readAsDataURL(f); }); attachments.push({name:f.name,mime_type:f.type,data_base64:data}); } try{ await api('/api/sessions/'+state.active+'/messages',{method:'POST',body:JSON.stringify({content:input.value,attachments,mode:mode.value,model_key:model.value})}); input.value=''; file.value=''; await refreshThread(); }catch(err){ toast(err.message); }};
addEventListener('resize', detectSource);
boot().catch(err=>{ console.error(err); toast(err.message || '启动失败'); });
</script>
</body>
</html>''';
