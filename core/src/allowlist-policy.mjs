import { isHomeUrl, rawHost } from './url-policy.mjs';

export function isHostAllowed(hosts, host) {
  return host.length > 0 && hosts.includes(host);
}

export function setHostAllowed(hosts, host, allowed) {
  if (host.length === 0) {
    return hosts.slice();
  }
  const without = hosts.filter((item) => item !== host);
  return allowed ? without.concat([host]) : without;
}

export function adsBlockEnabledForUrl(url, hosts, blockAds) {
  if (!blockAds || isHomeUrl(url)) {
    return false;
  }
  return !isHostAllowed(hosts, rawHost(url));
}
