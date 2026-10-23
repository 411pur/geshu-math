import { describe, expect, it } from 'vitest';
import { applyDiagramBlueprintToPlan } from '../../src/visual/diagram-redraw.js';
import { createEmptyBlueprint, createPlan, createProblem, createSolution } from '../helpers/lesson-fixtures.js';

const rampBlueprint = {
  ...createEmptyBlueprint(),
  template: 'polygon-field' as const,
  shape: 'hexagon' as const,
  relations: ['斜面与水平面夹角 30 度'],
  baseElements: [
    { type: 'polygon' as const, id: 'ramp', layer: 'base' as const, points: [{ x: 0, y: 50 }, { x: 200, y: 50 }, { x: 200, y: 0 }], color: 'chalk' as const },
    { type: 'point' as const, id: 'pt-A', layer: 'base' as const, x: 20, y: 40, radius: 6, color: 'yellow' as const, label: 'A' },
    { type: 'label' as const, id: 'lbl-angle', layer: 'base' as const, x: 170, y: 40, text: '30°', color: 'cyan' as const, size: 22 }
  ]
};

describe('diagram redraw (no templates)', () => {
  it('只用视觉蓝图里识别到的对象重绘，不套题型模板', () => {
    const problem = createProblem({
      subject: '物理',
      stem: '正六棱柱置于匀强电场中，判断各点电势',
      diagramMode: 'image',
      diagramBlueprint: rampBlueprint
    });
    const plan = applyDiagramBlueprintToPlan(createPlan(), problem, createSolution({ subject: '物理', correctOptions: [] }));

    expect(plan.diagram.mode).toBe('svg');
    expect(plan.diagram.baseElements.map((element) => element.id).sort()).toEqual(['lbl-angle', 'pt-A', 'ramp']);
    // 旧模板会塞进 hex-base / pt-D 这些写死的图元，这里必须没有
    expect(plan.diagram.baseElements.some((element) => element.id.startsWith('hex-'))).toBe(false);
    expect(plan.diagram.baseElements.some((element) => element.id === 'pt-D')).toBe(false);
  });

  it('等比缩放并居中，保持识别出的图形比例', () => {
    const problem = createProblem({ subject: '物理', stem: '斜面', diagramMode: 'image', diagramBlueprint: rampBlueprint });
    const plan = applyDiagramBlueprintToPlan(createPlan(), problem, createSolution({ subject: '物理', correctOptions: [] }));

    const points = plan.diagram.baseElements.flatMap((element) => element.type === 'polygon' ? element.points : []);
    const minX = Math.min(...points.map((p) => p.x));
    const maxX = Math.max(...points.map((p) => p.x));
    const minY = Math.min(...points.map((p) => p.y));
    const maxY = Math.max(...points.map((p) => p.y));
    const width = maxX - minX;
    const height = maxY - minY;

    // 原图 200 x 50 → 比例 4:1，重绘后必须还是 4:1
    expect(width / height).toBeCloseTo(4, 1);
    // 铺满画布且留出安全边距（viewBox 960 x 580）
    expect(minX).toBeGreaterThanOrEqual(40);
    expect(maxX).toBeLessThanOrEqual(920);
    expect(minY).toBeGreaterThanOrEqual(40);
    expect(maxY).toBeLessThanOrEqual(540);
    expect(width).toBeGreaterThan(600);
  });

  it('把场景里 layer=base 的图元沉到底图，分析层留在各自场景', () => {
    const problem = createProblem({ subject: '物理', stem: '斜面上物块，画出受力', diagramMode: 'svg', diagramBlueprint: createEmptyBlueprint() });
    const basePlan = createPlan();
    basePlan.diagram.baseElements = [];
    basePlan.scenes[0].diagramElements = [{ type: 'polygon', id: 'scene-base', layer: 'base', points: [{ x: 100, y: 300 }, { x: 500, y: 300 }, { x: 500, y: 120 }], color: 'chalk' }];
    basePlan.scenes[1].diagramElements = [{ type: 'arrow', id: 'analysis-g', layer: 'analysis', dashed: false, x1: 300, y1: 220, x2: 300, y2: 300, color: 'pink', label: 'G' }];

    const plan = applyDiagramBlueprintToPlan(basePlan, problem, createSolution({ subject: '物理', correctOptions: [] }));

    expect(plan.diagram.baseElements.map((element) => element.id)).toContain('scene-base');
    expect(plan.scenes.every((scene) => scene.diagramElements.every((element) => element.id !== 'scene-base'))).toBe(true);
    expect(plan.scenes[1].diagramElements.some((element) => element.id === 'analysis-g')).toBe(true);
  });

  it('为有高亮目标却没写 focusPath 的场景推导鼠标轨迹', () => {
    const problem = createProblem({ subject: '物理', stem: '斜面上物块', diagramMode: 'svg', diagramBlueprint: createEmptyBlueprint() });
    const basePlan = createPlan();
    basePlan.diagram.baseElements = [];
    basePlan.scenes[0].diagramElements = [{ type: 'point', id: 'block', layer: 'base', x: 200, y: 200, radius: 10, color: 'cyan' }];
    basePlan.scenes[0].activeElementIds = ['block'];

    const plan = applyDiagramBlueprintToPlan(basePlan, problem, createSolution({ subject: '物理', correctOptions: [] }));
    expect(plan.scenes[0].focusPath?.length).toBeGreaterThan(0);
  });

  it('题目确实没有图形时不凭空造图', () => {
    const problem = createProblem({ subject: '数学', stem: '计算 12 × 7', diagramMode: 'none' });
    const basePlan = createPlan();
    basePlan.diagram.baseElements = [];
    basePlan.scenes.forEach((scene) => { scene.diagramElements = []; });
    const plan = applyDiagramBlueprintToPlan(basePlan, problem, createSolution({ subject: '数学', correctOptions: [] }));
    expect(plan.diagram.baseElements).toEqual([]);
    expect(plan.diagram.mode).toBe('none');
  });

  it('同一支矢量只画一次：场景里与底图重合的箭头会被去掉并重定向 activeElementIds', () => {
    const problem = createProblem({ subject: '物理', stem: '水平拉物块', diagramMode: 'svg', diagramBlueprint: createEmptyBlueprint() });
    const basePlan = createPlan();
    basePlan.diagram.baseElements = [
      { type: 'arrow', id: 'base-F', dashed: false, x1: 300, y1: 300, x2: 600, y2: 300, color: 'pink', label: 'F' }
    ];
    basePlan.scenes[0].activeElementIds = ['scene-F'];
    basePlan.scenes[0].diagramElements = [
      { type: 'arrow', id: 'scene-F', dashed: false, x1: 302, y1: 301, x2: 598, y2: 299, color: 'pink', label: 'F = 6 N' }
    ];
    const plan = applyDiagramBlueprintToPlan(basePlan, problem, createSolution({ subject: '物理', correctOptions: [] }));
    const arrows = [...plan.diagram.baseElements, ...plan.scenes.flatMap((scene) => scene.diagramElements)].filter((element) => element.type === 'arrow');
    expect(arrows).toHaveLength(1);
    expect(arrows[0].id).toBe('base-F');
    expect(plan.scenes[0].activeElementIds).toContain('base-F');
  });

  it('不同符号的同位置箭头不会被误删（F 与 Ff）', () => {
    const problem = createProblem({ subject: '物理', stem: '水平拉物块', diagramMode: 'svg', diagramBlueprint: createEmptyBlueprint() });
    const basePlan = createPlan();
    basePlan.diagram.baseElements = [
      { type: 'arrow', id: 'base-F', dashed: false, x1: 300, y1: 300, x2: 600, y2: 300, color: 'pink', label: 'F' }
    ];
    basePlan.scenes[0].diagramElements = [
      { type: 'arrow', id: 'scene-Ff', dashed: false, x1: 302, y1: 301, x2: 598, y2: 299, color: 'yellow', label: 'Ff' }
    ];
    const plan = applyDiagramBlueprintToPlan(basePlan, problem, createSolution({ subject: '物理', correctOptions: [] }));
    const arrows = [...plan.diagram.baseElements, ...plan.scenes.flatMap((scene) => scene.diagramElements)].filter((element) => element.type === 'arrow');
    expect(arrows).toHaveLength(2);
  });

  it('叠在同一坐标的标签会被确定性散开（模型差异用代码兜底）', () => {
    const problem = createProblem({
      subject: '物理',
      stem: '不等宽导轨上两根金属棒的电磁感应',
      diagramMode: 'svg',
      diagramBlueprint: {
        ...createEmptyBlueprint(),
        baseElements: [
          { type: 'line', id: 'rail', x1: 60, y1: 60, x2: 900, y2: 60, color: 'chalk', dashed: false, width: 3 },
          { type: 'label', id: 'label_a', x: 300, y: 290, text: 'a', color: 'chalk', size: 22 },
          { type: 'label', id: 'label_b', x: 300, y: 290, text: 'b', color: 'chalk', size: 22 },
          { type: 'label', id: 'label_L', x: 300, y: 290, text: 'L', color: 'chalk', size: 22 },
          { type: 'label', id: 'label_3L', x: 600, y: 290, text: '3L', color: 'chalk', size: 22 }
        ]
      }
    });
    const plan = applyDiagramBlueprintToPlan(createPlan(), problem, createSolution({ subject: '物理', correctOptions: [] }));
    const labels = plan.diagram.baseElements.filter((element) => element.type === 'label') as Array<{ id: string; x: number; y: number }>;
    expect(labels).toHaveLength(4);
    for (let i = 0; i < labels.length; i += 1) {
      for (let j = i + 1; j < labels.length; j += 1) {
        const separated = Math.abs(labels[i].x - labels[j].x) >= 30 || Math.abs(labels[i].y - labels[j].y) >= 30;
        expect(separated, `${labels[i].id} 与 ${labels[j].id} 仍然重叠`).toBe(true);
      }
    }
  });

  it('同一 id 的标签在后续场景里复用时不继续漂移', () => {
    const problem = createProblem({
      subject: '物理',
      stem: '标签复用',
      diagramMode: 'svg',
      diagramBlueprint: {
        ...createEmptyBlueprint(),
        baseElements: [
          { type: 'label', id: 'lb_x', x: 400, y: 300, text: 'x', color: 'chalk', size: 22 },
          { type: 'label', id: 'lb_y', x: 400, y: 300, text: 'y', color: 'chalk', size: 22 }
        ]
      }
    });
    const basePlan = createPlan();
    basePlan.scenes[0].diagramElements = [
      { type: 'label', id: 'lb_x', layer: 'analysis', x: 400, y: 300, text: 'x', color: 'yellow', size: 22 }
    ];
    const plan = applyDiagramBlueprintToPlan(basePlan, problem, createSolution({ subject: '物理', correctOptions: [] }));
    const baseLabel = plan.diagram.baseElements.find((element) => element.id === 'lb_x') as { x: number; y: number };
    const sceneLabel = [...plan.diagram.baseElements, ...plan.scenes.flatMap((scene) => scene.diagramElements)].find((element) => element.id === 'lb_x' && element.layer === 'analysis') as { x: number; y: number } | undefined;
    // 场景里复用的同一 id 至少要落在同一个锚点上（不会因为"再散一次"而继续往外漂）
    if (sceneLabel) {
      expect(Math.abs(sceneLabel.x - baseLabel.x)).toBeLessThanOrEqual(1);
      expect(Math.abs(sceneLabel.y - baseLabel.y)).toBeLessThanOrEqual(1);
    }
  });

  it('自由标签会避开矢量标签与点标签的位置（渲染器画在哪，避到哪）', () => {
    const problem = createProblem({
      subject: '物理',
      stem: '矢量标签避让',
      diagramMode: 'svg',
      diagramBlueprint: {
        ...createEmptyBlueprint(),
        baseElements: [
          { type: 'line', id: 'rail', x1: 40, y1: 300, x2: 900, y2: 300, color: 'chalk', dashed: false, width: 3 },
          // 矢量 I：中点 (500,300)，其标签画在 (500,286)
          { type: 'arrow', id: 'vec_I', layer: 'analysis', x1: 400, y1: 300, x2: 600, y2: 300, color: 'black' as never, dashed: false, label: 'I' },
          // 自由标签正好压在那个位置上
          { type: 'label', id: 'label_L', x: 500, y: 286, text: 'L', color: 'chalk', size: 22 }
        ]
      }
    });
    const plan = applyDiagramBlueprintToPlan(createPlan(), problem, createSolution({ subject: '物理', correctOptions: [] }));
    const label = plan.diagram.baseElements.find((element) => element.id === 'label_L') as { x: number; y: number };
    const arrow = plan.diagram.baseElements.find((element) => element.id === 'vec_I') as { x1: number; y1: number; x2: number; y2: number };
    const arrowLabelX = (arrow.x1 + arrow.x2) / 2;
    const arrowLabelY = (arrow.y1 + arrow.y2) / 2 - 14;
    const farEnough = Math.abs(label.x - arrowLabelX) >= 30 || Math.abs(label.y - arrowLabelY) >= 30;
    expect(farEnough, '自由标签仍然压在矢量标签上').toBe(true);
  });
});
