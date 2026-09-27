const G = require('./load');
function run(sides, seed, terrain, print) {
  const b = new G.Battle({ seed, terrain: terrain || 'field', sides });
  let steps = 0; while (!b.over && steps < 5000) { G.CombatAI.step(b); steps++; }
  if (print) console.log(b.log.map(l => l.t).join('\n'));
  return b;
}
const H = f => { const h = G.Heroes.create('warlord', f, 'Hero'+f); return h; };
const army = f => [{ key: `${f}.1.0.`, count: 18 }, { key: `${f}.2.0.`, count: 6 }, { key: `${f}.3.0.`, count: 4 }];
G.CFG.beta2PerCreature = process.argv[2] !== "off";
const b = run([{ stacks: army('alpha'), hero: H('alpha'), ai: true }, { stacks: army('beta'), hero: H('beta'), ai: true }], 7, 'field', true);
console.log('\nRESULT', b.over, 'rounds', b.round);
// win matrix mirrored armies
let wins = {};
for (const f0 of G.FACTION_IDS) for (const f1 of G.FACTION_IDS) {
  let w = [0,0,0];
  for (let s = 1; s <= 40; s++) { const r = run([{ stacks: army(f0), hero: H(f0), ai: true }, { stacks: army(f1), hero: H(f1), ai: true }], s*13+1).over; w[r.winner === null ? 2 : r.winner]++; }
  wins[f0+'-'+f1] = w.join('/');
}
console.log(wins);
