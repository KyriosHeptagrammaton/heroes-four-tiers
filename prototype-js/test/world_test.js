const G = require('./load');
// stub UI bits used by controller
G.Game.handoff = () => {}; G.UI = { toast() {}, alert() {}, modal() {}, closeModal() {}, show() {} };
G.WorldUI = { enter() {}, renderSide() {}, redraw() {}, countWord: n => String(n) };
let fails = 0;
for (let seed = 1; seed <= 40; seed++) {
  G.Game.newGame({ names: ['A', 'B'], factions: ['alpha', 'gamma'], cls: ['warlord', 'mage'], seed });
  const S = G.Game.state, W = G.World;
  const [h0, h1] = Object.values(S.heroes);
  // reveal everything for pathing test
  G.World.revealAll(0);
  const t1 = S.towns[S.players[1].capital];
  // clear blocking monsters on the way for connectivity test: path ignoring objects -> temporarily strip objects
  const saved = S.map.cards.map(c => c.objs); S.map.cards.forEach(c => c.objs = c.objs.filter(o => o.type === 'town'));
  const p = W.path(h0, { c: t1.c, x: t1.x, y: t1.y });
  S.map.cards.forEach((c, i) => c.objs = saved[i]);
  if (!p) { console.log('seed', seed, 'NO ROAD PATH between capitals'); fails++; continue; }
  // count objects
  const n = {}; S.map.cards.forEach(c => c.objs.forEach(o => n[o.type] = (n[o.type] || 0) + 1));
  if (seed <= 3) console.log('seed', seed, 'road path len', p.length, 'objects', JSON.stringify(n));
}
// movement + visibility + transcendence on seed 5
G.Game.newGame({ names: ['A', 'B'], factions: ['alpha', 'beta'], cls: ['warlord', 'warlord'], seed: 5 });
const S = G.Game.state, W = G.World, P = S.players[0];
const h = Object.values(S.heroes)[0];
console.log('start seen cards', P.seen.filter(Boolean).length, 'mp', h.mp, 'speed', G.Army.speed(h.army, h));
// step along road a few tiles
let moved = 0;
for (let k = 0; k < 6; k++) {
  const nb = W.neighbors(0, h, h.pos).filter(n => !W.enterable(h, n, P));
  if (!nb.length) break; W.step(h, nb[0]); moved++;
}
console.log('moved', moved, 'mp left', h.mp, 'seen', P.seen.filter(Boolean).length);
// transcendence: teleport hero next to a trans card and walk into it, then cross
h.train.state = 'none';
const T = P.trans.cards[0];
const tx = W.cx(T), ty = W.cy(T);
// place hero on the west neighbour card's east edge if exists
let startC = null, e = 1;
for (const [dx, dy, ee] of [[-1, 0, 1], [1, 0, 3], [0, -1, 2], [0, 1, 0]]) { const x = tx + dx, y = ty + dy; if (x >= 0 && y >= 0 && x < 20 && y < 20 && S.map.cards[y * 20 + x].t !== 'chasm') { startC = y * 20 + x; e = ee; break; } }
const sc = W.card(startC); h.pos = { c: startC, x: e === 1 ? sc.size - 1 : e === 3 ? 0 : 0, y: e === 2 ? sc.size - 1 : 0 };
G.World.revealAll(0); h.mp = 99;
let r = W.cross(0, h, h.pos.c, h.pos.x, h.pos.y, e);
console.log('into trans card?', r.c === T, W.step(h, r));
console.log('active', !!P.trans.active, 'anchor dist', W.cheb(T, P.trans.active.anchor));
// now cross any edge out of T
const tc = W.card(T); h.pos = { c: T, x: tc.size - 1, y: 0 };
r = W.cross(0, h, T, h.pos.x, h.pos.y, 1);
console.log('jump target is anchor?', r.c === P.trans.active.anchor, 'ev', JSON.stringify(W.step(h, r)), 'links', P.trans.links.length);
// walking back across the linked edge returns to T
const back = W.cross(0, h, h.pos.c, h.pos.x, h.pos.y, 3);
console.log('back leads to T?', back && back.c === T);
// walk off region -> status ends
for (let k = 0; k < 40 && P.trans.active; k++) { const nb = W.neighbors(0, h, h.pos).filter(n => !W.enterable(h, n, P) && n.c !== T); if (!nb.length) break; W.step(h, nb[G.Game.rng.int(0, nb.length - 1)]); }
console.log('status ended', !P.trans.active, 'lines', P.trans.lines.length, P.trans.lines[0] && P.trans.lines[0].length);
// days
for (let d = 0; d < 8; d++) G.World.newDay();
console.log('day', S.day, 'gold', P.gold, 'pool', JSON.stringify(S.towns[P.capital].pool));
// battle vs a monster through the controller resolve
const mon = S.map.cards.flatMap((c, i) => c.objs.filter(o => o.type === 'monster').map(o => ({ o, c: i })))[0];
const hero = Object.values(S.heroes)[0]; hero.train.state = 'with';
hero.army = [{ key: 'alpha.1.0.', count: 30, splits: 2, name: '' }, { key: 'alpha.2.0.', count: 10, splits: 1, name: '' }, { key: 'alpha.3.0.', count: 6, splits: 1, name: '' }];
const tgt = { kind: 'monster', obj: mon.o, node: { c: mon.c, x: mon.o.x, y: mon.o.y } };
const info = G.Game.defInfo(tgt);
const b = new G.Battle({ seed: 3, terrain: 'field', time: 'dawn', sides: [{ name: 'A', hero, stacks: G.Game.tag(G.Army.battleStacks(hero.army), 'H'), ai: true }, { name: info.name, stacks: info.stacks, ai: true, neutral: true }] });
while (!b.over) G.CombatAI.step(b);
G.Game.afterReport = (lines) => console.log('REPORT:', lines.join(' | '));
G.Game.resolve(b, hero, tgt, info);
console.log('army after', JSON.stringify(hero.army), 'wounded', JSON.stringify(hero.train.wounded), 'xp', JSON.stringify(hero.xp), 'essence', JSON.stringify(P.essence));
console.log('monster still there?', S.map.cards[mon.c].objs.includes(mon.o));
// save roundtrip
const txt = G.Game.serialize(); const back2 = JSON.parse(txt); console.log('save size KB', (txt.length / 1024) | 0, 'players', back2.players.length);
console.log('fails', fails);
