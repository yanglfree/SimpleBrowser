import { AppIcon, IconName } from './AppIcon';
import { WebLongPressKind, WebLongPressTarget } from '../services/WebKernelService';

interface LinkAction {
  key: string;
  label: Resource;
  icon: IconName;
}

@Component
export struct LinkActionSheet {
  @Prop target: WebLongPressTarget;
  @Prop isPrivate: boolean = false;
  @Prop canOpenRight: boolean = false;
  onDismiss: () => void = (): void => {};
  onAction: (key: string) => void = (_key: string): void => {};

  build() {
    Column() {
      Column()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.onDismiss())
      this.Panel()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private Panel() {
    Column({ space: 14 }) {
      Row() {
        Text(this.target.kind === WebLongPressKind.Image
          ? $r('app.string.image_menu_title')
          : $r('app.string.link_menu_title'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Row() {
          AppIcon({ name: IconName.Close, glyphSize: 16, color: $r('app.color.text_secondary') })
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.onDismiss())
      }
      .width('100%')

      Text(this.target.url)
        .width('100%')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 10 }) {
        ForEach(this.actions(), (action: LinkAction) => {
          this.Action(action)
        }, (action: LinkAction) => action.key)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 18, left: 24, right: 24, bottom: 42 })
    .backgroundColor($r('app.color.surface_panel'))
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  @Builder
  private Action(action: LinkAction) {
    Column({ space: 8 }) {
      Row() {
        AppIcon({ name: action.icon, glyphSize: 22, color: $r('app.color.text_primary') })
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .borderRadius(24)
      .backgroundColor($r('app.color.surface_subtle'))
      Text(action.label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => this.onAction(action.key))
  }

  private actions(): LinkAction[] {
    if (this.target.kind === WebLongPressKind.Image) {
      return [
        { key: 'image_save', label: $r('app.string.image_menu_save'), icon: IconName.ArrowUpLeft },
        { key: 'image_share', label: $r('app.string.image_menu_share'), icon: IconName.Share }
      ];
    }
    const actions: LinkAction[] = [
      { key: 'link_open_background', label: $r('app.string.link_menu_open_background'), icon: IconName.Plus },
      { key: 'link_copy', label: $r('app.string.link_menu_copy'), icon: IconName.ArrowUpLeft },
      { key: 'link_share', label: $r('app.string.link_menu_share'), icon: IconName.Share }
    ];
    if (this.canOpenRight) {
      actions.unshift({ key: 'link_open_right', label: $r('app.string.tab_open_right'), icon: IconName.Tabs });
    }
    if (!this.isPrivate) {
      actions.push({ key: 'link_save_later', label: $r('app.string.link_menu_save_later'), icon: IconName.Reader });
    }
    return actions;
  }
}
