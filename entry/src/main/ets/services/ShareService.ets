import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { Logger } from '../utils/Logger';

const TAG: string = 'ShareService';

export enum ShareOutcome {
  Shared = 0,
  Copied = 1,
  Failed = 2
}

export class ShareService {
  /**
   * Hands the link to the system share sheet. Devices without one still get a
   * usable result: the URL lands on the clipboard and the caller shows a toast.
   */
  static async share(context: common.UIAbilityContext, url: string, title: string): Promise<ShareOutcome> {
    if (url.length === 0) {
      return ShareOutcome.Failed;
    }
    try {
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
        uri: url,
        title: title.length > 0 ? title : url
      };
      const controller: systemShare.ShareController =
        new systemShare.ShareController(new systemShare.SharedData(record));
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
      return ShareOutcome.Shared;
    } catch (error) {
      Logger.warn(TAG, `System share unavailable, copying instead: ${String(error)}`);
      return await ShareService.copy(url);
    }
  }

  static async copy(url: string): Promise<ShareOutcome> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      await pasteboard.getSystemPasteboard().setData(data);
      return ShareOutcome.Copied;
    } catch (error) {
      Logger.error(TAG, `Failed to copy link: ${String(error)}`);
      return ShareOutcome.Failed;
    }
  }
}
