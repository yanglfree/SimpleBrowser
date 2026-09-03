// Run with the installed SDK on NODE_PATH; keep plaintext passwords inside this child process.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

try {
  const [configPath, unsignedPath, outputPath, tool, toolsHome] = process.argv.slice(2);
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const material = config.app.signingConfigs[0].material;
  const { DecipherUtil } = require(path.join(toolsHome, 'hvigor/hvigor-ohos-plugin/src/utils/decipher-util.js'));
  const storePassword = DecipherUtil.decryptPwd(path.dirname(material.storeFile), material.storePassword, 'storePassword');
  const keyPassword = DecipherUtil.decryptPwd(path.dirname(material.storeFile), material.keyPassword, 'keyPassword');
  const common = ['-jar', tool];
  const signed = spawnSync('java', [...common, '-operation', 'sign', '-mode', 'localjks', '-privatekey', material.keyAlias,
    '-inputFile', unsignedPath, '-outputFile', outputPath, '-keystore', material.storeFile,
    '-keystorepasswd', storePassword, '-keyaliaspasswd', keyPassword], { encoding: 'utf8' });
  assert.equal(signed.status, 0, 'Manifest signing failed');
  assert.ok(JSON.parse(fs.readFileSync(outputPath, 'utf8')).sign, 'Manifest signature missing');
  const verified = spawnSync('java', [...common, '-operation', 'verify', '-inputFile', outputPath,
    '-keystore', material.storeFile, '-keystorepasswd', storePassword], { encoding: 'utf8' });
  assert.equal(verified.status, 0, 'Manifest signature verification failed');
  assert.ok(/success/i.test(verified.stdout + verified.stderr), 'Manifest verification did not report success');
  console.log('MANIFEST_SIGNATURE_VERIFIED');
} catch (error) {
  console.error(`Manifest operation failed: ${error.code === 'ERR_ASSERTION' ? error.message.split('\n')[0] : error.code ?? error.name}`);
  process.exitCode = 1;
}
