export type MemoryPressureHandler = (level: number) => void;

/** Bridges UIAbility memory callbacks to the mounted browser surface. */
export class MemoryPressureService {
  private static handler: MemoryPressureHandler | undefined;

  static register(handler: MemoryPressureHandler): void {
    MemoryPressureService.handler = handler;
  }

  static unregister(): void {
    MemoryPressureService.handler = undefined;
  }

  static notify(level: number): void {
    const handler: MemoryPressureHandler | undefined = MemoryPressureService.handler;
    if (handler !== undefined) {
      handler(level);
    }
  }
}
