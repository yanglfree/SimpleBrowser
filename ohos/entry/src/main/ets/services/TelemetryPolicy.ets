/**
 * A private tab suppresses every product analytics event, even when the event
 * contains only a coarse action name. This keeps the runtime rule aligned with
 * the privacy policy instead of relying on each caller to remember the guard.
 */
export function allowsTelemetryWrite(enabled: boolean, privateContext: boolean): boolean {
  return enabled && !privateContext;
}
