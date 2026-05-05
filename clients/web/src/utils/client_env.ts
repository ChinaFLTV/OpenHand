const WEB_CLIENT_VERSION = '0.1.0';

export interface ClientEnvironment {
  source: 'WEB_PC' | 'WEB_MOBILE' | 'WEB_TABLET';
  deviceName: string;
  devicePlatform: string;
  osName: string;
  osVersion: string;
  browserName: string;
  browserVersion: string;
  webClientVersion: string;
  locale: string;
  timezone: string;
  screenClass: string;
  userAgent: string;
}

function userAgent(): string {
  try {
    return navigator.userAgent || '';
  } catch {
    return '';
  }
}

function screenWidth(): number {
  try {
    return Math.max(window.innerWidth || 0, window.screen?.width || 0);
  } catch {
    return 0;
  }
}

function hasTouch(): boolean {
  try {
    return (navigator.maxTouchPoints ?? 0) > 0;
  } catch {
    return false;
  }
}

function parseBrowser(ua: string): { name: string; version: string } {
  const rules: Array<[string, RegExp]> = [
    ['Edge', /Edg\/([\d.]+)/],
    ['Chrome', /Chrome\/([\d.]+)/],
    ['Firefox', /Firefox\/([\d.]+)/],
    ['Safari', /Version\/([\d.]+).*Safari/],
  ];
  for (const [name, pattern] of rules) {
    const match = ua.match(pattern);
    if (match?.[1]) return { name, version: match[1] };
  }
  return { name: 'Browser', version: '' };
}

function parseOs(ua: string): { name: string; version: string } {
  const platform = platformName();
  const ios = ua.match(/(?:iPhone|iPad|iPod).*OS ([\d_]+)/);
  if (ios?.[1]) return { name: 'iOS', version: ios[1].replace(/_/g, '.') };
  const android = ua.match(/Android ([\d.]+)/);
  if (android?.[1]) return { name: 'Android', version: android[1] };
  const mac = ua.match(/Mac OS X ([\d_]+)/);
  if (mac?.[1]) return { name: 'macOS', version: mac[1].replace(/_/g, '.') };
  const win = ua.match(/Windows NT ([\d.]+)/);
  if (win?.[1]) return { name: 'Windows', version: win[1] };
  if (/Linux/i.test(ua) || /Linux/i.test(platform)) return { name: 'Linux', version: '' };
  return { name: platform || 'Web', version: '' };
}

function platformName(): string {
  try {
    return navigator.platform || 'web';
  } catch {
    return 'web';
  }
}

function detectSource(width: number): ClientEnvironment['source'] {
  if (hasTouch() && width > 0 && width <= 640) return 'WEB_MOBILE';
  if (hasTouch() && width > 0 && width <= 1180) return 'WEB_TABLET';
  return 'WEB_PC';
}

function detectScreenClass(width: number): string {
  if (width <= 640) return 'mobile';
  if (width <= 1180) return 'tablet';
  return 'desktop';
}

export function collectClientEnvironment(): ClientEnvironment {
  const ua = userAgent();
  const browser = parseBrowser(ua);
  const os = parseOs(ua);
  const width = screenWidth();
  let timezone = '';
  try {
    timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || '';
  } catch {
    timezone = '';
  }
  let locale = '';
  try {
    locale = navigator.language || '';
  } catch {
    locale = '';
  }
  const screenClass = detectScreenClass(width);
  return {
    source: detectSource(width),
    deviceName: `OpenHand Web ${screenClass}`,
    devicePlatform: platformName(),
    osName: os.name,
    osVersion: os.version,
    browserName: browser.name,
    browserVersion: browser.version,
    webClientVersion: WEB_CLIENT_VERSION,
    locale,
    timezone,
    screenClass,
    userAgent: ua,
  };
}

export function clientEnvironmentHeaders(): Record<string, string> {
  const env = collectClientEnvironment();
  return {
    'x-openhand-source': env.source,
    'x-openhand-device-name': env.deviceName,
    'x-openhand-device-platform': env.devicePlatform,
    'x-openhand-os-name': env.osName,
    'x-openhand-os-version': env.osVersion,
    'x-openhand-browser-name': env.browserName,
    'x-openhand-browser-version': env.browserVersion,
    'x-openhand-web-client-version': env.webClientVersion,
    'x-openhand-locale': env.locale,
    'x-openhand-timezone': env.timezone,
    'x-openhand-screen-class': env.screenClass,
  };
}
