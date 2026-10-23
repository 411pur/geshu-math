import { z } from 'zod';
import { ConfigurationError, ProviderError, ReasoningBudgetError } from '../lib/errors.js';
import { extractJsonObject, summarizeJsonError } from '../lib/json.js';
import type { ChatMessage, StructuredChatClient, StructuredCompletionOptions } from './types.js';

export interface OpenAICompatibleOptions {
  providerName: string;
  apiKey: string;
  baseUrl: string;
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
}

interface ChatCompletionResponse {
  choices?: Array<{
    finish_reason?: string;
    message?: {
      content?: string | Array<{ type?: string; text?: string }>;
      reasoning_content?: string;
    };
  }>;
  error?: { message?: string };
}

/**
 * 输出被 max_tokens 截断时的"精简"提示：每个阶段的 JSON 不一样，泛泛地说"请重新输出"没用
 * （模型还会写一样长）。这里按 schema 给出各自该砍什么，实测读题这一步最容易撑爆预算。
 */
const TRUNCATION_HINTS: Record<string, string> = {
  ProblemExtract: '只保留题目必要信息：选项照抄题干原文但不要附加解释，原解析概括成 3 句以内的要点，不要输出任何图形坐标或图元。',
  SolutionResult: 'steps 最多 4 步、每步 reasoning 不超过 80 字，去掉重复推导与多余解释。',
  LessonPlan: '场景压到 4 个、每段 narration 不超过 2 句（80 字以内），图元只保留必要的对象，并且只输出紧凑的单行 JSON（不要缩进换行）。',
  DiagramBlueprint: '只保留必要的对象与几何关系，坐标保留整数。',
  LessonPlanRepair: '只输出必要的修复操作。',
  VerificationResult: 'issues 最多 3 条、每条 40 字以内，只写问题与改法、不要复述题目，并且只输出紧凑单行 JSON。'
};

export class OpenAICompatibleClient implements StructuredChatClient {
  private readonly fetchImpl: typeof fetch;
  private readonly timeoutMs: number;

  constructor(private readonly options: OpenAICompatibleOptions) {
    this.fetchImpl = options.fetchImpl || fetch;
    this.timeoutMs = options.timeoutMs || 120_000;
  }

  async completeStructured<T>(schema: z.ZodType<T>, options: StructuredCompletionOptions): Promise<T> {
    const first = await this.complete(options);
    try {
      return schema.parse(options.normalize ? options.normalize(extractJsonObject(first.text)) : extractJsonObject(first.text));
    } catch (error) {
      // 真实故障：难题上模型会写出一份很长的 SolutionResult（每步 reasoning 一大段），
      // 8000 的输出上限把它从中间切断，JSON 就成了 "Expected ',' or ']'" 这种半截报错。
      // 这时原样让它"按 schema 重出"没有用（它还会写一样长），必须明确要求精简。
      const truncated = first.finishReason === 'length';
      const repairMessages: ChatMessage[] = [
        ...options.messages,
        { role: 'assistant', content: first.text },
        {
          role: 'user',
          content: truncated
            ? [
                `上一条响应超出了输出上限被截断（不是格式写错）：${summarizeJsonError(error)}。`,
                `请大幅精简后重新输出完整的 ${options.schemaName} JSON：${TRUNCATION_HINTS[options.schemaName] ?? '去掉冗余内容，只保留 schema 要求的关键字段。'}`,
                '只输出一个闭合的 JSON 对象，不要 Markdown 代码围栏。'
              ].join('')
            : [
                `上一条响应不是有效的 ${options.schemaName} JSON：${summarizeJsonError(error)}。`,
                '请严格按照提供的 JSON Schema 重新输出，只输出 JSON，不要解释，不要 Markdown 代码围栏。'
              ].join('\n')
        }
      ];
      const repaired = await this.complete({ ...options, messages: repairMessages, temperature: 0 });
      try {
        return schema.parse(options.normalize ? options.normalize(extractJsonObject(repaired.text)) : extractJsonObject(repaired.text));
      } catch (repairError) {
        // 两个错误都带上：一个是"首次输出"的问题，一个是"修复后"的问题，
        // 否则修复尝试反而会把真正的原因盖掉（排查时会误以为是同一处格式错）。
        throw new ProviderError(
          this.options.providerName,
          `${options.schemaName} 响应校验失败：${summarizeJsonError(error)}（修复后仍失败：${summarizeJsonError(repairError)}）。原始响应预览：${preview(first.text)} / 修复响应预览：${preview(repaired.text)}`
        );
      }
    }
  }

  private async complete(options: StructuredCompletionOptions): Promise<{ text: string; finishReason: string; reasoningLength: number }> {
    if (!this.options.apiKey) throw new ConfigurationError(`${this.options.providerName} API Key 未配置`);

    const endpoint = `${this.options.baseUrl.replace(/\/+$/, '')}/chat/completions`;
    let response: Response;
    try {
      response = await this.fetchImpl(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.options.apiKey}`
        },
        body: JSON.stringify({
          model: options.model,
          messages: options.messages,
          temperature: options.temperature ?? 0.2,
          max_tokens: options.maxTokens ?? 8000,
          response_format: { type: 'json_object' },
          ...options.extraBody
        }),
        signal: AbortSignal.timeout(options.timeoutMs ?? this.timeoutMs)
      });
    } catch (error) {
      throw new ProviderError(this.options.providerName, `${this.options.providerName} 网络请求失败：${summarizeJsonError(error)}`);
    }

    const rawBody = await response.text();
    let payload: ChatCompletionResponse;
    try {
      payload = JSON.parse(rawBody) as ChatCompletionResponse;
    } catch {
      throw new ProviderError(this.options.providerName, `${this.options.providerName} 返回了无法解析的响应`, response.status || 502);
    }

    if (!response.ok) {
      const message = payload.error?.message || rawBody.slice(0, 800) || response.statusText;
      throw new ProviderError(this.options.providerName, `${this.options.providerName} 请求失败（${response.status}）：${message}`, response.status);
    }

    const message = payload.choices?.[0]?.message;
    const content = message?.content;
    const finishReason = payload.choices?.[0]?.finish_reason ?? '';
    if (typeof content === 'string' && content.trim()) return { text: content, finishReason, reasoningLength: message?.reasoning_content?.length ?? 0 };
    if (Array.isArray(content)) {
      const text = content.map((item) => item.text || '').join('');
      if (text.trim()) return { text, finishReason, reasoningLength: message?.reasoning_content?.length ?? 0 };
    }
    if (message?.reasoning_content?.trim() && process.env.ALLOW_REASONING_CONTENT_FALLBACK === '1') {
      return { text: message.reasoning_content, finishReason, reasoningLength: message.reasoning_content.length };
    }

    const choice = payload.choices?.[0];
    const reasoningLength = message?.reasoning_content?.length ?? 0;
    const detail = [
      choice?.finish_reason ? `finish_reason=${choice.finish_reason}` : '',
      reasoningLength ? `reasoning_content=${reasoningLength} 字符（模型把预算花在思考上）` : ''
    ].filter(Boolean).join('，');
    const emptyContentMessage = `${this.options.providerName} 响应中缺少文本内容${detail ? `（${detail}）` : ''}；可尝试关闭 thinking 或提高 max_tokens`;
    if (reasoningLength > 0 || choice?.finish_reason === 'length') {
      throw new ReasoningBudgetError(this.options.providerName, emptyContentMessage, reasoningLength);
    }
    throw new ProviderError(this.options.providerName, emptyContentMessage);
  }
}

function preview(value: string): string {
  return value.replace(/\s+/g, ' ').slice(0, 320);
}
