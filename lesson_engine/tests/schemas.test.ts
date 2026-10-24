import { describe, expect, it } from 'vitest';
import { LessonPlanSchema, ProblemExtractSchema } from '../src/schemas/lesson.js';
import { ProjectRecordSchema } from '../src/schemas/project.js';

describe('lesson schemas', () => {
  it('accepts a minimal lesson plan with a generated SVG scene', () => {
    const result = LessonPlanSchema.safeParse({
      title: '测试讲题',
      subject: '物理',
      problem: { stem: '测试题目', options: [{ key: 'A', text: '正确' }], correctOptions: ['A'] },
      diagram: { mode: 'svg', viewBox: [960, 580], baseElements: [] },
      scenes: [
        { type: 'question', title: '读题', narration: '先读题。' },
        { type: 'formula', title: '分析', narration: '开始分析。', formulaLines: [{ segments: [{ type: 'text', value: 'E = 1' }] }] },
        {
          type: 'diagram', title: '画图', narration: '画出图形。',
          diagramElements: [{ type: 'point', id: 'p1', x: 100, y: 100, color: 'cyan' }]
        },
        { type: 'answer', title: '答案', narration: '答案正确。', revealAnswer: true }
      ]
    });
    expect(result.success).toBe(true);
  });

  it('keeps source text as data rather than executable markup', () => {
    const result = ProblemExtractSchema.safeParse({ stem: '<script>alert(1)</script>' });
    expect(result.success).toBe(true);
    expect(result.data?.stem).toContain('<script>');
  });

  it('validates persisted project records', () => {
    const result = ProjectRecordSchema.safeParse({
      id: '0199e80c-11c2-7c4d-9f9d-48caf19f5f0e',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      status: 'done',
      stage: 'done',
      progress: 100,
      title: '示例题',
      subject: '数学',
      input: { text: '1 + 1 = ?' }
    });
    expect(result.success).toBe(true);
  });
});
