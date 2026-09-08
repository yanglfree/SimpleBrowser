export interface FeedbackAttachment {
  fileName: string;
  mimeType: string;
  dataBase64: string;
}

export interface FeedbackRequest {
  appId?: string;
  appName?: string;
  packageName?: string;
  appVersion?: string;
  category?: string;
  message: string;
  contact?: string;
  allowFollowUp?: boolean;
  client?: string;
  metadata?: Record<string, Object>;
  attachments?: FeedbackAttachment[];
}

export interface FeedbackSubmission {
  ticketId: string;
  requestId: string;
}

export const FEEDBACK_APP_ID: string = 'zhuobrowser';
export const FEEDBACK_APP_NAME: string = '卓阅浏览器';
export const FEEDBACK_PACKAGE_NAME: string = 'com.youdroid.browser';
export const FEEDBACK_CLIENT: string = 'harmony';
export const FEEDBACK_DEFAULT_BASE_URL: string = 'https://gateway.youdroid.top';
export const FEEDBACK_PATH: string = '/v1/feedback';

export const FEEDBACK_MESSAGE_MIN_LENGTH: number = 5;
export const FEEDBACK_MESSAGE_MAX_LENGTH: number = 1000;

export function validateFeedbackMessage(message: string): 'too_short' | 'too_long' | null {
  const trimmed: string = message.trim();
  if (trimmed.length < FEEDBACK_MESSAGE_MIN_LENGTH) {
    return 'too_short';
  }
  if (trimmed.length > FEEDBACK_MESSAGE_MAX_LENGTH) {
    return 'too_long';
  }
  return null;
}

export function buildFeedbackPayload(request: FeedbackRequest): Record<string, Object> {
  const contact: string = request.contact !== undefined ? request.contact.trim() : '';
  const allowFollowUp: boolean = request.allowFollowUp !== undefined
    ? request.allowFollowUp
    : (contact.length > 0);
  const metadata: Record<string, Object> = request.metadata !== undefined ? request.metadata : {};

  const payload: Record<string, Object> = {
    'app_id': request.appId ?? FEEDBACK_APP_ID,
    'app_name': request.appName ?? FEEDBACK_APP_NAME,
    'package_name': request.packageName ?? FEEDBACK_PACKAGE_NAME,
    'app_version': request.appVersion ?? '1.0.0',
    'category': request.category ?? 'feedback',
    'message': request.message.trim(),
    'contact': contact,
    'allowFollowUp': allowFollowUp,
    'client': request.client ?? FEEDBACK_CLIENT,
    'metadata': metadata
  };

  if (request.attachments !== undefined && request.attachments.length > 0) {
    payload['attachments'] = request.attachments.map((att: FeedbackAttachment): Record<string, Object> => ({
      'file_name': att.fileName,
      'mime_type': att.mimeType,
      'data_base64': att.dataBase64
    }));
  }

  return payload;
}

export function parseFeedbackSubmission(responseObj: Record<string, Object>): FeedbackSubmission {
  let ticketId: string = '';
  if (typeof responseObj['ticketId'] === 'string') {
    ticketId = responseObj['ticketId'] as string;
  } else if (typeof responseObj['ticket_id'] === 'string') {
    ticketId = responseObj['ticket_id'] as string;
  }

  let requestId: string = '';
  if (typeof responseObj['request_id'] === 'string') {
    requestId = responseObj['request_id'] as string;
  } else if (typeof responseObj['requestId'] === 'string') {
    requestId = responseObj['requestId'] as string;
  }

  return { ticketId, requestId };
}
