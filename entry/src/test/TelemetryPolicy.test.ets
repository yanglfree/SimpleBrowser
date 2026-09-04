import { describe, expect, it } from '@ohos/hypium';
import { allowsTelemetryWrite } from '../main/ets/services/TelemetryPolicy';

export default function telemetryPolicyTest(): void {
  describe('Telemetry policy', (): void => {
    it('requires opt-in and a non-private context', 0, (): void => {
      expect(allowsTelemetryWrite(false, false)).assertFalse();
      expect(allowsTelemetryWrite(false, true)).assertFalse();
      expect(allowsTelemetryWrite(true, true)).assertFalse();
      expect(allowsTelemetryWrite(true, false)).assertTrue();
    });
  });
}
