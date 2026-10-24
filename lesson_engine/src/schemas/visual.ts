import { z } from 'zod';
import { SceneSchema } from './lesson.js';

export const VisualSeveritySchema = z.enum(['info', 'warning', 'critical']);
export const VisualIssueCodeSchema = z.enum([
  'text_overflow',
  'container_overflow',
  'element_out_of_bounds',
  'element_overlap',
  'pointer_out_of_bounds',
  'option_count_mismatch',
  'answer_not_revealed',
  'missing_diagram',
  'low_contrast',
  'scene_render_error',
  'duplicate_element_id',
  'unexpected_image_background'
]);

export const VisualIssueSchema = z.object({
  code: VisualIssueCodeSchema,
  severity: VisualSeveritySchema,
  sceneIndex: z.number().int().min(0).max(30),
  elementId: z.string().max(120).optional(),
  message: z.string().min(1).max(500),
  suggestion: z.string().max(500).default(''),
  details: z.record(z.string(), z.union([z.string(), z.number(), z.boolean()])).default({})
});

export const SceneScreenshotSchema = z.object({
  sceneIndex: z.number().int().min(0).max(30),
  file: z.string().min(1).max(200)
});

/**
 * 标签在画布坐标系里的实测框。
 *
 * 视觉检查本来就是按 DOM 里量到的真实文字框判重叠的，把这份测量交回流水线，
 * "按测量结果重排标签"才有依据（以前只报重叠，导致只能让模型看着 JSON 猜坐标）。
 */
export const LabelBoxSchema = z.object({
  sceneIndex: z.number().int().min(0).max(30),
  elementId: z.string().min(1).max(120),
  label: z.string().max(160).default(''),
  x: z.number(),
  y: z.number(),
  width: z.number().min(0),
  height: z.number().min(0)
});

export const VisualAuditReportSchema = z.object({
  iteration: z.number().int().min(0).max(10),
  score: z.number().min(0).max(100),
  passed: z.boolean(),
  issues: z.array(VisualIssueSchema).max(200).default([]),
  screenshots: z.array(SceneScreenshotSchema).max(30).default([]),
  // 旧报告里没有这个字段，默认空数组即可（重排逻辑会直接跳过）。
  labelBoxes: z.array(LabelBoxSchema).max(600).default([]),
  metricsVersion: z.literal('1.0').default('1.0')
});

export const VisualCritiqueSchema = z.object({
  iteration: z.number().int().min(0).max(10),
  summary: z.string().min(1).max(1000),
  issues: z.array(VisualIssueSchema).max(50).default([])
});

const RepairBaseSchema = z.object({
  sceneIndex: z.number().int().min(0).max(30),
  reason: z.string().min(1).max(300)
});

export const LessonPlanRepairOperationSchema = z.discriminatedUnion('kind', [
  RepairBaseSchema.extend({
    kind: z.literal('move_element'),
    elementId: z.string().min(1).max(120),
    dx: z.number().min(-500).max(500),
    dy: z.number().min(-500).max(500)
  }),
  RepairBaseSchema.extend({
    kind: z.literal('set_label_offset'),
    elementId: z.string().min(1).max(120),
    dx: z.number().min(-300).max(300),
    dy: z.number().min(-300).max(300)
  }),
  RepairBaseSchema.extend({
    kind: z.literal('delete_element'),
    elementId: z.string().min(1).max(120)
  }),
  RepairBaseSchema.extend({
    kind: z.literal('set_focus'),
    x: z.number().min(-200).max(1200),
    y: z.number().min(-200).max(900)
  }),
  RepairBaseSchema.extend({
    kind: z.literal('shorten_narration'),
    narration: z.string().min(1).max(1200)
  }),
  RepairBaseSchema.extend({
    kind: z.literal('set_tip'),
    tip: z.string().max(500)
  }),
  RepairBaseSchema.extend({
    kind: z.literal('replace_scene'),
    scene: SceneSchema
  })
]);

export const LessonPlanRepairSchema = z.object({
  summary: z.string().min(1).max(1000),
  operations: z.array(LessonPlanRepairOperationSchema).min(1).max(30)
});

export type LessonPlanRepair = z.infer<typeof LessonPlanRepairSchema>;
export type VisualAuditReport = z.infer<typeof VisualAuditReportSchema>;
export type VisualCritique = z.infer<typeof VisualCritiqueSchema>;
export type LabelBox = z.infer<typeof LabelBoxSchema>;
export type VisualIssue = z.infer<typeof VisualIssueSchema>;
