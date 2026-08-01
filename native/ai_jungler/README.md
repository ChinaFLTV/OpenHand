# OpenHand AI 基础设施暴露面扫描引擎

`ai_jungler` 是 OpenHand 自研的本地扫描引擎，只面向用户明确授权的目标。

## 安全边界

- 所有目标必须命中任务声明的域名、主机或 CIDR 授权范围。
- FOFA、Shodan、GitHub、Gitee、GitCode 仅使用用户提供的 API 凭证和平台配额。
- 可选代理池覆盖数据源发现、目标探测、主动验证和 GPT 辅助请求，支持固定、顺序轮询、随机及目标粘性选路。
- 规则引擎可对 Base64、Base64URL、URL 编码和 Hex 内容进行有界解码扫描。
- 默认仅执行被动 HTTP 探测，不进行弱口令、漏洞利用或权限绕过。
- 原始凭证使用 AES-256-GCM 加密后写入独立 SQLite 数据库。
- PostgreSQL 可选镜像任务数据，Redis 可选协调多实例目标租约；连接串只驻留进程内存。
- 守护进程仅监听随机 `127.0.0.1` 端口，并要求会话令牌。

## 开发运行

```bash
cargo run -p hunt-daemon -- serve --data-dir /tmp/openhand-ai-jungler
```

启动后从标准输入发送一行会话令牌。进程会在标准输出返回包含本地地址的 JSON。
