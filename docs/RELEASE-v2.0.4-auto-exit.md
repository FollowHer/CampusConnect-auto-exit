# FollowHer 自动退出版 2.0.4

基于 Ye9137/CampusConnect 的独立修改版；原作者版权及 MIT 许可保留。

- Windows 与 macOS 均增加“联网成功后自动退出”开关，默认关闭，保存后生效。
- 仅在目标网络仍连接、配置未变化且互联网检测成功后完整退出。
- `--settings` 启动直接进入设置，本次运行暂不自动退出。
- 本修改版的下载、源码与问题反馈入口统一到 FollowHer 仓库。社交主页待补充。
- macOS 提供 Apple 芯片与 Intel 通用应用；Windows 提供 x64 安装包。

macOS 使用临时签名，未完成 Apple Developer ID 签名与公证。退出后不再自动重连。联网检测使用系统路由 ping，可能受 VPN 影响；真实校园网认证仍需在对应学校验证。

构建流程运行核心、认证脚本、自动退出生命周期和平台启动检查，并提供 SHA256SUMS.txt。
