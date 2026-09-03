import { describe, expect, it } from '@ohos/hypium'
import { PendingPurchaseRecovery, PurchaseRecoveryResult } from '../main/ets/models/PendingPurchaseRecovery'

export default function pendingPurchaseRecoveryTest(): void {
  describe('PendingPurchaseRecovery', () => {
    it('retries verification errors before reporting recovery', 0, async () => {
      let attempts = 0
      let errors = 0
      const recovery = new PendingPurchaseRecovery()
      const result = await recovery.run(async (): Promise<boolean> => {
        attempts += 1
        if (attempts === 1) {
          throw new Error('Verification unavailable')
        }
        return attempts === 3
      }, () => { errors += 1 }, [0, 1, 1])
      expect(result).assertEqual(PurchaseRecoveryResult.RECOVERED)
      expect(attempts).assertEqual(3)
      expect(errors).assertEqual(1)
    })

    it('bounds unsuccessful recovery attempts', 0, async () => {
      let attempts = 0
      const result = await new PendingPurchaseRecovery().run(async (): Promise<boolean> => {
        attempts += 1
        return false
      }, () => {}, [0, 1, 1])
      expect(result).assertEqual(PurchaseRecoveryResult.EXHAUSTED)
      expect(attempts).assertEqual(3)
    })

    it('ignores successful responses after cancellation', 0, async () => {
      const recovery = new PendingPurchaseRecovery()
      const result = await recovery.run(async (): Promise<boolean> => {
        recovery.cancel()
        return true
      }, () => {})
      expect(result).assertEqual(PurchaseRecoveryResult.CANCELLED)
    })

    it('cancels scheduled retries without leaving a pending promise', 0, async () => {
      const recovery = new PendingPurchaseRecovery()
      let attempts = 0
      const running = recovery.run(async (): Promise<boolean> => {
        attempts += 1
        return false
      }, () => {}, [0, 10000])
      setTimeout(() => recovery.cancel(), 5)
      expect(await running).assertEqual(PurchaseRecoveryResult.CANCELLED)
      expect(attempts).assertEqual(1)
    })
  })
}
