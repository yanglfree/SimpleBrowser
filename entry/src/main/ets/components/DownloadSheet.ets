import { AppIcon, IconName } from './AppIcon';
import { DownloadTask } from '../services/DownloadService';
import { DownloadTaskRow } from './DownloadTaskRow';
import { emptyDownloadTask } from '../services/DownloadPresentation';

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
              DownloadTaskRow({
                task: this.taskFor(task.id),
                onPause: this.onPause,
                onResume: this.onResume,
                onRetry: this.onRetry,
                onOpen: this.onOpen,
                onShare: this.onShare,
                onDeleteFile: this.onDeleteFile,
                onDeleteRecord: this.onDeleteRecord
              })
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

  private taskFor(id: string): DownloadTask {
    return this.tasks.find((task: DownloadTask): boolean => task.id === id) ?? emptyDownloadTask();
  }

}
