// ============================================================================
// Overworld generation: 20x20 cards, each card an NxN interior of sub-tiles.
// Edges: 0=N 1=E 2=S 3=W
// ============================================================================
G.DX = [0, 1, 0, -1]; G.DY = [-1, 0, 1, 0];
G.OPP = e => (e + 2) % 4;

G.OBJ = {
  town:      { name: 'Town', glyph: '♜', color: '#e8dcc0', desc: 'Recruit, build, upgrade. Capture enemy towns; lose your capital and you lose the game.' },
  mine:      { name: 'Resource site', glyph: '$', color: '#f0d060', desc: 'Pay the survey cost while standing here to claim it for daily gold.' },
  monster:   { name: 'Monsters', glyph: '!', color: '#ff7a6a', desc: 'Neutral creatures. Step on them to fight.' },
  chest:     { name: 'Treasure trove', glyph: '◆', color: '#ffd76a', desc: 'Gold, or experience for the hero.' },
  buried:    { name: 'Buried treasure', glyph: '✕', color: '#ffe9a0', desc: 'A hidden cache.' },
  artifact:  { name: 'Artifact', glyph: '✧', color: '#ffb0f0', desc: 'A magical item for your hero.' },
  shrine:    { name: 'Spell shrine', glyph: '✦', color: '#c7a6ff', desc: 'Learn a spell into your spellbook.' },
  hermit:    { name: 'Wise hermit', glyph: '☥', color: '#b8e0a0', desc: 'Primary skill experience.' },
  academy:   { name: 'Academy', glyph: '⌂', color: '#9ad0ff', desc: 'Secondary skill experience.' },
  tower:     { name: 'Watchtower', glyph: '⟰', color: '#e0e0e0', desc: 'Reveals the land around it.' },
  fairy:     { name: 'Fairy ring', glyph: '❀', color: '#ff9ad8', desc: 'Magi creatures may join you.' },
  mercs:     { name: 'Mercenary camp', glyph: '♞', color: '#e0b080', desc: 'Hire a random mounted unit combination.' },
  knight:    { name: 'Lost knights', glyph: '⚔', color: '#e0e0ff', desc: 'Stranded soldiers who may join you.' },
  post:      { name: 'Recruiting post', glyph: '⚑', color: '#f0c070', desc: 'Buy units from your towns while abroad (+25% price).' },
  font:      { name: 'Arcane font', glyph: '◎', color: '#a0f0ff', desc: 'Upgrade first-upgrade creatures into Magi (essence + gold).' },
  cache:     { name: 'Essence cache', glyph: '⬡', color: '#8af0c8', desc: 'Upgrade essence.' },
  forget:    { name: 'Forest of Forgetting', glyph: '☁', color: '#c0b0e0', desc: 'Dangerous: lose all secondary skill experience, gain +2 knowledge.' },
  grail:     { name: 'The Holy Grail', glyph: '♆', color: '#fff2a0', desc: 'Whoever claims it gains +1 to every primary skill and +1000 gold per week.' },
};
G.flag('sites', 'Overworld', 'Map sites are from the doc\'s discovery list (troves, artifacts, spells, hermits, academies, watchtowers, fairy rings, mercenaries with random mounted combos, lost knights, forest of forgetting, the Grail). Their exact rewards are invented.');
G.flag('mines', 'Economy', 'Resource sites: Timber Stand +60/day (cost 300), Limestone Quarry +90/day (cost 450), Gold Vein +150/day (cost 750). Claiming = paying the survey cost while your army stands there (doc). Enemies take them by stepping on them.');
G.MINES = { timber: { name: 'Timber Stand', income: 60, cost: 300 }, quarry: { name: 'Limestone Quarry', income: 90, cost: 450 }, vein: { name: 'Gold Vein', income: 150, cost: 750 } };

G.WorldGen = {
  generate(seed, opts) {
    const r = G.RNG(seed);
    const W = G.CFG.mapSize, H = G.CFG.mapSize;
    const cards = [];
    // ---- terrain regions (weighted voronoi) ----------------------------------
    const pool = [['field', 12], ['plains', 10], ['forest', 12], ['hill', 8], ['swamp', 5], ['mountain', 6], ['tundra', 4], ['steppe', 4], ['moor', 3], ['ashlands', 3], ['badlands', 3], ['escarpment', 2], ['bluffs', 2], ['dreamwood', 2], ['canyon', 2], ['grove', 2]];
    const tot = G.util.sum(pool.map(p => p[1]));
    const pickT = () => { let x = r() * tot; for (const [t, w] of pool) { if ((x -= w) < 0) return t; } return 'field'; };
    const seeds = [];
    for (let i = 0; i < 46; i++) seeds.push({ x: r() * W, y: r() * H, t: pickT() });
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      let best = null, bd = 1e9;
      for (const s of seeds) { const d = Math.hypot(s.x - x - 0.5, s.y - y - 0.5) + r() * 0.9; if (d < bd) { bd = d; best = s; } }
      cards.push({ t: best.t, road: [false, false, false, false], objs: [] });
    }
    const idx = (x, y) => y * W + x, inb = (x, y) => x >= 0 && y >= 0 && x < W && y < H;
    // ---- towns ------------------------------------------------------------
    const starts = [[2, 2], [W - 3, H - 3]];
    const neutralTowns = [[W - 3, 2], [2, H - 3]];
    const calm = ['field', 'plains'];
    for (const [sx, sy] of starts.concat(neutralTowns)) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) if (inb(sx + dx, sy + dy)) cards[idx(sx + dx, sy + dy)].t = r.pick(calm);
    const townCards = [];
    starts.concat(neutralTowns).forEach(([x, y]) => { cards[idx(x, y)].t = 'town'; townCards.push(idx(x, y)); });
    const center = idx(W >> 1, H >> 1);
    cards[center].t = 'stones';
    // ---- specials ----------------------------------------------------------
    const free = () => { for (let k = 0; k < 500; k++) { const x = r.int(1, W - 2), y = r.int(1, H - 2), i = idx(x, y); if (cards[i].t !== 'town' && i !== center && !cards[i].special) return i; } return -1; };
    for (const [t, n] of [['village', 3], ['watchfort', 2], ['crossroads', 2], ['arena', 1], ['nexus', 2], ['stones', 1]]) for (let k = 0; k < n; k++) { const i = free(); if (i >= 0) { cards[i].t = t; cards[i].special = true; } }
    // ---- chasms (keep connectivity) ------------------------------------------
    for (let c = 0; c < 3; c++) {
      let x = r.int(5, W - 6), y = r.int(5, H - 6); const dir = r.int(0, 3); const len = r.int(3, 5);
      const placed = [];
      for (let k = 0; k < len; k++) {
        const i = idx(x, y);
        if (inb(x, y) && cards[i].t !== 'town' && !cards[i].special && i !== center) { placed.push([i, cards[i].t]); cards[i].t = 'chasm'; }
        x += G.DX[dir] + (r() < 0.3 ? r.int(-1, 1) : 0); y += G.DY[dir]; if (!inb(x, y)) break;
      }
      if (!this.connected(cards, W, H, townCards.concat([center]))) placed.forEach(([i, t]) => cards[i].t = t);
    }
    for (const c of cards) c.size = G.TERRAIN[c.t].size;
    // ---- roads -------------------------------------------------------------
    const T = townCards;
    const links = [[T[0], T[1]], [T[0], T[2]], [T[0], T[3]], [T[1], T[2]], [T[1], T[3]], [T[0], center], [T[1], center], [T[2], center], [T[3], center]];
    for (const [a, b] of links) this.road(cards, W, H, a, b, r);
    // spur roads to random special cards
    for (let i = 0; i < cards.length; i++) if (cards[i].special && !cards[i].road.some(Boolean)) {
      let best = null, bd = 1e9;
      for (let j = 0; j < cards.length; j++) if (cards[j].road.some(Boolean)) { const d = Math.abs(j % W - i % W) + Math.abs(((j / W) | 0) - ((i / W) | 0)); if (d < bd) { bd = d; best = j; } }
      if (best != null && bd < 6) this.road(cards, W, H, i, best, r);
    }
    // extra spurs so resource sites sit on roads
    for (let k = 0; k < 10; k++) {
      const i = free(); if (i < 0 || cards[i].t === 'chasm' || cards[i].t === 'mountain') continue;
      let best = null, bd = 1e9;
      for (let j = 0; j < cards.length; j++) if (cards[j].road.some(Boolean) && j !== i) { const d = Math.abs(j % W - i % W) + Math.abs(((j / W) | 0) - ((i / W) | 0)); if (d < bd) { bd = d; best = j; } }
      if (best != null && bd >= 2 && bd < 5) { this.road(cards, W, H, i, best, r); cards[i].spur = true; }
    }
    const map = { W, H, cards };
    // ---- objects -------------------------------------------------------------
    const factions = opts.factions;
    const towns = [];
    const neutralF = G.FACTION_IDS.filter(f => !factions.includes(f));
    starts.concat(neutralTowns).forEach(([x, y], k) => {
      const c = idx(x, y), s = cards[c].size, m = s >> 1;
      const t = { id: 't' + k, name: G.WorldGen.townName(r), c, x: m, y: m, owner: k < 2 ? k : -1, faction: k < 2 ? factions[k] : r.pick(neutralF.length ? neutralF : G.FACTION_IDS), capital: k < 2 };
      towns.push(t);
      cards[c].objs.push({ id: 'o' + t.id, type: 'town', x: m, y: m, town: t.id });
    });
    const distStart = c => Math.min(...starts.map(([x, y]) => Math.max(Math.abs(c % W - x), Math.abs(((c / W) | 0) - y))));
    const level = c => { const d = distStart(c); return d <= 3 ? 1 : d <= 6 ? 2 : d <= 9 ? 3 : 4; };
    let oid = 1;
    const put = (c, x, y, o) => { o.id = 'o' + (oid++); o.x = x; o.y = y; cards[c].objs.push(o); return o; };
    const roadTiles = c => cards[c].objs.length ? [] : this.roadTiles(cards[c]).filter(([x, y]) => !cards[c].objs.some(o => o.x === x && o.y === y));
    const offTiles = c => { const rt = this.roadTiles(cards[c]).map(p => p.join(',')); const out = []; const s = cards[c].size; for (let y = 0; y < s; y++) for (let x = 0; x < s; x++) if (!rt.includes(x + ',' + y) && !cards[c].objs.some(o => o.x === x && o.y === y)) out.push([x, y]); return out; };
    const roadCards = [];
    for (let i = 0; i < cards.length; i++) if (cards[i].road.some(Boolean) && cards[i].t !== 'town' && i !== center) roadCards.push(i);
    r.shuffle(roadCards);
    // mines: 2 near each start, then more
    const mineKinds = ['timber', 'quarry', 'vein'];
    let placedMines = 0;
    for (const c of roadCards) {
      if (placedMines >= 12) break;
      const d = distStart(c); if (d < 3) continue;
      const t = roadTiles(c); if (!t.length) continue;
      const kind = d <= 4 ? r.pick(['timber', 'quarry']) : r.pick(mineKinds);
      const [x, y] = r.pick(t);
      put(c, x, y, { type: 'mine', kind, owner: -1, guard: this.monsterArmy(r, level(c), d <= 4 ? 0.6 : 1) });
      placedMines++;
    }
    // sites on roads
    const siteList = ['chest', 'chest', 'chest', 'chest', 'shrine', 'shrine', 'shrine', 'hermit', 'hermit', 'academy', 'academy', 'tower', 'tower', 'fairy', 'mercs', 'mercs', 'knight', 'knight', 'post', 'post', 'font', 'cache', 'cache', 'artifact', 'artifact', 'artifact'];
    for (const type of siteList) {
      for (let tries = 0; tries < 40; tries++) {
        const c = r.pick(roadCards); const t = roadTiles(c); if (!t.length || distStart(c) < 2) continue;
        const [x, y] = r.pick(t);
        const o = { type };
        if (distStart(c) >= 3 && (['artifact', 'shrine', 'fairy', 'knight', 'cache'].includes(type) || (type === 'chest' && r() < 0.5))) o.guard = this.monsterArmy(r, level(c), 0.8);
        this.fillSite(o, r);
        put(c, x, y, o); break;
      }
    }
    // wandering monsters blocking roads
    for (let k = 0; k < 26; k++) {
      const c = r.pick(roadCards); if (distStart(c) < 3) continue;
      const t = roadTiles(c); if (!t.length) continue;
      const [x, y] = r.pick(t);
      put(c, x, y, { type: 'monster', army: this.monsterArmy(r, level(c), 1) });
    }
    // hidden things: larger cards hide more
    for (let c = 0; c < cards.length; c++) {
      const cd = cards[c]; if (cd.t === 'town' || cd.t === 'chasm') continue;
      const n = (cd.size >= 2 && r() < 0.06 * cd.size ? 1 : 0) + (cd.size >= 4 && r() < 0.25 ? 1 : 0);
      for (let k = 0; k < n; k++) {
        const t = offTiles(c); if (!t.length) break;
        const [x, y] = r.pick(t);
        const type = r() < 0.5 ? 'buried' : r() < 0.35 ? 'artifact' : r() < 0.5 ? 'cache' : 'chest';
        const o = { type, hidden: true };
        if (type === 'artifact' && r() < 0.5) o.guard = this.monsterArmy(r, level(c), 0.7);
        this.fillSite(o, r);
        put(c, x, y, o);
      }
      if (cd.t === 'dreamwood' && r() < 0.3) { const t = offTiles(c); if (t.length) { const [x, y] = r.pick(t); put(c, x, y, { type: 'forget' }); } }
    }
    // grail in the centre, heavily guarded
    { const cd = cards[center]; const m = cd.size >> 1; put(center, m, m, { type: 'grail', guard: this.monsterArmy(r, 6, 1) }); }
    // ---- transcendent cards per player ---------------------------------------
    const trans = [0, 1].map(p => {
      const out = [];
      const [sx, sy] = starts[p];
      for (let tries = 0; out.length < G.CFG.transcendentPerPlayer && tries < 2000; tries++) {
        const c = r.int(0, cards.length - 1);
        const x = c % W, y = (c / W) | 0;
        if (Math.max(Math.abs(x - sx), Math.abs(y - sy)) < 3) continue;
        if (['town', 'chasm'].includes(cards[c].t) || c === center || out.includes(c)) continue;
        out.push(c);
      }
      return out;
    });
    return { map, towns, starts: starts.map(([x, y]) => idx(x, y)), trans, center };
  },

  townName(r) {
    const a = ['Ash', 'Bright', 'Cold', 'Dun', 'Elder', 'Fair', 'Gold', 'High', 'Iron', 'Kings', 'Long', 'Mar', 'North', 'Oak', 'Raven', 'Stone', 'Thorn', 'West', 'Wolf', 'Yew'];
    const b = ['ford', 'hold', 'haven', 'watch', 'gate', 'moor', 'dale', 'crest', 'field', 'march', 'wick', 'stead'];
    return r.pick(a) + r.pick(b);
  },

  // "Level 1 fight = 3 weeks growth of an un-upgraded tier 1; one week less per tier, and per upgrade"
  monsterArmy(r, level, scale) {
    const f = r.pick(G.FACTION_IDS);
    const stacks = [];
    const n = r.int(1, level >= 3 ? 3 : 2);
    for (let k = 0; k < n; k++) {
      let tier = r.int(1, Math.min(3, 1 + Math.floor(level / 2) + (r() < 0.3 ? 1 : 0)));
      if (level >= 5 && r() < 0.4) tier = 4;
      const up = level >= 3 && r() < 0.4 ? 1 : 0;
      const weeks = Math.max(1, 3 - (tier - 1) - up);
      const growth = tier === 4 ? 1 : G.CFG.growth[tier] * (G.UNIT_BASE[f][tier].sp && G.UNIT_BASE[f][tier].sp.doubleGrowth ? 2 : 1);
      let count = Math.max(1, Math.round(weeks * growth * level * (scale || 1) / n * (0.8 + r() * 0.4)));
      if (tier === 4) count = Math.max(1, Math.round(level / 3));
      const mod = up && tier < 4 && r() < 0.3 ? 'r' : '';
      stacks.push({ key: G.Units.key(f, tier, up, mod), count });
    }
    return { faction: f, level, stacks };
  },

  fillSite(o, r) {
    switch (o.type) {
      case 'chest': o.gold = r.pick([500, 750, 1000, 1500]); o.xp = Math.round(o.gold / 125); break;
      case 'buried': o.gold = r.pick([300, 500, 800, 1200]); break;
      case 'artifact': o.art = r.pick(Object.keys(G.ARTIFACTS).filter(a => a !== 'heart' || r() < 0.2)); break;
      case 'shrine': o.spell = r.pick(Object.keys(G.SPELLS)); break;
      case 'hermit': o.stat = r.pick(G.PRIMARY); o.amount = r.int(3, 6); break;
      case 'academy': o.amount = r.int(3, 6); break;
      case 'fairy': { const f = r.pick(G.FACTION_IDS), t = r.int(1, 2); o.join = { key: G.Units.key(f, t, 1, 'm'), count: t === 1 ? r.int(4, 8) : r.int(2, 4) }; break; }
      case 'mercs': {
        const rk = G.Units.key(r.pick(G.FACTION_IDS), r.int(1, 2), r.int(0, 1), ''), mk = G.Units.key(r.pick(G.FACTION_IDS), r.int(2, 3), 0, '');
        const d = G.Units.resolve(rk + '@' + mk);
        o.join = { key: rk + '@' + mk, count: Math.max(1, Math.round(8 / Math.max(1, d.tier))) }; o.price = Math.round(G.util.sum([1]) * o.join.count * 60 * d.tier); break;
      }
      case 'knight': { const f = r.pick(G.FACTION_IDS), t = r.int(2, 3); o.join = { key: G.Units.key(f, t, 1, ''), count: t === 2 ? r.int(3, 6) : r.int(1, 3) }; break; }
      case 'cache': o.essence = { tier: r.int(1, 3), n: r.int(3, 8) }; break;
      case 'mine': break;
    }
  },

  roadTiles(card) {
    const s = card.size, m = s >> 1, out = new Set();
    if (!card.road.some(Boolean)) return [];
    out.add(m + ',' + m);
    if (card.road[0]) for (let y = 0; y <= m; y++) out.add(m + ',' + y);
    if (card.road[2]) for (let y = m; y < s; y++) out.add(m + ',' + y);
    if (card.road[3]) for (let x = 0; x <= m; x++) out.add(x + ',' + m);
    if (card.road[1]) for (let x = m; x < s; x++) out.add(x + ',' + m);
    return [...out].map(k => k.split(',').map(Number));
  },

  road(cards, W, H, a, b, r) {
    // A* on the card grid
    const cost = i => { const c = cards[i]; if (c.t === 'chasm') return Infinity; let v = c.size + (c.t === 'mountain' ? 4 : 0) + r() * 0.5; if (c.road.some(Boolean)) v *= 0.35; return v; };
    const open = [[0, a]], g = new Map([[a, 0]]), from = new Map();
    const hx = i => Math.abs(i % W - b % W) + Math.abs(((i / W) | 0) - ((b / W) | 0));
    while (open.length) {
      open.sort((p, q) => p[0] - q[0]);
      const [, cur] = open.shift();
      if (cur === b) break;
      const x = cur % W, y = (cur / W) | 0;
      for (let e = 0; e < 4; e++) {
        const nx = x + G.DX[e], ny = y + G.DY[e]; if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
        const n = ny * W + nx, c = cost(n); if (c === Infinity) continue;
        const ng = g.get(cur) + c;
        if (!g.has(n) || ng < g.get(n)) { g.set(n, ng); from.set(n, [cur, e]); open.push([ng + hx(n), n]); }
      }
    }
    let cur = b;
    while (cur !== a && from.has(cur)) { const [p, e] = from.get(cur); cards[p].road[e] = true; cards[cur].road[G.OPP(e)] = true; cur = p; }
  },

  connected(cards, W, H, must) {
    const seen = new Set([must[0]]), q = [must[0]];
    while (q.length) { const c = q.pop(); const x = c % W, y = (c / W) | 0; for (let e = 0; e < 4; e++) { const nx = x + G.DX[e], ny = y + G.DY[e]; if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue; const n = ny * W + nx; if (!seen.has(n) && cards[n].t !== 'chasm') { seen.add(n); q.push(n); } } }
    return must.every(m => seen.has(m));
  },
};
