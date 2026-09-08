import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Logger } from '../utils/Logger';
import {
  buildFeedbackPayload,
  FEEDBACK_APP_ID,
  FEEDBACK_DEFAULT_BASE_URL,
  FEEDBACK_PATH,
  FeedbackRequest,
  FeedbackSubmission,
  parseFeedbackSubmission
} from '../models/FeedbackModels';

const TAG: string = 'FeedbackService';
const CONNECT_TIMEOUT_MS: number = 10000;
const READ_TIMEOUT_MS: number = 15000;

export class FeedbackService {
  private static baseUrl: string = FEEDBACK_DEFAULT_BASE_URL;

  static setBaseUrl(url: string): void {
    FeedbackService.baseUrl = url.replace(/\/+$/, '');
  }

  static getBaseUrl(): string {
    return FeedbackService.baseUrl;
  }

  static resetBaseUrl(): void {
    FeedbackService.baseUrl = FEEDBACK_DEFAULT_BASE_URL;
  }

  static async submit(request: FeedbackRequest, customBaseUrl?: string): Promise<FeedbackSubmission> {
    const base: string = (customBaseUrl !== undefined && customBaseUrl.length > 0)
      ? customBaseUrl.replace(/\/+$/, '')
      : FeedbackService.baseUrl;
    const url: string = `${base}${FEEDBACK_PATH}`;
    const payload: Record<string, Object> = buildFeedbackPayload(request);
    const bodyStr: string = JSON.stringify(payload);

    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-App-Id': FEEDBACK_APP_ID,
          'X-Platform': 'HarmonyOS'
        },
        extraData: bodyStr,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS
      });

      const statusCode: number = Number(response.responseCode);
      if (statusCode < 200 || statusCode >= 300) {
        Logger.warn(TAG, `Feedback request failed with status: ${statusCode}`);
        throw new Error(`HTTP_${statusCode}`);
      }

      let rawResult: string = '';
      if (typeof response.result === 'string') {
        rawResult = response.result;
      } else if (response.result instanceof ArrayBuffer) {
        rawResult = new util.TextDecoder().decodeToString(new Uint8Array(response.result));
      } else {
        rawResult = JSON.stringify(response.result);
      }

      const parsed: Record<string, Object> = JSON.parse(rawResult) as Record<string, Object>;
      if (!parsed || parsed['ok'] !== true) {
        throw new Error('FEEDBACK_SUBMISSION_FAILED');
      }

      return parseFeedbackSubmission(parsed);
    } catch (error) {
      Logger.warn(TAG, `Failed to submit feedback: ${String(error)}`);
      throw new Error(error instanceof Error ? error.message : String(error));
    } finally {
      httpRequest.destroy();
    }
  }
}
