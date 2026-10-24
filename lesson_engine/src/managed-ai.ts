import type { FastifyInstance } from 'fastify';
import type { AppConfig } from './config.js';
import type { ModelProvider } from './config.js';
import { Readable } from 'node:stream';
import { modelForProvider, providerExtraBody, resolveProvider } from './ai/deepseek.js';

const TEST_IMAGE = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
const TEST_TIMEOUT_MS = 45_000;

type ModelRole = 'fast' | 'reasoning' | 'vision';

interface RoleProbe {
  role: ModelRole;
  label: string;
  provider: ModelProvider;
  model: string;
  baseUrl: string;
  apiKey: string;
  flavor: 'openai' | 'anthropic';
}

interface RoleProbeResult {
  role: ModelRole;
  label: string;
  provider: ModelProvider;
  model: string;
  ok: boolean;
  latencyMs: number;
  message: string;
}

export function configuredModelRoles(config: AppConfig): RoleProbe[] {
  const roles: Array<{ role: ModelRole; label: string; preferred: 'deepseek' | 'aliyun' }> = [
    { role: 'fast', label: '快速/结构化', preferred: config.providers.fast },
    { role: 'reasoning', label: '高难推理', preferred: config.providers.reasoning },
    { role: 'vision', label: '图片理解', preferred: config.providers.vision === 'auto' ? 'aliyun' : config.providers.vision }
  ];
  return roles.map(({ role, label, preferred }) => {
    const provider = resolveProvider(config, preferred);
    return {
      role,
      label,
      provider,
      model: modelForProvider(config, provider, role),
      baseUrl: provider === 'aliyun' ? config.aliyun.baseUrl : config.deepseek.baseUrl,
      apiKey: provider === 'aliyun' ? config.aliyun.apiKey : config.deepseek.apiKey,
      flavor: provider === 'aliyun' ? config.aliyun.apiFlavor : 'openai'
    };
  });
}

async function probeRole(fetchImpl: typeof fetch, config: AppConfig, probe: RoleProbe): Promise<RoleProbeResult> {
  const started = Date.now();
  try {
    if (!probe.apiKey) throw new Error(`${probe.provider === 'aliyun' ? '阿里云百炼' : 'DeepSeek'} API Key 未配置`);
    const endpoint = probe.flavor === 'anthropic'
      ? `${probe.baseUrl.replace(/\/+$/, '')}/v1/messages`
      : `${probe.baseUrl.replace(/\/+$/, '')}/chat/completions`;
    const common = probe.role === 'vision'
      ? { text: '这是一张测试图片。请只回复 OK。', image: TEST_IMAGE }
      : { text: probe.role === 'reasoning' ? '求 1+2 的值，只回复数字。' : '只回复 OK。', image: '' };
    const maxTokens = probe.role === 'reasoning' ? 512 : 32;
    const probeExtra = probe.role === 'reasoning'
      ? (probe.provider === 'aliyun' ? { enable_thinking: false } : { thinking: { type: 'disabled' } })
      : providerExtraBody(config, probe.provider, probe.model);
    const body = probe.flavor === 'anthropic'
      ? {
          model: probe.model,
          max_tokens: maxTokens,
          messages: [{ role: 'user', content: common.image
            ? [{ type: 'text', text: common.text }, { type: 'image', source: { type: 'base64', media_type: 'image/png', data: TEST_IMAGE.split(',')[1] } }]
            : common.text }]
        }
      : {
          model: probe.model,
          max_tokens: maxTokens,
          messages: [{ role: 'user', content: common.image
            ? [{ type: 'text', text: common.text }, { type: 'image_url', image_url: { url: common.image } }]
            : common.text }],
          ...probeExtra
        };
    const response = await fetchImpl(endpoint, {
      method: 'POST',
      headers: probe.flavor === 'anthropic'
        ? { 'Content-Type': 'application/json', 'x-api-key': probe.apiKey, 'anthropic-version': '2023-06-01' }
        : { 'Content-Type': 'application/json', Authorization: `Bearer ${probe.apiKey}` },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(TEST_TIMEOUT_MS)
    });
    const raw = await response.text();
    if (!response.ok) {
      let detail = raw.slice(0, 240);
      try {
        const payload = JSON.parse(raw) as { error?: { message?: string }; message?: string };
        detail = payload.error?.message || payload.message || detail;
      } catch { /* keep raw preview */ }
      throw new Error(`HTTP ${response.status}${detail ? `：${detail}` : ''}`);
    }
    let text = '';
    try {
      const payload = JSON.parse(raw) as {
        choices?: Array<{ message?: { content?: string | Array<{ text?: string }> } }>;
        content?: Array<{ type?: string; text?: string }>;
      };
      const content = payload.choices?.[0]?.message?.content;
      text = typeof content === 'string'
        ? content
        : Array.isArray(content)
          ? content.map((item) => item.text || '').join('')
          : (payload.content || []).map((item) => item.text || '').join('');
    } catch { throw new Error('上游返回了无法解析的响应'); }
    if (!text.trim()) throw new Error('上游返回了空内容，请检查模型能力或 thinking 配置');
    return { ...stripProbe(probe), ok: true, latencyMs: Date.now() - started, message: '可用' };
  } catch (error) {
    return { ...stripProbe(probe), ok: false, latencyMs: Date.now() - started, message: error instanceof Error ? error.message : String(error) };
  }
}

function stripProbe(probe: RoleProbe): Omit<RoleProbeResult, 'ok' | 'latencyMs' | 'message'> {
  return { role: probe.role, label: probe.label, provider: probe.provider, model: probe.model };
}


/** Local gateway: credentials and upstream URLs never come from browser input. */
export function registerManagedAi(app: FastifyInstance, config: AppConfig, fetchImpl: typeof fetch = fetch) {
  app.get('/v1/models', async () => ({data: [...new Set(configuredModelRoles(config).map((role) => role.model))].map(id => ({id}))}));
  app.post('/api/ai/test', async (_request, reply) => {
    const roles = configuredModelRoles(config);
    const results = await Promise.all(roles.map((role) => probeRole(fetchImpl, config, role)));
    const passed = results.filter((item) => item.ok).length;
    return reply.send({
      ok: passed === results.length,
      message: passed === results.length ? `模型配置检测通过（${passed}/${results.length}）` : `模型配置有 ${results.length - passed} 项异常（${passed}/${results.length} 可用）`,
      roles: results
    });
  });
  app.post('/v1/chat/completions', async (request, reply) => {
    if (!config.deepseek.apiKey && !config.aliyun.apiKey) return reply.code(503).send({error:{message:'服务端未配置模型 API Key，请填写根目录 .env.local 并重启'}});
    const body = request.body as Record<string, unknown>;
    if (!body || !Array.isArray(body.messages)) return reply.code(400).send({error:{message:'messages 必须是数组'}});
    const allowed = configuredModelRoles(config).map((role) => role.model);
    if (body.model && !allowed.includes(String(body.model))) return reply.code(400).send({error:{message:'模型未在服务端配置，请检查配置文件'}});
    const requestedModel = body.model ? String(body.model) : configuredModelRoles(config)[0].model;
    const role = configuredModelRoles(config).find((item) => item.model === requestedModel) || configuredModelRoles(config)[0];
    const upstreamBase = role.provider === 'aliyun' ? config.aliyun.baseUrl : config.deepseek.baseUrl;
    const upstreamKey = role.provider === 'aliyun' ? config.aliyun.apiKey : config.deepseek.apiKey;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 180000);
    reply.raw.on('close', () => { clearTimeout(timeout); controller.abort(); });
    try {
      const response = await fetchImpl(`${upstreamBase.replace(/\/+$/, '')}/chat/completions`, {
        method:'POST', headers:{'Content-Type':'application/json', Authorization:`Bearer ${upstreamKey}`},
        body:JSON.stringify({...body,model:requestedModel}), signal:controller.signal
      });
      if (!response.ok || !response.body) { await response.body?.cancel(); clearTimeout(timeout); return reply.code(502).send({error:{message:`上游模型错误（HTTP ${response.status}）`}}); }
      reply.header('Content-Type',response.headers.get('content-type') || 'application/json');
      reply.header('Cache-Control','no-store');
      return reply.send(Readable.fromWeb(response.body as any));
    } catch { clearTimeout(timeout); return reply.code(502).send({error:{message:'模型服务暂时不可用，请检查配置与网络'}}); }
  });
}
