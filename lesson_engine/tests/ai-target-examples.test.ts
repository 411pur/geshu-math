import { describe, expect, it } from 'vitest';
import { LessonPlanSchema } from '../src/schemas/lesson.js';
import { diagramConventionsText, targetExamplesText, targetLessonPlanExamples } from '../src/ai/target-examples.js';

/**
 * 目标示例是给模型照抄的标准答案，一旦它本身不合法，所有模型都会被带偏，
 * 所以这里用 schema 把示例"钉死"：示例必须永远是一份能通过校验的合法讲稿。
 */
describe('目标示例（few-shot）', () => {
  it('至少提供三个示例，且都包含有原图、无图与高中数学方法示例', () => {
    expect(targetLessonPlanExamples.length).toBeGreaterThanOrEqual(3);
    expect(targetLessonPlanExamples.some((example) => example.grade === '高中')).toBe(true);
    const modes = targetLessonPlanExamples.map((example) => example.diagram.mode);
    expect(modes).toContain('svg');
    expect(modes).toContain('none');
  });

  it('每个示例都能直接通过 LessonPlanSchema', () => {
    for (const example of targetLessonPlanExamples) {
      const parsed = LessonPlanSchema.safeParse(example);
      if (!parsed.success) {
        throw new Error(`示例不合法：${example.title} → ${JSON.stringify(parsed.error.issues.slice(0, 3))}`);
      }
      expect(parsed.success).toBe(true);
    }
  });

  it('首场景必须是 question、末场景必须是 answer，且末场景揭晓答案', () => {
    for (const example of targetLessonPlanExamples) {
      expect(example.scenes[0].type).toBe('question');
      expect(example.scenes[example.scenes.length - 1].type).toBe('answer');
      expect(example.scenes[example.scenes.length - 1].revealAnswer).toBe(true);
    }
  });

  it('图层归属符合约定：原图只在 diagram.baseElements，分析矢量只在场景里', () => {
    for (const example of targetLessonPlanExamples) {
      for (const element of example.diagram.baseElements) {
        expect(element.layer === undefined || element.layer === 'base').toBe(true);
      }
      for (const scene of example.scenes) {
        for (const element of scene.diagramElements) {
          expect(element.layer).toBe('analysis');
        }
      }
    }
  });

  it('图元 id 在同一示例内保持唯一，且坐标落在画布内', () => {
    for (const example of targetLessonPlanExamples) {
      const ids: string[] = [];
      const collect = (element: Record<string, unknown>) => {
        ids.push(String(element.id));
        const coords = [element.x, element.y, element.x1, element.y1, element.x2, element.y2].filter((value): value is number => typeof value === 'number');
        for (const value of coords) {
          expect(value).toBeGreaterThanOrEqual(0);
          expect(value).toBeLessThanOrEqual(960 + 200);
        }
        const points = Array.isArray(element.points) ? element.points as Array<{ x: number; y: number }> : [];
        for (const point of points) { expect(point.x).toBeGreaterThanOrEqual(0); expect(point.y).toBeGreaterThanOrEqual(0); }
      };
      example.diagram.baseElements.forEach((element) => collect(element as unknown as Record<string, unknown>));
      example.scenes.forEach((scene) => scene.diagramElements.forEach((element) => collect(element as unknown as Record<string, unknown>)));
      expect(new Set(ids).size).toBe(ids.length);
    }
  });

  it('有原图的示例里，辅助线的起点落在顶点上（与 p1 重合）', () => {
    const withDiagram = targetLessonPlanExamples.find((example) => example.diagram.mode === 'svg');
    expect(withDiagram).toBeDefined();
    const anchor = withDiagram!.diagram.baseElements.find((element) => element.id === 'p1') as { x: number; y: number } | undefined;
    expect(anchor).toBeDefined();
    const arrows = withDiagram!.scenes
      .flatMap((scene) => scene.diagramElements)
      .filter((element) => element.type === 'line') as Array<{ x1: number; y1: number }>;
    expect(arrows.length).toBeGreaterThan(0);
    for (const arrow of arrows) {
      expect(Math.abs(arrow.x1 - anchor!.x)).toBeLessThanOrEqual(2);
      expect(Math.abs(arrow.y1 - anchor!.y)).toBeLessThanOrEqual(2);
    }
  });

  it('纯公式示例不画图，且约定与示例文本都会被送给模型', () => {
    const withoutDiagram = targetLessonPlanExamples.find((example) => example.diagram.mode === 'none');
    expect(withoutDiagram!.diagram.baseElements).toHaveLength(0);
    for (const scene of withoutDiagram!.scenes) expect(scene.diagramElements).toHaveLength(0);
    expect(diagramConventionsText).toContain('960×580');
    expect(targetExamplesText).toContain('目标示例 1');
    expect(targetExamplesText).toContain('目标示例 2');
    expect(targetExamplesText).toContain('目标示例 3');
  });

  it('目标示例示范具体难点、易错提醒和条件检查，而不是空泛提示', () => {
    for (const example of targetLessonPlanExamples) {
      expect(example.scenes.some((scene) => /难点|易错|检查/.test(scene.tip))).toBe(true);
    }
    expect(targetExamplesText).toContain('为什么想到作高');
    expect(targetExamplesText).toContain('只比较极值点而漏掉端点');
  });
});
