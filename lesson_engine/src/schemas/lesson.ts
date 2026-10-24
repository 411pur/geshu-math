import { z } from 'zod';

export const DiagramColorSchema = z.enum(['yellow', 'cyan', 'pink', 'green', 'chalk', 'muted']);
export const SceneTypeSchema = z.enum(['question', 'formula', 'diagram', 'comparison', 'answer']);

export const OptionSchema = z.object({
  key: z.string().trim().min(1).max(4),
  text: z.string().trim().min(1).max(500)
});

export const MathSegmentSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('text'), value: z.string().max(300) }),
  z.object({ type: z.literal('sub'), base: z.string().max(80), value: z.string().max(80) }),
  z.object({ type: z.literal('sup'), base: z.string().max(80), value: z.string().max(80) }),
  z.object({ type: z.literal('fraction'), numerator: z.string().max(80), denominator: z.string().max(80) }),
  z.object({ type: z.literal('sqrt'), value: z.string().max(160) }),
  z.object({ type: z.literal('accent'), value: z.string().max(160) })
]);

export const FormulaLineSchema = z.object({
  segments: z.array(MathSegmentSchema).min(1).max(30),
  note: z.string().max(300).optional()
});

const PointSchema = z.object({ x: z.number(), y: z.number() });
const LayerField = { layer: z.enum(['base', 'analysis']).optional() };
const BoxSchema = z.object({ x: z.number(), y: z.number(), width: z.number().positive(), height: z.number().positive() });

export const DiagramElementSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('point'),
    ...LayerField,
    id: z.string().min(1).max(80),
    x: z.number().min(-200).max(1200),
    y: z.number().min(-200).max(900),
    radius: z.number().min(1).max(40).default(6),
    label: z.string().max(80).optional(),
    labelDx: z.number().min(-200).max(200).optional(),
    labelDy: z.number().min(-200).max(200).optional(),
    color: DiagramColorSchema.default('yellow')
  }),
  z.object({
    type: z.literal('polygon'),
    ...LayerField,
    id: z.string().min(1).max(80),
    points: z.array(PointSchema).min(3).max(80),
    color: DiagramColorSchema.default('chalk'),
    fill: z.string().max(80).optional()
  }),
  z.object({
    type: z.literal('polyline'),
    ...LayerField,
    id: z.string().min(1).max(80),
    points: z.array(PointSchema).min(3).max(120),
    color: DiagramColorSchema.default('chalk'),
    width: z.number().min(1).max(12).default(3)
  }),
  z.object({
    type: z.literal('line'),
    ...LayerField,
    id: z.string().min(1).max(80),
    x1: z.number(), y1: z.number(), x2: z.number(), y2: z.number(),
    color: DiagramColorSchema.default('chalk'),
    dashed: z.boolean().default(false),
    width: z.number().min(1).max(12).default(3)
  }),
  z.object({
    type: z.literal('arrow'),
    ...LayerField,
    id: z.string().min(1).max(80),
    x1: z.number(), y1: z.number(), x2: z.number(), y2: z.number(),
    color: DiagramColorSchema.default('pink'),
    dashed: z.boolean().default(false),
    label: z.string().max(160).optional(),
    // 矢量标签默认画在线段中点上方 14px；这两个偏移让“按测量结果重排标签”也能把
    // 挨在一起的矢量标签分开（见 src/visual/label-layout.ts）。
    labelDx: z.number().min(-200).max(200).optional(),
    labelDy: z.number().min(-200).max(200).optional()
  }),
  z.object({
    type: z.literal('label'),
    ...LayerField,
    id: z.string().min(1).max(80),
    x: z.number(), y: z.number(),
    text: z.string().min(1).max(160),
    color: DiagramColorSchema.default('chalk'),
    size: z.number().min(10).max(60).default(22)
  }),
  z.object({
    type: z.literal('rect'),
    ...LayerField,
    id: z.string().min(1).max(80),
    ...BoxSchema.shape,
    color: DiagramColorSchema.default('cyan'),
    fill: z.string().max(80).optional(),
    radius: z.number().min(0).max(40).default(8)
  })
]);

export const DiagramTemplateSchema = z.enum([
  'polygon-field',
  'mechanics-track',
  'coordinate-field',
  'free-body',
  'circuit',
  'function-graph',
  'custom-svg'
]);

export const DiagramSlotSchema = z.object({
  id: z.string().min(1).max(80),
  role: z.enum(['vertex', 'point', 'label', 'vector', 'axis', 'line', 'value', 'result']),
  label: z.string().max(120).default(''),
  value: z.string().max(160).default(''),
  anchorId: z.string().max(80).optional()
});

export const DiagramBlueprintSchema = z.object({
  template: DiagramTemplateSchema,
  shape: z.enum(['hexagon', 'triangle', 'quadrilateral', 'circle', 'generic']).default('generic'),
  orientation: z.enum(['flat-top', 'point-top', 'free']).default('free'),
  title: z.string().max(160).default(''),
  slots: z.array(DiagramSlotSchema).max(60).default([]),
  relations: z.array(z.string().max(300)).max(30).default([]),
  baseElements: z.array(DiagramElementSchema).max(60).default([]),
  notes: z.array(z.string().max(300)).max(20).default([])
});

export const ComparisonRowSchema = z.object({
  label: z.string().min(1).max(120),
  value: z.string().min(1).max(300),
  correct: z.boolean().optional(),
  reason: z.string().max(300).optional()
});

export const InspectForceSchema = z.object({
  name: z.string().min(1).max(60),
  // magnitude 为纯数值，单位由 unit 单独给出（避免模型拼进 "N" 字符串）
  magnitude: z.number().nonnegative(),
  unit: z.string().max(20).default('N'),
  direction: z.string().max(60).default(''),
  note: z.string().max(200).optional()
});

export const InspectQuantitySchema = z.object({
  name: z.string().min(1).max(60),
  value: z.number(),
  unit: z.string().max(20).default('')
});

export const InspectPanelSchema = z.object({
  elementId: z.string().min(1).max(80),
  title: z.string().max(120),
  forces: z.array(InspectForceSchema).max(12).default([]),
  quantities: z.array(InspectQuantitySchema).max(12).default([])
});

// max 用于把条形长度归一化到 100%（保证同场景多根柱状图可对比）
export const MetricBarSchema = z.object({
  label: z.string().min(1).max(60),
  value: z.number(),
  max: z.number().positive(),
  unit: z.string().max(20).default('')
});

export const SceneSchema = z.object({
  type: SceneTypeSchema,
  title: z.string().min(1).max(120),
  narration: z.string().min(1).max(2500),
  tip: z.string().max(500).default(''),
  formulaLines: z.array(FormulaLineSchema).max(10).default([]),
  comparisonRows: z.array(ComparisonRowSchema).max(5).default([]),
  inspectPanels: z.array(InspectPanelSchema).max(8).default([]),
  metricBars: z.array(MetricBarSchema).max(8).default([]),
  diagramElements: z.array(DiagramElementSchema).max(30).default([]),
  activeElementIds: z.array(z.string()).max(20).default([]),
  focus: PointSchema.optional(),
  focusPath: z.array(PointSchema).max(8).optional(),
  revealAnswer: z.boolean().default(false),
  durationHintMs: z.number().min(1200).max(30000).default(5000)
});

export const ProblemSchema = z.object({
  finalAnswer: z.string().max(2000).optional(),
  stem: z.string().min(1).max(5000),
  options: z.array(OptionSchema).min(0).max(12),
  correctOptions: z.array(z.string()).max(12).default([]),
  sourceAnswer: z.string().max(500).optional(),
  sourceExplanation: z.string().max(8000).optional()
});

export const LessonPlanSchema = z.object({
  schemaVersion: z.literal('1.0').default('1.0'),
  title: z.string().min(1).max(160),
  subject: z.string().min(1).max(80),
  grade: z.string().max(80).default(''),
  difficulty: z.string().max(80).default(''),
  problem: ProblemSchema,
  teacher: z.object({
    displayName: z.string().min(1).max(40).default('老师'),
    voiceLang: z.string().min(2).max(20).default('zh-CN')
  }).default({ displayName: '老师', voiceLang: 'zh-CN' }),
  diagram: z.object({
    mode: z.enum(['svg', 'image', 'none']).default('none'),
    viewBox: z.tuple([z.number().positive(), z.number().positive()]).default([960, 580]),
    imageDataUrl: z.string().max(12_000_000).optional(),
    imageAlt: z.string().max(200).optional(),
    template: DiagramBlueprintSchema.optional(),
    baseElements: z.array(DiagramElementSchema).max(120).default([])
  }).default({ mode: 'none', viewBox: [960, 580], baseElements: [] }),
  scenes: z.array(SceneSchema).min(4).max(8)
});

export const ProblemExtractSchema = z.object({
  stem: z.string().min(1).max(8000),
  options: z.array(OptionSchema).max(12).default([]),
  sourceAnswer: z.string().max(500).optional(),
  sourceExplanation: z.string().max(10_000).optional(),
  subject: z.string().max(80).default(''),
  grade: z.string().max(80).default(''),
  topic: z.string().max(160).default(''),
  diagramDescription: z.string().max(4000).default(''),
  diagramMode: z.enum(['svg', 'image', 'none']).default('none'),
  diagramBlueprint: DiagramBlueprintSchema.optional(),
  diagramBBox: z.object({
    x: z.number().min(0).max(1),
    y: z.number().min(0).max(1),
    width: z.number().positive().max(1),
    height: z.number().positive().max(1)
  }).optional(),
  warnings: z.array(z.string().max(2000)).max(20).default([])
});

export const SolutionResultSchema = z.object({
  subject: z.string().min(1).max(80),
  topic: z.string().max(160).default(''),
  correctOptions: z.array(z.string()).max(12),
  finalAnswer: z.string().min(1).max(800),
  confidence: z.number().min(0).max(1),
  steps: z.array(z.object({
    title: z.string().min(1).max(120),
    reasoning: z.string().min(1).max(3000),
    formulaLines: z.array(FormulaLineSchema).max(20).default([])
  })).min(1).max(16),
  checks: z.array(z.string().max(500)).max(20).default([]),
  sourceComparison: z.string().max(2000).default('')
});

export const VerificationResultSchema = z.object({
  ok: z.boolean(),
  issues: z.array(z.string().max(500)).max(20).default([]),
  correctedAnswer: z.string().max(800).optional(),
  correctedOptions: z.array(z.string()).max(12).optional()
});

export type DiagramBlueprint = z.infer<typeof DiagramBlueprintSchema>;
export type DiagramElement = z.infer<typeof DiagramElementSchema>;
export type DiagramTemplate = z.infer<typeof DiagramTemplateSchema>;
export type FormulaLine = z.infer<typeof FormulaLineSchema>;
export type InspectForce = z.infer<typeof InspectForceSchema>;
export type InspectPanel = z.infer<typeof InspectPanelSchema>;
export type InspectQuantity = z.infer<typeof InspectQuantitySchema>;
export type LessonPlan = z.infer<typeof LessonPlanSchema>;
export type MetricBar = z.infer<typeof MetricBarSchema>;
export type ProblemExtract = z.infer<typeof ProblemExtractSchema>;
export type Scene = z.infer<typeof SceneSchema>;
export type SolutionResult = z.infer<typeof SolutionResultSchema>;
export type VerificationResult = z.infer<typeof VerificationResultSchema>;
