import { LessonPlanSchema } from '../schemas/lesson.js';
import type { DiagramElement, LessonPlan } from '../schemas/lesson.js';
import type { LessonPlanRepair } from '../schemas/visual.js';

export interface AppliedRepair {
  plan: LessonPlan;
  contentChanged: boolean;
}

export interface FilteredRepair {
  repair: LessonPlanRepair;
  skipped: string[];
}

export function filterApplicableRepairOperations(plan: LessonPlan, repair: LessonPlanRepair): FilteredRepair {
  const skipped: string[] = [];
  const operations = repair.operations.filter((operation) => {
    if ('elementId' in operation) {
      const scene = plan.scenes[operation.sceneIndex];
      const exists = Boolean(scene?.diagramElements.some((element) => element.id === operation.elementId));
      if (!exists) skipped.push(`${operation.kind}:${operation.elementId}`);
      return exists;
    }
    return true;
  });
  return { repair: { ...repair, operations: operations as LessonPlanRepair['operations'] }, skipped };
}

export function applyLessonPlanRepair(plan: LessonPlan, repair: LessonPlanRepair): AppliedRepair {
  const next = structuredClone(plan) as LessonPlan;
  let contentChanged = false;

  for (const operation of repair.operations) {
    const scene = next.scenes[operation.sceneIndex];
    if (!scene) throw new Error(`修复操作引用了不存在的场景 ${operation.sceneIndex}`);

    if (operation.kind === 'replace_scene') {
      next.scenes[operation.sceneIndex] = operation.scene;
      contentChanged = true;
      continue;
    }

    if (operation.kind === 'shorten_narration') {
      scene.narration = operation.narration;
      contentChanged = true;
      continue;
    }

    if (operation.kind === 'set_tip') {
      scene.tip = operation.tip;
      contentChanged = true;
      continue;
    }

    if (operation.kind === 'set_focus') {
      scene.focus = { x: operation.x, y: operation.y };
      continue;
    }

    const elementIndex = scene.diagramElements.findIndex((element) => element.id === operation.elementId);
    if (elementIndex < 0) throw new Error(`修复操作引用了不存在的图元 ${operation.elementId}`);
    const element = scene.diagramElements[elementIndex];

    if (operation.kind === 'delete_element') {
      scene.diagramElements.splice(elementIndex, 1);
      scene.activeElementIds = scene.activeElementIds.filter((id) => id !== operation.elementId);
      continue;
    }

    if (operation.kind === 'move_element') {
      scene.diagramElements[elementIndex] = moveElement(element, operation.dx, operation.dy);
      continue;
    }

    if (operation.kind === 'set_label_offset') {
      scene.diagramElements[elementIndex] = setLabelOffset(element, operation.dx, operation.dy);
    }
  }

  return { plan: LessonPlanSchema.parse(next), contentChanged };
}

function moveElement(element: DiagramElement, dx: number, dy: number): DiagramElement {
  switch (element.type) {
    case 'point':
      return { ...element, x: element.x + dx, y: element.y + dy };
    case 'polygon':
    case 'polyline':
      return { ...element, points: element.points.map((point) => ({ x: point.x + dx, y: point.y + dy })) };
    case 'line':
    case 'arrow':
      return { ...element, x1: element.x1 + dx, y1: element.y1 + dy, x2: element.x2 + dx, y2: element.y2 + dy };
    case 'label':
      return { ...element, x: element.x + dx, y: element.y + dy };
    case 'rect':
      return { ...element, x: element.x + dx, y: element.y + dy };
  }
}

function setLabelOffset(element: DiagramElement, dx: number, dy: number): DiagramElement {
  if (element.type === 'point') {
    return { ...element, labelDx: (element.labelDx ?? 18) + dx, labelDy: (element.labelDy ?? -16) + dy };
  }
  if (element.type === 'label') return { ...element, x: element.x + dx, y: element.y + dy };
  if (element.type === 'arrow') return { ...element, label: element.label ?? '', x2: element.x2 + dx, y2: element.y2 + dy };
  throw new Error(`图元 ${element.id} 不支持标签偏移`);
}
