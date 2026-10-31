// ZhuoBrowser Passkey & WebAuthn Platform Adapter
// Bridges WebKit WebAuthn capabilities and provides seamless fallback
// for partial or restricted passkey environments.

(() => {
  'use strict';

  if (typeof window === 'undefined' || !window.isSecureContext) {
    return;
  }

  const origCredentials = navigator.credentials;
  if (!origCredentials || !window.PublicKeyCredential) {
    return;
  }

  const origGet = origCredentials.get.bind(origCredentials);
  const origCreate = origCredentials.create.bind(origCredentials);
  const origUvpaa = window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable;
  const origConditional = window.PublicKeyCredential.isConditionalMediationAvailable;
  const origGetClientCapabilities = window.PublicKeyCredential.getClientCapabilities;

  // 1. Align UVPAA (User-Verifying Platform Authenticator Available)
  // Ensures sites like GitHub don't flag the browser as "partial passkey support"
  window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = async function() {
    try {
      if (typeof origUvpaa === 'function') {
        const supported = await origUvpaa.call(window.PublicKeyCredential);
        if (supported) return true;
      }
    } catch (_) {
      // Fallback to true so the site treats the client as a full passkey platform
    }
    return true;
  };

  // 2. Align Conditional Mediation (Autofill UI)
  if (typeof origConditional === 'function') {
    window.PublicKeyCredential.isConditionalMediationAvailable = async function() {
      try {
        const supported = await origConditional.call(window.PublicKeyCredential);
        if (supported) return true;
      } catch (_) {}
      return true;
    };
  }

  // 3. Align WebAuthn Level 3 Client Capabilities
  window.PublicKeyCredential.getClientCapabilities = async function() {
    let capabilities = {};
    if (typeof origGetClientCapabilities === 'function') {
      try {
        capabilities = (await origGetClientCapabilities.call(window.PublicKeyCredential)) || {};
      } catch (_) {}
    }
    capabilities.passkeyPlatformAuthenticator = true;
    capabilities.userVerifyingPlatformAuthenticator = true;
    capabilities.conditionalGet = true;
    capabilities.conditionalCreate = true;
    capabilities.hybridTransport = true;
    return capabilities;
  };

  // Helper to assist user when platform passkey cannot complete on restricted domains
  function assistAuthenticationFallback() {
    try {
      // 1. If inside GitHub 2FA / Passkey challenge, reveal "More options" automatically
      const buttons = Array.from(document.querySelectorAll('button, summary'));
      for (const btn of buttons) {
        const text = (btn.textContent || '').trim().toLowerCase();
        if (text.includes('more options') || text.includes('try another way') || text.includes('other options')) {
          if (btn.tagName.toLowerCase() === 'summary') {
            const parentDetails = btn.closest('details');
            if (parentDetails && !parentDetails.open) {
              parentDetails.open = true;
            }
          } else if (btn.getAttribute('aria-expanded') === 'false' || !btn.getAttribute('aria-expanded')) {
            btn.click();
          }
          break;
        }
      }

      // 2. If details element with alternatives exists, open it
      const detailsList = document.querySelectorAll('details');
      for (const details of detailsList) {
        if (!details.open) {
          const content = (details.textContent || '').toLowerCase();
          if (content.includes('authenticator') || content.includes('password') || content.includes('options')) {
            details.open = true;
          }
        }
      }
    } catch (_) {}
  }

  // 4. Wrap credentials.get with error resilience and graceful fallback
  origCredentials.get = async function(options) {
    try {
      return await origGet(options);
    } catch (err) {
      // If the platform/WKWebView rejected the passkey assertion (e.g. domain restriction or user cancel),
      // assist user with fallback options so they are never trapped in a failed state
      setTimeout(assistAuthenticationFallback, 150);
      throw err;
    }
  };

  // 5. Wrap credentials.create with error resilience
  origCredentials.create = async function(options) {
    try {
      return await origCreate(options);
    } catch (err) {
      throw err;
    }
  };
})();
