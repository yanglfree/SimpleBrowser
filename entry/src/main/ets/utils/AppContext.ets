import { common } from '@kit.AbilityKit';

export class AppContext {
  private static abilityContext: common.UIAbilityContext | undefined;

  static setContext(context: common.UIAbilityContext): void {
    AppContext.abilityContext = context;
  }

  static getContext(): common.UIAbilityContext {
    if (AppContext.abilityContext === undefined) {
      throw new Error('Ability context is not available');
    }
    return AppContext.abilityContext;
  }
}
