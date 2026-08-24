import { BlockCategory } from '../models/BlockEventModels';
import { isTrackerUrl } from '../utils/UrlUtils';

export function classifyBlockCategory(url: string, ruleSource: string = ''): BlockCategory {
  const evidence: string = `${url}\n${ruleSource}`.toLowerCase();
  if (isTrackerUrl(url) || evidence.includes('track') || evidence.includes('analytics') ||
    evidence.includes('telemetry')) {
    return BlockCategory.Tracker;
  }
  return BlockCategory.Advertisement;
}
