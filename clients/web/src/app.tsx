import { LocationProvider } from 'preact-iso';
import { useEffect } from 'preact/hooks';
import { stopMessageTtsPlaybackOnPageExit } from './api/sessions';
import { SnackbarHost } from './components/Snackbar';
import { AppRouter } from './app/index';

export function App() {
  useEffect(() => {
    window.addEventListener('pagehide', stopMessageTtsPlaybackOnPageExit);
    return () => {
      window.removeEventListener('pagehide', stopMessageTtsPlaybackOnPageExit);
    };
  }, []);

  return (
    <LocationProvider>
      <AppRouter />
      <SnackbarHost />
    </LocationProvider>
  );
}
