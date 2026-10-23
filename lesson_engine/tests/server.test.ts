import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import FormData from 'form-data';
import { afterEach, describe, expect, it } from 'vitest';
import { buildServer } from '../src/server.js';
import { ProjectStore } from '../src/store/project-store.js';
import { loadConfig, type AppConfig } from '../src/config.js';
import { createPlan } from './helpers/lesson-fixtures.js';
import type { LessonPipeline } from '../src/pipeline/lesson-pipeline.js';

const tempDirs: string[] = [];
const apps: Array<Awaited<ReturnType<typeof buildServer>>> = [];

afterEach(async () => {
  await Promise.all(apps.splice(0).map((app) => app.close()));
  await Promise.all(tempDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});

async function createTestServer() {
  const root = await mkdtemp(path.join(os.tmpdir(), 'lesson-server-'));
  tempDirs.push(root);
  const store = new ProjectStore(path.join(root, 'projects'));
  await store.init();
  const config: AppConfig = loadConfig({
    dataDir: path.join(root, 'projects'),
    publicDir: path.join(process.cwd(), 'public'),
    templatePath: path.join(process.cwd(), 'templates', 'teacher-board.html'),
    deepseek: { apiKey: '', baseUrl: 'https://example.test', reasoningModel: 'reason', fastModel: 'fast' },
    aliyun: { apiKey: '', baseUrl: 'https://example.test', workspaceId: '', region: 'cn-beijing', visionModel: 'vision', visionModelFallbacks: [] }
  });
  const pipeline = {
    async run(projectId: string, onProgress: (event: unknown) => Promise<void>) {
      await onProgress({ stage: 'extracting', progress: 10, message: '读题' });
      await onProgress({ stage: 'solving', progress: 40, message: '求解' });
      await onProgress({ stage: 'rendering', progress: 90, message: '渲染' });
      await store.writeJson(projectId, 'lesson.json', createPlan());
      await store.writeHtml(projectId, '<html><body>generated lesson</body></html>');
      return { plan: createPlan(), html: '<html></html>' };
    }
  } as unknown as LessonPipeline;
  const app = await buildServer({ config, store, pipeline });
  apps.push(app);
  return { app, store };
}

async function waitForDone(app: Awaited<ReturnType<typeof buildServer>>, id: string) {
  for (let attempt = 0; attempt < 750; attempt += 1) {
    const response = await app.inject({ method: 'GET', url: `/api/projects/${id}` });
    const payload = response.json();
    if (payload.project.status === 'done') return payload.project;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error('project did not finish');
}

describe('HTTP API', () => {
  it('serves the local management interface', async () => {
    const { app } = await createTestServer();
    const response = await app.inject({ method: 'GET', url: '/' });
    expect(response.statusCode).toBe(200);
    expect(response.body).toContain('老师讲题 HTML 生成器');
  });

  it('creates a text project, generates HTML and exposes history', async () => {
    const { app } = await createTestServer();
    const response = await app.inject({ method: 'POST', url: '/api/projects', payload: { text: '1 + 1 = ?' } });
    expect(response.statusCode).toBe(202);
    const { id } = response.json();
    await waitForDone(app, id);

    const history = await app.inject({ method: 'GET', url: '/api/projects' });
    expect(history.json().projects).toHaveLength(1);
    const preview = await app.inject({ method: 'GET', url: `/api/projects/${id}/html` });
    expect(preview.body).toContain('generated lesson');
    const download = await app.inject({ method: 'GET', url: `/api/projects/${id}/download` });
    expect(download.headers['content-disposition']).toContain('attachment');
  });

  it('accepts an uploaded image through multipart', async () => {
    const { app, store } = await createTestServer();
    const form = new FormData();
    form.append('text', '图片补充文字');
    form.append('image', Buffer.from('fake-image'), { filename: 'question.png', contentType: 'image/png' });
    const response = await app.inject({ method: 'POST', url: '/api/projects', payload: form, headers: form.getHeaders() });
    expect(response.statusCode).toBe(202);
    const id = response.json().id;
    await waitForDone(app, id);
    const record = await store.get(id);
    expect(record.input.imageMimeType).toBe('image/png');
  });

  it('rejects unsupported files and empty projects', async () => {
    const { app } = await createTestServer();
    const empty = await app.inject({ method: 'POST', url: '/api/projects', payload: {} });
    expect(empty.statusCode).toBe(400);

    const form = new FormData();
    form.append('file', Buffer.from('text'), { filename: 'x.txt', contentType: 'text/plain' });
    const invalid = await app.inject({ method: 'POST', url: '/api/projects', payload: form, headers: form.getHeaders() });
    expect(invalid.statusCode).toBe(400);
  });

  it('reports provider configuration without exposing keys', async () => {
    const { app } = await createTestServer();
    const response = await app.inject({ method: 'GET', url: '/api/health' });
    expect(response.json()).toMatchObject({ ok: true, providers: { deepseek: false, aliyun: false } });
    expect(response.body).not.toContain('apiKey');
  });
  it('allows browser bridge CORS preflight only from local app origins', async () => {
    const { app } = await createTestServer();
    const response = await app.inject({
      method: 'OPTIONS',
      url: '/api/projects',
      headers: {
        origin: 'http://127.0.0.1:5070',
        'access-control-request-method': 'POST',
        'access-control-request-headers': 'content-type',
        'access-control-request-private-network': 'true'
      }
    });
    expect(response.statusCode).toBe(204);
    expect(response.headers['access-control-allow-origin']).toBe('http://127.0.0.1:5070');
    expect(response.headers['access-control-allow-private-network']).toBe('true');

    const denied = await app.inject({
      method: 'OPTIONS',
      url: '/api/projects',
      headers: {
        origin: 'http://127.0.0.1:9999',
        'access-control-request-method': 'POST'
      }
    });
    expect(denied.statusCode).toBe(403);
  });
  it('serves visual reports and screenshots', async () => {
    const { app, store } = await createTestServer();
    const response = await app.inject({ method: 'POST', url: '/api/projects', payload: { text: '视觉测试' } });
    const { id } = response.json();
    await waitForDone(app, id);
    await store.writeArtifactJson(id, 'visual/iteration-0/report.json', { iteration: 0, score: 100, passed: true, issues: [], screenshots: [{ sceneIndex: 0, file: 'scene-0.png' }], metricsVersion: '1.0' });
    await store.writeArtifactBinary(id, 'visual/iteration-0/scene-0.png', Buffer.from('89504e470d0a1a0a', 'hex'));
    await store.update(id, { visualStatus: 'passed', renderAttempts: 1 });
    const report = await app.inject({ method: 'GET', url: `/api/projects/${id}/visual` });
    expect(report.statusCode).toBe(200);
    expect(report.json().reports).toHaveLength(1);
    const image = await app.inject({ method: 'GET', url: `/api/projects/${id}/visual/0/0` });
    expect(image.statusCode).toBe(200);
    expect(image.headers['content-type']).toContain('image/png');
  });
    it('extracts question text from an uploaded document', async () => {
      const { app } = await createTestServer();

      const ok = new FormData();
      ok.append('file', Buffer.from('题目：1 + 1 = ?', 'utf8'), { filename: 'question.txt', contentType: 'text/plain' });
      const extracted = await app.inject({ method: 'POST', url: '/api/extract-text', payload: ok, headers: ok.getHeaders() });
      expect(extracted.statusCode).toBe(200);
      expect(extracted.json()).toMatchObject({ kind: 'text', text: '题目：1 + 1 = ?' });

      const unsupported = new FormData();
      unsupported.append('file', Buffer.from('image'), { filename: 'question.jpg', contentType: 'image/jpeg' });
      const rejected = await app.inject({ method: 'POST', url: '/api/extract-text', payload: unsupported, headers: unsupported.getHeaders() });
      expect(rejected.statusCode).toBe(400);
      expect(rejected.json().error).toBe('unsupported_document');

      const blank = new FormData();
      blank.append('file', Buffer.from('   \n  ', 'utf8'), { filename: 'blank.txt', contentType: 'text/plain' });
      const empty = await app.inject({ method: 'POST', url: '/api/extract-text', payload: blank, headers: blank.getHeaders() });
      expect(empty.statusCode).toBe(422);
      expect(empty.json().error).toBe('empty_document');
    });

});
