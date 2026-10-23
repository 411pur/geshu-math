import type { DiagramBlueprint, LessonPlan, ProblemExtract, SolutionResult } from '../../src/schemas/lesson.js';

export function createEmptyBlueprint(): DiagramBlueprint {
  return { template: 'custom-svg', shape: 'generic', orientation: 'free', title: '', slots: [], relations: [], baseElements: [], notes: [] };
}

export function createHexagonBlueprint(): DiagramBlueprint {
  return { template: 'polygon-field', shape: 'hexagon', orientation: 'flat-top', title: '', slots: [], relations: ['正六棱柱底面顶点按题图连接'], baseElements: [], notes: ['视觉模型明确识别'] };
}

export function createMechanicsTrackBlueprint(): DiagramBlueprint {
  return { template: 'mechanics-track', shape: 'generic', orientation: 'free', title: '', slots: [], relations: ['水平轨道与竖直半圆轨道相切'], baseElements: [], notes: ['视觉模型明确识别'] };
}

export function createVxGraphBlueprint(): DiagramBlueprint {
  return { template: 'function-graph', shape: 'generic', orientation: 'free', title: '', slots: [], relations: ['横轴为位移 x，纵轴为速度 v'], baseElements: [], notes: ['视觉模型明确识别'] };
}

export function createProblem(overrides: Partial<ProblemExtract> = {}): ProblemExtract {
  return {
    stem: '1 + 1 = ?',
    options: [
      { key: 'A', text: '1' },
      { key: 'B', text: '2' }
    ],
    sourceAnswer: 'B',
    sourceExplanation: '',
    subject: '数学',
    grade: '小学',
    topic: '加法',
    diagramDescription: '',
    diagramMode: 'none',
    warnings: [],
    ...overrides
  };
}

export function createSolution(overrides: Partial<SolutionResult> = {}): SolutionResult {
  return {
    subject: '数学',
    topic: '加法',
    correctOptions: ['B'],
    finalAnswer: 'B. 2',
    confidence: 0.99,
    steps: [{ title: '计算', reasoning: '1 加 1 等于 2。', formulaLines: [] }],
    checks: ['结果符合原答案'],
    sourceComparison: '与原答案一致',
    ...overrides
  };
}

export function createPlan(overrides: Partial<LessonPlan> = {}): LessonPlan {
  return {
    schemaVersion: '1.0',
    title: '加法题讲解',
    subject: '数学',
    grade: '小学',
    difficulty: '基础',
    problem: {
      stem: '1 + 1 = ?',
      options: [
        { key: 'A', text: '1' },
        { key: 'B', text: '2' }
      ],
      correctOptions: ['B'],
      sourceAnswer: 'B',
      sourceExplanation: ''
    },
    teacher: { displayName: '老师', voiceLang: 'zh-CN' },
    diagram: { mode: 'svg', viewBox: [960, 580], baseElements: [] },
    scenes: [
      { type: 'question', title: '先读题', narration: '同学们，先看题目。', tip: '', formulaLines: [], comparisonRows: [], inspectPanels: [], metricBars: [], diagramElements: [], activeElementIds: [], revealAnswer: false, durationHintMs: 4000 },
      { type: 'formula', title: '写出算式', narration: '把题目写成算式。', tip: '', formulaLines: [{ segments: [{ type: 'text', value: '1 + 1 = ?' }] }], comparisonRows: [], inspectPanels: [], metricBars: [], diagramElements: [], activeElementIds: [], revealAnswer: false, durationHintMs: 4000 },
      { type: 'diagram', title: '画出数量', narration: '我们画两个点帮助理解。', tip: '', formulaLines: [], comparisonRows: [], inspectPanels: [], metricBars: [], diagramElements: [{ type: 'point', id: 'p1', x: 400, y: 280, radius: 14, label: '1', color: 'cyan' }, { type: 'point', id: 'p2', x: 560, y: 280, radius: 14, label: '1', color: 'yellow' }], activeElementIds: ['p1', 'p2'], revealAnswer: false, durationHintMs: 4000 },
      { type: 'answer', title: '得到答案', narration: '一个加一个等于两个，所以选 B。', tip: '', formulaLines: [], comparisonRows: [], inspectPanels: [], metricBars: [], diagramElements: [], activeElementIds: [], revealAnswer: true, durationHintMs: 4000 }
    ],
    ...overrides
  };
}
