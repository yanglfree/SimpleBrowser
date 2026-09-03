import { AppIcon, IconName } from './AppIcon';

export const TERMS_URL: string = 'https://browser.youdroid.top/terms.html';
export const PRIVACY_URL: string = 'https://browser.youdroid.top/privacy.html';

interface LegalSection {
  title: string;
  body: string;
}

const TERMS_SECTIONS: LegalSection[] = [
  {
    title: '1. 服务范围',
    body: '卓阅浏览器提供网页浏览、内容拦截、阅读模式及本地资料整理能力。你应遵守所在地法律和所访问网站的条款，不得利用本应用侵害他人权益或实施违法行为。'
  },
  {
    title: '2. Free 与 Pro',
    body: 'Free 版本包含清洁打开、基础广告与追踪拦截、标签页和阅读模式。Pro 版本解锁离线文章库、全文搜索、批注、主题、导出与大屏阅读工作台。具体范围以应用内购买页当时展示为准。'
  },
  {
    title: '3. 自动续费订阅',
    body: '月度与年度方案属于自动续费订阅。确认购买后，费用由 AppGallery 账户收取；除非你在当前订阅周期结束前通过系统订阅管理取消，否则订阅会自动续期并收取下一周期费用。实际价格、周期、续费时间和税费以 AppGallery 支付页及订单为准。'
  },
  {
    title: '4. 终身会员',
    body: '终身会员是一次性购买的非消耗型项目，适用于卓阅浏览器当前提供的 Pro 能力，可通过同一 AppGallery 账户恢复。它不承诺永久提供受第三方平台、法律变化或不可抗力影响而无法继续的服务。'
  },
  {
    title: '5. 取消、退款与恢复',
    body: '你可以在 AppGallery 的订阅管理中取消自动续费；取消后通常可使用至已付周期结束。退款由 AppGallery 依据其规则处理。更换设备或重新安装后，请在购买页使用“恢复购买”，应用会在服务端验证有效订单后恢复权益。'
  },
  {
    title: '6. 内容与责任边界',
    body: '网页内容由对应网站提供。拦截、阅读抽取和离线保存可能因页面结构、版权限制或网络环境而不完整。你应仅保存和导出有权使用的内容，并自行备份重要资料。'
  },
  {
    title: '7. 变更与终止',
    body: '我们可能为安全、兼容、法律或产品改进调整服务，并在本页面发布更新。若重大变更影响付费权益，将在合理范围内提供说明或处理方案。'
  },
  {
    title: '8. 联系我们',
    body: '订阅、权益或协议问题请联系 youdroid2048@gmail.com。'
  }
];

const PRIVACY_SECTIONS: LegalSection[] = [
  {
    title: '1. 核心数据默认留在本机',
    body: '卓阅浏览器无需注册账号。浏览历史、标签页、收藏、离线文章、批注、主题、阅读位置、站点权限与拦截规则默认保存在你的设备上。普通使用过程中，我们不会上传访问网址、网页正文、搜索词或私密标签页内容。'
  },
  {
    title: '2. 无痕浏览',
    body: '无痕标签页与普通会话隔离，不写入浏览历史、恢复会话、离线文章库或产品分析事件。关闭无痕标签页后，应用会请求清理对应站点数据；网站或系统组件自身的行为仍受其各自政策约束。'
  },
  {
    title: '3. 可选的崩溃与性能统计',
    body: '该开关默认关闭。只有你主动开启后，应用才会发送不含网址、网页正文、搜索词和私密会话信息的产品可靠性事件。你可随时在设置中关闭；关闭后立即停止新增统计写入。'
  },
  {
    title: '4. Pro 购买与权益验证',
    body: '购买由华为 AppGallery IAP 处理。为校验、恢复和防止重复交付，应用会向 gateway.youdroid.top 发送商品 ID、订单 ID、购买令牌、AppGallery 返回的原始购买凭据、平台与应用标识，以及随机生成的本机安装标识。我们不接收你的银行卡或支付密码。'
  },
  {
    title: '5. 权限与外部服务',
    body: '只有在你触发下载、文件导入导出、分享或网站申请相机、麦克风、定位等能力时，应用才请求相应系统权限。访问的网站会按其自身隐私政策处理你提交给它们的数据。'
  },
  {
    title: '6. 数据删除与保存期限',
    body: '你可以在设置中清除历史、Cookie、网页存储、缓存、权限与例外，也可以逐项删除收藏和离线文章。卸载应用会删除设备上的应用数据。订单与权益记录会在履行购买、恢复、退款处理和合规义务所需期限内保存。'
  },
  {
    title: '7. 联系我们',
    body: '如需咨询隐私、数据删除或购买记录，请发送邮件至 youdroid2048@gmail.com。'
  }
];

@Component
export struct PrivacyConsentDialog {
  @Prop isSaving: boolean = false;
  @State private isAgreed: boolean = false;
  @State private selectedTab: number = 0;
  onAccept: () => void = (): void => {};
  onOpenUrl: (url: string) => void = (_url: string): void => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // Background barrier
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .opacity(0.6)

      // Dialog Card
      Column() {
        // Header
        this.Header()

        // Document tabs and container
        this.DocumentContainer()

        // Bottom actions
        this.BottomActions()
      }
      .width('90%')
      .constraintSize({ maxWidth: 560, maxHeight: 680 })
      .backgroundColor($r('app.color.surface_panel'))
      .borderRadius(24)
      .border({ width: 1, color: $r('app.color.border') })
      .shadow({ radius: 32, color: 'rgba(0, 0, 0, 0.25)', offsetY: 16 })
      .clip(true)
      .padding({
        top: 24,
        left: 20,
        right: 20,
        bottom: 20
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private Header() {
    Row() {
      // Shield Icon Box
      Row() {
        AppIcon({
          name: IconName.ShieldCheck,
          glyphSize: 22,
          color: $r('app.color.accent'),
          strokeWidth: 1.8
        })
      }
      .width(40)
      .height(40)
      .borderRadius(12)
      .backgroundColor($r('app.color.surface_subtle'))
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ right: 14 })

      // Titles
      Column() {
        Text($r('app.string.privacy_dialog_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .lineHeight(24)

        Text($r('app.string.privacy_dialog_subtitle'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(19)
          .margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 14 })
  }

  @Builder
  private DocumentContainer() {
    Column() {
      // Tab Bar
      Row() {
        // Terms Tab
        Column() {
          Text($r('app.string.privacy_dialog_tab_terms'))
            .fontSize(14)
            .fontWeight(this.selectedTab === 0 ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.selectedTab === 0 ? $r('app.color.accent') : $r('app.color.text_secondary'))
            .height(38)

          Row()
            .width(48)
            .height(2)
            .backgroundColor(this.selectedTab === 0 ? $r('app.color.accent') : Color.Transparent)
            .borderRadius(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .id('privacy-terms-tab')
        .onClick(() => {
          this.selectedTab = 0;
        })

        // Privacy Tab
        Column() {
          Text($r('app.string.privacy_dialog_tab_privacy'))
            .fontSize(14)
            .fontWeight(this.selectedTab === 1 ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.selectedTab === 1 ? $r('app.color.accent') : $r('app.color.text_secondary'))
            .height(38)

          Row()
            .width(48)
            .height(2)
            .backgroundColor(this.selectedTab === 1 ? $r('app.color.accent') : Color.Transparent)
            .borderRadius(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .id('privacy-policy-tab')
        .onClick(() => {
          this.selectedTab = 1;
        })
      }
      .width('100%')
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })

      // Document Content
      Scroll() {
        Column() {
          // Document Header with external link
          Row() {
            Text(this.selectedTab === 0
              ? $r('app.string.privacy_dialog_terms_title')
              : $r('app.string.privacy_dialog_privacy_title'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))

            Text($r('app.string.privacy_dialog_open_web'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.accent'))
              .onClick(() => {
                this.onOpenUrl(this.selectedTab === 0 ? TERMS_URL : PRIVACY_URL);
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Center)
          .margin({ bottom: 12 })

          // Sections
          ForEach(this.selectedTab === 0 ? TERMS_SECTIONS : PRIVACY_SECTIONS, (item: LegalSection) => {
            Column() {
              Text(item.title)
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .margin({ bottom: 4 })

              Text(item.body)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .lineHeight(18)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .margin({ bottom: 12 })
          }, (item: LegalSection) => item.title)
        }
        .width('100%')
        .padding(14)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.surface_subtle'))
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.border') })
    .clip(true)
  }

  @Builder
  private BottomActions() {
    Column() {
      // Agreement checkbox row
      Row({ space: 8 }) {
        Row() {
          if (this.isAgreed) {
            AppIcon({
              name: IconName.Check,
              glyphSize: 12,
              color: $r('app.color.accent_foreground'),
              strokeWidth: 2.2
            })
          }
        }
        .width(20)
        .height(20)
        .borderRadius(5)
        .border({
          width: 1.5,
          color: this.isAgreed ? $r('app.color.accent') : $r('app.color.border')
        })
        .backgroundColor(this.isAgreed ? $r('app.color.accent') : Color.Transparent)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)

        Text($r('app.string.privacy_dialog_agree_checkbox'))
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .lineHeight(18)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 12, bottom: 12 })
      .id('privacy-consent-checkbox')
      .enabled(!this.isSaving)
      .onClick(() => {
        this.isAgreed = !this.isAgreed;
      })

      // Agree button
      Button($r('app.string.privacy_dialog_agree_button'), { type: ButtonType.Normal })
        .width('100%')
        .height(46)
        .borderRadius(14)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .backgroundColor(this.isAgreed ? $r('app.color.accent') : $r('app.color.surface_subtle'))
        .fontColor(this.isAgreed ? $r('app.color.accent_foreground') : $r('app.color.text_secondary'))
        .id('privacy-consent-accept')
        .enabled(this.isAgreed && !this.isSaving)
        .onClick(() => {
          if (this.isAgreed && !this.isSaving) {
            this.onAccept();
          }
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
