#!/usr/bin/env node
// CI runs on a 30-minute schedule, so a broken main can stay red without anyone
// noticing (2026-11-01 .. 2026-11-26 went unnoticed). This turns a sustained failure
// streak into one tracked issue and closes it once CI is green again.

import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const ALERT_TITLE_PREFIX = '[ci-alert]';
export const DEFAULT_THRESHOLD = 3;
export const HISTORY_WINDOW = 50;
export const FAILED_RUN_LIST_LIMIT = 10;

/**
 * Leading failed runs before the first success. Cancelled and in-progress runs
 * neither extend nor reset the streak: they are transparent, so a cancelled
 * schedule tick cannot mask an outage.
 */
export function failureStreak(conclusions) {
  let streak = 0;
  for (const conclusion of conclusions) {
    if (conclusion === 'success') {
      break;
    }
    if (conclusion === 'failure') {
      streak += 1;
    }
  }
  return streak;
}

export function summarizeRuns(runs) {
  const streak = failureStreak(runs.map((run) => run.conclusion));
  const failedRuns = runs.filter((run) => run.conclusion === 'failure').slice(0, FAILED_RUN_LIST_LIMIT);
  const lastSuccess = runs.find((run) => run.conclusion === 'success') ?? null;
  return { streak, failedRuns, lastSuccess };
}

export function alertTitle(streak) {
  return `${ALERT_TITLE_PREFIX} CI on main has failed ${streak} runs in a row`;
}

/**
 * `create` when the streak crosses the threshold, `edit` to refresh an alert that is
 * already open (editing does not notify, so a long outage produces one issue), and
 * `close` once CI is green again.
 */
export function decide({ streak, threshold, hasOpenAlert }) {
  if (streak >= threshold) {
    return hasOpenAlert ? 'edit' : 'create';
  }
  if (streak === 0 && hasOpenAlert) {
    return 'close';
  }
  return 'none';
}

export function formatLastSuccess(lastSuccess) {
  if (lastSuccess === null) {
    return `no success in the last ${HISTORY_WINDOW} runs`;
  }
  return `\`${lastSuccess.head_sha.slice(0, 7)}\` at ${lastSuccess.created_at} — ${lastSuccess.html_url}`;
}

export function formatBody({ streak, threshold, lastSuccess, failedRuns }) {
  const lines = [
    `CI on \`main\` has failed **${streak}** runs in a row.`,
    '',
    `Last green run: ${formatLastSuccess(lastSuccess)}`,
    `Alert threshold: ${threshold} consecutive failures.`,
    '',
    '### Recent failed runs',
    '',
  ];
  for (const run of failedRuns) {
    lines.push(`- \`${run.head_sha.slice(0, 7)}\` ${run.created_at} (${run.event}) — ${run.html_url}`);
  }
  lines.push(
    '',
    'The iOS job is local-only; the gates above cover the shared contracts, Android and',
    'HarmonyOS (see `docs/mobile-ci-cd.md`).',
    '',
    'This issue is maintained by `.github/workflows/ci-alert.yml` and closes automatically',
    'once CI on `main` is green again.',
  );
  return `${lines.join('\n')}\n`;
}

function gh(args, { allowFailure = false } = {}) {
  try {
    return execFileSync('gh', args, { encoding: 'utf8' });
  } catch (error) {
    if (allowFailure) {
      return '';
    }
    const detail = error.stderr ? error.stderr.toString().trim() : error.message;
    throw new Error(`gh ${args[0]} ${args[1]} failed: ${detail}`);
  }
}

function ghJson(args) {
  return JSON.parse(gh(args));
}

function findOpenAlert(repository) {
  const issues = ghJson([
    'issue', 'list',
    '--repo', repository,
    '--state', 'open',
    '--limit', '100',
    '--json', 'number,title',
  ]);
  const match = issues.find((issue) => issue.title.startsWith(ALERT_TITLE_PREFIX));
  return match === undefined ? null : match;
}

export function parseArgs(argv) {
  const options = { repository: '', threshold: DEFAULT_THRESHOLD, dryRun: false };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--repository') {
      options.repository = argv[index + 1] ?? '';
      index += 1;
    } else if (arg === '--threshold') {
      const raw = argv[index + 1] ?? '';
      if (!/^\d+$/.test(raw) || Number(raw) < 1) {
        throw new Error(`--threshold must be a positive integer, got "${raw}"`);
      }
      options.threshold = Number(raw);
      index += 1;
    } else if (arg === '--dry-run') {
      options.dryRun = true;
    } else {
      throw new Error(`unknown argument "${arg}"`);
    }
  }
  if (options.repository === '') {
    throw new Error('--repository is required');
  }
  return options;
}

export function run({ repository, threshold, dryRun }) {
  const runs = ghJson([
    'api',
    `repos/${repository}/actions/workflows/ci.yml/runs?branch=main&per_page=${HISTORY_WINDOW}`,
  ]);
  const summary = summarizeRuns(runs.workflow_runs ?? []);
  const openAlert = findOpenAlert(repository);
  const action = decide({ streak: summary.streak, threshold, hasOpenAlert: openAlert !== null });

  console.log(
    `streak=${summary.streak} threshold=${threshold} action=${action} ` +
      `open_alert=${openAlert === null ? 'none' : `#${openAlert.number}`} dry_run=${dryRun}`,
  );

  if (action === 'none') {
    return action;
  }

  const body = formatBody({ streak: summary.streak, threshold, ...summary });
  const title = alertTitle(summary.streak);

  if (action === 'create') {
    console.log(`::error::CI has failed ${summary.streak} runs in a row; opening an alert issue`);
    if (!dryRun) {
      gh(['issue', 'create', '--repo', repository, '--title', title, '--body', body]);
    }
  } else if (action === 'edit') {
    console.log(`::warning::CI has failed ${summary.streak} runs in a row; refreshing issue #${openAlert.number}`);
    if (!dryRun) {
      gh(['issue', 'edit', String(openAlert.number), '--repo', repository, '--title', title, '--body', body]);
    }
  } else {
    console.log(`CI recovered; closing issue #${openAlert.number}`);
    if (!dryRun) {
      gh([
        'issue', 'comment', String(openAlert.number), '--repo', repository,
        '--body', `CI on \`main\` is green again (last green run: ${formatLastSuccess(summary.lastSuccess)}). Closing this alert.`,
      ]);
      gh(['issue', 'close', String(openAlert.number), '--repo', repository, '--reason', 'completed']);
    }
  }
  return action;
}

const isDirectRun = process.argv[1] && process.argv[1] === fileURLToPath(import.meta.url);
if (isDirectRun) {
  try {
    run(parseArgs(process.argv.slice(2)));
  } catch (error) {
    console.error(`::error::${error.message}`);
    process.exit(1);
  }
}
