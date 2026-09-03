import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';

// Direct DevEco/Hvigor builds must not bypass the canonical signing source.
execFileSync(process.execPath, [resolve(__dirname, 'scripts/mobile_cicd/signing-source.mjs'), 'assert-selected'], {
  stdio: 'inherit'
});

export default {
  system: appTasks,
  plugins: []
};
