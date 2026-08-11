import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserLayoutClass,
  BrowserWindowMode,
  createWindowMetrics
} from '../main/ets/models/WindowMetrics';

export default function windowMetricsTest(): void {
  describe('WindowMetrics responsive classification', (): void => {
    it('classifies exact width boundaries from the available window width', 0, (): void => {
      expect(createWindowMetrics(599, 900, BrowserWindowMode.Floating).layoutClass)
        .assertEqual(BrowserLayoutClass.Compact);
      expect(createWindowMetrics(600, 900, BrowserWindowMode.Floating).layoutClass)
        .assertEqual(BrowserLayoutClass.Medium);
      expect(createWindowMetrics(839, 900, BrowserWindowMode.Floating).layoutClass)
        .assertEqual(BrowserLayoutClass.Medium);
      expect(createWindowMetrics(840, 900, BrowserWindowMode.Floating).layoutClass)
        .assertEqual(BrowserLayoutClass.Expanded);
      expect(createWindowMetrics(1439, 900, BrowserWindowMode.Floating).layoutClass)
        .assertEqual(BrowserLayoutClass.Expanded);
      expect(createWindowMetrics(1440, 900, BrowserWindowMode.Floating).layoutClass)
        .assertEqual(BrowserLayoutClass.Desktop);
    });

    it('records height constraints and window mode without changing width class', 0, (): void => {
      const metrics = createWindowMetrics(900, 420, BrowserWindowMode.Split);

      expect(metrics.layoutClass).assertEqual(BrowserLayoutClass.Expanded);
      expect(metrics.isHeightConstrained).assertTrue();
      expect(metrics.aspectRatio).assertLarger(2);
      expect(metrics.windowMode).assertEqual(BrowserWindowMode.Split);
    });

    it('normalizes invalid dimensions at the input boundary', 0, (): void => {
      const metrics = createWindowMetrics(-1, Number.NaN, BrowserWindowMode.Unknown);

      expect(metrics.widthVp).assertEqual(0);
      expect(metrics.heightVp).assertEqual(0);
      expect(metrics.aspectRatio).assertEqual(0);
      expect(metrics.layoutClass).assertEqual(BrowserLayoutClass.Compact);
      expect(metrics.isHeightConstrained).assertTrue();
    });
  });
}
