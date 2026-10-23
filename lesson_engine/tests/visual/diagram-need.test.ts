import { describe, expect, it } from 'vitest';
import { decideDiagramNeed } from '../../src/visual/diagram-need.js';
import { createHexagonBlueprint, createProblem } from '../helpers/lesson-fixtures.js';

describe('decideDiagramNeed', () => {
  it('asks for a diagram on a physics force problem even without an explicit figure', () => {
    const decision = decideDiagramNeed(createProblem({
      subject: '物理',
      stem: '物块放在斜面上，画出它受到的力并求加速度',
      diagramMode: 'none'
    }));
    expect(decision.needed).toBe(true);
  });

  it('skips the diagram for a pure arithmetic problem', () => {
    const decision = decideDiagramNeed(createProblem({ subject: '数学', stem: '计算 12 × 7 的值', diagramMode: 'none' }));
    expect(decision.needed).toBe(false);
  });

  it('asks for a diagram when the problem ships reconstructable geometry', () => {
    const decision = decideDiagramNeed(createProblem({
      subject: '物理',
      stem: '正六棱柱置于匀强电场中',
      diagramMode: 'image',
      diagramBlueprint: createHexagonBlueprint()
    }));
    expect(decision.needed).toBe(true);
    expect(decision.reason).toContain('图形');
  });

  it('asks for a diagram on geometry problems', () => {
    const decision = decideDiagramNeed(createProblem({ subject: '数学', stem: '在三角形 ABC 中，AB 边上的高为 3', diagramMode: 'none' }));
    expect(decision.needed).toBe(true);
  });
});
