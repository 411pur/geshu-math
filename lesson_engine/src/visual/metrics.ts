import { VisualAuditReportSchema, VisualIssueSchema } from '../schemas/visual.js';
import type { VisualAuditReport, VisualIssue } from '../schemas/visual.js';

export interface RectSnapshot {
  id: string;
  label: string;
  x: number;
  y: number;
  width: number;
  height: number;
  clientWidth: number;
  clientHeight: number;
  scrollWidth: number;
  scrollHeight: number;
}

export interface BrowserSceneSnapshot {
  sceneIndex: number;
  sceneType: string;
  viewport: { width: number; height: number };
  textBlocks: RectSnapshot[];
  diagramArea?: RectSnapshot;
  diagramElements: RectSnapshot[];
  labels: RectSnapshot[];
  pointer?: RectSnapshot;
  optionCount: number;
  expectedOptionCount: number;
  finalAnswerRevealed: boolean | null;
  hasDiagramImage: boolean;
  pageError?: string;
}

export interface AuditOptions {
  iteration: number;
  screenshots: Array<{ sceneIndex: number; file: string }>;
}

export function auditBrowserSnapshots(snapshots: BrowserSceneSnapshot[], options: AuditOptions): VisualAuditReport {
  const issues: VisualIssue[] = [];

  for (const snapshot of snapshots) {
    if (snapshot.pageError) {
      issues.push(issue('scene_render_error', 'critical', snapshot.sceneIndex, '页面脚本执行失败', '检查渲染器控制台错误', { error: snapshot.pageError }));
    }

    for (const block of snapshot.textBlocks) {
      if (block.scrollWidth > block.clientWidth + 3 || block.scrollHeight > block.clientHeight + 4) {
        issues.push(issue(
          'text_overflow',
          'warning',
          snapshot.sceneIndex,
          `文字区域溢出：${block.label}`,
          '精简讲解文字或增加可显示区域',
          { elementId: block.id, scrollWidth: block.scrollWidth, clientWidth: block.clientWidth, scrollHeight: block.scrollHeight, clientHeight: block.clientHeight }
        ));
      }
    }

    if (snapshot.diagramArea) {
      const area = snapshot.diagramArea;
      for (const element of snapshot.diagramElements) {
        if (!containsRect(area, element, 8)) {
          issues.push(issue(
            'element_out_of_bounds',
            'warning',
            snapshot.sceneIndex,
            `图元超出画布：${element.label || element.id}`,
            '把图元移回画布安全区域',
            { elementId: element.id, x: element.x, y: element.y, width: element.width, height: element.height }
          ));
        }
      }

      if (snapshot.pointer && !containsRect(area, snapshot.pointer, 0)) {
        issues.push(issue('pointer_out_of_bounds', 'warning', snapshot.sceneIndex, '老师指点位置超出画布', '调整 focus 坐标到画布内部', { x: snapshot.pointer.x, y: snapshot.pointer.y }));
      }
    }

    for (let left = 0; left < snapshot.labels.length; left += 1) {
      for (let right = left + 1; right < snapshot.labels.length; right += 1) {
        const a = snapshot.labels[left];
        const b = snapshot.labels[right];
        const overlapArea = intersectionArea(a, b);
        const threshold = Math.min(a.width * a.height, b.width * b.height) * 0.22;
        if (overlapArea > threshold) {
          issues.push(issue('element_overlap', 'warning', snapshot.sceneIndex, `标签可能重叠：${a.label} / ${b.label}`, '移动其中一个标签或减少标签数量', { firstId: a.id, secondId: b.id, overlapArea: Math.round(overlapArea) }));
        }
      }
    }

    if (snapshot.optionCount !== snapshot.expectedOptionCount) {
      issues.push(issue('option_count_mismatch', 'critical', snapshot.sceneIndex, '选项数量与讲稿不一致', '检查 options 渲染逻辑', { rendered: snapshot.optionCount, expected: snapshot.expectedOptionCount }));
    }

    if (snapshot.sceneType === 'answer' && snapshot.finalAnswerRevealed !== true) {
      issues.push(issue('answer_not_revealed', 'critical', snapshot.sceneIndex, '最终答案没有正确显示', '检查 correctOptions 和 revealAnswer 标记', {}));
    }

    if (snapshot.sceneType === 'diagram' && snapshot.diagramElements.length === 0 && !snapshot.hasDiagramImage) {
      issues.push(issue('missing_diagram', 'warning', snapshot.sceneIndex, '图形步骤没有可显示图元', '增加图形元素或把它改成公式步骤', {}));
    }
  }

  const score = calculateScore(issues);
  const hasCritical = issues.some((item) => item.severity === 'critical');
  return VisualAuditReportSchema.parse({
    iteration: options.iteration,
    score,
    passed: issues.length === 0,
    issues,
    screenshots: options.screenshots
  });
}

export function calculateScore(issues: VisualIssue[]): number {
  const penalty = issues.reduce((sum, item) => {
    if (item.severity === 'critical') return sum + 28;
    if (item.severity === 'warning') return sum + 10;
    return sum + 3;
  }, 0);
  return Math.max(0, 100 - penalty);
}

export function compareAuditReports(a: VisualAuditReport, b: VisualAuditReport): VisualAuditReport {
  return b.score > a.score ? b : a;
}

function issue(code: VisualIssue['code'], severity: VisualIssue['severity'], sceneIndex: number, message: string, suggestion: string, details: Record<string, string | number | boolean>): VisualIssue {
  return VisualIssueSchema.parse({ code, severity, sceneIndex, message, suggestion, details });
}

function containsRect(outer: RectSnapshot, inner: RectSnapshot, padding: number): boolean {
  return inner.x >= outer.x + padding && inner.y >= outer.y + padding && inner.x + inner.width <= outer.x + outer.width - padding && inner.y + inner.height <= outer.y + outer.height - padding;
}

function intersectionArea(a: RectSnapshot, b: RectSnapshot): number {
  const width = Math.max(0, Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x));
  const height = Math.max(0, Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y));
  return width * height;
}
