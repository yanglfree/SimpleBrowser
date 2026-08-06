import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { image } from '@kit.ImageKit';
import { fileUri } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
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

  /** Encodes an in-memory page snapshot to a short-lived cache file for Share Kit. */
  static async shareImage(
    context: common.UIAbilityContext,
    pixelMap: image.PixelMap,
    title: string
  ): Promise<ShareOutcome> {
    const path: string = `${context.cacheDir}/minimal-browser-share-${Date.now()}.jpg`;
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const packer: image.ImagePacker = image.createImagePacker();
      const options: image.PackingOption = { format: 'image/jpeg', quality: 92 };
      await packer.packToFile(pixelMap, file.fd, options);
      fs.closeSync(file.fd);
      file = undefined;

      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(
          '.jpg', uniformTypeDescriptor.UniformDataType.IMAGE),
        uri: fileUri.getUriFromPath(path),
        title: title.length > 0 ? title : 'Browser page'
      };
      const controller: systemShare.ShareController =
        new systemShare.ShareController(new systemShare.SharedData(record));
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
      return ShareOutcome.Shared;
    } catch (error) {
      Logger.warn(TAG, `Page screenshot share unavailable: ${String(error)}`);
      return ShareOutcome.Failed;
    } finally {
      if (file !== undefined) {
        try {
          fs.closeSync(file.fd);
        } catch (_error) {
          Logger.warn(TAG, 'Failed to close screenshot cache file');
        }
      }
      try {
        fs.unlinkSync(path);
      } catch (_error) {
        // The cache file is best-effort cleanup only.
      }
    }
  }

  static async shareFile(
    context: common.UIAbilityContext,
    path: string,
    title: string
  ): Promise<ShareOutcome> {
    if (path.length === 0) {
      return ShareOutcome.Failed;
    }
    try {
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(`.${ShareService.extension(path)}`),
        uri: fileUri.getUriFromPath(path),
        title: title.length > 0 ? title : path
      };
      const controller: systemShare.ShareController =
        new systemShare.ShareController(new systemShare.SharedData(record));
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
      return ShareOutcome.Shared;
    } catch (error) {
      Logger.warn(TAG, `File share unavailable: ${String(error)}`);
      return ShareOutcome.Failed;
    }
  }

  private static extension(path: string): string {
    const name: string = path.split('/').pop() ?? '';
    const dot: number = name.lastIndexOf('.');
    return dot >= 0 && dot < name.length - 1 ? name.slice(dot + 1).toLowerCase() : 'octet-stream';
  }
}
