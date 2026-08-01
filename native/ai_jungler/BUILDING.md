# 跨平台构建

扫描引擎必须在对应操作系统的可信构建机上编译，不从外部下载二进制。

```bash
scripts/build_ai_jungler.sh host
```

产物目录：

```text
assets/ai_jungler/
├── darwin-arm64/ai_jungler
├── darwin-x64/ai_jungler
├── windows-arm64/ai_jungler.exe
├── windows-x64/ai_jungler.exe
├── linux-arm64/ai_jungler
└── linux-x64/ai_jungler
```

每个平台目录同时生成 `manifest.json`，记录平台、文件名和 SHA-256；OpenHand 解包前会验证清单与二进制。

发布流水线应分别在 macOS、Windows 和 Linux 构建机执行对应平台，再汇总六个产物后构建 Flutter 安装包。在 macOS 构建机执行 `scripts/build_ai_jungler.sh all` 时，Windows 目标使用 `cargo-xwin`，Linux 目标使用 `cargo-zigbuild`；所有目标仍需提前通过 rustup 安装。

仓库内的 `.github/workflows/ai-jungler.yml` 会在对应架构的原生构建机生成并校验六个平台产物，汇总时更新根清单的 `bundledPlatforms`，最终生成 `ai-jungler-all-platforms` 构建制品。未生成的平台目录只保留说明文件，不能作为发布产物。
