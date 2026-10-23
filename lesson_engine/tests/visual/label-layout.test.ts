import { describe, expect, it } from 'vitest';
import { measureLabelBoxes, relayoutOverlappingLabels } from '../../src/visual/label-layout.js';
import type { BrowserSceneSnapshot, RectSnapshot } from '../../src/visual/metrics.js';
import type { VisualAuditReport } from '../../src/schemas/visual.js';
import { createPlan } from '../helpers/lesson-fixtures.js';

function rect(id: string, label: string, x: number, y: number, width = 14, height = 18): RectSnapshot {
  return { id, label, x, y, width, height, clientWidth: 0, clientHeight: 0, scrollWidth: 0, scrollHeight: 0 };
}

function createSnapshot(overrides: Partial<BrowserSceneSnapshot> = {}): BrowserSceneSnapshot {
  return {
    sceneIndex: 0,
    sceneType: 'diagram',
    viewport: { width: 1600, height: 900 },
    textBlocks: [],
    diagramArea: rect('diagramArea', 'diagramArea', 100, 50, 960, 580),
    diagramElements: [],
    labels: [],
    optionCount: 2,
    expectedOptionCount: 2,
    finalAnswerRevealed: null,
    hasDiagramImage: false,
    ...overrides
  };
}

function reportWith(boxes: VisualAuditReport['labelBoxes']): VisualAuditReport {
  return { iteration: 0, score: 60, passed: false, screenshots: [], labelBoxes: boxes, metricsVersion: '1.0', issues: [] };
}

describe('画布坐标换算', () => {
  it('按缩放比把标签像素框换回画布坐标', () => {
    const boxes = measureLabelBoxes([
      createSnapshot({ diagramArea: rect('diagramArea', 'diagramArea', 100, 50, 480, 290), labels: [rect('p1', 'A', 140, 75)] })
    ], [960, 580]);
    expect(boxes).toHaveLength(1);
    expect(boxes[0]).toMatchObject({ sceneIndex: 0, elementId: 'p1', label: 'A' });
    expect(boxes[0].x).toBeCloseTo(80);
    expect(boxes[0].y).toBeCloseTo(50);
    expect(boxes[0].width).toBeCloseTo(28);
  });

  it('把 meet 居中留白也算进去，避免带着缩放误差推标签', () => {
    const scale = 400 / 580;
    const offsetX = (960 - 960 * scale) / 2;
    const boxes = measureLabelBoxes([
      createSnapshot({ diagramArea: rect('diagramArea', 'diagramArea', 0, 0, 960, 400), labels: [rect('p1', 'A', offsetX, 0)] })
    ], [960, 580]);
    expect(boxes[0].x).toBeCloseTo(0, 1);
    expect(boxes[0].y).toBeCloseTo(0, 1);
  });
});

describe('按测量结果重排标签', () => {
  it('把实测重叠的点标签推开，并且可以重复调用（已分开就不再动）', () => {
    const plan = createPlan();
    const measured = [
      { sceneIndex: 2, elementId: 'p1', label: '1', x: 418, y: 264, width: 14, height: 18 },
      { sceneIndex: 2, elementId: 'p2', label: '1', x: 424, y: 264, width: 14, height: 18 }
    ];
    const first = relayoutOverlappingLabels(plan, reportWith(measured));
    expect(first.moved).toBe(2);
    const point = (result: typeof first, id: string) => {
      const element = result.plan.scenes[2].diagramElements.find((item) => item.id === id)!;
      if (element.type !== 'point') throw new Error('夹具里应该是点');
      return { x: element.x + (element.labelDx ?? 18), y: element.y + (element.labelDy ?? -16) };
    };
    const p1 = point(first, 'p1');
    const p2 = point(first, 'p2');
    const apart = Math.max(Math.abs(p1.x - p2.x), Math.abs(p1.y - p2.y));
    expect(apart).toBeGreaterThanOrEqual(14 + 8);

    // 用重排后的位置再测一次：已经分开了，不应该继续推。
    const after = relayoutOverlappingLabels(first.plan, reportWith([
      { sceneIndex: 2, elementId: 'p1', label: '1', x: p1.x, y: p1.y, width: 14, height: 18 },
      { sceneIndex: 2, elementId: 'p2', label: '1', x: p2.x, y: p2.y, width: 14, height: 18 }
    ]));
    expect(after.moved).toBe(0);
  });

  it('矢量标签也能被推开（箭头支持 labelDx/labelDy）', () => {
    const plan = createPlan();
    plan.diagram.baseElements = [
      { type: 'arrow', id: 'vec_v', x1: 200, y1: 400, x2: 400, y2: 400, color: 'pink', dashed: false, label: 'v0' },
      { type: 'label', id: 'label_v', x: 296, y: 384, text: 'v0', color: 'chalk', size: 22 }
    ];
    const measured = [
      { sceneIndex: 0, elementId: 'vec_v', label: 'v0', x: 296, y: 372, width: 24, height: 18 },
      { sceneIndex: 0, elementId: 'label_v', label: 'v0', x: 298, y: 384, width: 24, height: 18 }
    ];
    const result = relayoutOverlappingLabels(plan, reportWith(measured));
    expect(result.moved).toBe(2);
    const arrow = result.plan.diagram.baseElements.find((element) => element.id === 'vec_v')!;
    expect(arrow.type).toBe('arrow');
    if (arrow.type !== 'arrow') throw new Error('夹具里应该是箭头');
    const arrowShift = Math.abs(arrow.labelDx ?? 0) + Math.abs(arrow.labelDy ?? 0);
    expect(arrowShift).toBeGreaterThan(0);
  });

  it('没有测量数据时原样返回（旧报告仍可走模型修复）', () => {
    const plan = createPlan();
    const result = relayoutOverlappingLabels(plan, reportWith([]));
    expect(result.moved).toBe(0);
    expect(result.plan).toBe(plan);
  });
});
