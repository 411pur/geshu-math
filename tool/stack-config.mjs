import path from 'node:path';

export function validateConfig(input, root) {
  if (input.host !== '127.0.0.1') throw new Error('本地服务只支持 127.0.0.1');
  const providers = {
    fastProvider: input.fastProvider || 'deepseek',
    reasoningProvider: input.reasoningProvider || input.fastProvider || 'deepseek',
    visionProvider: input.visionProvider || 'auto'
  };
  for (const key of ['fastProvider','reasoningProvider']) {
    if (!['deepseek','aliyun'].includes(providers[key])) throw new Error(`${key} 必须是 deepseek 或 aliyun`);
  }
  if (!['auto','deepseek','aliyun'].includes(providers.visionProvider)) throw new Error('visionProvider 必须是 auto、deepseek 或 aliyun');
  if (!Number.isInteger(input.port) || input.port < 1024 || input.port > 65535) throw new Error('port 必须是 1024–65535 的整数');
  const url = new URL(input.apiBaseUrl);
  if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error('模型地址格式无效');
  for (const key of ['model','visionModel','reasoningModel']) if (typeof input[key] !== 'string' || !input[key].trim()) throw new Error(`${key} 不能为空`);
  for (const key of ['requestTimeoutMs','maxImageBytes','maxDocumentBytes']) if (!Number.isInteger(input[key]) || input[key] <= 0) throw new Error(`${key} 必须是正整数`);
  if (typeof input.buildWeb !== 'boolean') throw new Error('buildWeb 必须为布尔值');
  const dataDir = path.resolve(root,input.dataDir);
  const relative = path.relative(root,dataDir);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('数据目录必须位于本项目内');
  if (relative.split(path.sep)[0] === 'build' || relative.split(path.sep)[0] === 'web') throw new Error('数据目录不能放入公开静态目录');
  return {...input,...providers,dataDir};
}

export function publicConfig(config) {
  const origin = `http://${config.host}:${config.port}`;
  return { apiBaseUrl: `${origin}/v1`, apiKey: 'proxy-managed', model:config.model, visionModel:config.visionModel,
    reasoningModel:config.reasoningModel, useServerPrompts:false, managedAi:true,
    modelProviders:{fast:config.fastProvider,reasoning:config.reasoningProvider,vision:config.visionProvider},
    lessonStudio:{externalLessonBridgeUrl:origin,timeoutMs:config.requestTimeoutMs,model:config.model} };
}
