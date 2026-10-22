# Windows · FollowHer 自动退出版

[下载安装包（x64）](https://github.com/FollowHer/CampusConnect-auto-exit/releases/download/v2.0.4-auto-exit/CampusConnect-Windows-x64-2.0.4-auto-exit-Setup.exe) · [发布页与校验文件](https://github.com/FollowHer/CampusConnect-auto-exit/releases/tag/v2.0.4-auto-exit) · [反馈问题](https://github.com/FollowHer/CampusConnect-auto-exit/issues) · [构建记录](https://github.com/FollowHer/CampusConnect-auto-exit/actions)

支持 Windows 10/11 x64。安装包包含 .NET 运行环境，界面使用 Microsoft WebView2；缺少时安装器会尝试安装。默认安装到当前用户目录。

## 使用

1. 运行安装程序。
2. 在“校园网设置”选择连接方式，填写学校网络、认证地址和账号信息，保存。
3. 根据需要开启自动连接；勾选“联网成功后自动退出”并保存。
4. 助手确认目标网络仍连接且可以上网后，完整退出程序、托盘和内置浏览器控件。

自动退出默认关闭，以兼容旧配置。退出后不再重连；助手不会主动断开 Wi-Fi、挂断宽带或结束学校专用客户端。

## 修改设置

使用开始菜单中的“校园网助手设置”，或运行：

```powershell
CampusConnect.exe --settings
```

本次运行暂不自动退出。取消开关并保存，可恢复持续后台检测和重连。早期本机定制安装还提供同名桌面快捷方式。

## 构建与验证

需要 .NET 10 SDK。从仓库根目录运行：

```powershell
dotnet run --project Windows/tests -c Release
dotnet run --project Windows/exit-tests -c Release
powershell -ExecutionPolicy Bypass -File Windows/build.ps1
```

输出为 `Windows/dist/win-x64/CampusConnect.exe`。安装包另需 NSIS，通过 `Windows/build-installer.ps1` 构建。本修改版关闭 ReadyToRun，以避免已观察到的启动兼容性问题。

网络检测继承原项目的系统路由 ping 判断，VPN 可能影响检测；真实校园认证需在对应学校验证。

本修改版由 [FollowHer](https://github.com/FollowHer) 维护，社交主页待补充。原项目为 [Ye9137/CampusConnect](https://github.com/Ye9137/CampusConnect)，原作者版权及 MIT 许可保留。 详见 [LICENSE](../LICENSE) 和 [第三方许可](../THIRD_PARTY_NOTICES.md)。
