import { rawHost } from '../utils/UrlUtils';

export enum BlockCategory {
  Advertisement = 0,
  Tracker = 1,
  Other = 2
}

export enum BlockEngine {
  OwnRuleEngine = 0,
  ArkWebSystemRules = 1
}

export enum BlockResult {
  Blocked = 0
}

/** A short-lived record of one resource stopped while a tab is loading. */
export interface BlockEvent {
  id: string;
  tabId: string;
  resourceUrl: string;
  resourceHost: string;
  category: BlockCategory;
  engine: BlockEngine;
  result: BlockResult;
  /** Present only when the app's own RuleEngine made the decision. */
  ruleSource: string;
  occurredAt: number;
}

export function createBlockEvent(
  tabId: string,
  resourceUrl: string,
  category: BlockCategory,
  engine: BlockEngine,
  ruleSource: string = '',
  occurredAt: number = Date.now()
): BlockEvent {
  return {
    id: `block-${occurredAt}-${Math.floor(Math.random() * 1000000)}`,
    tabId: tabId,
    resourceUrl: resourceUrl,
    resourceHost: rawHost(resourceUrl),
    category: category,
    engine: engine,
    result: BlockResult.Blocked,
    ruleSource: engine === BlockEngine.OwnRuleEngine ? ruleSource : '',
    occurredAt: occurredAt
  };
}

export function cloneBlockEvent(event: BlockEvent): BlockEvent {
  return {
    id: event.id,
    tabId: event.tabId,
    resourceUrl: event.resourceUrl,
    resourceHost: event.resourceHost,
    category: event.category,
    engine: event.engine,
    result: event.result,
    ruleSource: event.ruleSource,
    occurredAt: event.occurredAt
  };
}
