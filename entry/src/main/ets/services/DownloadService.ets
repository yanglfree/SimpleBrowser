import { webview } from '@kit.ArkWeb';
import { common, Want, wantConstant } from '@kit.AbilityKit';
import { connection } from '@kit.NetworkKit';
import { notificationManager } from '@kit.NotificationKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { Logger } from '../utils/Logger';
import { ShareService, ShareOutcome } from './ShareService';

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

export enum DownloadPolicyReason {
  None = 0,
  WifiRequired = 1,
  LargeFile = 2
}

export function resolveDownloadPolicyReason(
  wifiOnly: boolean,
  isWifiConnected: boolean,
  isApproved: boolean,
  totalBytes: number,
  largeDownloadThresholdBytes: number
): DownloadPolicyReason {
  if (wifiOnly && !isWifiConnected) {
    return DownloadPolicyReason.WifiRequired;
  }
  if (isWifiConnected || isApproved) {
    return DownloadPolicyReason.None;
  }
  return totalBytes > 0 && totalBytes >= largeDownloadThresholdBytes
    ? DownloadPolicyReason.LargeFile
    : DownloadPolicyReason.None;
}

type DownloadListener = (tasks: DownloadTask[]) => void;
type DownloadPolicyPrompt = (task: DownloadTask, reason: DownloadPolicyReason) => void;

export class DownloadService {
  private static isConfigured: boolean = false;
  private static maxConcurrent: number = 2;
  private static tasks: DownloadTask[] = [];
  private static items: Map<string, webview.WebDownloadItem> = new Map();
  private static beforeItems: Map<string, webview.WebDownloadItem> = new Map();
  private static startedIds: string[] = [];
  private static listeners: DownloadListener[] = [];
  private static notifiedProgress: Map<string, number> = new Map();
  private static downloadDirectory: string = '';
  private static directoryRequest: Promise<string> | undefined;
  private static context: common.UIAbilityContext | undefined;
  private static paths: Map<string, string> = new Map();
  private static startVersions: Map<string, number> = new Map();
  private static pausedIds: Set<string> = new Set();
  private static largeDownloadThresholdBytes: number = 50 * 1024 * 1024;
  private static wifiOnly: boolean = false;
  private static policyPrompt: DownloadPolicyPrompt | undefined = undefined;
  private static promptingIds: string[] = [];
  private static approvedIds: string[] = [];

  static configure(context: common.UIAbilityContext): void {
    DownloadService.context = context;
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

  static configurePolicy(
    thresholdMb: number,
    wifiOnly: boolean,
    prompt: DownloadPolicyPrompt
  ): void {
    const strictWifiOnlyActivated: boolean = wifiOnly && !DownloadService.wifiOnly;
    DownloadService.largeDownloadThresholdBytes = Math.max(1, thresholdMb) * 1024 * 1024;
    DownloadService.wifiOnly = wifiOnly;
    DownloadService.policyPrompt = prompt;
    if (strictWifiOnlyActivated) {
      DownloadService.promptingIds = [];
      DownloadService.approvedIds = [];
    }
    DownloadService.pump();
  }

  static approve(id: string): void {
    DownloadService.promptingIds = DownloadService.promptingIds.filter((item: string) => item !== id);
    if (!DownloadService.approvedIds.includes(id)) {
      DownloadService.approvedIds.push(id);
    }
    DownloadService.pump();
  }

  static cancelByPolicy(id: string): void {
    const task: DownloadTask | undefined = DownloadService.task(id);
    const item: webview.WebDownloadItem | undefined = DownloadService.items.get(id);
    DownloadService.promptingIds = DownloadService.promptingIds.filter((item: string) => item !== id);
    DownloadService.approvedIds = DownloadService.approvedIds.filter((item: string) => item !== id);
    if (task !== undefined) {
      task.status = DownloadTaskStatus.Canceled;
      try {
        item?.cancel();
      } catch (error) {
        Logger.warn(TAG, `Unable to cancel policy-blocked download: ${String(error)}`);
      }
      DownloadService.publishTasks();
    }
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
      task.status = DownloadTaskStatus.Paused;
      DownloadService.startVersions.set(id, (DownloadService.startVersions.get(id) ?? 0) + 1);
      item.pause();
      DownloadService.pausedIds.add(id);
      DownloadService.publishTasks();
      DownloadService.pump();
    } catch (error) {
      task.status = DownloadTaskStatus.Downloading;
      Logger.warn(TAG, `Failed to pause download ${id}: ${String(error)}`);
      DownloadService.publishTasks();
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

  static async open(context: common.UIAbilityContext, task: DownloadTask): Promise<boolean> {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: fileUri.getUriFromPath(DownloadService.pathFor(task)),
        type: DownloadService.mimeType(task.fileName),
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      };
      await context.startAbility(want);
      return true;
    } catch (error) {
      Logger.warn(TAG, `Unable to open downloaded file: ${String(error)}`);
      return false;
    }
  }

  static async share(context: common.UIAbilityContext, task: DownloadTask): Promise<ShareOutcome> {
    return await ShareService.shareFile(context, DownloadService.pathFor(task), task.fileName);
  }

  static remove(id: string, deleteFile: boolean): void {
    const task: DownloadTask | undefined = DownloadService.task(id);
    if (task === undefined) {
      return;
    }
    if (task.status !== DownloadTaskStatus.Completed && task.status !== DownloadTaskStatus.Canceled) {
      task.status = DownloadTaskStatus.Canceled;
      try {
        DownloadService.items.get(id)?.cancel();
      } catch (error) {
        Logger.warn(TAG, `Unable to cancel removed download: ${String(error)}`);
      }
    }
    if (deleteFile) {
      try {
        fs.unlinkSync(DownloadService.pathFor(task));
      } catch (error) {
        Logger.warn(TAG, `Downloaded file was not removed: ${String(error)}`);
      }
    }
    DownloadService.tasks = DownloadService.tasks.filter((item: DownloadTask) => item.id !== id);
    DownloadService.items.delete(id);
    DownloadService.beforeItems.delete(id);
    DownloadService.paths.delete(id);
    DownloadService.startVersions.delete(id);
    DownloadService.pausedIds.delete(id);
    DownloadService.startedIds = DownloadService.startedIds.filter((item: string) => item !== id);
    DownloadService.notifiedProgress.delete(id);
    DownloadService.promptingIds = DownloadService.promptingIds.filter((item: string) => item !== id);
    DownloadService.approvedIds = DownloadService.approvedIds.filter((item: string) => item !== id);
    DownloadService.publishTasks();
    DownloadService.pump();
  }

  private static enqueue(item: webview.WebDownloadItem): void {
    try {
      const id: string = item.getGuid();
      const existing: DownloadTask | undefined = DownloadService.task(id);
      DownloadService.items.set(id, item);
      if (existing !== undefined) {
        // Restored tasks receive a new before-download callback with the same GUID.
        if (existing.status === DownloadTaskStatus.Downloading) {
          item.start(DownloadService.pathFor(existing));
          DownloadService.beforeItems.delete(id);
          if (!DownloadService.startedIds.includes(id)) {
            DownloadService.startedIds.push(id);
          }
        } else {
          item.cancel();
        }
        return;
      }
      DownloadService.beforeItems.set(id, item);
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
      // ArkWeb starts receiving temporary bytes before start(path). Pause while
      // resolving the destination, waiting for policy approval or a queue slot.
      item.pause();
      DownloadService.pausedIds.add(id);
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
      const policyReason: DownloadPolicyReason = DownloadService.policyReason(task);
      if (policyReason !== DownloadPolicyReason.None) {
        if (!DownloadService.promptingIds.includes(task.id)) {
          DownloadService.promptingIds.push(task.id);
          DownloadService.policyPrompt?.(DownloadService.cloneTask(task), policyReason);
        }
        continue;
      }
      const item: webview.WebDownloadItem | undefined = DownloadService.items.get(task.id);
      if (item === undefined) {
        continue;
      }
      task.status = DownloadTaskStatus.Downloading;
      const version: number = (DownloadService.startVersions.get(task.id) ?? 0) + 1;
      DownloadService.startVersions.set(task.id, version);
      active += 1;
      void DownloadService.start(task, version);
    }
  }

  private static async start(task: DownloadTask, version: number): Promise<void> {
    try {
      if (!DownloadService.paths.has(task.id)) {
        const directory: string = await DownloadService.resolveDownloadDirectory();
        if (DownloadService.task(task.id) !== task || task.status !== DownloadTaskStatus.Downloading ||
          DownloadService.startVersions.get(task.id) !== version) {
          return;
        }
        DownloadService.reservePath(task, directory);
      }
      const item: webview.WebDownloadItem | undefined = DownloadService.items.get(task.id);
      if (item === undefined || task.status !== DownloadTaskStatus.Downloading ||
        DownloadService.startVersions.get(task.id) !== version) {
        return;
      }
      task.attempts += 1;
      task.error = '';
      if (item.getState() === webview.WebDownloadState.INTERRUPTED ||
        item.getState() === webview.WebDownloadState.CANCELED) {
        webview.WebDownloadManager.resumeDownload(webview.WebDownloadItem.deserialize(item.serialize()));
      } else {
        if (!DownloadService.startedIds.includes(task.id)) {
          // Only the before-download item owns the native start callback.
          // Progress items are newer snapshots but cannot assign a destination.
          const beforeItem: webview.WebDownloadItem | undefined = DownloadService.beforeItems.get(task.id);
          if (beforeItem === undefined) {
            throw new Error('Download destination callback is unavailable');
          }
          beforeItem.start(DownloadService.pathFor(task));
          DownloadService.beforeItems.delete(task.id);
          DownloadService.startedIds.push(task.id);
        }
        if (DownloadService.pausedIds.has(task.id) || item.getState() === webview.WebDownloadState.PAUSED) {
          item.resume();
          DownloadService.pausedIds.delete(task.id);
        }
      }
      Logger.info(TAG, `Download started: ${task.fileName}`);
      DownloadService.publishTasks();
    } catch (error) {
      if (DownloadService.task(task.id) !== task || task.status === DownloadTaskStatus.Canceled ||
        DownloadService.startVersions.get(task.id) !== version) {
        return;
      }
      task.status = DownloadTaskStatus.Failed;
      task.error = DownloadService.paths.has(task.id) ? 'start' : 'storage';
      try {
        DownloadService.items.get(task.id)?.cancel();
      } catch (cancelError) {
        Logger.warn(TAG, `Unable to stop failed download: ${String(cancelError)}`);
      }
      Logger.error(TAG, `Failed to start download: ${String(error)}`);
      DownloadService.publishTasks();
      DownloadService.notify(task, DownloadService.localized('download_failed'));
      DownloadService.pump();
    }
  }

  private static async resolveDownloadDirectory(): Promise<string> {
    if (DownloadService.downloadDirectory.length > 0) {
      return DownloadService.downloadDirectory;
    }
    if (DownloadService.directoryRequest !== undefined) {
      return await DownloadService.directoryRequest;
    }
    DownloadService.directoryRequest = DownloadService.selectDownloadDirectory();
    try {
      return await DownloadService.directoryRequest;
    } finally {
      DownloadService.directoryRequest = undefined;
    }
  }

  private static async selectDownloadDirectory(): Promise<string> {
    if (DownloadService.context === undefined) {
      throw new Error('Download context is unavailable');
    }
    const options: picker.DocumentSaveOptions = { pickerMode: picker.DocumentPickerMode.DOWNLOAD };
    const uris: string[] = await new picker.DocumentViewPicker(DownloadService.context).save(options);
    if (uris.length === 0 || uris[0].length === 0) {
      throw new Error('Download directory was not selected');
    }
    const directory: string = new fileUri.FileUri(uris[0]).path.replace(/\/+$/, '');
    if (directory.length === 0) {
      throw new Error('Download directory is unavailable');
    }
    DownloadService.downloadDirectory = directory;
    return directory;
  }

  private static reservePath(task: DownloadTask, directory: string): void {
    const original: string = task.fileName;
    const extensionIndex: number = original.lastIndexOf('.');
    const stem: string = extensionIndex > 0 ? original.slice(0, extensionIndex) : original;
    const extension: string = extensionIndex > 0 ? original.slice(extensionIndex) : '';
    let name: string = original;
    let index: number = 1;
    while (fs.accessSync(`${directory}/${name}`) ||
      Array.from(DownloadService.paths.values()).includes(`${directory}/${name}`)) {
      name = `${stem} (${index++})${extension}`;
    }
    task.fileName = name;
    DownloadService.paths.set(task.id, `${directory}/${name}`);
  }

  private static update(item: webview.WebDownloadItem): void {
    const task: DownloadTask | undefined = DownloadService.task(item.getGuid());
    if (task === undefined) {
      return;
    }
    DownloadService.items.set(task.id, item);
    if (task.status === DownloadTaskStatus.Completed || task.status === DownloadTaskStatus.Canceled ||
      task.status === DownloadTaskStatus.Failed) {
      return;
    }
    task.progress = item.getPercentComplete();
    task.receivedBytes = item.getReceivedBytes();
    task.totalBytes = item.getTotalBytes();
    task.speed = item.getCurrentSpeed();
    const progressBucket: number = task.progress < 0 ? -1 : Math.floor(task.progress / 10) * 10;
    const previousBucket: number = DownloadService.notifiedProgress.get(task.id) ?? -2;
    if (progressBucket >= 0 && progressBucket > previousBucket) {
      DownloadService.notifiedProgress.set(task.id, progressBucket);
      DownloadService.notify(task, `${DownloadService.localized('download_status_downloading')} ${progressBucket}%`);
    }
    DownloadService.publishTasks();
  }

  private static finish(item: webview.WebDownloadItem): void {
    const task: DownloadTask | undefined = DownloadService.task(item.getGuid());
    if (task === undefined) {
      return;
    }
    if (task.status === DownloadTaskStatus.Completed || task.status === DownloadTaskStatus.Canceled) {
      return;
    }
    DownloadService.items.set(task.id, item);
    if (item.getFullPath().length > 0) {
      DownloadService.paths.set(task.id, item.getFullPath());
    }
    task.status = DownloadTaskStatus.Completed;
    task.progress = 100;
    task.receivedBytes = item.getReceivedBytes();
    task.totalBytes = item.getTotalBytes();
    Logger.info(TAG, `Download finished: ${task.receivedBytes}/${task.totalBytes} bytes`);
    DownloadService.notify(task, DownloadService.localized('download_notice_completed'));
    DownloadService.publishTasks();
    DownloadService.pump();
  }

  private static fail(item: webview.WebDownloadItem): void {
    const task: DownloadTask | undefined = DownloadService.task(item.getGuid());
    if (task === undefined) {
      return;
    }
    DownloadService.items.set(task.id, item);
    // ArkWeb can discard an unstarted native item while a policy dialog is
    // awaiting input. Keep the queued task so approval can restore its snapshot.
    if (!DownloadService.startedIds.includes(task.id) &&
      item.getState() === webview.WebDownloadState.CANCELED &&
      (task.status === DownloadTaskStatus.Pending || task.status === DownloadTaskStatus.Downloading)) {
      return;
    }
    if (task.status === DownloadTaskStatus.Completed || task.status === DownloadTaskStatus.Canceled ||
      (task.status === DownloadTaskStatus.Failed && (task.error === 'storage' || task.error === 'start'))) {
      return;
    }
    task.status = item.getState() === webview.WebDownloadState.CANCELED
      ? DownloadTaskStatus.Canceled
      : DownloadTaskStatus.Failed;
    task.error = `${item.getLastErrorCode()}`;
    Logger.warn(TAG, `Download failed with native error ${task.error}`);
    DownloadService.notify(task, DownloadService.localized('download_failed'));
    DownloadService.publishTasks();
    DownloadService.pump();
  }

  private static task(id: string): DownloadTask | undefined {
    return DownloadService.tasks.find((task: DownloadTask) => task.id === id);
  }

  private static policyReason(task: DownloadTask): DownloadPolicyReason {
    if (DownloadService.policyPrompt === undefined) {
      return DownloadPolicyReason.None;
    }
    return resolveDownloadPolicyReason(
      DownloadService.wifiOnly,
      DownloadService.isWifiConnected(),
      DownloadService.approvedIds.includes(task.id),
      task.totalBytes,
      DownloadService.largeDownloadThresholdBytes
    );
  }

  private static isWifiConnected(): boolean {
    try {
      const handle: connection.NetHandle = connection.getDefaultNetSync();
      if (handle.netId === 0) {
        return false;
      }
      const capabilities: connection.NetCapabilities = connection.getNetCapabilitiesSync(handle);
      return capabilities.bearerTypes.includes(connection.NetBearType.BEARER_WIFI);
    } catch (error) {
      Logger.warn(TAG, `Unable to determine network type: ${String(error)}`);
      return false;
    }
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

  private static localized(name: string): string {
    try {
      return DownloadService.context?.resourceManager.getStringByNameSync(name) ?? '';
    } catch (error) {
      Logger.warn(TAG, `Download notification text unavailable: ${String(error)}`);
      return '';
    }
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
    const normalized: string = value.replace(/[\\/:*?"<>|\x00-\x1f\x7f]/g, '_').trim();
    return normalized.length > 0 && !/^\.+$/.test(normalized) ? normalized : `download-${Date.now()}`;
  }

  private static pathFor(task: DownloadTask): string {
    return DownloadService.paths.get(task.id) ?? '';
  }

  private static mimeType(fileName: string): string {
    const extension: string = fileName.split('.').pop()?.toLowerCase() ?? '';
    if (extension === 'pdf') {
      return 'application/pdf';
    }
    if (extension === 'png' || extension === 'jpg' || extension === 'jpeg' || extension === 'gif' || extension === 'webp') {
      return `image/${extension === 'jpg' ? 'jpeg' : extension}`;
    }
    if (extension === 'txt' || extension === 'md' || extension === 'json' || extension === 'csv') {
      return 'text/plain';
    }
    return 'application/octet-stream';
  }
}
