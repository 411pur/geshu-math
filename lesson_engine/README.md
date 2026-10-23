# 格数至理数学互动讲解引擎

本目录从 edu-agent 迁入，现已适配数学学科。日常使用请在仓库根目录运行 `启动项目.bat`，非敏感配置在 `local.config.json`，密钥在根目录 `.env.local`。统一启动不再从 web/config.json 导出密钥。下方历史引擎说明中的物理案例仅描述通用渲染能力，数学业务以根目录 README 和数学策略为准。

单独运行 `npm start` 仅启动引擎调试页面，需要自行设置服务端环境变量；遇到 Failed to fetch 应检查服务是否仍运行。

这是一个本地 Web 项目：输入题目图片或题目文字后，自动完成读题、求解、复核、老师式排课，并生成当前黑板风格的**单文件互动 HTML**。

生成结果支持：

- 老师讲解面板和分步板书，公式推导固定在左侧主视图
- KaTeX 0.16.22 离线真实排版：行内 `$...$`、独立居中 `$$...$$`，分式、根号、指数、对数、上下标与常用数学符号不再显示为原始 TeX
- 公式、图形、辅助线和重点高亮；纯代数步骤自动收起空白图形画布
- 选项互动和答案判断
- 浏览器中文语音朗读
- 暂停、上一步、下一步、重播、语速和全屏
- 模拟老师鼠标：金色指针按步骤平滑移动、点击涟漪并高亮当前对象，引导学生关注点；点过的对象在本场景内持续保留高亮，不会一闪而过
- 当前步骤矢量加粗：本步 `activeElementIds` 与指针点过的图元自动加粗（矢量约 1.9 倍），原图底座线宽不变，突出“这一步在讲什么”
- 内嵌播放器可通过 `postMessage` 控制播放/暂停/重讲（供 EduAgent App 内嵌）
- 自适应一屏排版：题干、选项、板书、提示、步骤和控制条在有限窗口里全部可见
- 离线双击打开，不依赖 CDN 或网络资源

当前版本只生成 HTML，不生成 MP4，也不做整套试卷批量处理。

## 运行环境

- Windows 10/11
- Node.js 20 或更高版本
- Chrome 或 Edge
- 图片识别默认由 DeepSeek `deepseek-flash`（V4.1 Flash）完成，无需阿里云 Key；若配置了阿里云 Key 则优先使用 Qwen-VL

## 模型分工

- DeepSeek `deepseek-flash`（V4.1 Flash）：**默认读图模型**（题目图片 OCR + 图形对象提取），并负责结构化讲稿、板书排课、自动复核与视觉修复。
- DeepSeek `deepseek-v4-pro`：独立求解并核对原答案。
- 阿里云 `Qwen-VL`（可选）：配置了 `ALIYUN_API_KEY` 时优先用它读图；不配置也能跑通全流程。

> 文档取文的上限由 `MAX_DOCUMENT_BYTES`（默认 12MB）控制；PDF 取文字层（前 8 页，扫描件没有文字层会提示改用「上传图片」），Word 走 mammoth 取纯文本，txt/md/csv 直接按 UTF-8 读。
>
> 结构化 JSON 调用（**读图**/排课/复核/修复）会自动关闭思考：思考模型会把 token 预算花在 `reasoning_content` 上，导致 `content` 为空、JSON 校验失败。开关由 `DEEPSEEK_DISABLE_THINKING`（默认 `1`）控制，网关侧参数为 `thinking: { type: 'disabled' }`（阿里云千问路径为 `enable_thinking: false`）。
>
> 读图这一步以前漏接了开关（`createVisionExtractor` 不带网关参数）。同一张 157KB 题图实测，同代码只切开关：**不关思考 39.2s → 关思考 4.1s**，题干、选项、原答案与 `diagramMode` 完全一致。
- 浏览器 `speechSynthesis`：老师语音朗读，不额外产生语音 API 费用。
- Playwright + Edge：逐场景截图和 DOM 布局测量，不调用外部 API。
- Qwen-VL 截图评审：可选增强项，设置 `ALIYUN_ENABLE_VISUAL_CRITIC=true` 后在有效阿里云 Key 下启用。

模型名称和请求地址都在 `.env.local` 中配置，后续模型升级时不需要修改代码。

## Anthropic 兼容网关

如果供应商提供的是 Anthropic 兼容地址，例如：

```env
ALIYUN_API_FLAVOR=anthropic
ALIYUN_BASE_URL=https://maas.qianwenaiapi.com/apps/anthropic
ALIYUN_API_KEY=该网关签发的Key
```

项目会自动调用 `/v1/messages`，并支持 Anthropic 图片消息格式。

Key 必须由目标网关签发并处于有效状态。把一个网关的 Key 用到另一个网关上，通常会返回 `InvalidApiKey`。

## 业务空间专属 Key

如果阿里云 Key 以 `sk-ws-` 开头，它通常是业务空间专属 Key，不能直接搭配公共地址 `https://dashscope.aliyuncs.com`，否则会返回 401。

请在阿里云百炼控制台的“业务空间详情”中找到 WorkspaceId，然后配置：

```env
ALIYUN_WORKSPACE_ID=你的WorkspaceId
ALIYUN_REGION=cn-beijing
ALIYUN_BASE_URL=
```

项目会自动生成：

```text
https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1
```

支持的地域：

- `cn-beijing`：华北 2（北京）
- `ap-southeast-1`：新加坡
- `us-east-1`：美国弗吉尼亚

Key、WorkspaceId 和地域必须属于同一个业务空间。

## 自动生成流程

1. 图片由千问视觉模型识别；纯文字直接进入结构化处理。
2. DeepSeek 独立求解，不直接照抄原答案。
3. 与原答案和原解析核对，不一致时自动重新推导。
4. 第二个模型步骤生成老师式讲解场景。
5. 自动检查公式、单位、答案、选项和场景结构。
6. 最多自动重试两次，仍失败则停止并显示具体原因。
7. 用固定黑板外壳 + 识别出的几何对象生成单文件 HTML（AI 只输出受限 JSON，不直接写 HTML/CSS/脚本）。

> **读题与图形重建是两步**：读图只负责 OCR 与文字化的图形描述（`diagramDescription`），
> 图形重建由专门的调用完成，并且会**再带一次题目原图**，模型看着图给出 0-960、0-580 的坐标；
> 这样每次调用的输出都更短，不会被输出上限截断成非法 JSON。
>
> **图形重建只在题目配了图时进行**：没有原图就没有对象可重现，这一步（推理模型 + 180s 超时 + 校验失败重试，最坏约 6 分钟）会被直接跳过，纯文字题交给讲稿模型按题干画图。

> **目标示例与归一化**：`src/ai/target-examples.ts` 提供两份可执行的标准答案（有原图 / 无图各一）与图形书写约定，与排课、视觉修复提示词一并注入，用来抹平不同模型的写法差异；`src/ai/normalize.ts` 负责把模型口辞（circle/vector/从 from-to 到 x1-y1-x2-y2、orange/blue 等颜色别名、intro/summary 等场景别名）折算成 schema 认可的唯一写法。
8. Playwright 离线打开 HTML，逐场景截图并测量文字溢出、图元重叠、越界和答案显示。
9. DeepSeek Flash 根据结构化的视觉报告输出受限修复操作，最多自动修复 3 轮。
10. 连续失败时交付得分最高的版本，并保留视觉警告。

## 使用方式

1. 在左侧粘贴题目文字，或上传题目截图。
2. 点击“开始自动生成”。
3. 页面会实时显示读题、求解、复核、排课和渲染进度。
4. 完成后可以在右侧直接预览。
5. 点击“下载 HTML”得到可发给学生的单文件。

所有生成记录都保存在本机 `data/projects` 目录中。

## 公式渲染与推导区

- 生成的单文件 HTML 内嵌 KaTeX 0.16.22（MIT）；KaTeX 的 JavaScript、CSS 与 WOFF2 字体均内联，无 CDN、外链或字体请求。
- 公式使用 LaTeX：`$...$` 为行内公式，`$$...$$` 为独立居中公式。题干、选项、讲稿、提示、比较表和板书共用同一解析器。
- 板书推演位于左侧；有图形时图形与公式上下排列，纯公式场景隐藏并清空图形区，避免不可见 SVG 参与视觉审计。
- 数学提示词要求优先使用 `\frac{}{}`、`\sqrt{}`、`\ln`、`\cdot` / `\times`、`^` 和 `_`，复杂分式不要写成斜杠串。
- 渲染使用 `trust: false`，不接受公式中的任意 HTML / 脚本；公式出错时只影响当前公式，不中断整页播放。

## 图片识别说明

如果阿里云密钥无效或权限不足，上传图片时会出现明确的 401/权限错误。此时可以：

- 直接留空 `ALIYUN_API_KEY`，系统会用 DeepSeek `deepseek-flash` 读图。
- 或更换为有效的阿里云百炼 / DashScope API Key。
- 同时在输入框粘贴题干文字，图片识别失败后系统会使用补充文字继续生成。

## 常用命令

```powershell
npm start          # 启动本地应用
npm run dev        # 开发模式，自动重启
npm test           # 运行全部离线测试
npm run build      # TypeScript 类型检查
npm run test:live  # 运行实时 API 测试，需要先设置 RUN_LIVE_API_TESTS=1
npm run smoke:live # 使用真实 DeepSeek 完整生成一道示例题
npm run demo       # 生成黑板渲染预览截图
```

实时测试示例：

```powershell
$env:RUN_LIVE_API_TESTS='1'
$env:SKIP_ALIYUN_LIVE='1'
npm run test:live
```

## 主要接口

| 接口 | 作用 |
| --- | --- |
| `POST /api/projects` | 上传题目并启动全自动生成 |
| `POST /api/extract-text` | 上传 PDF / DOCX / TXT 取题目文字（App「上传文档」入口用；只取文不建任务） |
| `GET /api/projects` | 获取历史项目 |
| `GET /api/projects/:id` | 获取项目详情和状态 |
| `GET /api/projects/:id/events` | SSE 实时生成进度 |
| `GET /api/projects/:id/visual` | 获取每轮视觉报告和截图评审 |
| `GET /api/projects/:id/visual/:iteration/:scene` | 获取单场景截图 |
| `POST /api/projects/:id/regenerate` | 重新生成 |
| `GET /api/projects/:id/html` | 预览生成的 HTML |
| `GET /api/projects/:id/download` | 下载单文件 HTML |
| `GET /api/health` | 查看模型配置状态 |

## 安全说明

- `.env.local` 已被 `.gitignore` 排除，绝不能提交到 Git。
- 页面、日志、项目历史和错误信息不会返回 API Key。
- AI 只能输出受限的 JSON 公式和图元，不能注入任意脚本或 HTML。
- 生成后的 HTML 使用 `JSON.stringify` 转义内嵌数据，防止 `</script>` 注入。
- 上传图片只保存在本机项目目录。

## 测试覆盖

- Zod 数据结构与输入校验
- 模型响应解析、JSON 修复和自动重试
- DeepSeek/Qwen 模型路由
- 项目历史、图片保存、重置与路径穿越防护
- 自动求解、复核、重试和文字回退流程
- HTTP API、SSE、下载和静态界面
- 本机 Edge 离线打开、步骤切换和答案判断
- 真实 DeepSeek 最小调用和完整的文本题目生成冒烟测试


## 生成不了怎么排查（互动讲解）

先看引擎自己的状态，这一步能区分 90% 的原因：

```powershell
Invoke-RestMethod http://127.0.0.1:8124/api/health
```

正常的返回里至少当前选用的服务商应为 `true`，并会显示快速、推理、视觉三类模型的实际服务商：

```json
{"ok":true,"providers":{"deepseek":true,"aliyun":false,"fast":"deepseek","reasoning":"deepseek","vision":"deepseek"},"models":{...},"features":{...}}
```

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `providers` 都是 `false` | 没配 Key：`web/config.json` 不存在或缺 `lessonStudio` 段 | 复制 `web/config.example.json` 为 `web/config.json`，填 DeepSeek 与阿里云 Key，重跑 `启动项目.bat` |
| 前端提示「未配置互动讲解服务地址」 | 前端 `build/web` 是旧构建，或 `config.json` 没同步进 `build/web` | 重新运行 `启动项目.bat`（新版会把 `web/config.json` 同步到 `build/web`），并在浏览器里 Ctrl+Shift+R 强刷 |
| 改了 Key 仍失败 | 前端/引擎是重启前启动的旧进程 | 关掉 3210 上的 node 进程后重跑启动器；前端需强制刷新（Service Worker 会缓存旧应用） |
| 任务报 `DeepSeek API Key 未配置` | 引擎进程是改配置之前启动的旧进程 | 关掉旧引擎（占用 3210 的 node 进程）再重跑启动器；新版启动器会自动检测并重启 |
| 任务报 401 / InvalidApiKey | Key 与地址不匹配（例如业务空间专属 Key 配了公共地址） | 见下面「业务空间专属 Key」一节 |

统一启动器读取根目录 `.env.local`；如果你改完 Key 仍然失败，多半是旧引擎还在跑——先把 3210 端口上的进程关掉再重启。

> 说明：这个功能产出的是**单文件互动 HTML**（老师语音朗读 + 自动翻页 + 模拟鼠标指点），不是 MP4。当前版本不生成视频文件。

## Failed to fetch 怎么处理

如果页面显示 `Failed to fetch`，通常表示本地服务已经停止。请在项目目录重新运行：

```powershell
npm start
```

然后刷新页面。只要图片上传接口收到请求，服务器不会因为 Key 错误而崩溃；Key 错误会显示为明确的 401 或 InvalidApiKey。


## 图形与内容正确性保障

- 求解、排课和复核共用数学教学规范：关键变形要解释“观察到什么、联想到什么、为什么这样变形”，并指出具体计算难点与易错原因。
- 讲稿只能复用、拆分或改写已验证解答中的关键公式，不得自行增加未经求解阶段确认的等式或结论。
- few-shot 覆盖原图题、纯公式题和高中数学闭区间最值题，示范端点比较、驻点判断和取等验证。
- 先生成题意判断，纯计算题不画图，物理受力/运动/场/电路题和数学几何题才生成示意图。
- 题目自带原图时按“原图层 + 分析层”重建：先用 `layer: "base"` 忠实复现原图的标注点、连线和器件，再用 `layer: "analysis"` 逐个场景叠加受力、速度、场强等矢量，矢量起点落在真实对象上。
- 原图层统一沉到 `diagram.baseElements`，保证每个场景都先显示重画出来的题目原图；分析层随讲解逐步出现。
- 受力方向确定性校验（`src/visual/physics-check.ts`）：按原图层里离作用点最近的接触面算方向，重力必须竖直向下、支持力必须垂直接触面、摩擦力必须沿接触面，偏差超过 30° 会带着具体角度进入复核意见并触发重画。
- 复核意见会回传给排课模型（`createLessonPlan(problem, solution, feedback)`），内容重试最多 3 轮，失败时保留问题最少的一版。
- 同一支矢量只画一次：几何重合且标签头符号相同的箭头会被去重，避免标签重叠。
- 忠实度守卫（`src/visual/diagram-fidelity.ts`）：题意判断不需要示意图时清空原图层，受力/速度/场强等分析矢量若被误放进原图层会自动退回讲解步骤，分析矢量起点偏离原图对象时会给出警告，避免脱离题目情景自行发挥。
- 每个场景会推导 `focusPath`（模型可显式给出，否则按 `activeElementIds` 的锚点自动生成），驱动模拟鼠标的移动顺序。
- **不使用任何题型模板**：图形完全来自视觉模型对题图的识别结果（`diagramBlueprint.baseElements` + 各场景 `diagramElements`），不再按“正六棱柱 / 力学轨道 / v-x 图像”之类的关键词换成写死的标准图。
- **矢量重绘**：识别出的每个点、线、面、器件都生成 SVG 图元（`src/visual/diagram-redraw.ts`），原题截图不会被嵌入，视觉检查会直接阻止截图叠加版本。
- **自动归一化排版**：模型估的坐标可能缩在一角或溢出画布，重绘时按整体包围盒做**等比**缩放并居中（`fitDiagramToCanvas`），保持原图宽高比与相对位置。
- **不替模型改答案**：已移除按题型强制改写正确答案的确定性解法，求解与讲稿全部走模型，并保留自动复核。
- 同一 ID 可以在不同场景复用来更新同一图元（这是合法的逐镜叠加），但同一层或同一场景内不允许重复定义。
- **标签重叠由代码按实测框重排**：视觉检查量到文字框互相压住时，先由 `src/visual/label-layout.ts` 按真实尺寸把同一场景内的标签推开（留 8 单位缝、按图元 id 稳定偏移、夹在画布内）并复测，**通过就不再调用模型**；只有代码修不掉才交给模型修复。点标签与矢量标签分别用 `labelDx/labelDy` 记录偏移。
- **警告分两条通道**：`visualWarnings` 只放学生/老师该知道的问题（图元越界、文字溢出、图形不符题意等），过程信息（跳过无效修复、修复失败、复核争议、排课重试）进 `visualDiagnostics`，避免把实现细节当成“视觉提示”展示。

## 内嵌到 App 播放时的宿主约定

生成的讲解 HTML 可以被宿主页面用 iframe 内嵌播放（EduAgent 的播放器就是这么用的），但**宿主 iframe 必须显式放行全屏**：

```html
<iframe src="..." allow="fullscreen"></iframe>
```

讲解 HTML 是通过 `data:` URL 塞进 iframe 的，这种子帧的 origin 是 opaque（`"null"`），而 `fullscreen` 的默认 allowlist 只放行同源帧——不放行时子帧 `document.fullscreenEnabled` 就是 `false`，黑板右上角的「全屏黑板」会被权限策略直接拒掉（表现为点了没反应）。

子帧检测到全屏被拦下时，会把按钮短暂显示为「全屏被拦截」，并通过 `postMessage` 回传原因，宿主可据此提示用户改用新窗口打开：

```js
{ __lessonStudioStatus: true, fullscreen: 'blocked', reason: '...' }
```

成功进入/退出全屏同样会回传 `fullscreen: "entered"`。回归测试见 `tests/browser.test.ts`（真实 Edge，分别验证放行与不放行两种 iframe）。
