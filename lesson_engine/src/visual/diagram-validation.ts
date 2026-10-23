import type { LessonPlan } from '../schemas/lesson.js';

export interface DiagramValidationResult { ok: boolean; issues: string[]; }

/**
 * 重绘版的图形自检：只做与题型无关的结构性检查（ID 唯一、原图层不被重复定义、不嵌截图）。
 * 不再有任何“正六棱柱/力学轨道/v-x 图像”之类的题型规则。
 */
export function validateDiagramPlan(plan: LessonPlan): DiagramValidationResult {
  const issues: string[] = [];
  const baseIds = plan.diagram.baseElements.map((element) => element.id);
  const duplicateBase = baseIds.filter((id, index) => baseIds.indexOf(id) !== index);
  if (duplicateBase.length) issues.push(`原图层图元 ID 重复：${[...new Set(duplicateBase)].join('、')}`);

  plan.scenes.forEach((scene, index) => {
    const sceneIds = scene.diagramElements.map((element) => element.id);
    const duplicateScene = sceneIds.filter((id, position) => sceneIds.indexOf(id) !== position);
    if (duplicateScene.length) issues.push(`场景 ${index + 1} 内图元 ID 重复：${[...new Set(duplicateScene)].join('、')}`);
    const redefinedBase = sceneIds.filter((id) => baseIds.includes(id));
    if (redefinedBase.length) issues.push(`场景 ${index + 1} 重复定义原图层图元：${[...new Set(redefinedBase)].join('、')}`);
  });

  if (plan.diagram.mode === 'svg' && plan.diagram.imageDataUrl) issues.push('矢量重绘模式不允许再嵌原题截图');
  return { ok: issues.length === 0, issues };
}
