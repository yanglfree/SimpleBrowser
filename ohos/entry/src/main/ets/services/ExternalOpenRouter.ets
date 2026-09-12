import { ExternalOpenRequest } from '../models/ExternalOpenRequest';

export type ExternalOpenListener = (request: ExternalOpenRequest) => void;

/** Delivers an inbound Want after the page is ready without persisting the share payload. */
export class ExternalOpenRouter {
  private static listeners: Map<string, ExternalOpenListener> = new Map();
  private static pending: Map<string, ExternalOpenRequest[]> = new Map();

  static deliver(windowToken: string, request: ExternalOpenRequest): void {
    const listener: ExternalOpenListener | undefined = ExternalOpenRouter.listeners.get(windowToken);
    if (listener === undefined) {
      const queued: ExternalOpenRequest[] = ExternalOpenRouter.pending.get(windowToken) ?? [];
      ExternalOpenRouter.pending.set(windowToken, queued.concat([request]));
      return;
    }
    listener(request);
  }

  static subscribe(windowToken: string, listener: ExternalOpenListener): void {
    ExternalOpenRouter.listeners.set(windowToken, listener);
    const pending: ExternalOpenRequest[] | undefined = ExternalOpenRouter.pending.get(windowToken);
    if (pending !== undefined) {
      ExternalOpenRouter.pending.delete(windowToken);
      for (const request of pending) {
        listener(request);
      }
    }
  }

  static unsubscribe(windowToken: string): void {
    ExternalOpenRouter.listeners.delete(windowToken);
  }
}
