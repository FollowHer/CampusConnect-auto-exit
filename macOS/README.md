# macOS · FollowHer 自动退出版

[下载本修改版](https://github.com/FollowHer/CampusConnect-auto-exit/releases/download/v2.0.4-auto-exit/CampusConnect-macOS-universal-2.0.4-auto-exit.zip) · [发布页与校验文件](https://github.com/FollowHer/CampusConnect-auto-exit/releases/tag/v2.0.4-auto-exit) · [反馈问题](https://github.com/FollowHer/CampusConnect-auto-exit/issues) · [构建记录](https://github.com/FollowHer/CampusConnect-auto-exit/actions)

需要 macOS 14 或更新版本。同一个 `CampusConnect.app` 包含 arm64 和 x86_64 两种架构，支持 Apple 芯片和 Intel。

## 安装与使用

1. 解压 ZIP，将 `CampusConnect.app` 移到“应用程序”目录。
2. 应用使用临时签名，未完成 Developer ID 公证。若系统拦截，请核对来源与 SHA-256，再按系统提示决定是否允许打开。
3. 在“校园网设置”填写学校网络和认证信息。Wi-Fi 模式需要读取网络名称的定位授权；有线模式不需要 Wi-Fi 定位权限。
4. 按需开启自动连接，勾选“联网成功后自动退出”，点击保存。
5. 目标校园网络可以上网后，助手停止检查、网页加载和认证代理，并结束应用及菜单栏后台。

旧配置默认关闭自动退出。退出后不会自动重连，需重新打开助手；助手不会结束学校专用客户端。

## 修改设置时保留窗口

助手退出后，在终端运行：

```sh
open -a CampusConnect --args --settings
```

本次运行直接进入设置，暂不自动退出；它不会永久修改自动退出开关。正常重新启动后恢复已保存行为。

## 本地构建与测试

在安装了 Xcode Command Line Tools 的 Mac 上，从仓库根目录运行：

```sh
zsh macOS/test.sh
zsh macOS/test-webkit.sh
zsh macOS/test-lifecycle.sh
zsh macOS/source/build.sh
```

输出为 `macOS/CampusConnect.app`。GitHub Actions 完成相同检查并生成通用 ZIP。生命周期测试使用模拟联网结果，不提交真实校园账号。

网络检测继承原项目的系统路由 ping 判断，VPN 可能影响检测；真实校园认证需在对应学校验证。

本修改版由 [FollowHer](https://github.com/FollowHer) 维护，社交主页待补充。原项目为 [Ye9137/CampusConnect](https://github.com/Ye9137/CampusConnect)，原作者版权及 MIT 许可保留。 详见 [LICENSE](../LICENSE)。
