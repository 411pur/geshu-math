import type { ProblemExtract } from '../schemas/lesson.js';

export interface DiagramDecision {
  needed: boolean;
  reason: string;
}

// 物理题里一旦出现这些对象，通常必须画出受力/运动/场/电路示意，光靠文字学生看不到几何关系。
const PHYSICS_GEOMETRY_CUES = /受力|力图|受力分析|力的合成|轨道|斜面|滑轮|弹簧|摆|碰撞|连接体|传送带|圆周|简谐|波形|波|光路|折射|全反射|透镜|干涉|衍射|电场|磁场|电磁|带电|电路|电阻|电容|变压器|导轨|线圈|磁通|坐标|图线|图象|图像|棱柱|三角形|长方形|圆|小球|物块|小车|滑块|绳子|杆|杆件|支架/;
const MATH_GEOMETRY_CUES = /几何|三角形|四边形|矩形|正方形|平行四边|梯形|圆|椭圆|抛物线|双曲线|坐标|函数|图象|图像|立体|棱柱|棱锥|球|角|直线|平面|向量|轨迹|切线|交点/;
const GRAPH_CUES = /图象|图像|图线|坐标|函数图|图表/;

/**
 * 先理解题意，再决定这道题到底需不需要示意图。
 * 这一步是纯规则判断，不依赖模型，避免“该画不画”或“不该画乱画”。
 */
export function decideDiagramNeed(problem: ProblemExtract): DiagramDecision {
  const blueprint = problem.diagramBlueprint;
  const blueprintObjects = Boolean(
    blueprint && (blueprint.baseElements.length > 0 || blueprint.slots.length > 0 || blueprint.relations.length > 0)
  );
  if (blueprintObjects) {
    return { needed: true, reason: '题目已提供可重建的图形对象与几何关系' };
  }

  const text = [problem.stem, problem.diagramDescription, ...problem.options.map((option) => option.text)].join(' ');
  const subject = problem.subject || '';
  const explicitFigure = problem.diagramMode !== 'none' || problem.diagramDescription.trim().length > 0;

  if (subject.includes('物理')) {
    if (PHYSICS_GEOMETRY_CUES.test(text) || explicitFigure) {
      return { needed: true, reason: '物理题存在需要图示的物体、受力或几何关系' };
    }
    return { needed: false, reason: '纯数值计算类物理题，文字足以说明，无需示意图' };
  }

  if (subject.includes('数学')) {
    if (MATH_GEOMETRY_CUES.test(text) || explicitFigure) {
      return { needed: true, reason: '数学题存在几何对象或函数图像' };
    }
    return { needed: false, reason: '纯代数计算题，无需示意图' };
  }

  if (explicitFigure && (GRAPH_CUES.test(text) || PHYSICS_GEOMETRY_CUES.test(text) || MATH_GEOMETRY_CUES.test(text))) {
    return { needed: true, reason: '题干或图形描述包含可重建的图形对象' };
  }

  return { needed: false, reason: '题目没有图形对象，无需示意图' };
}
