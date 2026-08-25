# Shinra 开发与发布流程

Shinra 以 OpenWrt 25.12 及更高版本为主要目标，发布物以 APK 为主；IPK 只保留为旧系统兼容构建，不作为日常验收目标。

## 分支职责

- `dev`：唯一开发与集成分支。功能修改先进入这里，并必须通过 GitHub Actions。
- `master`：已验证的发布分支。不得直接推送业务修改，只接收来自 `dev` 的 Pull Request。
- `vX.Y.Z` 标签：仅在 `master` 的已验证提交上创建；标签触发 GitHub Release，附加独立的 APK 和 IPK 文件。

## 必经流程

1. 从 `dev` 创建功能分支，完成修改后提交 Pull Request 到 `dev`；个人小改动也可以直接推送到 `dev`。
2. 等待 **Verify Shinra on OpenWrt** 通过。
3. 创建 `dev` 到 `master` 的 Pull Request；只在 `dev` 已通过且该 PR 检查通过时合并。
4. 确认版本号后，在合并提交创建 `vX.Y.Z` 标签。
5. 等待 **Release Shinra Packages** 完成，并从 Release 下载 APK；IPK 仅在确有旧系统兼容需求时使用。

建议在 GitHub 仓库设置中为 `master` 启用分支保护：要求 Pull Request、要求 **Verify Shinra on OpenWrt** 状态检查通过，并限制直接推送。

## GitHub 自动测试范围

每次 `dev` 推送和所有以 `dev` 或 `master` 为目标的 Pull Request，都会执行：

1. JSON、Git diff、GitHub Actions YAML 与 LuCI JavaScript 语法检查。
2. APK 与 IPK 的构建；APK 是主要交付物。
3. 基于官方 OpenWrt 25.12 x86_64 rootfs 的 APK 集成测试：安装刚构建的 APK，启动 `ubusd` 和 `rpcd`，调用 Shinra ubus API，生成并用 `sing-box check` 检查候选配置，并确认候选配置不含 Clash API。

这覆盖 Shinra 的包安装、UCode 模块加载、rpcd、默认配置、配置生成和 sing-box 配置校验。它不模拟真实路由器的目标 CPU、网卡驱动、TUN/防火墙与实际 WAN；涉及这些边界或大版本升级时，仍建议在实际设备完成一次验收。
