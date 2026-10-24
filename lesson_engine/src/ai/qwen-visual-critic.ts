import { readFile } from 'node:fs/promises';
import { z } from 'zod';
import { VisualCritiqueSchema } from '../schemas/visual.js';
import type { LessonPlan } from '../schemas/lesson.js';
import type { VisualAuditReport, VisualCritique } from '../schemas/visual.js';
import type { StructuredChatClient } from './types.js';
import type { VisualCritic } from '../visual/types.js';

const schemaText = JSON.stringify(z.toJSONSchema(VisualCritiqueSchema), null, 2);

export class QwenVisualCritic implements VisualCritic {
  constructor(private readonly client: StructuredChatClient, private readonly model: string) {}

  async critique(plan: LessonPlan, report: VisualAuditReport, screenshotPaths: string[], iteration: number): Promise<VisualCritique> {
    const images = await Promise.all(screenshotPaths.slice(0, 8).map(async (file) => {
      const data = await readFile(file);
      return { type: 'image_url' as const, image_url: { url: `data:image/png;base64,${data.toString('base64')}` } };
    }));

    return this.client.completeStructured(VisualCritiqueSchema, {
      model: this.model,
      schemaName: 'VisualCritique',
      temperature: 0,
      maxTokens: 4000,
      messages: [
        { role: 'system', content: '你是教学页面视觉审核员。只检查文字可读性、元素拥挤、遮挡、重点不清晰和教学引导顺序，不检查答案是否正确。只输出 VisualCritique JSON。' },
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: [`迭代轮次：${iteration}`, `讲稿：${JSON.stringify(plan)}`, `本地布局报告：${JSON.stringify(report)}`, `VisualCritique JSON Schema：\n${schemaText}`, '截图片段按场景顺序给出。'].join('\n\n')
            },
            ...images
          ]
        }
      ]
    });
  }
}
