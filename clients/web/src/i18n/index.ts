// Web 端最小化 i18n 骨架。Stage 2 仅引入框架与 zh-Hans 词表，后续阶段
// 按需补充 en / 其他语言。t(key) 缺词时 fallback 到 key 本身，方便快速迭代。

const dict: Record<string, string> = {
  'app.title': 'Web 通用消息平台',
  'app.brand': 'OpenHand · Web 通用消息平台',
  'common.copy': '复制',
  'common.copied': '已复制',
  'common.loading': '加载中…',
  'common.retry': '重试',
  'common.cancel': '取消',
  'common.confirm': '确定',
  'common.logout': '退出登录',
  'home.theme.source.api': '主题来源：与 OpenHand 主控制台同步',
  'home.theme.source.default': '主题来源：默认 token',
  'home.urls.title': '可访问 URL（点击复制）',
  'home.urls.empty': '当前 service 未返回 accessible_urls。',
  'home.next.stages': '后续阶段：会话 / 多类型消息 / 文件 / Ops 仪表盘。',
  'login.title': '登录 Web 通用消息平台',
  'login.subtitle': 'OpenHand 主控制台已开启鉴权，请输入用户名与密码',
  'login.username': '用户名',
  'login.password': '密码',
  'login.submit': '登录',
  'login.submitting': '登录中…',
  'login.error.empty': '用户名和密码不能为空',
  'login.error.network': '网络异常，无法连接到 service',
  'login.error.invalid': '用户名或密码错误',
  'login.anonymous.notice': '当前 service 未启用鉴权，可直接进入首页',
  'login.anonymous.enter': '直接进入',
  'guard.checking': '检查鉴权状态…',
  'guard.required': '需要先登录才能访问',
};

export function t(key: string, fallback?: string): string {
  return dict[key] ?? fallback ?? key;
}
