export const SitePermissionDecision = Object.freeze({
  Prompt: 0,
  Allow: 1,
  Deny: 2
});

export function emptySitePermission(origin) {
  return {
    origin: origin,
    camera: SitePermissionDecision.Prompt,
    microphone: SitePermissionDecision.Prompt,
    location: SitePermissionDecision.Prompt
  };
}

export function sitePermissionDecision(stored, kinds) {
  if (stored === undefined || stored === null) {
    return SitePermissionDecision.Prompt;
  }
  let result = SitePermissionDecision.Allow;
  for (const kind of kinds) {
    const decision = stored[kind];
    if (decision === undefined || decision === SitePermissionDecision.Deny) {
      return SitePermissionDecision.Deny;
    }
    if (decision === SitePermissionDecision.Prompt) {
      result = SitePermissionDecision.Prompt;
    }
  }
  return result;
}

export function applySitePermission(list, origin, kinds, decision) {
  const next = list.map((entry) => ({ ...entry }));
  let stored = next.find((entry) => entry.origin === origin);
  if (stored === undefined) {
    stored = emptySitePermission(origin);
    next.push(stored);
  }
  for (const kind of kinds) {
    stored[kind] = decision;
  }
  return next;
}

export function removeSitePermission(list, origin) {
  return list.filter((entry) => entry.origin !== origin);
}

export function originFromParts(protocol, host, port) {
  if (!protocol || !host) {
    return '';
  }
  const numeric = Number(port);
  const skipPort = !numeric || numeric === 80 || numeric === 443;
  return skipPort ? `${protocol}://${host}` : `${protocol}://${host}:${numeric}`;
}
