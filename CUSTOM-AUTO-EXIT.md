# FollowHer 联网成功后自动退出修改版

## 2.0.4 双平台版本

仓库、下载与反馈入口统一为 `https://github.com/FollowHer/CampusConnect-auto-exit`，社交主页待补充。Windows 与 macOS 均提供可保存的自动退出开关，默认关闭。原作者及第三方版权声明保留。

macOS 的新增实现位于 `macOS/source/App.swift` 与 `Core.swift`：联网检测完成后重新确认目标网络、配置代次与设置会话；成功时停止定时器、认证流程及校园代理，然后结束应用和菜单栏后台。`--settings` 直接进入设置并在本次运行暂停自动退出。

macOS 生命周期测试覆盖 64 种网络/设置组合、旧回调失效、设置入口以及退出清理，不提交真实校园账号。核心测试同时检查配置兼容和保存恢复。双架构编译、原生 WebKit 检查和退出测试由 GitHub Actions 在 macOS 上运行；只有构建通过才发布运行包。

以下是早期 Windows 2.0.3.1 本机定制的研究与验证记录，不能替代 macOS 构建结果。

基于 Ye9137/CampusConnect 提交 `2434f0164a61d29c175b138c210e8b67a695ac22`，版本 `2.0.3.1-local-auto-exit`。这是本地修改，并非作者发布的正式版本。原项目与第三方许可保持不变。

## 研究结论

官方 Windows 2.0.3 未提供自动退出选项。`MainForm.cs` 拦截普通关闭并隐藏到托盘，20 秒定时器持续检查网络；完整退出只能通过托盘菜单触发。

## 本次实现

- 增加 `CampusProfile.ExitAfterConnected` 和“校园网设置 → 联网成功后自动退出”开关，跟随原配置保存和恢复；兼容旧配置，代码默认关闭。本机部署时会单独开启此选项。
- `CheckInternetAsync` 先确认所选校园网络可用，再检测互联网，并重新确认网络未断开；只对当前配置代次的成功结果执行退出。
- 完整退出触发 FormClosed 清理：失效旧异步任务、取消有线认证、停止定时器与认证流程、释放托盘以及两个 WebView2 控件。不调用断开 Wi-Fi、挂断 PPPoE、修改路由或结束其他应用的操作。
- 新增 `--settings` 启动方式：直接进入设置，本次运行暂不自动退出，便于已联网时修改设置。该入口不会改写已保存的自动退出开关。
- 安装器源码补充相应开始菜单入口；本机部署额外提供桌面“校园网助手设置”。
- 不改变自动连接、开机自启或账号密码；它们继续按用户原设置执行。

## 使用

正常打开“校园 Wi-Fi 助手”，在目标校园网成功联网后进程会退出。以后需要修改配置，打开桌面或开始菜单中的“校园网助手设置”。取消自动退出开关并点击保存，可恢复持续后台重连。

退出后助手不再检测掉线或重新认证。网络是否需要其他客户端持续保活取决于学校，助手不会退出它启动的学校客户端。

继承原项目的联网判定：所选校园网络处于连接状态，且 `ping www.baidu.com` 成功。该 ping 使用系统路由，可能经过 VPN；因此不等同于对校园认证链路的独立验证。未在用户真实校园网环境中完成端到端认证测试。

## 验证与构建

- 原核心测试：2124 项通过（含新增配置兼容、保存恢复测试）。
- Windows 退出测试：64 种组合与真实 WebView2 消息循环、共 200 项断言，验证联网/离线、目标网络断开、配置代次变化、设置模式、开关关闭、有线/Wi-Fi，以及实际 Form.Dispose/WebView.Dispose、普通关闭留托盘和已加载浏览器时自动结束应用循环。
- 原桌面 Playwright 测试通过，新增开关保存与未保存草稿测试；恢复测试 85 项通过，包含刷新后开关草稿恢复。已检查设置界面布局。
- 有线模式界面回归通过。实际程序的离线启动测试同时覆盖 `--startup` 和 `--settings`。
- 本机使用 .NET SDK 10.0.402 构建时，启用 ReadyToRun 的单文件程序未生成界面验证结果；同一产物在禁用 ReadyToRun 后可正常启动。因此本定制版关闭 ReadyToRun，仍包含完整运行环境，不依赖额外安装 .NET。

需要 .NET 10 SDK。执行：

```powershell
dotnet run --project Windows/tests -c Release
dotnet run --project Windows/exit-tests -c Release
dotnet publish Windows/source/CampusConnect.csproj -c Release -r win-x64 --self-contained true -p:PublishReadyToRun=false -o dist
```

官方后续升级会覆盖本机定制程序；如需新版也保留自动退出功能，需要重新应用本修改并编译。
