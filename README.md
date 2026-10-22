# CampusConnect · FollowHer 自动退出版

校园网自动连接与网页认证助手，支持 Windows 和 macOS。本修改版由 [FollowHer](https://github.com/FollowHer) 维护，在原项目基础上增加 **联网成功后彻底退出后台**，并提供不会自动退出的设置入口。

这是独立修改版。原作者及第三方版权保留，项目继续按 [MIT 许可证](LICENSE) 开源。社交主页尚未添加，暂时通过本仓库反馈问题。

[发布页与校验文件](https://github.com/FollowHer/CampusConnect-auto-exit/releases/tag/v2.0.4-auto-exit) · [反馈问题](https://github.com/FollowHer/CampusConnect-auto-exit/issues) · [构建记录](https://github.com/FollowHer/CampusConnect-auto-exit/actions) · [源码](https://github.com/FollowHer/CampusConnect-auto-exit)

## 下载

| 平台 | 本修改版运行包 | 要求 |
| --- | --- | --- |
| Windows x64 | [下载安装包](https://github.com/FollowHer/CampusConnect-auto-exit/releases/download/v2.0.4-auto-exit/CampusConnect-Windows-x64-2.0.4-auto-exit-Setup.exe) | Windows 10/11 64 位；包含 .NET 运行环境；界面需要 WebView2 |
| macOS 通用版 | [下载应用 ZIP](https://github.com/FollowHer/CampusConnect-auto-exit/releases/download/v2.0.4-auto-exit/CampusConnect-macOS-universal-2.0.4-auto-exit.zip) | macOS 14+；同一应用支持 Apple 芯片和 Intel |

发布页提供 SHA-256 校验文件。应用由本仓库 GitHub Actions 从源码构建。首次构建未完成时，可在[构建记录](https://github.com/FollowHer/CampusConnect-auto-exit/actions)查看进度；下载入口不会跳转到原作者的旧版本。

macOS 应用使用临时签名，未完成 Apple Developer ID 签名及公证。若系统拦截打开，请先核对下载来源和校验值，再按 macOS 系统提示决定是否允许打开。

## 修改版功能

- **联网成功后自动退出**：设置开关保存后生效；仅在目标校园网络仍连接且互联网检测成功时执行。
- **完整停止后台工作**：停止定时检查和网页认证。Windows 释放托盘及 WebView2 控件；macOS 停止认证代理，结束应用和菜单栏后台。
- **设置入口保留窗口**：使用 `--settings` 启动时，本次运行暂不自动退出，便于已联网时修改配置。
- **兼容原配置**：旧配置默认关闭新开关；账号、自动连接和开机自启设置保持原样。需要自动退出时请开启并保存。

退出后不再检测掉线、重连或重新认证。需要时重新打开助手，或关闭自动退出以持续后台运行。助手不会主动断开 Wi-Fi、挂断宽带或结束学校专用客户端。

## 使用

1. 安装或解压对应平台应用。
2. 在“校园网设置”选择 Wi-Fi 或有线模式，填写学校网络名称、认证地址和账号信息，保存。
3. 根据需要开启自动连接；开启“联网成功后自动退出”并保存。
4. 点击“立即连接”。助手按配置认证，确认目标校园网可以上网后退出。

默认 SSID 为 `HNPI-STU`，认证地址为 `http://192.168.0.123`，请按学校实际情况修改。验证码、多步登录或学校客户端内部认证仍可能需要人工处理。

### 已联网时修改配置

- **Windows**：开始菜单打开“校园网助手设置”，或运行 `CampusConnect.exe --settings`。早期本机定制安装还提供同名桌面快捷方式。
- **macOS**：助手退出后，在终端运行：

  ```sh
  open -a CampusConnect --args --settings
  ```

  应用放在其他目录时，可把 `CampusConnect` 换为 `.app` 完整路径。退出本次设置会话后，正常重新启动才恢复自动退出。

## 适配与联网判断

支持网页认证、有线 PPPoE、系统已配置的 802.1X，以及启动已安装的学校客户端。原项目列出的支持学校包括河南工业职业技术大学、郑州信息工程职业学院、无锡职业技术大学、天津石油职业技术学院、华东交通大学和南通大学。本修改版仍需在真实学校网络验证，不代表适配所有学校。

联网检测继承原项目：目标网络可用，且 `ping www.baidu.com` 成功。ping 使用系统路由，可能经过 VPN，因此并非对校园网认证链路的独立验证。

## 构建与测试

```sh
git clone https://github.com/FollowHer/CampusConnect-auto-exit.git
cd CampusConnect-auto-exit
```

Windows 需要 .NET 10 SDK；安装包另需 NSIS：

```powershell
dotnet run --project Windows/tests -c Release
dotnet run --project Windows/exit-tests -c Release
powershell -ExecutionPolicy Bypass -File Windows/build.ps1
```

macOS 需要 Xcode Command Line Tools：

```sh
zsh macOS/test.sh
zsh macOS/test-webkit.sh
zsh macOS/test-lifecycle.sh
zsh macOS/source/build.sh
```

Mac 应用需要在 macOS 环境中编译。[Actions 工作流](https://github.com/FollowHer/CampusConnect-auto-exit/actions/workflows/build.yml)负责构建、测试和发布。[Windows 说明](Windows/README.md) · [macOS 说明](macOS/README.md) · [修改记录](CUSTOM-AUTO-EXIT.md)。

## 维护与反馈

- 维护者：[FollowHer](https://github.com/FollowHer)
- 本修改版反馈：[提交 Issue](https://github.com/FollowHer/CampusConnect-auto-exit/issues)
- 社交主页：待补充。

反馈请说明系统版本、学校和复现步骤。请移除账号、密码、配置文件、浏览器缓存及带身份参数的认证地址。

## 来源与许可

本修改版由 [FollowHer](https://github.com/FollowHer) 维护，社交主页待补充。原项目为 [Ye9137/CampusConnect](https://github.com/Ye9137/CampusConnect)，原作者版权及 MIT 许可保留。

本仓库的下载、源码、构建和反馈入口均指向 FollowHer 修改版；来源说明中的上游链接仅用于署名与溯源。第三方组件遵循各自许可，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [licenses](licenses/)。
