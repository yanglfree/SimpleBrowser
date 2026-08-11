import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { Logger } from '../utils/Logger';

const TAG: string = 'HomeBackgroundService';
const CUSTOM_BACKGROUND_FILE: string = 'home_background_custom.image';

export class HomeBackgroundService {
  static async selectCustomImage(context: common.UIAbilityContext): Promise<string | undefined> {
    try {
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result: photoAccessHelper.PhotoSelectResult =
        await new photoAccessHelper.PhotoViewPicker().select(options);
      if (result.photoUris.length === 0) {
        return undefined;
      }
      const targetPath: string = `${context.filesDir}/${CUSTOM_BACKGROUND_FILE}`;
      const source: fileIo.File = fileIo.openSync(result.photoUris[0], fileIo.OpenMode.READ_ONLY);
      try {
        const target: fileIo.File = fileIo.openSync(
          targetPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
        );
        try {
          fileIo.copyFileSync(source.fd, target.fd);
        } finally {
          fileIo.closeSync(target);
        }
      } finally {
        fileIo.closeSync(source);
      }
      return fileUri.getUriFromPath(targetPath);
    } catch (error) {
      Logger.warn(TAG, `Failed to import a custom background: ${String(error)}`);
      return undefined;
    }
  }
}
