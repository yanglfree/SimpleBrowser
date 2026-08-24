import { describe, expect, it } from '@ohos/hypium';
import { BlockCategory, BlockEngine, createBlockEvent } from '../main/ets/models/BlockEventModels';
import { BlockEventStore } from '../main/ets/services/BlockEventStore';

export default function blockEventStoreTest(): void {
  describe('Block event store', (): void => {
    it('retains only in-memory events for the matching tab', 0, (): void => {
      const store: BlockEventStore = new BlockEventStore();
      store.record(createBlockEvent('tab-1', 'https://ads.example/image.js', BlockCategory.Advertisement,
        BlockEngine.OwnRuleEngine, '||ads.example^', 1));
      expect(store.list('tab-1').length).assertEqual(1);
      expect(store.list('tab-1')[0].ruleSource).assertEqual('||ads.example^');
      expect(store.list('tab-2').length).assertEqual(0);
      store.clear('tab-1');
      expect(store.list('tab-1').length).assertEqual(0);
    });

    it('never exposes a specific rule for an ArkWeb system-list event', 0, (): void => {
      const event = createBlockEvent('tab-1', 'https://tracker.example/pixel', BlockCategory.Tracker,
        BlockEngine.ArkWebSystemRules, 'not-available', 1);
      expect(event.ruleSource).assertEqual('');
    });
  });
}
