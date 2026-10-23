import { describe, expect, it } from 'vitest';
import { applyLessonPlanRepair, filterApplicableRepairOperations } from '../../src/visual/repair.js';
import { LessonPlanRepairSchema } from '../../src/schemas/visual.js';
import { createPlan } from '../helpers/lesson-fixtures.js';

describe('lesson plan repairs', () => {
  it('moves a diagram element and updates its focus', () => {
    const plan = createPlan();
    const repair = LessonPlanRepairSchema.parse({
      summary: '移动重叠标签',
      operations: [
        { kind: 'move_element', sceneIndex: 2, elementId: 'p1', dx: 30, dy: -20, reason: '避免标签重叠' },
        { kind: 'set_focus', sceneIndex: 2, x: 300, y: 220, reason: '移动老师指点位置' }
      ]
    });

    const result = applyLessonPlanRepair(plan, repair);
    const point = result.plan.scenes[2].diagramElements.find((element) => element.id === 'p1');
    expect(point).toMatchObject({ x: 430, y: 260 });
    expect(result.plan.scenes[2].focus).toEqual({ x: 300, y: 220 });
    expect(result.contentChanged).toBe(false);
  });

  it('shortens narration and marks content as changed', () => {
    const repair = LessonPlanRepairSchema.parse({
      summary: '精简讲解',
      operations: [{ kind: 'shorten_narration', sceneIndex: 1, narration: '我们直接写出算式。', reason: '文字过长' }]
    });
    const result = applyLessonPlanRepair(createPlan(), repair);
    expect(result.plan.scenes[1].narration).toBe('我们直接写出算式。');
    expect(result.contentChanged).toBe(true);
  });

  it('rejects repairs that reference missing elements', () => {
    const repair = LessonPlanRepairSchema.parse({
      summary: '错误修复',
      operations: [{ kind: 'delete_element', sceneIndex: 2, elementId: 'missing', reason: '测试错误' }]
    });
    expect(() => applyLessonPlanRepair(createPlan(), repair)).toThrow('不存在的图元');
  });
  it('filters repairs that reference missing elements while keeping valid operations', () => {
    const repair = LessonPlanRepairSchema.parse({
      summary: '混合修复',
      operations: [
        { kind: 'set_focus', sceneIndex: 0, x: 300, y: 200, reason: '有效' },
        { kind: 'delete_element', sceneIndex: 2, elementId: 'missing', reason: '无效' }
      ]
    });
    const filtered = filterApplicableRepairOperations(createPlan(), repair);
    expect(filtered.repair.operations).toHaveLength(1);
    expect(filtered.skipped).toEqual(['delete_element:missing']);
  });

});
