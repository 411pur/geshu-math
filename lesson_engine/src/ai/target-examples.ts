import type { LessonPlan } from '../schemas/lesson.js';
export const diagramConventionsText = '画布为 960×580；原题对象放 diagram.baseElements，layer=base；辅助线放当前场景 diagramElements，layer=analysis。id 在同一场景唯一，跨场景复用表示更新。高亮对象写 activeElementIds。图形外观不是证明依据。';
function scene(type: LessonPlan['scenes'][number]['type'], title:string, narration:string, formula=''): LessonPlan['scenes'][number] {
 return {type,title,narration,tip:'检查每一步的依据',formulaLines:formula?[{segments:[{type:'text',value:formula}]}]:[],comparisonRows:[],inspectPanels:[],metricBars:[],diagramElements:[],activeElementIds:[],revealAnswer:type==='answer',durationHintMs:6000};
}
const algebra: LessonPlan = {
 schemaVersion:'1.0',title:'一元二次方程：求根与检验',subject:'数学',grade:'初中',difficulty:'基础',
 problem:{stem:'解方程 x² - 5x + 6 = 0',options:[],correctOptions:[],sourceAnswer:'',sourceExplanation:''},
 teacher:{displayName:'数学老师',voiceLang:'zh-CN'},diagram:{mode:'none',viewBox:[960,580],baseElements:[]},
 scenes:[scene('question','明确目标','求所有满足方程的实数。'),scene('formula','因式分解','两数之和为五、积为六，选二与三。','(x - 2)(x - 3) = 0'),scene('formula','零积性质','至少一个因式等于零。','x - 2 = 0 或 x - 3 = 0'),scene('answer','代回检验','分别代入原方程均成立，无增根漏根。','x = 2 或 x = 3')]
};
const geometry: LessonPlan = {...algebra,title:'等腰三角形：辅助线与勾股定理',
 problem:{stem:'三角形 ABC 中 AB=AC=5，BC=6，求面积。',options:[],correctOptions:[],sourceAnswer:'',sourceExplanation:''},
 diagram:{mode:'svg',viewBox:[960,580],baseElements:[
 {type:'polygon',id:'base_triangle',layer:'base',points:[{x:480,y:100},{x:240,y:420},{x:720,y:420}],color:'chalk'},
 {type:'point',id:'p1',layer:'base',x:480,y:100,radius:5,label:'A',color:'yellow'},
 {type:'point',id:'p2',layer:'base',x:240,y:420,radius:5,label:'B',color:'yellow'},
 {type:'point',id:'p3',layer:'base',x:720,y:420,radius:5,label:'C',color:'yellow'}]},
 scenes:[scene('question','整理条件','两腰为五，底边为六。推理依据是题设而不是图形外观。'),
 {...scene('diagram','作辅助线','作 AD 垂直于 BC。由等腰三角形三线合一，BD=DC=3。'),diagramElements:[
 {type:'line',id:'aux_height',layer:'analysis',x1:480,y1:100,x2:480,y2:420,dashed:true,width:3,color:'cyan'},
 {type:'point',id:'p_d',layer:'analysis',x:480,y:420,radius:5,label:'D',color:'cyan'}],activeElementIds:['aux_height']},
 scene('formula','求高','由勾股定理，高的平方为十六，长度取正值。','AD = √(5² - 3²) = 4'),
 scene('answer','求面积','底乘高除以二，面积为十二。','S = 6 × 4 / 2 = 12')]
};
export const targetLessonPlanExamples = [geometry,algebra];
export const targetExamplesText = targetLessonPlanExamples.map((e,i)=>`目标示例 ${i+1}：\n${JSON.stringify(e)}`).join('\n\n');
