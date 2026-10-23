import type { z } from 'zod';
import type { DiagramBlueprint, LessonPlan, ProblemExtract, SolutionResult, VerificationResult } from '../schemas/lesson.js';
import type { LessonPlanRepair, VisualAuditReport, VisualCritique } from '../schemas/visual.js';

export interface ImageInput {
  data: Buffer;
  mimeType: string;
  fileName: string;
}

export interface GenerationInput {
  text?: string;
  image?: ImageInput;
}

export type ChatMessage =
  | { role: 'system' | 'user' | 'assistant'; content: string }
  | {
      role: 'user';
      content: Array<
        | { type: 'text'; text: string }
        | { type: 'image_url'; image_url: { url: string } }
      >;
    };

export interface StructuredCompletionOptions {
  model: string;
  messages: ChatMessage[];
  schemaName: string;
  temperature?: number;
  maxTokens?: number;
  timeoutMs?: number;
  normalize?: (value: unknown) => unknown;
  extraBody?: Record<string, unknown>;
}

export interface StructuredChatClient {
  completeStructured<T>(schema: z.ZodType<T>, options: StructuredCompletionOptions): Promise<T>;
}

export interface TutorAI {
  extractProblem(input: GenerationInput): Promise<ProblemExtract>;
  solveProblem(problem: ProblemExtract, verificationFeedback?: string): Promise<SolutionResult>;
  createDiagramBlueprint(problem: ProblemExtract, solution: SolutionResult, image?: ImageInput): Promise<DiagramBlueprint>;
  createLessonPlan(problem: ProblemExtract, solution: SolutionResult, feedback?: string): Promise<LessonPlan>;
  verifyLessonPlan(problem: ProblemExtract, solution: SolutionResult, plan: LessonPlan): Promise<VerificationResult>;
  repairLessonPlan(problem: ProblemExtract, solution: SolutionResult, plan: LessonPlan, report: VisualAuditReport, critique?: VisualCritique): Promise<LessonPlanRepair>;
}
