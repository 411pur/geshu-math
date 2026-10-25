(() => {
  const lessonElement = document.getElementById('lesson-data');
  const lesson = JSON.parse(lessonElement.textContent);
  const correctOptions = new Set(lesson.problem.correctOptions || []);
  const sceneCount = lesson.scenes.length;

  const elements = {
    blackboard: document.getElementById('blackboard'),
    playButton: document.getElementById('playButton'),
    playIcon: document.getElementById('playIcon'),
    playLabel: document.getElementById('playLabel'),
    prevButton: document.getElementById('prevButton'),
    nextButton: document.getElementById('nextButton'),
    topPrevButton: document.getElementById('topPrevButton'),
    topNextButton: document.getElementById('topNextButton'),
    topStepCounter: document.getElementById('topStepCounter'),
    replayButton: document.getElementById('replayButton'),
    speedSelect: document.getElementById('speedSelect'),
    voiceButton: document.getElementById('voiceButton'),
    voiceTopButton: document.getElementById('voiceTopButton'),
    fullscreenButton: document.getElementById('fullscreenButton'),
    stepCounter: document.getElementById('stepCounter'),
    stepTitle: document.getElementById('stepTitle'),
    stepText: document.getElementById('stepText'),
    formulaBoard: document.getElementById('formulaBoard'),
    formulaStage: document.getElementById('formulaStage'),
    derivationColumn: document.getElementById('derivationColumn'),
    tipBoard: document.getElementById('tipBoard'),
    metricBoard: document.getElementById('metricBoard'),
    inspectLayer: document.getElementById('inspectLayer'),
    stepList: document.getElementById('stepList'),
    progressText: document.getElementById('progressText'),
    progressBar: document.getElementById('progressBar'),
    studentFeedback: document.getElementById('studentFeedback'),
    optionsGrid: document.getElementById('optionsGrid'),
    teacherAvatar: document.getElementById('teacherAvatar'),
    questionText: document.getElementById('questionText'),
    answerLine: document.getElementById('answerLine'),
    lessonSubject: document.getElementById('lessonSubject'),
    lessonTopic: document.getElementById('lessonTopic'),
    lessonTitle: document.getElementById('lessonTitle'),
    diagramArea: document.getElementById('diagramArea')
  };

  const state = {
    index: 0,
    isPlaying: false,
    voiceEnabled: true,
    speed: 1,
    chosen: null,
    timer: null,
    speechToken: 0,
    pointerToken: 0,
    pointerTimers: [],
    pointerPos: null,
    pointedIds: new Set()
  };

  const colorValues = {
    yellow: '#ffd166',
    cyan: '#70e1d0',
    pink: '#ff8fa3',
    green: '#8ae99e',
    chalk: '#f6f1dc',
    muted: '#8caaa0'
  };

  function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
  }

  function restartAnimation(element) {
    element.classList.remove('chalk-in');
    void element.offsetWidth;
    element.classList.add('chalk-in');
  }

  function make(tag, className, text) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (text !== undefined) element.textContent = text;
    return element;
  }


  function findClosingMath(text, delimiter, start) {
    let braceLevel = 0;
    for (let index = start; index < text.length; index += 1) {
      if (text[index] === '\\') {
        index += 1;
        continue;
      }
      if (braceLevel <= 0 && text.startsWith(delimiter, index)) return index;
      if (text[index] === '{') braceLevel += 1;
      else if (text[index] === '}') braceLevel -= 1;
    }
    return -1;
  }

  function splitMathText(text) {
    const source = String(text ?? '');
    const parts = [];
    let cursor = 0;
    while (cursor < source.length) {
      let start = -1;
      let delimiter = '';
      let display = false;
      for (let index = cursor; index < source.length; index += 1) {
        if (source[index] === '\\') {
          index += 1;
          continue;
        }
        if (source.startsWith('$$', index)) {
          start = index;
          delimiter = '$$';
          display = true;
          break;
        }
        if (source[index] === '$') {
          start = index;
          delimiter = '$';
          break;
        }
      }
      if (start < 0) {
        if (cursor < source.length) parts.push({ type: 'text', value: source.slice(cursor) });
        break;
      }
      if (start > cursor) parts.push({ type: 'text', value: source.slice(cursor, start) });
      const close = findClosingMath(source, delimiter, start + delimiter.length);
      if (close < 0) {
        parts.push({ type: 'text', value: source.slice(start) });
        break;
      }
      parts.push({
        type: 'math',
        value: source.slice(start + delimiter.length, close),
        display
      });
      cursor = close + delimiter.length;
    }
    return parts;
  }

  function renderMathNode(container, tex, displayMode) {
    const host = document.createElement(displayMode ? 'div' : 'span');
    host.className = displayMode ? 'math-display' : 'math-inline';
    const prepared = String(tex ?? '').trim();
    if (!prepared) return;
    try {
      if (!window.katex || typeof window.katex.render !== 'function') throw new Error('KaTeX unavailable');
      window.katex.render(prepared, host, {
        displayMode,
        throwOnError: false,
        strict: 'ignore',
        trust: false,
        output: 'htmlAndMathml'
      });
      host.setAttribute('data-tex', prepared);
      container.appendChild(host);
    } catch (_) {
      host.classList.add('math-fallback');
      host.textContent = displayMode ? prepared : `$${prepared}$`;
      container.appendChild(host);
    }
  }

  function renderRichText(container, text, options = {}) {
    const source = String(text ?? '');
    const parts = splitMathText(source);
    const hasMath = parts.some((part) => part.type === 'math');
    if (options.inlineFallback && !hasMath) {
      const prepared = source
        .replace(/\\([()\[\]])/g, '')
        .replace(/([\u4e00-\u9fff]+)/g, '\\text{$1}')
        .trim();
      renderMathNode(container, prepared, false);
      return;
    }
    if (options.displayFallback && parts.length === 1 && parts[0].type === 'math') {
      renderMathNode(container, parts[0].value, true);
      return;
    }
    if (!hasMath && options.displayFallback) {
      const prepared = source
        .replace(/\\([()\[\]])/g, '')
        .replace(/([\u4e00-\u9fff]+)/g, '\\text{$1}')
        .trim();
      renderMathNode(container, prepared, true);
      return;
    }
    parts.forEach((part) => {
      if (part.type === 'math') renderMathNode(container, part.value, part.display);
      else if (part.value) container.appendChild(document.createTextNode(part.value));
    });
  }

  function svgElement(tag, attributes = {}) {
    const element = document.createElementNS('http://www.w3.org/2000/svg', tag);
    Object.entries(attributes).forEach(([key, value]) => {
      if (value !== undefined && value !== null) element.setAttribute(key, String(value));
    });
    return element;
  }

  function safePaint(value, fallback) {
    if (typeof value !== 'string') return fallback;
    if (/^#[0-9a-f]{3,8}$/i.test(value)) return value;
    if (/^rgba?\([0-9.,\s%]+\)$/i.test(value)) return value;
    return fallback;
  }

  function renderOptions() {
    elements.optionsGrid.replaceChildren();
    lesson.problem.options.forEach((option) => {
      const button = make('button', 'option');
      button.type = 'button';
      button.dataset.option = option.key;
      const key = make('span', 'option-key', option.key);
      const text = make('span', '');
      renderRichText(text, option.text);
      button.append(key, text);
      elements.optionsGrid.appendChild(button);
    });
  }

  function updateOptions(revealAnswer) {
    if (!lesson.problem.options.length) {
      elements.studentFeedback.replaceChildren();
      if (!revealAnswer) {
        elements.studentFeedback.textContent = '先独立思考，再跟随板书推导。';
        elements.studentFeedback.dataset.answerRevealed = 'false';
        return;
      }
      const answer = lesson.problem.finalAnswer || lesson.scenes[state.sceneIndex]?.narration || '请看本步板书';
      elements.studentFeedback.appendChild(make('strong', '', '结论：'));
      renderRichText(elements.studentFeedback, answer, { inlineFallback: true });
      elements.studentFeedback.dataset.answerRevealed = String(Boolean(lesson.problem.finalAnswer));
      return;
    }
    elements.optionsGrid.querySelectorAll('.option').forEach((button) => {
      const key = button.dataset.option;
      button.classList.toggle('selected', state.chosen === key);
      button.classList.remove('is-correct', 'is-wrong');
      if (!revealAnswer) return;
      button.classList.add(correctOptions.has(key) ? 'is-correct' : 'is-wrong');
    });

    if (!revealAnswer) {
      elements.studentFeedback.textContent = state.chosen
        ? `你选了 ${state.chosen}，先记住判断，继续听老师分析。`
        : '你可以先点选一个答案，老师公布答案时会一起判断。';
      return;
    }

    const answer = [...correctOptions].join('');
    if (state.chosen && correctOptions.has(state.chosen)) {
      elements.studentFeedback.textContent = `老师公布答案：${answer}。你选了 ${state.chosen}，判断正确。`;
    } else if (state.chosen) {
      elements.studentFeedback.textContent = `你选了 ${state.chosen}，正确答案是 ${answer}。请重点看老师对错误选项的分析。`;
    } else {
      elements.studentFeedback.textContent = `老师公布答案：${answer}。`;
    }
  }

  function renderSegment(segment) {
    if (segment.type === 'text') return make('span', '', segment.value);
    if (segment.type === 'accent') return make('span', 'accent', segment.value);
    if (segment.type === 'sub') {
      const wrapper = make('span');
      wrapper.append(make('span', 'math-base', segment.base || ''), make('span', 'math-sub', segment.value || ''));
      return wrapper;
    }
    if (segment.type === 'sup') {
      const wrapper = make('span');
      wrapper.append(make('span', 'math-base', segment.base || ''), make('span', 'math-sup', segment.value || ''));
      return wrapper;
    }
    if (segment.type === 'fraction') {
      const wrapper = make('span', 'math-fraction');
      wrapper.append(make('span', 'math-fraction-top', segment.numerator), make('span', 'math-fraction-bottom', segment.denominator));
      return wrapper;
    }
    if (segment.type === 'sqrt') {
      const wrapper = make('span', 'math-sqrt');
      wrapper.append(make('span', 'math-sqrt-symbol', '√('), make('span', '', segment.value), make('span', '', ')'));
      return wrapper;
    }
    return make('span', '', segment.value || '');
  }

  function renderFormulaBoard(scene) {
    elements.formulaBoard.replaceChildren();
    if (scene.formulaLines?.length) {
      scene.formulaLines.forEach((line) => {
        const lineElement = make('div', 'math-line');
        const textSegments = line.segments.filter((segment) => segment.type === 'text');
        if (textSegments.length === line.segments.length) {
          renderRichText(
            lineElement,
            textSegments.map((segment) => segment.value || '').join(''),
            { displayFallback: true }
          );
        } else {
          line.segments.forEach((segment) => {
            if (segment.type === 'text') renderRichText(lineElement, segment.value || '');
            else lineElement.appendChild(renderSegment(segment));
          });
        }
        if (line.note) {
          const note = make('span', 'math-note');
          renderRichText(note, line.note);
          lineElement.appendChild(note);
        }
        elements.formulaBoard.appendChild(lineElement);
      });
      return;
    }

    if (scene.comparisonRows?.length) {
      scene.comparisonRows.forEach((row) => {
        const rowElement = make('div', 'comparison-row');
        const value = make('span', 'comparison-value');
        renderRichText(value, row.value);
        rowElement.append(make('span', 'comparison-label', row.label), value);
        if (row.reason) {
          const reason = make('span', 'comparison-reason');
          renderRichText(reason, row.reason);
          rowElement.appendChild(reason);
        }
        if (row.correct === true) rowElement.classList.add('is-correct');
        if (row.correct === false) rowElement.classList.add('is-wrong');
        elements.formulaBoard.appendChild(rowElement);
      });
      return;
    }

    elements.formulaBoard.appendChild(make('div', 'math-line muted', scene.title));
  }

  // ---- 数值柱状图：把变化太快的数值同时用条形可视化，便于肉眼对比 ----
  function renderMetricBars(scene) {
    elements.metricBoard.replaceChildren();
    if (!scene.metricBars?.length) return;
    const label = make('div', 'metric-bars-label', '实时数值');
    elements.metricBoard.appendChild(label);
    scene.metricBars.forEach((bar) => {
      const ratio = Math.max(0, Math.min(1, bar.value / bar.max));
      const track = make('div', 'metric-bar-track');
      const fill = make('div', 'metric-bar-fill');
      fill.style.width = `${Math.round(ratio * 100)}%`;
      track.appendChild(fill);
      const row = make('div', 'metric-bar');
      const valueText = bar.unit ? `${formatNumber(bar.value)} ${bar.unit}` : formatNumber(bar.value);
      row.append(
        make('span', 'metric-bar-name', bar.label),
        track,
        make('span', 'metric-bar-value', valueText)
      );
      elements.metricBoard.appendChild(row);
    });
  }

  function formatNumber(value) {
    if (!Number.isFinite(value)) return '—';
    const rounded = Math.round(value * 100) / 100;
    return String(rounded);
  }

  // ---- 点击物体 → 受力/参量面板 ----
  function openInspectPanel(scene, elementId) {
    closeInspectPanel();
    const panel = scene.inspectPanels?.find((item) => item.elementId === elementId);
    if (!panel) return;
    const overlay = make('div', 'inspect-panel');
    const titleRow = make('div', 'inspect-title');
    titleRow.append(make('span', '', panel.title), make('button', 'inspect-close', '×'));
    overlay.appendChild(titleRow);
    if (panel.forces?.length) {
      const section = make('div', 'inspect-section');
      section.appendChild(make('div', 'inspect-section-title', '受力分析'));
      panel.forces.forEach((force) => {
        const item = make('div', 'inspect-row');
        const sign = force.direction ? `${force.direction}·${formatNumber(force.magnitude)} ${force.unit}` : `${formatNumber(force.magnitude)} ${force.unit}`;
        item.append(make('span', 'inspect-key', force.name), make('span', 'inspect-val', sign));
        if (force.note) item.appendChild(make('small', 'inspect-note', force.note));
        section.appendChild(item);
      });
      overlay.appendChild(section);
    }
    if (panel.quantities?.length) {
      const section = make('div', 'inspect-section');
      section.appendChild(make('div', 'inspect-section-title', '运动参量'));
      panel.quantities.forEach((q) => {
        const item = make('div', 'inspect-row');
        const valueText = q.unit ? `${formatNumber(q.value)} ${q.unit}` : formatNumber(q.value);
        item.append(make('span', 'inspect-key', q.name), make('span', 'inspect-val', valueText));
        section.appendChild(item);
      });
      overlay.appendChild(section);
    }
    elements.inspectLayer.replaceChildren(overlay);
    overlay.querySelector('.inspect-close').addEventListener('click', closeInspectPanel);
  }

  function closeInspectPanel() {
    elements.inspectLayer.replaceChildren();
  }

  function clearDiagramArea() {
    cancelPointerTour();
    state.pointedIds = new Set();
    closeInspectPanel();
    elements.diagramArea.replaceChildren();
  }

  function createArrowMarker(defs, colorName) {
    const marker = svgElement('marker', {
      id: `arrow-${colorName}`,
      viewBox: '0 0 10 10',
      refX: 8,
      refY: 5,
      markerWidth: 7,
      markerHeight: 7,
      orient: 'auto-start-reverse'
    });
    marker.appendChild(svgElement('path', { d: 'M 0 0 L 10 5 L 0 10 z', fill: colorValues[colorName] }));
    defs.appendChild(marker);
  }

  // 基础线宽按图元类型推断，供“当前步骤矢量加粗”使用（不改动默认外观）。
  function strongStrokeWidth(element) {
    const base = element.type === 'arrow'
      ? 4
      : (typeof element.width === 'number' ? element.width : (element.type === 'polygon' || element.type === 'rect' ? 1 : 2));
    const factor = element.type === 'arrow' ? 1.9 : 1.7;
    return Math.min(12, Math.max(3, Number((base * factor).toFixed(1))));
  }

  function renderDiagramElement(element, plan, activeIds, svg) {
    const color = colorValues[element.color] || colorValues.chalk;
    const clickable = (plan.scenes || []).some((scene) => (scene.inspectPanels || []).some((panel) => panel.elementId === element.id));
    const group = svgElement('g', {
      class: ['diagram-element', ['line', 'polygon', 'polyline', 'arrow'].includes(element.type) ? 'draw-element' : '', activeIds.includes(element.id) ? 'is-active' : '', clickable ? 'is-clickable' : ''].filter(Boolean).join(' '),
      'data-element-id': element.id,
      style: `--element-color:${color};--element-width-strong:${strongStrokeWidth(element)}px`
    });

    if (element.type === 'point') {
      group.appendChild(svgElement('circle', { cx: element.x, cy: element.y, r: element.radius, fill: color, stroke: color }));
      if (element.label) {
        const label = svgElement('text', {
          x: element.x + (element.labelDx || 18),
          y: element.y + (element.labelDy || -16),
          fill: color,
          class: 'diagram-label'
        });
        label.textContent = element.label;
        group.appendChild(label);
      }
    } else if (element.type === 'polygon') {
      group.appendChild(svgElement('polygon', {
        points: element.points.map((point) => `${point.x},${point.y}`).join(' '),
        fill: safePaint(element.fill, 'rgba(255,255,255,0.025)'),
        stroke: color
      }));
    } else if (element.type === 'polyline') {
      group.appendChild(svgElement('polyline', {
        points: element.points.map((point) => `${point.x},${point.y}`).join(' '),
        fill: 'none',
        stroke: color,
        'stroke-width': element.width,
        'stroke-linecap': 'round',
        'stroke-linejoin': 'round'
      }));
    } else if (element.type === 'line') {
      group.appendChild(svgElement('line', {
        x1: element.x1,
        y1: element.y1,
        x2: element.x2,
        y2: element.y2,
        stroke: color,
        'stroke-width': element.width,
        'stroke-dasharray': element.dashed ? '10 8' : undefined,
        'stroke-linecap': 'round'
      }));
    } else if (element.type === 'arrow') {
      group.appendChild(svgElement('line', {
        x1: element.x1,
        y1: element.y1,
        x2: element.x2,
        y2: element.y2,
        stroke: color,
        'stroke-width': 4,
        'stroke-dasharray': element.dashed ? '10 8' : undefined,
        'stroke-linecap': 'round',
        'marker-end': `url(#arrow-${element.color})`
      }));
      if (element.label) {
        const label = svgElement('text', {
          x: (element.x1 + element.x2) / 2 + (element.labelDx || 0),
          y: (element.y1 + element.y2) / 2 - 14 + (element.labelDy || 0),
          fill: color,
          class: 'diagram-label'
        });
        label.textContent = element.label;
        group.appendChild(label);
      }
    } else if (element.type === 'label') {
      const label = svgElement('text', { x: element.x, y: element.y, fill: color, 'font-size': element.size, class: 'diagram-label' });
      label.textContent = element.text;
      group.appendChild(label);
    } else if (element.type === 'rect') {
      group.appendChild(svgElement('rect', {
        x: element.x,
        y: element.y,
        width: element.width,
        height: element.height,
        rx: element.radius,
        fill: safePaint(element.fill, 'rgba(255,255,255,0.025)'),
        stroke: color
      }));
    }

    svg.appendChild(group);
  }

  // ---- 模拟鼠标：像真实老师一样把学生的注意力带到关键对象上 ----
  function anchorOfElement(element) {
    if (!element) return undefined;
    if (element.type === 'point' || element.type === 'label') return { x: element.x, y: element.y };
    if (element.type === 'rect') return { x: element.x + element.width / 2, y: element.y + element.height / 2 };
    if (element.type === 'line' || element.type === 'arrow') return { x: (element.x1 + element.x2) / 2, y: (element.y1 + element.y2) / 2 };
    if (element.type === 'polygon' || element.type === 'polyline') {
      if (!element.points || !element.points.length) return undefined;
      const sum = element.points.reduce((acc, point) => ({ x: acc.x + point.x, y: acc.y + point.y }), { x: 0, y: 0 });
      return { x: sum.x / element.points.length, y: sum.y / element.points.length };
    }
    return undefined;
  }

  function clampPointerPoint(point, viewBox) {
    const [maxX, maxY] = viewBox;
    return { x: clamp(point.x, 58, Math.max(58, maxX - 58)), y: clamp(point.y, 66, Math.max(66, maxY - 70)) };
  }

  function describeGuidanceStops(scene, elementMap, viewBox) {
    const entries = [];
    (scene.focusPath || []).forEach((point) => entries.push({ point, ids: [] }));
    if (!entries.length) {
      (scene.activeElementIds || []).forEach((id) => {
        const anchor = anchorOfElement(elementMap.get(id));
        if (anchor) entries.push({ point: anchor, ids: [id] });
      });
    }
    if (!entries.length && scene.focus) entries.push({ point: scene.focus, ids: [] });
    const activeAnchors = (scene.activeElementIds || [])
      .map((id) => ({ id, anchor: anchorOfElement(elementMap.get(id)) }))
      .filter((item) => item.anchor);
    const nearestActiveId = (point) => {
      let best;
      let bestDistance = Infinity;
      activeAnchors.forEach((item) => {
        const distance = Math.hypot(item.anchor.x - point.x, item.anchor.y - point.y);
        if (distance < bestDistance) { bestDistance = distance; best = item.id; }
      });
      return bestDistance <= 260 ? best : undefined;
    };
    const stops = [];
    entries.forEach((entry) => {
      const point = clampPointerPoint(entry.point, viewBox);
      if (stops.some((item) => Math.abs(item.x - point.x) < 20 && Math.abs(item.y - point.y) < 20)) return;
      const ids = entry.ids.length ? entry.ids : [nearestActiveId(point)].filter(Boolean);
      stops.push({ x: point.x, y: point.y, ids });
    });
    return stops.slice(0, 6);
  }

  // 指针点过的对象在本场景内持续保持高亮（累积而不被下一个落点清掉），
  // 场景切换时重建 SVG 并由 startPointerTour 重置集合。
  function markPointedElements(ids) {
    (ids || []).forEach((id) => state.pointedIds.add(id));
    document.querySelectorAll('#diagram .diagram-element.is-pointed').forEach((node) => node.classList.remove('is-pointed'));
    state.pointedIds.forEach((id) => {
      const node = document.querySelector(`#diagram [data-element-id="${id}"]`);
      if (node) node.classList.add('is-pointed');
    });
  }

  function pulsePointer(pointer) {
    const ripple = pointer.querySelector('.pointer-ripple');
    if (!ripple) return;
    ripple.classList.remove('is-pulsing');
    void ripple.getBoundingClientRect();
    ripple.classList.add('is-pulsing');
  }

  function cancelPointerTour() {
    state.pointerToken += 1;
    state.pointerTimers.forEach((id) => window.clearTimeout(id));
    state.pointerTimers = [];
  }

  function startPointerTour(pointer, scene, elementMap, viewBox) {
    cancelPointerTour();
    const token = state.pointerToken;
    const stops = describeGuidanceStops(scene, elementMap, viewBox);
    state.pointedIds = new Set();
    // 即使本步没有指点目标，也先把指针放到画布安全位置，避免停留在 SVG 左上角越界。
    const fallback = clampPointerPoint({ x: viewBox[0] / 2, y: viewBox[1] / 2 }, viewBox);
    const start = state.pointerPos ? clampPointerPoint(state.pointerPos, viewBox) : (stops[0] || fallback);
    state.pointerPos = start;
    pointer.style.transform = `translate(${start.x}px, ${start.y}px)`;
    if (!stops.length) { pointer.style.opacity = '0'; return; }
    pointer.style.opacity = '1';
    const later = (fn, delay) => { const id = window.setTimeout(fn, delay); state.pointerTimers.push(id); return id; };
    const total = clamp(scene.durationHintMs || 5000, 2600, 30000);
    const dwell = clamp(Math.round(total / (stops.length + 0.8)), 1100, 4600);
    const step = (index) => {
      if (token !== state.pointerToken) return;
      const stop = stops[index];
      state.pointerPos = stop;
      pointer.style.transform = `translate(${stop.x}px, ${stop.y}px)`;
      later(() => { if (token !== state.pointerToken) return; pulsePointer(pointer); markPointedElements(stop.ids); }, 560);
      later(() => { if (token !== state.pointerToken) return; if (index + 1 < stops.length) step(index + 1); }, 560 + dwell);
    };
    window.requestAnimationFrame(() => step(0));
  }

  function renderDiagram(sceneIndex) {
    const activeScene = lesson.scenes[sceneIndex];
    const activeIds = activeScene.activeElementIds || [];
    const [viewWidth, viewHeight] = lesson.diagram.viewBox || [960, 580];
    const svg = svgElement('svg', {
      id: 'diagram',
      viewBox: `0 0 ${viewWidth} ${viewHeight}`,
      role: 'img',
      'aria-label': lesson.diagram.imageAlt || '题目图形与老师板书'
    });

    const defs = svgElement('defs');
    Object.keys(colorValues).forEach((colorName) => createArrowMarker(defs, colorName));
    svg.appendChild(defs);

    if (lesson.diagram.mode === 'image' && lesson.diagram.imageDataUrl) {
      svg.appendChild(svgElement('image', {
        href: lesson.diagram.imageDataUrl,
        x: 0,
        y: 0,
        width: viewWidth,
        height: viewHeight,
        preserveAspectRatio: 'xMidYMid meet'
      }));
    }

    const baseElements = lesson.diagram.baseElements || [];
    const baseIds = new Set(baseElements.map((element) => element.id));
    const accumulated = new Map(baseElements.map((element) => [element.id, element]));
    for (let index = 0; index <= sceneIndex; index += 1) {
      (lesson.scenes[index].diagramElements || []).forEach((element) => {
        if (!baseIds.has(element.id)) accumulated.set(element.id, element);
      });
    }
    accumulated.forEach((element) => renderDiagramElement(element, lesson, activeIds, svg));

    // 兜底：inspectPanels 引用了渲染树上不存在的 elementId 时（模型没画对应图元），
    // 用该场景第一个分析矢量的起点（物体质心）挂一个可点击的热区，保证受力面板能打开。
    const renderedIds = new Set(accumulated.keys());
    const missingInspectIds = new Set();
    (activeScene.inspectPanels || []).forEach((panel) => {
      if (!renderedIds.has(panel.elementId)) missingInspectIds.add(panel.elementId);
    });
    if (missingInspectIds.size) {
      const anchor = (Array.from(accumulated.values())).find((el) => el.layer === 'analysis' && (el.type === 'arrow' || el.type === 'line') && el.x1 !== undefined && el.y1 !== undefined);
      missingInspectIds.forEach((elementId) => {
        const group = svgElement('g', {
          class: 'diagram-element is-clickable is-inspect-anchor',
          'data-element-id': elementId
        });
        const cx = anchor ? anchor.x1 : viewWidth / 2;
        const cy = anchor ? anchor.y1 : viewHeight / 2;
        group.appendChild(svgElement('circle', {
          cx,
          cy,
          r: 18,
          fill: 'transparent',
          stroke: 'none'
        }));
        svg.appendChild(group);
      });
    }

    const pointer = svgElement('g', { id: 'teacherPointer', class: 'teacher-pointer is-visible' });
    pointer.appendChild(svgElement('circle', { class: 'pointer-ripple', cx: 4, cy: 5, r: 7 }));
    pointer.appendChild(svgElement('path', {
      class: 'pointer-arrow',
      d: 'M 0 0 L 0 35 L 9 27 L 17 45 L 26 41 L 18 24 L 32 24 Z',
      fill: '#ffd166',
      stroke: '#2c2515',
      'stroke-width': 2
    }));
    pointer.appendChild(svgElement('circle', { class: 'pointer-dot', cx: 4, cy: 5, r: 5, fill: '#ffd166' }));
    svg.appendChild(pointer);

    elements.diagramArea.replaceChildren(svg);
    elements.diagramArea.append(elements.metricBoard, elements.inspectLayer);
    closeInspectPanel();
    svg.addEventListener('click', (event) => {
      const group = event.target.closest?.('.diagram-element');
      if (!group) return;
      openInspectPanel(activeScene, group.getAttribute('data-element-id'));
    });
    startPointerTour(pointer, activeScene, accumulated, [viewWidth, viewHeight]);
    if (activeScene.comparisonRows?.length) {
      const card = make('div', 'comparison-card');
      activeScene.comparisonRows.forEach((row) => {
        const item = make('div', 'comparison-card-row');
        item.append(make('strong', '', row.label), make('span', '', row.value));
        if (row.reason) item.appendChild(make('small', '', row.reason));
        if (row.correct === true) item.classList.add('is-correct');
        if (row.correct === false) item.classList.add('is-wrong');
        card.appendChild(item);
      });
      elements.diagramArea.appendChild(card);
    }
  }

  function renderStepList() {
    elements.stepList.replaceChildren();
    lesson.scenes.forEach((scene, index) => {
      const button = make('button', 'step-chip');
      button.type = 'button';
      const number = make('span', '', String(index + 1));
      const title = make('span', '', scene.title);
      button.append(number, title);
      button.addEventListener('click', () => jumpToStep(index));
      elements.stepList.appendChild(button);
    });
  }

  function updateStepList() {
    [...elements.stepList.children].forEach((button, index) => {
      button.classList.toggle('is-active', index === state.index);
      button.classList.toggle('is-done', index < state.index);
    });
    const active = elements.stepList.querySelector('.step-chip.is-active');
    if (active && elements.stepList.scrollHeight > elements.stepList.clientHeight) {
      active.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'smooth' });
    }
  }

  function postStatus() {
    try { window.parent.postMessage({ __lessonStudioStatus: true, index: state.index, sceneCount, isPlaying: state.isPlaying }, '*'); } catch (error) { /* 忽略跨域限制 */ }
  }

  function updatePlayButton() {
    const isLast = state.index === sceneCount - 1;
    elements.playButton.classList.toggle('is-playing', state.isPlaying);
    elements.teacherAvatar.classList.toggle('is-speaking', state.isPlaying);
    if (state.isPlaying) {
      elements.playIcon.textContent = '❚❚';
      elements.playLabel.textContent = '暂停讲课';
    } else {
      elements.playIcon.textContent = isLast && state.index !== 0 ? '↺' : '▶';
      elements.playLabel.textContent = state.index === 0 ? '开始上课' : (isLast ? '从头再讲' : '继续讲课');
    }
  }

  function updateVoiceButtons() {
    const on = state.voiceEnabled;
    [elements.voiceButton, elements.voiceTopButton].forEach((button) => button.classList.toggle('is-on', on));
    elements.voiceButton.setAttribute('aria-pressed', String(on));
    elements.voiceButton.textContent = on ? '老师语音：开' : '老师语音：关';
    elements.voiceTopButton.textContent = on ? '语音：开' : '语音：关';
  }

  function renderStep(index, options = {}) {
    state.index = clamp(index, 0, sceneCount - 1);
    const scene = lesson.scenes[state.index];
    const progress = ((state.index + 1) / sceneCount) * 100;

    document.title = lesson.title;
    elements.lessonTitle.textContent = lesson.title;
    elements.lessonSubject.textContent = lesson.subject || '题目讲解';
    elements.lessonTopic.textContent = lesson.difficulty ? `${lesson.grade || ''} · ${lesson.difficulty}`.replace(/^ · /, '') : (lesson.grade || '互动讲题');
    elements.questionText.replaceChildren();
    renderRichText(elements.questionText, lesson.problem.stem);
    elements.answerLine.replaceChildren();
    renderRichText(
      elements.answerLine,
      scene.type === 'question'
        ? '先自己想一想：这道题应该从哪里开始分析？'
        : '跟着老师的指点和板书，一步一步看清楚。'
    );
    elements.stepCounter.textContent = `第 ${state.index + 1} / ${sceneCount} 步`;
    elements.stepTitle.textContent = scene.title;
    elements.stepText.replaceChildren();
    renderRichText(elements.stepText, scene.narration);
    elements.tipBoard.replaceChildren();
    const tipStrong = make('strong', '', '老师提示：');
    elements.tipBoard.appendChild(tipStrong);
    renderRichText(
      elements.tipBoard,
      scene.tip || '关键步骤要同时检查定义域、等价变形和取等条件。'
    );
    const hasDiagram =
      Boolean(lesson.diagram.imageDataUrl) ||
      (lesson.diagram.baseElements || []).length > 0 ||
      (scene.diagramElements || []).length > 0;
    elements.derivationColumn.classList.toggle('formula-only', !hasDiagram);
    elements.progressText.textContent = `${state.index + 1} / ${sceneCount}`;
    elements.progressBar.style.width = `${progress}%`;
    elements.topStepCounter.textContent = `${state.index + 1} / ${sceneCount}`;
    elements.prevButton.disabled = state.index === 0;
    elements.topPrevButton.disabled = state.index === 0;
    elements.nextButton.disabled = state.index === sceneCount - 1;
    elements.topNextButton.disabled = state.index === sceneCount - 1;

    restartAnimation(elements.stepTitle);
    restartAnimation(elements.stepText);
    restartAnimation(elements.formulaBoard);

    renderFormulaBoard(scene);
    renderMetricBars(scene);
    if (hasDiagram) renderDiagram(state.index);
    else clearDiagramArea();
    updateStepList();
    updateOptions(scene.revealAnswer || state.index === sceneCount - 1);
    updatePlayButton();

    if (options.teach) startTeacherSpeech();
    window.__LESSON_CURRENT_STEP__ = state.index;
  }

  function getChineseVoice() {
    if (!('speechSynthesis' in window)) return null;
    const voices = window.speechSynthesis.getVoices();
    return voices.find((voice) => /^zh(-|_)/i.test(voice.lang)) || null;
  }

  function cancelSpeech() {
    state.speechToken += 1;
    if ('speechSynthesis' in window) window.speechSynthesis.cancel();
  }

  function clearTimer() {
    window.clearTimeout(state.timer);
    state.timer = null;
  }

  function queueAdvance(delay) {
    clearTimer();
    if (!state.isPlaying) return;
    state.timer = window.setTimeout(() => {
      if (!state.isPlaying) return;
      if (state.index < sceneCount - 1) renderStep(state.index + 1, { teach: true });
      else stopLesson();
    }, Math.max(0, delay / state.speed));
  }

  function startTeacherSpeech() {
    clearTimer();
    cancelSpeech();
    if (!state.isPlaying) return;
    const scene = lesson.scenes[state.index];
    const token = state.speechToken;

    if (state.voiceEnabled && 'speechSynthesis' in window && 'SpeechSynthesisUtterance' in window) {
      const utterance = new SpeechSynthesisUtterance(scene.narration);
      const voice = getChineseVoice();
      utterance.lang = lesson.teacher.voiceLang || 'zh-CN';
      utterance.rate = clamp(0.96 * state.speed, 0.72, 1.45);
      utterance.pitch = 1.02;
      if (voice) utterance.voice = voice;
      utterance.onend = () => { if (token === state.speechToken) { clearTimer(); queueAdvance(700); } };
      utterance.onerror = () => { if (token === state.speechToken) { clearTimer(); queueAdvance(1200); } };
      // 语音合成在无声音、被浏览器挂起或没有中文语音时可能永远不触发 onend，
      // 用一个按字数估算的兜底计时器保证讲课不会卡死。
      const watchdog = clamp(2600 + (scene.narration || '').length * 230, 4000, 40000) / state.speed;
      state.timer = window.setTimeout(() => { if (token === state.speechToken) queueAdvance(0); }, watchdog);
      window.speechSynthesis.speak(utterance);
      return;
    }

    const duration = clamp(scene.durationHintMs || 5000, 1800, 30000) / state.speed;
    state.timer = window.setTimeout(() => { if (token === state.speechToken) queueAdvance(0); }, duration);
  }

  function startLesson() {
    cancelSpeech();
    clearTimer();
    if (state.index >= sceneCount - 1) {
      state.index = 0;
      renderStep(0);
    }
    state.isPlaying = true;
    updatePlayButton();
    postStatus();
    startTeacherSpeech();
  }

  function pauseLesson() {
    state.isPlaying = false;
    clearTimer();
    cancelSpeech();
    updatePlayButton();
    postStatus();
  }

  function stopLesson() {
    state.isPlaying = false;
    clearTimer();
    cancelSpeech();
    updatePlayButton();
    postStatus();
  }

  function toggleLesson() {
    if (state.isPlaying) pauseLesson(); else startLesson();
  }

  function jumpToStep(index) {
    const wasPlaying = state.isPlaying;
    clearTimer();
    cancelSpeech();
    renderStep(index);
    if (wasPlaying) {
      state.isPlaying = true;
      updatePlayButton();
      startTeacherSpeech();
    }
  }

  function stepForward() {
    if (state.index >= sceneCount - 1) { pauseLesson(); return; }
    const wasPlaying = state.isPlaying;
    clearTimer();
    cancelSpeech();
    renderStep(state.index + 1);
    if (wasPlaying) startTeacherSpeech();
  }

  function stepBack() {
    const wasPlaying = state.isPlaying;
    clearTimer();
    cancelSpeech();
    renderStep(state.index - 1);
    if (wasPlaying) startTeacherSpeech();
  }

  function replayLesson() {
    pauseLesson();
    state.chosen = null;
    renderStep(0);
    window.setTimeout(() => {
      state.isPlaying = true;
      updatePlayButton();
      startTeacherSpeech();
    }, 160);
  }

  function toggleVoice() {
    state.voiceEnabled = !state.voiceEnabled;
    updateVoiceButtons();
    if (state.isPlaying) startTeacherSpeech();
    else if (!state.voiceEnabled) cancelSpeech();
  }

  // 全屏黑板。
  //
  // 真实故障：讲解 HTML 在 App 里是经 iframe 内嵌播放的，宿主 iframe 若没有显式放行
  // fullscreen（allow="fullscreen"），子帧的 document.fullscreenEnabled 就是 false，
  // requestFullscreen() 会被权限策略直接拒掉——按钮点了毫无反应、也没有任何提示。
  // 所以这里不再“调用一下就完事”：失败要接住，把原因回传给宿主页面（App 据此提示），
  // 并在按钮上短暂显示「被拦截」，不留下静默失效的功能。
  function fullscreenElement() {
    return document.fullscreenElement || document.webkitFullscreenElement || null;
  }

  function requestFullscreen(target) {
    const request = target.requestFullscreen || target.webkitRequestFullscreen;
    if (typeof request !== 'function') return Promise.reject(new Error('当前浏览器不支持全屏 API'));
    if (document.fullscreenEnabled === false) return Promise.reject(new Error('当前页面或内嵌窗口没有放行全屏权限'));
    try { return Promise.resolve(request.call(target)); }
    catch (error) { return Promise.reject(error); }
  }

  function exitFullscreen() {
    const exit = document.exitFullscreen || document.webkitExitFullscreen;
    if (typeof exit !== 'function') return Promise.resolve();
    try { return Promise.resolve(exit.call(document)); }
    catch (error) { return Promise.resolve(); }
  }

  function notifyHostFullscreen(kind, reason) {
    if (!window.parent || window.parent === window) return;
    if (typeof window.parent.postMessage !== 'function') return;
    try {
      window.parent.postMessage({ __lessonStudioStatus: true, fullscreen: kind, reason: reason || '', index: state.index, sceneCount, isPlaying: state.isPlaying }, '*');
    } catch (error) { /* 宿主不可达时忽略：全屏本身已经处理完了 */ }
  }

  function updateFullscreenButton() {
    if (!elements.fullscreenButton) return;
    elements.fullscreenButton.textContent = fullscreenElement() ? '退出全屏' : '全屏黑板';
  }

  function reportFullscreenBlocked(reason) {
    if (elements.fullscreenButton) {
      elements.fullscreenButton.textContent = '全屏被拦截';
      elements.fullscreenButton.title = reason;
      window.setTimeout(() => { elements.fullscreenButton.title = ''; updateFullscreenButton(); }, 2400);
    }
    notifyHostFullscreen('blocked', reason);
  }

  function toggleFullscreen() {
    if (fullscreenElement()) {
      exitFullscreen().then(updateFullscreenButton);
      return;
    }
    requestFullscreen(elements.blackboard)
      .then(() => { updateFullscreenButton(); notifyHostFullscreen('entered', ''); })
      .catch((error) => reportFullscreenBlocked(error && error.message ? error.message : String(error)));
  }

  // 供外部页面（如 Flutter 讲解播放器）通过 postMessage 控制讲解进度。
  window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || data.__lessonStudio !== true) return;
    if (data.kind === 'play') { if (!state.isPlaying) startLesson(); }
    else if (data.kind === 'pause') { if (state.isPlaying) pauseLesson(); }
    else if (data.kind === 'toggle') toggleLesson();
    else if (data.kind === 'next') stepForward();
    else if (data.kind === 'prev') stepBack();
    else if (data.kind === 'replay') replayLesson();
    else if (data.kind === 'jump' && Number.isInteger(data.index)) jumpToStep(data.index);
    if (event.source && typeof event.source.postMessage === 'function') {
      event.source.postMessage({ __lessonStudioStatus: true, index: state.index, sceneCount, isPlaying: state.isPlaying }, '*');
    }
  });

  elements.playButton.addEventListener('click', toggleLesson);
  elements.prevButton.addEventListener('click', stepBack);
  elements.nextButton.addEventListener('click', stepForward);
  elements.topPrevButton.addEventListener('click', stepBack);
  elements.topNextButton.addEventListener('click', stepForward);
  elements.replayButton.addEventListener('click', replayLesson);
  elements.fullscreenButton.addEventListener('click', toggleFullscreen);
  elements.voiceButton.addEventListener('click', toggleVoice);
  elements.voiceTopButton.addEventListener('click', toggleVoice);
  elements.speedSelect.addEventListener('change', (event) => {
    state.speed = Number(event.target.value) || 1;
    if (state.isPlaying) startTeacherSpeech();
  });
  elements.optionsGrid.addEventListener('click', (event) => {
    const option = event.target.closest('.option');
    if (!option) return;
    state.chosen = option.dataset.option;
    updateOptions(state.index === sceneCount - 1 || lesson.scenes[state.index].revealAnswer);
  });
  document.addEventListener('fullscreenchange', updateFullscreenButton);
  // Edge/Chrome 老版本只发前缀事件，也要跟一下按钮文案。
  document.addEventListener('webkitfullscreenchange', updateFullscreenButton);
  document.addEventListener('keydown', (event) => {
    const isControl = event.target.closest('button, select, input, textarea');
    if (isControl && event.code === 'Space') return;
    if (event.code === 'Space') { event.preventDefault(); toggleLesson(); }
    else if (event.key === 'ArrowRight') { event.preventDefault(); stepForward(); }
    else if (event.key === 'ArrowLeft') { event.preventDefault(); stepBack(); }
    else if (event.key.toLowerCase() === 'r') replayLesson();
    else if (event.key.toLowerCase() === 'f') toggleFullscreen();
  });

  renderOptions();
  renderStepList();
  updateVoiceButtons();
  renderStep(0);
  window.__LESSON_READY__ = true;
  window.__LESSON_RENDER_STEP__ = renderStep;
  // 供离线回归测试直接触发全屏开关（浏览器测试不依赖按钮点击）。
  window.__LESSON_TOGGLE_FULLSCREEN__ = toggleFullscreen;
})();
