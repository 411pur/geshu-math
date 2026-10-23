/**
 * 模型输出归一化：跨模型一致性的第一道闸。
 *
 * 同一个 schema、同一个提示词交给不同模型，差异往往不在"内容对不对"，而在"写法不一样"：
 * 图元类型名不同（circle / dot / segment）、坐标写成字符串、用 from/to 而不是 x1/y1/x2/y2、
 * 颜色写 orange / blue、图层写 original / overlay、场景类型写 intro / summary……
 * 这些差异过去会直接撞在 zod 上：轻则多一次"修复"往返（更容易超时），重则整次生成失败；
 * 而且不同模型被修复到的程度不同，最终产出的讲解形态就各不相同。
 *
 * 这里把它们统一折算成 schema 认可的唯一写法，与具体模型无关。
 *
 * 边界：只折算"结构与写法"，不发明内容——缺少讲解文字时仍然让校验失败，
 * 避免不同模型靠"被兜底"产出看起来一样、实际是空壳的讲稿。
 */

const COLOR_SET = new Set(['yellow', 'cyan', 'pink', 'green', 'chalk', 'muted']);

const COLOR_ALIASES: Record<string, string> = {
  yellow: 'yellow', gold: 'yellow', orange: 'yellow', amber: 'yellow', warning: 'yellow',
  cyan: 'cyan', blue: 'cyan', sky: 'cyan', teal: 'cyan', lightblue: 'cyan', info: 'cyan',
  pink: 'pink', red: 'pink', rose: 'pink', magenta: 'pink', crimson: 'pink', error: 'pink',
  green: 'green', lime: 'green', emerald: 'green', success: 'green',
  chalk: 'chalk', white: 'chalk', black: 'chalk', gray: 'chalk', grey: 'chalk', default: 'chalk',
  muted: 'muted', dim: 'muted', secondary: 'muted', ghost: 'muted'
};

const LAYER_ALIASES: Record<string, string> = {
  base: 'base', original: 'base', background: 'base', bg: 'base', static: 'base', figure: 'base',
  analysis: 'analysis', dynamic: 'analysis', overlay: 'analysis', annotation: 'analysis', step: 'analysis'
};

const ELEMENT_TYPE_ALIASES: Record<string, string> = {
  point: 'point', dot: 'point', circle: 'point', marker: 'point', node: 'point', vertex: 'point',
  label: 'label', text: 'label', caption: 'label', tag: 'label', annotation: 'label',
  line: 'line', segment: 'line', axis: 'line', ray: 'line', edge: 'line', straight: 'line',
  arrow: 'arrow', vector: 'arrow', force: 'arrow', velocity: 'arrow',
  rect: 'rect', rectangle: 'rect', box: 'rect', square: 'rect', block: 'rect',
  polygon: 'polygon', triangle: 'polygon', quad: 'polygon', shape: 'polygon', surface: 'polygon', area: 'polygon',
  polyline: 'polyline', path: 'polyline', curve: 'polyline', arc: 'polyline', track: 'polyline'
};

const SCENE_TYPE_ALIASES: Record<string, string> = {
  question: 'question', problem: 'question', stem: 'question', intro: 'question', setup: 'question', read: 'question',
  formula: 'formula', equation: 'formula', derivation: 'formula', derive: 'formula', calc: 'formula', calculation: 'formula',
  diagram: 'diagram', figure: 'diagram', graph: 'diagram', drawing: 'diagram', force: 'diagram', analysis: 'diagram',
  comparison: 'comparison', compare: 'comparison', contrast: 'comparison', options: 'comparison',
  answer: 'answer', conclusion: 'answer', summary: 'answer', result: 'answer', final: 'answer'
};

const SEGMENT_TYPE_ALIASES: Record<string, string> = {
  text: 'text', plain: 'text', str: 'text', string: 'text',
  sub: 'sub', subscript: 'sub', index: 'sub',
  sup: 'sup', superscript: 'sup', pow: 'sup', power: 'sup', exponent: 'sup',
  fraction: 'fraction', frac: 'fraction', div: 'fraction', divide: 'fraction', ratio: 'fraction',
  sqrt: 'sqrt', root: 'sqrt', radical: 'sqrt',
  accent: 'accent', highlight: 'accent', hi: 'accent', em: 'accent', key: 'accent'
};

const DIAGRAM_MODE_ALIASES: Record<string, string> = {
  svg: 'svg', vector: 'svg', draw: 'svg', figure: 'svg', redraw: 'svg',
  image: 'image', img: 'image', photo: 'image', picture: 'image', screenshot: 'image',
  none: 'none', no: 'none', false: 'none', text: 'none', empty: 'none'
};

const DEFAULT_SCENE_TITLES: Record<string, string> = {
  question: '读题', formula: '推导', diagram: '画图', comparison: '对比', answer: '结论'
};

export function normalizeLessonPlanCandidate(value: unknown): unknown {
  const plan = asRecord(value);
  const scenes = Array.isArray(plan.scenes) ? plan.scenes : [];
  plan.scenes = scenes.map((sceneValue) => normalizeScene(asRecord(sceneValue)));
  plan.diagram = normalizeDiagram(asRecord(plan.diagram));
  plan.problem = normalizeProblem(asRecord(plan.problem));
  return plan;
}

export function normalizeSolutionCandidate(value: unknown): unknown {
  const solution = asRecord(value);
  if (Array.isArray(solution.steps)) solution.steps = solution.steps.map((stepValue) => { const step = asRecord(stepValue); step.formulaLines = normalizeFormulaLines(step.formulaLines); return step; });
  if (Array.isArray(solution.correctOptions)) solution.correctOptions = solution.correctOptions.map((option) => str(option)).filter(Boolean);
  return solution;
}

function normalizeDiagram(diagram: Record<string, any>): Record<string, any> {
  const mode = pickAlias(DIAGRAM_MODE_ALIASES, diagram.mode ?? diagram.type);
  if (mode) diagram.mode = mode;
  const viewBox = Array.isArray(diagram.viewBox) ? diagram.viewBox : null;
  const width = viewBox ? num(viewBox[0]) : NaN;
  const height = viewBox ? num(viewBox[1]) : NaN;
  diagram.viewBox = width && width > 0 && height && height > 0 ? [width, height] : [960, 580];
  if (diagram.baseElements !== undefined) {
    const elements = normalizeElements(diagram.baseElements);
    if (elements.length) diagram.baseElements = elements; else delete diagram.baseElements;
  }
  return diagram;
}

function normalizeProblem(problem: Record<string, any>): Record<string, any> {
  if (Array.isArray(problem.options)) {
    problem.options = problem.options
      .map((optionValue) => {
        const option = asRecord(optionValue);
        const key = str(option.key ?? option.label ?? option.option ?? option.name).slice(0, 4);
        const text = str(option.text ?? option.value ?? option.content ?? option.body).slice(0, 500);
        return key && text ? { key, text } : null;
      })
      .filter(Boolean);
  }
  if (Array.isArray(problem.correctOptions)) {
    problem.correctOptions = problem.correctOptions.map((option) => str(option).slice(0, 20)).filter(Boolean);
  }
  return problem;
}

function normalizeScene(scene: Record<string, any>): Record<string, any> {
  const sceneType = pickAlias(SCENE_TYPE_ALIASES, scene.type ?? scene.kind);
  if (sceneType) scene.type = sceneType;
  delete scene.kind;
  scene.title = str(scene.title ?? scene.heading).slice(0, 120) || DEFAULT_SCENE_TITLES[String(scene.type)] || '讲解';
  delete scene.heading;
  scene.narration = str(scene.narration ?? scene.speech ?? scene.script ?? scene.content).slice(0, 2500);
  delete scene.speech; delete scene.script; delete scene.content;
  if (scene.tip !== undefined) scene.tip = str(scene.tip).slice(0, 500);
  scene.formulaLines = normalizeFormulaLines(scene.formulaLines);
  if (!Array.isArray(scene.comparisonRows)) scene.comparisonRows = [];
  scene.diagramElements = normalizeElements(scene.diagramElements);
  scene.activeElementIds = Array.isArray(scene.activeElementIds)
    ? scene.activeElementIds.map((id) => str(id)).filter(Boolean).slice(0, 20)
    : [];
  const focus = normalizePoint(scene.focus);
  if (focus) scene.focus = focus; else delete scene.focus;
  if (Array.isArray(scene.focusPath)) {
    const path = scene.focusPath.map((point) => normalizePoint(point)).filter(Boolean).slice(0, 8);
    if (path.length) scene.focusPath = path; else delete scene.focusPath;
  } else if (scene.focusPath !== undefined) {
    delete scene.focusPath;
  }
  if (scene.revealAnswer !== undefined) scene.revealAnswer = truthy(scene.revealAnswer);
  if (scene.durationHintMs !== undefined) {
    const duration = num(scene.durationHintMs);
    scene.durationHintMs = Number.isFinite(duration) ? clamp(duration, 1200, 30_000) : 5000;
  }
  return scene;
}

function normalizeElements(value: unknown): Array<Record<string, unknown>> {
  if (!Array.isArray(value)) return [];
  return value
    .map((elementValue) => normalizeElement(asRecord(elementValue)))
    .filter((element): element is Record<string, unknown> => element !== null)
    .slice(0, 30);
}

function normalizeElement(element: Record<string, any>): Record<string, any> | null {
  const type = pickAlias(ELEMENT_TYPE_ALIASES, element.type ?? element.kind ?? element.shape);
  if (!type) return null;
  const id = str(element.id ?? element.name ?? element.key).replace(/\s+/g, '_').slice(0, 80);
  if (!id) return null;

  const out: Record<string, any> = { type, id };
  const layer = pickAlias(LAYER_ALIASES, element.layer);
  if (layer) out.layer = layer;
  const color = pickAlias(COLOR_ALIASES, element.color ?? element.stroke);
  if (color && COLOR_SET.has(color)) out.color = color;
  if (typeof element.fill === 'string') out.fill = element.fill.slice(0, 80);
  if (element.dashed !== undefined) out.dashed = truthy(element.dashed);

  if (type === 'point') {
    const x = num(element.x ?? element.cx, element.center?.x);
    const y = num(element.y ?? element.cy, element.center?.y);
    if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
    out.x = clamp(x, -200, 1200);
    out.y = clamp(y, -200, 900);
    const radius = num(element.radius ?? element.r);
    if (Number.isFinite(radius)) out.radius = clamp(radius, 1, 40);
    const label = str(element.label ?? element.text).slice(0, 80);
    if (label) out.label = label;
    for (const key of ['labelDx', 'labelDy'] as const) {
      const value = num(element[key]);
      if (Number.isFinite(value)) out[key] = clamp(value, -200, 200);
    }
    return out;
  }

  if (type === 'label') {
    const text = str(element.text ?? element.label ?? element.value).slice(0, 160);
    const x = num(element.x);
    const y = num(element.y);
    if (!text || !Number.isFinite(x) || !Number.isFinite(y)) return null;
    out.text = text;
    out.x = clamp(x, -200, 1200);
    out.y = clamp(y, -200, 900);
    const size = num(element.size ?? element.fontSize);
    if (Number.isFinite(size)) out.size = clamp(size, 10, 60);
    return out;
  }

  if (type === 'rect') {
    const x = num(element.x);
    const y = num(element.y);
    const width = num(element.width);
    const height = num(element.height);
    if (![x, y, width, height].every(Number.isFinite) || width <= 0 || height <= 0) return null;
    out.x = clamp(x, -200, 1200);
    out.y = clamp(y, -200, 900);
    out.width = Math.min(width, 1200);
    out.height = Math.min(height, 900);
    const radius = num(element.radius ?? element.rx ?? element.cornerRadius);
    out.radius = Number.isFinite(radius) ? clamp(radius, 0, 40) : 8;
    return out;
  }

  if (type === 'line' || type === 'arrow') {
    const coords = lineCoords(element);
    if (!coords) return null;
    Object.assign(out, coords);
    const width = num(element.width ?? element.strokeWidth);
    if (type === 'line') out.width = Number.isFinite(width) ? clamp(width, 1, 12) : 3;
    if (type === 'arrow') {
      const label = str(element.label ?? element.text).slice(0, 160);
      if (label) out.label = label;
    }
    return out;
  }

  const points = pointList(element.points ?? element.vertices ?? element.pts);
  if (type === 'polygon') {
    if (points.length < 3) return null;
    out.points = points.slice(0, 80);
    return out;
  }
  if (type === 'polyline') {
    if (points.length >= 3) {
      out.points = points.slice(0, 120);
      const width = num(element.width ?? element.strokeWidth);
      out.width = Number.isFinite(width) ? clamp(width, 1, 12) : 3;
      return out;
    }
    if (points.length === 2) {
      // 两个点的"折线"其实就是一条线段：折算成 line，避免整条讲稿因为一个类型选错而失败。
      return { type: 'line', id, ...(layer ? { layer } : {}), ...(color ? { color } : {}), x1: points[0].x, y1: points[0].y, x2: points[1].x, y2: points[1].y, width: 3 };
    }
    return null;
  }
  return null;
}

function lineCoords(element: Record<string, any>): { x1: number; y1: number; x2: number; y2: number } | null {
  let x1 = num(element.x1 ?? element.from?.x ?? element.start?.x ?? element.x);
  let y1 = num(element.y1 ?? element.from?.y ?? element.start?.y ?? element.y);
  let x2 = num(element.x2 ?? element.to?.x ?? element.end?.x);
  let y2 = num(element.y2 ?? element.to?.y ?? element.end?.y);
  if (![x1, y1, x2, y2].every(Number.isFinite)) {
    // 有些模型把线段写成 { type:'segment', points:[{x,y},{x,y}] }：取首尾两点折算，
    // 否则这个图元会被静默丢弃，讲稿里就少一截图形。
    const fallback = pointList(element.points ?? element.pts ?? element.vertices ?? element.path);
    if (fallback.length >= 2) {
      x1 = fallback[0].x; y1 = fallback[0].y;
      x2 = fallback[fallback.length - 1].x; y2 = fallback[fallback.length - 1].y;
    }
  }
  if (![x1, y1, x2, y2].every(Number.isFinite)) return null;
  x1 = clamp(x1, -200, 1200); y1 = clamp(y1, -200, 900);
  x2 = clamp(x2, -200, 1200); y2 = clamp(y2, -200, 900);
  return { x1, y1, x2, y2 };
}

function pointList(value: unknown): Array<{ x: number; y: number }> {
  if (!Array.isArray(value)) return [];
  const points: Array<{ x: number; y: number }> = [];
  for (const pointValue of value) {
    const point = normalizePoint(pointValue);
    if (point) points.push(point);
  }
  return points;
}

function normalizePoint(value: unknown): { x: number; y: number } | null {
  if (Array.isArray(value)) {
    const x = num(value[0]);
    const y = num(value[1]);
    if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
    return { x: clamp(x, -200, 1200), y: clamp(y, -200, 900) };
  }
  const point = asRecord(value);
  const x = num(point.x);
  const y = num(point.y);
  if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
  return { x: clamp(x, -200, 1200), y: clamp(y, -200, 900) };
}

function normalizeFormulaLines(value: unknown): Array<Record<string, unknown>> {
  if (!Array.isArray(value)) return [];
  return value.map((lineValue) => {
    if (typeof lineValue === 'string') return { segments: [{ type: 'text', value: lineValue }] };
    const line = asRecord(lineValue);
    line.segments = normalizeSegments(line.segments ?? line.parts ?? line.items, line);
    if (line.note !== undefined) line.note = str(line.note).slice(0, 300);
    return line;
  });
}

function normalizeSegments(value: unknown, line: Record<string, any>): Array<Record<string, unknown>> {
  const source = Array.isArray(value) ? value : [];
  const segments: Array<Record<string, unknown>> = [];
  for (const segmentValue of source) {
    if (typeof segmentValue === 'string') { segments.push({ type: 'text', value: segmentValue.slice(0, 300) }); continue; }
    const segment = asRecord(segmentValue);
    const type = pickAlias(SEGMENT_TYPE_ALIASES, segment.type ?? segment.kind);
    if (!type) continue;
    if (type === 'text') segments.push({ type: 'text', value: str(segment.value ?? segment.text ?? segment.content).slice(0, 300) });
    else if (type === 'sub') segments.push({ type: 'sub', base: str(segment.base ?? segment.of).slice(0, 80), value: str(segment.value ?? segment.sub ?? segment.text).slice(0, 80) });
    else if (type === 'sup') segments.push({ type: 'sup', base: str(segment.base ?? segment.of).slice(0, 80), value: str(segment.value ?? segment.sup ?? segment.text).slice(0, 80) });
    else if (type === 'fraction') segments.push({ type: 'fraction', numerator: str(segment.numerator ?? segment.num ?? segment.top).slice(0, 80), denominator: str(segment.denominator ?? segment.den ?? segment.bottom).slice(0, 80) });
    else if (type === 'sqrt') segments.push({ type: 'sqrt', value: str(segment.value ?? segment.radicand ?? segment.text).slice(0, 160) });
    else if (type === 'accent') segments.push({ type: 'accent', value: str(segment.value ?? segment.text).slice(0, 160) });
  }
  if (!segments.length) {
    const text = str(line.text ?? line.value ?? line.formula ?? line.content).slice(0, 300);
    segments.push({ type: 'text', value: text || '公式' });
  }
  return segments.slice(0, 30);
}

function pickAlias(map: Record<string, string>, value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const key = String(value).trim().toLowerCase().replace(/[\s_-]+/g, '');
  return map[key] ?? null;
}

function str(value: unknown): string {
  if (typeof value === 'string') return value.trim();
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  return '';
}

function num(...values: unknown[]): number {
  for (const value of values) {
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    if (typeof value === 'string' && value.trim()) {
      const parsed = Number(value);
      if (Number.isFinite(parsed)) return parsed;
    }
  }
  return NaN;
}

function clamp(value: number, low: number, high: number): number {
  return Math.min(high, Math.max(low, value));
}

function truthy(value: unknown): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') return ['true', '1', 'yes', 'y', 'on'].includes(value.trim().toLowerCase());
  if (typeof value === 'number') return value !== 0;
  return false;
}

function asRecord(value: unknown): Record<string, any> { return value && typeof value === 'object' && !Array.isArray(value) ? { ...(value as Record<string, any>) } : {}; }
