import { DownloadTask, DownloadTaskStatus } from '../services/DownloadService';
import { downloadStatusLabel, emptyDownloadTask } from '../services/DownloadPresentation';
import { AppIcon, IconName } from './AppIcon';

@Component
export struct DownloadNotice {
  @Prop task: DownloadTask = emptyDownloadTask();
  onOpen: () => void = (): void => {};
  onDismiss: () => void = (): void => {};

  build() {
    Row({ space: 10 }) {
      AppIcon({
        name: this.task.status === DownloadTaskStatus.Completed ? IconName.Check : IconName.Download,
        glyphSize: 18,
        color: $r('app.color.accent')
      })
      Column({ space: 2 }) {
        Text(downloadStatusLabel(this.task.status))
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
        Text(this.task.fileName)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => this.onOpen())
      Button($r('app.string.download_view_tasks'))
        .id('download-notice-open')
        .fontSize(13)
        .fontColor($r('app.color.accent'))
        .backgroundColor($r('app.color.surface_subtle'))
        .onClick(() => this.onOpen())
      AppIcon({ name: IconName.Close, glyphSize: 15, color: $r('app.color.text_secondary') })
        .width(32)
        .height(40)
        .accessibilityText($r('app.string.download_dismiss_notice'))
        .onClick(() => this.onDismiss())
    }
    .id('download-notice')
    .width('100%')
    .constraintSize({ maxWidth: 520 })
    .padding({ left: 16, right: 8, top: 8, bottom: 8 })
    .borderRadius(18)
    .backgroundColor($r('app.color.surface_panel'))
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 16, color: $r('app.color.shadow_soft'), offsetY: 3 })
  }
}
