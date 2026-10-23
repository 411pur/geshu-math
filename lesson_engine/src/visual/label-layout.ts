import { LessonPlanSchema } from '../schemas/lesson.js';
import type { DiagramElement, LessonPlan } from '../schemas/lesson.js';
import type { VisualAuditReport } from '../schemas/visual.js';
import type { BrowserSceneSnapshot } from './metrics.js';

/** 测量到的标签框（坐标与 diagram.viewBox 同一坐标系）。 */
export interface MeasuredLabelBox {
  sceneIndex: number;
  elementId: string;
  label: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface LabelLayoutResult {
  plan: LessonPlan;
  moved: number;
}

const DEFAULT_VIEW_BOX: [number, number] = [960, 580];
/** 推到贴边时给画布留的余量（viewBox 单位）。 */
const EDGE_MARGIN = 4;
/** 推开后两框之间至少留的缝：视觉检查按“较小框面积的 22%”判重叠，留 8 个单位足够躲开。 */
const MIN_GAP = 8;
/**
 * 触发阈值：视觉检查按“较小框面积的 22%”判 element_overlap，这里取它的一半——
 * 只处理挨到判罚线附近的重叠，轻微擦边不动，免得为了看不见的重叠把标签推得到处都是。
 */
const OVERLAP_TRIGGER_RATIO = 0.11;
const ITERATIONS = 60;
/** 单个标签最多挪多远，避免松弛把标签甩到画布另一头。 */
const MAX_SHIFT = 120;
const OFFSET_LIMIT = 200;

/**
 * 把浏览器里量到的标签像素框换算成 viewBox 坐标。
 *
 * 画布是 preserveAspectRatio="xMidYMid meet" 等比缩放居中的，必须先算缩放比与留白偏移，
 * 否则“按测量结果移动标签”会带着缩放误差越推越偏（两端差一个比例，推一次就错一倍）。
 */
export function measureLabelBoxes(snapshots: BrowserSceneSnapshot[], viewBox: [number, number] = DEFAULT_VIEW_BOX): MeasuredLabelBox[] {
  const [viewWidth, viewHeight] = viewBox;
  if (!(viewWidth > 0) || !(viewHeight > 0)) return [];
  const boxes: MeasuredLabelBox[] = [];
  for (const snapshot of snapshots) {
    const area = snapshot.diagramArea;
    if (!area || !(area.width > 0) || !(area.height > 0)) continue;
    const scale = Math.min(area.width / viewWidth, area.height / viewHeight);
    if (!Number.isFinite(scale) || scale <= 0) continue;
    const offsetX = area.x + (area.width - viewWidth * scale) / 2;
    const offsetY = area.y + (area.height - viewHeight * scale) / 2;
    for (const label of snapshot.labels) {
      if (!label.id || !(label.width > 0) || !(label.height > 0)) continue;
      boxes.push({
        sceneIndex: snapshot.sceneIndex,
        elementId: label.id,
        label: label.label || '',
        x: round2((label.x - offsetX) / scale),
        y: round2((label.y - offsetY) / scale),
        width: round2(label.width / scale),
        height: round2(label.height / scale)
      });
    }
  }
  return boxes;
}

/**
 * 按“测量到的真实文字框”把互相压住的标签推开。
 *
 * 为什么用代码而不是模型：element_overlap 是矩形测出来的确定事实，模型只能看着 JSON
 * 猜坐标——实测一轮模型修复经常整轮作废（引用了不存在的图元 ID），而修复轮次有限。
 * 这里做的是确定性松弛：只在同一场景里真正重叠的标签之间互相推，推到留出 MIN_GAP；
 * 偏移按图元 id 记录，同一个 id 在所有图层/场景保持同一偏移，不会越推越远。
 */
export function relayoutOverlappingLabels(plan: LessonPlan, report: VisualAuditReport): LabelLayoutResult {
  const measured = (report.labelBoxes ?? []).filter((box) => box.width > 0 && box.height > 0);
  if (!measured.length) return { plan, moved: 0 };
  const [viewWidth, viewHeight] = plan.diagram.viewBox ?? DEFAULT_VIEW_BOX;

  const sizeById = new Map<string, { width: number; height: number }>();
  const startById = new Map<string, { x: number; y: number }>();
  const positionById = new Map<string, { x: number; y: number }>();
  const order: string[] = [];
  for (const box of measured) {
    if (startById.has(box.elementId)) continue;
    sizeById.set(box.elementId, { width: box.width, height: box.height });
    startById.set(box.elementId, { x: box.x, y: box.y });
    positionById.set(box.elementId, { x: box.x, y: box.y });
    order.push(box.elementId);
  }

  const idsByScene = new Map<number, string[]>();
  for (const box of measured) {
    const ids = idsByScene.get(box.sceneIndex) ?? [];
    if (!ids.includes(box.elementId)) ids.push(box.elementId);
    idsByScene.set(box.sceneIndex, ids);
  }
  const pairs: Array<[string, string]> = [];
  const seenPairs = new Set<string>();
  for (const ids of idsByScene.values()) {
    for (let first = 0; first < ids.length; first += 1) {
      for (let second = first + 1; second < ids.length; second += 1) {
        const key = [ids[first], ids[second]].sort().join('|');
        if (seenPairs.has(key)) continue;
        seenPairs.add(key);
        pairs.push([ids[first], ids[second]]);
      }
    }
  }
  if (!pairs.length) return { plan, moved: 0 };

  for (let iteration = 0; iteration < ITERATIONS; iteration += 1) {
    let overlapped = false;
    for (const [firstId, secondId] of pairs) {
      const first = positionById.get(firstId);
      const second = positionById.get(secondId);
      const firstSize = sizeById.get(firstId);
      const secondSize = sizeById.get(secondId);
      if (!first || !second || !firstSize || !secondSize) continue;
      const overlapX = Math.min(first.x + firstSize.width, second.x + secondSize.width) - Math.max(first.x, second.x);
      const overlapY = Math.min(first.y + firstSize.height, second.y + secondSize.height) - Math.max(first.y, second.y);
      if (overlapX <= 0 || overlapY <= 0) continue;
      const overlapArea = overlapX * overlapY;
      const smallerArea = Math.min(firstSize.width * firstSize.height, secondSize.width * secondSize.height);
      if (overlapArea <= smallerArea * OVERLAP_TRIGGER_RATIO) continue;
      overlapped = true;
      // 往“重叠更浅”的方向推，改动最小。
      if (overlapX <= overlapY) {
        const shift = (overlapX + MIN_GAP) / 2;
        const direction = first.x <= second.x ? -1 : 1;
        first.x += shift * direction;
        second.x -= shift * direction;
      } else {
        const shift = (overlapY + MIN_GAP) / 2;
        const direction = first.y <= second.y ? -1 : 1;
        first.y += shift * direction;
        second.y -= shift * direction;
      }
    }
    for (const id of order) {
      const position = positionById.get(id);
      const size = sizeById.get(id);
      const start = startById.get(id);
      if (!position || !size || !start) continue;
      const maxX = Math.max(EDGE_MARGIN, viewWidth - size.width - EDGE_MARGIN);
      const maxY = Math.max(EDGE_MARGIN, viewHeight - size.height - EDGE_MARGIN);
      position.x = clamp(start.x - MAX_SHIFT, start.x + MAX_SHIFT, clamp(EDGE_MARGIN, maxX, position.x));
      position.y = clamp(start.y - MAX_SHIFT, start.y + MAX_SHIFT, clamp(EDGE_MARGIN, maxY, position.y));
    }
    if (!overlapped) break;
  }

  const deltas = new Map<string, { dx: number; dy: number }>();
  for (const id of order) {
    const start = startById.get(id);
    const position = positionById.get(id);
    if (!start || !position) continue;
    const dx = position.x - start.x;
    const dy = position.y - start.y;
    if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) continue;
    deltas.set(id, { dx: Math.round(dx), dy: Math.round(dy) });
  }
  if (!deltas.size) return { plan, moved: 0 };

  const applyToElement = (element: DiagramElement): DiagramElement => {
    const delta = deltas.get(element.id);
    if (!delta) return element;
    if (element.type === 'point' && element.label) {
      return { ...element, labelDx: limitOffset((element.labelDx ?? 18) + delta.dx), labelDy: limitOffset((element.labelDy ?? -16) + delta.dy) };
    }
    if (element.type === 'arrow' && element.label) {
      return { ...element, labelDx: limitOffset((element.labelDx ?? 0) + delta.dx), labelDy: limitOffset((element.labelDy ?? 0) + delta.dy) };
    }
    if (element.type === 'label') {
      return { ...element, x: Math.round(element.x + delta.dx), y: Math.round(element.y + delta.dy) };
    }
    return element;
  };

  const nextPlan = LessonPlanSchema.parse({
    ...plan,
    diagram: { ...plan.diagram, baseElements: plan.diagram.baseElements.map(applyToElement) },
    scenes: plan.scenes.map((scene) => ({ ...scene, diagramElements: scene.diagramElements.map(applyToElement) }))
  });
  return { plan: nextPlan, moved: deltas.size };
}

function limitOffset(value: number): number {
  return Math.round(clamp(-OFFSET_LIMIT, OFFSET_LIMIT, value));
}

function clamp(min: number, max: number, value: number): number {
  if (min > max) return min;
  return Math.min(Math.max(value, min), max);
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}
