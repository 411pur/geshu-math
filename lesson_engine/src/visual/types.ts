import type { LessonPlan } from '../schemas/lesson.js';
import type { VisualAuditReport, VisualCritique } from '../schemas/visual.js';

export interface VisualAuditContext {
  outputDir: string;
  iteration: number;
}

export interface VisualAuditor {
  audit(html: string, plan: LessonPlan, context: VisualAuditContext): Promise<VisualAuditReport>;
}

export interface VisualCritic {
  critique(plan: LessonPlan, report: VisualAuditReport, screenshotPaths: string[], iteration: number): Promise<VisualCritique>;
}
