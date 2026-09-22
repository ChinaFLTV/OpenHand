import { useCallback, useEffect, useRef, useState } from 'preact/hooks';

/** 串行执行页面操作，并在卸载时取消请求、丢弃迟到回调。 */
export function useAsyncAction<Key>() {
  const [pending, setPending] = useState<Key | null>(null);
  const activeRef = useRef(true);
  const controllerRef = useRef<AbortController | null>(null);

  useEffect(() => () => {
    activeRef.current = false;
    controllerRef.current?.abort();
  }, []);

  const run = useCallback(async <T,>(
    key: Key,
    request: (signal: AbortSignal) => Promise<T>,
    onSuccess: (result: T) => void,
    onError: (error: unknown) => void,
  ): Promise<void> => {
    if (!activeRef.current || controllerRef.current) return;
    const controller = new AbortController();
    controllerRef.current = controller;
    setPending(key);
    try {
      const result = await request(controller.signal);
      if (activeRef.current) onSuccess(result);
    } catch (error) {
      if (activeRef.current) onError(error);
    } finally {
      controllerRef.current = null;
      if (activeRef.current) setPending(null);
    }
  }, []);

  return { pending, run };
}
