import { LessonPlanSchema, ProblemExtractSchema, SolutionResultSchema } from '../schemas/lesson.js';
import type { LessonPlan, ProblemExtract, SolutionResult, VerificationResult } from '../schemas/lesson.js';
import type { GenerationInput, ImageInput, TutorAI } from '../ai/types.js';
import type { ProjectStore } from '../store/project-store.js';
import type { ProjectStage, VisualStatus } from '../schemas/project.js';
import type { VisualAuditReport, VisualCritique } from '../schemas/visual.js';
import type { VisualAuditor, VisualCritic } from '../visual/types.js';
import { extractDiagramImage } from './diagram-image.js';
import { applyLessonPlanRepair, filterApplicableRepairOperations } from '../visual/repair.js';
import { applyDiagramBlueprintToPlan } from '../visual/diagram-redraw.js';
import { validateDiagramPlan } from '../visual/diagram-validation.js';
import { decideDiagramNeed } from '../visual/diagram-need.js';
import { auditDiagramFidelity, demoteMisplacedBaseLayer } from '../visual/diagram-fidelity.js';
import { checkAnalysisPhysics } from '../visual/physics-check.js';
import { relayoutOverlappingLabels } from '../visual/label-layout.js';

const MAX_VISUAL_REPAIRS = 3;
const MAX_CONTENT_ATTEMPTS = 3;

/** 记录里 visualWarnings 每项上限 500 字（见 schemas/project.ts）。 */
const MAX_WARNING_LENGTH = 500;

export interface HtmlRenderer { render(plan: LessonPlan): Promise<string>; }
export interface PipelineProgress { stage: ProjectStage; progress: number; message: string; }

export interface PipelineResult {
  problem: ProblemExtract;
  solution: SolutionResult;
  plan: LessonPlan;
  html: string;
  visualStatus: VisualStatus;
  visualWarnings: string[];
  /** 只给排查用：跳过无效修复、复核争议、重试次数这类过程信息，不进面向学生的警告。 */
  diagnostics: string[];
  renderAttempts: number;
}

interface VisualCandidate {
  plan: LessonPlan;
  html: string;
  report: VisualAuditReport;
  critique?: VisualCritique;
  diagnostics: string[];
}

export class LessonPipeline {
  constructor(
    private readonly tutor: TutorAI,
    private readonly store: ProjectStore,
    private readonly renderer: HtmlRenderer,
    private readonly visualAuditor?: VisualAuditor,
    private readonly visualCritic?: VisualCritic
  ) {}

  async run(projectId: string, onProgress: (event: PipelineProgress) => Promise<void> | void): Promise<PipelineResult> {
    const record = await this.store.get(projectId);
    const image = await this.store.readInputImage(projectId);
    const input: GenerationInput = { text: record.input.text, image };

    await this.report(onProgress, 'extracting', 8, '正在读取题目和图形信息');
    let problem = await this.extractWithFallback(input);
    // 先理解题意，再决定到底需不需要示意图，避免该画不画或不该画乱画。
    const diagramDecision = decideDiagramNeed(problem);
    problem = ProblemExtractSchema.parse({
      ...problem,
      diagramMode: diagramDecision.needed ? (problem.diagramMode === 'none' ? 'svg' : problem.diagramMode) : 'none'
    });
    await this.store.writeJson(projectId, 'problem.json', problem);

    await this.report(onProgress, 'solving', 30, '正在独立求解并核对原答案');
    let solution = await this.tutor.solveProblem(problem);
    await this.store.writeJson(projectId, 'solution.json', solution);

    const contentWarnings: string[] = [];
    // 过程信息单独走一条通道：它们对排查有用，但作为“视觉提示”显示给学生毫无意义。
    const diagnostics: string[] = [];
    const hasInputImage = Boolean(image);
    const hasVisionBlueprint = Boolean(
      problem.diagramBlueprint &&
      (problem.diagramBlueprint.slots.length > 0 || problem.diagramBlueprint.relations.length > 0 || problem.diagramBlueprint.baseElements.length > 0)
    );
    // 只有"题目配了图"才值得做原图重建：没有图就没有原图可复现，这一次视觉调用最坏要
    // 180s×2（推理模型 + 校验失败重试一次），还会凭题干编出一份不存在的底座。
    // 纯文字题直接交给讲稿模型按题干画图（提示词里已经要求没有底座时逐项画出题目对象）。
    if (diagramDecision.needed && !hasVisionBlueprint && hasInputImage) {
      try {
        await this.report(onProgress, 'planning', 38, '正在重现题目原图并分离原图层与分析层');
        // 把原图一起交过去：重建这一步要看图，而不是凭题干印象另画一套。
        const diagramBlueprint = await this.tutor.createDiagramBlueprint(problem, solution, image);
        problem = ProblemExtractSchema.parse({ ...problem, diagramBlueprint });
        await this.store.writeJson(projectId, 'diagram-blueprint.json', diagramBlueprint);
        await this.store.writeJson(projectId, 'problem.json', problem);
      } catch (error) {
        contentWarnings.push(`题意图形重建失败，将使用排课模型按题干绘制：${error instanceof Error ? error.message : String(error)}`);
      }
    } else if (!diagramDecision.needed) {
      await this.report(onProgress, 'planning', 38, `题意判断：${diagramDecision.reason}`);
    } else {
      await this.report(onProgress, 'planning', 38, '题目没有配图，图形将由讲稿模型按题干绘制');
    }

    // 不套题型模板：讲稿与图形都来自模型对本题的理解，下面是“排课 + 复核 + 重画”的重试循环。
    // 关键：复核意见必须回传给排课模型，否则重试只是在重复同一个错误答案（旧实现就漏了这一步）。
    let plan: LessonPlan | undefined;
    let normalizedPlan: LessonPlan | undefined;
    let best: { plan: LessonPlan; normalized: LessonPlan; issues: number } | undefined;
    let feedback: string | undefined;
    for (let attempt = 0; attempt < MAX_CONTENT_ATTEMPTS; attempt += 1) {
      await this.report(onProgress, 'planning', 44 + attempt * 8, attempt === 0 ? '正在编排老师讲解步骤' : '正在根据复核意见修订数学推导与图形');
      let draft: LessonPlan;
      try {
        draft = await this.tutor.createLessonPlan(problem, solution, feedback);
      } catch (error) {
        // 模型这一次的输出坏掉（JSON 被截断、语法错）不该直接判整次生成失败：
        // 记下原因，换一份更简洁的讲稿再试，最多试满 MAX_CONTENT_ATTEMPTS 次。
        const message = error instanceof Error ? error.message : String(error);
        diagnostics.push(`排课第 ${attempt + 1} 次未成功：${message.slice(0, 200)}`);
        if (attempt === MAX_CONTENT_ATTEMPTS - 1) throw error;
        feedback = `上一次输出没有通过校验（${message.slice(0, 120)}）。请重新输出一份更简洁、闭合的 LessonPlan JSON。`;
        continue;
      }
      await this.report(onProgress, 'verifying', 56 + attempt * 8, '正在检查定义域、公式、答案与几何关系');
      const normalizedDraft = await this.normalizePlan(problem, solution, draft);
      let verification: VerificationResult;
      try {
        verification = await this.tutor.verifyLessonPlan(problem, solution, draft);
      } catch (error) {
        // 复核调用本身失败（同样常见于输出被截断）按"有争议"处理，继续走重试，而不是让整次生成失败。
        verification = { ok: false, issues: [`复核调用失败：${(error instanceof Error ? error.message : String(error)).slice(0, 200)}`] };
      }
      await this.store.writeJson(projectId, 'verification.json', verification);
      // 模型复核（内容对错） + 确定性物理校验（受力方向按接触面几何算）取并集。
      const issues = [...new Set([...(verification.ok ? [] : verification.issues), ...(problem.subject.includes('物理') ? checkAnalysisPhysics(normalizedDraft, problem).map((issue) => issue.message) : [])])];
      if (!best || issues.length < best.issues) best = { plan: draft, normalized: normalizedDraft, issues: issues.length };
      if (!issues.length) {
        plan = draft;
        normalizedPlan = normalizedDraft;
        break;
      }

      feedback = issues.join('；');
      contentWarnings.push(...issues);
      if (attempt < MAX_CONTENT_ATTEMPTS - 1) {
        // 重跑一次独立求解要 2 分钟上下（推理模型），而实测复核提出的问题大多是
        // 图形/矢量/讲解细节，重排一次讲稿（十几秒）就能改。所以只有问题确实指向
        // 解法本身（答案/选项/公式/数值）时才重新求解；到第二轮仍不通过再无条件升级。
        const solutionContested = issues.some((issue) => /答案|选项|求解|公式|单位|数值|计算|结果|结论|answer/i.test(issue));
        if (solutionContested || attempt >= 1) {
          await this.report(onProgress, 'solving', 52 + attempt * 8, '发现不一致，正在重新推导');
          solution = await this.tutor.solveProblem(problem, feedback);
          await this.store.writeJson(projectId, 'solution.json', solution);
        } else {
          await this.report(onProgress, 'planning', 52 + attempt * 8, '讲解细节需要调整，正在重排讲稿');
        }
      } else {
        await this.report(onProgress, 'planning', 70, '内容复核仍有争议，将采用当前最佳讲稿并标记警告');
        // 争议本身已经作为 issues 进入面向学生的警告，这里只留过程信息，避免同一个问题说两遍。
        diagnostics.push('内容复核仍有争议，已采用当前最佳讲稿并标记警告');
      }
    }
    if (!plan) {
      plan = best?.plan;
      normalizedPlan = best?.normalized;
    }
    if (!plan || !normalizedPlan) throw new Error('未能生成讲稿');

    const diagramValidation = validateDiagramPlan(normalizedPlan);
    if (!diagramValidation.ok) throw new Error(`图形结构校验失败：${diagramValidation.issues.join('；')}`);
    // 图形忠实度：分析矢量起点必须落在题目原图的对象上，否则可能脱离题目情景。
    const fidelityIssues = auditDiagramFidelity(normalizedPlan, problem);
    if (fidelityIssues.length) contentWarnings.push(...fidelityIssues);
    if (!this.visualAuditor) {
      await this.report(onProgress, 'rendering', 92, '正在生成互动黑板 HTML');
      const html = await this.renderer.render(normalizedPlan);
      await this.store.writeJson(projectId, 'lesson.json', normalizedPlan);
      await this.store.writeHtml(projectId, html);
      await this.report(onProgress, 'done', 100, '讲解 HTML 已生成，视觉检查未启用');
      return { problem, solution, plan: normalizedPlan, html, visualStatus: contentWarnings.length ? 'warning' : 'not_checked', visualWarnings: clampWarnings(contentWarnings), diagnostics: clampWarnings(diagnostics), renderAttempts: 0 };
    }

    const visual = await this.runVisualLoop(projectId, problem, solution, normalizedPlan, onProgress);
    await this.store.writeJson(projectId, 'lesson.json', visual.plan);
    await this.store.writeHtml(projectId, visual.html);
    await this.report(onProgress, 'done', 100, visual.report.passed ? '讲解 HTML 已生成，视觉检查通过' : '讲解 HTML 已生成，已交付最佳版本并保留视觉警告');
    return {
      problem,
      solution,
      plan: visual.plan,
      html: visual.html,
      visualStatus: visual.report.passed && contentWarnings.length === 0 ? 'passed' : 'warning',
      visualWarnings: clampWarnings([...contentWarnings, ...reportWarnings(visual.report)]),
      diagnostics: clampWarnings([...diagnostics, ...visual.diagnostics]),
      renderAttempts: visual.report.iteration + 1
    };
  }

  private async runVisualLoop(projectId: string, problem: ProblemExtract, solution: SolutionResult, initialPlan: LessonPlan, onProgress: (event: PipelineProgress) => Promise<void> | void): Promise<VisualCandidate> {
    let currentPlan = initialPlan;
    let currentHtml = await this.renderer.render(currentPlan);
    let best: VisualCandidate | undefined;
    const diagnostics: string[] = [];

    for (let iteration = 0; iteration <= MAX_VISUAL_REPAIRS; iteration += 1) {
      await this.report(onProgress, 'visual_check', Math.min(96, 88 + iteration * 2), `正在进行第 ${iteration + 1} 轮视觉检查`);
      const outputDir = this.store.artifactPath(projectId, `visual/iteration-${iteration}`);
      let report: VisualAuditReport;
      try {
        report = await this.visualAuditor!.audit(currentHtml, currentPlan, { outputDir, iteration });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        diagnostics.push(`视觉检查未完成：${message}`);
        if (best) return best;
        return { plan: currentPlan, html: currentHtml, report: fallbackReport(iteration, message), diagnostics: [...diagnostics] };
      }

      await this.store.writeArtifactJson(projectId, `visual/iteration-${iteration}/report.json`, report);
      const screenshotPaths = report.screenshots.map((shot) => this.store.artifactPath(projectId, `visual/iteration-${iteration}/${shot.file}`));
      let critique: VisualCritique | undefined;
      if (this.visualCritic && screenshotPaths.length) {
        try {
          critique = await this.visualCritic.critique(currentPlan, report, screenshotPaths, iteration);
          await this.store.writeArtifactJson(projectId, `visual/iteration-${iteration}/critique.json`, critique);
        } catch (error) {
          await this.store.writeArtifactText(projectId, `visual/iteration-${iteration}/critique-error.txt`, error instanceof Error ? error.message : String(error));
        }
      }

      const candidate: VisualCandidate = { plan: currentPlan, html: currentHtml, report, critique, diagnostics: [...diagnostics] };
      if (!best || report.score >= best.report.score) best = candidate;
      if (report.passed || iteration === MAX_VISUAL_REPAIRS) break;

      // ① 代码兜底：标签重叠先按“测量到的真实文字框”重排，不花模型调用。
      //    这类问题占视觉不通过的绝大多数，而模型修复经常整轮作废（引用了不存在的图元 ID）。
      const relayout = relayoutOverlappingLabels(currentPlan, report);
      if (relayout.moved > 0) {
        await this.report(onProgress, 'repairing', Math.min(97, 90 + iteration * 2), `正在按测量结果重排 ${relayout.moved} 个重叠标签`);
        const relayoutHtml = await this.renderer.render(relayout.plan);
        const relayoutReport = await this.tryAudit(relayout.plan, relayoutHtml, this.store.artifactPath(projectId, `visual/iteration-${iteration}/relayout`), iteration);
        if (relayoutReport) {
          await this.store.writeArtifactJson(projectId, `visual/iteration-${iteration}/relayout/report.json`, relayoutReport);
          if (relayoutReport.score >= best.report.score) best = { plan: relayout.plan, html: relayoutHtml, report: relayoutReport, diagnostics: [...diagnostics] };
          currentPlan = relayout.plan;
          currentHtml = relayoutHtml;
          report = relayoutReport;
          if (relayoutReport.passed) break;
        }
      }

      await this.report(onProgress, 'repairing', Math.min(97, 90 + iteration * 2), `Flash 正在修复第 ${iteration + 1} 轮视觉问题`);
      try {
        const rawRepair = await this.tutor.repairLessonPlan(problem, solution, currentPlan, report, critique);
        const filtered = filterApplicableRepairOperations(currentPlan, rawRepair);
        if (filtered.skipped.length) diagnostics.push(`已跳过无效视觉修复：${filtered.skipped.join('、')}`);
        if (!filtered.repair.operations.length) throw new Error('所有视觉修复操作都引用了不存在的元素');
        const applied = applyLessonPlanRepair(currentPlan, filtered.repair);
        if (applied.contentChanged) {
          const verification = await this.tutor.verifyLessonPlan(problem, solution, applied.plan);
          if (!verification.ok) {
            diagnostics.push(`视觉修复涉及文案，但内容复核未通过：${verification.issues.join('；')}`);
            break;
          }
        }
        currentPlan = applied.plan;
        currentHtml = await this.renderer.render(currentPlan);
      } catch (error) {
        diagnostics.push(`视觉自动修复失败：${error instanceof Error ? error.message : String(error)}`);
        break;
      }
    }

    if (!best) throw new Error('视觉检查未产生有效结果');
    // 过程信息只进诊断通道，不再塞进视觉报告的 issues（那会让“视觉提示”里出现给学生看的实现细节）。
    best.diagnostics = diagnostics;
    return best;
  }

  /** 视觉检查失败不抛异常：拿不到报告时上层继续走模型修复或交付当前最佳版本。 */
  private async tryAudit(plan: LessonPlan, html: string, outputDir: string, iteration: number): Promise<VisualAuditReport | undefined> {
    if (!this.visualAuditor) return undefined;
    try {
      return await this.visualAuditor.audit(html, plan, { outputDir, iteration });
    } catch {
      return undefined;
    }
  }

  private async extractWithFallback(input: GenerationInput): Promise<ProblemExtract> {
    try {
      return ProblemExtractSchema.parse(await this.tutor.extractProblem(input));
    } catch (error) {
      if (!input.image || !input.text?.trim()) throw error;
      const problem = await this.tutor.extractProblem({ text: input.text });
      return ProblemExtractSchema.parse({ ...problem, warnings: [...problem.warnings, `图片识别失败，已使用补充文字继续生成：${error instanceof Error ? error.message : String(error)}`] });
    }
  }

  private async normalizePlan(problem: ProblemExtract, solution: SolutionResult, plan: LessonPlan): Promise<LessonPlan> {
    const scenes = plan.scenes.map((scene, index) => ({ ...scene, revealAnswer: scene.revealAnswer || index === plan.scenes.length - 1, type: index === plan.scenes.length - 1 ? 'answer' as const : scene.type }));
    const normalized = LessonPlanSchema.parse({
      ...plan,
      title: plan.title || problem.topic || '题目讲解',
      subject: plan.subject || problem.subject || '综合',
      grade: plan.grade || problem.grade,
      problem: {
        finalAnswer: solution.finalAnswer,
        stem: problem.stem,
        options: problem.options.length ? problem.options : plan.problem.options,
        correctOptions: solution.correctOptions.length ? solution.correctOptions : plan.problem.correctOptions,
        sourceAnswer: problem.sourceAnswer,
        sourceExplanation: problem.sourceExplanation
      },
      diagram: {
        ...plan.diagram,
        mode: plan.diagram.imageDataUrl ? 'image' : plan.diagram.mode,
        imageAlt: plan.diagram.imageDataUrl ? `${problem.subject}题目图形` : plan.diagram.imageAlt
      },
      scenes
    });
    // 尊重题目情景：只有题目确实有图才保留原图底座，分析矢量不得混进原图层。
    return demoteMisplacedBaseLayer(applyDiagramBlueprintToPlan(normalized, problem, solution), problem);
  }
  private async report(onProgress: (event: PipelineProgress) => Promise<void> | void, stage: ProjectStage, progress: number, message: string): Promise<void> {
    await onProgress({ stage, progress, message });
  }
}

function reportWarnings(report: VisualAuditReport): string[] { return [...new Set(report.issues.map((issue) => issue.message))].slice(0, 30); }

/**
 * 警告在落库前统一截断。
 *
 * 真实故障：模型报错常常自带两段响应预览（各 320 字），拼起来远超 500 字；而记录 schema 要求
 * 每项不超过 500 字，写记录时直接抛校验错误，于是一次已经成功生成 HTML 的任务被判成 failed，
 * 界面上只显示生成失败、连讲解入口都没有。截断后任务照常交付，长错误仍然留在报告的 details 里。
 */
function clampWarnings(warnings: string[]): string[] {
  return [...new Set(warnings)]
    .slice(0, 30)
    .map((warning) => (warning.length > MAX_WARNING_LENGTH ? `${warning.slice(0, MAX_WARNING_LENGTH - 1)}…` : warning));
}

function fallbackReport(iteration: number, message: string): VisualAuditReport {
  return { iteration, score: 0, passed: false, issues: [{ code: 'scene_render_error', severity: 'critical', sceneIndex: 0, message, suggestion: '检查视觉检查配置', details: {} }], screenshots: [], labelBoxes: [], metricsVersion: '1.0' };
}
