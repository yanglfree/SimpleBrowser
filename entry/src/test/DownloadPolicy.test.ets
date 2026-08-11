import { describe, expect, it } from '@ohos/hypium';
import {
  DownloadPolicyReason,
  resolveDownloadPolicyReason
} from '../main/ets/services/DownloadService';

export default function downloadPolicyTest(): void {
  describe('DownloadPolicy strict network rules', (): void => {
    it('requires Wi-Fi before honoring any previous approval', 0, (): void => {
      const reason: DownloadPolicyReason = resolveDownloadPolicyReason(true, false, true, 5 * 1024 * 1024,
        50 * 1024 * 1024);

      expect(reason).assertEqual(DownloadPolicyReason.WifiRequired);
    });

    it('keeps large-file confirmation separate from strict Wi-Fi-only blocking', 0, (): void => {
      const reason: DownloadPolicyReason = resolveDownloadPolicyReason(false, false, false, 100 * 1024 * 1024,
        50 * 1024 * 1024);

      expect(reason).assertEqual(DownloadPolicyReason.LargeFile);
    });

    it('allows approved large files only when Wi-Fi-only is disabled', 0, (): void => {
      const reason: DownloadPolicyReason = resolveDownloadPolicyReason(false, false, true, 100 * 1024 * 1024,
        50 * 1024 * 1024);

      expect(reason).assertEqual(DownloadPolicyReason.None);
    });

    it('does not prompt on Wi-Fi regardless of size', 0, (): void => {
      const reason: DownloadPolicyReason = resolveDownloadPolicyReason(true, true, false, 500 * 1024 * 1024,
        50 * 1024 * 1024);

      expect(reason).assertEqual(DownloadPolicyReason.None);
    });
  });
}
