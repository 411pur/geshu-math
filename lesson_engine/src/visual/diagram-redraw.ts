import type { DiagramElement, LessonPlan, ProblemExtract, SolutionResult } from '../schemas/lesson.js';
import { elementAnchor } from './diagram-fidelity.js';

type DiagramPoint = { x: number; y: number };

/**
 * 把“视觉识别出的图形对象”重绘成 SVG 板书。
 *
 * 这里**不做任何题型模板匹配**：原图层与分析层的图元全部来自模型对题图的实际识别
 * （`diagramBlueprint.baseElements` 与各场景的 `diagramElements`）。本模块只负责三件事：
 *   1. 分层：原图层沉到底图，分析层留在各自场景里逐镜叠加；
 *   2. 归一化排版：把识别出来的坐标等比缩放并居中，铺满画布（不改变图形比例）；
 *   3. 推导模拟鼠标的指点轨迹 focusPath。
 */
export function applyDiagramBlueprintToPlan(plan: LessonPlan, problem: ProblemExtract, solution: SolutionResult): LessonPlan {
  void solution;
  const blueprint = problem.diagramBlueprint;
  const sourceBase = blueprint?.baseElements.length ? blueprint.baseElements : plan.diagram.baseElements;
  if (!sourceBase.length && !plan.scenes.some((scene) => scene.diagramElements.length)) {
    // 题目确实没有图形：保持 none/image，不去凭空造图。
    const mode = problem.diagramMode === 'none' ? 'none' as const : (plan.diagram.imageDataUrl ? 'image' as const : plan.diagram.mode);
    return withGuidance(separateCoincidentLabels(promoteBaseLayer({
      ...plan,
      diagram: { ...plan.diagram, mode, imageDataUrl: mode === 'none' ? undefined : plan.diagram.imageDataUrl }
    })));
  }

  const baseElements = sourceBase.map((element) => ({ ...element, layer: 'base' as const }));
  const layered = promoteBaseLayer({
    ...plan,
    diagram: { ...plan.diagram, mode: 'svg', imageDataUrl: undefined, template: blueprint, baseElements }
  });
  return withGuidance(dedupeOverlappingVectors(separateCoincidentLabels(fitDiagramToCanvas(layered))));
}

/** 原图层统一沉到 diagram.baseElements，保证每个场景都先显示按图重绘出来的题目原图。 */
function promoteBaseLayer(plan: LessonPlan): LessonPlan {
  const withBase = plan.diagram.baseElements.map((element) => ({ ...element, layer: element.layer ?? ('base' as const) }));
  const sceneBase = plan.scenes.flatMap((scene) => scene.diagramElements.filter((element) => element.layer === 'base'));
  const merged = dedupeElements([...withBase, ...sceneBase.map((element) => ({ ...element, layer: 'base' as const }))]);
  const baseIds = new Set(merged.map((element) => element.id));
  return {
    ...plan,
    diagram: { ...plan.diagram, baseElements: merged },
    scenes: plan.scenes.map((scene) => ({ ...scene, diagramElements: scene.diagramElements.filter((element) => !baseIds.has(element.id)) }))
  };
}

function dedupeElements(elements: DiagramElement[]): DiagramElement[] {
  const seen = new Map<string, DiagramElement>();
  for (const element of elements) if (!seen.has(element.id)) seen.set(element.id, element);
  return [...seen.values()];
}

function pointsOf(element: DiagramElement): DiagramPoint[] {
  if (element.type === 'point' || element.type === 'label') return [{ x: element.x, y: element.y }];
  if (element.type === 'line' || element.type === 'arrow') return [{ x: element.x1, y: element.y1 }, { x: element.x2, y: element.y2 }];
  if (element.type === 'rect') return [{ x: element.x, y: element.y }, { x: element.x + element.width, y: element.y + element.height }];
  return element.points;
}

function boundsOf(elements: DiagramElement[]): { minX: number; minY: number; maxX: number; maxY: number } | undefined {
  const points = elements.flatMap(pointsOf);
  if (!points.length) return undefined;
  return {
    minX: Math.min(...points.map((point) => point.x)),
    minY: Math.min(...points.map((point) => point.y)),
    maxX: Math.max(...points.map((point) => point.x)),
    maxY: Math.max(...points.map((point) => point.y))
  };
}

/** 按坐标映射重写一个图元；只动坐标，不动线宽/字号/颜色。 */
function mapElement(element: DiagramElement, fn: (point: DiagramPoint) => DiagramPoint): DiagramElement {
  const round = (value: number) => Number(value.toFixed(2));
  if (element.type === 'point' || element.type === 'label') {
    const point = fn({ x: element.x, y: element.y });
    return { ...element, x: round(point.x), y: round(point.y) };
  }
  if (element.type === 'line' || element.type === 'arrow') {
    const a = fn({ x: element.x1, y: element.y1 });
    const b = fn({ x: element.x2, y: element.y2 });
    return { ...element, x1: round(a.x), y1: round(a.y), x2: round(b.x), y2: round(b.y) };
  }
  if (element.type === 'rect') {
    const a = fn({ x: element.x, y: element.y });
    const b = fn({ x: element.x + element.width, y: element.y + element.height });
    return {
      ...element,
      x: round(Math.min(a.x, b.x)),
      y: round(Math.min(a.y, b.y)),
      width: Math.max(1, round(Math.abs(b.x - a.x))),
      height: Math.max(1, round(Math.abs(b.y - a.y)))
    };
  }
  return { ...element, points: element.points.map((point) => { const next = fn(point); return { x: round(next.x), y: round(next.y) }; }) };
}

/**
 * 视觉模型给出的坐标只是“看着图估的”，可能缩在一角或溢出画布。
 * 这里按整体包围盒做一次**等比**缩放 + 居中，让重绘结果铺满画布，同时保持图形比例不变。
 */
function fitDiagramToCanvas(plan: LessonPlan): LessonPlan {
  const baseElements = plan.diagram.baseElements;
  const overlays = plan.scenes.flatMap((scene) => scene.diagramElements);
  // 原图决定画布构图；没有原图层时才退化为按全部图元计算。
  const box = (baseElements.length ? boundsOf(baseElements) : undefined) ?? boundsOf([...baseElements, ...overlays]);
  if (!box) return plan;

  const [width, height] = plan.diagram.viewBox;
  const padding = 56;
  const boxWidth = Math.max(1, box.maxX - box.minX);
  const boxHeight = Math.max(1, box.maxY - box.minY);
  const rawScale = Math.min((width - padding * 2) / boxWidth, (height - padding * 2) / boxHeight);
  const scale = Math.min(Math.max(rawScale, 0.35), 4);
  const offsetX = (width - boxWidth * scale) / 2 - box.minX * scale;
  const offsetY = (height - boxHeight * scale) / 2 - box.minY * scale;
  const map = (point: DiagramPoint): DiagramPoint => ({ x: point.x * scale + offsetX, y: point.y * scale + offsetY });

  return {
    ...plan,
    diagram: { ...plan.diagram, baseElements: plan.diagram.baseElements.map((element) => mapElement(element, map)) },
    scenes: plan.scenes.map((scene) => ({
      ...scene,
      focus: scene.focus ? map(scene.focus) : undefined,
      focusPath: (scene.focusPath ?? []).map(map),
      diagramElements: scene.diagramElements.map((element) => mapElement(element, map))
    }))
  };
}

/**
 * 把"叠在一起"的标签散开——这一条用代码兜底，不交给模型。
 *
 * 真实故障：为了让图形重建更快，把它换成快速模型后，对象都识别对了，但
 * label_a/label_b/label_L/label_3L 被放在几乎同一个坐标上（两处各挤一堆），
 * 渲染出来标签互相覆盖，视觉检查连续 4 轮都判不过——省下的时间又被修复轮吃掉，
 * 而且成品是带重叠的。
 *
 * 规则是确定性的、与模型无关：同一位置的标签按固定扇形依次错开，同一 id 在后续
 * 场景里复用时保持同一个偏移（"更新同一图元"不会被越推越远），最后仍夹在画布安全边距内。
 */
const LABEL_MIN_GAP = 34;
const LABEL_FAN: Array<[number, number]> = [
  [0, 0], [0, -44], [0, 44], [-64, 0], [64, 0], [-64, -44], [64, 44], [-64, 44], [64, -44]
];

export function separateCoincidentLabels(plan: LessonPlan): LessonPlan {
  const viewBox = plan.diagram.viewBox;
  const taken: DiagramPoint[] = [];
  const offsetById = new Map<string, DiagramPoint>();

  // 先把"不会移动的标签位置"占住：点标注与矢量的标签由渲染器画在固定位置
  // （点：x+labelDx、y+labelDy，默认 18/-16；矢量：线段中点上方 14px）。
  // 否则自由标签会正好压到它们身上——实测就是 label_L 压住了电流矢量 I 的标签，
  // 视觉检查连续四轮都判"标签区域重叠：L / I"。
  const allElements = [...plan.diagram.baseElements, ...plan.scenes.flatMap((scene) => scene.diagramElements)];
  for (const element of allElements) {
    if (element.type === 'point' && element.label) {
      taken.push(clampToViewBox({ x: element.x + (element.labelDx ?? 18), y: element.y + (element.labelDy ?? -16) }, viewBox));
    } else if (element.type === 'arrow' && element.label) {
      taken.push(clampToViewBox({ x: (element.x1 + element.x2) / 2, y: (element.y1 + element.y2) / 2 - 14 }, viewBox));
    }
  }

  const adjust = (elements: DiagramElement[]): DiagramElement[] =>
    elements.map((element) => {
      if (element.type !== 'label') return element;
      let offset = offsetById.get(element.id);
      if (!offset) {
        let candidate: DiagramPoint = { x: element.x, y: element.y };
        for (const [dx, dy] of LABEL_FAN) {
          candidate = { x: element.x + dx, y: element.y + dy };
          const clash = taken.some((point) => Math.abs(point.x - candidate.x) < LABEL_MIN_GAP && Math.abs(point.y - candidate.y) < LABEL_MIN_GAP);
          if (!clash) break;
        }
        const placed = clampToViewBox(candidate, viewBox);
        taken.push(placed);
        offset = { x: placed.x - element.x, y: placed.y - element.y };
        offsetById.set(element.id, offset);
      }
      const moved = clampToViewBox({ x: element.x + offset.x, y: element.y + offset.y }, viewBox);
      return { ...element, x: Math.round(moved.x), y: Math.round(moved.y) };
    });

  return {
    ...plan,
    diagram: { ...plan.diagram, baseElements: adjust(plan.diagram.baseElements) },
    scenes: plan.scenes.map((scene) => ({ ...scene, diagramElements: adjust(scene.diagramElements) }))
  };
}

function clampToViewBox(point: DiagramPoint, viewBox: [number, number]): DiagramPoint {
  // 指针图形以锚点为原点向右下延伸，且点击涟漪会向外扩张，需要预留安全边距。
  const marginX = 56;
  const marginY = 64;
  return { x: Math.min(Math.max(point.x, marginX), viewBox[0] - marginX), y: Math.min(Math.max(point.y, marginY), viewBox[1] - marginY) };
}

/** 推导每个场景的鼠标指点轨迹：模型给了 focusPath 就用，否则按 activeElementIds 的锚点。 */
function withGuidance(plan: LessonPlan): LessonPlan {
  const viewBox = plan.diagram.viewBox;
  const accumulated = new Map<string, DiagramElement>();
  for (const element of plan.diagram.baseElements) accumulated.set(element.id, element);
  const scenes = plan.scenes.map((scene) => {
    for (const element of scene.diagramElements) accumulated.set(element.id, element);
    const stops: DiagramPoint[] = [];
    for (const point of scene.focusPath ?? []) stops.push(point);
    if (!stops.length) {
      for (const id of scene.activeElementIds) {
        const element = accumulated.get(id);
        const anchor = element ? elementAnchor(element) : undefined;
        if (anchor) stops.push(anchor);
      }
    }
    if (!stops.length && scene.focus) stops.push(scene.focus);
    const unique: DiagramPoint[] = [];
    for (const point of stops) {
      if (unique.some((item) => Math.abs(item.x - point.x) < 18 && Math.abs(item.y - point.y) < 18)) continue;
      unique.push(point);
    }
    const focusPath = unique.slice(0, 6).map((point) => clampToViewBox(point, viewBox));
    return { ...scene, focus: scene.focus ?? focusPath[0], focusPath };
  });
  return { ...plan, scenes };
}


/** 取标签的“头符号”：F = 6 N → F，Ff → Ff，用于判断是不是同一支矢量。 */
function labelHead(label: string): string {
  const match = (label || '').trim().match(/^[A-Za-z][A-Za-z0-9_]*/);
  return match ? match[0].toLowerCase() : '';
}

function sameVector(a: DiagramElement, b: DiagramElement): boolean {
  if (a.type !== 'arrow' || b.type !== 'arrow') return false;
  const forward = Math.hypot(a.x1 - b.x1, a.y1 - b.y1) + Math.hypot(a.x2 - b.x2, a.y2 - b.y2);
  const reversed = Math.hypot(a.x1 - b.x2, a.y1 - b.y2) + Math.hypot(a.x2 - b.x1, a.y2 - b.y1);
  if (Math.min(forward, reversed) > 30) return false;
  const headA = labelHead(a.label || '');
  const headB = labelHead(b.label || '');
  if (!headA || !headB) return true;
  return headA === headB;
}

/**
 * 同一支矢量只画一次：模型经常在原图已经画了「F」的情况下，又在场景里画一支同位置同符号的
 * 「F = 6 N」，两支箭头完全重合、两个标签叠在一起。这里按“几何重合 + 头符号相同”去掉后来的那支，
 * 并把 activeElementIds 重定向到保留的图元上，避免指针找不到对象。
 */
function dedupeOverlappingVectors(plan: LessonPlan): LessonPlan {
  const kept: DiagramElement[] = [...plan.diagram.baseElements];
  const scenes = plan.scenes.map((scene) => {
    const redirect = new Map<string, string>();
    const diagramElements: DiagramElement[] = [];
    for (const element of scene.diagramElements) {
      if (element.type === 'arrow') {
        const duplicate = kept.find((candidate) => sameVector(candidate, element));
        if (duplicate) { redirect.set(element.id, duplicate.id); continue; }
      }
      diagramElements.push(element);
      kept.push(element);
    }
    return {
      ...scene,
      diagramElements,
      activeElementIds: scene.activeElementIds.map((id) => redirect.get(id) ?? id)
    };
  });
  return { ...plan, scenes };
}
