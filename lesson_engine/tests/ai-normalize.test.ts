import { describe, expect, it } from 'vitest';
import { normalizeLessonPlanCandidate, normalizeSolutionCandidate } from '../src/ai/normalize.js';

describe('AI output normalization', () => {
  it('converts string formula lines into segment arrays', () => {
    const plan = normalizeLessonPlanCandidate({ scenes: [{ formulaLines: ['E = 1700 V/m', { text: 'φA = 16 V' }] }] }) as any;
    expect(plan.scenes[0].formulaLines[0].segments).toEqual([{ type: 'text', value: 'E = 1700 V/m' }]);
    expect(plan.scenes[0].formulaLines[1].segments).toEqual([{ type: 'text', value: 'φA = 16 V' }]);
  });
  it('normalizes solution step formulas', () => {
    const solution = normalizeSolutionCandidate({ steps: [{ title: '计算', formulaLines: ['1 + 1 = 2'] }] }) as any;
    expect(solution.steps[0].formulaLines[0].segments[0].value).toBe('1 + 1 = 2');
  });

  it('把不同模型的图元写法折算成同一套 schema 写法', () => {
    const plan = normalizeLessonPlanCandidate({
      diagram: { mode: 'vector', viewBox: ['960', 580] },
      scenes: [{
        type: 'figure',
        diagramElements: [
          { kind: 'circle', name: 'p1', x: '480', y: '420', r: '99', stroke: 'orange' },
          { type: 'vector', id: 'v1', from: { x: 480, y: 420 }, to: { x: 480, y: 300 }, color: 'blue', layer: 'overlay', label: 'N' },
          { type: 'segment', id: 'l1', pts: [{ x: 0, y: 0 }, { x: 500, y: 0 }] },
          { type: 'label', id: 'lb1', value: 'mg', x: 500, y: 380, fontSize: 4 }
        ]
      }]
    }) as any;
    expect(plan.diagram.mode).toBe('svg');
    const [point, arrow, line, label] = plan.scenes[0].diagramElements;
    expect(point).toMatchObject({ type: 'point', id: 'p1', x: 480, y: 420, radius: 40, color: 'yellow' });
    expect(arrow).toMatchObject({ type: 'arrow', id: 'v1', x1: 480, y1: 420, x2: 480, y2: 300, color: 'cyan', layer: 'analysis', label: 'N' });
    expect(line).toMatchObject({ type: 'line', id: 'l1', width: 3 });
    expect(label).toMatchObject({ type: 'label', id: 'lb1', text: 'mg', size: 10 });
  });

  it('补全结构字段、裁剪越界数值，但不发明讲解正文', () => {
    const plan = normalizeLessonPlanCandidate({
      scenes: [{ type: 'intro', durationHintMs: 99999, revealAnswer: 'true', activeElementIds: ['p1', 2], narration: '先读题。' }]
    }) as any;
    expect(plan.scenes[0].type).toBe('question');
    expect(plan.scenes[0].title).toBe('读题');
    expect(plan.scenes[0].durationHintMs).toBe(30000);
    expect(plan.scenes[0].revealAnswer).toBe(true);
    expect(plan.scenes[0].activeElementIds).toEqual(['p1', '2']);
    expect(plan.scenes[0].comparisonRows).toEqual([]);
    const empty = normalizeLessonPlanCandidate({ scenes: [{ type: 'answer' }] }) as any;
    expect(empty.scenes[0].narration).toBe('');
  });
});
