import { describe, expect, it } from 'vitest';
import { checkAnalysisPhysics } from '../../src/visual/physics-check.js';
import { createPlan, createProblem } from '../helpers/lesson-fixtures.js';

/** 30° 斜面：B(200,460) → A(760,140)，物块作用点取斜面中点 (480,300)。 */
function inclinePlan() {
  const plan = createPlan();
  plan.diagram.baseElements = [
    { type: 'line', id: 'slope_AB', x1: 200, y1: 460, x2: 760, y2: 140, color: 'chalk', dashed: false, width: 3 }
  ];
  plan.scenes[0].diagramElements = [];
  return plan;
}

describe('analysis physics check', () => {
  it('水平面上的支持力垂直于地面时通过', () => {
    const plan = createPlan();
    plan.diagram.baseElements = [
      { type: 'line', id: 'ground', x1: 140, y1: 420, x2: 680, y2: 420, color: 'chalk', dashed: false, width: 3 }
    ];
    plan.scenes[0].diagramElements = [
      { type: 'arrow', id: 'vec-N', dashed: false, x1: 360, y1: 360, x2: 360, y2: 280, color: 'green', label: 'N' },
      { type: 'arrow', id: 'vec-G', dashed: false, x1: 360, y1: 360, x2: 360, y2: 440, color: 'pink', label: 'mg' }
    ];
    expect(checkAnalysisPhysics(plan)).toEqual([]);
  });

  it('支持力画成水平（不垂直于地面）时报错', () => {
    const plan = createPlan();
    plan.diagram.baseElements = [
      { type: 'line', id: 'ground', x1: 140, y1: 420, x2: 680, y2: 420, color: 'chalk', dashed: false, width: 3 }
    ];
    plan.scenes[0].diagramElements = [
      { type: 'arrow', id: 'vec-N', dashed: false, x1: 360, y1: 360, x2: 470, y2: 360, color: 'green', label: 'N' }
    ];
    const issues = checkAnalysisPhysics(plan);
    expect(issues).toHaveLength(1);
    expect(issues[0].message).toContain('支持力应垂直于接触面');
  });

  it('重力不竖直向下时报错', () => {
    const plan = createPlan();
    plan.diagram.baseElements = [
      { type: 'line', id: 'ground', x1: 140, y1: 420, x2: 680, y2: 420, color: 'chalk', dashed: false, width: 3 }
    ];
    plan.scenes[0].diagramElements = [
      { type: 'arrow', id: 'vec-G', dashed: false, x1: 360, y1: 320, x2: 430, y2: 390, color: 'pink', label: 'mg' }
    ];
    expect(checkAnalysisPhysics(plan).map((issue) => issue.message).join('；')).toContain('重力方向应为竖直向下');
  });

  it('斜面上的支持力垂直于斜面时通过', () => {
    const plan = inclinePlan();
    plan.scenes[0].diagramElements = [
      { type: 'arrow', id: 'vec-N', dashed: false, x1: 480, y1: 300, x2: 430, y2: 213, color: 'green', label: 'N' }
    ];
    expect(checkAnalysisPhysics(plan)).toEqual([]);
  });

  it('斜面上支持力沿斜面画时报错', () => {
    const plan = inclinePlan();
    plan.scenes[0].diagramElements = [
      { type: 'arrow', id: 'vec-N', dashed: false, x1: 480, y1: 300, x2: 536, y2: 268, color: 'green', label: 'N' }
    ];
    expect(checkAnalysisPhysics(plan).map((issue) => issue.message).join('；')).toContain('支持力应垂直于接触面');
  });

  it('摩擦力沿斜面时通过，垂直于斜面时报错', () => {
    const ok = inclinePlan();
    ok.scenes[0].diagramElements = [
      { type: 'arrow', id: 'vec-f', dashed: false, x1: 480, y1: 300, x2: 536, y2: 268, color: 'yellow', label: 'f' }
    ];
    expect(checkAnalysisPhysics(ok)).toEqual([]);

    const bad = inclinePlan();
    bad.scenes[0].diagramElements = [
      { type: 'arrow', id: 'vec-f', dashed: false, x1: 480, y1: 300, x2: 430, y2: 213, color: 'yellow', label: 'f' }
    ];
    expect(checkAnalysisPhysics(bad).map((issue) => issue.message).join('；')).toContain('摩擦力应沿接触面');
  });

  it('大写 F（外加力）不会被误判成摩擦力 f', () => {
    const plan = createPlan();
    plan.diagram.baseElements = [
      { type: 'line', id: 'ground', x1: 140, y1: 420, x2: 680, y2: 420, color: 'chalk', dashed: false, width: 3 }
    ];
    plan.scenes[0].diagramElements = [
      { type: 'arrow', id: 'vec-F', dashed: false, x1: 360, y1: 380, x2: 460, y2: 380, color: 'pink', label: 'F' }
    ];
    const smooth = createProblem({ subject: '物理', stem: '光滑水平面上物块受水平拉力 F', diagramMode: 'svg' });
    expect(checkAnalysisPhysics(plan, smooth)).toEqual([]);
  });

  it('题干说明接触面光滑时，画了摩擦力要报错', () => {
    const plan = createPlan();
    plan.diagram.baseElements = [
      { type: 'line', id: 'ground', x1: 140, y1: 420, x2: 680, y2: 420, color: 'chalk', dashed: false, width: 3 }
    ];
    plan.scenes[0].diagramElements = [
      { type: 'arrow', id: 'vec-f', dashed: false, x1: 360, y1: 380, x2: 300, y2: 380, color: 'yellow', label: 'f' }
    ];
    const smooth = createProblem({ subject: '物理', stem: '物块在光滑水平面上向右滑动', diagramMode: 'svg' });
    expect(checkAnalysisPhysics(plan, smooth).map((issue) => issue.message).join('；')).toContain('不应有摩擦力');

    const rough = createProblem({ subject: '物理', stem: '物块在粗糙水平面上向右滑动', diagramMode: 'svg' });
    expect(checkAnalysisPhysics(plan, rough)).toEqual([]);
  });

  it('同一物体的受力起点明显分散时给出提示', () => {
    const plan = createPlan();
    plan.diagram.baseElements = [
      { type: 'line', id: 'ground', x1: 140, y1: 420, x2: 680, y2: 420, color: 'chalk', dashed: false, width: 3 }
    ];
    plan.scenes[0].diagramElements = [
      { type: 'arrow', id: 'vec-G', dashed: false, x1: 360, y1: 340, x2: 360, y2: 420, color: 'pink', label: 'mg' },
      { type: 'arrow', id: 'vec-N', dashed: false, x1: 360, y1: 420, x2: 360, y2: 340, color: 'green', label: 'N' }
    ];
    expect(checkAnalysisPhysics(plan).map((issue) => issue.message).join('；')).toContain('受力矢量起点不一致');
  });

  it('重力分力（mg sinθ / mg cosθ）不参与重力方向判定', () => {
    const plan = inclinePlan();
    plan.scenes[0].diagramElements = [
      { type: 'arrow', id: 'vec-mg-sin', dashed: false, x1: 480, y1: 300, x2: 536, y2: 268, color: 'cyan', label: 'mg sinθ' },
      { type: 'arrow', id: 'vec-mg-cos', dashed: false, x1: 480, y1: 300, x2: 430, y2: 213, color: 'cyan', label: 'mg cosθ' }
    ];
    expect(checkAnalysisPhysics(plan)).toEqual([]);
  });
});
