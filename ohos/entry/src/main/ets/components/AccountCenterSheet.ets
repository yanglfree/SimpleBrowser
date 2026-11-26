import { common } from '@kit.AbilityKit';
import { RemoteDeviceTabEntry, RemoteDeviceTabGroup } from '../models/AccountSyncModels';
import { AccountAuthService } from '../services/AccountAuthService';
import { AppIcon, IconName } from './AppIcon';

@Component
export struct AccountCenterSheet {
  @Prop topInset: number = 0;
  @Prop isPro: boolean = false;
  @Prop remoteDeviceTabs: RemoteDeviceTabGroup[] = [];
  onSyncNow: () => Promise<boolean> = async (): Promise<boolean> => false;
  onOpenUrl: (url: string) => void = (_url: string): void => {};
  onAuthChanged: () => void = (): void => {};
  onDismiss: () => void = (): void => {};

  @State private useOtpMode: boolean = true;
  @State private isRegisterMode: boolean = false;
  @State private emailInput: string = '';
  @State private otpCodeInput: string = '';
  @State private passwordInput: string = '';
  @State private displayNameInput: string = '';
  @State private isBusy: boolean = false;
  @State private errorText: string = '';
  @State private otpSent: boolean = false;
  @State private showDeleteConfirm: boolean = false;
  @State private loggedIn: boolean = false;
  @State private googleAllowed: boolean = false;

  private auth: AccountAuthService = AccountAuthService.getInstance();

  aboutToAppear(): void {
    this.refreshLocalState();
  }

  private refreshLocalState(): void {
    this.loggedIn = this.auth.isLoggedIn();
    this.googleAllowed = this.auth.isGoogleSignInAvailableForDevice();
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        AppIcon({ name: IconName.ArrowLeft, glyphSize: 21, color: $r('app.color.text_primary') })
          .id('account-back-button')
          .onClick((): void => this.onDismiss())
        Text($r('app.string.account_center_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.topInset + 16, bottom: 12 })

      Scroll() {
        Column({ space: 16 }) {
          if (this.loggedIn) {
            this.LoggedInBody()
          } else {
            this.LoginBody()
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 32 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private LoggedInBody() {
    Column({ space: 10 }) {
      Text(this.auth.getCurrentUser()?.displayName ?? '')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(this.auth.getCurrentUser()?.email ?? '')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      if (this.isPro) {
        Text($r('app.string.account_pro_active'))
          .fontSize(13)
          .fontColor($r('app.color.accent'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(18)
    .borderRadius(16)
    .backgroundColor($r('app.color.surface_panel'))
    .border({ width: 1, color: $r('app.color.border') })

    Button(this.isBusy ? $r('app.string.account_syncing') : $r('app.string.account_sync_now'))
      .id('account-sync-now-button')
      .width('100%')
      .height(48)
      .backgroundColor($r('app.color.accent'))
      .fontColor($r('app.color.accent_foreground'))
      .enabled(!this.isBusy)
      .onClick((): void => {
        void this.handleSyncNow();
      })

    if (this.errorText.length > 0) {
      Text(this.errorText)
        .fontSize(13)
        .fontColor($r('app.color.danger'))
        .width('100%')
    }

    if (this.remoteDeviceTabs.length > 0) {
      Column({ space: 8 }) {
        Text($r('app.string.sync_remote_tabs_title'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        ForEach(this.remoteDeviceTabs, (group: RemoteDeviceTabGroup) => {
          Column({ space: 6 }) {
            Text(`${group.deviceName} (${group.platform})`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            ForEach(group.tabs.slice(0, 5), (tab: RemoteDeviceTabEntry) => {
              Row() {
                Text(tab.title)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })
              .onClick((): void => {
                this.onOpenUrl(tab.url);
                this.onDismiss();
              })
            }, (tab: RemoteDeviceTabEntry): string => tab.id)
          }
          .width('100%')
        }, (group: RemoteDeviceTabGroup): string => group.deviceId)
      }
      .width('100%')
      .padding(16)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface_panel'))
      .border({ width: 1, color: $r('app.color.border') })
    }

    Button($r('app.string.account_logout'))
      .id('account-logout-button')
      .width('100%')
      .height(44)
      .backgroundColor($r('app.color.surface_subtle'))
      .fontColor($r('app.color.text_primary'))
      .onClick((): void => {
        void this.handleLogout();
      })

    if (!this.showDeleteConfirm) {
      Button($r('app.string.account_delete_action'))
        .id('account-delete-button')
        .width('100%')
        .height(44)
        .backgroundColor($r('app.color.surface_panel'))
        .fontColor($r('app.color.danger'))
        .onClick((): void => {
          this.showDeleteConfirm = true;
        })
    } else {
      Column({ space: 8 }) {
        Text($r('app.string.account_delete_confirm_message'))
          .fontSize(13)
          .fontColor($r('app.color.danger'))
          .width('100%')
        Row({ space: 12 }) {
          Button($r('app.string.cancel'))
            .layoutWeight(1)
            .backgroundColor($r('app.color.surface_subtle'))
            .fontColor($r('app.color.text_primary'))
            .onClick((): void => {
              this.showDeleteConfirm = false;
            })
          Button($r('app.string.account_delete_confirm_button'))
            .layoutWeight(1)
            .backgroundColor($r('app.color.danger'))
            .fontColor($r('app.color.accent_foreground'))
            .onClick((): void => {
              void this.handleDeleteAccount();
            })
        }
        .width('100%')
      }
      .padding(14)
      .borderRadius(14)
      .backgroundColor($r('app.color.surface_panel'))
      .border({ width: 1, color: $r('app.color.danger') })
    }
  }

  @Builder
  private LoginBody() {
    Row({ space: 10 }) {
      Button($r('app.string.auth_mode_otp'))
        .layoutWeight(1)
        .height(40)
        .backgroundColor(this.useOtpMode ? $r('app.color.accent') : $r('app.color.surface_subtle'))
        .fontColor(this.useOtpMode ? $r('app.color.accent_foreground') : $r('app.color.text_primary'))
        .onClick((): void => {
          this.useOtpMode = true;
          this.errorText = '';
        })
      Button($r('app.string.auth_mode_password'))
        .layoutWeight(1)
        .height(40)
        .backgroundColor(!this.useOtpMode ? $r('app.color.accent') : $r('app.color.surface_subtle'))
        .fontColor(!this.useOtpMode ? $r('app.color.accent_foreground') : $r('app.color.text_primary'))
        .onClick((): void => {
          this.useOtpMode = false;
          this.errorText = '';
        })
    }
    .width('100%')

    TextInput({ text: this.emailInput, placeholder: $r('app.string.auth_email_placeholder') })
      .id('account-email-input')
      .width('100%')
      .height(46)
      .backgroundColor($r('app.color.surface_subtle'))
      .borderRadius(12)
      .padding({ left: 14, right: 14 })
      .onChange((val: string): void => {
        this.emailInput = val;
      })

    if (this.useOtpMode) {
      Row({ space: 10 }) {
        TextInput({ text: this.otpCodeInput, placeholder: $r('app.string.auth_otp_placeholder') })
          .id('account-otp-input')
          .layoutWeight(1)
          .height(46)
          .backgroundColor($r('app.color.surface_subtle'))
          .borderRadius(12)
          .padding({ left: 14, right: 14 })
          .onChange((val: string): void => {
            this.otpCodeInput = val;
          })
        Button(this.otpSent ? $r('app.string.auth_email_otp_resend') : $r('app.string.auth_email_otp_send'))
          .id('account-send-otp-button')
          .height(46)
          .backgroundColor($r('app.color.surface_panel'))
          .fontColor($r('app.color.accent'))
          .border({ width: 1, color: $r('app.color.border') })
          .enabled(!this.isBusy && this.emailInput.trim().length > 0)
          .onClick((): void => {
            void this.handleSendOtp();
          })
      }
      .width('100%')
    } else {
      if (this.isRegisterMode) {
        TextInput({ text: this.displayNameInput, placeholder: $r('app.string.auth_display_name_placeholder') })
          .width('100%')
          .height(46)
          .backgroundColor($r('app.color.surface_subtle'))
          .borderRadius(12)
          .padding({ left: 14, right: 14 })
          .onChange((val: string): void => {
            this.displayNameInput = val;
          })
      }
      TextInput({ text: this.passwordInput, placeholder: $r('app.string.auth_password_placeholder') })
        .id('account-password-input')
        .type(InputType.Password)
        .width('100%')
        .height(46)
        .backgroundColor($r('app.color.surface_subtle'))
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .onChange((val: string): void => {
          this.passwordInput = val;
        })
    }

    if (this.errorText.length > 0) {
      Text(this.errorText)
        .fontSize(13)
        .fontColor($r('app.color.danger'))
        .width('100%')
    }

    Button(this.useOtpMode
      ? $r('app.string.auth_otp_submit')
      : (this.isRegisterMode ? $r('app.string.auth_register_submit') : $r('app.string.auth_login_submit')))
      .id('account-submit-button')
      .width('100%')
      .height(48)
      .backgroundColor($r('app.color.accent'))
      .fontColor($r('app.color.accent_foreground'))
      .enabled(!this.isBusy)
      .onClick((): void => {
        void this.handleEmailSubmit();
      })

    if (!this.useOtpMode) {
      Button(this.isRegisterMode ? $r('app.string.auth_switch_to_login') : $r('app.string.auth_switch_to_register'))
        .width('100%')
        .height(36)
        .backgroundColor($r('app.color.page_background'))
        .fontColor($r('app.color.accent'))
        .onClick((): void => {
          this.isRegisterMode = !this.isRegisterMode;
          this.errorText = '';
        })
    }

    Button($r('app.string.auth_huawei_sign_in'))
      .id('account-huawei-button')
      .width('100%')
      .height(46)
      .backgroundColor($r('app.color.surface_panel'))
      .fontColor($r('app.color.text_primary'))
      .border({ width: 1, color: $r('app.color.border') })
      .enabled(!this.isBusy)
      .onClick((): void => {
        void this.handleHuaweiLogin();
      })

    if (this.googleAllowed) {
      Button($r('app.string.auth_google_sign_in'))
        .id('account-google-button')
        .width('100%')
        .height(46)
        .backgroundColor($r('app.color.surface_panel'))
        .fontColor($r('app.color.text_primary'))
        .border({ width: 1, color: $r('app.color.border') })
        .enabled(!this.isBusy)
        .onClick((): void => {
          const url: string = this.auth.buildGoogleOAuthStartUrl();
          if (url.length > 0) {
            this.onOpenUrl(url);
            this.onDismiss();
          }
        })
    }
  }

  private async handleSendOtp(): Promise<void> {
    this.isBusy = true;
    this.errorText = '';
    const ok: boolean = await this.auth.sendEmailOtp(this.emailInput);
    this.isBusy = false;
    if (ok) {
      this.otpSent = true;
    } else {
      this.errorText = this.auth.lastError;
    }
  }

  private async handleEmailSubmit(): Promise<void> {
    const hostContext: Context | undefined = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      return;
    }
    this.isBusy = true;
    this.errorText = '';
    let ok: boolean = false;
    if (this.useOtpMode) {
      ok = await this.auth.verifyEmailOtp(hostContext, this.emailInput, this.otpCodeInput, this.displayNameInput);
    } else if (this.isRegisterMode) {
      ok = await this.auth.registerWithPassword(hostContext, this.emailInput, this.passwordInput, this.displayNameInput);
    } else {
      ok = await this.auth.loginWithPassword(hostContext, this.emailInput, this.passwordInput);
    }
    this.isBusy = false;
    if (ok) {
      this.refreshLocalState();
      this.onAuthChanged();
      void this.handleSyncNow();
    } else {
      this.errorText = this.auth.lastError;
    }
  }

  private async handleHuaweiLogin(): Promise<void> {
    const hostContext: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (hostContext === undefined) {
      return;
    }
    this.isBusy = true;
    this.errorText = '';
    const ok: boolean = await this.auth.signInWithHuawei(hostContext);
    this.isBusy = false;
    if (ok) {
      this.refreshLocalState();
      this.onAuthChanged();
      void this.handleSyncNow();
    } else {
      this.errorText = this.auth.lastError;
    }
  }

  private async handleSyncNow(): Promise<void> {
    this.isBusy = true;
    this.errorText = '';
    const ok: boolean = await this.onSyncNow();
    this.isBusy = false;
    if (!ok) {
      this.errorText = this.auth.lastError;
    }
  }

  private async handleLogout(): Promise<void> {
    const hostContext: Context | undefined = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      return;
    }
    await this.auth.logout(hostContext);
    this.refreshLocalState();
    this.onAuthChanged();
  }

  private async handleDeleteAccount(): Promise<void> {
    const hostContext: Context | undefined = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      return;
    }
    this.isBusy = true;
    const ok: boolean = await this.auth.deleteAccount(hostContext);
    this.isBusy = false;
    if (ok) {
      this.showDeleteConfirm = false;
      this.refreshLocalState();
      this.onAuthChanged();
      this.onDismiss();
    } else {
      this.errorText = this.auth.lastError;
    }
  }
}
