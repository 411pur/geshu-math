# 格数至理（geshu-math）

面向初高中学生的 AI 数学答疑与学习分析应用。拍照或粘贴一道数学题，得到「错因 → 正解 → 分步解析 → 知识点回顾 → 变式训练」的结构化讲解，讲解结果自动沉淀到错题本、学习报告与知识图谱。

Flutter 单页应用，同时支持 Web 与 Windows 桌面；模型侧只要求兼容 OpenAI 的 `chat/completions` 协议，服务商、地址与模型名全部由配置决定，不绑定任何厂商。可选用 Cloudflare Worker 做 AI 网关。

> 本项目定位为演示 / 自用：默认由浏览器直连模型厂商，API Key 会暴露在前端。公网部署请使用 [`ai_proxy`](ai_proxy/README.md)。

## 功能

| 模块 | 能力 |
|---|---|
| 首页概览 | 8 个功能入口、错题统计环（未掌握 / 复习中 / 已掌握）、最近错题 |
| 错题指导 | 快速版一问一答、专家版决策树多轮追问、文本 / 图片 / 拍照提交、流式输出、7 段错题订正模板、讲完自动入库 |
| 错题本 | 掌握度切换、收藏、标签、难度、模块筛选、排序、导出 PDF、详情回看解析 |
| 拍照识题 | 图片 OCR + 多模态直发双通道，OCR 质量不足时自动改为「图 + 题」一起送模型 |
| 考试分析 | 试卷拍照识别、按模块统计得分、AI 分析报告、考情历史与单次详情 |
| 智能问答 | 多轮数学问答、流式回答、常用问题快捷入口 |
| 学习报告 | 近 7 / 30 / 90 天统计、AI 生成复习建议、重点练习推荐、定时报告 |
| 学生画像 | 全量错题 KPI、掌握度环、薄弱知识点、错因分布、近 8 周节奏、反复错误、自述薄弱点、AI 画像解读 |
| 知识图谱 | 333 节点三层图谱（10 模块 / 55 章 / 268 知识点）、旋转与层级缩放、知识树浏览 |

## 技术栈

- **Flutter**（Web / Windows）+ **Riverpod** 状态管理 + **go_router** 路由
- **Dio** 负责 HTTP 与 SSE 流式解析
- **flutter_markdown / markdown** 渲染讲解正文，**fl_chart** 画统计图，**pdf / printing** 导出错题 PDF
- 模型：任意 OpenAI 兼容服务；`baseUrl` / `apiKey` / `model` / `visionModel` 均可替换，默认留空由配置注入
- 可选网关：Cloudflare Workers（`ai_proxy/`）

## 快速开始

环境要求：Flutter ≥ 3.29、Dart ≥ 3.8。

```bash
flutter pub get

# 填入你的模型 Key（config.json 不入库）
cp web/config.example.json web/config.json

flutter run -d chrome
```

构建并本地预览 Web：

```bash
flutter build web --release --no-web-resources-cdn
python3 -m http.server 8123 --directory build/web
# 打开 http://127.0.0.1:8123
```

`--no-web-resources-cdn` 会把 CanvasKit 一起打进 `build/web`。不加这个参数时 Flutter 默认从公网 CDN 拉取 CanvasKit，国内网络或离线环境容易出现白屏。

Windows 桌面：

```bash
flutter run -d windows     # 需要 Visual Studio 的 C++ 桌面开发组件
```

## 配置

运行时读取站点根目录的 `/config.json`（即 `web/config.json`，构建时拷进 `build/web`），并在 URL 上带时间戳参数，避免浏览器或 Service Worker 缓存旧配置。

| 字段 | 说明 |
|---|---|
| `apiBaseUrl` | OpenAI 兼容接口地址，形如 `https://your-host/v1`，默认空 |
| `apiKey` | 接口 Key（`YOUR_API_KEY` 等占位串视为未配置） |
| `model` | 文本模型名，必填 |
| `visionModel` | 多模态模型名，图片识别与拍照识题必填 |
| `reasoningModel` | 可选的推理模型，留空则不启用 |
| `useServerPrompts` | 为 `true` 时不再发送内置提示词，由网关按板块注入 |

- 配置既可以写在顶层，也可以收在 `ai` 段，两种写法都支持。
- 换服务商 / 换模型只需改 `apiBaseUrl`、`apiKey`、`model`（模型名由服务商定义），代码无需改动、无需重新编译。
- 默认值全部为空：未配置时页面会提示「尚未配置 AI 服务」，而不是抛出 401。
- `web/config.json` 已被 `.gitignore` 忽略；仓库里只有 `config.example.json` 与 `config.proxy.sample.json` 两个占位样例。

## 提示词

6 条系统提示词内置在 `lib/core/network/ai_api_client.dart`（错题指导、专家版、追问、考试分析、智能问答、学习报告），另有拍照识题的内联 OCR 指令：

- 全部使用 `r'''` 原始字符串，避免 Dart 转义与 LaTeX 反斜杠冲突；
- 统一要求模型输出严格 JSON，数学公式使用 `$...$` / `$$...$$`。

启用 `ai_proxy` 后，服务端提示词由脚本从 Dart 源码生成，保持单一事实来源：

```bash
cd ai_proxy
npm run extract-prompts   # 读取 Dart 常量 → src/prompts.gen.js
npm test                  # 网关单测（10 例）
```

## AI 网关（可选）

`ai_proxy/` 是一个 Cloudflare Worker：隐藏真实 Key、按 `X-Board` 注入服务端提示词、限制模型白名单、透传 SSE。前端把 `config.json` 的 `apiBaseUrl` 指向 Worker，并设置 `useServerPrompts: true` 即可。

部署与环境变量说明见 [`ai_proxy/README.md`](ai_proxy/README.md)。

## 知识图谱数据

知识结构完全由 `assets/knowledge/initial_knowledge_structure.json` 驱动，启动时载入内存：

```json
{
  "id": "plane-geometry",
  "parentId": null,
  "title": "平面几何",
  "level": 1,
  "description": "……"
}
```

- 三层：`level` 1 模块 / 2 章 / 3 知识点，共 333 个节点；
- 节点颜色按标题关键字映射到五个模块色（数与代数、函数、几何、概率统计、导数）；
- 增删节点只改 JSON，无需改动代码。

## 目录结构

```
lib/
├── core/            # 主题、网络（OpenAI 兼容客户端 / SSE / JSON 容错）、PDF、平台配置
├── data/            # DataStore（localStorage）、数据源与仓库
├── domain/          # 错题、考试、知识节点等实体
├── features/        # 首页、错题、考试、问答、识题、报告、知识图谱
└── shared/          # 通用组件（Markdown 渲染等）与工具
assets/knowledge/    # 知识图谱种子数据
ai_proxy/            # 可选的 AI 网关（Cloudflare Worker）
web/                 # index.html、manifest、config 样例
windows/             # Windows 桌面 runner
```

## 数据存储

- 错题、考试记录、单题详情保存在浏览器 `localStorage`（`wrong_questions` / `exam_records` / `exam_details`）；
- 知识节点来自打包资源，不做持久化；
- 没有账号体系与云端同步，清除站点数据即清空全部记录。

## 公式渲染

`lib/shared/widgets/styled_markdown.dart` 内置轻量 TeX 转换：`\frac{a}{b}` → `(a)/(b)`、`\sqrt{x}` → `√x`、希腊字母、上下标等，不依赖 MathJax / KaTeX。

模型有时会在 JSON 字符串里直接输出单个反斜杠（`\frac` 被解析成换页符），所以 `lib/core/network/ai_json.dart` 会在 `jsonDecode` **之前**修复非法转义，SSE 流式结果与最终结果都走这一层。

## 已知限制

- 仅本地单机使用，无后端、无账号、无多端同步；
- 前端直连模型厂商时 Key 会被抓包 / F12 看到，只适合本地演示；
- 公式排版是轻量降级方案，矩阵、多行对齐等复杂公式会退化成线性文本；
- 自动化测试目前只覆盖 `ai_proxy` 的网关逻辑，前端以 `flutter analyze` + 构建 + 手工冒烟为主。

## 许可证

本仓库暂未指定开源许可证，默认保留所有权利。
