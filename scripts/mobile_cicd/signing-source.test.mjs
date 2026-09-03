import test from 'node:test';
import assert from 'node:assert/strict';
import { makeConfig } from './signing-source.mjs';

const source = { signingConfigs: ['default', 'dis', 'device'].map(name => ({ name, material: { profile: `${name}.p7b` } })) };
for (const [channel, expected] of [['debug', 'default'], ['app_gallery', 'dis'], ['internaltesting', 'device']]) {
  test(`derives only the canonical ${channel} signing selection`, () => {
    const config = makeConfig(source, channel);
    assert.equal(config.app.products[0].signingConfig, expected);
    assert.deepEqual(config.app.signingConfigs.map(s => s.name), [expected]);
    config.app.signingConfigs[0].material.profile = 'changed';
    assert.equal(source.signingConfigs.find(s => s.name === expected).material.profile, `${expected}.p7b`);
  });
}
test('rejects missing, ambiguous and unsupported channel selections', () => {
  assert.throws(() => makeConfig({ signingConfigs: [] }, 'internaltesting'));
  assert.throws(() => makeConfig({ signingConfigs: [source.signingConfigs[2], source.signingConfigs[2]] }, 'internaltesting'));
  assert.throws(() => makeConfig(source, 'release'));
});
