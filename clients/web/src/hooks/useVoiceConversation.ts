import { useEffect, useRef, useState } from 'preact/hooks';
import type { SessionMessage } from '../api/sessions';

const RECOGNITION_TIMEOUT_MS = 60_000;
const SUBMISSION_TIMEOUT_MS = 60_000;
const SPEECH_TIMEOUT_MS = 120_000;
const RECOGNITION_RETRY_DELAY_MS = 300;
const MAX_EMPTY_RECOGNITION_ENDS = 3;

type Recognition = {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  onresult: ((event: { results: ArrayLike<ArrayLike<{ transcript: string }>> }) => void) | null;
  onerror: ((event: { error: string }) => void) | null;
  onend: (() => void) | null;
  start(): void;
  abort(): void;
};

type VoiceWindow = Window & {
  SpeechRecognition?: new () => Recognition;
  webkitSpeechRecognition?: new () => Recognition;
};

function lastAssistantMessage(messages: SessionMessage[]): SessionMessage | undefined {
  for (let index = messages.length - 1; index >= 0; index--) {
    const message = messages[index];
    if (message.kind === 'assistant' && message.content.trim()) return message;
  }
  return undefined;
}

export function useVoiceConversation(options: {
  sessionId: string;
  messages: SessionMessage[];
  busy: boolean;
  submit(text: string, callId: string): Promise<void>;
  onStop(): void;
  onError(message: string): void;
}) {
  const [callId, setCallId] = useState<string | null>(null);
  const [phase, setPhase] = useState('');
  const latest = useRef(options);
  latest.current = options;
  const active = useRef<string | null>(null);
  const ownerSession = useRef(options.sessionId);
  const recognition = useRef<Recognition | null>(null);
  const speech = useRef<SpeechSynthesisUtterance | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const waiting = useRef(false);
  const emptyEnds = useRef(0);
  const lastRead = useRef('');
  const api = window as VoiceWindow;
  const RecognitionApi = api.SpeechRecognition ?? api.webkitSpeechRecognition;
  const supported = Boolean(RecognitionApi && window.speechSynthesis && window.isSecureContext);

  function clearTimer() {
    if (timer.current != null) clearTimeout(timer.current);
    timer.current = null;
  }

  function releaseRecognition() {
    const recorder = recognition.current;
    recognition.current = null;
    if (!recorder) return;
    recorder.onend = recorder.onerror = recorder.onresult = null;
    try { recorder.abort(); } catch {
      // 浏览器设备已失效时仍继续释放通话状态。
    }
  }

  function releaseSpeech() {
    const utterance = speech.current;
    speech.current = null;
    if (!utterance) return;
    utterance.onend = utterance.onerror = null;
    try { window.speechSynthesis.cancel(); } catch {
      // 语音服务已退出时仍继续释放通话状态。
    }
  }

  function stop(focus = true) {
    active.current = null;
    waiting.current = false;
    clearTimer();
    releaseRecognition();
    releaseSpeech();
    setCallId(null);
    setPhase('');
    if (focus) latest.current.onStop();
  }

  function fail(message: string) {
    stop();
    latest.current.onError(message);
  }

  function listen(id: string) {
    if (active.current !== id || ownerSession.current !== latest.current.sessionId || latest.current.busy || waiting.current || recognition.current || speech.current || !RecognitionApi) return;
    let recorder: Recognition;
    try { recorder = new RecognitionApi(); } catch {
      fail('无法创建语音识别设备，请检查浏览器支持。');
      return;
    }
    recognition.current = recorder;
    clearTimer();
    timer.current = setTimeout(() => {
      if (active.current !== id || recognition.current !== recorder) return;
      fail('语音识别等待超时，已返回文字输入。');
    }, RECOGNITION_TIMEOUT_MS);
    recorder.lang = navigator.language || 'zh-CN';
    recorder.continuous = false;
    recorder.interimResults = false;
    setPhase('正在聆听');
    recorder.onresult = (event) => {
      if (active.current !== id || recognition.current !== recorder || ownerSession.current !== latest.current.sessionId || waiting.current || latest.current.busy) return;
      const text = Array.from(event.results).map((result) => result[0]?.transcript ?? '').join('').trim();
      if (!text) return;
      emptyEnds.current = 0;
      waiting.current = true;
      setPhase('正在回复');
      clearTimer();
      releaseRecognition();
      timer.current = setTimeout(() => {
        if (active.current === id && waiting.current) {
          fail('语音消息发送超时，已返回文字输入。');
        }
      }, SUBMISSION_TIMEOUT_MS);
      void (async () => {
        try {
          await latest.current.submit(text, id);
        } catch {
          if (active.current === id) fail('语音消息发送失败，已返回文字输入。');
        } finally {
          if (active.current === id) {
            clearTimer();
            waiting.current = false;
            setPhase('等待回复');
          }
        }
      })();
    };
    recorder.onerror = (event) => {
      if (active.current !== id || recognition.current !== recorder || event.error === 'aborted' || event.error === 'no-speech') return;
      fail('语音识别失败，请检查麦克风权限与浏览器支持。');
    };
    recorder.onend = () => {
      if (recognition.current !== recorder) return;
      clearTimer();
      releaseRecognition();
      if (active.current !== id || waiting.current || latest.current.busy) return;
      if (++emptyEnds.current > MAX_EMPTY_RECOGNITION_ENDS) {
        fail('长时间未识别到语音，已返回文字输入。');
        return;
      }
      timer.current = setTimeout(() => listen(id), RECOGNITION_RETRY_DELAY_MS);
    };
    try { recorder.start(); } catch {
      fail('无法启动语音识别，请检查麦克风权限。');
    }
  }

  function start() {
    if (!supported || active.current || latest.current.busy) return;
    const id = crypto.randomUUID();
    active.current = id;
    ownerSession.current = latest.current.sessionId;
    emptyEnds.current = 0;
    lastRead.current = lastAssistantMessage(latest.current.messages)?.id ?? '';
    setCallId(id);
    listen(id);
  }

  useEffect(() => {
    const onVisibility = () => { if (document.hidden) stop(false); };
    document.addEventListener('visibilitychange', onVisibility);
    return () => {
      document.removeEventListener('visibilitychange', onVisibility);
      stop(false);
    };
  }, [options.sessionId]);
  useEffect(() => {
    const id = active.current;
    if (!id) return;
    if (options.messages.some((message) => message.metadata?.ended_voice_call_id === id)) {
      stop();
      return;
    }
    if (options.busy) {
      if (recognition.current) {
        clearTimer();
        releaseRecognition();
      }
      return;
    }
    if (waiting.current || speech.current) return;
    const message = lastAssistantMessage(options.messages);
    if (!message || message.id === lastRead.current) {
      listen(id);
      return;
    }
    lastRead.current = message.id;
    releaseRecognition();
    clearTimer();
    let utterance: SpeechSynthesisUtterance;
    try { utterance = new SpeechSynthesisUtterance(message.content); } catch {
      fail('无法创建语音朗读任务，请检查浏览器支持。');
      return;
    }
    speech.current = utterance;
    setPhase('正在朗读');
    const finished = () => {
      if (active.current !== id || speech.current !== utterance) return;
      clearTimer();
      releaseSpeech();
      listen(id);
    };
    utterance.onend = finished;
    utterance.onerror = finished;
    timer.current = setTimeout(finished, SPEECH_TIMEOUT_MS);
    try { window.speechSynthesis.speak(utterance); } catch {
      fail('无法启动语音朗读，已返回文字输入。');
    }
  }, [options.messages, options.busy, callId, phase]);

  return { active: callId != null, supported, phase, start, stop };
}
