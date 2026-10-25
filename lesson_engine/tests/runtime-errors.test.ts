import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { EventEmitter } from 'node:events';
import { afterEach, describe, expect, it } from 'vitest';
import {
  appendFatalError,
  defaultFatalErrorLogPath,
  formatFatalError,
  installFatalErrorHandlers
} from '../src/runtime-errors.js';

const tempDirs: string[] = [];
afterEach(async () => {
  await Promise.all(tempDirs.splice(0).map((dir) => rm(dir, {recursive: true, force: true})));
});

describe('fatal error logging', () => {
  it('formats timestamp, kind, pid and stack', () => {
    const text = formatFatalError('uncaughtException', new Error('boom'), {
      now: new Date('2026-10-25T10:20:30.123Z'),
      pid: 1234
    });
    expect(text).toContain('[2026-10-25T10:20:30.123Z] [uncaughtException] pid=1234');
    expect(text).toContain('Error: boom');
  });

  it('creates the log directory and appends fatal errors', async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), 'geshu-runtime-errors-'));
    tempDirs.push(root);
    const logFile = path.join(root, 'nested', 'logs', 'lesson-engine.log');
    appendFatalError(logFile, 'unhandledRejection', 'rejected promise', {
      now: new Date('2026-10-25T10:20:30.123Z'),
      pid: 77
    });
    appendFatalError(logFile, 'startupFailure', new Error('listen failed'));
    const content = await readFile(logFile, 'utf8');
    expect(content).toContain('[unhandledRejection] pid=77');
    expect(content).toContain('rejected promise');
    expect(content).toContain('[startupFailure]');
    expect(content).toContain('Error: listen failed');
  });

  it('uses the startup log path when provided and a project fallback otherwise', () => {
    expect(defaultFatalErrorLogPath({GESHU_ENGINE_LOG_FILE: 'C:/logs/run.log'}, 'C:/repo/lesson_engine'))
      .toBe(path.resolve('C:/logs/run.log'));
    expect(defaultFatalErrorLogPath({GESHU_INSTANCE: 'C:/repo'}, 'C:/other/lesson_engine'))
      .toBe(path.join('C:/repo', 'build', 'local-stack-logs', 'lesson-engine-crash.log'));
  });

  it('records uncaught and unhandled failures before exiting', async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), 'geshu-runtime-handlers-'));
    tempDirs.push(root);
    const logFile = path.join(root, 'lesson-engine.log');
    const emitter = new EventEmitter();
    const exitCodes: number[] = [];
    const consoleMessages: string[] = [];
    const dispose = installFatalErrorHandlers({
      logFile,
      target: emitter,
      exit: (code) => exitCodes.push(code),
      consoleError: (message) => consoleMessages.push(message)
    });

    emitter.emit('uncaughtException', new Error('uncaught boom'));
    emitter.emit('unhandledRejection', new Error('rejection boom'));
    dispose();

    const content = await readFile(logFile, 'utf8');
    expect(content).toContain('[uncaughtException]');
    expect(content).toContain('uncaught boom');
    expect(content).toContain('[unhandledRejection]');
    expect(content).toContain('rejection boom');
    expect(exitCodes).toEqual([1, 1]);
    expect(consoleMessages).toHaveLength(2);
  });
});