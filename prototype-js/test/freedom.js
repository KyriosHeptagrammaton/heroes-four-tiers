const G_ = require('./load'); G_.Game.handoff = () => {}; G_.WorldUI = { enter() {}, renderSide() {}, redraw() {} };
for (let seed = 1; seed <= 10; seed++) {
  G_.Game.newGame({ names: ['A', 'B'], factions: ['alpha', 'beta'], cls: ['warlord', 'mage'], seed });
  const S = G_.Game.state, out = [];
  for (const h of Object.values(S.heroes)) {
    const P = S.players[h.owner]; G_.World.revealAll(h.owner);
    let seen = new Set([G_.World.key(h.pos)]), q = [h.pos], n = 0;
    while (q.length) { const c = q.shift(); for (const nb of G_.World.neighbors(h.owner, h, c)) { const k = G_.World.key(nb); if (seen.has(k)) continue; seen.add(k); if (!G_.World.enterable(h, nb, P)) { q.push(nb); n++; } } }
    out.push(n);
  }
  console.log('seed', seed, 'free road tiles reachable without a fight:', out.join(' / '));
}
