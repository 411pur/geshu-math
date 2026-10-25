import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, readFileSync, rmSync} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {PassThrough} from 'node:stream';
import {createRunLog, runLogFileName} from './run-log.mjs';

test('run logs use a timestamped Windows-safe filename', () => {
  const name = runLogFileName(new Date('2026-10-25T10:20:30.123Z'));
  assert.equal(name, 'lesson-engine.2026-10-25T10-20-30-123Z.log');
});

test('run logger mirrors startup and engine output to disk', async () => {
  const root = mkdtempSync(path.join(os.tmpdir(), 'geshu-run-log-'));
  try {
    const stdout = [];
    const stderr = [];
    const log = createRunLog({
      root,
      now: new Date('2026-10-25T10:20:30.123Z'),
      stdout: {write: (chunk) => stdout.push(String(chunk))},
      stderr: {write: (chunk) => stderr.push(String(chunk))}
    });
    log.info('starting');
    log.error('failed');
    const child = new PassThrough();
    const childOutput = [];
    log.pipe(child, {write: (chunk) => childOutput.push(String(chunk))});
    child.write('engine output\n');
    await new Promise((resolve) => setImmediate(resolve));

    const content = readFileSync(log.filePath, 'utf8');
    assert.match(log.filePath, /build[\\/]local-stack-logs[\\/]lesson-engine\./);
    assert.match(content, /\[startup\] starting/);
    assert.match(content, /\[startup-error\] failed/);
    assert.match(content, /engine output/);
    assert.deepEqual(stdout, ['[2026-10-25T10:20:30.123Z] [startup] starting\n']);
    assert.deepEqual(stderr, ['[2026-10-25T10:20:30.123Z] [startup-error] failed\n']);
    assert.deepEqual(childOutput, ['engine output\n']);
  } finally {
    rmSync(root, {recursive: true, force: true});
  }
});