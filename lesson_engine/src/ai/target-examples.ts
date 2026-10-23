import type { LessonPlan } from '../schemas/lesson.js';
export const diagramConventionsText = '画布为 960×580；原题对象放 diagram.baseElements，layer=base；辅助线放当前场景 diagramElements，layer=analysis。id 在同一场景唯一，跨场景复用表示更新。高亮对象写 activeElementIds。图形外观不是证明依据。';
function scene(type: LessonPlan['scenes'][number]['type'], title:string, narration:string, formula='', tip='检查每一步的依据'): LessonPlan['scenes'][number] {
 return {type,title,narration,tip,formulaLines:formula?[{segments:[{type:'text',value:formula}]}]:[],comparisonRows:[],inspectPanels:[],metricBars:[],diagramElements:[],activeElementIds:[],revealAnswer:type==='answer',durationHintMs:6000};
}
const algebra: LessonPlan = {
 schemaVersion:'1.0',title:'一元二次方程：求根与检验',subject:'数学',grade:'初中',difficulty:'基础',
 problem:{stem:'解方程 x² - 5x + 6 = 0',options:[],correctOptions:[],sourceAnswer:'',sourceExplanation:''},
 teacher:{displayName:'数学老师',voiceLang:'zh-CN'},diagram:{mode:'none',viewBox:[960,580],baseElements:[]},
 scenes:[
  scene('question','明确目标','求所有满足方程的实数。','','易错：方程的解是使等式成立的数，不是因式本身'),
  scene('formula','因式分解','观察常数项为六、一次项系数为负五，寻找和为负五、积为六的两个数。','(x - 2)(x - 3) = 0','难点：先找对两个数，再检查展开是否还原'),
  scene('formula','零积性质','两个因式相乘为零，说明至少有一个因式为零。','x - 2 = 0 或 x - 3 = 0','易错：不能只写出一个根'),
  scene('answer','代回检验','分别代入原方程都成立，两个根都没有增根或漏根。','x = 2 或 x = 3','检查：两个根都要代回原方程')
 ]
};
const geometry: LessonPlan = {...algebra,title:'等腰三角形：辅助线与勾股定理',
 problem:{stem:'三角形 ABC 中 AB=AC=5，BC=6，求面积。',options:[],correctOptions:[],sourceAnswer:'',sourceExplanation:''},
 diagram:{mode:'svg',viewBox:[960,580],baseElements:[
 {type:'polygon',id:'base_triangle',layer:'base',points:[{x:480,y:100},{x:240,y:420},{x:720,y:420}],color:'chalk'},
 {type:'point',id:'p1',layer:'base',x:480,y:100,radius:5,label:'A',color:'yellow'},
 {type:'point',id:'p2',layer:'base',x:240,y:420,radius:5,label:'B',color:'yellow'},
 {type:'point',id:'p3',layer:'base',x:720,y:420,radius:5,label:'C',color:'yellow'}]},
 scenes:[
  scene('question','整理条件','两腰为五，底边为六。推理依据是题设而不是图形外观。','','已知关系来自题设，不能靠图形目测'),
  {...scene('diagram','作辅助线','为什么想到作高？等腰三角形底边上的高同时平分底边，能把斜边和半边底放进直角三角形。','','难点：先说明作高的目的，再写 BD=DC=3'),diagramElements:[
   {type:'line',id:'aux_height',layer:'analysis',x1:480,y1:100,x2:480,y2:420,dashed:true,width:3,color:'cyan'},
   {type:'point',id:'p_d',layer:'analysis',x:480,y:420,radius:5,label:'D',color:'cyan'}],activeElementIds:['aux_height']},
  scene('formula','求高','在直角三角形 ABD 中，由勾股定理求高，长度取正值。','AD = √(5² - 3²) = 4','易错：不要忘记平方和开方'),
  scene('answer','求面积','底边为六、高为四，代入三角形面积公式得到十二。','S = 6 × 4 / 2 = 12','检查：面积单位是平方单位')
 ]
};
const highSchool: LessonPlan = {...algebra,title:'三次函数在闭区间上的最值',grade:'高中',difficulty:'中等',
 problem:{stem:'求 f(x)=x³-3x 在 [-2,2] 上的最大值与最小值。',options:[],correctOptions:[],sourceAnswer:'',sourceExplanation:''},
 diagram:{mode:'none',viewBox:[960,580],baseElements:[]},
 scenes:[
  scene('question','先看闭区间','闭区间最值要同时比较驻点和端点，先记住定义域是 [-2,2]。','-2 ≤ x ≤ 2','易错：只比较极值点而漏掉端点'),
  scene('formula','求导找驻点','先求导并因式分解，得到 x=-1 和 x=1 两个驻点。','f′(x)=3(x-1)(x+1)','难点：先因式分解，再判断导数符号'),
  scene('formula','判断单调区间','导数在 [-2,-1] 为正、[-1,1] 为负、[1,2] 为正，所以 -1 是极大点，1 是极小点。','f′(x)>0 / f′(x)<0 / f′(x)>0','易错：驻点不一定是最值点'),
  scene('formula','比较候选值','把两个驻点和两个端点都代入，得到四个候选值。','f(-2)=-2，f(-1)=2，f(1)=-2，f(2)=2','计算难点：候选值要同时包含驻点和端点'),
  scene('answer','比较得结论','最大值是二，最小值是负二；端点没有被遗漏。','max = 2，min = -2','检查：最大值和最小值是否同时回答')
 ]
};
export const targetLessonPlanExamples = [geometry,algebra,highSchool];
export const targetExamplesText = targetLessonPlanExamples.map((e,i)=>`目标示例 ${i+1}：\n${JSON.stringify(e)}`).join('\n\n');
