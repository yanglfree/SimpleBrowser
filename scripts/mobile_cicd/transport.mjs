const retryableStatus = status => [408, 429].includes(status) || status >= 500;
const retryableError = error => ['TypeError', 'TimeoutError', 'AbortError'].includes(error?.name);

// Buffer the body within the retry boundary: a TLS reset can happen after headers.
// Callers use this only for reads, immutable PUTs and idempotent release operations.
export async function requestBytes(url, init = {}, {
  fetchImpl = fetch,
  sleep = ms => new Promise(resolve => setTimeout(resolve, ms)),
  attempts = 4,
  timeoutMs = 180000,
  onRetry = attempt => console.warn(`Retrying distribution request (${attempt}/${attempts})`),
} = {}) {
  for (let attempt = 1; attempt <= attempts; attempt++) {
    let response;
    try {
      response = await fetchImpl(url, { ...init, redirect: 'error', signal: AbortSignal.timeout(timeoutMs) });
      const bytes = await response.arrayBuffer();
      if (!retryableStatus(response.status) || attempt === attempts) {
        return new Response(init.method === 'HEAD' || [204, 205, 304].includes(response.status) ? null : bytes, {
          status: response.status, statusText: response.statusText, headers: response.headers,
        });
      }
    } catch (error) {
      if (!retryableError(error) || attempt === attempts) throw error;
    }
    onRetry(attempt + 1);
    await sleep(1000 * 2 ** (attempt - 1));
  }
  throw new Error('Distribution request exhausted attempts');
}
