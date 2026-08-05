import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN_ID: number = 0x0000;

export class Logger {
  static debug(tag: string, message: string): void {
    hilog.debug(DOMAIN_ID, tag, message);
  }

  static info(tag: string, message: string): void {
    hilog.info(DOMAIN_ID, tag, message);
  }

  static warn(tag: string, message: string): void {
    hilog.warn(DOMAIN_ID, tag, message);
  }

  static error(tag: string, message: string): void {
    hilog.error(DOMAIN_ID, tag, message);
  }
}
