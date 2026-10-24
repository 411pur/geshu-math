import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {existsSync,readFileSync,writeFileSync,copyFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateConfig,publicConfig} from './stack-config.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const engine = path.join(root,'lesson_engine');
const localFile = path.join(root,'local.config.json');
if (!existsSync(localFile)) copyFileSync(path.join(root,'local.config.example.json'),localFile);
if (!existsSync(path.join(root,'.env.local'))) copyFileSync(path.join(root,'.env.example'),path.join(root,'.env.local'));
const config = validateConfig(JSON.parse(readFileSync(localFile,'utf8').replace(/^\uFEFF/,'')),root);
const origin = `http://${config.host}:${config.port}`;
async function run(command,args,cwd=root) {
  return new Promise((resolve,reject) => {
    const child=spawn(command,args,{cwd,stdio:'inherit',shell:process.platform==='win32',windowsHide:true});
    child.on('error',reject); child.on('exit',code=>code===0?resolve():reject(new Error(`${command} 失败：${code}`)));
  });
}
try {
  let existing;
  try {existing=await (await fetch(`${origin}/api/health`,{signal:AbortSignal.timeout(1500)})).json();} catch {}
  if(existing) {
    if(existing.service !== 'geshu-math' || existing.instance !== root) throw new Error('端口已被其他服务占用，请修改 local.config.json');
    console.log(`项目已运行：${origin}。修改服务端配置后，请先在原启动窗口 Ctrl+C，再重新启动。`);
    process.exit(0);
  }
  const fingerprint=createHash('sha256').update(readFileSync(path.join(engine,'package-lock.json'))).digest('hex');
  const stamp=path.join(engine,'node_modules','.geshu-lock');
  if(!existsSync(stamp) || readFileSync(stamp,'utf8')!==fingerprint) {
    await run('npm',['ci','--no-audit','--no-fund'],engine);
    writeFileSync(stamp,fingerprint);
  }
  const dotenv = createRequire(path.join(engine,'package.json'))('dotenv');
  dotenv.config({path:path.join(root,'.env.local'),quiet:true,override:true});
  if(config.buildWeb) {
    await run('flutter',['pub','get']);
    await run('flutter',['build','web','--release','--no-web-resources-cdn','--no-pub']);
  }
  if(!existsSync(path.join(root,'build/web/index.html'))) throw new Error('缺少 Web 构建，请设置 buildWeb=true');
  writeFileSync(path.join(root,'build/web/config.json'),JSON.stringify(publicConfig(config),null,2));
  const env={...process.env,HOST:config.host,PORT:String(config.port),PUBLIC_DIR:path.join(root,'build/web'),DATA_DIR:config.dataDir,
    GESHU_INSTANCE:root,DEEPSEEK_BASE_URL:config.apiBaseUrl,DEEPSEEK_FAST_MODEL:config.model,DEEPSEEK_VISION_MODEL:config.visionModel,
    DEEPSEEK_REASONING_MODEL:config.reasoningModel,MODEL_PROVIDER_FAST:config.fastProvider,
    MODEL_PROVIDER_REASONING:config.reasoningProvider,MODEL_PROVIDER_VISION:config.visionProvider,
    ALIYUN_API_KEY:process.env.ALIYUN_API_KEY || '',ALIYUN_API_FLAVOR:process.env.ALIYUN_API_FLAVOR || 'openai',
    ALIYUN_WORKSPACE_ID:process.env.ALIYUN_WORKSPACE_ID || '',ALIYUN_REGION:process.env.ALIYUN_REGION || 'cn-beijing',
    ALIYUN_BASE_URL:process.env.ALIYUN_BASE_URL || '',ALIYUN_MODEL:process.env.ALIYUN_MODEL || 'qwen-plus',
    ALIYUN_VISION_FAST_MODEL:process.env.ALIYUN_VISION_FAST_MODEL || 'qwen3-vl-flash',
    ALIYUN_VISION_MODEL:process.env.ALIYUN_VISION_MODEL || 'qwen3-vl-plus',
    ALIYUN_VISION_MODEL_FALLBACKS:process.env.ALIYUN_VISION_MODEL_FALLBACKS || 'qwen-vl-max,qwen3-vl-max',
    ALIYUN_ENABLE_VISUAL_CRITIC:process.env.ALIYUN_ENABLE_VISUAL_CRITIC || '0',
    MAX_IMAGE_BYTES:String(config.maxImageBytes),MAX_DOCUMENT_BYTES:String(config.maxDocumentBytes),
    CORS_ALLOWED_ORIGINS:origin};
  const child=spawn(process.execPath,['--import','tsx','src/server.ts'],{cwd:engine,env,stdio:'inherit',windowsHide:true});
  child.on('error',error=>{console.error(error.message);process.exitCode=1;});
  child.on('exit',code=>{process.exitCode=code ?? 1;});
  process.on('SIGINT',()=>child.kill('SIGINT'));
  process.on('SIGTERM',()=>child.kill('SIGTERM'));
  let ready=false;
  for(let i=0;i<40 && child.exitCode===null;i++) {
    try {const health=await (await fetch(`${origin}/api/health`,{signal:AbortSignal.timeout(1000)})).json();if(health.service==='geshu-math' && health.instance===root){ready=true;break;}} catch {}
    await new Promise(resolve=>setTimeout(resolve,250));
  }
  if(!ready) {child.kill();throw new Error('服务启动失败，请查看上方错误；不会停止其他项目的进程');}
  console.log(`格数至理已启动：${origin}（Ctrl+C 停止本次启动的服务）`);
} catch(error) {console.error(error.message);process.exitCode=1;}
