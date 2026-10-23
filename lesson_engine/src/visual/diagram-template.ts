/**
 * @deprecated 已移除题型模板机制。
 *
 * 图形不再按题型套写死的模板，而是把视觉识别出的几何对象重绘成矢量图。
 * 保留本文件只是为了兼容旧引用，实际实现见 `diagram-redraw.ts`。
 */
export { applyDiagramBlueprintToPlan } from './diagram-redraw.js';
