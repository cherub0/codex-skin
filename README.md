# Codex Retro QQ Skin

一套面向 Windows Codex 桌面端的复古 QQ 风皮肤包：蓝银标题栏、经典工具条、QQ 在线资料卡、三栏工作区、右侧摘要/伙伴面板，以及 Codex pet 装饰。

本项目参考并融合了：

- [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin) 的 Windows 安装、启动、恢复、验证和 CDP 注入框架。
- [zhulin025/Codex-QQ-Skin](https://github.com/zhulin025/Codex-QQ-Skin) 的复古 QQ 视觉资产、CSS 和 renderer 注入逻辑。

> 非 OpenAI、腾讯或 QQ 官方产品。本项目不会修改官方 Codex 安装目录、`app.asar`、代码签名、API Key 或 Base URL。

## 效果特点

- 复古蓝银双层标题栏和窗口边框。
- QQ 风头像、在线状态和资料卡。
- Codex 首页宠物装饰和经典浅色蓝银界面。
- 任务页自动适配左侧项目栏、中间对话区、右侧摘要区。
- 右侧保留 Codex 原生输出、来源、进度、子代理等面板。
- 支持一键启动、一键验证、一键恢复官方外观。

## 系统要求

- Windows 10/11。
- 已安装 Microsoft Store 版 `OpenAI.Codex`，并至少正常启动过一次。
- 安装前请完全退出 Codex，避免安装脚本备份 `config.toml` 时配置仍在变化。
- Node.js 22 或更新版本。若系统 PATH 中的 Node 版本较低，可设置 `CODEX_QQ_SKIN_NODE` 指向 Node 22+ 的 `node.exe`。

## 安装

在 PowerShell 中进入项目目录后运行：

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File ".\Install Codex Retro QQ Skin.ps1"
```

安装后运行时会复制到：

```text
%LOCALAPPDATA%\CodexQQSkin\engine
```

安装脚本会创建桌面和开始菜单快捷方式：

- `Codex Retro QQ Skin`
- `Codex Retro QQ Skin - Restore`
- `Codex Retro QQ Skin - Tray`

## 日常使用

启动皮肤版 Codex：

```powershell
.\Start Codex Retro QQ Skin.ps1
```

验证安装和注入状态：

```powershell
.\Verify Codex Retro QQ Skin.ps1
```

恢复官方外观：

```powershell
.\Restore Codex Retro QQ Skin.ps1 -RestoreBaseTheme -PromptRestart
```

默认调试端口是 `9335`。如果端口被占用，可以传入其他端口：

```powershell
.\Start Codex Retro QQ Skin.ps1 -Port 9340
```

## 安全边界

- 只识别 Microsoft Store 的 `OpenAI.Codex` 包。
- CDP WebSocket 只接受 `127.0.0.1`、`localhost` 和 IPv6 loopback。
- 状态、主题和运行时只写入 `%LOCALAPPDATA%\CodexQQSkin`。
- 恢复脚本会停止记录的注入器并恢复保存的 Codex 基础外观配置。
- 运行时会校验主题图片路径、图片尺寸、运行时文件哈希和 CDP 目标身份。

## 项目结构

```text
assets/      QQ 视觉资源、CSS、renderer 注入模板和默认主题
scripts/     Windows 安装、启动、恢复、托盘、验证和注入脚本
tests/       Node 与 PowerShell 回归测试
docs/        设计说明和实施计划
```

## 验证

推荐使用 Node 22+ 运行测试：

```powershell
$env:CODEX_QQ_SKIN_NODE = "C:\path\to\node.exe"
node --test tests\*.test.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

如果 PowerShell 不展开 `tests\*.test.mjs`，可以改用：

```powershell
$files = Get-ChildItem -LiteralPath tests -Filter *.test.mjs | ForEach-Object FullName
node --test @files
```

## 恢复与清理

如果想完全停用皮肤：

```powershell
.\Restore Codex Retro QQ Skin.ps1 -RestoreBaseTheme -PromptRestart
```

恢复脚本会停止注入器、移除暂停/运行状态，并恢复安装前备份的 Codex 外观配置。

## License

请在分发前自行确认上游项目和素材授权边界。本仓库保留来源说明，默认仅用于个人学习和本机自定义。
