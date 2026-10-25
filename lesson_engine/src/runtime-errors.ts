import {appendFileSync, mkdirSync} from 'node:fs';
import path from 'node:path';

export type FatalErrorKind = 'uncaughtException' | 'unhandledRejection' | 'startupFailure';

interface FatalErrorFormatterOptions {
  now?: Date;
  pid?: number;
}

export function defaultFatalErrorLogPath(
  env: NodeJS.ProcessEnv = process.env,
  cwd = process.cwd()
): string {
  const explicit = env.GESHU_ENGINE_LOG_FILE?.trim();
  if (explicit) return path.resolve(explicit);
  const root = env.GESHU_INSTANCE?.trim() || path.resolve(cwd, '..');
  return path.join(root, 'build', 'local-stack-logs', 'lesson-engine-crash.log');
}

function errorDetails(reason: unknown): string {
  if (reason instanceof Error) return reason.stack || `${reason.name}: ${reason.message}`;
  if (typeof reason === 'string') return reason;
  try {
    return JSON.stringify(reason, null, 2);
  } catch {
    return String(reason);
  }
}

export function formatFatalError(
  kind: FatalErrorKind,
  reason: unknown,
  options: FatalErrorFormatterOptions = {}
): string {
  const now = options.now ?? new Date();
  const pid = options.pid ?? process.pid;
  return `[${now.toISOString()}] [${kind}] pid=${pid}\n${errorDetails(reason)}\n`;
}

export function appendFatalError(
  logFile: string,
  kind: FatalErrorKind,
  reason: unknown,
  options: FatalErrorFormatterOptions = {}
): string {
  const text = formatFatalError(kind, reason, options);
  mkdirSync(path.dirname(logFile), {recursive: true});
  appendFileSync(logFile, text, 'utf8');
  return text;
}

interface ErrorEmitter {
  on(event: string, listener: (...args: any[]) => void): unknown;
  off?(event: string, listener: (...args: any[]) => void): unknown;
}

interface InstallFatalErrorOptions {
  logFile?: string;
  target?: ErrorEmitter;
  exit?: (code: number) => void;
  consoleError?: (message: string) => void;
}

/** Persist fatal process errors, then fail fast instead of leaving a half-dead server. */
export function installFatalErrorHandlers(options: InstallFatalErrorOptions = {}): () => void {
  const logFile = options.logFile ?? defaultFatalErrorLogPath();
  const target = options.target ?? process;
  const exit = options.exit ?? ((code: number) => process.exit(code));
  const consoleError = options.consoleError ?? ((message: string) => console.error(message));

  const handler = (kind: FatalErrorKind) => (reason: unknown) => {
    const text = appendFatalError(logFile, kind, reason);
    consoleError(text.trimEnd());
    exit(1);
  };
  const onUncaught = handler('uncaughtException');
  const onUnhandled = handler('unhandledRejection');
  target.on('uncaughtException', onUncaught);
  target.on('unhandledRejection', onUnhandled);
  return () => {
    target.off?.('uncaughtException', onUncaught);
    target.off?.('unhandledRejection', onUnhandled);
  };
}