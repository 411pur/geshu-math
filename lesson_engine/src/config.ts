import path from 'node:path';
import dotenv from 'dotenv';

dotenv.config({ path: path.resolve(process.cwd(), '.env') });
dotenv.config({ path: path.resolve(process.cwd(), '.env.local'), override: false });

function numberFromEnv(name: string, fallback: number): number {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? value : fallback;
}

function providerFromEnv(name: string, fallback: string): ModelProvider {
  const value = process.env[name] || fallback;
  return value === 'aliyun' ? 'aliyun' : 'deepseek';
}

function visionProviderFromEnv(name: string, fallback: VisionProvider): VisionProvider {
  const value = process.env[name] || fallback;
  return value === 'deepseek' || value === 'aliyun' ? value : 'auto';
}

const regionHosts: Record<string, string> = { 'cn-beijing': 'cn-beijing', 'ap-southeast-1': 'ap-southeast-1', 'us-east-1': 'us-east-1' };

export function deriveAliyunBaseUrl(workspaceId: string, region: string): string | undefined {
  const hostRegion = regionHosts[region];
  if (!workspaceId || !hostRegion) return undefined;
  return `https://${workspaceId}.${hostRegion}.maas.aliyuncs.com/compatible-mode/v1`;
}

export type ModelProvider = 'deepseek' | 'aliyun';
export type VisionProvider = ModelProvider | 'auto';

export interface AppConfig {
  host: string;
  port: number;
  dataDir: string;
  publicDir: string;
  templatePath: string;
  maxImageBytes: number;
  maxDocumentBytes: number;
  deepseek: { apiKey: string; baseUrl: string; reasoningModel: string; fastModel: string; visionModel: string; disableThinking: boolean; };
  providers: { fast: ModelProvider; reasoning: ModelProvider; vision: VisionProvider; };
  aliyun: { apiKey: string; apiFlavor: 'openai' | 'anthropic'; baseUrl: string; workspaceId: string; region: string; model: string; visionFastModel: string; visionModel: string; visionModelFallbacks: string[]; };
}

export type ConfigOverrides = Omit<Partial<AppConfig>, 'deepseek' | 'aliyun' | 'providers'> & { deepseek?: Partial<AppConfig['deepseek']>; aliyun?: Partial<AppConfig['aliyun']>; providers?: Partial<AppConfig['providers']>; };

export function loadConfig(overrides: ConfigOverrides = {}): AppConfig {
  const workspaceId = overrides.aliyun?.workspaceId ?? process.env.ALIYUN_WORKSPACE_ID ?? '';
  const region = overrides.aliyun?.region ?? process.env.ALIYUN_REGION ?? 'cn-beijing';
  const defaultBaseUrl = deriveAliyunBaseUrl(workspaceId, region) || 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  const base: AppConfig = {
    host: process.env.HOST || '127.0.0.1',
    port: numberFromEnv('PORT', 3210),
    dataDir: path.resolve(process.env.DATA_DIR || path.join(process.cwd(), 'data', 'projects')),
    publicDir: path.resolve(process.env.PUBLIC_DIR || path.join(process.cwd(), 'public')),
    templatePath: path.join(process.cwd(), 'templates', 'teacher-board.html'),
    maxImageBytes: numberFromEnv('MAX_IMAGE_BYTES', 12 * 1024 * 1024),
    maxDocumentBytes: numberFromEnv('MAX_DOCUMENT_BYTES', 12 * 1024 * 1024),
    deepseek: { apiKey: process.env.DEEPSEEK_API_KEY || '', baseUrl: process.env.DEEPSEEK_BASE_URL || 'https://api.deepseek.com', reasoningModel: process.env.DEEPSEEK_REASONING_MODEL || 'deepseek-flash', fastModel: process.env.DEEPSEEK_FAST_MODEL || 'deepseek-flash', visionModel: process.env.DEEPSEEK_VISION_MODEL || 'deepseek-flash', disableThinking: !/^(0|false|no)$/i.test(process.env.DEEPSEEK_DISABLE_THINKING || '') },
    providers: {
      fast: providerFromEnv('MODEL_PROVIDER_FAST', process.env.DEEPSEEK_FAST_PROVIDER || 'deepseek'),
      reasoning: providerFromEnv('MODEL_PROVIDER_REASONING', process.env.DEEPSEEK_FAST_PROVIDER || 'deepseek'),
      vision: visionProviderFromEnv('MODEL_PROVIDER_VISION', 'auto')
    },
    aliyun: {
      apiKey: process.env.ALIYUN_API_KEY || '',
      apiFlavor: (process.env.ALIYUN_API_FLAVOR as 'openai' | 'anthropic') || 'openai',
      baseUrl: process.env.ALIYUN_BASE_URL || defaultBaseUrl,
      workspaceId,
      region,
      model: process.env.ALIYUN_MODEL || 'qwen-plus',
      visionFastModel: process.env.ALIYUN_VISION_FAST_MODEL || 'qwen3-vl-flash',
      visionModel: process.env.ALIYUN_VISION_MODEL || 'qwen3-vl-plus',
      visionModelFallbacks: (process.env.ALIYUN_VISION_MODEL_FALLBACKS || 'qwen-vl-max,qwen3-vl-max').split(',').map((item) => item.trim()).filter(Boolean)
    }
  };
  const mergedAliyun = { ...base.aliyun, ...overrides.aliyun };
  if (!mergedAliyun.baseUrl) mergedAliyun.baseUrl = deriveAliyunBaseUrl(mergedAliyun.workspaceId, mergedAliyun.region) || base.aliyun.baseUrl;
  return { ...base, ...overrides, deepseek: { ...base.deepseek, ...overrides.deepseek }, providers: { ...base.providers, ...overrides.providers }, aliyun: mergedAliyun };
}
