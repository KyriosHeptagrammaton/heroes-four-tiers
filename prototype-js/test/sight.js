const X = require('./load'); X.Game.handoff = () => {}; X.WorldUI = { enter() {}, renderSide() {}, redraw() {} };
X.Game.newGame({ names: ['A', 'B'], factions: ['alpha', 'beta'], cls: ['warlord', 'mage'], seed: 5 });
const S = X.Game.state, W = S.map.W, P = S.players[0], h = Object.values(S.heroes)[0];
// row 10: plains(hero) | forest 3x3 | swamp 4x4 | plains
const set = (x, t) => { const c = S.map.cards[10 * W + x]; c.t = t; c.size = X.TERRAIN[t].size; c.objs = []; c._rs = null; };
set(0, 'field'); set(1, 'swamp'); set(2, 'plains'); set(3, 'plains');
for (let x = 0; x < 4; x++) for (const y of [9, 11]) { const c = S.map.cards[y * W + x]; c.t = 'field'; c.size = 2; c.objs = []; }
P.tmask.fill(0); P.seen.fill(0);
for (const t of Object.values(S.towns)) t.owner = -1;
h.pos = { c: 10 * W, x: 1, y: 1 };
X.World.computeVisible(0);
const show = x => { const c = 10 * W + x, s = S.map.cards[c].size; const rows = []; for (let y = 0; y < s; y++) { let r = ''; for (let i = 0; i < s; i++) r += X.World.tileSeen(P, c, i, y) ? '#' : '.'; rows.push(r); } return S.map.cards[c].t + ' ' + rows.join('/'); };
console.log('hero on field, looking east:'); for (let x = 1; x < 4; x++) console.log('  ', show(x));
const t0 = Date.now(); for (let i = 0; i < 200; i++) X.World.computeVisible(0); console.log('computeVisible avg ms', (Date.now() - t0) / 200);
