# Visual-PS5 — PS5 Homebrew Studio 1.1.6

面向 Windows 的本地可视化 IDE，用于设计界面、管理项目、检查代码、生成 C++20 UI，并通过 PS5 社区工具链协调构建。

**语言状态：** 应用界面目前仍为西班牙语。中文版手册已提供，界面翻译将另行进行。

## 1.1.6 版本更新

- 新增**“结构”**视图，将可编辑的可视化屏幕与原生 C++ 代码中识别出的菜单状态分开显示，并提供可搜索的树、转换关系图、检测到的菜单文本和源代码行跳转。C++ 转换来自静态推断，仍需人工核实。
- 修复了 UltraPack 和“演示资源”对话框中的操作按钮。
- IDE 生成的原生 OpenGL 项目现在使用项目自己的 `build.ps1` 和本地依赖，避免在未启用 `metadata` 的 WSL/DrvFS 挂载中重复准备共享 SDK 时出现失败。
- 编译前可选择应用图标、选择背景、启动背景和音乐；新增屏幕管理以及每个屏幕独立的图层排序。
- 维护者已在 Windows/WSL 环境确认 OpenGL 编译和 UltraPack 打包可用。完整 Vulkan 编译、ATRAC9 转换以及在实体 PS5 上运行仍未验证。请参阅[已知问题与验证状态](PS5-Homebrew-Studio/docs/KNOWN-ISSUES.es-ES.md)。

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
- [已知问题与验证状态](PS5-Homebrew-Studio/docs/KNOWN-ISSUES.es-ES.md)

## 快速开始

1. 下载或构建目标开发分支的软件包。
2. 在 Windows 10/11 上解压到可写目录。
3. 运行 `PS5-Homebrew-Studio/start.bat`；如果浏览器未自动打开，请访问 http://127.0.0.1:47813/。

建议使用 PowerShell 7，也支持 Windows PowerShell 5.1。原生编译需要 Git、WSL/Linux 以及所选模板的依赖。服务仅监听 127.0.0.1。

编译与打包成功本身并不能证明软件可在实体 PS5 上运行；当前验证状态请参阅已知问题文档。Visual-PS5 不是 Sony 官方 SDK，不包含专有文件、固件、密钥、游戏或 BIOS。