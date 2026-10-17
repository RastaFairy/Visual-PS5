# 用户手册 — PS5 Homebrew Studio 1.1.0

最后更新：2026 年 10 月 17 日。应用界面目前仍为西班牙语；手册翻译并不表示 UI 本身已完成本地化。

## 1. 环境要求

运行 IDE 需要 Windows 10/11 和应用目录读写权限，建议使用 PowerShell 7；启动器也支持 Windows PowerShell 5.1。

编译标题需要 Git、WSL/Linux 及所选后端的上游依赖。SharpProspero/C# 需要已安装上游版本要求的 .NET。原生 C++ 模板需要兼容工具链。UltraPack 需要 Python 3.10 或更高版本及 [PS5 UltraPack](https://github.com/knutwurst/ps5-ultrapack) 源码仓库。

## 2. 安装与启动

1. 下载或构建要测试的分支软件包。
2. 解压到可写目录，不要放入 Windows 受保护目录。
3. 运行 start.bat，并保持 PowerShell 服务窗口打开。
4. 若浏览器没有自动打开，请访问 http://127.0.0.1:47813/。
5. 关闭服务窗口或运行 STOP.bat 即可停止服务。

服务只监听 127.0.0.1。不要将其暴露到网络，也不要改为监听 0.0.0.0。项目默认保存在 Documents/PS5HomebrewStudio/Projects。

## 3. 界面与可视化项目

1920×1080 画布是虚拟工作区，并非 PS5 系统界面的精确截图。使用组件面板添加控件、属性检查器修改位置和属性、层级面板整理元素，并通过屏幕管理器组织界面。流程编辑器可以把事件连接到 notify、setText、toggleVisibility、setValue、changeColor、navigate 等操作，但必须由选定的后端和组件支持。

创建项目后，在准备依赖前先选择后端。添加组件和资源，保持 ID 唯一并配置屏幕。运行诊断并修复无效目标。使用 Ctrl+S 保存。导出模型或 ZIP 不等于编译原生标题。

## 4. 后端与构建

**SharpProspero / C#：** 使用真实的上游构建流程和 .NET/NativeAOT；请确认当前提交要求的 .NET 版本。

**原生 OpenGL / C++20：** 根据 ps5-homebrew-ui 接口生成界面。图像转换为 RGBA8，每张屏幕最多 512×512 像素、16 个唯一纹理 ID。

**Vulkan/RADV / C++20：** 通过 PS5_VulkanTemplate 创建标题并集成兼容的 Vulkan UI 模块。PS5_Vulkan、PS5_Mesa/RADV、PS5_PayloadSDK 与 PS5_VKHomebrewUI 版本必须兼容。

IDE 会运行真实的上游构建脚本并保留日志。退出代码为 0 并不足够：原生标题打包还要求 eboot.bin 和 sce_sys/param.json。IDE 不提供 Sony 专有 SDK，也不保证兼容所有固件。

## 5. 使用 UltraPack 打包

1. 打开“工具”，配置 Python 3.10+ 和 UltraPack 的 backend/cli.py。
2. 保存设置；路径只写入本地 .runtime/integrations.json。
3. 选择已构建的原生项目并点击“打包”。
4. 选择 .ffpfs、.ffpfsc 或 .pkg。Windows 下 .pkg 需要原生 helper 及其依赖。
5. 保持“对照源文件验证内容”选项开启，以向 UltraPack 传递 --verify。验证可能增加时间和内存使用。
6. 检查最终日志、退出代码、输出路径及警告。旧文件不能证明本次运行成功。

输出按格式和时间戳保存在 packages-ultrapack 下。打包任务在后台运行。维护者报告称生成的 .ffpfsc 镜像已在真实硬件上成功测试；这并不保证所有标题、固件或后端均已验证。

## 6. 测试与故障排查

安装 Node.js 后，在应用目录运行 node --check app.js、node --check runtime/native-generator.js 和 node runtime/test-native-generator.js。这些测试检查 JavaScript 语法和生成器案例，不能替代完整 PS5 工具链构建或真实主机测试。

若服务无法启动，请保留完整错误并检查 PowerShell 和目录权限。若构建失败，记录后端、上游版本和提交、完整日志及退出代码。若 UltraPack 失败，检查 Python/cli.py 路径、eboot.bin、sce_sys/param.json 和输出目录权限。不要分享密钥或令牌。

## 7. 许可与范围

SDK、驱动、模板和 UI 工具包均保留各自许可。发布二进制前请检查 LICENSE、COPYING、NOTICE 和再分发条件。Visual-PS5 不是 Sony 官方 SDK，不包含固件、密钥、游戏或 BIOS，也不会自动将标题安装到主机。编辑器预览不是 PS5 模拟器，无法验证运行时、音频、输入或持久化。
