import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DEFAULT_THRESHOLD,
  alertTitle,
  decide,
  failureStreak,
  formatBody,
  formatLastSuccess,
  parseArgs,
  summarizeRuns,
} from './ci-alert.mjs';

const run = (conclusion, index = 0) => ({
  conclusion,
  head_sha: `${index}`.padStart(7, '0').padEnd(40, '0'),
  created_at: '2026-11-26T03:00:00Z',
  event: 'schedule',
  html_url: `https://github.com/o/r/actions/runs/${index}`,
});

test('failure streak counts leading failures only', () => {
  assert.equal(failureStreak(['failure', 'failure', 'failure', 'success']), 3);
  assert.equal(failureStreak(['success', 'failure']), 0);
  assert.equal(failureStreak(['failure', 'failure']), 2);
  assert.equal(failureStreak([]), 0);
  assert.equal(failureStreak(['failure', 'failure', 'success', 'failure']), 2);
});

test('cancelled and in-progress runs neither extend nor reset the streak', () => {
  assert.equal(failureStreak(['cancelled', 'failure', 'failure', 'success']), 2);
  assert.equal(failureStreak([null, 'failure', 'success']), 1);
  assert.equal(failureStreak(['cancelled', 'success', 'failure']), 0);
});

test('summarizeRuns reports the streak, the last success and the failed runs', () => {
  const runs = [run('failure', 0), run('failure', 1), run('success', 2), run('failure', 3)];
  const summary = summarizeRuns(runs);
  assert.equal(summary.streak, 2);
  assert.equal(summary.lastSuccess.html_url, 'https://github.com/o/r/actions/runs/2');
  assert.deepEqual(summary.failedRuns.map((item) => item.html_url), [
    'https://github.com/o/r/actions/runs/0',
    'https://github.com/o/r/actions/runs/1',
    'https://github.com/o/r/actions/runs/3',
  ]);
});

test('summarizeRuns caps the failed-run list and tolerates an all-red history', () => {
  const runs = Array.from({ length: 15 }, (_unused, index) => run('failure', index));
  const summary = summarizeRuns(runs);
  assert.equal(summary.streak, 15);
  assert.equal(summary.lastSuccess, null);
  assert.equal(summary.failedRuns.length, 10);
});

test('decide opens one alert, refreshes it while red, and closes it when green', () => {
  assert.equal(decide({ streak: 3, threshold: 3, hasOpenAlert: false }), 'create');
  assert.equal(decide({ streak: 9, threshold: 3, hasOpenAlert: false }), 'create');
  assert.equal(decide({ streak: 9, threshold: 3, hasOpenAlert: true }), 'edit');
  assert.equal(decide({ streak: 0, threshold: 3, hasOpenAlert: true }), 'close');
  assert.equal(decide({ streak: 0, threshold: 3, hasOpenAlert: false }), 'none');
  // Below the threshold nothing happens, even when an alert is already open.
  assert.equal(decide({ streak: 2, threshold: 3, hasOpenAlert: true }), 'none');
  assert.equal(decide({ streak: 2, threshold: 3, hasOpenAlert: false }), 'none');
});

test('alert title carries the stable dedupe marker', () => {
  assert.equal(alertTitle(4), '[ci-alert] CI on main has failed 4 runs in a row');
});

test('issue body lists the streak, the last green run and the failed runs', () => {
  const body = formatBody({
    streak: 3,
    threshold: DEFAULT_THRESHOLD,
    lastSuccess: run('success', 7),
    failedRuns: [run('failure', 0), run('failure', 1)],
  });
  assert.match(body, /\*\*3\*\* runs in a row/);
  assert.match(body, /Last green run: `0000007` at 2026-11-26T03:00:00Z/);
  assert.match(body, /Alert threshold: 3 consecutive failures/);
  assert.match(body, /runs\/0/);
  assert.match(body, /closes automatically/);
});

test('last success falls back to a readable message for an all-red window', () => {
  assert.match(formatLastSuccess(null), /no success in the last 50 runs/);
});

test('parseArgs validates the threshold and the repository', () => {
  assert.deepEqual(parseArgs(['--repository', 'o/r']), { repository: 'o/r', threshold: 3, dryRun: false });
  assert.deepEqual(parseArgs(['--repository', 'o/r', '--threshold', '5', '--dry-run']), {
    repository: 'o/r',
    threshold: 5,
    dryRun: true,
  });
  assert.throws(() => parseArgs(['--threshold', '3']), /--repository is required/);
  assert.throws(() => parseArgs(['--repository', 'o/r', '--threshold', '0']), /positive integer/);
  assert.throws(() => parseArgs(['--repository', 'o/r', '--threshold', 'many']), /positive integer/);
  assert.throws(() => parseArgs(['--repository', 'o/r', '--nope']), /unknown argument/);
});
