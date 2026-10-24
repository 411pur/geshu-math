import {readFileSync} from 'node:fs';
import {describe,it,expect} from 'vitest';
import {DeepSeekTutorAI} from '../src/ai/deepseek.js';
import {targetLessonPlanExamples,targetExamplesText} from '../src/ai/target-examples.js';
import {LessonPlanSchema} from '../src/schemas/lesson.js';
import {decideDiagramNeed} from '../src/visual/diagram-need.js';
import {demoteMisplacedBaseLayer,auditDiagramFidelity} from '../src/visual/diagram-fidelity.js';
import {createProblem,createPlan,createSolution} from './helpers/lesson-fixtures.js';

describe('数学学科适配',()=>{
  it('代数和几何示例均合法且不包含物理引导',()=>{
    for(const plan of targetLessonPlanExamples) {expect(LessonPlanSchema.safeParse(plan).success).toBe(true);expect(plan.subject).toBe('数学');}
    expect(targetExamplesText).not.toMatch(/受力|摩擦|重力/);
  });
  it('纯代数不画图，几何和函数图需要图示',()=>{
    expect(decideDiagramNeed(createProblem({stem:'解方程 x²-5x+6=0'})).needed).toBe(false);
    expect(decideDiagramNeed(createProblem({stem:'求等腰三角形的高'})).needed).toBe(true);
    expect(decideDiagramNeed(createProblem({stem:'画函数 y=x² 的图像'})).needed).toBe(true);
  });
  it('数学向量 a 不会被当成加速度从原图移走',()=>{
    const problem=createProblem({diagramMode:'svg',stem:'已知向量 a，求模长'});
    const plan=createPlan({diagram:{mode:'svg',viewBox:[960,580],baseElements:[{type:'arrow',id:'a',layer:'base',x1:100,y1:100,x2:300,y2:200,label:'a',color:'cyan',dashed:false}]}});
    expect(demoteMisplacedBaseLayer(plan,problem).diagram.baseElements).toHaveLength(1);
    expect(auditDiagramFidelity(plan,problem)).toEqual([]);
  });
  it('求解、排课与复核都携带数学边界条件和教学表达规范',async()=>{
    const calls:any[]=[];
    const client:any={completeStructured:async (_schema:any,options:any)=>{calls.push(options);
      if(options.schemaName==='SolutionResult') return createSolution();
      if(options.schemaName==='VerificationResult') return {ok:true,issues:[]};
      return createPlan();
    }};
    const tutor=new DeepSeekTutorAI(client,{reasoningModel:'test',fastModel:'test'});
    const problem=createProblem();const solution=createSolution();const plan=createPlan();
    await tutor.solveProblem(problem); await tutor.createLessonPlan(problem,solution); await tutor.verifyLessonPlan(problem,solution,plan);
    expect(calls).toHaveLength(3);
    for(const call of calls){
      const system=call.messages.find((m:any)=>m.role==='system').content;
      expect(system).toContain('定义域');expect(system).toContain('增根漏根');expect(system).toContain('证明题');
      expect(system).toContain('具体计算难点');expect(system).toContain('易错');expect(system).toContain('不得为了讲解流畅自行新增');
    }
    const planPrompt=calls[1].messages.find((m:any)=>m.role==='system').content;
    expect(planPrompt).toContain('思路来源');expect(planPrompt).toContain('不得自行增加未经确认');
    const verifyPrompt=calls[2].messages.find((m:any)=>m.role==='system').content;
    expect(verifyPrompt).toContain('思路来源');expect(verifyPrompt).toContain('空泛');
  });
});

it('播放器使用数学品牌标识',()=>{const html=readFileSync(new URL('../templates/teacher-board.html',import.meta.url),'utf8');expect(html).toContain('brand-badge\">数');expect(html).not.toContain('物理老师');});
