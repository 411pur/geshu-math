import {it,expect,vi} from 'vitest';
import Fastify from 'fastify';
import {configuredModelRoles,registerManagedAi} from '../src/managed-ai.js';
import {loadConfig} from '../src/config.js';

function configured(){
 return loadConfig({
  deepseek:{apiKey:'server-secret',baseUrl:'https://deepseek.test',fastModel:'fast-model',reasoningModel:'reasoning-model',visionModel:'vision-model'},
  aliyun:{apiKey:'aliyun-secret',baseUrl:'https://aliyun.test/v1',visionFastModel:'qwen-vl-fast',visionModel:'qwen-vl-plus',visionModelFallbacks:[],model:'qwen-plus'},
  providers:{fast:'deepseek',reasoning:'deepseek',vision:'aliyun'}
 });
}

it('服务器密钥替换浏览器密钥，流式内容原样返回',async()=>{
 const app=Fastify();const upstream=vi.fn(async()=>new Response('data: {"ok":true}\n\ndata: [DONE]\n\n',{headers:{'content-type':'text/event-stream'}}));
 registerManagedAi(app,configured(),upstream as any);
 try{const response=await app.inject({method:'POST',url:'/v1/chat/completions',headers:{authorization:'Bearer browser-secret'},payload:{model:'fast-model',messages:[],stream:true}});
 expect(response.statusCode).toBe(200);expect(response.body).toContain('[DONE]');expect(JSON.stringify(upstream.mock.calls)).not.toContain('browser-secret');
 expect((upstream.mock.calls as any)[0][1].headers.Authorization).toBe('Bearer server-secret');}finally{await app.close();}
});

it('按快速、推理、视觉三个角色检测真实配置与服务商',async()=>{
 const app=Fastify();const upstream=vi.fn(async()=>new Response(JSON.stringify({choices:[{message:{content:'OK'}}]}),{headers:{'content-type':'application/json'}}));
 const config=configured();
 expect(configuredModelRoles(config).map(({role,provider,model})=>({role,provider,model}))).toEqual([
  {role:'fast',provider:'deepseek',model:'fast-model'},
  {role:'reasoning',provider:'deepseek',model:'reasoning-model'},
  {role:'vision',provider:'aliyun',model:'qwen-vl-plus'}
 ]);
 registerManagedAi(app,config,upstream as any);
 try{const response=await app.inject({method:'POST',url:'/api/ai/test'});
 expect(response.statusCode).toBe(200);const body=response.json();expect(body.ok).toBe(true);expect(body.roles).toHaveLength(3);expect(body.message).toContain('3/3');
 expect(upstream).toHaveBeenCalledTimes(3);expect(JSON.stringify(body)).not.toContain('server-secret');expect(JSON.stringify(body)).not.toContain('aliyun-secret');}finally{await app.close();}
});

it('缺少密钥时返回逐角色诊断而不是暴露密钥',async()=>{
 const app=Fastify();const upstream=vi.fn();registerManagedAi(app,loadConfig({deepseek:{apiKey:''},aliyun:{apiKey:''}}),upstream);
 try{const response=await app.inject({method:'POST',url:'/api/ai/test'});expect(response.statusCode).toBe(200);const body=response.json();expect(body.ok).toBe(false);expect(body.roles).toHaveLength(3);expect(body.roles.every((role:any)=>!role.ok&&role.message.includes('API Key'))).toBe(true);expect(upstream).not.toHaveBeenCalled();}finally{await app.close();}
});

it('上游错误会逐角色返回但不会回显密钥，未知模型在调用上游前被拒绝',async()=>{
 const app=Fastify();registerManagedAi(app,configured(),async()=>new Response('upstream denied secret',{status:401}));
 try{const response=await app.inject({method:'POST',url:'/api/ai/test'});expect(response.statusCode).toBe(200);expect(response.body).not.toContain('server-secret');expect(response.body).not.toContain('aliyun-secret');expect(response.body).toContain('401');}finally{await app.close();}
 const app2=Fastify();const upstream=vi.fn();registerManagedAi(app2,configured(),upstream as any);
 try{expect((await app2.inject({method:'POST',url:'/v1/chat/completions',payload:{model:'unknown',messages:[]}})).statusCode).toBe(400);expect(upstream).not.toHaveBeenCalled();}finally{await app2.close();}
});
