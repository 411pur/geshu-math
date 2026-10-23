import { configuredModelRoles, registerManagedAi } from './managed-ai.js';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import Fastify, { type FastifyInstance } from 'fastify';
import multipart from '@fastify/multipart';
import fastifyStatic from '@fastify/static';
import { loadConfig, type AppConfig } from './config.js';
import { createDefaultTutor } from './ai/deepseek.js';
import { createAliyunClient } from './ai/deepseek.js';
import { QwenVisualCritic } from './ai/qwen-visual-critic.js';
import { LessonPipeline } from './pipeline/lesson-pipeline.js';
import { LocalHtmlRenderer } from './render/render-lesson.js';
import { PlaywrightVisualAuditor } from './visual/playwright-auditor.js';
import { ProjectStore } from './store/project-store.js';
import { JobManager } from './jobs/job-manager.js';
import { extractDocumentText } from './pipeline/document-text.js';
import { AppError } from './lib/errors.js';

export interface BuildServerOptions { config?: AppConfig; store?: ProjectStore; pipeline?: LessonPipeline; logger?: boolean; }

export async function buildServer(options: BuildServerOptions = {}): Promise<FastifyInstance> {
  const config = options.config || loadConfig();
  const store = options.store || new ProjectStore(config.dataDir);
  await store.init();
  await store.failInterruptedJobs();
  const tutor = createDefaultTutor(config);
  const renderer = new LocalHtmlRenderer(config.templatePath);
  const visualAuditor = new PlaywrightVisualAuditor();
  const visualCritic = process.env.ALIYUN_ENABLE_VISUAL_CRITIC === '1' && config.aliyun.apiKey
    ? new QwenVisualCritic(createAliyunClient(config), config.aliyun.visionModel)
    : undefined;
  const pipeline = options.pipeline || new LessonPipeline(tutor, store, renderer, visualAuditor, visualCritic);
  const jobs = new JobManager();

  const app = Fastify({ logger: options.logger ?? false, bodyLimit: config.maxImageBytes + 1024 * 1024 });
  registerManagedAi(app, config);
  // 允许访问的前端 origin。
  //
  // 只放行「本机已知的应用端口」，而不是任意回环端口 —— 本机其它进程
  // （包括别的本地页面）不应该能无声调用讲题引擎。
  //
  // 但同一端口的 127.0.0.1 / localhost / [::1] 是等价的，必须都给：之前只白名单了
  // 127.0.0.1:8082，用户用 localhost:8082 打开就整片 CORS 失败，报错还只是
  // 「原讲解服务连接失败」这种看不出原因的话。
  //
  // 端口变化时用 CORS_ALLOWED_ORIGINS 覆盖（启动脚本会按实际端口注入）。
  const defaultPorts = [5070, 8082];
  const allowedOrigins = new Set<string>(
    (process.env.CORS_ALLOWED_ORIGINS ?? '')
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean)
  );
  if (allowedOrigins.size === 0) {
    for (const port of defaultPorts) {
      for (const host of ['127.0.0.1', 'localhost', '[::1]']) {
        allowedOrigins.add('http://' + host + ':' + port);
      }
    }
  }

  app.addHook('onRequest', async (request, reply) => {
    const origin = typeof request.headers.origin === 'string' ? request.headers.origin : '';
    const allowed = origin.length > 0 && allowedOrigins.has(origin);
    if (allowed) {
      reply.header('Access-Control-Allow-Origin', origin);
      reply.header('Vary', 'Origin');
    }
    reply.header('Access-Control-Allow-Headers', 'content-type,authorization,x-board,x-custom-prompt');
    if (origin && !allowed) return reply.code(403).send({message:'来源未授权'});
    reply.header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    reply.header('Access-Control-Allow-Private-Network', 'true');
    if (request.method === 'OPTIONS') {
      if (!allowed) return reply.code(403).send();
      return reply.code(204).send();
    }
  });
  // 传输层按两者较大值放行；每条路由再各自卡自己的上限（图片走 maxImageBytes、文档走 maxDocumentBytes）。
  await app.register(multipart, { limits: { fileSize: Math.max(config.maxImageBytes, config.maxDocumentBytes), files: 1, fields: 10 } });
  await app.register(fastifyStatic, { root: config.publicDir, prefix: '/' });

  app.setErrorHandler((error, _request, reply) => {
    const statusCode = error instanceof AppError ? error.statusCode : Number((error as { statusCode?: number }).statusCode || 500);
    const code = error instanceof AppError ? error.code : 'internal_error';
    const message = error instanceof Error ? error.message : String(error);
    reply.code(statusCode).send({ error: code, message });
  });

  async function runJob(projectId: string): Promise<void> {
    try {
      let record = await store.update(projectId, { status: 'running', stage: 'queued', progress: 1, error: undefined });
      jobs.publish({ type: 'progress', record, message: '任务已开始' });
      const result = await pipeline.run(projectId, async (event) => {
        record = await store.update(projectId, { status: 'running', stage: event.stage, progress: event.progress, error: undefined });
        jobs.publish({ type: 'progress', record, message: event.message });
      });
      record = await store.update(projectId, {
        status: 'done', stage: 'done', progress: 100, title: result.plan.title, subject: result.plan.subject, error: undefined,
        visualStatus: result.visualStatus || 'not_checked', visualWarnings: result.visualWarnings || [], visualDiagnostics: result.diagnostics || [], renderAttempts: result.renderAttempts || 0
      });
      jobs.publish({ type: 'done', record, message: record.visualWarnings.length ? '讲解 HTML 已生成，存在视觉警告' : '讲解 HTML 已生成' });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const record = await store.update(projectId, { status: 'failed', stage: 'failed', progress: 100, error: message.slice(0, 2000) });
      jobs.publish({ type: 'error', record, message });
    }
  }

  app.get('/api/health', async () => {
    const roles = configuredModelRoles(config);
    return {
      ok: true, service: 'geshu-math', instance: process.env.GESHU_INSTANCE || '',
      providers: {
        deepseek: Boolean(config.deepseek.apiKey), aliyun: Boolean(config.aliyun.apiKey),
        fast: roles.find((role) => role.role === 'fast')?.provider,
        reasoning: roles.find((role) => role.role === 'reasoning')?.provider,
        vision: roles.find((role) => role.role === 'vision')?.provider
      },
      models: Object.fromEntries(roles.map((role) => [role.role, role.model])),
      features: { visualAudit: true, visualCritic: Boolean(visualCritic) }
    };
  });

  app.get('/api/projects', async () => ({ projects: await store.list() }));
  app.get<{ Params: { id: string } }>('/api/projects/:id', async (request, reply) => {
    try { return { project: await store.get(request.params.id) }; } catch { return reply.code(404).send({ error: 'not_found', message: '项目不存在' }); }
  });

  app.post('/api/projects', async (request, reply) => {
    const input = await parseProjectInput(request, config.maxImageBytes);
    if (!input.text?.trim() && !input.image) return reply.code(400).send({ error: 'invalid_input', message: '请输入题目文字或上传题目图片' });
    const record = await store.create({ text: input.text?.trim() || undefined });
    if (input.image) {
      const savedName = await store.saveInputImage(record.id, input.image.fileName, input.image.mimeType, input.image.data);
      const updated = await store.update(record.id, { input: { ...record.input, imageFileName: savedName, imageMimeType: input.image.mimeType } });
      jobs.publish({ type: 'created', record: updated, message: '项目已创建' });
    } else jobs.publish({ type: 'created', record, message: '项目已创建' });
    void runJob(record.id);
    return reply.code(202).send({ id: record.id, status: 'queued' });
  });

  /**
   * 取文接口：App 的「上传文档生成讲解」把 PDF / DOCX / TXT 发过来，这里换回题目文字。
   * 只做取文，不建任务——学生能先在页面上看到／改提取结果，再决定要不要生成。
   */
  app.post('/api/extract-text', async (request, reply) => {
    if (!request.isMultipart()) return reply.code(400).send({ error: 'invalid_body', message: '请用 multipart/form-data 上传文件' });
    for await (const part of request.parts()) {
      if (part.type !== 'file') continue;
      const fileName = part.filename || 'document';
      const data = await part.toBuffer();
      if (data.length > config.maxDocumentBytes) throw new AppError('document_too_large', `文件超过 ${Math.round(config.maxDocumentBytes / 1024 / 1024)}MB 上限`, 413);
      const extracted = await extractDocumentText(fileName, data);
      if (!extracted.text.trim()) {
        throw new AppError('empty_document', '没有从文件里读到文字：扫描件或纯图片 PDF 请改用「上传图片」，也可以直接粘贴题目文字', 422);
      }
      return reply.send(extracted);
    }
    throw new AppError('missing_document', '没有收到文件', 400);
  });

  app.post<{ Params: { id: string } }>('/api/projects/:id/regenerate', async (request, reply) => {
    try {
      const record = await store.reset(request.params.id);
      jobs.publish({ type: 'created', record, message: '正在重新生成' });
      void runJob(record.id);
      return reply.code(202).send({ id: record.id, status: 'queued' });
    } catch { return reply.code(404).send({ error: 'not_found', message: '项目不存在' }); }
  });

  app.get<{ Params: { id: string } }>('/api/projects/:id/events', async (request, reply) => {
    try { await store.get(request.params.id); } catch { return reply.code(404).send({ error: 'not_found', message: '项目不存在' }); }
    reply.hijack();
    reply.raw.writeHead(200, { 'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-cache, no-transform', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
    let closed = false;
    const send = (event: unknown) => { if (!closed) reply.raw.write(`data: ${JSON.stringify(event)}\n\n`); };
    const unsubscribe = jobs.subscribe(request.params.id, (event) => send(event));
    const keepAlive = setInterval(() => { if (!closed) reply.raw.write(': keep-alive\n\n'); }, 15_000);
    send({ type: 'connected', record: await store.get(request.params.id), message: '已连接' });
    request.raw.on('close', () => { closed = true; clearInterval(keepAlive); unsubscribe(); });
  });

  app.get<{ Params: { id: string } }>('/api/projects/:id/html', async (request, reply) => {
    try { return reply.type('text/html; charset=utf-8').send(await store.readHtml(request.params.id)); } catch { return reply.code(404).send({ error: 'not_found', message: '讲解 HTML 尚未生成' }); }
  });

  app.get<{ Params: { id: string } }>('/api/projects/:id/download', async (request, reply) => {
    try {
      const [html, record] = await Promise.all([store.readHtml(request.params.id), store.get(request.params.id)]);
      const safeName = record.title.replace(/[\\/:*?"<>|]/g, '_').slice(0, 60) || '题目讲解';
      return reply.header('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent(safeName)}.html`).type('text/html; charset=utf-8').send(html);
    } catch { return reply.code(404).send({ error: 'not_found', message: '讲解 HTML 尚未生成' }); }
  });

  app.get<{ Params: { id: string } }>('/api/projects/:id/visual', async (request, reply) => {
    try {
      const record = await store.get(request.params.id);
      const reports = [];
      const critiques = [];
      for (let iteration = 0; iteration < Math.max(record.renderAttempts, 1); iteration += 1) {
        const reportPath = `visual/iteration-${iteration}/report.json`;
        const critiquePath = `visual/iteration-${iteration}/critique.json`;
        if (await store.artifactExists(request.params.id, reportPath)) reports.push(await store.readArtifactJson(request.params.id, reportPath));
        if (await store.artifactExists(request.params.id, critiquePath)) critiques.push(await store.readArtifactJson(request.params.id, critiquePath));
      }
      return { reports, critiques, warnings: record.visualWarnings };
    } catch { return reply.code(404).send({ error: 'not_found', message: '项目不存在' }); }
  });

  app.get<{ Params: { id: string; iteration: string; scene: string } }>('/api/projects/:id/visual/:iteration/:scene', async (request, reply) => {
    const iteration = Number(request.params.iteration);
    const scene = Number(request.params.scene);
    if (!Number.isInteger(iteration) || !Number.isInteger(scene) || iteration < 0 || iteration > 10 || scene < 0 || scene > 30) return reply.code(400).send({ error: 'invalid_path', message: '非法视觉产物路径' });
    try { return reply.type('image/png').send(await store.readArtifactBuffer(request.params.id, `visual/iteration-${iteration}/scene-${scene}.png`)); }
    catch { return reply.code(404).send({ error: 'not_found', message: '视觉截图不存在' }); }
  });

  return app;
}

interface ParsedProjectInput { text?: string; image?: { data: Buffer; mimeType: string; fileName: string }; }

async function parseProjectInput(request: any, maxBytes: number): Promise<ParsedProjectInput> {
  if (request.isMultipart()) {
    let text: string | undefined;
    let image: ParsedProjectInput['image'];
    for await (const part of request.parts()) {
      if (part.type === 'file') {
        const mimeType = part.mimetype || 'application/octet-stream';
        if (!['image/jpeg', 'image/png', 'image/webp'].includes(mimeType)) { part.file.resume(); throw new AppError('invalid_image', '只支持 JPG、PNG、WebP 图片', 400); }
        const data = await part.toBuffer();
        if (data.length > maxBytes) throw new AppError('image_too_large', '图片超过大小限制', 413);
        image = { data, mimeType, fileName: part.filename || 'question-image' };
      } else if (part.fieldname === 'text') text = String(part.value || '');
    }
    return { text, image };
  }
  const body = request.body as { text?: string } | undefined;
  return { text: body?.text };
}

export async function startServer(): Promise<void> {
  const config = loadConfig();
  const app = await buildServer({ config, logger: true });
  await app.listen({ host: config.host, port: config.port });
  for (const signal of ['SIGINT','SIGTERM'] as const) process.once(signal, () => { void app.close().then(() => process.exit(0)); });
  if (!config.deepseek.apiKey) {
    console.warn(
      '[lesson-engine] 未配置 DEEPSEEK_API_KEY：读图与求解都会失败。' +
      '请在项目根目录 .env.local 填写后重启 启动项目.bat，' +
      '或设置用户环境变量 DEEPSEEK_API_KEY。'
    );
  } else if (!config.aliyun.apiKey) {
    console.info(
      `[lesson-engine] 未配置 ALIYUN_API_KEY：读图将使用 DeepSeek ${config.deepseek.visionModel || config.deepseek.fastModel}（可选配置，不影响流程跑通）。`
    );
  }
}

const isDirectRun = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isDirectRun) startServer().catch((error) => { console.error(error); process.exitCode = 1; });
