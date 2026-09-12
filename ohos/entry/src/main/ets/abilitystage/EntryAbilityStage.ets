import { AbilityStage, Want } from '@kit.AbilityKit';
import { resolveWindowInstanceId } from '../models/WindowLaunchPolicy';

export default class EntryAbilityStage extends AbilityStage {
  onAcceptWant(want: Want): string {
    const requestedToken: string = String(want.parameters?.['dolphin.windowToken'] ?? '');
    return resolveWindowInstanceId(requestedToken);
  }
}
