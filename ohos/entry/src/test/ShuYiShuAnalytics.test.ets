import { describe, expect, it } from '@ohos/hypium';
import {
  ShuYiShuAnalytics,
  ShuYiShuAnalyticsOptions,
  ShuYiShuJsonObject,
  ShuYiShuTransport,
  ShuYiShuTransportRequest,
  ShuYiShuTransportResponse
} from '../main/ets/services/ShuYiShuAnalytics';

// ArkTS only lets a class implement the transport interface, so tests capture requests here.
class CapturingTransport implements ShuYiShuTransport {
  private readonly bodies: string[];
  private readonly statusCode: number;

  public constructor(bodies: string[], statusCode: number) {
    this.bodies = bodies;
    this.statusCode = statusCode;
  }

  public postJson(request: ShuYiShuTransportRequest): Promise<ShuYiShuTransportResponse> {
    this.bodies.push(request.body);
    const response: ShuYiShuTransportResponse = { statusCode: this.statusCode, body: '' };
    return Promise.resolve(response);
  }
}

// The ArkTS-safe replacements for object spread are easy to get subtly wrong, so these
// pin the merge semantics the analytics payload depends on.
function createOptions(
  bodies: string[],
  statusCode: number = 200,
  retryAttempts: number = 0
): ShuYiShuAnalyticsOptions {
  const options: ShuYiShuAnalyticsOptions = {
    baseUrl: 'https://collect.example.test',
    appKey: 'test-app-key',
    productId: 'test-product',
    platform: 'harmony',
    appVersion: '1.0.0',
    buildNumber: '1',
    installationId: 'install-test',
    locale: 'zh-CN',
    timezone: 'Asia/Shanghai',
    consentState: 'granted',
    retryAttempts: retryAttempts,
    delay: (durationMs: number): Promise<void> => {
      return Promise.resolve();
    },
    transport: new CapturingTransport(bodies, statusCode)
  };
  return options;
}

export default function shuYiShuAnalyticsTest(): void {
  describe('ShuYiShu analytics payload', (): void => {
    it('adds screen context without mutating the caller properties', 0, async (): Promise<void> => {
      const bodies: string[] = [];
      const client: ShuYiShuAnalytics = new ShuYiShuAnalytics(createOptions(bodies));

      client.screen('start');
      const properties: ShuYiShuJsonObject = { name: 'detail' };
      client.screen('detail', properties);
      await client.flush();

      expect(properties.previous_screen === undefined).assertTrue();
      expect(properties.screen === undefined).assertTrue();
      expect(bodies.length).assertEqual(1);
      expect(bodies[0].includes('"previous_screen":"start"')).assertTrue();
      expect(bodies[0].includes('"screen":"detail"')).assertTrue();
    });

    it('lets caller-supplied session counts override the computed ones', 0, async (): Promise<void> => {
      const bodies: string[] = [];
      const client: ShuYiShuAnalytics = new ShuYiShuAnalytics(createOptions(bodies));

      client.startSession();
      client.track('tab_open');
      client.endSession({ event_count: 99, end_reason: 'manual' });
      await client.flush();

      expect(bodies.length).assertEqual(1);
      expect(bodies[0].includes('"event_count":99')).assertTrue();
      expect(bodies[0].includes('"event_count":1')).assertFalse();
      // screen_count was not supplied, so the computed value survives the merge.
      expect(bodies[0].includes('"screen_count":0')).assertTrue();
      expect(bodies[0].includes('"end_reason":"manual"')).assertTrue();
    });

    it('restores the batch and rethrows when ingestion keeps failing', 0, async (): Promise<void> => {
      const bodies: string[] = [];
      const client: ShuYiShuAnalytics = new ShuYiShuAnalytics(createOptions(bodies, 500, 1));

      client.track('tab_open');
      let threw: boolean = false;
      try {
        await client.flush();
      } catch (error) {
        threw = true;
      }

      expect(threw).assertTrue();
      expect(bodies.length).assertEqual(2);
      expect(client.pendingCount).assertEqual(1);
    });

    it('drops the queue once consent is denied', 0, async (): Promise<void> => {
      const bodies: string[] = [];
      const client: ShuYiShuAnalytics = new ShuYiShuAnalytics(createOptions(bodies));

      client.track('tab_open');
      expect(client.pendingCount).assertEqual(1);
      client.setConsent('denied');
      expect(client.pendingCount).assertEqual(0);

      await client.flush();
      expect(bodies.length).assertEqual(0);
    });
  });
}
