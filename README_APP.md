# PaperDaily App Guide

## 1. 项目目标

`PaperDaily` 把现有 `zotero-arxiv-daily` 的推荐能力改造成两段式架构：

1. GitHub Actions 每天运行 Zotero 抓取、论文检索、相似度排序和 LLM 总结。
2. 输出面向移动端的 JSON feed。
3. iOS App 拉取 `latest.json`，做离线缓存、收藏、已读、本地提醒。

核心原则是复用现有 Python 推荐逻辑，不把推荐算法搬到 iPhone 上跑。

## 2. 架构说明

数据流如下：

1. GitHub Actions 定时执行 [scripts/run_app_feed.py](/Users/liuliaoyuan/dl_code/zotero-arxiv-daily-main/scripts/run_app_feed.py)。
2. Python 侧复用 [src/zotero_arxiv_daily/executor.py](/Users/liuliaoyuan/dl_code/zotero-arxiv-daily-main/src/zotero_arxiv_daily/executor.py) 的 Zotero、retriever、reranker、TL;DR 流程。
3. 新增的 [src/zotero_arxiv_daily/app_export/json_exporter.py](/Users/liuliaoyuan/dl_code/zotero-arxiv-daily-main/src/zotero_arxiv_daily/app_export/json_exporter.py) 产出：
   - [public/data/latest.json](/Users/liuliaoyuan/dl_code/zotero-arxiv-daily-main/public/data/latest.json)
   - [public/data/manifest.json](/Users/liuliaoyuan/dl_code/zotero-arxiv-daily-main/public/data/manifest.json)
   - [public/data/archive/2026-04-23.json](/Users/liuliaoyuan/dl_code/zotero-arxiv-daily-main/public/data/archive/2026-04-23.json)
4. 同一个 workflow 可把 `public/` 发布到 GitHub Pages，Pages 地址下的 feed 路径通常是 `/data/latest.json`。
5. iOS 工程 [ios/PaperDaily/PaperDaily.xcodeproj](/Users/liuliaoyuan/dl_code/zotero-arxiv-daily-main/ios/PaperDaily/PaperDaily.xcodeproj) 读取远程 feed，失败时回退到缓存或内置 sample。

## 3. Python 改造点

- `Executor` 新增 `collect_recommendations()`，允许“产出推荐结果但不发邮件”。
- `Paper` 增加了 app feed 需要的可选字段：发布时间、分类、关键词、DOI、推荐理由等。
- `app_export` 模块负责稳定 ID、LLM 摘要缓存、manifest 更新和 JSON 输出。
- 原邮件流程仍保留，`config.email.enabled=true` 时行为不变。

## 4. GitHub Actions Secrets

在仓库 `Settings > Secrets and variables > Actions` 中至少配置：

- `ZOTERO_ID`
- `ZOTERO_KEY`
- `OPENAI_API_KEY`

如果要保留邮件工作流，还需要：

- `SENDER`
- `RECEIVER`
- `SENDER_PASSWORD`

不要把这些值写入 iOS App，也不要提交到 Git 仓库。

## 5. GitHub Variables

建议配置以下 Variables：

- `OPENAI_API_BASE`
  默认可用 `https://api.openai.com/v1`
- `OPENAI_MODEL`
  建议用成本更稳的 `gpt-5.4-mini`
- `CUSTOM_CONFIG`
  可以填 `config/custom.yaml`，也可以填一段内联 YAML 覆盖

`scripts/run_app_feed.py` 会优先读取 `--config`，支持“配置文件路径”或“内联 YAML”两种写法。

如果你想直接复用仓库内模板，`CUSTOM_CONFIG` 可以先填：

- `config/paperdaily.example.yaml`

部署前也可以先跑一次 [scripts/preflight_paperdaily.sh](/Users/liuliaoyuan/dl_code/zotero-arxiv-daily-main/scripts/preflight_paperdaily.sh) 检查本地命令、关键文件和环境变量是否齐全。

## 6. 本地运行 Python feed 生成

如果本地已有 `uv`：

```bash
uv sync
uv run python scripts/run_app_feed.py \
  --config config/custom.yaml \
  --output-dir public/data \
  --timezone Asia/Taipei \
  --language zh-Hans
```

如果缺少 `OPENAI_API_KEY`，仍可生成推荐列表；`summary_zh` 会回退为空或使用截断摘要。

## 7. 手动触发 workflow

1. 推送到 `dev` 分支。
2. 打开 GitHub 仓库的 `Actions`。
3. 选择 `Generate Daily App Feed`。
4. 点击 `Run workflow`。

该 workflow 会：

1. 运行 feed 生成脚本。
2. 更新 `public/data`。
3. 将 JSON commit 回当前分支。
4. 把 `public/` 部署到 GitHub Pages。

## 8. 如何启用 GitHub Pages

本仓库的 workflow 已包含 `deploy-pages` job。

首次启用时：

1. 进入 GitHub `Settings > Pages`。
2. 将 Source 设为 `GitHub Actions`。
3. 等待 `deploy-pages` 完成。

部署后，feed URL 通常形如：

`https://<你的用户名>.github.io/<仓库名>/data/latest.json`

## 9. iOS App 如何配置 Feed URL

App 启动后可直接打开设置页：

1. 在 `Feed URL` 填入 GitHub Pages 的 `latest.json` 地址。
2. 点击“测试连接”。
3. 成功后点“立即刷新”。

设置保存在本地 `UserDefaults`，不经过任何账号系统。

## 10. 本地缓存与离线逻辑

App 侧实现了：

- 启动先读缓存。
- 后台刷新远程 feed。
- 远程失败时保留旧缓存。
- 没有缓存时回退到内置 `sample_latest.json`。

缓存文件名固定为 `latest_feed.json`，保存在 `Application Support/PaperDaily/`。

## 11. 本地通知

MVP 只做本地通知：

- 标题：`今日论文推荐`
- 文案：`新的论文推荐可能已经生成，打开 App 查看最新内容。`

本地通知只负责提醒，不保证服务端已经生成当天数据。真正的数据拉取仍发生在 App 打开后。

## 12. Phase 2：APNs 远程推送

MVP 之外，后续可以加：

1. App 注册 APNs，显示 device token。
2. 你手动把 token 放进 GitHub Secrets。
3. Actions 成功生成 feed 后调用独立脚本向 APNs 发送通知。

建议新增 Secrets：

- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`
- `APNS_AUTH_KEY_P8`
- `APNS_DEVICE_TOKEN`
- `APNS_ENV`

## 13. 三种部署模式

### 模式 A：Public repo + GitHub Pages

优点：

- 最容易部署。
- App 直接访问公开 `latest.json`。

缺点：

- 推荐结果 JSON 公开可访问。
- 可能暴露研究兴趣。

### 模式 B：Private repo + GitHub Actions

优点：

- 代码和配置更私有。

缺点：

- App 不适合直接读 private raw 文件。
- 不建议把 GitHub Token 放进 App。

### 模式 C：GitHub Actions + 私有 API / 对象存储

优点：

- 数据不公开。
- 后续更容易扩展多用户。

可选后端：

- Cloudflare Workers + KV
- Supabase
- Firebase
- 自建 VPS

当前 MVP 推荐先用模式 A。

## 14. FAQ

### 为什么不能直接用 ChatGPT Pro / Plus 订阅当 API？

ChatGPT 订阅和 OpenAI API 是分开计费、分开管理的。这个项目运行时应该使用 `OPENAI_API_KEY` 或兼容 API，不应写成“调用 ChatGPT Pro 订阅”。

### 为什么不把 OpenAI Key 放进 App？

因为 App 会分发到终端设备，密钥极易泄露，也无法控制调用成本。正确做法是把 LLM 调用放在 GitHub Actions 或你自己的后端。

### 为什么推荐逻辑不直接跑在 iPhone 上？

当前逻辑涉及 Zotero API、论文抓取、向量重排、可选 LLM 总结和每日定时任务。把这些全搬到 iPhone 上既不稳定，也不利于成本和密钥管理。

### public repo 会不会泄露隐私？

会。即使不导出 Zotero 原始条目，推荐结果仍可能暴露你的研究方向。若介意，请改用 private repo + 私有后端。

### 没有新论文时 App 怎么显示？

仍会生成合法的 `latest.json`，其中 `papers: []`，App 会显示“今日暂无匹配论文”。

## 15. iOS 工程说明

工程入口：

- [ios/PaperDaily/PaperDaily.xcodeproj](/Users/liuliaoyuan/dl_code/zotero-arxiv-daily-main/ios/PaperDaily/PaperDaily.xcodeproj)

本地打开方式：

1. 用 Xcode 打开 `PaperDaily.xcodeproj`。
2. 把 Bundle ID 从 `com.example.paperdaily` 改成你自己的。
3. 如需真机运行，选择你自己的 Team。

当前最低版本为 iOS 17+。

## 16. 已实现的 App 功能

- 今日推荐列表
- 详情页
- 搜索标题 / 作者 / 关键词
- 分类过滤
- 收藏和已读本地持久化
- 远程 feed 拉取
- 本地缓存与离线回退
- Feed URL 设置
- 每日本地提醒
- sample JSON 解码测试

## 17. License 注意事项

- 请保留上游项目的开源协议说明。
- 如果你分发改造后的版本，需继续遵守上游 license。
- 新增的 iOS 与 JSON 导出层并不替代原项目 license。

## 18. 已验证内容

Python：

```bash
PYTHONPATH=src ./.venv/bin/pytest tests/test_app_exporter.py tests/test_executor.py tests/test_protocol.py tests/test_main.py
```

iOS：

```bash
xcodebuild test \
  -project ios/PaperDaily/PaperDaily.xcodeproj \
  -scheme PaperDaily \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
