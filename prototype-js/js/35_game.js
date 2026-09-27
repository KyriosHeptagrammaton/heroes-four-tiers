// ============================================================================
// Game controller: new game, hotseat turns, walking, sites, battles, saves.
// ============================================================================
G.Game = {
  state: null, rng: G.RNG(1),
  PCOLORS: ['#e8b33c', '#43b5e8'],

  // ---------------------------------------------------------------- new game
  newGameDialog() {
    const h = G.UI.h;
    const cfg = { names: ['Player 1', 'Player 2'], factions: ['alpha', 'beta'], cls: ['warlord', 'mage'], seed: (Math.random() * 1e6) | 0 };
    const draw = () => {
      const box = h('div', { class: 'col', style: { minWidth: '520px' } }, h('h2', null, 'New hotseat game'),
        h('div', { class: 'muted' }, 'Two players share this computer and take turns. The map is hidden between turns.'));
      for (let p = 0; p < 2; p++) {
        box.append(h('div', { class: 'panel row wrap' },
          h('b', { style: { color: this.PCOLORS[p], width: '20px' } }, '●'),
          h('input', { value: cfg.names[p], style: { width: '140px' }, onchange: e => cfg.names[p] = e.target.value }),
          h('span', { class: 'muted' }, 'Faction'),
          (() => { const s = h('select', null, G.FACTION_IDS.map(f => h('option', { value: f, selected: cfg.factions[p] === f }, G.FACTIONS[f].name))); s.onchange = () => { cfg.factions[p] = s.value; }; return s; })(),
          h('span', { class: 'muted' }, 'Hero'),
          (() => { const s = h('select', null, Object.keys(G.CLASSES).map(c => h('option', { value: c, selected: cfg.cls[p] === c }, G.CLASSES[c].name))); s.onchange = () => { cfg.cls[p] = s.value; }; return s; })()));
      }
      box.append(h('div', { class: 'row' }, h('span', { class: 'muted' }, 'Map seed'), h('input', { type: 'number', value: cfg.seed, style: { width: '110px' }, onchange: e => cfg.seed = +e.target.value || 1 })));
      box.append(h('div', { class: 'row', style: { justifyContent: 'flex-end' } }, h('button', { onclick: () => G.UI.closeModal() }, 'Cancel'),
        h('button', { class: 'primary', onclick: () => { if (cfg.factions[0] === cfg.factions[1]) { G.UI.toast('Pick two different factions'); return; } G.UI.closeModal(); this.newGame(cfg); } }, 'Start')));
      G.UI.modal(box);
    };
    draw();
  },

  newGame(cfg) {
    const gen = G.WorldGen.generate(cfg.seed, { factions: cfg.factions });
    this.rng = G.RNG(cfg.seed * 7 + 13);
    const N = gen.map.cards.length;
    const S = {
      v: 1, seed: cfg.seed, day: 1, cur: 0, map: gen.map, center: gen.center, winner: null, log: [], towns: {}, heroes: {},
      players: [0, 1].map(p => ({ name: cfg.names[p], faction: cfg.factions[p], color: this.PCOLORS[p], gold: G.CFG.startGold, essence: { 1: 0, 2: 0, 3: 0, 4: 0 }, alive: true,
        seen: new Array(N).fill(0), tmask: new Array(N).fill(0), seenSub: {}, trans: { cards: gen.trans[p], spent: [], links: [], lines: [], active: null }, invest: 0, grail: false, skipMove: {}, capital: null })),
    };
    this.state = S;
    for (const t of gen.towns) {
      t.built = { dwell1: true, walls: !!t.capital };
      t.pool = { 1: 0, 2: 0, 3: 0, 4: 0 }; t.extra = { 1: 0, 2: 0, 3: 0, 4: 0 };
      t.garrison = []; t.builtToday = false;
      for (let k = 1; k <= 4; k++) t.pool[k] = G.World.growth(t, k);
      if (t.owner < 0) {
        const a = G.WorldGen.monsterArmy(this.rng, 2, 1);
        t.garrison = a.stacks.map(s => ({ key: s.key, count: s.count, splits: 1, name: '' }));
        t.built.dwell2 = true; t.built.up1_1 = true;
      } else S.players[t.owner].capital = t.id;
      S.towns[t.id] = t;
    }
    for (let p = 0; p < 2; p++) {
      const t = S.towns[S.players[p].capital];
      this.spawnHero(p, cfg.cls[p], t, true);
    }
    for (let p = 0; p < 2; p++) G.World.computeVisible(p);
    G.World.log('A new world takes shape.');
    this.handoff(0);
  },

  spawnHero(p, cls, town, starter) {
    const S = this.state, f = S.players[p].faction;
    const h = G.Heroes.create(cls, f, null, this.rng);
    Object.assign(h, { owner: p, pos: { c: town.c, x: town.x, y: town.y }, alive: true, visited: {}, train: { state: 'with', at: null, wounded: [] }, mp: 0 });
    h.army = starter
      ? [{ key: G.Units.key(f, 1, 0, ''), count: 12, splits: 2, name: '' }, { key: G.Units.key(f, 2, 0, ''), count: 3, splits: 1, name: '' }]
      : [{ key: G.Units.key(f, 1, 0, ''), count: 6, splits: 1, name: '' }];
    h.mp = G.World.mpMax(h);
    S.heroes[h.id] = h;
    return h;
  },
  rngInt(a, b) { return this.rng.int(a, b); },

  // ---------------------------------------------------------------- turns
  handoff(p, text, cb) {
    const h = G.UI.h, S = this.state, P = S.players[p], el = G.UI.clear(document.getElementById('handoff'));
    const week = Math.floor((S.day - 1) / 7) + 1, dow = (S.day - 1) % 7 + 1;
    el.append(h('div', { class: 'sigil', style: { color: P.color } }, '♛'),
      h('h1', { style: { color: P.color } }, P.name),
      h('div', { class: 'muted', style: { margin: '6px 0 18px' } }, text || `Day ${dow}, week ${week}. Pass the computer to ${P.name}.`),
      h('button', { class: 'primary', style: { padding: '12px 30px', fontSize: '16px' }, onclick: () => (cb ? cb() : this.beginTurn()) }, cb ? 'Continue' : `I am ${P.name} — show my lands`));
    G.UI.closeModal();
    G.UI.show('handoff');
  },
  beginTurn() {
    const S = this.state;
    G.World.computeVisible(S.cur);
    G.WorldUI.enter();
    this.checkSkillChoices();
  },
  resume() { if (!this.state) return; if (this.state.winner != null) return this.victory(this.state.winner); this.handoff(this.state.cur); },
  checkSkillChoices() {
    const S = this.state;
    for (const hr of G.World.heroesOf(S.cur)) { if (G.Heroes.maybeOfferSkill(hr, this.rng)) { G.ArmyUI.skillChoice(hr.id, () => this.checkSkillChoices()); return; } }
  },
  endTurnConfirm() {
    const left = G.World.heroesOf(this.state.cur).filter(h => h.mp > 0);
    if (left.length) G.UI.confirm(`${left.map(h => h.name).join(', ')} still ${left.length > 1 ? 'have' : 'has'} movement. End turn?`, () => this.endTurn());
    else this.endTurn();
  },
  endTurn() {
    const S = this.state;
    let next = S.cur, wrapped = false;
    do { next = (next + 1) % S.players.length; if (next === 0) wrapped = true; } while (!S.players[next].alive && next !== S.cur);
    if (wrapped) { const week = G.World.newDay(); if (week) G.World.log('A new week begins: creatures muster in every town.'); }
    S.cur = next;
    this.autosave();
    this.handoff(S.cur);
  },

  // ---------------------------------------------------------------- walking
  walk(hero, path) {
    const UI = G.WorldUI, W = G.World;
    if (hero.mp <= 0) { G.UI.toast('No movement left today'); return; }
    UI.anim = true;
    const done = msg => { UI.anim = false; UI.path = path.length ? path : null; UI.renderSide(); UI.redraw(); if (msg) G.UI.toast(msg); };
    const tick = () => {
      if (!path.length) return done();
      if (hero.mp <= 0) return done('Out of movement for today');
      const n = path[0];
      const P = this.state.players[hero.owner];
      const why = W.enterable(hero, n, P);
      if (why === 'stop') { path.length = 0; done(); this.interact(hero, n); return; }
      if (why) { path.length = 0; return done(why); }
      path.shift();
      const ev = W.step(hero, n);
      UI.redraw();
      const o = W.objAt(n.c, n.x, n.y);
      if (o && !o.guard && G.OBJ[o.type] && !['monster', 'town'].includes(o.type) && (!o.hidden || W.subSeen(P, n.c, n.x, n.y))) { path.length = 0; done(); this.site(hero, o); return; }
      if (ev && (ev.type === 'transStart' || ev.type === 'jump' || ev.type === 'transEnd')) {
        path.length = 0; done();
        if (ev.type === 'transStart') G.UI.alert('✧ Transcendent zone', 'The land shimmers. A distant part of the world has been lifted and laid beside you: <b>the next edge you cross from this card leads there</b>. A glowing line will record your path; you can always walk it back.');
        if (ev.type === 'jump') { UI.centerOnSel(); G.UI.toast('You emerge in a far corner of the world…', 3000); }
        return;
      }
      // stop if something now blocks the path
      if (path.length) { const w2 = W.enterable(hero, path[0], P); if (w2 && w2 !== 'stop') { path.length = 0; return done(w2); } }
      setTimeout(tick, 70);
    };
    tick();
  },

  interact(hero, n) {
    const W = G.World, S = this.state;
    if (hero.mp < 1) { G.UI.toast('Not enough movement'); return; }
    const o = W.objAt(n.c, n.x, n.y);
    const oh = W.heroAt(n.c, n.x, n.y, hero);
    if (oh) {
      if (oh.owner === hero.owner) { G.ArmyUI.exchange(hero.id, oh.id); return; }
      return this.battle(hero, { kind: oh && o && o.type === 'town' ? 'town' : 'hero', hero: oh, town: o && o.type === 'town' ? S.towns[o.town] : null, node: n });
    }
    if (o && o.type === 'town') {
      const t = S.towns[o.town];
      if (t.owner === hero.owner) { W.step(hero, n); this.enterTown(hero, t); return; }
      if (t.garrison.length) return this.battle(hero, { kind: 'town', town: t, node: n });
      W.step(hero, n); this.capture(hero, t); return;
    }
    if (o && o.type === 'monster') return this.battle(hero, { kind: 'monster', obj: o, node: n });
    if (o && o.guard) return this.battle(hero, { kind: 'guard', obj: o, node: n });
    W.step(hero, n);
    if (o) this.site(hero, o);
    G.WorldUI.renderSide(); G.WorldUI.redraw();
  },

  enterTown(hero, t) {
    const n = G.World.healInTown(hero);
    if (n) G.UI.toast(`${n} wounded creatures rejoin ${hero.name}`);
    G.WorldUI.renderSide(); G.WorldUI.redraw();
    G.TownUI.open(t.id, hero.id);
  },
  capture(hero, t, lines) {
    const S = this.state, old = t.owner;
    t.owner = hero.owner; t.garrison = [];
    G.World.log(`${hero.name} captures ${t.name}!`);
    if (old >= 0 && S.players[old].capital === t.id) { this.state.winner = hero.owner; this.autosave(); return this.victory(hero.owner); }
    G.WorldUI.renderSide(); G.WorldUI.redraw();
    if (lines) lines.push(`${t.name} now flies your banner.`); else G.UI.alert('Town captured', `${t.name} now flies your banner.`);
  },

  parkTrain(hero) {
    hero.train.state = 'parked'; hero.train.at = { c: hero.pos.c, x: hero.pos.x, y: hero.pos.y };
    G.UI.toast('Train parked. You may leave the road; your troops fight at -1 morale and suffer attrition until you return.', 4200);
    G.WorldUI.renderSide(); G.WorldUI.redraw();
  },

  // ---------------------------------------------------------------- sites
  site(hero, o) {
    const S = this.state, P = S.players[hero.owner], h = G.UI.h, W = G.World;
    const remove = () => { const card = W.card(hero.pos.c); card.objs = card.objs.filter(x => x !== o); };
    const done = () => { G.WorldUI.renderSide(); G.WorldUI.redraw(); };
    const once = k => { hero.visited[o.id] = true; };
    switch (o.type) {
      case 'chest':
        G.UI.modal(h('div', { class: 'col' }, h('h2', null, '◆ Treasure trove'), h('div', null, 'Take the gold, or study the maps and journals inside?'),
          h('div', { class: 'pop-choice' },
            h('div', { onclick: () => { P.gold += o.gold; remove(); G.UI.closeModal(); done(); } }, h('b', null, `${o.gold} gold`)),
            h('div', { onclick: () => { G.UI.closeModal(); this.pickPrimary(hero, o.xp, () => { remove(); done(); }); } }, h('b', null, `${o.xp} experience`), h('div', { class: 'muted' }, 'in a primary skill of your choice'))))
          , { locked: true });
        return;
      case 'buried': P.gold += o.gold; remove(); G.UI.alert('✕ Buried treasure', `You dig up ${o.gold} gold.`); return done();
      case 'artifact': hero.artifacts.push(o.art); remove(); G.UI.alert('✧ ' + G.ARTIFACTS[o.art].name, G.ARTIFACTS[o.art].desc); return done();
      case 'shrine':
        if (hero.spellbook.includes(o.spell)) { G.UI.toast(`${hero.name} already knows ${G.SPELLS[o.spell].name}`); return done(); }
        hero.spellbook.push(o.spell); G.UI.alert('✦ Spell shrine', `${hero.name} learns <b>${G.SPELLS[o.spell].name}</b>: ${G.SPELLS[o.spell].desc}<br><span class="muted">Equip it from the Hero screen.</span>`); return done();
      case 'hermit':
        if (hero.visited[o.id]) { G.UI.toast('The hermit has nothing more to teach you'); return; }
        once(); hero.xp[o.stat] += o.amount; { const log = []; G.Heroes.applyPrimaryLevels(hero, this.rng, log); G.UI.alert('☥ Wise hermit', `+${o.amount} ${o.stat} experience.${log.length ? '<br>' + log.join('<br>') : ''}`); } return done();
      case 'academy':
        if (hero.visited[o.id]) { G.UI.toast('You have studied here already'); return; }
        G.UI.modal(h('div', { class: 'col' }, h('h2', null, '⌂ Academy'), h('div', null, `Study one secondary skill (+${o.amount * 2} experience):`),
          h('div', { class: 'row wrap' }, Object.keys(G.SKILLS).map(k => h('button', { class: 'small', tip: G.SKILLS[k].tiers.join('<br>'), onclick: () => { once(); hero.skillXp[k] += o.amount * 2; G.UI.closeModal(); this.checkSkillChoices(); done(); } }, G.SKILLS[k].name)))), { locked: true });
        return;
      case 'tower': { const n = W.revealRadius(hero.owner, hero.pos.c, Math.round(5 * G.CFG.sightScale)); W.scoutXp(hero, n); G.UI.toast('From the tower you survey the land.'); return done(); }
      case 'fairy': case 'knight': {
        const d = G.Units.resolve(o.join.key);
        if (!G.Army.canAdd(hero.army, o.join.key)) { G.UI.alert(G.OBJ[o.type].name, `${o.join.count} ${d.name} would join, but your army has no room.`); return; }
        G.Army.add(hero.army, o.join.key, o.join.count); remove();
        G.UI.alert(G.OBJ[o.type].name, `${o.join.count} ${d.name} join your army.`); return done();
      }
      case 'mercs': return this.useSite(hero, o);
      case 'post': return this.useSite(hero, o);
      case 'font': return this.useSite(hero, o);
      case 'mine': return this.useSite(hero, o);
      case 'cache': P.essence[o.essence.tier] += o.essence.n; remove(); G.UI.alert('⬡ Essence cache', `+${o.essence.n} tier-${o.essence.tier} upgrade essence.`); return done();
      case 'forget':
        if (hero.visited[o.id]) return;
        once(); for (const k in hero.skillXp) hero.skillXp[k] = 0; hero.stats.knowledge += 2;
        G.UI.alert('☁ Forest of Forgetting', 'Your secondary skill experience fades away… but something else takes root: +2 knowledge.'); return done();
      case 'grail':
        remove(); P.grail = true; for (const k of G.PRIMARY) hero.stats[k] += 1;
        G.UI.alert('♆ The Holy Grail', `${hero.name} claims the Grail: +1 to every primary skill, and ${P.name} gains 1000 gold every week.`); return done();
    }
    done();
  },
  useSite(hero, o) {
    const S = this.state, P = S.players[hero.owner], h = G.UI.h, W = G.World;
    const done = () => { G.WorldUI.renderSide(); G.WorldUI.redraw(); };
    if (o.type === 'mine') {
      const M = G.MINES[o.kind];
      if (o.owner === hero.owner) { G.UI.toast(`${M.name}: yours (+${M.income}/day)`); return; }
      if (o.owner >= 0) { G.World.log(`${hero.name} raids ${S.players[o.owner].name}'s ${M.name}.`); o.owner = -1; }
      G.UI.confirm(`${M.name}: pay ${M.cost} gold to survey and claim it (+${M.income} gold per day)?`, () => {
        if (P.gold < M.cost) { G.UI.toast('Not enough gold'); return; }
        P.gold -= M.cost; o.owner = hero.owner; G.World.log(`${hero.name} claims a ${M.name}.`); done();
      });
      return done();
    }
    if (o.type === 'mercs') {
      if (o.hired) { G.UI.toast('The camp is empty'); return; }
      const d = G.Units.resolve(o.join.key);
      G.UI.modal(h('div', { class: 'col' }, h('h2', null, '♞ Mercenary camp'), h('div', { class: 'row' }, G.UI.sym(d, 36), h('div', { html: `${o.join.count} × <b>${d.name}</b><br>for ${o.price} gold` })), h('div', { html: G.UI.unitTip(d), class: 'panel' }),
        h('div', { class: 'row', style: { justifyContent: 'flex-end' } }, h('button', { onclick: () => G.UI.closeModal() }, 'Leave'),
          h('button', { class: 'primary', onclick: () => { if (P.gold < o.price) return G.UI.toast('Not enough gold'); if (!G.Army.canAdd(hero.army, o.join.key)) return G.UI.toast('No room in your army'); P.gold -= o.price; G.Army.add(hero.army, o.join.key, o.join.count); o.hired = true; G.UI.closeModal(); done(); } }, 'Hire'))));
      return;
    }
    if (o.type === 'post') return G.TownUI.remoteRecruit(hero.id);
    if (o.type === 'font') return G.TownUI.upgradeModal(hero.id, null, true);
  },
  pickPrimary(hero, xp, then) {
    const h = G.UI.h;
    G.UI.modal(h('div', { class: 'col' }, h('h2', null, `+${xp} experience`), h('div', { class: 'row wrap' }, G.PRIMARY.map(k => h('button', { onclick: () => { hero.xp[k] += xp; const log = []; G.Heroes.applyPrimaryLevels(hero, this.rng, log); G.UI.closeModal(); if (log.length) G.UI.alert('Level up', log.join('<br>')); then && then(); } }, k)))), { locked: true });
  },

  // ---------------------------------------------------------------- battles
  defInfo(tgt) {
    const S = this.state;
    if (tgt.kind === 'monster') return { owner: -1, name: 'Neutral creatures', groups: null, stacks: tgt.obj.army.stacks.map((s, i) => ({ key: s.key, count: s.count, uid: 'M' + i })), neutral: true, faction: tgt.obj.army.faction };
    if (tgt.kind === 'guard') return { owner: -1, name: 'Guardians', stacks: tgt.obj.guard.stacks.map((s, i) => ({ key: s.key, count: s.count, uid: 'M' + i })), neutral: true, faction: tgt.obj.guard.faction };
    if (tgt.kind === 'hero') return { owner: tgt.hero.owner, name: S.players[tgt.hero.owner].name + ' – ' + tgt.hero.name, hero: tgt.hero, stacks: this.tag(G.Army.battleStacks(tgt.hero.army), 'H'), faction: tgt.hero.faction };
    // town
    const t = tgt.town, oh = tgt.hero || G.World.heroAt(t.c, t.x, t.y);
    let stacks = this.tag(G.Army.battleStacks(t.garrison), 'T');
    if (oh) stacks = this.tag(G.Army.battleStacks(oh.army), 'H').concat(stacks);
    stacks = stacks.slice(0, G.CFG.maxStacks);
    return { owner: t.owner, name: t.owner >= 0 ? S.players[t.owner].name + ' – ' + t.name : t.name + ' garrison', hero: oh || null, stacks, neutral: t.owner < 0, faction: t.faction, town: t };
  },
  tag(stacks, p) { return stacks.map(s => Object.assign(s, { uid: p + s.uid })); },

  groundChoices(tgt) {
    const W = G.World, c = tgt.node.c, out = [];
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const x = W.cx(c) + dx, y = W.cy(c) + dy; if (x < 0 || y < 0 || x >= W.W() || y >= this.state.map.H) continue;
      const t = W.card(y * W.W() + x).t; if (t === 'chasm' || t === 'town') continue;
      if (!out.includes(t)) out.push(t);
    }
    if (!out.length) out.push('field');
    return out;
  },
  aiGround(choices) {
    const score = { canyon: 5, hill: 4, escarpment: 4, mountain: 4, bluffs: 3, watchfort: 3, village: 3, forest: 2, swamp: 2, moor: 1 };
    return choices.slice().sort((a, b) => (score[b] || 0) - (score[a] || 0))[0];
  },

  battle(hero, tgt) {
    const S = this.state, info = this.defInfo(tgt);
    const me = S.players[hero.owner];
    const afterGround = (ground, ignored) => this.chooseTime(hero, info, ground, ignored, (time) => {
      if (time === 'feint') {
        hero.mp = Math.max(0, hero.mp - 1);
        if (!ignored && info.owner >= 0 && info.hero) { S.players[info.owner].skipMove[info.hero.id] = true; G.World.log(`${hero.name} feints; ${info.hero.name} wasted their preparations.`); }
        G.WorldUI.enter(); return;
      }
      this.launch(hero, tgt, info, ground, time, ignored);
    });
    if (tgt.kind === 'town') { const t = info.town; return afterGround(t.built.walls ? 'town' : this.aiGround(this.groundChoices(tgt)), false); }
    const choices = this.groundChoices(tgt);
    if (info.owner < 0) return afterGround(this.aiGround(choices), false);
    // human defender picks ground (hotseat: pass the computer)
    const def = S.players[info.owner];
    this.handoff(info.owner, `${me.name}'s ${hero.name} is attacking your ${info.hero ? info.hero.name : 'army'}! Choose your ground.`, () => {
      const h = G.UI.h;
      G.UI.modal(h('div', { class: 'col', style: { minWidth: '480px' } }, h('h2', null, `${def.name}: choose your ground`),
        h('div', { class: 'muted' }, 'Pick the battlefield from the card you stand on or any card around it — or ignore the attack (1-3 of your stacks start slow).'),
        ...choices.map(t => h('button', { style: { textAlign: 'left' }, onclick: () => { G.UI.closeModal(); this.handoff(hero.owner, `${def.name} chose to fight on ${G.TERRAIN[t].name}.`, () => afterGround(t, false)); } }, h('b', null, G.TERRAIN[t].name), ' — ', h('span', { class: 'muted' }, G.TERRAIN[t].desc))),
        h('button', { class: 'danger', onclick: () => { G.UI.closeModal(); this.handoff(hero.owner, `${def.name} ignores the attack.`, () => afterGround(tgt.node ? G.World.card(tgt.node.c).t : 'field', true)); } }, 'Ignore the attack')), { locked: true });
    });
  },
  chooseTime(hero, info, ground, ignored, cb) {
    const h = G.UI.h;
    G.UI.show('world');
    G.UI.modal(h('div', { class: 'col', style: { minWidth: '480px' } }, h('h2', null, `Attack ${info.name}`),
      h('div', null, `Ground: `, h('b', null, G.TERRAIN[ground].name), ' — ', h('span', { class: 'muted' }, G.TERRAIN[ground].desc), ignored ? h('div', { class: 'good' }, 'The defender ignored your attack: 1-3 of their stacks start slow.') : null),
      h('div', { class: 'panel', html: 'Defenders: ' + info.stacks.map(s => `${G.WorldUI.countWord(s.count)} ${G.Units.resolve(s.key).name}`).join(', ') }),
      h('div', { class: 'muted' }, 'Choose the time of your attack:'),
      ...Object.keys(G.TIMES).map(t => h('button', { style: { textAlign: 'left' }, onclick: () => { G.UI.closeModal(); cb(t); } }, h('b', null, G.TIMES[t].name), ' — ', h('span', { class: 'muted' }, G.TIMES[t].desc))),
      h('button', { class: 'danger', onclick: () => { G.UI.closeModal(); cb('feint'); } }, 'Feint (do not attack)')), { locked: true });
  },
  launch(hero, tgt, info, ground, time, ignored) {
    const S = this.state;
    const weather = this.rng() < G.CFG.rainChance ? 'rain' : 'clear';
    this.fieldUpgrade(hero); if (info.hero) this.fieldUpgrade(info.hero);
    const b = new G.Battle({
      seed: this.rng.int(1, 1e9), terrain: ground, time, weather, ignoredAttack: ignored,
      sides: [
        { name: S.players[hero.owner].name + ' – ' + hero.name, hero, stacks: this.tag(G.Army.battleStacks(hero.army), 'H'), faction: hero.faction, trainless: G.World.trainless(hero) },
        { name: info.name, hero: info.hero || null, stacks: info.stacks, faction: info.faction, ai: info.owner < 0, neutral: info.owner < 0, trainless: info.hero ? G.World.trainless(info.hero) : false },
      ],
    });
    G.BattleUI.start(b, () => this.resolve(b, hero, tgt, info));
  },
  fieldUpgrade(hero) {
    if (G.Heroes.skill(hero, 'fieldcraft') < 2) return;
    const P = this.state.players[hero.owner];
    for (const g of hero.army) {
      const p = G.Units.parse(g.key.split('@')[0]); if (g.key.includes('@') || p.up !== 0 || p.tier > 3) continue;
      if (!G.World.townsOf(hero.owner).some(t => t.built['up1_' + p.tier] && t.faction === p.faction)) continue;
      if (P.essence[p.tier] >= g.count) { P.essence[p.tier] -= g.count; g.key = G.Units.key(p.faction, p.tier, 1, ''); G.World.log(`${hero.name}'s ${g.count} creatures upgrade in the field.`); }
    }
  },

  resolve(b, hero, tgt, info) {
    const S = this.state, W = G.World, o = b.over, sum = b.summary();
    const lines = [];
    const aWon = o.winner === 0, dWon = o.winner === 1;
    const aAlive = b.stacksOf(0).length > 0, dAlive = b.stacksOf(1).length > 0;
    // --- casualties
    const woundA = W.applyCasualties(hero.owner, hero.army, this.part(sum[0], 'H'), aAlive, hero);
    if (woundA.length) lines.push(`${hero.name}: ${G.util.sum(woundA.map(w => w.count))} wounded ride in the supply train.`);
    const defHero = info.hero;
    if (defHero) { const w = W.applyCasualties(defHero.owner, defHero.army, this.part(sum[1], 'H'), dAlive, defHero); if (w.length) lines.push(`${defHero.name}: ${G.util.sum(w.map(x => x.count))} wounded.`); }
    if (tgt.kind === 'town') W.applyCasualties(info.town.owner, info.town.garrison, this.part(sum[1], 'T'), dAlive, null);
    if (tgt.kind === 'monster' || tgt.kind === 'guard') {
      const army = tgt.kind === 'monster' ? tgt.obj.army : tgt.obj.guard;
      army.stacks = army.stacks.map((s, i) => { const st = sum[1].stacks.find(x => x.uid === 'M' + i); return { key: s.key, count: st ? st.survivors : 0 }; }).filter(s => s.count > 0);
    }
    // --- xp & essence
    const lvA = W.heroXP(hero, b.sides[0], o.fled === 1 ? { fled: true } : null, aWon, defHero, b.round);
    lines.push(...lvA);
    if (defHero) lines.push(...W.heroXP(defHero, b.sides[1], o.fled === 0 ? { fled: true } : null, dWon, hero, b.round));
    const win = aWon ? 0 : dWon ? 1 : null;
    const winOwner = win === 0 ? hero.owner : win === 1 ? info.owner : -1;
    if (winOwner >= 0) {
      const P = S.players[winOwner], k = b.sides[win].st.killsByTier;
      let ess = [];
      for (let t = 1; t <= 4; t++) if (k[t]) { P.essence[t] += k[t]; ess.push(`${k[t]}×T${t}`); }
      if (ess.length) lines.push(`${P.name} gains upgrade essence: ${ess.join(', ')}.`);
    }
    // --- commander deaths
    const gone = [sum[0].heroGone, sum[1].heroGone];
    if (gone[0] === 'dead') { this.killHero(hero, defHero); lines.push(`${hero.name} fell beside the tier-4 creatures.`); }
    if (defHero && gone[1] === 'dead') { this.killHero(defHero, hero); lines.push(`${defHero.name} fell beside the tier-4 creatures.`); }
    // --- outcomes
    const n = tgt.node;
    if (aWon) {
      if (tgt.kind === 'monster') { const card = W.card(n.c); card.objs = card.objs.filter(x => x !== tgt.obj); lines.push(o.reason === 'fled' ? 'The creatures flee the area.' : 'The creatures are destroyed.'); }
      if (tgt.kind === 'guard') { delete tgt.obj.guard; }
      if (defHero && defHero.alive) {
        if (o.reason === 'fled') this.retreatHero(defHero, hero, lines);
        else { this.killHero(defHero, hero); lines.push(`${defHero.name} is defeated. ${hero.name} takes their spell book.`); }
      }
      if (tgt.kind === 'town') info.town.garrison = [];
      if (hero.alive && hero.army.length) {
        W.step(hero, n);
        if (tgt.kind === 'town') { this.capture(hero, info.town, lines); if (S.winner != null) return; }
        if (tgt.kind === 'guard') { this.afterReport(lines, b, () => this.site(hero, tgt.obj)); return; }
      }
    } else if (dWon) {
      if (hero.alive) {
        if (o.reason === 'fled') { hero.mp = 0; lines.push(`${hero.name} retreats.`); if (defHero && G.Heroes.skill(defHero, 'spellthief') >= 1) this.takeBook(defHero, hero); }
        else { this.killHero(hero, defHero); lines.push(`${hero.name} is defeated.`); }
      }
    } else { hero.mp = 0; lines.push('Neither side can make headway; the armies disengage.'); }
    if (hero.alive && !hero.army.length) { this.killHero(hero, defHero); lines.push(`${hero.name} has no army left and leaves the field for good.`); }
    this.checkElimination();
    this.afterReport(lines, b);
  },
  part(sideSum, prefix) { return { stacks: sideSum.stacks.filter(s => s.uid && s.uid.startsWith(prefix)).map(s => Object.assign({}, s, { uid: s.uid.slice(1) })) }; },
  afterReport(lines, b, then) {
    const h = G.UI.h;
    G.World.computeVisible(this.state.cur);
    G.WorldUI.enter();
    if (this.state.winner != null) return;
    G.UI.modal(h('div', { class: 'col', style: { minWidth: '420px' } }, h('h2', null, 'After the battle'), ...lines.map(l => h('div', null, l)),
      h('div', { class: 'row', style: { justifyContent: 'flex-end' } }, h('button', { class: 'primary', onclick: () => { G.UI.closeModal(); this.checkSkillChoices(); then && then(); } }, 'OK'))), { locked: true });
  },
  takeBook(winner, loser) { for (const s of loser.spellbook) if (!winner.spellbook.includes(s)) winner.spellbook.push(s); },
  killHero(loser, winner) {
    const S = this.state;
    if (!loser.alive) return;
    loser.alive = false;
    if (winner && winner.alive) { this.takeBook(winner, loser); winner.artifacts.push(...loser.artifacts); loser.artifacts = []; }
    const P = S.players[loser.owner];
    if (P.trans.active && P.trans.active.hero === loser.id) { P.trans.lines.push(P.trans.active.line); P.trans.active = null; }
    if (loser.army.length) { const t = G.World.townsOf(loser.owner)[0]; if (t && !winner) for (const g of loser.army) G.Army.add(t.garrison, g.key, g.count); }
    G.World.log(`${loser.name} is gone.`);
  },
  retreatHero(loser, winner, lines) {
    const t = G.World.townsOf(loser.owner).find(t => !G.World.heroAt(t.c, t.x, t.y, loser));
    if (winner && G.Heroes.skill(winner, 'spellthief') >= 1) { this.takeBook(winner, loser); lines.push(`${winner.name} copies ${loser.name}'s spell book.`); }
    if (t) { loser.pos = { c: t.c, x: t.x, y: t.y }; loser.mp = 0; lines.push(`${loser.name} retreats to ${t.name}.`); }
    else { this.killHero(loser, winner); lines.push(`${loser.name} has nowhere to retreat and is lost.`); }
  },
  checkElimination() {
    const S = this.state;
    for (let p = 0; p < S.players.length; p++) {
      const P = S.players[p]; if (!P.alive) continue;
      if (!G.World.heroesOf(p).length && !G.World.townsOf(p).length) { P.alive = false; G.World.log(`${P.name} has been eliminated.`); }
    }
    const alive = S.players.filter(p => p.alive);
    if (alive.length === 1) { S.winner = S.players.indexOf(alive[0]); this.victory(S.winner); }
  },
  victory(p) {
    const h = G.UI.h, P = this.state.players[p];
    const el = G.UI.clear(document.getElementById('handoff'));
    el.append(h('div', { class: 'sigil', style: { color: P.color } }, '♛'), h('h1', { style: { color: P.color } }, `${P.name} is victorious!`),
      h('div', { class: 'muted', style: { margin: '8px 0 18px' } }, `Day ${this.state.day}.`), h('button', { class: 'primary', onclick: () => { this.state = null; G.Main.menu(); } }, 'Main menu'));
    G.UI.closeModal(); G.UI.show('handoff');
  },

  // ---------------------------------------------------------------- saves
  api: null,
  async detectApi() {
    if (!/^http/.test(location.protocol)) { this.api = false; return; }
    try { const r = await fetch('/api/saves'); this.api = r.ok; } catch (e) { this.api = false; }
    if (this.api) setInterval(() => fetch('/api/ping').catch(() => {}), 10000), fetch('/api/ping').catch(() => {});
  },
  serialize() { this.state.rngState = this.rng.state(); return JSON.stringify(this.state, (k, v) => (k[0] === '_' ? undefined : v)); },
  async save(name) {
    const data = this.serialize();
    try {
      if (this.api) { const r = await fetch('/api/save?name=' + encodeURIComponent(name), { method: 'POST', body: data }); if (!r.ok) throw new Error('save failed'); }
      else { localStorage.setItem('h4t_save_' + name, data); const idx = JSON.parse(localStorage.getItem('h4t_saves') || '{}'); idx[name] = Date.now(); localStorage.setItem('h4t_saves', JSON.stringify(idx)); }
      return true;
    } catch (e) { console.warn(e); return false; }
  },
  autosave() { this.save('autosave'); },
  async listSaves() {
    try {
      if (this.api) { const r = await fetch('/api/saves'); return await r.json(); }
      const idx = JSON.parse(localStorage.getItem('h4t_saves') || '{}'); return Object.keys(idx).map(n => ({ name: n, time: idx[n] / 1000 })).sort((a, b) => b.time - a.time);
    } catch (e) { return []; }
  },
  async loadSave(name) {
    let txt = null;
    try {
      if (this.api) { const r = await fetch('/api/save?name=' + encodeURIComponent(name)); if (r.ok) txt = await r.text(); }
      else txt = localStorage.getItem('h4t_save_' + name);
    } catch (e) { }
    if (!txt) { G.UI.toast('Could not load ' + name); return; }
    const S = JSON.parse(txt);
    this.state = S; this.rng = G.RNG(1); this.rng.setState(S.rngState || 1);
    G.WorldUI.cache = null;
    this.resume();
  },
  saveDialog() {
    G.UI.prompt('Save game as', 'Day ' + this.state.day, async v => { if (!v) return; const ok = await this.save(v.replace(/[^A-Za-z0-9 _\-.]/g, '')); G.UI.toast(ok ? 'Saved' : 'Save failed'); });
  },
  async loadDialog() {
    const h = G.UI.h, list = await this.listSaves();
    G.UI.modal(h('div', { class: 'col', style: { minWidth: '380px' } }, h('h2', null, 'Load game'),
      list.length ? list.map(s => h('button', { style: { textAlign: 'left' }, onclick: () => { G.UI.closeModal(); this.loadSave(s.name); } }, h('b', null, s.name), h('span', { class: 'muted' }, '  ' + new Date(s.time * 1000).toLocaleString()))) : h('div', { class: 'muted' }, 'No saved games yet.'),
      h('div', { class: 'muted', style: { fontSize: '12px' } }, this.api ? 'Saves live in the "saves" folder next to the program.' : 'Saves live in this browser.'),
      h('button', { onclick: () => G.UI.closeModal() }, 'Close')));
  },
};
if (typeof window !== 'undefined') window.addEventListener('DOMContentLoaded', () => G.Game.detectApi());
