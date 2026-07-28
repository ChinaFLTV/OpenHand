// storage_keys —— 本地持久化 / 跨组件事件 / 缓存命名统一登记表。
//
// 历史键名格式不一（openhand.web. 点号、openhand_ 下划线、openhand- 连
// 字符、openhand: 冒号事件）；为兼容既有用户数据与既有事件监听，值一律
// 逐字保留，只收敛声明位置。新增键一律在此登记，统一采用
// `openhand.web.<snake_case>` 形式。
//
// ── localStorage 键（统一经 shared/util/browser_storage 读写） ──────────
const STORAGE_KEY_PREFIX = 'openhand.web.';
export const STORAGE_KEY_DEVICE_ID = `${STORAGE_KEY_PREFIX}device_id`;
export const STORAGE_KEY_TOKEN = `${STORAGE_KEY_PREFIX}token`;
export const STORAGE_KEY_PROFILE = `${STORAGE_KEY_PREFIX}profile`;
export const STORAGE_KEY_COMPOSER_COLLAPSED = `${STORAGE_KEY_PREFIX}composer_collapsed`;
export const STORAGE_KEY_LAST_MODEL = 'openhand.web.lastModelKey';
export const STORAGE_KEY_RECENT_MODELS = 'openhand.web.recent_models';
export const STORAGE_KEY_LANG = 'openhand_web_lang';
export const STORAGE_KEY_REDUCE_MOTION = 'openhand_web_reduce_motion';
export const STORAGE_KEY_TTS_SETTINGS = 'openhand_tts_settings';
export const STORAGE_KEY_MESSAGE_CONTENT_FORMAT = 'openhand_message_content_format';
export const STORAGE_KEY_HTML_RENDER_FALLBACK = 'openhand_html_render_fallback';

// ── window CustomEvent 事件名 ───────────────────────────────────────────
export const EVENT_TTS_SETTINGS_CHANGED = 'openhand:tts-settings-changed';
export const EVENT_MESSAGE_CONTENT_FORMAT_CHANGED =
  'openhand:message-content-format-changed';

// ── Cache API / Service Worker 消息与通知 tag ───────────────────────────
export const CACHE_NAME_REMOTE_MEDIA = 'openhand-remote-media-v1';
export const NOTIFICATION_TAG_MESSAGE = 'openhand-message';
export const SW_MESSAGE_TYPE_NOTIFY = 'openhand-notify';
