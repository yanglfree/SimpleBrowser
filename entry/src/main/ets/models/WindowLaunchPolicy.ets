export const MAIN_WINDOW_INSTANCE_ID: string = 'dolphin-main';

export function resolveWindowInstanceId(requestedToken: string): string {
  return requestedToken.length > 0 ? requestedToken : MAIN_WINDOW_INSTANCE_ID;
}
