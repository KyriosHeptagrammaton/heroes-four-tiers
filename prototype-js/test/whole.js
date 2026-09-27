const X = require('./load');
// check every stack value stays whole across many AI battles
const rng = X.RNG(9); let bad = 0, n = 0;
for (let i = 0; i < 400; i++) {
  const f = () => X.FACTION_IDS[rng.int(0, 3)];
  const army = fa => [1, 2, 3].map(t => ({ key: rng.pick(X.Units.variants(fa, t)), count: rng.int(2, 25) }));
  const H = fa => { const h = X.Heroes.create(rng.pick(Object.keys(X.CLASSES)), fa, null, rng); h.spellbook = Object.keys(X.SPELLS); h.equipped = ['flame', 'dread', 'ward', 'mend', 'valor']; h.skills.sorcery = 2; h.skills.evocation = 1; h.stats.power = rng.int(0, 5); return h; };
  const f0 = f(), f1 = f();
  const b = new X.Battle({ seed: i + 1, terrain: rng.pick(Object.keys(X.TERRAIN).filter(t => t !== 'chasm')), time: rng.pick(Object.keys(X.TIMES)), sides: [{ stacks: army(f0), hero: H(f0), ai: true }, { stacks: army(f1), hero: H(f1), ai: true }] });
  while (!b.over) {
    X.CombatAI.step(b);
    for (const s of b.stacks) { n++; for (const v of [s.count, s.phys, s.mor, s.moraleVal, b.attack(s), b.defence(s)]) if (!Number.isInteger(v)) { bad++; if (bad < 5) console.log('non-integer', s.name, s.count, s.phys, s.mor, s.moraleVal, b.attack(s), b.defence(s)); break; } }
    for (const sd of b.sides) if (!Number.isInteger(sd.courage)) { bad++; }
  }
}
console.log('checks', n, 'non-integer values', bad);
