export type PurchaseRecoveryResult = 'recovered' | 'exhausted' | 'cancelled'

export const PurchaseRecoveryResult = {
  RECOVERED: 'recovered' as PurchaseRecoveryResult,
  EXHAUSTED: 'exhausted' as PurchaseRecoveryResult,
  CANCELLED: 'cancelled' as PurchaseRecoveryResult
}

export class PendingPurchaseRecovery {
  private generation: number = 0
  private timer: number = -1
  private releaseWait: (() => void) | null = null

  cancel(): void {
    this.generation += 1
    if (this.timer >= 0) {
      clearTimeout(this.timer)
      this.timer = -1
    }
    if (this.releaseWait !== null) {
      this.releaseWait()
      this.releaseWait = null
    }
  }

  async run(restore: () => Promise<boolean>, onError: () => void,
    delays: number[] = [0, 3000, 8000]): Promise<PurchaseRecoveryResult> {
    this.cancel()
    const generation = this.generation
    for (const delay of delays) {
      if (delay > 0) {
        await new Promise<void>((resolve: () => void) => {
          this.releaseWait = resolve
          this.timer = setTimeout(() => {
            this.timer = -1
            this.releaseWait = null
            resolve()
          }, delay) as number
        })
      }
      if (generation !== this.generation) {
        return PurchaseRecoveryResult.CANCELLED
      }
      let restored = false
      try {
        restored = await restore()
      } catch (error) {
        onError()
      }
      if (generation !== this.generation) {
        return PurchaseRecoveryResult.CANCELLED
      }
      if (restored) {
        return PurchaseRecoveryResult.RECOVERED
      }
    }
    return PurchaseRecoveryResult.EXHAUSTED
  }
}
