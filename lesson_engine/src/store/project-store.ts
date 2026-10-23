import { mkdir, readFile, readdir, rename, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { ProjectRecordSchema } from '../schemas/project.js';
import type { ProjectInput, ProjectRecord } from '../schemas/project.js';

const UTF8 = 'utf8';

export class ProjectStore {
  constructor(private readonly rootDir: string) {}
  async init(): Promise<void> { await mkdir(this.rootDir, { recursive: true }); }

  async create(input: ProjectInput): Promise<ProjectRecord> {
    await this.init();
    const now = new Date().toISOString();
    const record = ProjectRecordSchema.parse({ id: randomUUID(), createdAt: now, updatedAt: now, status: 'queued', stage: 'queued', progress: 0, title: '未命名题目', subject: '', input, visualStatus: 'not_checked', visualWarnings: [], renderAttempts: 0 });
    await mkdir(this.projectDir(record.id), { recursive: true });
    await this.writeRecord(record);
    return record;
  }

  async get(id: string): Promise<ProjectRecord> {
    return ProjectRecordSchema.parse(JSON.parse(await readFile(this.filePath(id, 'meta.json'), UTF8)));
  }

  async list(): Promise<ProjectRecord[]> {
    await this.init();
    const entries = await readdir(this.rootDir, { withFileTypes: true });
    const records: ProjectRecord[] = [];
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      try { records.push(await this.get(entry.name)); } catch { /* ignore partial projects */ }
    }
    return records.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  async update(id: string, patch: Partial<ProjectRecord>): Promise<ProjectRecord> {
    const current = await this.get(id);
    const next = ProjectRecordSchema.parse({ ...current, ...patch, id: current.id, createdAt: current.createdAt, updatedAt: new Date().toISOString() });
    await this.writeRecord(next);
    return next;
  }

  async reset(id: string): Promise<ProjectRecord> {
    for (const name of ['problem.json', 'solution.json', 'verification.json', 'lesson.json', 'index.html', 'render-error.txt']) {
      await rm(this.filePath(id, name), { force: true });
    }
    await rm(this.artifactPath(id, 'visual'), { recursive: true, force: true });
    return this.update(id, { status: 'queued', stage: 'queued', progress: 0, error: undefined, visualStatus: 'not_checked', visualWarnings: [], renderAttempts: 0 });
  }

  async writeJson(id: string, name: string, value: unknown): Promise<void> { await this.writeText(id, name, JSON.stringify(value, null, 2)); }
  async readJson<T>(id: string, name: string): Promise<T> { return JSON.parse(await readFile(this.filePath(id, name), UTF8)) as T; }
  async writeHtml(id: string, html: string): Promise<void> { await this.writeText(id, 'index.html', html); }
  async readHtml(id: string): Promise<string> { return readFile(this.filePath(id, 'index.html'), UTF8); }

  async saveInputImage(id: string, fileName: string, mimeType: string, data: Buffer): Promise<string> {
    const extension = extensionForMime(mimeType) || path.extname(fileName).toLowerCase() || '.img';
    const savedName = `input${extension}`;
    await this.writeBinary(id, savedName, data);
    return savedName;
  }

  async readInputImage(id: string): Promise<{ data: Buffer; mimeType: string; fileName: string } | undefined> {
    const record = await this.get(id);
    if (!record.input.imageFileName || !record.input.imageMimeType) return undefined;
    return { data: await readFile(this.filePath(id, record.input.imageFileName)), mimeType: record.input.imageMimeType, fileName: record.input.imageFileName };
  }

  async writeText(id: string, name: string, value: string): Promise<void> { await this.writeAtomic(this.filePath(id, name), value); }
  async writeBinary(id: string, name: string, value: Buffer): Promise<void> { await this.writeAtomic(this.filePath(id, name), value); }
  async writeArtifactJson(id: string, relativePath: string, value: unknown): Promise<void> { await this.writeArtifactText(id, relativePath, JSON.stringify(value, null, 2)); }
  async writeArtifactText(id: string, relativePath: string, value: string): Promise<void> { await this.writeAtomic(this.artifactPath(id, relativePath), value); }
  async writeArtifactBinary(id: string, relativePath: string, value: Buffer): Promise<void> { await this.writeAtomic(this.artifactPath(id, relativePath), value); }
  async readArtifactJson<T>(id: string, relativePath: string): Promise<T> { return JSON.parse(await readFile(this.artifactPath(id, relativePath), UTF8)) as T; }
  async readArtifactBuffer(id: string, relativePath: string): Promise<Buffer> { return readFile(this.artifactPath(id, relativePath)); }
  async artifactExists(id: string, relativePath: string): Promise<boolean> { try { await stat(this.artifactPath(id, relativePath)); return true; } catch { return false; } }

  projectDir(id: string): string { assertSafeId(id); return path.join(this.rootDir, id); }
  filePath(id: string, name: string): string { if (!/^[a-zA-Z0-9._-]+$/.test(name)) throw new Error('非法项目文件名'); return path.join(this.projectDir(id), name); }
  artifactPath(id: string, relativePath: string): string {
    const projectDir = this.projectDir(id);
    const target = path.resolve(projectDir, relativePath);
    if (target !== projectDir && !target.startsWith(projectDir + path.sep)) throw new Error('非法项目产物路径');
    return target;
  }

  private async writeAtomic(target: string, value: string | Buffer): Promise<void> {
    await mkdir(path.dirname(target), { recursive: true });
    const temp = `${target}.${randomUUID()}.tmp`;
    await writeFile(temp, value);
    await rename(temp, target);
  }
  private async writeRecord(record: ProjectRecord): Promise<void> { await this.writeJson(record.id, 'meta.json', record); }
}

function assertSafeId(id: string): void { if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) throw new Error('非法项目 ID'); }
function extensionForMime(mimeType: string): string { return ({ 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp' } as Record<string, string>)[mimeType] || ''; }
