import { useCallback, useRef } from 'preact/hooks';

export function useEventCallback<Arguments extends unknown[], ReturnValue>(
  callback: (...args: Arguments) => ReturnValue,
): (...args: Arguments) => ReturnValue {
  const callbackRef = useRef(callback);
  callbackRef.current = callback;

  return useCallback((...args: Arguments) => callbackRef.current(...args), []);
}
