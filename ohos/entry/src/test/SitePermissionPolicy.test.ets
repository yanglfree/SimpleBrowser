import { Permissions } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import {
  APPROXIMATE_LOCATION_PERMISSION,
  CAMERA_PERMISSION,
  MICROPHONE_PERMISSION,
  PRECISE_LOCATION_PERMISSION,
  nativePermissionResultAllows,
  nativePermissionsForSiteResources
} from '../main/ets/services/SitePermissionPolicy';

export default function sitePermissionPolicyTest(): void {
  describe('Site permission policy', (): void => {
    it('requests precise and approximate permissions for web geolocation', 0, (): void => {
      const permissions: Permissions[] = nativePermissionsForSiteResources(['LOCATION']);
      expect(permissions.length).assertEqual(2);
      expect(permissions.includes(PRECISE_LOCATION_PERMISSION)).assertTrue();
      expect(permissions.includes(APPROXIMATE_LOCATION_PERMISSION)).assertTrue();
    });

    it('accepts either location grant while requiring requested media grants', 0, (): void => {
      const resources: string[] = ['TYPE_VIDEO_CAPTURE', 'TYPE_AUDIO_CAPTURE', 'LOCATION'];
      const permissions: Permissions[] = [
        CAMERA_PERMISSION,
        MICROPHONE_PERMISSION,
        PRECISE_LOCATION_PERMISSION,
        APPROXIMATE_LOCATION_PERMISSION
      ];
      expect(nativePermissionResultAllows(resources, permissions, [0, 0, -1, 0])).assertTrue();
      expect(nativePermissionResultAllows(resources, permissions, [0, -1, 0, 0])).assertFalse();
      expect(nativePermissionResultAllows(resources, permissions, [0, 0, -1, -1])).assertFalse();
    });
  });
}
