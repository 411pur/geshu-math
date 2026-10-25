import {appendFileSync, mkdirSync} from 'node:fs';
import path from 'node:path';

/** Stable, Windows-safe filename for one application run. */
export function runLogFileName(now = new Date()) {
  const stamp = now.toISOString().replace(/[:.]/g, '-');
  return `lesson-engine.${stamp}.log`;
}

/**
 * Mirror startup and child-process output to the terminal and a per-run log.
 * Synchronous file appends are intentional: crash evidence must survive an
 * immediate process exit.
 */
export function createRunLog({root, now = new Date(), stdout = process.stdout, stderr = process.stderr}) {
  const directory = path.join(root, 'build', 'local-stack-logs');
  mkdirSync(directory, {recursive: true});
  const filePath = path.join(directory, runLogFileName(now));

  function line(kind, stream, message) {
    const text = String(message ?? '').replace(/\r?\n$/, '');
    const entry = `[${now.toISOString()}] [${kind}] ${text}\n`;
    stream.write(entry);
    appendFileSync(filePath, entry, 'utf8');
  }

  return {
    filePath,
    info(message) { line('startup', stdout, message); },
    error(message) { line('startup-error', stderr, message); },
    pipe(readable, target = stdout) {
      readable.on('data', (chunk) => {
        target.write(chunk);
        appendFileSync(filePath, chunk);
      });
    }
  };
}