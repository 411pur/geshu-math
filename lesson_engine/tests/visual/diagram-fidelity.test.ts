import { describe, expect, it } from 'vitest';
import { auditDiagramFidelity, demoteMisplacedBaseLayer, looksLikeAnalysisVector } from '../../src/visual/diagram-fidelity.js';
import { createPlan, createProblem } from '../helpers/lesson-fixtures.js';

describe('diagram fidelity guard', () => {
  it('把混进原图层的分析矢量退回讲解步骤', () => {
    const plan = createPlan();
    plan.scenes[0].activeElementIds = ['weight-force'];
    plan.diagram.baseElements = [
      { type: 'rect', id: 'block', x: 400, y: 240, width: 120, height: 90, color: 'cyan', radius: 8, layer: 'base' },
      { type: 'arrow', id: 'weight-force', x1: 460, y1: 330, x2: 460, y2: 410, color: 'pink', dashed: false, label: 'mg', layer: 'base' }
    ];
    const guarded = demoteMisplacedBaseLayer(plan, createProblem({ subject: '物理', stem: '物块沿斜面下滑，画出受力', diagramMode: 'svg' }));
    expect(guarded.diagram.baseElements.map((element) => element.id)).toEqual(['block']);
    expect(guarded.scenes[0].diagramElements.some((element) => element.id === 'weight-force')).toBe(true);
  });

  it('题意判断不需要示意图时不保留任何底座', () => {
    const plan = createPlan();
    plan.diagram.baseElements = [{ type: 'rect', id: 'invented', x: 10, y: 10, width: 50, height: 50, color: 'cyan', radius: 4 }];
    const guarded = demoteMisplacedBaseLayer(plan, createProblem({ subject: '数学', stem: '计算 12 × 7', diagramMode: 'none' }));
    expect(guarded.diagram.baseElements).toEqual([]);
  });

  it('识别常见的分析矢量标签', () => {
    expect(looksLikeAnalysisVector({ type: 'arrow', id: 'a', x1: 0, y1: 0, x2: 1, y2: 1, color: 'pink', dashed: false, label: 'mg' })).toBe(true);
    expect(looksLikeAnalysisVector({ type: 'arrow', id: 'b', x1: 0, y1: 0, x2: 1, y2: 1, color: 'pink', dashed: false, label: 'AB' })).toBe(false);
  });

  it('分析矢量起点脱离原图对象时给出忠实度警告', () => {
    const plan = createPlan();
    plan.diagram.baseElements = [{ type: 'point', id: 'ball', x: 200, y: 200, radius: 8, color: 'cyan' }];
    plan.scenes[1].diagramElements = [{ type: 'arrow', id: 'analysis-a', x1: 800, y1: 500, x2: 860, y2: 540, color: 'pink', dashed: false, label: 'a' }];
    const issues = auditDiagramFidelity(plan, createProblem({ subject: '物理', stem: '小球运动，求加速度', diagramMode: 'svg' }));
    expect(issues.length).toBeGreaterThan(0);
  });

  it('分析矢量起点落在原图对象附近时不报警', () => {
    const plan = createPlan();
    plan.diagram.baseElements = [{ type: 'point', id: 'ball', x: 200, y: 200, radius: 8, color: 'cyan' }];
    plan.scenes[1].diagramElements = [{ type: 'arrow', id: 'analysis-N', x1: 205, y1: 195, x2: 205, y2: 120, color: 'green', dashed: false, label: 'N' }];
    const issues = auditDiagramFidelity(plan, createProblem({ subject: '物理', stem: '小球受力分析', diagramMode: 'svg' }));
    expect(issues).toEqual([]);
  });
});
