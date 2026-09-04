import { Permissions } from '@kit.AbilityKit';

const GRANTED: number = 0;

export const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';
export const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
export const PRECISE_LOCATION_PERMISSION: Permissions = 'ohos.permission.LOCATION';
export const APPROXIMATE_LOCATION_PERMISSION: Permissions = 'ohos.permission.APPROXIMATELY_LOCATION';

export function nativePermissionsForSiteResources(resources: string[]): Permissions[] {
  const permissions: Permissions[] = [];
  if (resources.includes('TYPE_VIDEO_CAPTURE')) {
    permissions.push(CAMERA_PERMISSION);
  }
  if (resources.includes('TYPE_AUDIO_CAPTURE')) {
    permissions.push(MICROPHONE_PERMISSION);
  }
  if (resources.includes('LOCATION')) {
    permissions.push(PRECISE_LOCATION_PERMISSION, APPROXIMATE_LOCATION_PERMISSION);
  }
  return permissions;
}

export function nativePermissionResultAllows(
  resources: string[],
  permissions: Permissions[],
  authResults: number[]
): boolean {
  if (permissions.length !== authResults.length) {
    return false;
  }
  const resultFor = (permission: Permissions): number | undefined => {
    const index: number = permissions.indexOf(permission);
    return index < 0 ? undefined : authResults[index];
  };
  if (resources.includes('TYPE_VIDEO_CAPTURE') && resultFor(CAMERA_PERMISSION) !== GRANTED) {
    return false;
  }
  if (resources.includes('TYPE_AUDIO_CAPTURE') && resultFor(MICROPHONE_PERMISSION) !== GRANTED) {
    return false;
  }
  if (resources.includes('LOCATION') && resultFor(PRECISE_LOCATION_PERMISSION) !== GRANTED &&
    resultFor(APPROXIMATE_LOCATION_PERMISSION) !== GRANTED) {
    return false;
  }
  return true;
}
