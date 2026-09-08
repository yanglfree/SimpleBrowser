import { describe, expect, it } from '@ohos/hypium';
import {
  buildFeedbackPayload,
  FEEDBACK_APP_ID,
  FEEDBACK_APP_NAME,
  FEEDBACK_CLIENT,
  FEEDBACK_DEFAULT_BASE_URL,
  FEEDBACK_PACKAGE_NAME,
  FeedbackAttachment,
  FeedbackRequest,
  FeedbackSubmission,
  parseFeedbackSubmission,
  validateFeedbackMessage
} from '../main/ets/models/FeedbackModels';
import { FeedbackService } from '../main/ets/services/FeedbackService';

export default function feedbackServiceTest(): void {
  describe('Feedback models and payload serialization', (): void => {
    it('builds default payload matching ai-gateway requirements', 0, (): void => {
      const request: FeedbackRequest = {
        message: 'This is a test feedback message.'
      };

      const payload: Record<string, Object> = buildFeedbackPayload(request);

      expect(payload['app_id']).assertEqual(FEEDBACK_APP_ID);
      expect(payload['app_name']).assertEqual(FEEDBACK_APP_NAME);
      expect(payload['package_name']).assertEqual(FEEDBACK_PACKAGE_NAME);
      expect(payload['category']).assertEqual('feedback');
      expect(payload['client']).assertEqual(FEEDBACK_CLIENT);
      expect(payload['message']).assertEqual('This is a test feedback message.');
      expect(payload['contact']).assertEqual('');
      expect(payload['allowFollowUp']).assertEqual(false);
    });

    it('sets allowFollowUp to true when contact is provided', 0, (): void => {
      const request: FeedbackRequest = {
        message: 'Need help with bookmarks',
        contact: 'test@example.com'
      };

      const payload: Record<string, Object> = buildFeedbackPayload(request);

      expect(payload['contact']).assertEqual('test@example.com');
      expect(payload['allowFollowUp']).assertEqual(true);
    });

    it('preserves custom metadata, app version, and attachments', 0, (): void => {
      const attachment: FeedbackAttachment = {
        fileName: 'screenshot.png',
        mimeType: 'image/png',
        dataBase64: 'iVBORw0KGgo='
      };
      const metadata: Record<string, Object> = {
        'version_code': 1000001,
        'platform': 'harmonyos'
      };
      const request: FeedbackRequest = {
        appId: 'custom_id',
        appName: 'Custom App',
        packageName: 'com.custom.app',
        appVersion: '2.0.0',
        category: 'bug',
        message: '  Whitespace trimmed  ',
        contact: '  dev@example.com  ',
        allowFollowUp: false,
        client: 'custom_harmony',
        metadata: metadata,
        attachments: [attachment]
      };

      const payload: Record<string, Object> = buildFeedbackPayload(request);

      expect(payload['app_id']).assertEqual('custom_id');
      expect(payload['app_name']).assertEqual('Custom App');
      expect(payload['package_name']).assertEqual('com.custom.app');
      expect(payload['app_version']).assertEqual('2.0.0');
      expect(payload['category']).assertEqual('bug');
      expect(payload['message']).assertEqual('Whitespace trimmed');
      expect(payload['contact']).assertEqual('dev@example.com');
      expect(payload['allowFollowUp']).assertEqual(false);
      expect(payload['client']).assertEqual('custom_harmony');

      const meta = payload['metadata'] as Record<string, Object>;
      expect(meta['version_code']).assertEqual(1000001);

      const atts = payload['attachments'] as Record<string, Object>[];
      expect(atts.length).assertEqual(1);
      expect(atts[0]['file_name']).assertEqual('screenshot.png');
      expect(atts[0]['mime_type']).assertEqual('image/png');
      expect(atts[0]['data_base64']).assertEqual('iVBORw0KGgo=');
    });

    it('validates feedback message length correctly', 0, (): void => {
      expect(validateFeedbackMessage('')).assertEqual('too_short');
      expect(validateFeedbackMessage('   ')).assertEqual('too_short');
      expect(validateFeedbackMessage('1234')).assertEqual('too_short');
      expect(validateFeedbackMessage(' 1234 ')).assertEqual('too_short');

      expect(validateFeedbackMessage('12345')).assertEqual(null);
      expect(validateFeedbackMessage('Valid message here')).assertEqual(null);

      const exactly1000: string = 'a'.repeat(1000);
      expect(validateFeedbackMessage(exactly1000)).assertEqual(null);

      const tooLong1001: string = 'a'.repeat(1001);
      expect(validateFeedbackMessage(tooLong1001)).assertEqual('too_long');
    });

    it('parses feedback submission response with standard and alternate keys', 0, (): void => {
      const response1: Record<string, Object> = {
        'ok': true,
        'ticketId': 't-12345',
        'request_id': 'req-9876'
      };
      const submission1: FeedbackSubmission = parseFeedbackSubmission(response1);
      expect(submission1.ticketId).assertEqual('t-12345');
      expect(submission1.requestId).assertEqual('req-9876');

      const response2: Record<string, Object> = {
        'ok': true,
        'ticket_id': 't-alt-1',
        'requestId': 'req-alt-2'
      };
      const submission2: FeedbackSubmission = parseFeedbackSubmission(response2);
      expect(submission2.ticketId).assertEqual('t-alt-1');
      expect(submission2.requestId).assertEqual('req-alt-2');

      const responseEmpty: Record<string, Object> = { 'ok': true };
      const submissionEmpty: FeedbackSubmission = parseFeedbackSubmission(responseEmpty);
      expect(submissionEmpty.ticketId).assertEqual('');
      expect(submissionEmpty.requestId).assertEqual('');
    });

    it('manages feedback base url and trims trailing slashes', 0, (): void => {
      FeedbackService.resetBaseUrl();
      expect(FeedbackService.getBaseUrl()).assertEqual(FEEDBACK_DEFAULT_BASE_URL);

      FeedbackService.setBaseUrl('https://custom.gateway.top///');
      expect(FeedbackService.getBaseUrl()).assertEqual('https://custom.gateway.top');

      FeedbackService.resetBaseUrl();
      expect(FeedbackService.getBaseUrl()).assertEqual(FEEDBACK_DEFAULT_BASE_URL);
    });
  });
}
