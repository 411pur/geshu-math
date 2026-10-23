import { z } from 'zod';

export const ProjectStatusSchema = z.enum(['queued', 'running', 'done', 'failed']);
export const ProjectStageSchema = z.enum(['queued','extracting','solving','verifying','planning','rendering','visual_check','repairing','done','failed']);
export const VisualStatusSchema = z.enum(['not_checked', 'passed', 'warning']);

export const ProjectInputSchema = z.object({
  text: z.string().max(20_000).optional(),
  imageFileName: z.string().max(255).optional(),
  imageMimeType: z.string().max(100).optional()
});

export const ProjectRecordSchema = z.object({
  id: z.string().uuid(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
  status: ProjectStatusSchema,
  stage: ProjectStageSchema,
  progress: z.number().min(0).max(100),
  title: z.string().max(200).default('未命名题目'),
  subject: z.string().max(80).default(''),
  input: ProjectInputSchema,
  error: z.string().max(2000).optional(),
  visualStatus: VisualStatusSchema.default('not_checked'),
  visualWarnings: z.array(z.string().max(500)).max(30).default([]),
  // 面向排查的过程信息（跳过无效修复、复核争议、重试次数……），不展示给学生。
  visualDiagnostics: z.array(z.string().max(500)).max(30).default([]),
  renderAttempts: z.number().int().min(0).max(10).default(0)
});

export type ProjectInput = z.infer<typeof ProjectInputSchema>;
export type ProjectRecord = z.infer<typeof ProjectRecordSchema>;
export type ProjectStatus = z.infer<typeof ProjectStatusSchema>;
export type ProjectStage = z.infer<typeof ProjectStageSchema>;
export type VisualStatus = z.infer<typeof VisualStatusSchema>;
