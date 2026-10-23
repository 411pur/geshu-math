# ai_proxy — AI 网关（把 Key 和提示词放到服务端）

## 为什么需要它

现在前端（浏览器）**直连**模型商，`web/config.json` 里明文放着真实 API Key：

```
前端 ──Bearer sk-98fc...（明文，F12 可见）──▶ DashScope
```

任何人打开你的网站就能抓走 Key 盗刷；系统提示词也全在 `main.dart.js` 里。

本网关把这两样都挪到服务端：

```
前端 ──POST /v1/chat/completions──▶ 本网关 ──Bearer <真Key>──▶ DashScope / DeepSeek
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
> 若用其他平台（Vercel / Deno Deploy / 阿里云函数计算 FC）也同理，入口都是 `src/index.js` 的 `fetch`。

部署后把 `wrangler.toml` 里的 `ALLOWED_MODELS`、`ALLOW_ORIGIN` 按需收紧（`ALLOW_ORIGIN` 建议改为你的站点域名）。

## 切换前端

1. 用 `web/config.proxy.sample.json` 覆盖 `web/config.json`，把其中 baseUrl 换成你的 Worker 地址。
2. `useServerPrompts: true` → 未自定义提示词的板块不再发送内置提示词，由网关注入。
3. `flutter build web` 重新构建。

之后前端不再持有任何真实 Key。

## 提示词同步

`src/prompts.gen.js` 由 `scripts/extract-prompts.mjs` 从
`lib/core/network/aliyun_api_client.dart` 的 `_xxxSystemPrompt` 常量生成 ——
**改提示词改 Dart 源码即可，跑一次 `npm run extract-prompts` 保持服务端同步**，
不要手改 `prompts.gen.js`。

## ⚠️ 安全待办（重要）

`web/config.json` 里那个 `sk-98fc...` **已经随代码提交过、等于已泄露**，
上线前务必到阿里云百炼控制台**吊销并重建**该 Key，新 Key 只放到
`wrangler secret` / `.dev.vars`，永不进仓库。

## 尚未迁移

- 拍照识题（`vision_llm_ocr_service.dart`、`ocrQuestionImage`）的内联指令仍是
  前端直发；后续可加一个 `ocr` 板块提示词到 registry。
- 互动讲解服务（`lesson_engine/`，Fastify）已在服务端，但它依赖
  `playwright-core + sharp`，需要独立 VPS/容器，不能跑在 Worker 上。
