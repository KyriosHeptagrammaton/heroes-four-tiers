// Dump generated maps for a few seeds so the Godot port can be compared.
const X = require('./load');
const fs = require('fs');
const out = {};
for (const seed of [1, 42, 777, 123456, 999999]) {
  const g = X.WorldGen.generate(seed, { factions: ['alpha', 'beta'] });
  out[seed] = g;
}
fs.mkdirSync('/tmp/claude-0/parity', { recursive: true });
fs.writeFileSync('/tmp/claude-0/parity/world_js.json', JSON.stringify(out));
console.log('ok');
