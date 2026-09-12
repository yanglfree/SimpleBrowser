import { describe, expect, it } from '@ohos/hypium';
import {
  BrowseDisposition,
  createExternalOpenRequest,
  dispositionForExternalAction,
  extractDroppedInput,
  extractDroppedUrl,
  ExternalOpenAction,
  extractSharedUrl,
  restoreTrackingParameters,
  withExternalOpenAction
} from '../main/ets/models/ExternalOpenRequest';
import externalProtocolServiceTest from './ExternalProtocolService.test';

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

    it('extracts links embedded in shared or dropped text', 0, (): void => {
      expect(extractSharedUrl('Read this: https://example.com/article?id=7.', undefined))
        .assertEqual('https://example.com/article?id=7');
      expect(extractDroppedUrl(['Plain note', 'Open https://example.com/drop?source=desktop。']))
        .assertEqual('https://example.com/drop?source=desktop');
      expect(extractDroppedUrl(['ftp://example.com/file', 'no link here'])).assertEqual('');
      expect(extractDroppedInput(['  local-first reading workflow  '])).assertEqual('local-first reading workflow');
      expect(extractDroppedInput(['note', 'https://example.com/preferred']))
        .assertEqual('https://example.com/preferred');
    });

    it('retains the source and resolves the selected task strategy in the request', 0, (): void => {
      const request = createExternalOpenRequest('https://example.com/article', 'Article', 44, 'com.example.news');
      expect(request?.sourceApp).assertEqual('com.example.news');
      if (request === undefined) {
        return;
      }
      const disposable = withExternalOpenAction(request, ExternalOpenAction.ReadAndClose);
      const save = withExternalOpenAction(request, ExternalOpenAction.SaveArticle);
      expect(disposable.disposition).assertEqual(BrowseDisposition.Disposable);
      expect(disposable.autoReader).assertTrue();
      expect(disposable.shouldSave).assertFalse();
      expect(save.shouldSave).assertTrue();
    });
  });
  externalProtocolServiceTest();
}
