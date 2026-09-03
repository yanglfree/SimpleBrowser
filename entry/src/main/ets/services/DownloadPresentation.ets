import { DownloadTask, DownloadTaskStatus } from './DownloadService';

export function emptyDownloadTask(): DownloadTask {
  return {
    id: '', fileName: '', url: '', status: DownloadTaskStatus.Pending,
    progress: 0, receivedBytes: 0, totalBytes: 0, speed: 0, attempts: 0, error: ''
  };
}

export function nextDownloadNotice(previous: DownloadTask[], tasks: DownloadTask[]): DownloadTask | undefined {
  let started: DownloadTask | undefined = undefined;
  for (const task of tasks) {
    const old: DownloadTask | undefined = previous.find((entry: DownloadTask): boolean => entry.id === task.id);
    if (old !== undefined && old.status !== task.status &&
      (task.status === DownloadTaskStatus.Completed || task.status === DownloadTaskStatus.Failed)) {
      return task;
    }
    if ((task.status === DownloadTaskStatus.Pending || task.status === DownloadTaskStatus.Downloading) &&
      (old === undefined || old.status === DownloadTaskStatus.Failed || old.status === DownloadTaskStatus.Canceled)) {
      started = task;
    }
  }
  return started;
}

export function downloadStatusLabel(status: DownloadTaskStatus): Resource {
  switch (status) {
    case DownloadTaskStatus.Downloading: return $r('app.string.download_status_downloading');
    case DownloadTaskStatus.Paused: return $r('app.string.download_status_paused');
    case DownloadTaskStatus.Pending: return $r('app.string.download_status_pending');
    case DownloadTaskStatus.Completed: return $r('app.string.download_notice_completed');
    case DownloadTaskStatus.Canceled: return $r('app.string.download_status_canceled');
    default: return $r('app.string.download_failed');
  }
}

export function downloadErrorLabel(error: string): Resource {
  if (error === 'storage' || error === '2') {
    return $r('app.string.download_error_storage');
  }
  if (error === '3') {
    return $r('app.string.download_error_space');
  }
  if (error === '5') {
    return $r('app.string.download_error_filename');
  }
  if (error === '34' || error === '33') {
    return $r('app.string.download_error_link');
  }
  if (error === '20' || error === '21' || error === '22' || error === '23') {
    return $r('app.string.download_error_network');
  }
  return $r('app.string.download_error_retry');
}
