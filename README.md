# Shinra

Shinra 是面向 OpenWrt 25.12+ 的 sing-box TUN 与 LuCI 管理插件。APK 是主要交付物；IPK
仅用于旧系统兼容。

## Dashboard 访问模型

Shinra 使用 Zashboard，并通过 sing-box 的 `experimental.clash_api` 提供面板所需
的兼容 API。默认使用内网直连；反向代理和公网访问不属于 Shinra 管理范围。

详细的开发、验收与发布流程见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

## Release

仅从已验证的 `master` 提交创建 `vX.Y.Z` tag 才会发布正式版本。Release 固定提供：

- `luci-app-shinra_<版本>-1_all.ipk`
- `luci-app-shinra_<版本>-r1_all.apk`

普通 CI artifact 仅用于验证，不能替代 Release，也不构成稳定的下载或命名接口。
