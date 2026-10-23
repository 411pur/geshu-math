import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { LessonPipeline } from '../src/pipeline/lesson-pipeline.js';
import { ProjectStore } from '../src/store/project-store.js';
import type { TutorAI } from '../src/ai/types.js';
import type { LessonPlan, ProblemExtract, VerificationResult } from '../src/schemas/lesson.js';
import type { LessonPlanRepair } from '../src/schemas/visual.js';
import { createEmptyBlueprint, createPlan, createProblem, createSolution, createVxGraphBlueprint } from './helpers/lesson-fixtures.js';
import type { VisualAuditor } from '../src/visual/types.js';
import type { VisualAuditReport } from '../src/schemas/visual.js';

const tempDirs: string[] = [];

afterEach(async () => {
  await Promise.all(tempDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});

async function createFixture() {
  const root = await mkdtemp(path.join(os.tmpdir(), 'lesson-pipeline-'));
  tempDirs.push(root);
  const store = new ProjectStore(root);
  await store.init();
  const project = await store.create({ text: '1 + 1 = ?' });
  const renderer = { render: vi.fn(async (plan: LessonPlan) => `<html>${plan.title}</html>`) };
  return { store, project, renderer };
}

function createTutor(overrides: Partial<TutorAI> = {}): TutorAI {
  return {
    extractProblem: vi.fn(async () => createProblem()),
    solveProblem: vi.fn(async () => createSolution()),
    createDiagramBlueprint: vi.fn(async () => createEmptyBlueprint()),
    createLessonPlan: vi.fn(async () => createPlan()),
    verifyLessonPlan: vi.fn(async (): Promise<VerificationResult> => ({ ok: true, issues: [] })),
    repairLessonPlan: vi.fn(async (): Promise<LessonPlanRepair> => ({ summary: '无需修复', operations: [{ kind: 'set_focus', sceneIndex: 0, x: 480, y: 290, reason: '测试' }] })),
    ...overrides
  };
}

describe('LessonPipeline', () => {
  it('纯文字题跳过"原图重建"：没有图片可复现，那一步最坏要 6 分钟', async () => {
    const { store, project, renderer } = await createFixture();
    const tutor = createTutor({
      extractProblem: vi.fn(async () => createProblem({ subject: '物理', stem: '斜面上的物块受力分析，求摩擦力大小', diagramDescription: '斜面上有一个物块' }))
    });
    const pipeline = new LessonPipeline(tutor, store, renderer);
    await pipeline.run(project.id, () => {});
    expect(tutor.createDiagramBlueprint).not.toHaveBeenCalled();
  });

  it('题目配了图才做原图重建', async () => {
    const { store, project, renderer } = await createFixture();
    const savedName = await store.saveInputImage(project.id, 'question.png', 'image/png', Buffer.from('fake-image'));
    await store.update(project.id, { input: { ...project.input, imageFileName: savedName, imageMimeType: 'image/png' } });
    const tutor = createTutor({
      extractProblem: vi.fn(async () => createProblem({ subject: '物理', stem: '斜面上的物块受力分析，求摩擦力大小', diagramDescription: '斜面上有一个物块' }))
    });
    const pipeline = new LessonPipeline(tutor, store, renderer);
    await pipeline.run(project.id, () => {});
    expect(tutor.createDiagramBlueprint).toHaveBeenCalledTimes(1);
  });

  it('超长视觉警告会被截断，不再把成功任务变成 failed', async () => {
    const { store, project, renderer } = await createFixture();
    const longMessage = 'x'.repeat(1200);
    const auditor: VisualAuditor = { audit: vi.fn(async () => { throw new Error(longMessage); }) };
    const pipeline = new LessonPipeline(createTutor(), store, renderer, auditor);
    const result = await pipeline.run(project.id, () => {});
    expect(result.visualWarnings.length).toBeGreaterThan(0);
    for (const warning of result.visualWarnings) expect(warning.length).toBeLessThanOrEqual(500);
  });

  it('图形类问题只重排讲稿，不再重跑两分钟的独立求解', async () => {
    const { store, project, renderer } = await createFixture();
    const solveProblem = vi.fn(async () => createSolution());
    let round = 0;
    const verifyLessonPlan = vi.fn(async (): Promise<VerificationResult> => {
      round += 1;
      return round === 1 ? { ok: false, issues: ['受力矢量起点偏离物块，应回到作用点'] } : { ok: true, issues: [] };
    });
    const tutor = createTutor({ solveProblem, verifyLessonPlan });
    await new LessonPipeline(tutor, store, renderer).run(project.id, () => undefined);
    expect(solveProblem).toHaveBeenCalledTimes(1);
    expect(verifyLessonPlan).toHaveBeenCalledTimes(2);
  });

  it('答案类问题仍然重新求解一次', async () => {
    const { store, project, renderer } = await createFixture();
    const solveProblem = vi.fn(async () => createSolution());
    let round = 0;
    const verifyLessonPlan = vi.fn(async (): Promise<VerificationResult> => {
      round += 1;
      return round === 1 ? { ok: false, issues: ['最终答案与选项 C 不一致'] } : { ok: true, issues: [] };
    });
    const tutor = createTutor({ solveProblem, verifyLessonPlan });
    await new LessonPipeline(tutor, store, renderer).run(project.id, () => undefined);
    expect(solveProblem).toHaveBeenCalledTimes(2);
  });

  it('runs the full text pipeline and writes artifacts', async () => {
    const { store, project, renderer } = await createFixture();
    const events: string[] = [];
    const pipeline = new LessonPipeline(createTutor(), store, renderer);

    const result = await pipeline.run(project.id, (event) => { events.push(event.stage); });

    expect(result.html).toContain('加法题讲解');
    // 纯计算题会先给出“是否需要示意图”的判断，因此 planning 阶段会多一条进度事件。
    expect(events).toEqual(['extracting', 'solving', 'planning', 'planning', 'verifying', 'rendering', 'done']);
    expect(await store.readJson(project.id, 'problem.json')).toMatchObject({ subject: '数学' });
    expect(await store.readHtml(project.id)).toContain('加法题讲解');
  });

  it('retries solving when automatic verification finds an answer mismatch', async () => {
    const { store, project, renderer } = await createFixture();
    const solveProblem = vi.fn()
      .mockResolvedValueOnce(createSolution({ correctOptions: ['A'], finalAnswer: 'A. 1' }))
      .mockResolvedValueOnce(createSolution({ correctOptions: ['B'], finalAnswer: 'B. 2' }));
    const verifyLessonPlan = vi.fn()
      .mockResolvedValueOnce({ ok: false, issues: ['答案与原解析不一致'] } satisfies VerificationResult)
      .mockResolvedValueOnce({ ok: true, issues: [] } satisfies VerificationResult);
    const tutor = createTutor({ solveProblem, verifyLessonPlan });

    await new LessonPipeline(tutor, store, renderer).run(project.id, () => undefined);

    expect(solveProblem).toHaveBeenCalledTimes(2);
    expect(verifyLessonPlan).toHaveBeenCalledTimes(2);
  });

  it('不再用确定性模板改写答案：v-x 图像题也走模型求解', async () => {
    const { store, renderer } = await createFixture();
    const problem = createProblem({
      stem: '一汽车从静止开始做匀加速直线运动，然后刹车做匀减速直线运动，直到停止。下列速度v和位移x的关系图象中，能描述该过程的是( )',
      options: [
        { key: 'A', text: '先上凸后上凸，拱形' },
        { key: 'B', text: '弯曲方向不符' },
        { key: 'C', text: '先下凸后上凸' },
        { key: 'D', text: '尖顶折线' }
      ],
      sourceAnswer: 'C',
      sourceExplanation: '原解析把加速段误判为下凸。',
      subject: '物理',
      diagramMode: 'image',
      diagramDescription: '四个v-x坐标系图像，分别标记为A、B、C、D'
    });
    const project = await store.create({ text: problem.stem });
    const extractProblem = vi.fn(async () => problem);
    const solveProblem = vi.fn(async () => createSolution({ subject: '物理', correctOptions: ['B'], finalAnswer: 'B' }));
    const tutor = createTutor({ extractProblem, solveProblem, createDiagramBlueprint: vi.fn(async () => createVxGraphBlueprint()) });

    const result = await new LessonPipeline(tutor, store, renderer).run(project.id, () => undefined);

    // 以前这里会命中写死的 v-x 模板、强行把答案改成 A；现在必须采用模型独立求解的结果。
    expect(solveProblem).toHaveBeenCalledTimes(1);
    expect(result.solution.correctOptions).toEqual(['B']);
    expect(result.plan.problem.correctOptions).toEqual(['B']);
    expect((await store.readJson(project.id, 'solution.json') as { correctOptions: string[] }).correctOptions).toEqual(['B']);
  });

  it('uses a non-empty vision blueprint without keyword override or extra reconstruction', async () => {
    const { store, renderer } = await createFixture();
    const problem = createProblem({
      stem: '一汽车从静止开始做匀加速直线运动，然后刹车做匀减速直线运动，直到停止。下列速度v和位移x的关系图象中，能描述该过程的是( )',
      options: [{ key: 'A', text: 'A图' }, { key: 'B', text: 'B图' }, { key: 'C', text: 'C图' }, { key: 'D', text: 'D图' }],
      sourceAnswer: 'C',
      subject: '物理',
      diagramMode: 'image',
      diagramDescription: '四个v-x图像',
      diagramBlueprint: createVxGraphBlueprint()
    });
    const project = await store.create({ text: problem.stem });
    const createDiagramBlueprint = vi.fn(async () => { throw new Error('不应重新重建非空视觉蓝图'); });
    const tutor = createTutor({
      extractProblem: vi.fn(async () => problem),
      solveProblem: vi.fn(async () => createSolution({ subject: '物理', correctOptions: ['A'], finalAnswer: 'A' })),
      createDiagramBlueprint
    });

    const result = await new LessonPipeline(tutor, store, renderer).run(project.id, () => undefined);

    expect(createDiagramBlueprint).not.toHaveBeenCalled();
    expect(result.plan.diagram.template?.template).toBe('function-graph');
    const saved = await store.readJson<ProblemExtract>(project.id, 'problem.json');
    expect(saved.diagramBlueprint?.relations).toContain('横轴为位移 x，纵轴为速度 v');
  });

  it('falls back to supplemental text when image extraction fails', async () => {
    const { store, renderer } = await createFixture();
    const project = await store.create({ text: '1 + 1 = ?', imageFileName: 'x.png', imageMimeType: 'image/png' });
    await store.saveInputImage(project.id, 'x.png', 'image/png', Buffer.from('not-an-image'));
    await store.update(project.id, { input: { ...project.input, imageFileName: 'input.png' } });

    const extractProblem = vi.fn()
      .mockRejectedValueOnce(new Error('vision unavailable'))
      .mockResolvedValueOnce(createProblem({ warnings: [] }));
    const tutor = createTutor({ extractProblem });

    await new LessonPipeline(tutor, store, renderer).run(project.id, () => undefined);

    expect(extractProblem).toHaveBeenCalledTimes(2);
    const saved = await store.readJson<ProblemExtract>(project.id, 'problem.json');
    expect(saved.warnings.join(' ')).toContain('vision unavailable');
  });
  it('converges after Flash repairs a visual issue', async () => {
    const { store, project, renderer } = await createFixture();
    let audits = 0;
    const auditor: VisualAuditor = {
      audit: vi.fn(async (): Promise<VisualAuditReport> => {
        audits += 1;
        return audits === 1
          ? { iteration: 0, score: 70, passed: false, metricsVersion: '1.0', screenshots: [], labelBoxes: [], issues: [{ code: 'element_overlap', severity: 'warning', sceneIndex: 2, message: '标签重叠', suggestion: '移动标签', details: {} }] }
          : { iteration: 1, score: 100, passed: true, metricsVersion: '1.0', screenshots: [], labelBoxes: [], issues: [] };
      })
    };
    const result = await new LessonPipeline(createTutor(), store, renderer, auditor).run(project.id, () => undefined);
    expect(result.visualStatus).toBe('passed');
    expect(result.renderAttempts).toBe(2);
    expect(auditor.audit).toHaveBeenCalledTimes(2);
    expect(await store.artifactExists(project.id, 'visual/iteration-0/report.json')).toBe(true);
  });

  it('标签重叠先按测量结果由代码重排，不再先叫模型', async () => {
    const { store, project, renderer } = await createFixture();
    const repairLessonPlan = vi.fn(async (): Promise<LessonPlanRepair> => ({ summary: '不该被调用', operations: [{ kind: 'set_focus', sceneIndex: 0, x: 480, y: 290, reason: '测试' }] }));
    const tutor = createTutor({ repairLessonPlan });
    let audits = 0;
    const auditor: VisualAuditor = {
      audit: vi.fn(async (): Promise<VisualAuditReport> => {
        audits += 1;
        // 第 1 轮：两个点标签（场景 2 的 p1/p2）实测框几乎重合；重排后第 2 轮：通过。
        return audits === 1
          ? {
              iteration: 0, score: 80, passed: false, metricsVersion: '1.0', screenshots: [],
              issues: [{ code: 'element_overlap', severity: 'warning', sceneIndex: 2, message: '标签可能重叠：1 / 1', suggestion: '移动其中一个标签', details: {} }],
              labelBoxes: [
                { sceneIndex: 2, elementId: 'p1', label: '1', x: 418, y: 264, width: 14, height: 18 },
                { sceneIndex: 2, elementId: 'p2', label: '1', x: 424, y: 264, width: 14, height: 18 }
              ]
            }
          : { iteration: 0, score: 100, passed: true, metricsVersion: '1.0', screenshots: [], labelBoxes: [], issues: [] };
      })
    };
    const result = await new LessonPipeline(tutor, store, renderer, auditor).run(project.id, () => undefined);
    expect(repairLessonPlan).not.toHaveBeenCalled();
    expect(auditor.audit).toHaveBeenCalledTimes(2);
    expect(renderer.render).toHaveBeenCalledTimes(2);
    expect(result.visualStatus).toBe('passed');
    expect(await store.artifactExists(project.id, 'visual/iteration-0/relayout/report.json')).toBe(true);
  });
  it('内部过程信息走诊断通道，不混进面向学生的视觉提示', async () => {
    const { store, project, renderer } = await createFixture();
    // 模型给了一条引用不存在图元的修复：旧行为会把“已跳过无效视觉修复”当成视觉提示显示给学生。
    const repairLessonPlan = vi.fn(async (): Promise<LessonPlanRepair> => ({ summary: '移动不存在的标签', operations: [{ kind: 'move_element', sceneIndex: 0, elementId: 'label_不存在', dx: 10, dy: 10, reason: '测试' }] }));
    let audits = 0;
    const auditor: VisualAuditor = {
      audit: vi.fn(async (): Promise<VisualAuditReport> => {
        audits += 1;
        return { iteration: audits - 1, score: 70, passed: false, metricsVersion: '1.0', screenshots: [], labelBoxes: [], issues: [{ code: 'text_overflow', severity: 'warning', sceneIndex: 1, message: '文字区域溢出：题干', suggestion: '精简讲解文字', details: {} }] };
      })
    };
    const result = await new LessonPipeline(createTutor({ repairLessonPlan }), store, renderer, auditor).run(project.id, () => undefined);
    // 真正该让学生看到的（文字溢出）留在 visualWarnings
    expect(result.visualWarnings).toContain('文字区域溢出：题干');
    // 实现细节（跳过无效修复、修复失败）只进诊断
    expect(result.visualWarnings.some((item) => item.includes('已跳过无效视觉修复'))).toBe(false);
    expect(result.visualWarnings.some((item) => item.includes('视觉自动修复失败'))).toBe(false);
    expect(result.diagnostics.some((item) => item.includes('已跳过无效视觉修复'))).toBe(true);
    expect(result.diagnostics.some((item) => item.includes('视觉自动修复失败'))).toBe(true);
  });
  it('delivers the best version with warnings after visual repair limit', async () => {
    const { store, project, renderer } = await createFixture();
    const repairLessonPlan = vi.fn(async () => ({ summary: '移动指点', operations: [{ kind: 'set_focus' as const, sceneIndex: 0, x: 300, y: 200, reason: '测试' }] }));
    const auditor: VisualAuditor = {
      audit: vi.fn(async (html, plan, context): Promise<VisualAuditReport> => ({ iteration: context.iteration, score: 70, passed: false, metricsVersion: '1.0', screenshots: [], labelBoxes: [], issues: [{ code: 'element_overlap', severity: 'warning', sceneIndex: 0, message: '仍有重叠', suggestion: '继续调整', details: {} }] }))
    };
    const tutor = createTutor({ repairLessonPlan });
    const result = await new LessonPipeline(tutor, store, renderer, auditor).run(project.id, () => undefined);
    expect(result.visualStatus).toBe('warning');
    expect(result.renderAttempts).toBe(4);
    expect(repairLessonPlan).toHaveBeenCalledTimes(3);
    expect(await store.readHtml(project.id)).toContain('加法题讲解');
  });

  it('keeps the last content version with warnings when review never passes', async () => {
    const { store, project, renderer } = await createFixture();
    const verifyLessonPlan = vi.fn(async (): Promise<VerificationResult> => ({ ok: false, issues: ['存在未解决的符号争议'] }));
    const solveProblem = vi.fn(async () => createSolution());
    const tutor = createTutor({ verifyLessonPlan, solveProblem });
    const result = await new LessonPipeline(tutor, store, renderer).run(project.id, () => undefined);
    expect(result.visualStatus).toBe('warning');
    expect(result.visualWarnings).toContain('存在未解决的符号争议');
    // 复核 3 次（三轮都判不过）。这里的争议是"符号争议"，不指向解法本身，
    // 所以第二轮只重排讲稿；只有到了第三轮才兜底重新求解 → 求解共 2 次
    // （旧行为是每轮都重跑推理模型求解，一次两分钟，难题因此动辄 9-10 分钟）。
    expect(verifyLessonPlan).toHaveBeenCalledTimes(3);
    expect(solveProblem).toHaveBeenCalledTimes(2);
    expect(await store.readHtml(project.id)).toContain('加法题讲解');
  });

});
