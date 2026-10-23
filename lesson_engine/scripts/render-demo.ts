import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { chromium } from 'playwright-core';
import { LocalHtmlRenderer } from '../src/render/render-lesson.js';
import { createPlan } from '../tests/helpers/lesson-fixtures.js';

const outputDir = path.join(process.cwd(), 'generated');
await mkdir(outputDir, { recursive: true });
const html = await new LocalHtmlRenderer().render(createPlan({ title: '互动讲题渲染预览' }));
const htmlPath = path.join(outputDir, 'demo.html');
const initialScreenshotPath = path.join(outputDir, 'demo.png');
const finalScreenshotPath = path.join(outputDir, 'demo-final.png');
await writeFile(htmlPath, html, 'utf8');

const browser = await chromium.launch({
  executablePath: 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  headless: true
});
const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(htmlPath).href);
await page.waitForFunction(() => Boolean((window as any).__LESSON_READY__));
await page.waitForTimeout(750);
await page.screenshot({ path: initialScreenshotPath, fullPage: true });
await page.locator('#stepList .step-chip').last().click();
await page.waitForTimeout(750);
await page.screenshot({ path: finalScreenshotPath, fullPage: true });
await browser.close();

console.log(JSON.stringify({ htmlPath, initialScreenshotPath, finalScreenshotPath }, null, 2));
