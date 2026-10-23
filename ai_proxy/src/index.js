/**
 * 「格数至理」AI 网关（Cloudflare Worker / 任意支持 fetch 的运行时）。
 *
 * 目的：把 API Key 与系统提示词从浏览器端挪到服务端，前端只与本网关通信。
 *
 *   前端 ──POST /v1/chat/completions──▶ 本网关 ──Bearer <真Key>──▶ 任意 OpenAI 兼容服务
 *
 * 关键行为：
 *  1. 永不转发客户端带来的 Authorization —— 一律用服务端环境变量里的真 Key。
 *  2. X-Board 头指定板块时，用服务端 registry 里的系统提示词覆盖客户端内置的
 *     系统消息（真正把「指令」藏在服务端）。客户端要自带自定义提示词时，
 *     额外带 X-Custom-Prompt: 1 即可放行。
 *  3. 模型白名单：客户端把模型名写歪也不让它打到白名单外的模型（防烧钱）。
 *  4. SSE 原样透传（流式）与 JSON 透传（非流式）都支持。
 *  5. CORS 预检在网关处理，前端可跨域直连。
 *
 * 上游协议：标准 OpenAI 兼容（/chat/completions），
 * 与本仓库 lib/core/network/ai_api_client.dart 完全一致。
 */

/** X-Board 取值 → prompts registry 键。 */
export const BOARD_KEYS = [
  'wrongQuestion',
  'expert',
  'followUp',
  'exam',
  'qa',
  'report',
];

function corsHeaders(env) {
  return {
    'Access-Control-Allow-Origin': env.ALLOW_ORIGIN || '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers':
      'Content-Type, Authorization, X-Board, X-Custom-Prompt',
    'Access-Control-Max-Age': '86400',
  };
}

function jsonError(status, message, env) {
  return new Response(
    JSON.stringify({ error: { message, type: 'proxy_error' } }),
    {
      status,
      headers: { 'Content-Type': 'application/json', ...corsHeaders(env) },
    },
  );
}

/** 去掉客户端发来的所有 system 消息，只保留对话内容。 */
function stripSystem(messages) {
  return (Array.isArray(messages) ? messages : []).filter(
    (m) => m && m.role !== 'system',
  );
}

/** 把上游 base 与请求 path 拼成真实上游地址（去掉 path 里的 /v1 前缀）。 */
export function buildUpstreamUrl(upstreamBase, pathname) {
  const base = String(upstreamBase || '').replace(/\/+$/, '');
  let path = pathname || '/chat/completions';
  path = path.replace(/^\/v1(?=\/|$)/, '');
  if (!path.startsWith('/')) path = '/' + path;
  return base + path;
}

/**
 * 网关核心。抽成纯函数便于单测：只依赖传入的 request/env/prompts 和全局 fetch。
 *
 * @param {Request} request
 * @param {{UPSTREAM_BASE_URL?: string, UPSTREAM_API_KEY?: string,
 *          ALLOWED_MODELS?: string, ALLOW_ORIGIN?: string}} env
 * @param {Record<string, string>} prompts 板块 → 系统提示词
 */
export async function handleRequest(request, env, prompts = {}) {
  const cors = corsHeaders(env);

  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: cors });
  }
  if (request.method !== 'POST') {
    return jsonError(405, '只支持 POST', env);
  }

  if (!env.UPSTREAM_BASE_URL) {
    return jsonError(500, '服务端未配置 UPSTREAM_BASE_URL', env);
  }
  if (!env.UPSTREAM_API_KEY) {
    return jsonError(500, '服务端未配置 UPSTREAM_API_KEY', env);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return jsonError(400, '请求体不是合法 JSON', env);
  }

  // ── 服务端托管系统提示词 ───────────────────────────────────────
  const board = request.headers.get('X-Board');
  const customPrompt = request.headers.get('X-Custom-Prompt') === '1';
  if (board && prompts[board] && !customPrompt && Array.isArray(body.messages)) {
    body.messages = [
      { role: 'system', content: prompts[board] },
      ...stripSystem(body.messages),
    ];
  }

  // ── 模型白名单 ────────────────────────────────────────────────
  const allow = String(env.ALLOWED_MODELS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  if (allow.length && !allow.includes(body.model)) {
    body.model = allow[0];
  }

  const upstreamUrl = buildUpstreamUrl(
    env.UPSTREAM_BASE_URL,
    new URL(request.url).pathname,
  );

  const upstreamRes = await fetch(upstreamUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      // 关键：只用服务端 Key，绝不透传客户端 Authorization。
      Authorization: `Bearer ${env.UPSTREAM_API_KEY}`,
      Accept:
        request.headers.get('Accept') ||
        (body.stream ? 'text/event-stream' : 'application/json'),
    },
    body: JSON.stringify(body),
  });

  const headers = new Headers();
  const upstreamType = upstreamRes.headers.get('content-type');
  if (upstreamType) headers.set('Content-Type', upstreamType);
  for (const [k, v] of Object.entries(cors)) headers.set(k, v);

  // 直接把上游 body（ReadableStream）透传回去：SSE 流式逐块到达，不缓冲。
  return new Response(upstreamRes.body, {
    status: upstreamRes.status,
    headers,
  });
}

export default {
  async fetch(request, env) {
    // prompts.gen.js 由 scripts/extract-prompts.mjs 从 Dart 源码生成。
    const { PROMPTS } = await import('./prompts.gen.js');
    return handleRequest(request, env, PROMPTS);
  },
};
