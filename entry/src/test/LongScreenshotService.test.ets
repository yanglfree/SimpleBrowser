import { describe, expect, it } from '@ohos/hypium';
import {
  computeScrollSlices,
  parsePageMetrics,
  PageMetrics,
  ScrollSlice,
  PAGE_PREPARE_SCRIPT,
  PAGE_RESTORE_SCRIPT
} from '../main/ets/services/LongScreenshotService';

export default function longScreenshotServiceTest(): void {
  describe('LongScreenshotService test', (): void => {
    it('parses valid page metrics json string', 0, (): void => {
      const raw: string = JSON.stringify({
        totalHeight: 3200,
        viewportHeight: 800,
        viewportWidth: 360,
        scrollY: 150,
        dpr: 3
      });
      const metrics: PageMetrics | undefined = parsePageMetrics(raw);
      expect(metrics !== undefined).assertTrue();
      expect(metrics?.totalHeight).assertEqual(3200);
      expect(metrics?.viewportHeight).assertEqual(800);
      expect(metrics?.scrollY).assertEqual(150);
    });

    it('parses double-escaped json string from runScript', 0, (): void => {
      const raw: string = JSON.stringify(JSON.stringify({
        totalHeight: 2400,
        viewportHeight: 600,
        viewportWidth: 400,
        scrollY: 0,
        dpr: 2
      }));
      const metrics: PageMetrics | undefined = parsePageMetrics(raw);
      expect(metrics !== undefined).assertTrue();
      expect(metrics?.totalHeight).assertEqual(2400);
      expect(metrics?.viewportHeight).assertEqual(600);
    });

    it('returns single slice if page fits in one viewport', 0, (): void => {
      const slices: ScrollSlice[] = computeScrollSlices(600, 800);
      expect(slices.length).assertEqual(1);
      expect(slices[0].scrollY).assertEqual(0);
      expect(slices[0].clipTopRatio).assertEqual(0);
      expect(slices[0].clipHeightRatio).assertEqual(1.0);
    });

    it('computes exact full-screen slices when total is integer multiple', 0, (): void => {
      const slices: ScrollSlice[] = computeScrollSlices(2400, 800);
      expect(slices.length).assertEqual(3);
      expect(slices[0].scrollY).assertEqual(0);
      expect(slices[1].scrollY).assertEqual(800);
      expect(slices[2].scrollY).assertEqual(1600);
      expect(slices[2].clipTopRatio).assertEqual(0);
      expect(slices[2].clipHeightRatio).assertEqual(1.0);
    });

    it('computes remainder slice correctly for trailing page content', 0, (): void => {
      const slices: ScrollSlice[] = computeScrollSlices(2600, 1000);
      expect(slices.length).assertEqual(3);
      // Slice 0: [0..1000]
      expect(slices[0].scrollY).assertEqual(0);
      expect(slices[0].clipHeightRatio).assertEqual(1.0);
      // Slice 1: [1000..2000]
      expect(slices[1].scrollY).assertEqual(1000);
      expect(slices[1].clipHeightRatio).assertEqual(1.0);
      // Slice 2: [2000..2600] -> scrolled to 1600 (2600 - 1000), remainder = 600
      expect(slices[2].scrollY).assertEqual(1600);
      expect(slices[2].clipTopRatio).assertEqual(0.4); // (1000 - 600) / 1000 = 0.4
      expect(slices[2].clipHeightRatio).assertEqual(0.6); // 600 / 1000 = 0.6
    });

    it('caps slices at maxScreens limit', 0, (): void => {
      const slices: ScrollSlice[] = computeScrollSlices(50000, 1000, 5);
      expect(slices.length).assertEqual(5);
    });

    it('contains valid dom preparation and restoration scripts', 0, (): void => {
      expect(PAGE_PREPARE_SCRIPT.includes('__zhuo_long_shot_style')).assertTrue();
      expect(PAGE_PREPARE_SCRIPT.includes('position')).assertTrue();
      expect(PAGE_RESTORE_SCRIPT.includes('__zhuo_long_shot_style')).assertTrue();
      expect(PAGE_RESTORE_SCRIPT.includes('data-zhuo-orig-visibility')).assertTrue();
    });
  });
}
