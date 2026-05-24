import { useEffect, useLayoutEffect, useRef } from 'preact/hooks';

export function useStickyBottom<T extends HTMLElement>(
  signal: string | number,
  enabled: boolean,
) {
  const ref = useRef<T | null>(null);
  const pinnedRef = useRef(true);
  const programmaticUntilRef = useRef(0);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    const onScroll = () => {
      if (Date.now() <= programmaticUntilRef.current) return;
      const distance = element.scrollHeight - (element.scrollTop + element.clientHeight);
      pinnedRef.current = distance <= 20;
    };
    onScroll();
    element.addEventListener('scroll', onScroll, { passive: true });
    return () => element.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => {
    if (enabled) return;
    pinnedRef.current = true;
  }, [enabled]);

  useLayoutEffect(() => {
    const element = ref.current;
    if (!enabled || !element || !pinnedRef.current) return;
    const pin = () => {
      programmaticUntilRef.current = Date.now() + 120;
      element.scrollTop = element.scrollHeight;
    };
    pin();
    const frame = requestAnimationFrame(pin);
    return () => cancelAnimationFrame(frame);
  }, [enabled, signal]);

  return ref;
}