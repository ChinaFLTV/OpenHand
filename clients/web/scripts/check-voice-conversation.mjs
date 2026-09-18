import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { transformWithOxc } from 'vite';

// 使用可控语音设备验证生命周期，不访问真实麦克风或发送消息。
const source = fs.readFileSync(new URL('../src/hooks/useVoiceConversation.ts', import.meta.url), 'utf8');
const compiled = (await transformWithOxc(source, 'useVoiceConversation.ts')).code
  .replace(/import .* from ["']preact\/hooks["'];/, "const { useEffect, useRef, useState } = require();")
  .replace('export function useVoiceConversation', 'exports.useVoiceConversation = function');
const slots = [];
let cursor = 0;
let pendingEffects = [];
let dirty = false;
const timers = new Map();
let nextTimer = 0;
const recorders = [];
const spoken = [];
let cancelledSpeech = 0;
let stops = 0;
let errors = 0;
let submissions = 0;
let resolveSend;
const hooks = {
  useRef(value) {
    const index = cursor++;
    return slots[index] ??= { current: value };
  },
  useState(value) {
    const index = cursor++;
    slots[index] ??= { value };
    return [slots[index].value, (next) => {
      if (slots[index].value !== next) dirty = true;
      slots[index].value = next;
    }];
  },
  useEffect(effect, deps) {
    const index = cursor++;
    const previous = slots[index];
    if (previous && deps.every((dep, i) => dep === previous.deps[i])) return;
    pendingEffects.push(() => {
      previous?.cleanup?.();
      slots[index] = { deps, cleanup: effect() };
    });
  },
};
class Recognition {
  constructor() { recorders.push(this); }
  start() { this.started = true; }
  abort() { this.aborted = true; }
}
const visibility = new Set();
const sandbox = {
  exports: {},
  require: () => hooks,
  window: {
    isSecureContext: true,
    SpeechRecognition: Recognition,
    speechSynthesis: { cancel: () => cancelledSpeech++, speak: (value) => spoken.push(value) },
  },
  document: {
    hidden: false,
    addEventListener: (_, callback) => visibility.add(callback),
    removeEventListener: (_, callback) => visibility.delete(callback),
  },
  navigator: { language: 'zh-CN' },
  crypto: { randomUUID: () => `通话-${recorders.length}` },
  SpeechSynthesisUtterance: class { constructor(text) { this.text = text; } },
  setTimeout: (callback) => { timers.set(++nextTimer, callback); return nextTimer; },
  clearTimeout: (id) => timers.delete(id),
};
vm.runInNewContext(compiled, sandbox);
let options = {
  sessionId: '线程甲', messages: [], busy: false,
  submit: () => { submissions++; return new Promise((resolve) => { resolveSend = resolve; }); },
  onStop: () => stops++, onError: () => errors++,
};
let voice;
function render() {
  let passes = 0;
  do {
    assert.ok(++passes < 12, '状态更新不能无限循环');
    dirty = false;
    cursor = 0;
    voice = sandbox.exports.useVoiceConversation(options);
    const effects = pendingEffects;
    pendingEffects = [];
    effects.forEach((effect) => effect());
  } while (dirty);
}
render();
voice.start(); render();
assert.equal(voice.active, true);
const first = recorders.at(-1);
first.onresult({ results: [[{ transcript: '挂了吧' }]] });
first.onresult({ results: [[{ transcript: '重复识别' }]] });
assert.equal(submissions, 1, '重复识别不能重复提交');
first.onend();
options.busy = true; render();
resolveSend();
await new Promise((resolve) => setImmediate(resolve));
options.messages = [{ id: '结束结果', kind: 'tool', metadata: { ended_voice_call_id: '通话-0' } }];
render();
assert.equal(voice.active, false);
assert.equal(stops, 1);
assert.equal(first.aborted, true);
assert.equal(timers.size, 0);

options.busy = false;
render(); voice.start(); render();
assert.equal(voice.active, true, '历史结束结果不能关闭新通话');
const lateRecognition = recorders.at(-1).onresult;
options.messages = [...options.messages, { id: '回复', kind: 'assistant', content: '你好' }];
render();
assert.equal(spoken.length, 1);
lateRecognition({ results: [[{ transcript: '迟到识别' }]] });
assert.equal(submissions, 1, '朗读期间不能处理已取消录音的迟到结果');
const staleSpeechEnd = spoken[0].onend;
voice.stop(); render();
staleSpeechEnd(); render();
assert.equal(voice.active, false);
assert.ok(cancelledSpeech > 0);
assert.equal(timers.size, 0);

voice.start(); render();
const beforeNavigation = recorders.at(-1);
options = { ...options, sessionId: '线程乙', messages: [] };
render();
assert.equal(voice.active, false);
assert.equal(beforeNavigation.aborted, true);
assert.equal(beforeNavigation.onresult, null);

voice.start(); render();
sandbox.document.hidden = true;
visibility.forEach((callback) => callback());
render();
assert.equal(voice.active, false, '隐藏页面必须释放麦克风');
assert.equal(timers.size, 0);
assert.equal(errors, 0);
sandbox.document.hidden = false;
voice.start(); render();
const timeout = [...timers.values()][0];
timeout(); render();
assert.equal(voice.active, false, '识别引擎卡住时不能无限等待');
assert.equal(errors, 1);
assert.equal(timers.size, 0);

voice.start(); render();
recorders.at(-1).onerror({ error: 'not-allowed' });
render();
assert.equal(voice.active, false);
assert.equal(errors, 2);
assert.equal(timers.size, 0);
console.log('[语音交互检查] 挂断、重复提交、旧通话隔离、迟到回调、切换线程及隐藏页面资源清理通过。');
