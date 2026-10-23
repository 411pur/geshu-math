import { z } from 'zod';
import { ConfigurationError, ProviderError } from '../lib/errors.js';
import { extractJsonObject, summarizeJsonError } from '../lib/json.js';
import type { ChatMessage, StructuredChatClient, StructuredCompletionOptions } from './types.js';

export interface AnthropicCompatibleOptions { providerName: string; apiKey: string; baseUrl: string; fetchImpl?: typeof fetch; timeoutMs?: number; }
interface AnthropicResponse { content?: Array<{ type?: string; text?: string }>; error?: { message?: string; type?: string }; message?: string; }

export class AnthropicCompatibleClient implements StructuredChatClient {
  private readonly fetchImpl: typeof fetch;
  private readonly timeoutMs: number;
  constructor(private readonly options: AnthropicCompatibleOptions) { this.fetchImpl = options.fetchImpl || fetch; this.timeoutMs = options.timeoutMs || 120_000; }

  async completeStructured<T>(schema: z.ZodType<T>, options: StructuredCompletionOptions): Promise<T> {
    const first = await this.complete(options);
    try { return schema.parse(options.normalize ? options.normalize(extractJsonObject(first)) : extractJsonObject(first)); }
    catch (error) {
      const repairMessages: ChatMessage[] = [...options.messages, { role: 'assistant', content: first }, { role: 'user', content: `上一条响应不是有效的 ${options.schemaName} JSON：${summarizeJsonError(error)}。只输出符合 JSON Schema 的 JSON，不要解释。` }];
      const repaired = await this.complete({ ...options, messages: repairMessages, temperature: 0 });
      try { return schema.parse(options.normalize ? options.normalize(extractJsonObject(repaired)) : extractJsonObject(repaired)); }
      catch (repairError) { throw new ProviderError(this.options.providerName, `${options.schemaName} Anthropic 响应校验失败：${summarizeJsonError(repairError)}`); }
    }
  }

  private async complete(options: StructuredCompletionOptions): Promise<string> {
    if (!this.options.apiKey) throw new ConfigurationError(`${this.options.providerName} API Key 未配置`);
    const endpoint = `${this.options.baseUrl.replace(/\/+$/, '')}/v1/messages`;
    const system = options.messages.filter((message) => message.role === 'system' && typeof message.content === 'string').map((message) => message.content as string).join('\n\n');
    const messages = options.messages.filter((message) => message.role !== 'system').map(toAnthropicMessage);
    let response: Response;
    try {
      response = await this.fetchImpl(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-api-key': this.options.apiKey, 'anthropic-version': '2023-06-01' },
        body: JSON.stringify({ model: options.model, max_tokens: options.maxTokens ?? 8000, temperature: options.temperature ?? 0.2, system: system || undefined, messages }),
        signal: AbortSignal.timeout(options.timeoutMs ?? this.timeoutMs)
      });
    } catch (error) { throw new ProviderError(this.options.providerName, `${this.options.providerName} 网络请求失败：${summarizeJsonError(error)}`); }

    const raw = await response.text();
    let payload: AnthropicResponse;
    try { payload = JSON.parse(raw) as AnthropicResponse; } catch { throw new ProviderError(this.options.providerName, `${this.options.providerName} 返回了无法解析的响应`, response.status || 502); }
    if (!response.ok) {
      const message = payload.error?.message || payload.message || raw.slice(0, 800) || response.statusText;
      throw new ProviderError(this.options.providerName, `${this.options.providerName} Anthropic 请求失败（${response.status}）：${message}`, response.status);
    }
    const text = payload.content?.filter((block) => block.type === 'text' || block.text).map((block) => block.text || '').join('');
    if (!text?.trim()) throw new ProviderError(this.options.providerName, `${this.options.providerName} Anthropic 响应中缺少文本内容`);
    return text;
  }
}

function toAnthropicMessage(message: ChatMessage) {
  if (typeof message.content === 'string') return { role: message.role, content: message.content };
  const content = message.content.map((item) => {
    if (item.type === 'text') return { type: 'text', text: item.text };
    const match = item.image_url.url.match(/^data:([^;]+);base64,(.+)$/);
    if (!match) throw new Error('Anthropic 图片必须是 Base64 Data URL');
    return { type: 'image', source: { type: 'base64', media_type: match[1], data: match[2] } };
  });
  return { role: message.role, content };
}
