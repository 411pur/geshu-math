import type { DiagramElement, LessonPlan, ProblemExtract } from '../schemas/lesson.js';

export interface DiagramPoint { x: number; y: number; }

// 受力、速度、场强等分析矢量的典型标签。原图层里不应该出现这些，
// 一旦出现说明是分析用的标注，必须从“原图”里摘出来，避免把推演结果画成题目原本就有。
const ANALYSIS_LABEL = /(^|[\s(（])(mg|G|N|f|F|T|v|a|E|B|I|q|Fn|Ff|Ek|Ep)(\d|′|'|[\s)）]|$)|重力|支持力|压力|摩擦力|拉力|弹力|浮力|合力|分力|速度|加速度|场强|电场线|磁场|磁感线|安培力|洛伦兹力|电场力|电流|冲量|动量|向心力|回复力/i;

export function elementAnchor(element: DiagramElement): DiagramPoint | undefined {
  if (element.type === 'point' || element.type === 'label') return { x: element.x, y: element.y };
  if (element.type === 'rect') return { x: element.x + element.width / 2, y: element.y + element.height / 2 };
  if (element.type === 'line' || element.type === 'arrow') return { x: (element.x1 + element.x2) / 2, y: (element.y1 + element.y2) / 2 };
  if (element.type === 'polygon' || element.type === 'polyline') {
    if (!element.points.length) return undefined;
    const sum = element.points.reduce((acc, point) => ({ x: acc.x + point.x, y: acc.y + point.y }), { x: 0, y: 0 });
    return { x: sum.x / element.points.length, y: sum.y / element.points.length };
  }
  return undefined;
}

export function looksLikeAnalysisVector(element: DiagramElement): boolean {
  if (element.type !== 'arrow') return false;
  return ANALYSIS_LABEL.test((element.label || '').trim());
}

/**
 * 尊重题目情景：只有题目确实有图，才允许存在原图底座；受力/速度/场强等分析矢量不能混进原图层，
 * 必须回到它所属的讲解步骤里逐步出现。
 */
export function demoteMisplacedBaseLayer(plan: LessonPlan, problem: ProblemExtract): LessonPlan {
  if (problem.diagramMode === 'none') {
    // 题意判断为“不需要示意图”，不保留任何臆造出来的底座。
    return { ...plan, diagram: { ...plan.diagram, baseElements: [] } };
  }

  if (problem.subject.includes('数学')) return plan;
  const keepBase: DiagramElement[] = [];
  const misplaced: DiagramElement[] = [];
  for (const element of plan.diagram.baseElements) {
    if (looksLikeAnalysisVector(element)) misplaced.push({ ...element, layer: 'analysis' }); else keepBase.push(element);
  }
  if (!misplaced.length) return plan;

  const targetIndex = Math.max(0, plan.scenes.findIndex((scene) => scene.diagramElements.some((element) => misplaced.some((item) => item.id === element.id)) || scene.activeElementIds.some((id) => misplaced.some((item) => item.id === id))));
  const scenes = plan.scenes.map((scene, index) => index === targetIndex
    ? { ...scene, diagramElements: [...misplaced, ...scene.diagramElements] }
    : scene);
  return { ...plan, diagram: { ...plan.diagram, baseElements: keepBase }, scenes };
}

/**
 * 忠实度检查：分析矢量的起点必须落在题目原图的对象附近，
 * 否则说明它可能脱离了题目情景（凭空指向画布上的空白位置）。
 */
export function auditDiagramFidelity(plan: LessonPlan, problem: ProblemExtract): string[] {
  const issues: string[] = [];
  if (problem.diagramMode === 'none') {
    if (plan.diagram.baseElements.length) issues.push('题意判断为无需示意图，但讲稿仍在原图层画了图元');
    return issues;
  }
  if (problem.subject.includes('数学')) return issues;
  const anchors = plan.diagram.baseElements.map(elementAnchor).filter((point): point is DiagramPoint => Boolean(point));
  if (!anchors.length) return issues;

  for (const scene of plan.scenes) {
    for (const element of scene.diagramElements) {
      if (!looksLikeAnalysisVector(element) || element.type !== 'arrow') continue;
      const tail = { x: element.x1, y: element.y1 };
      const nearest = Math.min(...anchors.map((anchor) => Math.hypot(anchor.x - tail.x, anchor.y - tail.y)));
      if (nearest > 260) issues.push(`分析矢量「${element.label || element.id}」的起点没有落在题目原图的对象上，可能与题意不符`);
    }
  }
  return [...new Set(issues)];
}
