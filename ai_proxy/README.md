# ai_proxy — AI 网关（把 Key 和提示词放到服务端）

## 为什么需要它

现在前端（浏览器）**直连**模型商，`web/config.json` 里明文放着真实 API Key：

```
前端 ──Bearer sk-xxxx...（明文，F12 可见）──▶ 模型服务
```

任何人打开你的网站就能抓走 Key 盗刷；系统提示词也全在 `main.dart.js` 里。

本网关把这两样都挪到服务端：

```
前端 ──POST /v1/chat/completions──▶ 本网关 ──Bearer <真Key>──▶ 任意 OpenAI 兼容服务
      （不带 Key；按 X-Board 注入提示词）
```

## 它做了什么

| 能力 | 说明 |
|---|---|
| 藏 Key | 永不透传客户端 `Authorization`，一律用服务端 `UPSTREAM_API_KEY` |
| 藏提示词 | `X-Board` 指定板块时，用服务端 registry 覆盖客户端 system 消息；客户端自定义提示词带 `X-Custom-Prompt: 1` 放行 |
| 模型白名单 | `ALLOWED_MODELS` 外的模型一律回落，防乱填模型烧钱 |
| SSE 透传 | 流式逐块转发，不缓冲；非流式 JSON 同样支持 |
| CORS | 预检在网关处理，前端可跨域直连 |

已用 `node --test` 覆盖：Key 剥离、URL 拼接、SSE 透传、提示词注入、CORS、白名单（10 例全绿）。

## 本地开发

```bash
cd ai_proxy
cp .dev.vars.example .dev.vars     # 填真实 Key
npm install
npm run extract-prompts            # 从 Dart 源码生成 src/prompts.gen.js
npm test                           # 10 例网关单测
npm run dev                        # 起在 http://127.0.0.1:8787
```

## 部署到 Cloudflare Workers（免费额度、按量计费，不用不花钱）

```bash
cd ai_proxy
npm install
npx wrangler login                 # 浏览器授权一次
npx wrangler secret put UPSTREAM_API_KEY     # 粘贴真实 Key（不会写进仓库）
npx wrangler deploy                # 得到 https://geshu-math-ai-proxy.<子域>.workers.dev
```

> Workers 免费版：每天 10 万次请求、零闲置成本。超出按 $5/千万次计。
> 其他支持 `fetch` 的运行时（Vercel / Deno Deploy / 自建 Node 服务）同理，入口都是 `src/index.js`。

部署后把 `wrangler.toml` 里的 `ALLOWED_MODELS`、`ALLOW_ORIGIN` 按需收紧（`ALLOW_ORIGIN` 建议改为你的站点域名）。

## 切换前端

1. 用 `web/config.proxy.sample.json` 覆盖 `web/config.json`，把其中 baseUrl 换成你的 Worker 地址。
2. `useServerPrompts: true` → 未自定义提示词的板块不再发送内置提示词，由网关注入。
3. `flutter build web` 重新构建。

之后前端不再持有任何真实 Key。

## 提示词同步

`src/prompts.gen.js` 由 `scripts/extract-prompts.mjs` 从
`lib/core/network/ai_api_client.dart` 的 `_xxxSystemPrompt` 常量生成 ——
**改提示词改 Dart 源码即可，跑一次 `npm run extract-prompts` 保持服务端同步**，
不要手改 `prompts.gen.js`。

## ⚠️ 安全提示（重要）

只要 Key 以任何形式公开过（截图、日志、聊天记录、提交历史），就应视为已泄露：
请直接在上游服务商控制台**吊销并重建**，新 Key 只放在 `wrangler secret` / `.dev.vars`，
永不写入仓库或前端配置。

## 尚未覆盖

- 拍照识题（`vision_llm_ocr_service.dart` 中的 `ocrQuestionImage`）仍由前端直接
  发送内联指令；后续可新增 `ocr` 板块提示词，交给网关注入。
