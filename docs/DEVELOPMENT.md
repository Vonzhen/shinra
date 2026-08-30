# Shinra 开发与发布流程

Shinra 以 OpenWrt 25.12 及更高版本为主要目标，发布物以 APK 为主；IPK 只保留为旧系统兼容构建，不作为日常验收目标。

## 不可变约束

下列规则是已确认的产品与发布契约。除非先完成影响分析并获得明确批准，不得通过“顺手优化”、CI 改造或重构改变它们。

### 发布契约

- `dev` 的 **Verify Shinra on OpenWrt** 只用于静态检查和临时 APK/IPK 验证 artifact；它不是 Release。
- `master` 只接收已验证的 `dev`，不得因为普通推送自动创建 Release 或替换正式下载入口。
- 只有 `master` 上的 `vX.Y.Z` tag 触发 **Release Shinra Packages**。
- 正式 Release 的文件名必须保持由包元数据生成的稳定格式：`luci-app-shinra_<版本>-1_all.ipk` 与 `luci-app-shinra_<版本>-r1_all.apk`。不得以 commit SHA、CI run number 或临时 artifact 名替代。

### 业务访问契约

- Shinra 使用 Zashboard；面板兼容接口来自 sing-box 的 `experimental.clash_api`。
- 内网直连是默认和优先路径。反向代理、公网访问、TLS、路径重写、WebSocket 转发和访问控制均属于外部网关配置，不属于 Shinra 的功能或兼容承诺。
- Dashboard 的下载来源、Clash API 监听地址、访问密钥和默认模式由 LuCI 面板设置保存，并在生成配置时写入 sing-box。

## 分支职责

- `dev`：唯一开发与集成分支。功能修改先进入这里，并必须通过 GitHub Actions。
- `master`：已验证的发布分支。不得直接推送业务修改，只接收来自 `dev` 的 Pull Request。
- `vX.Y.Z` 标签：仅在 `master` 的已验证提交上创建；标签触发 GitHub Release，附加独立的 APK 和 IPK 文件。

## 必经流程

1. 从 `dev` 创建功能分支，完成修改后提交 Pull Request 到 `dev`；个人小改动也可以直接推送到 `dev`。
2. 等待 **Verify Shinra on OpenWrt** 通过。
3. 在真实 OpenWrt 25.12+ 设备安装 GitHub Actions 生成的 APK，确认 LuCI、生成并应用配置、sing-box 运行及 Dashboard 可用。
4. 创建 `dev` 到 `master` 的 Pull Request；只在 `dev` 已通过且设备验收完成时合并。
5. 确认版本号后，在合并提交创建 `vX.Y.Z` 标签。
6. 等待 **Release Shinra Packages** 完成，并从 Release 下载 APK；IPK 仅在确有旧系统兼容需求时使用。

建议在 GitHub 仓库设置中为 `master` 启用分支保护：要求 Pull Request、要求 **Verify Shinra on OpenWrt** 状态检查通过，并限制直接推送。

## GitHub 自动测试范围

每次 `dev` 推送和所有以 `dev` 或 `master` 为目标的 Pull Request，都会执行：

1. JSON、Git diff、GitHub Actions YAML 与 LuCI JavaScript 语法检查。
2. APK 与 IPK 的构建；APK 是主要交付物。

容器化 OpenWrt 测试不作为门禁：它不能可靠模拟 procd、TUN、路由、防火墙和实际 WAN，维护成本高于收益。每次准备将 `dev` 合并到 `master` 时，改为在真实 OpenWrt 25.12+ 设备安装 CI 生成的 APK，完成一次设备验收。
