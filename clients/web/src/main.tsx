import { render } from 'preact';
import { App } from './app';
import './styles/global.css';

const root = document.getElementById('root');
if (!root) {
  throw new Error('找不到 #root 挂载点');
}
render(<App />, root);
