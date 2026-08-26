# Shinra

Shinra 是面向 OpenWrt 25.12+ 的 sing-box TUN 与 LuCI 管理插件。APK 是主要交付物；IPK
仅用于旧系统兼容。

## Dashboard 访问模型

默认且必须保持稳定的是内网直连：

```text
LuCI / Dashboard -> http://<路由器地址>:20123/dashboard/
```

公网反向代理是可选增强。启用后，只有浏览器当前 Origin 精确匹配已配置的公网 Origin 时，
Shinra 才会使用配置的 Dashboard 与 API 路径（例如 `/shinra/dashboard/` 与
`/`）。NPS 的域名、证书、路径重写、WebSocket 与访问控制始终在 NPS 服务器
维护，Shinra 不管理 NPS，也不为此引入本机 nginx。

详细的开发、验收与发布流程见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

## Release

仅从已验证的 `master` 提交创建 `vX.Y.Z` tag 才会发布正式版本。Release 固定提供：

- `luci-app-shinra_<版本>-1_all.ipk`
- `luci-app-shinra_<版本>-r1_all.apk`

普通 CI artifact 仅用于验证，不能替代 Release，也不构成稳定的下载或命名接口。
