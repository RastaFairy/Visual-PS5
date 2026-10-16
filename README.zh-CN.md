# Visual-PS5 — PS5 Homebrew Studio 1.1.0

面向 Windows 的本地可视化 IDE，用于设计界面、管理项目、检查代码、生成 C++20 UI，并通过 PS5 社区工具链协调构建。

**语言状态：** 应用界面目前仍为西班牙语。中文版手册已提供，界面翻译将另行进行。

## 文档

- [简体中文用户手册](docs/USER-MANUAL.zh-CN.md)
- [西班牙语手册](docs/MANUAL.es-ES.md)
- [英语手册](docs/USER-MANUAL.en-GB.md)
- [法语手册](docs/USER-MANUAL.fr-FR.md)
- [德语手册](docs/USER-MANUAL.de-DE.md)
- [日语手册](docs/USER-MANUAL.ja-JP.md)
- [俄语手册](docs/USER-MANUAL.ru-RU.md)
- [开发者致谢与上游归属](docs/CREDITS.md)
- [SDK 与上游项目矩阵](release/UPSTREAM-SDK-MATRIX.md)
- [更新日志](docs/CHANGELOG.md)

## 快速开始

1. 下载或构建目标开发分支的软件包。
2. 在 Windows 10/11 上解压到可写目录。
3. 运行 start.bat；如果浏览器未自动打开，请访问 http://127.0.0.1:47813/。

建议使用 PowerShell 7，也支持 Windows PowerShell 5.1。原生编译需要 Git、WSL/Linux 以及所选模板的依赖。服务仅监听 127.0.0.1。

维护者报告称 .ffpfsc 镜像已在真实硬件上测试成功；这不代表所有标题和固件组合均已验证。Visual-PS5 不是 Sony 官方 SDK，不包含专有文件、固件、密钥、游戏或 BIOS。