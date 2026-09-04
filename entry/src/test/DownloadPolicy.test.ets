import { describe, expect, it } from '@ohos/hypium';
import {
  DownloadPolicyReason,
  DownloadTask,
  DownloadTaskStatus,
  reconcileRestoredDownloadTask,
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

    it('restores an existing completed file as completed', 0, (): void => {
      const task: DownloadTask = downloadTask(DownloadTaskStatus.Completed);
      const restored: DownloadTask = reconcileRestoredDownloadTask(task, '/downloads/qa.txt', (): boolean => true);

      expect(restored.status).assertEqual(DownloadTaskStatus.Completed);
      expect(restored.error).assertEqual('');
    });

    it('marks a missing completed file with specific feedback', 0, (): void => {
      const task: DownloadTask = downloadTask(DownloadTaskStatus.Completed);
      const restored: DownloadTask = reconcileRestoredDownloadTask(task, '/downloads/qa.txt', (): boolean => false);

      expect(restored.status).assertEqual(DownloadTaskStatus.Failed);
      expect(restored.error).assertEqual('missing');
    });

    it('makes an in-flight cold-start record retryable', 0, (): void => {
      const task: DownloadTask = downloadTask(DownloadTaskStatus.Downloading);
      const restored: DownloadTask = reconcileRestoredDownloadTask(task, '/downloads/qa.txt', (): boolean => true);

      expect(restored.status).assertEqual(DownloadTaskStatus.Failed);
      expect(restored.error).assertEqual('interrupted');
      expect(restored.speed).assertEqual(0);
    });
  });
}

function downloadTask(status: DownloadTaskStatus): DownloadTask {
  return {
    id: 'qa-download',
    fileName: 'qa.txt',
    url: 'https://example.com/qa.txt',
    status: status,
    progress: status === DownloadTaskStatus.Completed ? 100 : 42,
    receivedBytes: 42,
    totalBytes: 100,
    speed: 10,
    attempts: 1,
    error: ''
  };
}
