import { common } from '@kit.AbilityKit';

export class AppContext {
  private static abilityContexts: Map<string, common.UIAbilityContext> = new Map();

  static setContext(token: string, context: common.UIAbilityContext): void {
    AppContext.abilityContexts.set(token, context);
  }

  static getContext(token: string): common.UIAbilityContext {
    const context: common.UIAbilityContext | undefined = AppContext.abilityContexts.get(token);
    if (context === undefined) {
      throw new Error(`Ability context is not available for window ${token}`);
    }
    return context;
  }

  static removeContext(token: string): void {
    AppContext.abilityContexts.delete(token);
  }
}
