import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {validateConfig,publicConfig} from './stack-config.mjs';
const sample=JSON.parse(readFileSync(new URL('../local.config.example.json',import.meta.url)));
test('public configuration never includes secrets or upstream credentials',()=>{
 const config=validateConfig({...sample,apiKey:'private-secret'},process.cwd());
 const serialized=JSON.stringify(publicConfig(config));
 assert.ok(!serialized.includes('private-secret'));assert.ok(!serialized.includes('api.deepseek.com'));assert.equal(publicConfig(config).managedAi,true);
});
test('invalid ports, external data directories and public data directories fail early',()=>{
 for(const patch of [{port:0},{port:1.5},{host:'0.0.0.0'},{dataDir:'../outside'},{dataDir:'web/secrets'},{model:''},{requestTimeoutMs:-1}]) {
 assert.throws(()=>validateConfig({...sample,...patch},process.cwd()));
 }
});
