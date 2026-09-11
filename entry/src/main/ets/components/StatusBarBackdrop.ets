import {
  BrowserSystemBarStyle, HOME_STATUS_SCRIM, STATUS_SCRIM_FADE_HEIGHT
} from '../models/SystemBarStyle';

@Component
export struct StatusBarBackdrop {
  @Prop topInset: number = 0;
  @Prop style: BrowserSystemBarStyle = { background: '#FAF9F7', content: '#1A1A18', wallpaper: false };

  build() {
    Column() {
      Row()
        .width('100%')
        .height(this.topInset)
        .backgroundColor(this.style.wallpaper ? HOME_STATUS_SCRIM : this.style.background)
      if (this.style.wallpaper) {
        Row()
          .width('100%')
          .height(STATUS_SCRIM_FADE_HEIGHT)
          .linearGradient({ angle: 180, colors: [[HOME_STATUS_SCRIM, 0], ['#00000000', 1]] })
      }
    }
    .width('100%')
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }
}
