import type { DiagramElement, LessonPlan, ProblemExtract } from '../schemas/lesson.js';

interface Point { x: number; y: number; }
interface Segment { a: Point; b: Point; }

export interface PhysicsIssue { sceneIndex: number; elementId: string; message: string; }

// 注意：这里不能用 i 标志——否则小写 f（摩擦力）会匹配到大写 F（外加力），
// 导致“光滑水平面上的拉力 F”被误判成摩擦力。
const GRAVITY = /^(m\s*\*?\s*g|g|G)$/i;
const NORMAL = /^(N|n|Fn|F_N)$/;
const FRICTION = /^(f|Ff|F_f)$/;

function isGravity(label: string): boolean {
  if (/分力/.test(label)) return false;
  return GRAVITY.test(label.trim()) || (/重力/.test(label) && !/分力/.test(label));
}
function isNormal(label: string): boolean {
  if (/分力/.test(label)) return false;
  return NORMAL.test(label.trim()) || /支持力|法向|正压力/.test(label);
}
function isFriction(label: string): boolean {
  if (/分力/.test(label)) return false;
  return FRICTION.test(label.trim()) || /摩擦力/.test(label);
}

function isForceLike(label: string): boolean {
  const trimmed = label.trim();
  if (!trimmed) return false;
  if (isGravity(trimmed) || isNormal(trimmed) || isFriction(trimmed)) return true;
  return /^[FT](\b|_|=)/i.test(trimmed) || /拉力|弹力|压力|合力|向心力|安培力|洛伦兹力/.test(trimmed);
}

function segmentsOf(element: DiagramElement): Segment[] {
  if (element.type === 'line' || element.type === 'arrow') {
    return [{ a: { x: element.x1, y: element.y1 }, b: { x: element.x2, y: element.y2 } }];
  }
  if (element.type === 'polyline' || element.type === 'polygon') {
    const points = element.points;
    const segments: Segment[] = [];
    for (let index = 1; index < points.length; index += 1) segments.push({ a: points[index - 1], b: points[index] });
    if (element.type === 'polygon' && points.length > 2) segments.push({ a: points[points.length - 1], b: points[0] });
    return segments;
  }
  return [];
}

function segmentLength(segment: Segment): number {
  return Math.hypot(segment.b.x - segment.a.x, segment.b.y - segment.a.y);
}

function closestPointOnSegment(point: Point, segment: Segment): Point {
  const dx = segment.b.x - segment.a.x;
  const dy = segment.b.y - segment.a.y;
  const lengthSquared = dx * dx + dy * dy;
  if (lengthSquared === 0) return { ...segment.a };
  const t = Math.max(0, Math.min(1, ((point.x - segment.a.x) * dx + (point.y - segment.a.y) * dy) / lengthSquared));
  return { x: segment.a.x + t * dx, y: segment.a.y + t * dy };
}

function distanceToSegment(point: Point, segment: Segment): number {
  const closest = closestPointOnSegment(point, segment);
  return Math.hypot(point.x - closest.x, point.y - closest.y);
}

function angleBetweenDeg(u: Point, v: Point): number {
  const lengthU = Math.hypot(u.x, u.y);
  const lengthV = Math.hypot(v.x, v.y);
  if (!lengthU || !lengthV) return 0;
  const cosine = Math.max(-1, Math.min(1, (u.x * v.x + u.y * v.y) / (lengthU * lengthV)));
  return (Math.acos(cosine) * 180) / Math.PI;
}

/** 与轴线的最小夹角：0° 和 180° 都算“沿该方向”。 */
function parallelAngleDeg(u: Point, v: Point): number {
  const angle = angleBetweenDeg(u, v);
  return Math.min(angle, 180 - angle);
}

/**
 * 接触面法线：取垂直于接触面的两个方向中，背离接触面（指向受力物体）的那个。
 * SVG 的 y 轴向下，因此“竖直向下”是 (0, +1)。
 */
function outwardNormal(support: Segment, from: Point): Point {
  const tangent = { x: support.b.x - support.a.x, y: support.b.y - support.a.y };
  let normal = { x: -tangent.y, y: tangent.x };
  const closest = closestPointOnSegment(from, support);
  const away = { x: from.x - closest.x, y: from.y - closest.y };
  if (Math.hypot(away.x, away.y) < 1) {
    // 起点正好落在接触面上（讲稿通常要求矢量起点贴住物体）：默认取“向上”的法线。
    if (normal.y > 0) normal = { x: -normal.x, y: -normal.y };
  } else if (normal.x * away.x + normal.y * away.y < 0) {
    normal = { x: -normal.x, y: -normal.y };
  }
  return normal;
}

function nearestSurface(point: Point, segments: Segment[]): Segment | undefined {
  let best: Segment | undefined;
  let bestDistance = Number.POSITIVE_INFINITY;
  for (const segment of segments) {
    const distance = distanceToSegment(point, segment);
    if (distance < bestDistance) { bestDistance = distance; best = segment; }
  }
  return bestDistance <= 150 ? best : undefined;
}

/**
 * 受力分析的确定性物理校验：不依赖模型自述，直接按“接触面几何”算方向。
 *   · 重力必须竖直向下（屏幕坐标 y 正方向）
 *   · 支持力必须垂直于接触面、背离接触面
 *   · 摩擦力必须沿接触面
 * 只检查能明确定位的箭头；无法判定（没有接触面、标签不明确）就不报，避免误伤。
 */
export function checkAnalysisPhysics(plan: LessonPlan, problem?: ProblemExtract): PhysicsIssue[] {
  const text = problem ? `${problem.stem} ${problem.diagramDescription}` : '';
  const frictionless = /光滑|不计摩擦|无摩擦/.test(text);
  const surfaces = plan.diagram.baseElements.flatMap(segmentsOf).filter((segment) => segmentLength(segment) > 40);
  if (!surfaces.length) return [];

  const issues: PhysicsIssue[] = [];
  plan.scenes.forEach((scene, sceneIndex) => {
    for (const element of scene.diagramElements) {
      if (element.type !== 'arrow') continue;
      const label = (element.label || '').trim();
      const direction = { x: element.x2 - element.x1, y: element.y2 - element.y1 };
      if (Math.hypot(direction.x, direction.y) < 5) continue;

      if (isGravity(label)) {
        const deviation = angleBetweenDeg(direction, { x: 0, y: 1 });
        if (deviation > 25) {
          issues.push({ sceneIndex, elementId: element.id, message: `场景 ${sceneIndex + 1} 的「${label}」偏离竖直向下约 ${Math.round(deviation)}°，重力方向应为竖直向下` });
        }
        continue;
      }

      const normal = isNormal(label);
      const friction = isFriction(label);
      if (friction && frictionless) {
        issues.push({ sceneIndex, elementId: element.id, message: `场景 ${sceneIndex + 1} 画了摩擦力「${label}」，但题干说明接触面光滑，不应有摩擦力` });
        continue;
      }
      if (!normal && !friction) continue;

      const start = { x: element.x1, y: element.y1 };
      const surface = nearestSurface(start, surfaces);
      if (!surface) continue;

      if (normal) {
        const deviation = angleBetweenDeg(direction, outwardNormal(surface, start));
        if (deviation > 30) {
          issues.push({ sceneIndex, elementId: element.id, message: `场景 ${sceneIndex + 1} 的「${label}」与接触面法线偏差约 ${Math.round(deviation)}°，支持力应垂直于接触面` });
        }
      } else {
        const tangent = { x: surface.b.x - surface.a.x, y: surface.b.y - surface.a.y };
        const deviation = parallelAngleDeg(direction, tangent);
        if (deviation > 30) {
          issues.push({ sceneIndex, elementId: element.id, message: `场景 ${sceneIndex + 1} 的「${label}」与接触面偏差约 ${Math.round(deviation)}°，摩擦力应沿接触面` });
        }
      }
    }

    const forceArrows = scene.diagramElements.filter((element) => element.type === 'arrow' && isForceLike(element.label || ''));
    if (forceArrows.length >= 2) {
      let spread = 0;
      for (let left = 0; left < forceArrows.length; left += 1) {
        for (let right = left + 1; right < forceArrows.length; right += 1) {
          const a = forceArrows[left] as { x1: number; y1: number };
          const b = forceArrows[right] as { x1: number; y1: number };
          spread = Math.max(spread, Math.hypot(a.x1 - b.x1, a.y1 - b.y1));
        }
      }
      if (spread > 70 && spread <= 200) {
        issues.push({
          sceneIndex,
          elementId: forceArrows[0].id,
          message: `场景 ${sceneIndex + 1} 的受力矢量起点不一致（最大相距 ${Math.round(spread)}），同一物体的受力应从同一作用点画出`
        });
      }
    }
  });

  return [...new Map(issues.map((issue) => [`${issue.elementId}:${issue.message}`, issue])).values()];
}
