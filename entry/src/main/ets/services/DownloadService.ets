import { webview } from '@kit.ArkWeb';
import { notificationManager } from '@kit.NotificationKit';
import environment from '@ohos.file.environment';
import { Logger } from '../utils/Logger';

const TAG: string = 'DownloadService';

export enum DownloadTaskStatus {
  Pending = 0,
  Downloading = 1,
  Paused = 2,
  Completed = 3,
  Failed = 4,
  Canceled = 5
}

export interface DownloadTask {
  id: string;
  fileName: string;
  url: string;
  status: DownloadTaskStatus;
  progress: number;
  receivedBytes: number;
  totalBytes: number;
  speed: number;
  attempts: number;
  error: string;
}

type DownloadListener = (tasks: DownloadTask[]) => void;

export class DownloadService {
  private static isConfigured: boolean = false;
  private static maxConcurrent: number = 2;
  private static tasks: DownloadTask[] = [];
  private static items: Map<string, webview.WebDownloadItem> = new Map();
  private static startedIds: string[] = [];
  private static listeners: DownloadListener[] = [];
  private static notifiedProgress: Map<string, number> = new Map();

  static configure(): void {
    if (DownloadService.isConfigured) {
      return;
    }
    const delegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
    delegate.onBeforeDownload((item: webview.WebDownloadItem) => DownloadService.enqueue(item));
    delegate.onDownloadUpdated((item: webview.WebDownloadItem) => DownloadService.update(item));
    delegate.onDownloadFinish((item: webview.WebDownloadItem) => {
      DownloadService.finish(item);
    });
    delegate.onDownloadFailed((item: webview.WebDownloadItem) => {
      DownloadService.fail(item);
    });
    webview.WebDownloadManager.setDownloadDelegate(delegate);
    DownloadService.isConfigured = true;
  }

  static setConcurrencyLimit(limit: number): void {
    DownloadService.maxConcurrent = Math.min(6, Math.max(1, Math.floor(limit)));
    DownloadService.pump();
  }

  static subscribe(listener: DownloadListener): void {
    if (!DownloadService.listeners.includes(listener)) {
      DownloadService.listeners.push(listener);
    }
    listener(DownloadService.getTasks());
  }

  static unsubscribe(listener: DownloadListener): void {
    DownloadService.listeners = DownloadService.listeners.filter(
      (item: DownloadListener) => item !== listener);
  }

  static getTasks(): DownloadTask[] {
    return DownloadService.tasks.map((task: DownloadTask) => DownloadService.cloneTask(task));
  }

  static pause(id: string): void {
    const item: webview.WebDownloadItem | undefined = DownloadService.items.get(id);
    const task: DownloadTask | undefined = DownloadService.task(id);
    if (item === undefined || task === undefined || task.status !== DownloadTaskStatus.Downloading) {
      return;
    }
    try {
      item.pause();
      task.status = DownloadTaskStatus.Paused;
      DownloadService.publishTasks();
      DownloadService.pump();
    } catch (error) {
      Logger.warn(TAG, `Failed to pause download ${id}: ${String(error)}`);
    }
  }

  static resume(id: string): void {
    const task: DownloadTask | undefined = DownloadService.task(id);
    if (task === undefined || task.status !== DownloadTaskStatus.Paused) {
      return;
    }
    task.status = DownloadTaskStatus.Pending;
    DownloadService.pump();
    DownloadService.publishTasks();
  }

  static retry(id: string): void {
    const task: DownloadTask | undefined = DownloadService.task(id);
    if (task === undefined ||
      (task.status !== DownloadTaskStatus.Failed && task.status !== DownloadTaskStatus.Canceled)) {
      return;
    }
    task.status = DownloadTaskStatus.Pending;
    task.error = '';
    DownloadService.pump();
    DownloadService.publishTasks();
  }

  private static enqueue(item: webview.WebDownloadItem): void {
    try {
      const id: string = item.getGuid();
      const existing: DownloadTask | undefined = DownloadService.task(id);
      DownloadService.items.set(id, item);
      if (existing === undefined) {
        DownloadService.tasks.push({
          id: id,
          fileName: DownloadService.safeFileName(item.getSuggestedFileName()),
          url: item.getUrl(),
          status: DownloadTaskStatus.Pending,
          progress: 0,
          receivedBytes: 0,
          totalBytes: item.getTotalBytes(),
          speed: 0,
          attempts: 0,
          error: ''
        });
      }
      DownloadService.publishTasks();
      DownloadService.pump();
    } catch (error) {
      Logger.error(TAG, `Failed to enqueue download: ${String(error)}`);
      item.cancel();
    }
  }

  private static pump(): void {
    let active: number = DownloadService.tasks.filter(
      (task: DownloadTask) => task.status === DownloadTaskStatus.Downloading).length;
    for (const task of DownloadService.tasks) {
      if (active >= DownloadService.maxConcurrent) {
        break;
      }
      if (task.status !== DownloadTaskStatus.Pending) {
        continue;
      }
      const item: webview.WebDownloadItem | undefined = DownloadService.items.get(task.id);
      if (item === undefined) {
        continue;
      }
      if (DownloadService.start(task, item)) {
        active += 1;
      }
    }
  }

  private static start(task: DownloadTask, item: webview.WebDownloadItem): boolean {
    try {
      if (DownloadService.startedIds.includes(task.id)) {
        webview.WebDownloadManager.resumeDownload(item);
      } else {
        const targetPath: string = `${environment.getUserDownloadDir()}/${task.fileName}`;
        item.start(targetPath);
        DownloadService.startedIds.push(task.id);
      }
      task.status = DownloadTaskStatus.Downloading;
      task.attempts += 1;
      task.error = '';
      Logger.info(TAG, `Download started: ${task.fileName}`);
      DownloadService.publishTasks();
      return true;
    } catch (error) {
      task.status = DownloadTaskStatus.Failed;
      task.error = String(error);
      Logger.error(TAG, `Failed to start download: ${String(error)}`);
      DownloadService.publishTasks();
      DownloadService.notify(task, 'Download failed');
      return false;
    }
  }

  private static update(item: webview.WebDownloadItem): void {
    const task: DownloadTask | undefined = DownloadService.task(item.getGuid());
    if (task === undefined) {
      return;
    }
    task.status = DownloadTaskStatus.Downloading;
    task.progress = item.getPercentComplete();
    task.receivedBytes = item.getReceivedBytes();
    task.totalBytes = item.getTotalBytes();
    task.speed = item.getCurrentSpeed();
    const progressBucket: number = task.progress < 0 ? -1 : Math.floor(task.progress / 10) * 10;
    const previousBucket: number = DownloadService.notifiedProgress.get(task.id) ?? -2;
    if (progressBucket >= 0 && progressBucket > previousBucket) {
      DownloadService.notifiedProgress.set(task.id, progressBucket);
      DownloadService.notify(task, `${progressBucket}%`);
    }
    DownloadService.publishTasks();
  }

  private static finish(item: webview.WebDownloadItem): void {
    const task: DownloadTask | undefined = DownloadService.task(item.getGuid());
    if (task === undefined) {
      return;
    }
    task.status = DownloadTaskStatus.Completed;
    task.progress = 100;
    task.receivedBytes = item.getReceivedBytes();
    task.totalBytes = item.getTotalBytes();
    Logger.info(TAG, `Download finished: ${task.fileName}`);
    DownloadService.notify(task, 'Download completed');
    DownloadService.publishTasks();
    DownloadService.pump();
  }

  private static fail(item: webview.WebDownloadItem): void {
    const task: DownloadTask | undefined = DownloadService.task(item.getGuid());
    if (task === undefined) {
      return;
    }
    task.status = item.getState() === webview.WebDownloadState.CANCELED
      ? DownloadTaskStatus.Canceled
      : DownloadTaskStatus.Failed;
    task.error = `${item.getLastErrorCode()}`;
    Logger.warn(TAG, `Download failed: ${task.fileName}`);
    DownloadService.notify(task, 'Download failed');
    DownloadService.publishTasks();
    DownloadService.pump();
  }

  private static task(id: string): DownloadTask | undefined {
    return DownloadService.tasks.find((task: DownloadTask) => task.id === id);
  }

  private static publishTasks(): void {
    const tasks: DownloadTask[] = DownloadService.getTasks();
    for (const listener of DownloadService.listeners) {
      listener(tasks);
    }
  }

  private static notify(task: DownloadTask, suffix: string): void {
    notificationManager.publish({
      id: Math.abs(task.id.split('').reduce((hash: number, character: string) =>
        ((hash * 31 + character.charCodeAt(0)) | 0), 0)),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: task.fileName,
          text: suffix
        }
      }
    }).catch((error: Error): void => {
      Logger.warn(TAG, `Download notification unavailable: ${String(error)}`);
    });
  }

  private static cloneTask(task: DownloadTask): DownloadTask {
    return {
      id: task.id,
      fileName: task.fileName,
      url: task.url,
      status: task.status,
      progress: task.progress,
      receivedBytes: task.receivedBytes,
      totalBytes: task.totalBytes,
      speed: task.speed,
      attempts: task.attempts,
      error: task.error
    };
  }

  private static safeFileName(value: string): string {
    const normalized: string = value.replace(/[\\/:*?"<>|]/g, '_').trim();
    return normalized.length > 0 ? normalized : `download-${Date.now()}`;
  }
}
