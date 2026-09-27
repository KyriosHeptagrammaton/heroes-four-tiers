// ============================================================================
// World rules (no DOM): armies, movement, sight, transcendence, sites, days,
// battle setup/aftermath. State lives in G.Game.state (S).
// ============================================================================
G.Army = {
  // A hero/garrison army is a list of groups {key, count, splits, name}. Doc: all stacks of the same
  // type must have the same number of units, so a group of N creatures fights as `splits` equal stacks.
  stacks(groups) { return G.util.sum(groups.map(g => g.splits || 1)); },
  divisors(n) { const out = []; for (let k = 1; k <= Math.min(n, G.CFG.maxStacks); k++) if (n % k === 0) out.push(k); return out; },
  normalize(g) { if (!g.splits || g.count % g.splits !== 0 || g.splits > g.count) { const d = this.divisors(g.count).filter(k => k <= (g.splits || 1)); g.splits = d.length ? d[d.length - 1] : 1; } },
  add(groups, key, count, name) {
    const g = groups.find(x => x.key === key);
    if (g) { g.count += count; this.normalize(g); return true; }
    if (groups.length >= G.CFG.maxStacks || this.stacks(groups) >= G.CFG.maxStacks) return false;
    groups.push({ key, count, splits: 1, name: name || '' });
    return true;
  },
  canAdd(groups, key) { return groups.some(x => x.key === key) || (groups.length < G.CFG.maxStacks && this.stacks(groups) < G.CFG.maxStacks); },
  battleStacks(groups) {
    const out = [];
    groups.forEach((g, gi) => {
      const per = g.count / g.splits;
      const d = G.Units.resolve(g.key);
      for (let k = 0; k < g.splits; k++) out.push({ key: g.key, count: per, name: (g.name || d.name) + (g.splits > 1 ? ' ' + (k + 1) : ''), uid: gi + ':' + k });
    });
    return out;
  },
  value(groups) { return G.util.sum(groups.map(g => g.count * G.Units.value(G.Units.resolve(g.key)))); },
  speed(groups, hero) {
    if (!groups.length) return G.CFG.speed.normal;
    let v = Infinity;
    for (const g of groups) {
      const d = G.Units.resolve(g.key);
      let slow = d.ab.slow || 0;
      if (hero && G.Heroes.has(hero, 'horseshoe')) slow -= 1;
      if (hero && d.mounted && G.Heroes.skill(hero, 'horsemanship') >= 3) slow -= 1;
      const s = slow > 0 ? Math.max(1, G.CFG.speed.slow - (slow - 1)) : (d.ab.cavalry ? G.CFG.speed.cavalry : G.CFG.speed.normal);
      v = Math.min(v, s);
    }
    return v;
  },
  mount(groups, ri, mi, n) {
    const R = groups[ri], M = groups[mi];
    const rd = G.Units.resolve(R.key), md = G.Units.resolve(M.key);
    if (rd.mounted || md.mounted) return 'Mounted units cannot mount again';
    const per = Math.ceil(rd.w / md.s);
    n = Math.min(n, R.count, Math.floor(M.count / per));
    if (n <= 0) return `Need ${per} mount(s) per rider`;
    const key = R.key + '@' + M.key;
    R.count -= n; M.count -= n * per;
    const keep = groups.filter(g => g.count > 0);
    groups.length = 0; keep.forEach(g => { this.normalize(g); groups.push(g); });
    const ex = groups.find(g => g.key === key);
    if (ex) { ex.count += n; this.normalize(ex); } else groups.push({ key, count: n, splits: 1, name: '' });
    return null;
  },
  dismount(groups, gi) {
    const g = groups[gi]; const d = G.Units.resolve(g.key);
    if (!d.mounted) return 'Not mounted';
    const [rk, mk] = g.key.split('@');
    const n = g.count; groups.splice(gi, 1);
    for (const [k, c] of [[rk, n], [mk, n * d.mountsPer]]) {
      const ex = groups.find(x => x.key === k);
      if (ex) { ex.count += c; this.normalize(ex); } else groups.push({ key: k, count: c, splits: 1, name: '' });
    }
    return null;
  },
};

G.BUILDINGS = {
  dwell2: { name: 'Tier 2 dwelling', cost: 1000, req: [], desc: 'Recruit tier 2 creatures.' },
  dwell3: { name: 'Tier 3 dwelling', cost: 2000, req: ['dwell2'], desc: 'Recruit tier 3 creatures.' },
  dwell4: { name: 'Tier 4 lair', cost: 4000, req: ['dwell3'], desc: 'Recruit tier 4 creatures (each costs 1 courage in battle; your hero must fight beside them).' },
  up1_1: { name: 'T1 drill yard', cost: 500, req: [], desc: 'First upgrade (melee or ranged) for tier 1.' },
  up1_2: { name: 'T2 drill yard', cost: 900, req: ['dwell2'], desc: 'First upgrade (melee or ranged) for tier 2.' },
  up1_3: { name: 'T3 drill yard', cost: 1500, req: ['dwell3'], desc: 'First upgrade (melee or ranged) for tier 3.' },
  up1_4: { name: 'T4 drill yard', cost: 3000, req: ['dwell4'], desc: 'Normal upgrade for tier 4 ⚑.' },
  up2_1: { name: 'T1 war college', cost: 800, req: ['up1_1'], desc: 'Second upgrade for tier 1 ⚑.' },
  up2_2: { name: 'T2 war college', cost: 1400, req: ['up1_2'], desc: 'Second upgrade for tier 2 ⚑.' },
  up2_3: { name: 'T3 war college', cost: 2200, req: ['up1_3'], desc: 'Second upgrade for tier 3 ⚑.' },
  sanctum: { name: 'Arcane sanctum', cost: 3500, req: [], desc: 'Turn base creatures (any tier) into Magi.' },
  walls: { name: 'Walls', cost: 1500, req: [], desc: 'Sieges of this town are fought behind walls.' },
};
G.flag('buildings', 'Towns', 'Building list and costs are placeholders. One building per town per day. Magi upgrades need an Arcane Sanctum or an Arcane Font on the map; Magi replaces the first upgrade (base → Magi).');
G.flag('invest', 'Economy', 'Treasury: "3 gold now for 1 gold forever" implemented as: invest 300 gold for +100 gold every week, forever (repeatable).');
G.flag('casualties', 'Overworld', 'After battle (doc): half of deserters (rounded down) rejoin the army, the rest rejoin the nearest own town\'s recruit pool; half of the dead (rounded down) become wounded and ride in the supply train until you visit a town, the rest die. Without a train, the wounded die too.');
G.flag('feint', 'Overworld', 'Attacker may feint (not attack) after the defender picks ground; a defender who picked ground but was not attacked loses its movement next turn. Defender may instead "ignore" the attack: 1-3 random stacks start slow.');
G.flag('herodeath', 'Overworld', 'A defeated hero is removed; the winner takes their spell book (doc) and artifacts (assumed). If a commander dies with its tier-4 stack but its army wins, the survivors walk to the nearest own town garrison.');

G.World = {
  S() { return G.Game.state; },
  W() { return this.S().map.W; },
  card(c) { return this.S().map.cards[c]; },
  cx(c) { return c % this.W(); }, cy(c) { return (c / this.W()) | 0; },
  cheb(a, b) { return Math.max(Math.abs(this.cx(a) - this.cx(b)), Math.abs(this.cy(a) - this.cy(b))); },
  hero(id) { return this.S().heroes[id]; },
  town(id) { return this.S().towns[id]; },
  player(p) { return this.S().players[p]; },
  heroesOf(p) { return Object.values(this.S().heroes).filter(h => h.owner === p && h.alive); },
  townsOf(p) { return Object.values(this.S().towns).filter(t => t.owner === p); },
  log(t) { const S = this.S(); S.log.push({ day: S.day, p: S.cur, t }); if (S.log.length > 300) S.log.shift(); },
  roadSet(c) { const card = this.card(c); if (!card._rs) card._rs = new Set(G.WorldGen.roadTiles(card).map(p => p.join(','))); return card._rs; },
  isRoad(c, x, y) { return this.roadSet(c).has(x + ',' + y); },

  // ---------------------------------------------------------------- hero overworld helpers
  hasTrainWith(h) { return h.train && h.train.state === 'with'; },
  needsRoad(h) { return this.hasTrainWith(h) && G.Heroes.skill(h, 'logistics') < 1; },
  trainless(h) { return !this.hasTrainWith(h) && G.Heroes.skill(h, 'logistics') < 1; },
  mpMax(h) {
    let v = G.Army.speed(h.army, h);
    if (G.Heroes.skill(h, 'logistics') < 1) v -= 1;
    if (G.Heroes.has(h, 'boots')) v += 2;
    if (G.Heroes.skill(h, 'logistics') >= 3) v *= 2;
    return Math.max(2, v);
  },
  objAt(c, x, y) { return this.card(c).objs.find(o => o.x === x && o.y === y); },
  heroAt(c, x, y, except) { return Object.values(this.S().heroes).find(h => h.alive && h !== except && h.pos.c === c && h.pos.x === x && h.pos.y === y); },

  // ---------------------------------------------------------------- movement graph
  // Crossing an edge honours the player's personal transcendent links.
  cross(p, h, c, x, y, e) {
    const card = this.card(c), s = card.size;
    const P = this.player(p);
    let c2 = null, e2 = null;
    const act = h && P.trans.active && P.trans.active.hero === h.id ? P.trans.active : null;
    if (act && !act.jumped && c === act.from) { c2 = act.anchor; e2 = G.OPP(e); }
    else {
      const L = P.trans.links.find(l => l.c === c && l.e === e);
      if (L) { c2 = L.to; e2 = L.te; }
      else {
        const nx = this.cx(c) + G.DX[e], ny = this.cy(c) + G.DY[e];
        if (nx < 0 || ny < 0 || nx >= this.W() || ny >= this.S().map.H) return null;
        c2 = ny * this.W() + nx; e2 = G.OPP(e);
      }
    }
    const card2 = this.card(c2), s2 = card2.size, m = s >> 1, m2 = s2 >> 1;
    const along = (e === 0 || e === 2) ? x : y;
    let mapped;
    if (card.road[e] && along === m && card2.road[e2]) mapped = m2;
    else mapped = Math.min(s2 - 1, Math.floor((along + 0.5) / s * s2));
    const pos = [[mapped, 0], [s2 - 1, mapped], [mapped, s2 - 1], [0, mapped]][e2];
    return { c: c2, x: pos[0], y: pos[1], ex: e, jump: !!act && !act.jumped && c === act.from, linked: !(c2 === (this.cy(c) + G.DY[e]) * this.W() + this.cx(c) + G.DX[e] && e2 === G.OPP(e)) };
  },
  neighbors(p, h, n) {
    const out = [];
    const s = this.card(n.c).size;
    for (let e = 0; e < 4; e++) {
      const nx = n.x + G.DX[e], ny = n.y + G.DY[e];
      if (nx >= 0 && ny >= 0 && nx < s && ny < s) out.push({ c: n.c, x: nx, y: ny });
      else { const r = this.cross(p, h, n.c, n.x, n.y, e); if (r) out.push(r); }
    }
    return out;
  },
  key(n) { return n.c + ':' + n.x + ':' + n.y; },
  // Can hero step onto node n? returns null or reason; 'stop' means only as a final destination
  enterable(h, n, P) {
    const card = this.card(n.c);
    if (!this.tileSeen(P, n.c, n.x, n.y)) return 'Unexplored';
    if (card.t === 'chasm' && G.Heroes.skill(h, 'logistics') < 2) return 'Chasm';
    if (this.needsRoad(h) && !this.isRoad(n.c, n.x, n.y)) return 'Your supply train must stay on roads';
    const o = this.objAt(n.c, n.x, n.y);
    const visibleObj = o && (!o.hidden || this.subSeen(P, n.c, n.x, n.y));
    if (visibleObj && (o.type === 'monster' || o.guard || o.type === 'town' || o.type === 'grail')) return 'stop';
    const oh = this.heroAt(n.c, n.x, n.y, h);
    if (oh) return 'stop';
    if (this.trainAt(n.c, n.x, n.y, h)) return 'stop';
    return null;
  },
  trainAt(c, x, y, except) { return Object.values(this.S().heroes).find(o => o.alive && o !== except && o.train && o.train.state === 'parked' && o.train.at.c === c && o.train.at.x === x && o.train.at.y === y); },
  path(h, goal) {
    const P = this.player(h.owner);
    const start = h.pos, gk = this.key(goal);
    if (gk === this.key(start)) return null;
    const ge = this.enterable(h, goal, P);
    if (ge && ge !== 'stop') return null;
    const hd = n => this.cheb(n.c, goal.c) * 2;
    const open = [[hd(start), 0, start]], g = new Map([[this.key(start), 0]]), from = new Map();
    let found = false, iter = 0;
    while (open.length && iter++ < 30000) {
      let bi = 0; for (let i = 1; i < open.length; i++) if (open[i][0] < open[bi][0]) bi = i;
      const [, cost, cur] = open.splice(bi, 1)[0];
      const ck = this.key(cur);
      if (ck === gk) { found = true; break; }
      if (cost > g.get(ck)) continue;
      for (const n of this.neighbors(h.owner, h, cur)) {
        const nk = this.key(n);
        const why = this.enterable(h, n, P);
        if (why && !(why === 'stop' && nk === gk)) continue;
        const ng = cost + 1;
        if (!g.has(nk) || ng < g.get(nk)) { g.set(nk, ng); from.set(nk, cur); open.push([ng + hd(n), ng, n]); }
      }
    }
    if (!found) return null;
    const out = []; let cur = goal;
    while (this.key(cur) !== this.key(start)) { out.unshift(cur); cur = from.get(this.key(cur)); }
    // re-resolve nodes so jump flags are correct
    return out;
  },

  // ---------------------------------------------------------------- sight
  subSeen(P, c, x, y) { const a = P.seenSub[c]; return !!a && a.includes(x + ',' + y); },
  markSub(P, c, x, y) { const a = P.seenSub[c] || (P.seenSub[c] = []); const k = x + ',' + y; if (!a.includes(k)) { a.push(k); return 1; } return 0; },
  // ---- tile-by-tile sight -----------------------------------------------------------
  // Each card's tiles are revealed individually (bitmask per card, max 4x4 = 16 tiles).
  tileBit(c, x, y) { return 1 << (y * this.card(c).size + x); },
  fullMask(c) { const s = this.card(c).size; return (1 << (s * s)) - 1; },
  tileSeen(P, c, x, y) { return !!P.tmask && !!(P.tmask[c] & this.tileBit(c, x, y)); },
  tileVis(P, c, x, y) { return !!P._vmask && !!((P._vmask.get(c) || 0) & this.tileBit(c, x, y)); },
  cardVis(P, c) { return !!P._vmask && !!P._vmask.get(c); },
  occluded(C, D) {
    // mountains obscure adjacent cards that are further away than the mountain
    const W = this.W(), H = this.S().map.H, x2 = this.cx(D), y2 = this.cy(D), dc = this.cheb(C, D);
    for (let my = -1; my <= 1; my++) for (let mx = -1; mx <= 1; mx++) {
      if (!mx && !my) continue;
      const ax = x2 + mx, ay = y2 + my; if (ax < 0 || ay < 0 || ax >= W || ay >= H) continue;
      const M = ay * W + ax;
      if (M === C || M === D || this.card(M).t !== 'mountain') continue;
      if (this.cheb(C, M) < dc) return true;
    }
    return false;
  },
  // real-geography step across a card edge (sight ignores transcendent links)
  crossReal(c, x, y, e) {
    const nx = this.cx(c) + G.DX[e], ny = this.cy(c) + G.DY[e];
    if (nx < 0 || ny < 0 || nx >= this.W() || ny >= this.S().map.H) return null;
    const c2 = ny * this.W() + nx, s = this.card(c).size, s2 = this.card(c2).size;
    const along = (e === 0 || e === 2) ? x : y, m = Math.min(s2 - 1, Math.floor((along + 0.5) / s * s2));
    const pos = [[m, s2 - 1], [0, m], [m, 0], [s2 - 1, m]][e];
    return { c: c2, x: pos[0], y: pos[1] };
  },
  // Tile distances from the hero: 1 per tile, diagonals allowed inside a card, edges crossed square by square.
  sightBFS(h, max) {
    const dist = new Map(), q = [];
    const k = n => n.c * 16 + n.y * 4 + n.x;
    const start = { c: h.pos.c, x: h.pos.x, y: h.pos.y };
    dist.set(k(start), 0); q.push(start);
    const out = [[start, 0]];
    for (let i = 0; i < q.length; i++) {
      const n = q[i], d = dist.get(k(n));
      if (d >= max) continue;
      const s = this.card(n.c).size, nb = [];
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        if (!dx && !dy) continue;
        const x = n.x + dx, y = n.y + dy;
        if (x >= 0 && y >= 0 && x < s && y < s) nb.push({ c: n.c, x, y });
      }
      for (let e = 0; e < 4; e++) {
        const at = [n.y === 0, n.x === s - 1, n.y === s - 1, n.x === 0][e];
        if (at) { const r = this.crossReal(n.c, n.x, n.y, e); if (r) nb.push(r); }
      }
      for (const m of nb) { const km = k(m); if (!dist.has(km)) { dist.set(km, d + 1); q.push(m); out.push([m, d + 1]); } }
    }
    return out;
  },
  computeVisible(p) {
    const S = this.S(), P = S.players[p], W = this.W(), H = S.map.H;
    if (!P.tmask) P.tmask = P.seen.map((v, c) => (v ? this.fullMask(c) : 0));
    const vm = new Map();
    let newly = 0;
    const seeTile = (c, x, y) => {
      const b = this.tileBit(c, x, y);
      vm.set(c, (vm.get(c) || 0) | b);
      if (!(P.tmask[c] & b)) { P.tmask[c] |= b; newly++; }
      P.seen[c] = 1;
    };
    const seeCard = c => { const s = this.card(c).size; for (let y = 0; y < s; y++) for (let x = 0; x < s; x++) seeTile(c, x, y); };
    for (const h of this.heroesOf(p)) {
      const C = h.pos.c, card = this.card(C), s = card.size;
      const scout = [0, 1, 2, 4][G.Heroes.skill(h, 'scouting')];
      const sb = G.TERRAIN[card.t].sight;
      const max = Math.max(1, this.sightRange('mountain', sb, scout));
      const occ = new Map();
      for (const [n, d] of this.sightBFS(h, max)) {
        if (d > 1) {
          if (d > this.sightRange(this.card(n.c).t, sb, scout)) continue;
          if (!occ.has(n.c)) occ.set(n.c, this.occluded(C, n.c));
          if (occ.get(n.c)) continue;
        }
        seeTile(n.c, n.x, n.y);
      }
      // searching: hidden objects are only found right next to the hero
      const rr = 1 + (G.Heroes.skill(h, 'scouting') ? 1 : 0);
      for (let y = 0; y < s; y++) for (let x = 0; x < s; x++) if (Math.max(Math.abs(x - h.pos.x), Math.abs(y - h.pos.y)) <= rr) this.markSub(P, C, x, y);
    }
    const TR = Math.round(2 * G.CFG.sightScale);
    for (const t of this.townsOf(p)) for (let dy = -TR; dy <= TR; dy++) for (let dx = -TR; dx <= TR; dx++) {
      const x2 = this.cx(t.c) + dx, y2 = this.cy(t.c) + dy; if (x2 >= 0 && y2 >= 0 && x2 < W && y2 < H) seeCard(y2 * W + x2);
    }
    P._vmask = vm;
    P._vis = new Set(vm.keys());
    return newly;
  },
  sightRange(t, standBonus, scout) { return Math.round((G.TERRAIN[t].vis + standBonus + scout) * G.CFG.sightScale); },
  // 1 scouting XP per 10 tiles revealed (remainder carried over)
  scoutXp(h, tiles) {
    h.scoutTiles = (h.scoutTiles || 0) + tiles;
    const xp = Math.floor(h.scoutTiles / G.CFG.scoutTilesPerXP);
    h.scoutTiles -= xp * G.CFG.scoutTilesPerXP;
    if (xp) G.Heroes.addSkillXp(h, 'scouting', xp);
  },
  revealAll(p) { const P = this.player(p); if (!P.tmask) P.tmask = []; this.S().map.cards.forEach((_, c) => { P.tmask[c] = this.fullMask(c); P.seen[c] = 1; }); this.computeVisible(p); },
  revealRadius(p, c, R) {
    const P = this.player(p); const W = this.W(), H = this.S().map.H; let n = 0;
    for (let dy = -R; dy <= R; dy++) for (let dx = -R; dx <= R; dx++) {
      const x = this.cx(c) + dx, y = this.cy(c) + dy; if (x < 0 || y < 0 || x >= W || y >= H) continue;
      const D = y * W + x, full = this.fullMask(D);
      for (let b = full & ~P.tmask[D]; b; b &= b - 1) n++;
      P.tmask[D] = full; P.seen[D] = 1;
    }
    return n;
  },

  // ---------------------------------------------------------------- stepping
  // Move one step. Returns an event or null.
  step(h, n) {
    const S = this.S(), P = this.player(h.owner);
    const prevCard = h.pos.c;
    h.prev = { c: h.pos.c, x: h.pos.x, y: h.pos.y };
    // transcendence bookkeeping
    const act = P.trans.active && P.trans.active.hero === h.id ? P.trans.active : null;
    h.pos = { c: n.c, x: n.x, y: n.y };
    h.mp -= 1;
    let ev = null;
    if (n.c !== prevCard) {
      G.Heroes.addSkillXp(h, 'logistics', 1);
      if (act) {
        if (!act.jumped && prevCard === act.from) {
          act.jumped = true;
          const e = n.ex != null ? n.ex : 1;
          P.trans.links.push({ c: act.from, e: e, to: act.anchor, te: G.OPP(e) }, { c: act.anchor, e: G.OPP(e), to: act.from, te: e });
          act.line.push(n.c);
          ev = { type: 'jump' };
          this.log(`${h.name} steps through the veil and emerges far away.`);
        } else if (act.region.includes(n.c)) { if (act.line[act.line.length - 1] !== n.c) act.line.push(n.c); }
        else {
          P.trans.lines.push(act.line.slice());
          P.trans.active = null;
          this.log(`${h.name} leaves the transcendent zone.`);
          ev = ev || { type: 'transEnd' };
        }
      }
      const ti = P.trans.cards.indexOf(n.c);
      if (ti >= 0 && !P.trans.active) {
        P.trans.cards.splice(ti, 1);
        P.trans.spent.push(n.c);
        const anchor = this.pickAnchor(n.c);
        const region = this.blob(anchor, G.Game.rng.int(4, 12));
        P.trans.active = { hero: h.id, from: n.c, anchor, region, jumped: false, line: [n.c] };
        ev = { type: 'transStart' };
        this.log(`${h.name} feels the land shift: a transcendent zone opens. The next edge you cross leads elsewhere.`);
      }
    }
    // parked train reclaim / destroy enemy train
    const tr = this.trainAt(n.c, n.x, n.y, null);
    if (tr) {
      if (tr === h) { h.train.state = 'with'; h.train.at = null; this.log(`${h.name} rejoins the supply train.`); }
      else if (tr.owner !== h.owner) { this.log(`${h.name} burns ${tr.name}'s supply train!`); tr.train = { state: 'none', at: null, wounded: [] }; }
    }
    const newly = this.computeVisible(h.owner);
    if (newly) this.scoutXp(h, newly);
    return ev;
  },
  pickAnchor(from) {
    const S = this.S();
    for (let k = 0; k < 400; k++) {
      const c = G.Game.rng.int(0, S.map.cards.length - 1);
      if (this.cheb(c, from) >= 6 && !['town', 'chasm'].includes(this.card(c).t)) return c;
    }
    return from;
  },
  blob(a, n) {
    const out = [a], q = [a];
    while (q.length && out.length < n) {
      const c = q.shift();
      const nb = [0, 1, 2, 3].map(e => { const x = this.cx(c) + G.DX[e], y = this.cy(c) + G.DY[e]; return (x >= 0 && y >= 0 && x < this.W() && y < this.S().map.H) ? y * this.W() + x : -1; }).filter(x => x >= 0 && !out.includes(x) && !['town', 'chasm'].includes(this.card(x).t));
      for (const x of nb) { if (out.length >= n) break; if (G.Game.rng() < 0.75) { out.push(x); q.push(x); } }
    }
    return out;
  },

  // ---------------------------------------------------------------- days
  income(p) {
    let g = 0;
    for (const t of this.townsOf(p)) g += t.capital ? G.CFG.townIncome : Math.round(G.CFG.townIncome * 0.6);
    for (const c of this.S().map.cards) for (const o of c.objs) if (o.type === 'mine' && o.owner === p) g += G.MINES[o.kind].income;
    return g;
  },
  newDay() {
    const S = this.S();
    S.day++;
    const week = (S.day - 1) % 7 === 0;
    for (let p = 0; p < S.players.length; p++) {
      const P = S.players[p]; if (!P.alive) continue;
      P.gold += this.income(p);
      if (week) { P.gold += P.invest + (P.grail ? 1000 : 0); }
      for (const h of this.heroesOf(p)) {
        h.mp = this.mpMax(h);
        if (P.skipMove && P.skipMove[h.id]) { h.mp = 0; delete P.skipMove[h.id]; }
        if (this.trainless(h) && h.army.length) {
          const g = h.army.slice().sort((a, b) => b.count - a.count)[0];
          g.count -= 1; if (g.count <= 0) h.army.splice(h.army.indexOf(g), 1); else G.Army.normalize(g);
          this.log(`${h.name}'s army suffers attrition away from its supply train (-1).`);
        }
      }
    }
    for (const t of Object.values(S.towns)) {
      t.builtToday = false;
      if (week) { for (let k = 1; k <= 4; k++) { t.pool[k] = this.growth(t, k); t.extra[k] = 0; } }
    }
    return week;
  },
  growth(t, tier) {
    const f = G.UNIT_BASE[t.faction][tier];
    return G.CFG.growth[tier] * (f.sp && f.sp.doubleGrowth ? 2 : 1);
  },
  // price of buying n more creatures of tier at town t (doc: past the weekly amount the price doubles, then triples...)
  priceFor(t, tier, n, markup) {
    let total = 0, pool = t.pool[tier], extra = t.extra[tier];
    const g = Math.max(1, this.growth(t, tier));
    for (let i = 0; i < n; i++) {
      if (pool > 0) { total += G.CFG.unitPrice[tier]; pool--; }
      else { total += G.CFG.unitPrice[tier] * (2 + Math.floor(extra / g)); extra++; }
    }
    return Math.round(total * (markup || 1));
  },
  buy(t, tier, n) { for (let i = 0; i < n; i++) { if (t.pool[tier] > 0) t.pool[tier]--; else t.extra[tier]++; } },

  // ---------------------------------------------------------------- upgrades
  upgradeOptions(key, ctx) {
    // ctx: {town, font, hero}
    const d = G.Units.resolve(key); if (d.mounted) return [];
    const p = G.Units.parse(key), out = [];
    const t = ctx.town, built = b => t && t.built[b];
    const asc = ctx.hero ? G.Heroes.skill(ctx.hero, 'ascension') : 0;
    const f = p.faction;
    if (p.tier < 4) {
      if (p.up === 0) {
        if (built('up1_' + p.tier)) { out.push(G.Units.key(f, p.tier, 1, '')); out.push(G.Units.key(f, p.tier, 1, 'r')); }
        if (built('sanctum') || ctx.font) out.push(G.Units.key(f, p.tier, 1, 'm'));
      } else if (p.up === 1 && p.mod !== 'm' && built('up2_' + p.tier)) {
        const path = G.SECOND_UPGRADE[t.faction][p.tier];
        if (p.mod === path || asc >= p.tier) out.push(G.Units.key(f, p.tier, 2, p.mod));
      }
    } else if (p.up === 0) {
      if (built('up1_4')) out.push(G.Units.key(f, 4, 1, ''));
      if (built('sanctum') || ctx.font) out.push(G.Units.key(f, 4, 1, 'm'));
    }
    // a town can only train its own faction's upgrades (fonts work for anyone)
    return out.filter(k => ctx.font ? k.endsWith('.m') : (!t || G.Units.parse(k).faction === t.faction || k.endsWith('.m') && built('sanctum')));
  },
  upgradeCost(key, n) { const tier = Math.min(4, G.Units.resolve(key).tier); return { gold: G.CFG.upgradeFee[tier] * n, essence: n, tier }; },

  // ---------------------------------------------------------------- battle aftermath
  applyCasualties(owner, groups, sumSide, hasArmy, trainHero) {
    const S = this.S();
    const toPool = {};
    const wounded = [];
    groups.forEach((g, gi) => {
      const st = sumSide.stacks.filter(s => s.uid && s.uid.split(':')[0] === String(gi));
      if (!st.length) return;
      const surv = G.util.sum(st.map(s => s.survivors)), dead = G.util.sum(st.map(s => s.dead)), des = G.util.sum(st.map(s => s.deserters));
      const d = G.Units.resolve(g.key);
      const rejoinAll = !!d.sp.moraleCasualtiesRejoin;
      let rejoin = hasArmy ? (rejoinAll ? des : Math.floor(des / 2)) : 0;
      const pool = des - rejoin;
      const w = Math.floor(dead / 2);
      g.count = surv + rejoin;
      if (pool > 0) { const tier = Math.min(4, G.Units.resolve(d.baseKey).tier); toPool[tier] = (toPool[tier] || 0) + pool; }
      if (w > 0) wounded.push({ key: g.key, count: w });
    });
    for (let i = groups.length - 1; i >= 0; i--) { if (groups[i].count <= 0) groups.splice(i, 1); else G.Army.normalize(groups[i]); }
    // deserters drift back to the nearest own town
    if (owner >= 0) {
      const towns = this.townsOf(owner);
      if (towns.length) { const t = towns[0]; for (const k in toPool) t.pool[k] = (t.pool[k] || 0) + toPool[k]; }
    }
    if (trainHero && this.hasTrainWith(trainHero)) { for (const w of wounded) trainHero.train.wounded.push(w); return wounded; }
    return [];
  },

  heroXP(h, sd, opp, won, oppHero, rounds) {
    const st = sd.st;
    h.xp.attack += st.killTier;
    h.xp.defence += st.lostTier;
    h.xp.courage += (st.startCourageLE0 ? 1 : 0) + st.desertedByEnemy;
    h.xp.initiative += Math.max(0, st.notFirst - (opp && opp.fled ? 1 : 0));
    h.xp.power += st.spells;
    h.xp.knowledge += st.knowledgeXP;
    if (won && oppHero) for (const k of G.PRIMARY) h.xp[k] += oppHero.stats[k];
    G.Heroes.addSkillXp(h, 'martial', 1 + rounds);
    G.Heroes.addSkillXp(h, 'magic', st.spells);
    if (won) G.Heroes.addSkillXp(h, 'craft', 1);
    const log = [];
    G.Heroes.applyPrimaryLevels(h, G.Game.rng, log);
    return log;
  },

  healInTown(h) {
    if (!h.train || !h.train.wounded.length) return 0;
    let n = 0;
    for (const w of h.train.wounded) { if (G.Army.add(h.army, w.key, w.count)) n += w.count; }
    h.train.wounded = [];
    return n;
  },
};
