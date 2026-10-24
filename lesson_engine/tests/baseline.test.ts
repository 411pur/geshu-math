import { readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';

async function readText(path: string) {
  return readFile(new URL(path, import.meta.url), 'utf8');
}

describe('embedded lesson engine baseline', () => {
  it('keeps the teacher board template structurally valid', async () => {
    const html = await readText('../templates/teacher-board.html');
    expect(html.trim().endsWith('</html>')).toBe(true);
    expect(html).toContain('id="blackboard"');
    expect(html).toContain('__LESSON_JSON__');
  });

  it('keeps browser speech and navigation runtime available', async () => {
    const renderer = await readText('../src/render/client-renderer.js');
    expect(renderer).toContain('speechSynthesis');
    expect(renderer).toContain('window.__LESSON_READY__');
    expect(renderer).toContain('topNextButton');
  });
});
