import { describe, expect, it } from '@ohos/hypium';
import {
  BrowseDisposition,
  createExternalOpenRequest,
  dispositionForExternalAction,
  ExternalOpenAction,
  extractSharedUrl,
  restoreTrackingParameters
} from '../main/ets/models/ExternalOpenRequest';

export default function externalOpenRequestTest(): void {
  describe('External open request', (): void => {
    it('removes only explicit marketing parameters and preserves the original for undo', 0, (): void => {
      const request = createExternalOpenRequest(
        'https://example.com/story?utm_source=newsletter&token=abc&sig=keep&fbclid=tracking#read',
        'Story',
        42
      );
      expect(request?.cleanUrl).assertEqual('https://example.com/story?token=abc&sig=keep#read');
      expect(request?.removedTrackingParameters.join(',')).assertEqual('utm_source,fbclid');
      expect(request === undefined ? '' : restoreTrackingParameters(request))
        .assertEqual('https://example.com/story?utm_source=newsletter&token=abc&sig=keep&fbclid=tracking#read');
    });

    it('does not strip unknown, login, payment, or signature parameters', 0, (): void => {
      const request = createExternalOpenRequest(
        'https://example.com/checkout?session=one&payment_intent=two&signature=three&campaign=unknown',
        '',
        43
      );
      expect(request?.cleanUrl).assertEqual(
        'https://example.com/checkout?session=one&payment_intent=two&signature=three&campaign=unknown'
      );
      expect(request?.removedTrackingParameters.length).assertEqual(0);
    });

    it('accepts a direct share URL and keeps disposable work private', 0, (): void => {
      expect(extractSharedUrl('https://example.com/article', undefined)).assertEqual('https://example.com/article');
      expect(dispositionForExternalAction(ExternalOpenAction.CleanOpen)).assertEqual(BrowseDisposition.Normal);
      expect(dispositionForExternalAction(ExternalOpenAction.PrivateOpen)).assertEqual(BrowseDisposition.Private);
      expect(dispositionForExternalAction(ExternalOpenAction.ReadAndClose)).assertEqual(BrowseDisposition.Disposable);
    });
  });
}
