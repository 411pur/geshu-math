import type { ProjectRecord } from '../schemas/project.js';

export interface JobEvent {
  type: 'created' | 'progress' | 'done' | 'error';
  record: ProjectRecord;
  message: string;
}

type Listener = (event: JobEvent) => void;

export class JobManager {
  private readonly channels = new Map<string, Set<Listener>>();

  subscribe(projectId: string, listener: Listener): () => void {
    const listeners = this.channels.get(projectId) || new Set<Listener>();
    listeners.add(listener);
    this.channels.set(projectId, listeners);
    return () => {
      listeners.delete(listener);
      if (!listeners.size) this.channels.delete(projectId);
    };
  }

  publish(event: JobEvent): void {
    const listeners = this.channels.get(event.record.id);
    if (!listeners) return;
    for (const listener of listeners) listener(event);
  }
}
