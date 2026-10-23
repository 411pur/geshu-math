import {it,expect,vi} from 'vitest';
import Fastify from 'fastify';
import {registerManagedAi} from '../src/managed-ai.js';
import {loadConfig} from '../src/config.js';

it('服务器密钥替换浏览器密钥，流式内容原样返回',async()=>{
 const app=Fastify();const upstream=vi.fn(async()=>new Response('data: {"ok":true}\n\ndata: [DONE]\n\n',{headers:{'content-type':'text/event-stream'}}));
 registerManagedAi(app,loadConfig({deepseek:{apiKey:'server-secret',fastModel:'test'}}),upstream as any);
 try{const response=await app.inject({method:'POST',url:'/v1/chat/completions',headers:{authorization:'Bearer browser-secret'},payload:{model:'test',messages:[],stream:true}});
 expect(response.statusCode).toBe(200);expect(response.body).toContain('[DONE]');expect(JSON.stringify(upstream.mock.calls)).not.toContain('browser-secret');
 expect((upstream.mock.calls as any)[0][1].headers.Authorization).toBe('Bearer server-secret');}finally{await app.close();}
});
it('缺密钥和不允许的模型在调用上游前报错',async()=>{
 const app=Fastify();const upstream=vi.fn();registerManagedAi(app,loadConfig({deepseek:{apiKey:''}}),upstream);
 try{expect((await app.inject({method:'POST',url:'/api/ai/test'})).statusCode).toBe(503);expect(upstream).not.toHaveBeenCalled();}finally{await app.close();}
 const app2=Fastify();registerManagedAi(app2,loadConfig({deepseek:{apiKey:'secret'}}),upstream);
 try{expect((await app2.inject({method:'POST',url:'/v1/chat/completions',payload:{model:'unknown',messages:[]}})).statusCode).toBe(400);}finally{await app2.close();}
});
it('上游错误内容不会回显密钥',async()=>{
 const app=Fastify();registerManagedAi(app,loadConfig({deepseek:{apiKey:'secret'}}),async()=>new Response('secret',{status:401}));
 try{const response=await app.inject({method:'POST',url:'/api/ai/test'});expect(response.statusCode).toBe(502);expect(response.body).not.toContain('secret');expect(response.body).toContain('401');}finally{await app.close();}
});
