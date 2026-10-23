import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { ProjectStore } from '../src/store/project-store.js';

const tempDirs: string[] = [];
afterEach(async () => Promise.all(tempDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true }))));
async function createStore() {
  const root = await mkdtemp(path.join(os.tmpdir(), 'lesson-store-'));
  tempDirs.push(root);
  const store = new ProjectStore(root);
  await store.init();
  return store;
}

describe('ProjectStore', () => {
  it('stores artifacts in nested safe paths', async () => {
    const store = await createStore();
    const project = await store.create({ text: 'test' });
    await store.writeArtifactJson(project.id, 'visual/iteration-0/report.json', { ok: true });
    expect(await store.readArtifactJson(project.id, 'visual/iteration-0/report.json')).toEqual({ ok: true });
    expect(await store.artifactExists(project.id, 'visual/iteration-0/report.json')).toBe(true);
    expect(() => store.artifactPath(project.id, '../escape.txt')).toThrow();
  });

  it('creates, updates, lists and resets projects', async () => {
    const store = await createStore();
    const created = await store.create({ text: '1 + 1 = ?' });
    await store.writeHtml(created.id, '<html>ok</html>');
    const updated = await store.update(created.id, { title: '加法', status: 'done', stage: 'done', progress: 100, visualStatus: 'passed' });
    expect(updated.title).toBe('加法');
    expect(await store.list()).toHaveLength(1);
    const reset = await store.reset(created.id);
    expect(reset.visualStatus).toBe('not_checked');
    await expect(store.readHtml(created.id)).rejects.toThrow();
  });
});
