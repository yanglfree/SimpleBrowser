import { AppIcon, IconName } from './AppIcon';
import { DownloadTask, DownloadTaskStatus } from '../services/DownloadService';

@Component
export struct DownloadSheet {
  @Prop topInset: number = 0;
  @Prop tasks: DownloadTask[] = [];
  onDismiss: () => void = (): void => {};
  onPause: (id: string) => void = (_id: string): void => {};
  onResume: (id: string) => void = (_id: string): void => {};
  onRetry: (id: string) => void = (_id: string): void => {};
  onOpen: (task: DownloadTask) => void = (_task: DownloadTask): void => {};
  onShare: (task: DownloadTask) => void = (_task: DownloadTask): void => {};
  onDeleteFile: (id: string) => void = (_id: string): void => {};
  onDeleteRecord: (id: string) => void = (_id: string): void => {};

  build() {
    Column() {
      Row({ space: 12 }) {
        AppIcon({ name: IconName.ArrowLeft, glyphSize: 21, color: $r('app.color.text_primary') })
          .onClick(() => this.onDismiss())
        Text($r('app.string.download_title'))
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.tasks.length > 0) {
          Text(`${this.tasks.length}`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .fontFeature('"tnum" 1')
        }
      }
      .width('100%')
      .height(56 + Math.max(0, this.topInset))
      .padding({ top: Math.max(0, this.topInset), left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })

      if (this.tasks.length === 0) {
        Column({ space: 10 }) {
          AppIcon({ name: IconName.Reader, glyphSize: 26, color: $r('app.color.text_secondary') })
          Text($r('app.string.download_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ top: 48 })
        .justifyContent(FlexAlign.Start)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.tasks, (task: DownloadTask) => {
              this.TaskRow(task)
            }, (task: DownloadTask) => task.id)
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 16, bottom: 32 })
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private TaskRow(task: DownloadTask) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(task.fileName)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.statusText(task.status))
          .fontSize(12)
          .fontColor(task.status === DownloadTaskStatus.Failed
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
          .width(`${this.progress(task)}%`)
          .height(5)
          .borderRadius(3)
          .backgroundColor($r('app.color.bar_fill'))
      }
      .width('100%')
      .height(5)
      Row({ space: 8 }) {
        Text(this.progressLabel(task))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        if (task.status === DownloadTaskStatus.Downloading) {
          Text($r('app.string.download_pause'))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .onClick(() => this.onPause(task.id))
        } else if (task.status === DownloadTaskStatus.Paused) {
          Text($r('app.string.download_resume'))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .onClick(() => this.onResume(task.id))
        } else if (task.status === DownloadTaskStatus.Failed || task.status === DownloadTaskStatus.Canceled) {
          Text($r('app.string.download_retry'))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .onClick(() => this.onRetry(task.id))
        }
        if (task.status === DownloadTaskStatus.Completed) {
          Text($r('app.string.download_open'))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .accessibilityText($r('app.string.download_open'))
            .onClick(() => this.onOpen(task))
          Text($r('app.string.download_share'))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .accessibilityText($r('app.string.download_share'))
            .onClick(() => this.onShare(task))
        }
        Text($r('app.string.download_delete_record'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .accessibilityText($r('app.string.download_delete_record'))
          .onClick(() => this.onDeleteRecord(task.id))
        if (task.status === DownloadTaskStatus.Completed) {
          Text($r('app.string.download_delete_file'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .accessibilityText($r('app.string.download_delete_file'))
            .onClick(() => this.onDeleteFile(task.id))
        }
      }
      .width('100%')
    }
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
      return $r('app.string.download_failed');
    }
    if (task.progress < 0) {
      return $r('app.string.download_progress_unknown');
    }
    return `${Math.floor(task.progress)}%`;
  }

  private statusText(status: DownloadTaskStatus): Resource {
    if (status === DownloadTaskStatus.Downloading) {
      return $r('app.string.download_status_downloading');
    }
    if (status === DownloadTaskStatus.Paused) {
      return $r('app.string.download_status_paused');
    }
    if (status === DownloadTaskStatus.Pending) {
      return $r('app.string.download_status_pending');
    }
    if (status === DownloadTaskStatus.Completed) {
      return $r('app.string.download_status_completed');
    }
    return $r('app.string.download_status_failed');
  }
}
