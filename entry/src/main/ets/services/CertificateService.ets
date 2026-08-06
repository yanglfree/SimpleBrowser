import { cert } from '@kit.DeviceCertificateKit';
import { Logger } from '../utils/Logger';
import { CertificateSummary } from '../models/BrowserModels';

const TAG: string = 'CertificateService';

/**
 * Parses DER certificate chains delivered by ArkWeb's ssl-error callback into
 * the human-readable summary shown in the security panel. Kept inside a service
 * so the page does not know about X.509 decoding.
 */
export class CertificateService {
  static async summarizeChain(chain: Array<Uint8Array>): Promise<CertificateSummary | undefined> {
    if (chain.length === 0) {
      return undefined;
    }
    const leaf: Uint8Array = chain[0];
    try {
      const x509: cert.X509Cert = await cert.createX509Cert({
        data: leaf,
        encodingFormat: cert.EncodingFormat.FORMAT_DER
      });
      const subject: string = x509.getSubjectX500DistinguishedName().toString();
      const issuer: string = x509.getIssuerX500DistinguishedName().toString();
      const validFrom: string = x509.getNotBeforeTime();
      const validTo: string = x509.getNotAfterTime();
      return {
        subject: CertificateService.readableName(subject),
        issuer: CertificateService.readableName(issuer),
        validFrom: validFrom,
        validTo: validTo
      };
    } catch (error) {
      Logger.warn(TAG, `Certificate parse failed: ${(error as Error).message ?? error}`);
      return undefined;
    }
  }

  /**
   * X.500 names come back as RFC 2253 ("CN=example.com,O=Acme,C=US"). The
   * common name is what users recognise; the rest is noise in this panel.
   */
  private static readableName(dn: string): string {
    const match: RegExpMatchArray | null = dn.match(/CN=([^,]+)/);
    return match !== null ? match[1] : dn;
  }
}
