import { BlockEvent, cloneBlockEvent } from '../models/BlockEventModels';

const MAX_EVENTS_PER_TAB: number = 60;

/** Keeps page-scoped block diagnostics in memory only; it deliberately never persists them. */
export class BlockEventStore {
  private readonly eventsByTab: Map<string, BlockEvent[]> = new Map();

  record(event: BlockEvent): void {
    const current: BlockEvent[] = this.eventsByTab.get(event.tabId) ?? [];
    this.eventsByTab.set(event.tabId, [cloneBlockEvent(event)].concat(current).slice(0, MAX_EVENTS_PER_TAB));
  }

  list(tabId: string): BlockEvent[] {
    return (this.eventsByTab.get(tabId) ?? []).map((event: BlockEvent): BlockEvent => cloneBlockEvent(event));
  }

  clear(tabId: string): void {
    this.eventsByTab.delete(tabId);
  }

  remove(tabId: string): void {
    this.eventsByTab.delete(tabId);
  }
}
