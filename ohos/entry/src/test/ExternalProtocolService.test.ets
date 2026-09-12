import { describe, expect, it } from '@ohos/hypium';
import {
  createExternalProtocolRequest,
  ExternalProtocolCategory,
  externalProtocolCategory,
  isBlockedProtocol,
  isWebProtocol,
  protocolScheme
} from '../main/ets/services/ExternalProtocolService';

export default function externalProtocolServiceTest(): void {
  describe('External protocol service', (): void => {
    it('routes HarmonyOS installation and application market links', 0, (): void => {
      const store = createExternalProtocolRequest(
        'store://enterprise/manifest?url=https%3A%2F%2Fdownloads.example%2Fmanifest.json5',
        'downloads.example'
      );
      expect(store?.scheme).assertEqual('store');
      expect(store?.category).assertEqual(ExternalProtocolCategory.AppInstall);
      expect(store?.sourceHost).assertEqual('downloads.example');
      expect(externalProtocolCategory('market')).assertEqual(ExternalProtocolCategory.AppInstall);
      expect(externalProtocolCategory('intent')).assertEqual(ExternalProtocolCategory.AppInstall);
    });

    it('classifies common communication, navigation, payment, social, and transfer schemes', 0, (): void => {
      expect(externalProtocolCategory('tel')).assertEqual(ExternalProtocolCategory.Communication);
      expect(externalProtocolCategory('mailto')).assertEqual(ExternalProtocolCategory.Communication);
      expect(externalProtocolCategory('petalmaps')).assertEqual(ExternalProtocolCategory.Navigation);
      expect(externalProtocolCategory('alipays')).assertEqual(ExternalProtocolCategory.Payment);
      expect(externalProtocolCategory('mqqapi')).assertEqual(ExternalProtocolCategory.Social);
      expect(externalProtocolCategory('magnet')).assertEqual(ExternalProtocolCategory.FileTransfer);
    });

    it('supports valid custom schemes without handing internal web schemes to applications', 0, (): void => {
      expect(createExternalProtocolRequest('my-app+auth://callback')?.category)
        .assertEqual(ExternalProtocolCategory.Custom);
      expect(isWebProtocol('HTTPS://example.com')).assertTrue();
      expect(isBlockedProtocol('javascript:alert(1)')).assertTrue();
      expect(createExternalProtocolRequest('javascript:alert(1)') === undefined).assertTrue();
      expect(createExternalProtocolRequest('data:text/plain,hello') === undefined).assertTrue();
      expect(createExternalProtocolRequest('blob:https://example.com/id') === undefined).assertTrue();
      expect(createExternalProtocolRequest('file:///data/test') === undefined).assertTrue();
      expect(createExternalProtocolRequest('not a protocol') === undefined).assertTrue();
    });

    it('normalizes schemes case-insensitively', 0, (): void => {
      expect(protocolScheme('  Store://enterprise/manifest')).assertEqual('store');
      expect(protocolScheme('invalid')).assertEqual('');
    });
  });
}
