import { describe, expect, it } from 'vitest';
import { validateDiagramPlan } from '../../src/visual/diagram-validation.js';
import { applyDiagramBlueprintToPlan } from '../../src/visual/diagram-redraw.js';
import { createEmptyBlueprint, createPlan, createProblem, createSolution } from '../helpers/lesson-fixtures.js';

const problem = createProblem({ subject: '物理', stem: '斜面上物块', diagramMode: 'image', diagramBlueprint: createEmptyBlueprint() });

describe('diagram validation (template-independent)', () => {
  it('对正常重绘结果不报问题', () => {
    const basePlan = createPlan();
    basePlan.diagram.baseElements = [];
    basePlan.scenes[0].diagramElements = [{ type: 'polygon', id: 'ramp', layer: 'base', points: [{ x: 100, y: 300 }, { x: 500, y: 300 }, { x: 500, y: 120 }], color: 'chalk' }];
    basePlan.scenes[1].diagramElements = [{ type: 'arrow', id: 'analysis-g', layer: 'analysis', dashed: false, x1: 300, y1: 220, x2: 300, y2: 300, color: 'pink', label: 'G' }];
    const plan = applyDiagramBlueprintToPlan(basePlan, problem, createSolution({ subject: '物理', correctOptions: [] }));
    expect(validateDiagramPlan(plan)).toEqual({ ok: true, issues: [] });
  });

  it('重绘阶段对重复 ID 幂等去重，校验器自身也会报重复', () => {
    const basePlan = createPlan();
    basePlan.diagram.baseElements = [
      { type: 'point', id: 'dup', x: 100, y: 100, radius: 6, color: 'yellow' },
      { type: 'point', id: 'dup', x: 200, y: 200, radius: 6, color: 'yellow' }
    ];
    const plan = applyDiagramBlueprintToPlan(basePlan, problem, createSolution({ subject: '物理', correctOptions: [] }));
    expect(plan.diagram.baseElements.filter((element) => element.id === 'dup')).toHaveLength(1);

    // 直接喂给校验器（绕过重绘）时，重复 ID 必须被报出来
    const raw = createPlan();
    raw.diagram.baseElements = [
      { type: 'point', id: 'dup', x: 100, y: 100, radius: 6, color: 'yellow' },
      { type: 'point', id: 'dup', x: 200, y: 200, radius: 6, color: 'yellow' }
    ];
    expect(validateDiagramPlan(raw).issues.join('；')).toContain('原图层图元 ID 重复');
  });

  it('场景内重复 ID 要报错，但跨场景复用同一 ID 是合法的', () => {
    const basePlan = createPlan();
    basePlan.diagram.baseElements = [];
    basePlan.scenes[0].diagramElements = [{ type: 'point', id: 'p', x: 100, y: 100, radius: 6, color: 'yellow' }];
    basePlan.scenes[1].diagramElements = [{ type: 'point', id: 'p', x: 300, y: 200, radius: 6, color: 'cyan' }];
    const acrossScenes = applyDiagramBlueprintToPlan(basePlan, problem, createSolution({ subject: '物理', correctOptions: [] }));
    expect(validateDiagramPlan(acrossScenes).issues.join('；')).not.toContain('场景内图元 ID 重复');

    const sameScene = createPlan();
    sameScene.diagram.baseElements = [];
    sameScene.scenes[0].diagramElements = [
      { type: 'point', id: 'p', x: 100, y: 100, radius: 6, color: 'yellow' },
      { type: 'point', id: 'p', x: 200, y: 200, radius: 6, color: 'cyan' }
    ];
    const withinScene = applyDiagramBlueprintToPlan(sameScene, problem, createSolution({ subject: '物理', correctOptions: [] }));
    expect(validateDiagramPlan(withinScene).issues.join('；')).toContain('场景 1 内图元 ID 重复');
  });

  it('矢量重绘模式不允许再嵌原题截图', () => {
    const basePlan = createPlan();
    basePlan.diagram.mode = 'svg';
    basePlan.diagram.imageDataUrl = 'data:image/png;base64,AAAA';
    expect(validateDiagramPlan(basePlan).issues.join('；')).toContain('不允许再嵌原题截图');
  });
});
