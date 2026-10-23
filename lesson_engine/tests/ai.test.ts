import { describe, expect, it, vi } from 'vitest';
import { z } from 'zod';
import { DeepSeekTutorAI, DeepSeekVisionExtractor, QwenVisionExtractor, createDefaultTutor, createVisionExtractor } from '../src/ai/deepseek.js';
import { loadConfig } from '../src/config.js';
import { AnthropicCompatibleClient } from '../src/ai/anthropic-client.js';
import { OpenAICompatibleClient } from '../src/ai/chat-client.js';
import type { StructuredChatClient, StructuredCompletionOptions } from '../src/ai/types.js';
import { ProviderError, ReasoningBudgetError } from '../src/lib/errors.js';
import { createPlan, createProblem, createSolution } from './helpers/lesson-fixtures.js';

class RecordingClient implements StructuredChatClient {
  calls: Array<{ schemaName: string; options: StructuredCompletionOptions }> = [];
  constructor(private readonly responder: (options: StructuredCompletionOptions) => unknown) {}
  async completeStructured<T>(schema: z.ZodType<T>, options: StructuredCompletionOptions): Promise<T> {
    this.calls.push({ schemaName: options.schemaName, options });
    return schema.parse(this.responder(options));
  }
}

describe('DeepSeek and Qwen adapters', () => {
  it('routes text extraction to the fast model and solving to the reasoning model', async () => {
    const client = new RecordingClient((options) => {
      if (options.schemaName === 'ProblemExtract') return { stem: '1 + 1 = ?', options: [], diagramMode: 'none' };
      return { subject: '数学', topic: '加法', correctOptions: [], finalAnswer: '2', confidence: 0.99, steps: [{ title: '计算', reasoning: '1 加 1 等于 2。' }], checks: [], sourceComparison: '' };
    });
    const tutor = new DeepSeekTutorAI(client, { reasoningModel: 'deepseek-v4-pro', fastModel: 'deepseek-flash' });
    const problem = await tutor.extractProblem({ text: '1 + 1 = ?' });
    await tutor.solveProblem(problem);
    expect(client.calls[0].options.model).toBe('deepseek-flash');
    expect(JSON.stringify(client.calls[0].options.messages)).toContain('ProblemExtract JSON Schema');
    expect(client.calls[1].options.model).toBe('deepseek-v4-pro');
    expect(JSON.stringify(client.calls[1].options.messages)).toContain('SolutionResult JSON Schema');
  });

  it('读图只做 OCR 与图形描述，坐标留给专门的原图重建（避免一次输出被截断）', async () => {
    const client = new RecordingClient(() => ({ stem: '电磁感应双杆', options: [], diagramMode: 'image' }));
    const extractor = new DeepSeekVisionExtractor(client, ['deepseek-flash']);
    await extractor.extract({ image: { data: Buffer.from('img'), mimeType: 'image/jpeg', fileName: 'q.jpg' } });
    const prompt = JSON.stringify(client.calls[0].options.messages);
    expect(prompt).toContain('不要给出图元坐标');
    expect(prompt).toContain('diagramDescription');
    // 指令里不能再要求"逐个对象写进 baseElements"（schema 文本里出现 baseElements 是正常的）
    expect(prompt).not.toContain('必须把图形重画依据写入 diagramBlueprint');
    expect(prompt).not.toContain('像临摹一样先完整重现原图');
    expect(client.calls[0].options.maxTokens).toBe(8000);
  });

  it('原图重建会把题目图片一起发给模型（看着图重建，而不是凭题干另画）', async () => {
    const client = new RecordingClient(() => ({
      template: 'custom-svg', shape: 'generic', orientation: 'free', title: '',
      slots: [], relations: ['AB 与 EF 间距为 L'], baseElements: [], notes: []
    }));
    const tutor = new DeepSeekTutorAI(client, { reasoningModel: 'deepseek-v4-pro', fastModel: 'deepseek-flash' });
    await tutor.createDiagramBlueprint(
      createProblem({ subject: '物理', diagramMode: 'image', diagramDescription: '金属导轨俯视图' }),
      createSolution({ subject: '物理' }),
      { data: Buffer.from('image-bytes'), mimeType: 'image/jpeg', fileName: 'q.jpg' }
    );
    const messages = JSON.stringify(client.calls[0].options.messages);
    expect(messages).toContain('data:image/jpeg;base64,');
    expect(messages).toContain('像临摹一样按图重建');
  });

  it('推理模型把预算烧在思考上时，关掉 thinking 重试而不是直接失败', async () => {
    let solveCalls = 0;
    const client = new RecordingClient((options) => {
      if (options.schemaName !== 'SolutionResult') throw new Error('unexpected schema');
      solveCalls += 1;
      if (solveCalls === 1) {
        throw new ReasoningBudgetError('DeepSeek', '响应中缺少文本内容（finish_reason=length，reasoning_content=12662 字符）', 12662);
      }
      return { subject: '物理', topic: '电磁感应', correctOptions: ['A', 'C', 'D'], finalAnswer: 'ACD', confidence: 0.9, steps: [{ title: '求解', reasoning: '动量定理 + 能量守恒。' }], checks: [], sourceComparison: '' };
    });
    const tutor = new DeepSeekTutorAI(client, { reasoningModel: 'deepseek-v4-pro', fastModel: 'deepseek-flash' });
    const solution = await tutor.solveProblem(createProblem({ subject: '物理', stem: '电磁感应双杆' }));
    expect(solution.correctOptions).toEqual(['A', 'C', 'D']);
    expect(solveCalls).toBe(2);
    const retry = client.calls[1].options;
    expect((retry.extraBody as Record<string, any>).thinking.type).toBe('disabled');
    expect(retry.maxTokens).toBe(client.calls[0].options.maxTokens);
    expect(JSON.stringify(retry.messages)).toContain('不要再长篇推演');
  });

  it('普通供应商错误不会被当成思考预算问题重试', async () => {
    let calls = 0;
    const client = new RecordingClient(() => { calls += 1; throw new ProviderError('DeepSeek', '网络请求失败', 502); });
    const tutor = new DeepSeekTutorAI(client, { reasoningModel: 'deepseek-v4-pro', fastModel: 'deepseek-flash' });
    await expect(tutor.solveProblem(createProblem({ subject: '物理', stem: 'x' }))).rejects.toThrow('网络请求失败');
    expect(calls).toBe(1);
  });

  it('原图重建先走快速模型（带图），能给出对象就不再叫推理模型', async () => {
    const client = new RecordingClient(() => ({
      template: 'custom-svg', shape: 'generic', orientation: 'free', title: '题目图形',
      slots: [{ id: 'A', role: 'point', label: 'A', value: '' }],
      relations: ['A 在水平面上'], baseElements: [], notes: []
    }));
    const tutor = new DeepSeekTutorAI(client, { reasoningModel: 'deepseek-v4-pro', fastModel: 'deepseek-flash' });
    const result = await tutor.createDiagramBlueprint(
      createProblem({ subject: '物理', diagramMode: 'image', diagramDescription: '水平面上的点 A' }),
      createSolution({ subject: '物理' }),
      { data: Buffer.from('img'), mimeType: 'image/jpeg', fileName: 'q.jpg' }
    );
    expect(result.template).toBe('custom-svg');
    expect(client.calls).toHaveLength(1);
    expect(client.calls[0].options.model).toBe('deepseek-flash');
    expect(JSON.stringify(client.calls[0].options.messages)).toContain('禁止因为出现某个关键词就套用整题模板');
    expect(JSON.stringify(client.calls[0].options.messages)).toContain('data:image/jpeg;base64,');
  });

  it('快速模型给不出任何对象时，回退推理模型重做一次', async () => {
    let call = 0;
    const client = new RecordingClient(() => {
      call += 1;
      if (call === 1) {
        return { template: 'custom-svg', shape: 'generic', orientation: 'free', title: '', slots: [], relations: [], baseElements: [], notes: [] };
      }
      return {
        template: 'custom-svg', shape: 'generic', orientation: 'free', title: '重建结果',
        slots: [{ id: 'A', role: 'point', label: 'A', value: '' }], relations: [], baseElements: [], notes: []
      };
    });
    const tutor = new DeepSeekTutorAI(client, { reasoningModel: 'deepseek-v4-pro', fastModel: 'deepseek-flash' });
    const result = await tutor.createDiagramBlueprint(
      createProblem({ subject: '物理', diagramMode: 'image', diagramDescription: '水平面上的点 A' }),
      createSolution({ subject: '物理' }),
      { data: Buffer.from('img'), mimeType: 'image/jpeg', fileName: 'q.jpg' }
    );
    expect(result.title).toBe('重建结果');
    expect(client.calls).toHaveLength(2);
    expect(client.calls[1].options.model).toBe('deepseek-v4-pro');
  });

  it('passes an image data URL to Qwen-VL and retries fallback models', async () => {
    const client = new RecordingClient((options) => {
      if (options.model === 'primary') throw new Error('model unavailable');
      return { stem: '图片题目', options: [], diagramMode: 'image' };
    });
    const extractor = new QwenVisionExtractor(client, ['primary', 'fallback']);
    const result = await extractor.extract({ image: { data: Buffer.from('image-bytes'), mimeType: 'image/jpeg', fileName: 'question.jpg' } });
    expect(result.stem).toBe('图片题目');
    expect(JSON.stringify(client.calls[1].options.messages[1])).toContain('data:image/jpeg;base64,');
  });

  it('stops immediately when the Alibaba key is unauthorized', async () => {
    const client = new RecordingClient(() => { throw new ProviderError('阿里云百炼', 'Incorrect API key provided', 401); });
    const extractor = new QwenVisionExtractor(client, ['primary', 'fallback', 'third']);
    await expect(extractor.extract({ image: { data: Buffer.from('x'), mimeType: 'image/png', fileName: 'x.png' } })).rejects.toThrow('阿里云百炼鉴权失败');
    expect(client.calls).toHaveLength(1);
  });

  it('repairs a visual report with Flash without changing the answer', async () => {
    const client = new RecordingClient(() => ({ summary: '移动标签', operations: [{ kind: 'set_focus', sceneIndex: 0, x: 300, y: 200, reason: '避开文字' }] }));
    const tutor = new DeepSeekTutorAI(client, { reasoningModel: 'deepseek-v4-pro', fastModel: 'deepseek-flash' });
    const repair = await tutor.repairLessonPlan(createProblem(), createSolution(), createPlan(), { iteration: 0, score: 85, passed: false, issues: [], screenshots: [], labelBoxes: [], metricsVersion: '1.0' });
    expect(repair.operations[0].kind).toBe('set_focus');
    expect(client.calls[0].options.model).toBe('deepseek-flash');
  });

  it('validates Alibaba model output against the schema', async () => {
    const client = new RecordingClient(() => ({ stem: '题目', options: [], diagramMode: 'bad-value' }));
    const extractor = new QwenVisionExtractor(client, ['qwen-vl']);
    await expect(extractor.extract({ image: { data: Buffer.from('x'), mimeType: 'image/png', fileName: 'x.png' } })).rejects.toThrow();
  });
  it('supports Anthropic-compatible gateways and image blocks', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(new Response(JSON.stringify({ content: [{ type: 'text', text: '{"ok":true}' }] }), { status: 200 })) as unknown as typeof fetch;
    const client = new AnthropicCompatibleClient({ providerName: 'Anthropic gateway', apiKey: 'secret', baseUrl: 'https://gateway.example/apps/anthropic', fetchImpl });
    const schema = z.object({ ok: z.boolean() });
    const result = await client.completeStructured(schema, {
      model: 'qwen3-vl-plus', schemaName: 'Smoke',
      messages: [{ role: 'system', content: '只输出 JSON' }, { role: 'user', content: [{ type: 'text', text: '看图' }, { type: 'image_url', image_url: { url: 'data:image/png;base64,AAAA' } }] }]
    });
    expect(result.ok).toBe(true);
    const [url, options] = (fetchImpl as any).mock.calls[0];
    expect(url).toBe('https://gateway.example/apps/anthropic/v1/messages');
    expect(options.headers['x-api-key']).toBe('secret');
    expect(options.headers['anthropic-version']).toBe('2023-06-01');
    const body = JSON.parse(options.body);
    expect(body.system).toBe('只输出 JSON');
    expect(body.messages[0].content[1]).toMatchObject({ type: 'image', source: { type: 'base64', media_type: 'image/png' } });
  });

  it('没有阿里云 Key 时用 deepseek-flash 读图', async () => {
    const client = new RecordingClient(() => ({ stem: '图片题目', options: [], diagramMode: 'image' }));
    const extractor = new DeepSeekVisionExtractor(client, ['deepseek-flash']);
    const result = await extractor.extract({ image: { data: Buffer.from('image-bytes'), mimeType: 'image/png', fileName: 'question.png' } });
    expect(result.stem).toBe('图片题目');
    expect(client.calls[0].options.model).toBe('deepseek-flash');
    expect(JSON.stringify(client.calls[0].options.messages[1])).toContain('data:image/png;base64,');
  });

  it('视觉抽取器优先千问，其次 DeepSeek flash，都没有则返回 undefined', () => {
    const client = new RecordingClient(() => ({ stem: 'x', options: [], diagramMode: 'none' }));
    const both = loadConfig({ deepseek: { apiKey: 'sk-ds' }, aliyun: { apiKey: 'sk-aliyun' } });
    const onlyDeepseek = loadConfig({ deepseek: { apiKey: 'sk-ds' }, aliyun: { apiKey: '' } });
    const none = loadConfig({ deepseek: { apiKey: '' }, aliyun: { apiKey: '' } });
    expect(createVisionExtractor(both, client)).toBeInstanceOf(QwenVisionExtractor);
    expect(createVisionExtractor(onlyDeepseek, client)).toBeInstanceOf(DeepSeekVisionExtractor);
    expect(createVisionExtractor(none, client)).toBeUndefined();
  });

  it('DeepSeek 读图鉴权失败时给出明确提示且不重试其它模型', async () => {
    const client = new RecordingClient(() => { throw new ProviderError('DeepSeek', 'Incorrect API key provided', 401); });
    const extractor = new DeepSeekVisionExtractor(client, ['deepseek-flash', 'deepseek-v4-pro']);
    await expect(extractor.extract({ image: { data: Buffer.from('x'), mimeType: 'image/png', fileName: 'x.png' } })).rejects.toThrow('DeepSeek 鉴权失败');
    expect(client.calls).toHaveLength(1);
  });

  it('输出被 max_tokens 截断时，重试提示要求精简而不是原样重出', async () => {
    const truncated = '{"subject":"物理","steps":[{"title":"求解","reasoning":"很长很长';
    let call = 0;
    const fetchImpl = vi.fn().mockImplementation(async () => {
      call += 1;
      const body = call === 1
        ? { choices: [{ finish_reason: 'length', message: { content: truncated } }] }
        : { choices: [{ finish_reason: 'stop', message: { content: '{"ok":true}' } }] };
      return new Response(JSON.stringify(body), { status: 200 });
    }) as unknown as typeof fetch;
    const client = new OpenAICompatibleClient({ providerName: 'test', apiKey: 'secret', baseUrl: 'https://example.test', fetchImpl });
    const result = await client.completeStructured(z.object({ ok: z.boolean() }), {
      model: 'deepseek-v4-pro', schemaName: 'SolutionResult', messages: [{ role: 'user', content: 'solve' }]
    });
    expect(result.ok).toBe(true);
    const secondBody = JSON.parse((fetchImpl as any).mock.calls[1][1].body);
    const prompt = JSON.stringify(secondBody.messages);
    expect(prompt).toContain('超出了输出上限被截断');
    expect(prompt).toContain('steps 最多 4 步');
  });

  it('普通的格式错误仍然只要求按 schema 重出', async () => {
    let call = 0;
    const fetchImpl = vi.fn().mockImplementation(async () => {
      call += 1;
      const body = call === 1
        ? { choices: [{ finish_reason: 'stop', message: { content: '抱歉，我先解释一下思路' } }] }
        : { choices: [{ finish_reason: 'stop', message: { content: '{"ok":true}' } }] };
      return new Response(JSON.stringify(body), { status: 200 });
    }) as unknown as typeof fetch;
    const client = new OpenAICompatibleClient({ providerName: 'test', apiKey: 'secret', baseUrl: 'https://example.test', fetchImpl });
    await client.completeStructured(z.object({ ok: z.boolean() }), {
      model: 'deepseek-flash', schemaName: 'LessonPlan', messages: [{ role: 'user', content: 'plan' }]
    });
    const prompt = JSON.stringify(JSON.parse((fetchImpl as any).mock.calls[1][1].body).messages);
    expect(prompt).toContain('严格按照提供的 JSON Schema');
    expect(prompt).not.toContain('超出输出上限被截断');
  });

  it('forwards provider-specific request options', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(new Response(JSON.stringify({ choices: [{ message: { content: '{"ok":true}' } }] }), { status: 200 })) as unknown as typeof fetch;
    const client = new OpenAICompatibleClient({ providerName: 'test', apiKey: 'secret', baseUrl: 'https://example.test', fetchImpl });
    await client.completeStructured(z.object({ ok: z.boolean() }), {
      model: 'deepseek-v4.1-flash', schemaName: 'Smoke', extraBody: { enable_thinking: false },
      messages: [{ role: 'user', content: 'return json' }]
    });
    const body = JSON.parse((fetchImpl as any).mock.calls[0][1].body);
    expect(body.enable_thinking).toBe(false);
  });

});

describe('读图的思考开关（回归：排课关了思考、读图漏关）', () => {
  it('DeepSeek 读图会带上关闭思考的网关参数', async () => {
    const client = new RecordingClient(() => ({ stem: '图片题目', options: [], diagramMode: 'image' }));
    const extractor = new DeepSeekVisionExtractor(client, ['deepseek-flash'], { thinking: { type: 'disabled' } });
    await extractor.extract({ image: { data: Buffer.from('image-bytes'), mimeType: 'image/png', fileName: 'q.png' } });
    expect((client.calls[0].options.extraBody as Record<string, any>).thinking.type).toBe('disabled');
  });

  it('createDefaultTutor 会把开关接到视觉抽取器上（visionModel 也是思考模型时）', () => {
    const config = loadConfig({ deepseek: { apiKey: 'sk-ds', disableThinking: true, visionModel: 'deepseek-flash' }, aliyun: { apiKey: '' } });
    const tutor = createDefaultTutor(config);
    const vision = (tutor as unknown as { visionExtractor: DeepSeekVisionExtractor }).visionExtractor;
    expect(vision).toBeInstanceOf(DeepSeekVisionExtractor);
    expect((vision as unknown as { extraBody: Record<string, unknown> }).extraBody).toEqual({ thinking: { type: 'disabled' } });
  });

  it('关掉 DEEPSEEK_DISABLE_THINKING 时读图不带任何开关', () => {
    const config = loadConfig({ deepseek: { apiKey: 'sk-ds', disableThinking: false, visionModel: 'deepseek-flash' }, aliyun: { apiKey: '' } });
    const tutor = createDefaultTutor(config);
    const vision = (tutor as unknown as { visionExtractor: DeepSeekVisionExtractor }).visionExtractor;
    expect((vision as unknown as { extraBody: Record<string, unknown> }).extraBody).toEqual({});
  });

  it('配了阿里云 Key 时读图走千问，并带上 DashScope 侧的关思考开关', () => {
    // 工厂会给千问路径自建 client，所以这里只断言构造出来的开关，不发真实请求。
    const client = new RecordingClient(() => ({ stem: '图片题目', options: [], diagramMode: 'image' }));
    const config = loadConfig({ deepseek: { apiKey: '', disableThinking: true }, aliyun: { apiKey: 'sk-aliyun' } });
    const extractor = createVisionExtractor(config, client);
    expect(extractor).toBeInstanceOf(QwenVisionExtractor);
    expect((extractor as unknown as { extraBody: Record<string, unknown> }).extraBody).toEqual({ enable_thinking: false });
  });
});
