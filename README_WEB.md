# PaperDaily Web App

这是 `每日论文` 的静态 Web/PWA 版本，用于在不依赖 iOS 开发者签名的情况下长期使用。

访问地址：

`https://llyniku.github.io/ios_paper/web/`

## 使用方式

1. 在 iPhone 上用 Safari 打开上面的地址。
2. 点击 Safari 分享按钮。
3. 选择“添加到主屏幕”。
4. 之后从主屏幕打开“每日论文”即可。

## 功能

- 读取现有 GitHub Pages JSON 数据源。
- 支持今日、经典、网络、收藏、设置五个页面。
- 支持搜索、筛选、收藏、已读、星级评分。
- 收藏、已读和星级保存在浏览器本地，不影响原生 iOS App。
- 支持 Service Worker 缓存，离线时可查看上次加载的数据。

## 注意

- Web App 不需要 iOS 签名，因此不会遇到免费 Apple ID 七天过期的问题。
- Web App 与原生 App 的本地收藏数据暂不互通；如果需要同步，可以后续接入已有 Cloudflare Worker 同步服务。
- 数据源仍来自公开的 GitHub Pages JSON，因此隐私边界与当前公开 Pages 部署一致。
