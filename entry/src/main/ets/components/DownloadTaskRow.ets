import { DownloadTask, DownloadTaskStatus } from '../services/DownloadService';
import { downloadStatusLabel, downloadErrorLabel, emptyDownloadTask } from '../services/DownloadPresentation';

@Component
export struct DownloadTaskRow {
  @Prop task: DownloadTask = emptyDownloadTask();
  onPause: (id: string) => void = (_id: string): void => {};
  onResume: (id: string) => void = (_id: string): void => {};
  onRetry: (id: string) => void = (_id: string): void => {};
  onOpen: (task: DownloadTask) => void = (_task: DownloadTask): void => {};
  onShare: (task: DownloadTask) => void = (_task: DownloadTask): void => {};
  onDeleteFile: (id: string) => void = (_id: string): void => {};
  onDeleteRecord: (id: string) => void = (_id: string): void => {};

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.task.fileName)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(downloadStatusLabel(this.task.status))
          .fontSize(12)
          .fontColor(this.task.status === DownloadTaskStatus.Failed
            ? $r('app.color.text_secondary')
            : $r('app.color.accent'))
      }
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(5)
          .borderRadius(3)
          .backgroundColor($r('app.color.bar_track'))
        Row()
          .width(`${this.progress(this.task)}%`)
          .height(5)
          .borderRadius(3)
          .backgroundColor($r('app.color.bar_fill'))
      }
      .width('100%')
      .height(5)
      Row({ space: 8 }) {
        Text(this.progressLabel(this.task))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        if (this.task.status === DownloadTaskStatus.Downloading) {
          Text($r('app.string.download_pause'))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .onClick(() => this.onPause(this.task.id))
        } else if (this.task.status === DownloadTaskStatus.Paused) {
          Text($r('app.string.download_resume'))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .onClick(() => this.onResume(this.task.id))
        } else if (this.task.status === DownloadTaskStatus.Failed || this.task.status === DownloadTaskStatus.Canceled) {
          Text($r('app.string.download_retry'))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .onClick(() => this.onRetry(this.task.id))
        }
        if (this.task.status === DownloadTaskStatus.Completed) {
          Text($r('app.string.download_open'))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .accessibilityText($r('app.string.download_open'))
            .onClick(() => this.onOpen(this.task))
          Text($r('app.string.download_share'))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .accessibilityText($r('app.string.download_share'))
            .onClick(() => this.onShare(this.task))
        }
        Text($r('app.string.download_delete_record'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .accessibilityText($r('app.string.download_delete_record'))
          .onClick(() => this.onDeleteRecord(this.task.id))
        if (this.task.status === DownloadTaskStatus.Completed) {
          Text($r('app.string.download_delete_file'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .accessibilityText($r('app.string.download_delete_file'))
            .onClick(() => this.onDeleteFile(this.task.id))
        }
      }
      .width('100%')
    }
    .id(`download-task-${this.task.id}`)
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .borderRadius(16)
    .backgroundColor($r('app.color.surface_panel'))
    .border({ width: 1, color: $r('app.color.border') })
  }

  private progress(task: DownloadTask): number {
    return task.progress < 0 ? 0 : Math.min(100, Math.max(0, task.progress));
  }

  private progressLabel(task: DownloadTask): ResourceStr {
    if (task.status === DownloadTaskStatus.Completed) {
      return $r('app.string.download_completed');
    }
    if (task.status === DownloadTaskStatus.Failed) {
      return downloadErrorLabel(task.error);
    }
    if (task.progress < 0) {
      return $r('app.string.download_progress_unknown');
    }
    return `${Math.floor(task.progress)}%`;
  }

}
