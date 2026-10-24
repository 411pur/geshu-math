import { readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';

describe('beginner connection guidance', () => {
  it('shows a helpful message when the local server is unavailable', async () => {
    const app = await readFile(new URL('../public/app.js', import.meta.url), 'utf8');
    expect(app).toContain('无法连接本地服务');
    expect(app).toContain('npm start');
  });

  it('documents how to recover from Failed to fetch', async () => {
    const readme = await readFile(new URL('../README.md', import.meta.url), 'utf8');
    expect(readme).toContain('Failed to fetch');
    expect(readme).toContain('npm start');
  });
});
