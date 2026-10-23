import type { FastifyInstance } from 'fastify';
import type { AppConfig } from './config.js';
import { Readable } from 'node:stream';

/** Local gateway: credentials and upstream URLs never come from browser input. */
export function registerManagedAi(app: FastifyInstance, config: AppConfig, fetchImpl: typeof fetch = fetch) {
  app.get('/v1/models', async () => ({data: [...new Set([config.deepseek.fastModel, config.deepseek.reasoningModel, config.deepseek.visionModel])].map(id => ({id}))}));
  app.post('/api/ai/test', async (_request, reply) => {
    if (!config.deepseek.apiKey) return reply.code(503).send({message: '请在根目录 .env.local 填写 DEEPSEEK_API_KEY 后重启'});
    try {
      const response = await fetchImpl(`${config.deepseek.baseUrl.replace(/\/+$/, '')}/chat/completions`, {
        method: 'POST', headers: {'Content-Type':'application/json', Authorization:`Bearer ${config.deepseek.apiKey}`},
        body: JSON.stringify({model: config.deepseek.fastModel, messages:[{role:'user',content:'Reply OK'}], max_tokens:32, thinking:{type:'disabled'}}), signal: AbortSignal.timeout(30000)
      });
      if (!response.ok) { await response.body?.cancel(); return reply.code(502).send({message:`模型连接失败（HTTP ${response.status}），请检查地址、Key 和模型权限`}); }
      const result = await response.json() as {choices?: {message?: {content?: string}}[]};
      if (!result.choices?.[0]?.message?.content) return reply.code(502).send({message:'模型返回了空内容，请检查模型能力'});
      return {ok:true, model:config.deepseek.fastModel, message:'模型连接正常'};
    } catch { return reply.code(502).send({message:'模型连接超时或网络不可用'}); }
  });
  app.post('/v1/chat/completions', async (request, reply) => {
    if (!config.deepseek.apiKey) return reply.code(503).send({error:{message:'服务端未配置 API Key，请填写根目录 .env.local 并重启'}});
    const body = request.body as Record<string, unknown>;
    if (!body || !Array.isArray(body.messages)) return reply.code(400).send({error:{message:'messages 必须是数组'}});
    const allowed = [config.deepseek.fastModel,config.deepseek.reasoningModel,config.deepseek.visionModel];
    if (body.model && !allowed.includes(String(body.model))) return reply.code(400).send({error:{message:'模型未在服务端配置，请检查配置文件'}});
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 180000);
    reply.raw.on('close', () => { clearTimeout(timeout); controller.abort(); });
    try {
      const response = await fetchImpl(`${config.deepseek.baseUrl.replace(/\/+$/, '')}/chat/completions`, {
        method:'POST', headers:{'Content-Type':'application/json', Authorization:`Bearer ${config.deepseek.apiKey}`},
        body:JSON.stringify({...body,model:body.model || config.deepseek.fastModel}), signal:controller.signal
      });
      if (!response.ok || !response.body) { await response.body?.cancel(); clearTimeout(timeout); return reply.code(502).send({error:{message:`上游模型错误（HTTP ${response.status}）`}}); }
      reply.header('Content-Type',response.headers.get('content-type') || 'application/json');
      reply.header('Cache-Control','no-store');
      return reply.send(Readable.fromWeb(response.body as any));
    } catch { clearTimeout(timeout); return reply.code(502).send({error:{message:'模型服务暂时不可用，请检查配置与网络'}}); }
  });
}
