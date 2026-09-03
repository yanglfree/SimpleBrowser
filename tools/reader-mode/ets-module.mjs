import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { repositoryRoot } from './reader-core-source.mjs';

const require = createRequire(import.meta.url);
const compilerPath = process.env.ARTICLE_TEST_TYPESCRIPT ?? path.join(os.homedir(),
  'Library/Huawei/CommandLineTools/current/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const ts = require(compilerPath);

/** Execute non-UI production ArkTS with explicit platform adapters, never source-text assertions. */
export function loadEts(relativePath, adapters = {}) {
  const filename = path.join(repositoryRoot, relativePath);
  const exports = {};
  const source = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const context = {
    exports, console, setTimeout, clearTimeout, Date, URL, ArrayBuffer, Uint8Array,
    require: name => {
      if (name in adapters) return { ...adapters[name], default: adapters[name] };
      if (name.endsWith('/Logger')) return { Logger: { warn() {}, info() {}, error() {} } };
      if (name.startsWith('.')) {
        const resolved = path.relative(repositoryRoot, path.resolve(path.dirname(filename), `${name}.ets`));
        return loadEts(resolved, adapters);
      }
      throw new Error(`Missing explicit adapter: ${name}`);
    }
  };
  vm.runInNewContext(source, context, { filename });
  return exports;
}
