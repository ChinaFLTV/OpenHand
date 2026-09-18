import { useEffect, useRef, useState } from 'preact/hooks';
import type { SessionMessage } from '../api/sessions';

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

  function stop(focus = true) {
    active.current = null;
    waiting.current = false;
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
    const recorder = recognition.current;
    recognition.current = null;
    if (recorder) {
      recorder.onend = recorder.onerror = recorder.onresult = null;
      recorder.abort();
    }
    if (speech.current) {
      speech.current.onend = speech.current.onerror = null;
      speech.current = null;
      window.speechSynthesis.cancel();
    }
    setCallId(null);
    setPhase('');
    if (focus) latest.current.onStop();
  }

  function listen(id: string) {
    if (active.current !== id || ownerSession.current !== latest.current.sessionId || latest.current.busy || waiting.current || recognition.current || speech.current || !RecognitionApi) return;
    const recorder = new RecognitionApi();
    recognition.current = recorder;
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => {
      if (active.current !== id || recognition.current !== recorder) return;
      stop();
      latest.current.onError('语音识别等待超时，已返回文字输入。');
    }, 60000);
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
      recorder.abort();
      void latest.current.submit(text, id).catch(() => {
        if (active.current !== id) return;
        stop();
        latest.current.onError('语音消息发送失败，已返回文字输入。');
      }).finally(() => {
        if (active.current !== id) return;
        waiting.current = false;
        setPhase('等待回复');
      });
    };
    recorder.onerror = (event) => {
      if (active.current !== id || recognition.current !== recorder || event.error === 'aborted' || event.error === 'no-speech') return;
      stop();
      latest.current.onError('语音识别失败，请检查麦克风权限与浏览器支持。');
    };
    recorder.onend = () => {
      if (recognition.current !== recorder) return;
      if (timer.current) clearTimeout(timer.current);
      recognition.current = null;
      if (active.current !== id || waiting.current || latest.current.busy) return;
      if (++emptyEnds.current > 3) {
        stop();
        latest.current.onError('长时间未识别到语音，已返回文字输入。');
        return;
      }
      timer.current = setTimeout(() => listen(id), 300);
    };
    try { recorder.start(); } catch {
      stop();
      latest.current.onError('无法启动语音识别，请检查麦克风权限。');
    }
  }

  function start() {
    if (!supported || active.current || latest.current.busy) return;
    const id = crypto.randomUUID();
    active.current = id;
    ownerSession.current = latest.current.sessionId;
    emptyEnds.current = 0;
    lastRead.current = [...latest.current.messages].reverse().find((item) => item.kind === 'assistant')?.id ?? '';
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
      recognition.current?.abort();
      return;
    }
    if (waiting.current || speech.current) return;
    const message = [...options.messages].reverse().find((item) => item.kind === 'assistant' && item.content.trim());
    if (!message || message.id === lastRead.current) {
      listen(id);
      return;
    }
    lastRead.current = message.id;
    const recorder = recognition.current;
    recognition.current = null;
    recorder?.abort();
    if (timer.current) clearTimeout(timer.current);
    const utterance = new SpeechSynthesisUtterance(message.content);
    speech.current = utterance;
    setPhase('正在朗读');
    const finished = () => {
      if (active.current !== id || speech.current !== utterance) return;
      if (timer.current) clearTimeout(timer.current);
      speech.current = null;
      window.speechSynthesis.cancel();
      listen(id);
    };
    utterance.onend = finished;
    utterance.onerror = finished;
    timer.current = setTimeout(finished, 120000);
    window.speechSynthesis.speak(utterance);
  }, [options.messages, options.busy, callId, phase]);

  return { active: callId != null, supported, phase, start, stop };
}
