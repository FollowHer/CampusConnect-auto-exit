# macOS 版

适用 macOS 14 或更新版本，支持 Apple 芯片和 Intel 芯片。

## 1.3.4 连接恢复与即时导航

- 两平台均使用即时悬停选择，内容推进动画为 280ms；认证准备、SSID 查询和联网检查不阻塞导航。
- 学校认证初始化在 DOM 就绪时开始，无须等背景图片；参数和加密公钥就绪后以 150ms 检查间隔尽早填写、提交，提交后 1 秒开始检查互联网。

- 侧边栏移入即切换，无悬停计时器；页面常驻，推进动画仅作用于内容，快速切页不会重新挂载认证浏览器。
- 保持 Wi-Fi 连接时每 20 秒继续检查互联网，严格校验两个不同站点的响应；探测走物理 Wi-Fi 并禁用缓存和重定向。
- 认证失效后自动重新认证；网络超时连续两次才触发恢复，重试间隔逐步从 60 秒增加至最多 300 秒。手动填写、特殊表单不反复刷新。

## 1.3.3 更新

- 精简为网络概览、校园网设置、上网认证三个页面。
- 鼠标悬停 100ms 切换菜单，页面以 480ms 双向推进动画切换。
- 新增登录自启开关，使用 macOS 登录项管理，默认不主动开启。
- 左下角显示小字 By Ye 和“MIT 开源项目”。普通界面文字不可选中，输入框仍可编辑、选择和粘贴。

## 安装与使用

1. 下载并解压 `CampusConnect-macOS-universal.zip`。
2. 将 `CampusConnect.app` 拖到「应用程序」，双击打开。
3. 此包使用本地临时签名，未经过 Apple Developer ID 签名和公证。若系统拦截，请确认下载来源后，在「系统设置 → 隐私与安全性」中允许打开。
4. 在应用「网络概览」点击授权定位，允许读取 Wi-Fi 名称。
5. 在「校园网设置」填入校园账号密码并保存，点击「立即连接」。默认不自动连接，可自行开启。
6. 关闭窗口后保留在菜单栏，在菜单栏选择退出可完全关闭。

账号密码仅保存于本机：`~/Library/Application Support/CampusConnect/configuration.json`。延续原版的本地明文存储方式，配置目录权限为 700，文件权限为 600，不访问系统钥匙串。请勿分享该文件。

## 从源码构建

```sh
xcode-select --install
zsh macOS/source/build.sh
```

请在仓库根目录执行。输出 `macOS/CampusConnect.app`，包含 `arm64` 和 `x86_64` 两种架构。运行检查：

```sh
zsh macOS/test.sh
codesign --verify --deep --strict macOS/CampusConnect.app
lipo -archs macOS/CampusConnect.app/Contents/MacOS/CampusConnect
```

应用内部认证连接可绑定物理 Wi-Fi，适用于部分 VPN 干扰校园认证的情况。并不修改系统 VPN 配置。不同学校的验证码、运营商选择等页面需手动处理。
