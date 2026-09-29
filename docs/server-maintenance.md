# 服务器运维面板

机器专家 → 左侧终端 → 执行历史右侧的「服务器运维」。所有查询和操作均使用当前终端连接，不建立额外 SSH 会话，也不自动提权或安装软件。

## 分区

| 分区 | 内容 |
| --- | --- |
| 运行总览 | CPU 总体/每核使用率与趋势，内存、SWAP、运行时间、负载，磁盘容量/inode/IO，网卡吞吐/丢包，内存分页/交换，资源压力、温度、块设备/RAID、内核参数、控制组限制 |
| 进程管理 | PID/名称筛选，CPU/内存/PID 排序，分页，进程状态、命令行、工作路径、IO、内存映射汇总、资源限制、控制组、文件描述符；终止/暂停/恢复 |
| 系统服务 | 服务列表、运行状态、详情；按管理器支持启动/停止/重启、启动级别管理；systemd 属性、日志、定时器 |
| 网络与诊断 | 监听连接、地址/路由、DNS、日志、登录用户、当前用户计划任务、防火墙规则、Docker/Podman 容器列表 |

刷新开关和 5/10/30/60 秒间隔作用于当前分区；间隔从上次采集完成后开始。手动刷新默认开启，自动刷新默认关闭。切入后台或打开详情暂停自动采样；失败后停止自动重试，手动刷新成功后恢复。关闭面板取消计时并停止后续脚本分块，已执行命令由终端超时机制收尾。

面板采用紧凑导航、资源摘要和左侧资源／中间机器详情／右侧操作的三栏布局；系统信息按平台明确解析，完整命令输出通过详情入口查看，不按冒号猜测字段。网络页展示已解析的 TCP/UDP 连接、DNS 与诊断入口；进程表用短名称、完整路径提示和中文状态。存储摘要略去 macOS 辅助系统卷、模拟器卷与虚拟文件系统，完整列表仍保留在详情。窄窗口与大字体自动减少列数，失败状态优先展示原因与重试入口。分区过渡遵循全局弹窗动效设置，定时刷新不重复触发进场动画。列表、表格和详情限制高度并滚动；进程每页 40 条，服务列表惰性构建。CPU 趋势保留最近 60 个有效点。

## 跨平台适配

平台策略按当前终端实际目标选择，独立于运行 OpenHand 的宿主系统；Shell 协议支持 POSIX、PowerShell 和 CMD。先探测目标，再选择采集、进程管理与服务管理策略；面板提供 Shell 协议选择。切换平台清除旧采样，操作前重新验证主机与启动标识。

| 目标 | 采集方式 | 服务管理 | 边界 |
| --- | --- | --- | --- |
| Linux（CentOS、Debian、Ubuntu、Arch 等） | `/proc`、`/sys` 与可用系统工具 | systemd、OpenRC、runit、SysV | 按能力识别，不依赖发行版名称或 Python；容器显示可读的内核视图与控制组限制 |
| macOS | sysctl、top、vm_stat、ioreg、netstat、ps | 当前 bootstrap 上下文中的 launchd | 内存可用量为估算；无通用每核 CPU 计数时明确说明；进程支持终止、暂停、恢复 |
| Windows / Windows Server | 系统 WSH/JScript 调用 WMI，CMD 和 PowerShell 共用采集脚本 | Windows SCM | 不依赖 PowerShell 版本、WMIC 或第三方运行时；进程仅提供终止；需启用 WSH、JScript 与 WMI |

Windows 使用老系统已有的 WMI/WSH 接口，以兼容 XP、7、8、10、11 和不同 Server 版本；可选属性及性能类缺失时显示不可用，旧版防火墙查询使用相应命令。Windows 9 没有正式发行版。这里的兼容性指终端连接的目标机器，不代表 Flutter 桌面客户端可安装于 XP 等旧系统；未经过实机矩阵验证，不能保证全部版本和系统裁剪环境可用。

工具缺失、内核接口不可读或权限不足时展示原因或不可用，不填零冒充正常状态。未知服务管理器保留监控能力。Linux 指标依据 [proc 文档](https://docs.kernel.org/filesystems/proc.html) 和 [块设备统计文档](https://docs.kernel.org/block/stat.html)；Windows 使用 WMI 接口，避免依赖[逐步移除的 WMIC](https://support.microsoft.com/en-us/servicing/os/windows/docs/2025/09/windows-management-instrumentation-command-line-wmic-removal-from-windows)。

Linux CPU 排除重复的 guest 字段，磁盘扇区按 512 字节换算；Windows 原始性能计数器和 macOS 原生统计转换为统一指标。速率用目标机采样时间差计算，macOS CPU 使用 top 的采样结果。目标变化、重启、时间或计数器回退、进程 PID 重用时不复用无效差值。

## 执行边界

- 复用文件管理的终端门闩、分块传输、临时文件清理与 `recordHistory: false`；辅助命令和结果不写入应用的终端持久化历史。实时终端仍会显示命令执行过程。
- 单条终端命令最长等待 30 秒；Linux 有 `timeout` 时对较慢查询额外设置 5 秒限制。Windows 脚本传输总时限 2 分钟，cscript 自身时限 25 秒，外部诊断子命令最多等待 4 秒；不发起无限重试。终端被文件操作占用时立即提示。
- 服务名称严格校验并按 shell 参数转义；操作需确认，并验证目标主机/启动标识。进程操作前校验 PID 启动标识；禁止控制 Unix PID 1、Windows PID 4 及以下，无可验证启动标识时不提供控制。Windows 服务重启有停止状态等待上限。
- 进程每批最多 512 条，可用上一批/下一批继续浏览；筛选与排序作用于当前批次。其他诊断输出按命令限制到 8–50 KB；Windows WMI 单次枚举最多 16384 条、编码输出总预算 100000 字符，截断时提示，防止输出挤爆终端缓冲区。
- 未实现独立服务器面板的应用商店、网站部署、数据库管理、证书签发、备份恢复、账号/软件包编辑；当前不能宣称与 1Panel 全功能等价。

## 界面语言

运维标题、字段、提示、操作和状态使用应用 ARB 资源，覆盖简体中文、繁体中文、英语、法语、德语和日语。已知系统字段和网络表头按当前语言展示，可切换原始输出；主机名、地址、路径、命令和日志正文保留原值。

## 验证

```sh
dart run scripts/check_machine_maintenance.dart
dart run scripts/check_machine_maintenance_platforms.dart
dart run scripts/check_machine_maintenance_widgets.dart
dart run scripts/check_imports.dart
bash scripts/build_web.sh
```

检查覆盖采样协议、单位换算、重启/回退、注入输入、Linux 服务策略、POSIX 脚本语法、Shell 探测、CMD/PowerShell 回显边界和 Windows WMI 模拟执行。组件检查覆盖六种语言切换、已知字段翻译与原始数据保真、三平台动作差异、浅深主题、窄窗口、大字体、详情弹窗、列表限高、刷新间隔、串行采样、失败暂停及关闭清理。

本机 macOS 已实际执行总览、进程、服务与诊断采集，并以真实输出检查四个分区的浅深主题布局；Windows 脚本经过模拟 WMI 执行，尚未在真实 CMD/PowerShell、XP 或 Windows Server 上联调。Linux 发行版、权限及 SSH 的完整实机矩阵仍待验证。
