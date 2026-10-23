import { describe, expect, it } from 'vitest';
import { deriveAliyunBaseUrl, loadConfig } from '../src/config.js';
import { redactSecret } from '../src/lib/errors.js';

describe('secret redaction', () => {
  it('never returns the complete secret', () => {
    const secret = 'sk-1234567890abcdef';
    const redacted = redactSecret(secret);
    expect(redacted).not.toContain('1234567890');
    expect(redacted).toContain('sk-1');
    expect(redacted).toContain('cdef');
  });

  it('handles missing secrets without throwing', () => {
    expect(redactSecret()).toBe('<missing>');
    expect(redactSecret('short')).toBe('***');
  });
});

describe('model role configuration', () => {
  it('keeps fast, reasoning and vision providers independent', () => {
    const config = loadConfig({ providers: { fast: 'deepseek', reasoning: 'deepseek', vision: 'aliyun' } });
    expect(config.providers).toEqual({ fast: 'deepseek', reasoning: 'deepseek', vision: 'aliyun' });
  });
});

describe('Alibaba workspace endpoints', () => {
  it('derives the workspace-specific base URL for supported regions', () => {
    expect(deriveAliyunBaseUrl('ws-demo', 'cn-beijing')).toBe('https://ws-demo.cn-beijing.maas.aliyuncs.com/compatible-mode/v1');
    expect(deriveAliyunBaseUrl('ws-demo', 'ap-southeast-1')).toBe('https://ws-demo.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1');
    expect(deriveAliyunBaseUrl('ws-demo', 'us-east-1')).toBe('https://ws-demo.us-east-1.maas.aliyuncs.com/compatible-mode/v1');
  });

  it('uses a workspace URL when configured', () => {
    const config = loadConfig({
      aliyun: {
        apiKey: 'test',
        baseUrl: '',
        workspaceId: 'ws-test',
        region: 'cn-beijing',
        visionModel: 'qwen3-vl-plus',
        visionModelFallbacks: []
      }
    });
    expect(config.aliyun.baseUrl).toBe('https://ws-test.cn-beijing.maas.aliyuncs.com/compatible-mode/v1');
  });
});
