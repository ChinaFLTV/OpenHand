import { LocationProvider } from 'preact-iso';
import { SnackbarHost } from './components/Snackbar';
import { AppRouter } from './app/index';

export function App() {
  return (
    <LocationProvider>
      <AppRouter />
      <SnackbarHost />
    </LocationProvider>
  );
}
