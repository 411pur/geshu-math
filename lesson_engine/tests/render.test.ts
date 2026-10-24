import { describe, expect, it } from 'vitest';
import { LocalHtmlRenderer } from '../src/render/render-lesson.js';
import { createPlan } from './helpers/lesson-fixtures.js';

describe('LocalHtmlRenderer', () => {
  it('builds a self-contained interactive HTML file', async () => {
    const plan = createPlan({ title: '测试讲解 <安全>' });
    const html = await new LocalHtmlRenderer().render(plan);

    expect(html).toContain('测试讲解 &lt;安全&gt;');
    expect(html).toContain('window.__LESSON_READY__ = true');
    expect(html).toContain('1 + 1 = ?');
    expect(html).not.toContain('__LESSON_JSON__');
    expect(html).not.toContain('__CLIENT_RENDERER__');
    expect(html).not.toMatch(/<(?:script|link)[^>]+(?:src|href)=["']https?:/i);
    expect(html).toContain('data:font/woff2;base64,');
    expect(html).toContain('class="derivation-column"');
    expect(html).toContain('id="formulaStage"');
    expect(html.indexOf('id="formulaStage"')).toBeLessThan(html.indexOf('id="teacherConsole"'));
    expect(html).not.toContain('__KATEX_');
    expect(html.trim().endsWith('</html>')).toBe(true);
  });

  it('escapes a script-closing sequence in lesson data', async () => {
    const plan = createPlan({ title: '安全测试' });
    plan.problem.stem = '</script><script>alert(1)</script>';
    const html = await new LocalHtmlRenderer().render(plan);
    expect(html).not.toContain('</script><script>alert(1)</script>');
    expect(html).toContain('\\u003c/script\\u003e');
  });
});
