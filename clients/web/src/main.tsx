import { render } from 'preact';
import { App } from './app';
import { t } from './i18n';
import './styles/global.css';

const root = document.getElementById('root');
if (!root) {
  throw new Error(t('boot.missingMount'));
}
render(<App />, root);
