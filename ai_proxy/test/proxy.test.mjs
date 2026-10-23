import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleRequest, buildUpstreamUrl } from '../src/index.js';

const ENV = {
  UPSTREAM_BASE_URL: 'https://upstream.test/compatible-mode/v1',
  UPSTREAM_API_KEY: 'sk-server-secret',
  ALLOWED_MODELS: 'test-model,test-vision-model',
  ALLOW_ORIGIN: 'https://app.test',
};

function post(body, headers = {}) {
  return new Request('https://proxy.test/v1/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
}

/** 假上游：捕获请求，返回固定响应。 */
function stubUpstream(responder) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url, init });
    return (
      responder?.(url, init) ??
      new Response('data: {"choices":[]}\n\n', {
        status: 200,
        headers: { 'Content-Type': 'text/event-stream' },
      })
    );
  };
  return calls;
}

test('OPTIONS 预检返回 204 + CORS', async () => {
  const res = await handleRequest(
    new Request('https://proxy.test/v1/chat/completions', { method: 'OPTIONS' }),
    ENV,
    {},
  );
  assert.equal(res.status, 204);
  assert.equal(res.headers.get('Access-Control-Allow-Origin'), 'https://app.test');
});

test('非 POST 返回 405', async () => {
  const res = await handleRequest(
    new Request('https://proxy.test/v1/chat/completions', { method: 'GET' }),
    ENV,
    {},
  );
  assert.equal(res.status, 405);
});

test('缺 UPSTREAM_API_KEY 返回 500', async () => {
  const res = await handleRequest(
    post({ messages: [] }),
    { ...ENV, UPSTREAM_API_KEY: '' },
    {},
  );
  assert.equal(res.status, 500);
});

test('剥离客户端 Authorization，改用服务端 Key', async () => {
  const calls = stubUpstream();
  await handleRequest(
    post(
      { model: 'test-model', messages: [{ role: 'user', content: 'hi' }] },
      { Authorization: 'Bearer sk-client-LEAK' },
    ),
    ENV,
    {},
  );
  assert.equal(calls.length, 1);
  assert.equal(calls[0].init.headers.Authorization, 'Bearer sk-server-secret');
  assert.ok(!JSON.stringify(calls[0].init.headers).includes('LEAK'));
});

test('上游 URL 去掉 /v1 前缀并拼接', async () => {
  const calls = stubUpstream();
  await handleRequest(post({ model: 'test-model', messages: [] }), ENV, {});
  assert.equal(
    calls[0].url,
    'https://upstream.test/compatible-mode/v1/chat/completions',
  );
});

test('SSE 流透传 + CORS', async () => {
  stubUpstream(
    () =>
      new Response('data: {"choices":[]}\n\n', {
        status: 200,
        headers: { 'Content-Type': 'text/event-stream' },
      }),
  );
  const res = await handleRequest(
    post({ model: 'test-model', stream: true, messages: [] }),
    ENV,
    {},
  );
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('Content-Type'), 'text/event-stream');
  assert.equal(res.headers.get('Access-Control-Allow-Origin'), 'https://app.test');
  assert.ok((await res.text()).includes('data:'));
});

test('X-Board 注入服务端提示词并移除客户端 system', async () => {
  const calls = stubUpstream();
  const prompts = { qa: 'SERVER-QA-PROMPT' };
  await handleRequest(
    post(
      {
        model: 'test-model',
        messages: [
          { role: 'system', content: 'CLIENT-BUILTIN' },
          { role: 'user', content: 'hello' },
        ],
      },
      { 'X-Board': 'qa' },
    ),
    ENV,
    prompts,
  );
  const sent = JSON.parse(calls[0].init.body);
  assert.equal(sent.messages[0].role, 'system');
  assert.equal(sent.messages[0].content, 'SERVER-QA-PROMPT');
  assert.ok(!JSON.stringify(sent.messages).includes('CLIENT-BUILTIN'));
  assert.equal(sent.messages.length, 2);
});

test('X-Custom-Prompt 放行客户端自带提示词', async () => {
  const calls = stubUpstream();
  await handleRequest(
    post(
      {
        model: 'test-model',
        messages: [
          { role: 'system', content: 'MY-CUSTOM' },
          { role: 'user', content: 'hi' },
        ],
      },
      { 'X-Board': 'qa', 'X-Custom-Prompt': '1' },
    ),
    ENV,
    { qa: 'SERVER-QA-PROMPT' },
  );
  const sent = JSON.parse(calls[0].init.body);
  assert.equal(sent.messages[0].content, 'MY-CUSTOM');
});

test('模型白名单外强制回落到第一个允许模型', async () => {
  const calls = stubUpstream();
  await handleRequest(post({ model: 'gpt-4-expensive', messages: [] }), ENV, {});
  const sent = JSON.parse(calls[0].init.body);
  assert.equal(sent.model, 'test-model');
});

test('buildUpstreamUrl 处理各种前缀', () => {
  assert.equal(
    buildUpstreamUrl('https://u/v1', '/v1/chat/completions'),
    'https://u/v1/chat/completions',
  );
  assert.equal(
    buildUpstreamUrl('https://u/v1/', '/chat/completions'),
    'https://u/v1/chat/completions',
  );
  assert.equal(
    buildUpstreamUrl('https://u', '/v1/chat/completions'),
    'https://u/chat/completions',
  );
});
