// Generate deterministic battle configs + reference logs from the JS engine.
const X = require('./load');
const fs = require('fs');
const rng = X.RNG(12345);
const terrains = Object.keys(X.TERRAIN).filter(t => t !== 'chasm');
function army(f) {
  const n = rng.int(1, 6), out = [];
  for (let i = 0; i < n; i++) {
    const t = rng.int(1, 4);
    let key = rng.pick(X.Units.variants(f, t));
    if (rng() < 0.15) key = key.split('@')[0] + '@' + rng.pick(X.Units.variants(rng.pick(X.FACTION_IDS), rng.int(1, 3)));
    out.push({ key, count: t === 4 ? rng.int(1, 3) : rng.int(1, [0, 30, 12, 8][t]) });
  }
  return out;
}
function hero(f) {
  if (rng() > 0.7) return null;
  const h = X.Heroes.create(rng.pick(Object.keys(X.CLASSES)), f, null, rng);
  if (rng() < 0.5) h.skills[rng.pick(Object.keys(X.SKILLS))] = rng.int(1, 2);
  if (rng() < 0.3) h.artifacts.push(rng.pick(Object.keys(X.ARTIFACTS)));
  h.spellbook = Object.keys(X.SPELLS);
  h.equipped = rng.shuffle(Object.keys(X.SPELLS)).slice(0, 4);
  h.stats.power = rng.int(0, 4);
  return h;
}
const cfgs = [], logs = [];
for (let i = 0; i < 300; i++) {
  const f0 = rng.pick(X.FACTION_IDS), f1 = rng.pick(X.FACTION_IDS);
  const cfg = {
    seed: i * 7919 + 13, terrain: rng.pick(terrains), time: rng.pick(Object.keys(X.TIMES)), weather: rng.pick(['clear', 'rain']), ignoredAttack: rng() < 0.15,
    sides: [{ name: 'A', stacks: army(f0), hero: hero(f0), ai: true, neutral: rng() < 0.3, trainless: rng() < 0.2 },
            { name: 'B', stacks: army(f1), hero: hero(f1), ai: true, neutral: rng() < 0.5 }],
  };
  cfgs.push(JSON.parse(JSON.stringify(cfg)));
  const b = new X.Battle(JSON.parse(JSON.stringify(cfg)));
  let steps = 0; while (!b.over && steps < 20000) { X.CombatAI.step(b); steps++; }
  logs.push({ log: b.log.map(l => l.t), over: b.over, round: b.round });
}
fs.writeFileSync('/tmp/claude-0/parity/configs.json', JSON.stringify(cfgs));
fs.writeFileSync('/tmp/claude-0/parity/js.json', JSON.stringify(logs));
console.log('generated', cfgs.length);
