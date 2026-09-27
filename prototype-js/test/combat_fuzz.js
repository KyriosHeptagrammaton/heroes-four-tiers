const G = require('./load');
const rng = G.RNG(42);
function randArmy(f) {
  const n = rng.int(1, 6), out = [];
  for (let i = 0; i < n; i++) {
    const t = rng.int(1, 4);
    const vs = G.Units.variants(f, t);
    let key = rng.pick(vs);
    if (rng() < 0.15) { const m = rng.pick(G.Units.variants(rng.pick(G.FACTION_IDS), rng.int(1, 3))); key = key + '@' + m; }
    out.push({ key, count: t === 4 ? rng.int(1, 3) : rng.int(1, [0, 30, 12, 8][t]) });
  }
  return out;
}
let rounds = [], results = {}, errors = 0, maxLog = 0;
const terrains = Object.keys(G.TERRAIN).filter(t => t !== 'chasm');
for (let i = 0; i < 1500; i++) {
  const f0 = rng.pick(G.FACTION_IDS), f1 = rng.pick(G.FACTION_IDS);
  const heroes = [0, 1].map(k => rng() < 0.7 ? G.Heroes.create(rng.pick(Object.keys(G.CLASSES)), k ? f1 : f0, null, rng) : null);
  heroes.forEach(h => { if (h) { if (rng() < 0.5) { h.skills[rng.pick(Object.keys(G.SKILLS))] = rng.int(1, 2); } if (rng() < 0.3) h.artifacts.push(rng.pick(Object.keys(G.ARTIFACTS))); h.spellbook = Object.keys(G.SPELLS); h.equipped = rng.shuffle(Object.keys(G.SPELLS)).slice(0, 4); } });
  try {
    const b = new G.Battle({
      seed: i + 1, terrain: rng.pick(terrains), time: rng.pick(Object.keys(G.TIMES)), weather: rng.pick(['clear', 'rain']),
      sides: [{ stacks: randArmy(f0), hero: heroes[0], ai: true, neutral: rng() < 0.3 }, { stacks: randArmy(f1), hero: heroes[1], ai: true, neutral: rng() < 0.5 }],
    });
    let steps = 0;
    while (!b.over && steps < 20000) { G.CombatAI.step(b); steps++; }
    if (!b.over) { console.log('NO END', i, b.round, b.qi, b.queue.length); errors++; continue; }
    rounds.push(b.round);
    results[b.over.reason] = (results[b.over.reason] || 0) + 1;
    for (const s of b.stacks) if (!isFinite(s.count) || !isFinite(s.phys) || !isFinite(s.mor) || s.count < 0) { console.log('BAD STATE', i, s.name, s.count, s.phys, s.mor); errors++; break; }
    b.summary();
  } catch (e) { errors++; if (errors < 5) console.log('ERR', i, e.stack); }
}
rounds.sort((a, b) => a - b);
console.log('errors', errors, 'results', results, 'rounds median', rounds[rounds.length >> 1], 'p90', rounds[Math.floor(rounds.length * 0.9)], 'max', rounds[rounds.length - 1]);
