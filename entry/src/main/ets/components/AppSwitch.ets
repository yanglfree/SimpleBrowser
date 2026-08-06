const TRACK_WIDTH: number = 46;
const TRACK_HEIGHT: number = 28;
const KNOB_SIZE: number = 24;
const KNOB_INSET: number = 2;

/**
 * The 46x28 switch from the design. The on state is deliberately the only place
 * the ink-green accent is used as a fill.
 */
@Component
export struct AppSwitch {
  @Prop checked: boolean = false;
  @Prop accessibilityLabel: Resource = $r('app.string.settings');
  onToggle: () => void = (): void => {};

  build() {
    Row() {
      Stack({ alignContent: Alignment.TopStart }) {
        Circle()
          .width(KNOB_SIZE)
          .height(KNOB_SIZE)
          .fill(this.checked ? $r('app.color.switch_knob') : $r('app.color.switch_knob_off'))
          .shadow(this.checked
            ? { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 }
            : { radius: 3, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: 1 })
          .margin({
            top: KNOB_INSET,
            left: this.checked ? TRACK_WIDTH - KNOB_SIZE - KNOB_INSET : KNOB_INSET
          })
          .animation({ duration: 180, curve: Curve.FastOutSlowIn })
      }
      .width(TRACK_WIDTH)
      .height(TRACK_HEIGHT)
      .borderRadius(TRACK_HEIGHT / 2)
      .backgroundColor(this.checked ? $r('app.color.accent') : $r('app.color.switch_track_off'))
      .animation({ duration: 180, curve: Curve.FastOutSlowIn })
    }
    .width(48)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .accessibilityText(this.accessibilityLabel)
    .accessibilityDescription(this.checked ? '已开启' : '已关闭')
    .onClick(() => this.onToggle())
  }
}
