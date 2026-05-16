// hook_crypto.js
// 拦截常见加密签名 API，把调用栈打到 console，便于定位 sign / encrypt 函数。
// 通过 __OH_CRYPTO__ 前缀方便 grep 提取。
(() => {
  if (window.__oh_hook_crypto_installed) return;
  window.__oh_hook_crypto_installed = true;

  const log = (api, args) => {
    try {
      console.log('__OH_CRYPTO__', JSON.stringify({
        api,
        args: args.map((a) => {
          if (a == null) return null;
          if (typeof a === 'string') return a.length > 256 ? a.slice(0, 256) + '…' : a;
          if (a instanceof ArrayBuffer || ArrayBuffer.isView(a)) return `[binary length=${a.byteLength}]`;
          if (typeof a === 'object') return Object.keys(a).slice(0, 8);
          return String(a);
        }),
        stack: (new Error().stack || '').split('\n').slice(1, 9).map((s) => s.trim()),
      }));
    } catch (e) { /* ignore */ }
  };

  // crypto.subtle.*
  if (window.crypto && window.crypto.subtle) {
    const subtle = window.crypto.subtle;
    ['encrypt', 'decrypt', 'sign', 'verify', 'digest', 'deriveKey', 'deriveBits'].forEach((m) => {
      const orig = subtle[m] && subtle[m].bind(subtle);
      if (!orig) return;
      subtle[m] = function (...args) { log(`subtle.${m}`, args); return orig(...args); };
    });
  }

  // CryptoJS（如果页面引入了 crypto-js）
  Object.defineProperty(window, 'CryptoJS', {
    configurable: true,
    set(v) {
      try {
        const wrap = (obj, prefix) => {
          if (!obj || typeof obj !== 'object') return obj;
          for (const key of Object.keys(obj)) {
            const fn = obj[key];
            if (typeof fn === 'function') {
              obj[key] = function (...args) { log(`${prefix}.${key}`, args); return fn.apply(this, args); };
            }
          }
          return obj;
        };
        if (v.HmacSHA256) wrap(v, 'CryptoJS');
        if (v.AES) wrap(v.AES, 'CryptoJS.AES');
        if (v.MD5) wrap(v, 'CryptoJS');
      } catch (_) { /* ignore */ }
      Object.defineProperty(window, 'CryptoJS', { value: v, writable: true, configurable: true });
    },
  });

  // 常见自定义 sign 函数命名（按 window 顶层属性名嗅探）
  const suspects = ['sign', 'encrypt', 'getSign', '_sign', '__sign', 'genSign', 'makeSign'];
  suspects.forEach((name) => {
    let cached = window[name];
    Object.defineProperty(window, name, {
      configurable: true,
      get() { return cached; },
      set(v) {
        if (typeof v === 'function') {
          const wrapped = function (...args) { log(`window.${name}`, args); return v.apply(this, args); };
          cached = wrapped;
        } else { cached = v; }
      },
    });
  });
})();
