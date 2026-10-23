import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { OpenAICompatibleClient } from '../../src/ai/chat-client.js';
import { loadConfig } from '../../src/config.js';

const runLive = process.env.RUN_LIVE_API_TESTS === '1';
const skipAliyun = process.env.SKIP_ALIYUN_LIVE === '1';

describe.runIf(runLive)('live provider connectivity', () => {
  it('lists and uses a DeepSeek model with structured JSON', async () => {
    const config = loadConfig();
    const modelsResponse = await fetch(`${config.deepseek.baseUrl.replace(/\/+$/, '')}/models`, {
      headers: { Authorization: `Bearer ${config.deepseek.apiKey}` }
    });
    expect(modelsResponse.ok).toBe(true);
    const models = await modelsResponse.json();
    const ids = models.data.map((item: { id: string }) => item.id);
    expect(ids).toContain(config.deepseek.fastModel);

    const client = new OpenAICompatibleClient({
      providerName: 'DeepSeek live',
      apiKey: config.deepseek.apiKey,
      baseUrl: config.deepseek.baseUrl,
      timeoutMs: 90_000
    });
    const result = await client.completeStructured(z.object({ ok: z.boolean() }), {
      model: config.deepseek.fastModel,
      schemaName: 'LiveSmoke',
      temperature: 0,
      maxTokens: 512,
      messages: [
        { role: 'system', content: '只输出 JSON。' },
        { role: 'user', content: '输出 {"ok":true}' }
      ]
    });
    expect(result.ok).toBe(true);
  });

  it.skipIf(skipAliyun)('lists the configured Alibaba vision model', async () => {
    const config = loadConfig();
    const response = await fetch(`${config.aliyun.baseUrl.replace(/\/+$/, '')}/models`, {
      headers: { Authorization: `Bearer ${config.aliyun.apiKey}` }
    });
    expect(response.ok).toBe(true);
    const models = await response.json();
    const ids = models.data.map((item: { id: string }) => item.id);
    expect(ids).toContain(config.aliyun.visionModel);
  });
});
