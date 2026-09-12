import { UserAgentPreference } from '../models/BrowserModels';

@Component
export struct UserAgentPolicySheet {
  @Prop host: string = '';
  @Prop currentPreference: UserAgentPreference = UserAgentPreference.Default;
  @Prop globalPreference: UserAgentPreference = UserAgentPreference.Default;
  onApplyOnce: (preference: UserAgentPreference) => void = (_preference: UserAgentPreference): void => {};
  onApplyAlways: (preference: UserAgentPreference) => void = (_preference: UserAgentPreference): void => {};
  onSetGlobal: (preference: UserAgentPreference) => void = (_preference: UserAgentPreference): void => {};
  onResetAll: () => void = (): void => {};
  onDismiss: () => void = (): void => {};

  build() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 3 }) {
          Text($r('app.string.ua_policy_title'))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.host)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text($r('app.string.done'))
          .fontSize(15)
          .fontColor($r('app.color.accent'))
          .onClick(() => this.onDismiss())
      }
      .width('100%')

      Text($r('app.string.ua_once'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 8 }) {
        this.PolicyButton(UserAgentPreference.Mobile, $r('app.string.ua_mobile'), false)
        this.PolicyButton(UserAgentPreference.Desktop, $r('app.string.ua_desktop'), false)
      }
      .width('100%')

      Text($r('app.string.ua_always_site'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 8 }) {
        this.PolicyButton(UserAgentPreference.Default, $r('app.string.ua_default'), true)
        this.PolicyButton(UserAgentPreference.Mobile, $r('app.string.ua_mobile'), true)
        this.PolicyButton(UserAgentPreference.Desktop, $r('app.string.ua_desktop'), true)
      }
      .width('100%')

      Text($r('app.string.ua_global_default'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 8 }) {
        this.GlobalButton(UserAgentPreference.Default, $r('app.string.ua_default'))
        this.GlobalButton(UserAgentPreference.Mobile, $r('app.string.ua_mobile'))
        this.GlobalButton(UserAgentPreference.Desktop, $r('app.string.ua_desktop'))
      }
      .width('100%')

      Text($r('app.string.ua_reset_all'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .padding({ top: 8, bottom: 8 })
        .onClick(() => this.onResetAll())
    }
    .width('100%')
    .padding({ top: 22, left: 22, right: 22, bottom: 28 })
    .borderRadius({ topLeft: 24, topRight: 24 })
    .backgroundColor($r('app.color.surface_panel'))
  }

  @Builder
  private PolicyButton(preference: UserAgentPreference, label: ResourceStr, persistent: boolean) {
    Text(label)
      .fontSize(14)
      .fontColor(persistent && preference === this.currentPreference
        ? Color.White
        : $r('app.color.text_primary'))
      .layoutWeight(1)
      .height(42)
      .textAlign(TextAlign.Center)
      .borderRadius(12)
      .backgroundColor(persistent && preference === this.currentPreference
        ? $r('app.color.accent')
        : $r('app.color.surface_subtle'))
      .hoverEffect(HoverEffect.Auto)
      .onClick(() => persistent ? this.onApplyAlways(preference) : this.onApplyOnce(preference))
  }

  @Builder
  private GlobalButton(preference: UserAgentPreference, label: ResourceStr) {
    Text(label)
      .fontSize(14)
      .fontColor(preference === this.globalPreference ? Color.White : $r('app.color.text_primary'))
      .layoutWeight(1)
      .height(42)
      .textAlign(TextAlign.Center)
      .borderRadius(12)
      .backgroundColor(preference === this.globalPreference
        ? $r('app.color.accent')
        : $r('app.color.surface_subtle'))
      .hoverEffect(HoverEffect.Auto)
      .onClick(() => this.onSetGlobal(preference))
  }
}
