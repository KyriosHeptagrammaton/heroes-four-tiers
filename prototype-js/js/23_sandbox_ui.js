// ============================================================================
// Combat sandbox: build two armies + commanders, pick the ground, fight or simulate.
// ============================================================================
G.Sandbox = {
  cfg: null,
  defaultSide(f, ai) {
    return {
      faction: f, ai, name: '',
      hero: { enabled: true, cls: 'warlord', name: '', stats: Object.assign({}, G.CFG.heroStart.warlord), skills: {}, artifacts: [], equipped: ['flame', 'valor'] },
      stacks: [{ key: G.Units.key(f, 1, 0, ''), count: 18 }, { key: G.Units.key(f, 2, 0, ''), count: 6 }, { key: G.Units.key(f, 3, 0, ''), count: 4 }],
    };
  },
  init() {
    if (!this.cfg) this.cfg = { sides: [this.defaultSide('alpha', false), this.defaultSide('beta', true)], terrain: 'field', time: 'dawn', weather: 'clear', ignored: false, seed: 0 };
    this.cfg.sides[0].name = this.cfg.sides[0].name || 'Attacker';
    this.cfg.sides[1].name = this.cfg.sides[1].name || 'Defender';
    G.UI.show('sandbox');
    this.render();
  },

  makeHero(hc, f, rng) {
    if (!hc.enabled) return null;
    const hero = G.Heroes.create(hc.cls, f, hc.name || null, rng);
    hero.stats = Object.assign({}, hc.stats);
    hero.skills = Object.assign({}, hc.skills);
    hero.artifacts = hc.artifacts.slice();
    hero.spellbook = Object.keys(G.SPELLS);
    hero.equipped = hc.equipped.slice();
    if (hc.name) hero.name = hc.name;
    return hero;
  },
  battleOpts(seed, forceAI) {
    const c = this.cfg;
    return {
      seed: seed || c.seed || ((Math.random() * 1e9) | 0), terrain: c.terrain, time: c.time, weather: c.weather, ignoredAttack: c.ignored,
      sides: c.sides.map(sd => ({ name: sd.name, faction: sd.faction, ai: forceAI || sd.ai, hero: this.makeHero(sd.hero, sd.faction), stacks: sd.stacks.map(s => ({ key: s.key, count: s.count })) })),
    };
  },
  fight() {
    const b = new G.Battle(this.battleOpts());
    G.BattleUI.start(b, () => this.init());
  },

  simulate(n) {
    const h = G.UI.h;
    const res = { w: [0, 0, 0], rounds: 0, loss: [0, 0], n: 0 };
    const out = h('div', { class: 'col', style: { minWidth: '420px' } }, h('h2', null, 'Simulating…'));
    G.UI.modal(out, { locked: true });
    const total = [0, 1].map(i => G.util.sum(this.cfg.sides[i].stacks.map(s => s.count * G.Units.value(G.Units.resolve(s.key)))));
    const step = () => {
      for (let k = 0; k < 10 && res.n < n; k++, res.n++) {
        const b = new G.Battle(this.battleOpts((res.n + 1) * 7919, true));
        let guard = 0; while (!b.over && guard++ < 20000) G.CombatAI.step(b);
        res.w[b.over.winner === null ? 2 : b.over.winner]++;
        res.rounds += b.round;
        for (let i = 0; i < 2; i++) res.loss[i] += G.util.sum(b.stacks.filter(s => s.side === i && !s.name.match(/^(Militia|Mercenaries)$/)).map(s => (s.start - Math.max(0, s.count)) * G.Units.value(s.def)));
      }
      G.UI.clear(out);
      const pct = x => Math.round(100 * x / Math.max(1, res.n)) + '%';
      out.append(h('h2', null, `AI vs AI: ${res.n} / ${n} battles`),
        h('table', { class: 'tbl' },
          h('tr', null, h('th', null, ''), h('th', null, this.cfg.sides[0].name + ' ▼'), h('th', null, this.cfg.sides[1].name + ' ▲')),
          h('tr', null, h('td', null, 'Wins'), h('td', null, pct(res.w[0])), h('td', null, pct(res.w[1]))),
          h('tr', null, h('td', null, 'Avg. value lost'), h('td', null, G.util.fmt(res.loss[0] / Math.max(1, res.n) / Math.max(1, total[0]) * 100) + '%'), h('td', null, G.util.fmt(res.loss[1] / Math.max(1, res.n) / Math.max(1, total[1]) * 100) + '%'))),
        h('div', { class: 'muted' }, `Stalemates/draws: ${pct(res.w[2])} · average ${G.util.fmt(res.rounds / Math.max(1, res.n))} rounds · army value ${G.util.fmt(total[0])} vs ${G.util.fmt(total[1])} (T1=1, T2=2, T3=3, T4=6 per creature)`),
        h('div', { class: 'muted', style: { fontSize: '12px' } }, 'The AI is a simple one-ply heuristic, so treat these as rough signals, not verdicts.'));
      if (res.n < n) setTimeout(step, 0);
      else out.append(h('div', { class: 'row', style: { justifyContent: 'flex-end' } }, h('button', { class: 'primary', onclick: () => G.UI.closeModal() }, 'Close')));
    };
    setTimeout(step, 30);
  },

  // ---------------------------------------------------------------- rendering
  render() {
    const h = G.UI.h, c = this.cfg, el = G.UI.clear(document.getElementById('sandbox'));
    const sel = (opts, val, on, attrs) => { const s = h('select', attrs || null, opts.map(([v, l]) => h('option', { value: v, selected: v === val }, l))); s.onchange = () => on(s.value); return s; };
    const T = G.TERRAIN[c.terrain];
    el.append(h('div', { class: 'bar-top' },
      h('button', { onclick: () => G.Main.menu() }, '◂ Menu'),
      h('h2', { style: { margin: 0 } }, 'Combat Sandbox'),
      h('span', { class: 'grow' }),
      h('span', { class: 'muted' }, 'Ground'), sel(Object.keys(G.TERRAIN).filter(t => t !== 'chasm').map(k => [k, G.TERRAIN[k].name]), c.terrain, v => { c.terrain = v; this.render(); }, { tip: `<b>${T.name}</b><br>${T.desc}` }),
      h('span', { class: 'muted' }, 'Time'), sel(Object.keys(G.TIMES).map(k => [k, G.TIMES[k].name]), c.time, v => { c.time = v; this.render(); }, { tip: G.TIMES[c.time].desc }),
      h('span', { class: 'muted' }, 'Weather'), sel(Object.keys(G.WEATHER).map(k => [k, G.WEATHER[k].name]), c.weather, v => { c.weather = v; this.render(); }, { tip: G.WEATHER[c.weather].desc }),
      h('label', { class: 'row', tip: 'The defender chose to ignore the attack instead of picking ground: 1-3 random defending stacks gain one slow.' }, h('input', { type: 'checkbox', checked: c.ignored, onchange: e => { c.ignored = e.target.checked; } }), 'Defender ignored'),
      h('button', { onclick: () => this.simulate(100), tip: 'Run 100 AI-vs-AI battles with these armies' }, '⚖ Simulate ×100'),
      h('button', { class: 'primary', onclick: () => this.fight() }, '⚔ Fight!'),
    ));
    const body = h('div', { class: 'sb-body' });
    body.append(this.sideEditor(0), this.sideEditor(1));
    el.append(body);
  },

  sideEditor(i) {
    const h = G.UI.h, sd = this.cfg.sides[i], U = G.util;
    const sel = (opts, val, on) => { const s = h('select', null, opts.map(([v, l]) => h('option', { value: v, selected: String(v) === String(val) }, l))); s.onchange = () => on(s.value); return s; };
    const box = h('div', { class: 'sb-side' });
    box.append(h('div', { class: 'panel' },
      h('div', { class: 'row wrap' },
        h('h2', { style: { margin: 0 } }, i === 0 ? '▼ Attacker' : '▲ Defender'),
        h('input', { value: sd.name, style: { width: '120px' }, onchange: e => sd.name = e.target.value }),
        h('span', { class: 'grow' }),
        h('span', { class: 'muted' }, 'Faction'), sel(G.FACTION_IDS.map(f => [f, G.FACTIONS[f].name]), sd.faction, v => { sd.faction = v; this.render(); }),
        h('label', { class: 'row' }, h('input', { type: 'checkbox', checked: sd.ai, onchange: e => { sd.ai = e.target.checked; } }), 'AI controlled')),
    ));
    // stacks
    const sp = h('div', { class: 'panel' }, h('div', { class: 'row between' }, h('h3', null, `Army (${sd.stacks.length}/${G.CFG.maxStacks} stacks)`),
      h('button', { class: 'small', disabled: sd.stacks.length >= G.CFG.maxStacks, onclick: () => { sd.stacks.push({ key: G.Units.key(sd.faction, 1, 0, ''), count: 10 }); this.render(); } }, '+ Add stack')));
    sd.stacks.forEach((s, k) => {
      const d = G.Units.resolve(s.key);
      const row = h('div', { class: 'stack-row' },
        h('span', { tip: G.UI.unitTip(d) }, G.UI.sym(d, 26)),
        h('button', { style: { textAlign: 'left' }, onclick: () => this.pickUnit(sd, s), tip: 'Click to change unit / mount it' }, d.name + (d.placeholder ? ' ⚑' : '')),
        h('input', { type: 'number', min: 1, value: s.count, onchange: e => { s.count = Math.max(1, +e.target.value || 1); } }),
        h('button', { class: 'small', onclick: () => { sd.stacks.splice(k, 1); this.render(); } }, '✕'));
      sp.append(row);
    });
    box.append(sp);
    // hero
    const hc = sd.hero;
    const hp = h('div', { class: 'panel' });
    hp.append(h('div', { class: 'row wrap' }, h('label', { class: 'row' }, h('input', { type: 'checkbox', checked: hc.enabled, onchange: e => { hc.enabled = e.target.checked; this.render(); } }), h('h3', { style: { margin: 0 } }, 'Commander')),
      hc.enabled ? sel(Object.keys(G.CLASSES).map(k => [k, G.CLASSES[k].name]), hc.cls, v => { hc.cls = v; hc.stats = Object.assign({}, G.CFG.heroStart[v]); hc.skills = Object.assign({}, G.CLASSES[v].skills); this.render(); }) : null,
      hc.enabled ? h('input', { placeholder: 'name', value: hc.name, style: { width: '110px' }, onchange: e => hc.name = e.target.value }) : null));
    if (hc.enabled) {
      hp.append(h('div', { class: 'muted', style: { fontSize: '12px', margin: '4px 0' } }, G.CLASSES[hc.cls].desc));
      const stats = h('div', { class: 'row wrap' });
      for (const k of G.PRIMARY) stats.append(h('label', { class: 'row', style: { gap: '4px' } }, h('span', { class: 'muted' }, k.slice(0, 4)), h('input', { type: 'number', value: hc.stats[k], style: { width: '52px' }, onchange: e => { hc.stats[k] = +e.target.value || 0; this.render(); } })));
      hp.append(stats);
      // spells
      const fakeHero = { cls: hc.cls, skills: hc.skills, artifacts: hc.artifacts, stats: hc.stats };
      const cost = G.Heroes.equippedCost(fakeHero, hc.equipped), know = G.Heroes.stat(fakeHero, 'knowledge');
      const spRow = h('div', { class: 'row wrap', style: { marginTop: '8px' } }, h('span', { class: 'muted' }, 'Spells'),
        h('span', { class: 'chip ' + (cost > know && hc.equipped.length > 1 ? 'warn' : '') , tip: 'Knowledge used / knowledge. You may always equip any one spell.' }, `${cost}/${know} knowledge`));
      hc.equipped.forEach((id, k) => spRow.append(h('span', { class: 'chip', tip: G.SPELLS[id].desc }, G.SPELLS[id].name, h('a', { style: { cursor: 'pointer', color: 'var(--danger)' }, onclick: () => { hc.equipped.splice(k, 1); this.render(); } }, ' ✕'))));
      const add = sel([['', '+ equip…']].concat(Object.keys(G.SPELLS).map(k => [k, `${G.SPELLS[k].name} (${G.Heroes.spellCost(fakeHero, k)})`])), '', v => { if (v) { hc.equipped.push(v); this.render(); } });
      spRow.append(add);
      hp.append(spRow);
      // skills
      const skRow = h('div', { class: 'row wrap', style: { marginTop: '8px' } }, h('span', { class: 'muted' }, 'Skills'));
      for (const k in G.SKILLS) {
        const S = G.SKILLS[k];
        skRow.append(h('label', { class: 'row', style: { gap: '2px' }, tip: `<b>${S.name}</b><br>` + S.tiers.map((t, n) => `${'I'.repeat(n + 1)}: ${t}`).join('<br>') }, h('span', { style: { fontSize: '12px' } }, S.name),
          sel([[0, '–']].concat(S.tiers.map((t, n) => [n + 1, 'I'.repeat(n + 1)])), hc.skills[k] || 0, v => { hc.skills[k] = +v; if (k === 'sorcery' && +v === 3 && hc.skills.arcana === 3) hc.skills.arcana = 2; if (k === 'arcana' && +v === 3 && hc.skills.sorcery === 3) hc.skills.sorcery = 2; this.render(); })));
      }
      hp.append(skRow);
      const arRow = h('div', { class: 'row wrap', style: { marginTop: '8px' } }, h('span', { class: 'muted' }, 'Artifacts'));
      for (const a in G.ARTIFACTS) arRow.append(h('label', { class: 'row', style: { gap: '3px', fontSize: '12px' }, tip: G.ARTIFACTS[a].desc }, h('input', { type: 'checkbox', checked: hc.artifacts.includes(a), onchange: e => { if (e.target.checked) hc.artifacts.push(a); else hc.artifacts = hc.artifacts.filter(x => x !== a); } }), G.ARTIFACTS[a].name));
      hp.append(arRow);
    }
    box.append(hp);
    return box;
  },

  // unit picker modal: all variants, optionally mounted
  pickUnit(sd, s) {
    const h = G.UI.h;
    let rider = s.key.split('@')[0], mount = s.key.includes('@') ? s.key.split('@')[1] : null;
    let step = 'rider';
    const draw = () => {
      const box = h('div', { class: 'col', style: { minWidth: '640px' } });
      box.append(h('h2', null, step === 'rider' ? 'Choose unit' : 'Choose mount'));
      if (step === 'mount') box.append(h('div', { class: 'muted' }, `Rider: ${G.Units.resolve(rider).name}. Mounts needed = rider weight ÷ mount strength (rounded up).`));
      for (const f of G.FACTION_IDS) {
        const r = h('div', { class: 'row wrap', style: { borderBottom: '1px solid var(--line)', paddingBottom: '6px' } }, h('b', { style: { color: G.FACTIONS[f].color, width: '52px' } }, G.FACTIONS[f].name));
        for (let t = 1; t <= 4; t++) for (const k of G.Units.variants(f, t)) {
          const d = G.Units.resolve(k);
          let extra = '';
          if (step === 'mount') { const R = G.Units.resolve(rider); extra = `<div style="margin-top:4px">Mounts per rider: ${Math.ceil(R.w / d.s)}</div>`; }
          r.append(h('button', { class: 'small' + ((step === 'rider' ? rider : mount) === k ? ' sel' : ''), tip: G.UI.unitTip(d, extra), onclick: () => {
            if (step === 'rider') { rider = k; } else { mount = k; }
            finish();
          }, style: { display: 'inline-flex', alignItems: 'center', gap: '3px' } }, G.UI.sym(d, 20), d.name + (d.placeholder ? '⚑' : '')));
        }
        box.append(r);
      }
      const mountToggle = h('label', { class: 'row' }, h('input', { type: 'checkbox', checked: !!mount, onchange: e => { if (e.target.checked) { step = 'mount'; draw(); } else { mount = null; finish(); } } }), 'Mounted (rider + mount)');
      box.append(h('div', { class: 'row between' }, step === 'rider' ? mountToggle : h('span'), h('button', { onclick: () => G.UI.closeModal() }, 'Close')));
      G.UI.modal(box);
    };
    const finish = () => { s.key = mount ? rider + '@' + mount : rider; if (step === 'rider' && mount) { /* keep */ } G.UI.closeModal(); this.render(); };
    draw();
  },
};
