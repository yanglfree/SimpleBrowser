import { AppIcon, IconName } from './AppIcon';
import { AppMetadataService } from '../services/AppMetadataService';
import { FeedbackService } from '../services/FeedbackService';
import {
  FEEDBACK_MESSAGE_MAX_LENGTH,
  validateFeedbackMessage
} from '../models/FeedbackModels';

@Component
export struct FeedbackSheet {
  @Prop isWide: boolean = false;
  appVersion: string = '';
  onDismiss: () => void = (): void => {};

  @State private message: string = '';
  @State private contact: string = '';
  @State private isSubmitting: boolean = false;
  @State private errorMessage: ResourceStr = '';

  build() {
    Stack({ alignContent: this.isWide ? Alignment.Center : Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => {
          if (!this.isSubmitting) {
            this.onDismiss();
          }
        })

      Column({ space: 14 }) {
        if (!this.isWide) {
          Row()
            .width(36)
            .height(4)
            .borderRadius(2)
            .backgroundColor($r('app.color.handle'))
        }

        Row({ space: 10 }) {
          Text($r('app.string.feedback_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          AppIcon({ name: IconName.Close, glyphSize: 16, color: $r('app.color.text_secondary') })
            .onClick(() => {
              if (!this.isSubmitting) {
                this.onDismiss();
              }
            })
        }
        .width('100%')

        TextArea({ text: this.message, placeholder: $r('app.string.feedback_hint') })
          .id('feedback-message-input')
          .width('100%')
          .height(130)
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface_subtle'))
          .borderRadius(12)
          .caretColor($r('app.color.accent'))
          .maxLength(FEEDBACK_MESSAGE_MAX_LENGTH)
          .showCounter(true)
          .enabled(!this.isSubmitting)
          .focusable(true)
          .enableKeyboardOnFocus(true)
          .defaultFocus(true)
          .onAppear(() => {
            focusControl.requestFocus('feedback-message-input');
          })
          .onChange((value: string): void => {
            this.message = value;
            if (this.errorMessage !== '') {
              this.errorMessage = '';
            }
          })

        TextInput({ text: this.contact, placeholder: $r('app.string.feedback_contact_placeholder') })
          .id('feedback-contact-input')
          .width('100%')
          .height(46)
          .padding({ left: 14, right: 14 })
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface_subtle'))
          .borderRadius(12)
          .caretColor($r('app.color.accent'))
          .enabled(!this.isSubmitting)
          .focusable(true)
          .enableKeyboardOnFocus(true)
          .onChange((value: string): void => {
            this.contact = value;
          })

        if (this.errorMessage !== '') {
          Text(this.errorMessage)
            .width('100%')
            .fontSize(13)
            .fontColor($r('app.color.danger'))
            .textAlign(TextAlign.Start)
        }

        Row({ space: 12 }) {
          Row() {
            Text($r('app.string.cancel'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
          }
          .height(46)
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .borderRadius(12)
          .backgroundColor($r('app.color.surface_subtle'))
          .onClick(() => {
            if (!this.isSubmitting) {
              this.onDismiss();
            }
          })

          Row() {
            if (this.isSubmitting) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color($r('app.color.content_background'))
                .margin({ right: 6 })
            }
            Text(this.isSubmitting ? $r('app.string.feedback_submitting') : $r('app.string.feedback_submit'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.content_background'))
          }
          .height(46)
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .borderRadius(12)
          .backgroundColor($r('app.color.accent'))
          .onClick(() => {
            if (!this.isSubmitting) {
              void this.submit();
            }
          })
        }
        .width('100%')
      }
      .width(this.isWide ? '88%' : '100%')
      .constraintSize({ maxWidth: this.isWide ? 520 : '100%' })
      .padding({ top: this.isWide ? 24 : 10, left: 24, right: 24, bottom: this.isWide ? 24 : 42 })
      .backgroundColor($r('app.color.surface_panel'))
      .borderRadius(this.isWide ? 20 : { topLeft: 20, topRight: 20 })
      .border({ width: this.isWide ? 1 : 0, color: $r('app.color.border') })
      .shadow(this.isWide ? { radius: 18, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: 6 } : undefined)
      .onClick((): void => {})
    }
    .width('100%')
    .height('100%')
  }

  private async submit(): Promise<void> {
    const errorKind = validateFeedbackMessage(this.message);
    if (errorKind === 'too_short') {
      this.errorMessage = $r('app.string.feedback_too_short');
      return;
    }
    if (errorKind === 'too_long') {
      this.errorMessage = $r('app.string.feedback_too_long');
      return;
    }

    this.errorMessage = '';
    this.isSubmitting = true;

    try {
      const version: string = this.appVersion.length > 0 ? this.appVersion : AppMetadataService.getVersionName();
      const packageName: string = AppMetadataService.getPackageName();
      const versionCode: number = AppMetadataService.getVersionCode();

      await FeedbackService.submit({
        message: this.message,
        contact: this.contact.trim(),
        appVersion: version,
        packageName: packageName,
        metadata: {
          'version_code': versionCode,
          'platform': 'harmonyos'
        }
      });

      try {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.feedback_submitted')
        });
      } catch (_e) {
        // toast fallback
      }

      this.onDismiss();
    } catch (error) {
      this.isSubmitting = false;
      this.errorMessage = $r('app.string.feedback_submit_failed');
      try {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.feedback_submit_failed')
        });
      } catch (_e) {
        // toast fallback
      }
    }
  }
}
