// ============================================================================
// Army management (split/merge stacks, riders, transfers) and hero screen.
// ============================================================================
G.ArmyUI = {
  groupRow(groups, gi, opts) {
    const h = G.UI.h, g = groups[gi], d = G.Units.resolve(g.key);
    const divs = G.Army.divisors(g.count).filter(k => k - (g.splits || 1) + G.Army.stacks(groups) <= G.CFG.maxStacks);
    const sel = h('select', { tip: 'Doc: all stacks of the same creature must be the same size, so a group can only split into equal stacks.' }, divs.map(k => h('option', { value: k, selected: k === g.splits }, k === 1 ? '1 stack' : `${k} stacks of ${g.count / k}`)));
    sel.onchange = () => { g.splits = +sel.value; opts.redraw(); };
    const row = h('div', { class: 'row wrap', style: { padding: '5px 0', borderBottom: '1px solid var(--line)' } },
      h('span', { tip: G.UI.unitTip(d) }, G.UI.sym(d, 30)),
      h('div', { class: 'grow', style: { minWidth: '140px' } }, h('div', null, h('b', null, g.count), ' ', g.name || d.name, d.placeholder ? h('span', { class: 'flagmark', tip: 'Placeholder second-upgrade stats' }, ' ⚑') : null), h('div', { class: 'muted', style: { fontSize: '11px' } }, `${G.FACTIONS[d.faction].name} T${d.tier}${d.mounted ? ' · mounted' : ''}`)),
      sel,
      h('button', { class: 'small', tip: 'Rename this group', onclick: () => G.UI.prompt('Name', g.name || d.name, v => { g.name = v; opts.redraw(); }) }, '✎'),
      d.mounted ? h('button', { class: 'small', onclick: () => { G.Army.dismount(groups, gi); opts.redraw(); } }, 'Dismount') : null,
      opts.transfer ? h('button', { class: 'small', tip: opts.transferTip, onclick: () => opts.transfer(gi) }, opts.transferLabel) : null,
      opts.canDismiss ? h('button', { class: 'small danger', tip: 'Dismiss', onclick: () => G.UI.confirm(`Dismiss ${g.count} ${d.name}?`, () => { groups.splice(gi, 1); opts.redraw(); }) }, '✕') : null);
    return row;
  },
  mountPanel(groups, redraw) {
    const h = G.UI.h;
    const cands = groups.map((g, i) => [i, G.Units.resolve(g.key)]).filter(([, d]) => !d.mounted);
    if (cands.length < 2) return h('div', { class: 'muted', style: { fontSize: '12px' } }, 'Riders: need two different unmounted groups.');
    let r = cands[0][0], m = cands[1][0], n = 1;
    const info = h('span', { class: 'muted' });
    const upd = () => {
      if (r === m) { info.textContent = 'pick two different groups'; return; }
      const R = G.Units.resolve(groups[r].key), M = G.Units.resolve(groups[m].key), per = Math.ceil(R.w / M.s);
      const max = Math.min(groups[r].count, Math.floor(groups[m].count / per));
      info.innerHTML = `${per} mount(s) per rider · up to ${max}`;
      info.dataset.tip = G.UI.unitTip(G.Units.resolve(groups[r].key + '@' + groups[m].key));
    };
    const mk = (v, on) => { const s = h('select', null, cands.map(([i, d]) => h('option', { value: i, selected: i === v }, `${groups[i].count} ${d.name}`))); s.onchange = () => { on(+s.value); upd(); }; return s; };
    const num = h('input', { type: 'number', min: 1, value: 1, onchange: e => n = Math.max(1, +e.target.value || 1) });
    const box = h('div', { class: 'row wrap', style: { marginTop: '8px' } }, h('b', null, 'Mount'), mk(r, v => r = v), h('span', null, 'on'), mk(m, v => m = v), h('span', null, '×'), num, info,
      h('button', { class: 'small', onclick: () => { if (r === m) return; const err = G.Army.mount(groups, r, m, n); if (err) G.UI.toast(err); redraw(); } }, 'Mount'));
    setTimeout(upd, 0);
    return box;
  },
  moveUnits(from, to, gi, cb) {
    const g = from[gi];
    G.UI.prompt(`Move how many ${G.Units.resolve(g.key).name}? (max ${g.count})`, String(g.count), v => {
      const n = Math.max(0, Math.min(g.count, Math.floor(+v || 0))); if (!n) return;
      if (!G.Army.canAdd(to, g.key)) { G.UI.toast('No free stack slot there'); return; }
      g.count -= n; G.Army.add(to, g.key, n, g.name);
      if (g.count <= 0) from.splice(gi, 1); else G.Army.normalize(g);
      cb();
    });
  },

  // hero army (+ town garrison if tid)
  armyScreen(hid, tid, onClose) {
    const h = G.UI.h, S = G.Game.state;
    const hero = hid && G.World.hero(hid), t = tid && S.towns[tid];
    const draw = () => {
      const box = h('div', { class: 'col', style: { minWidth: '720px' } });
      const cols = h('div', { class: 'row', style: { alignItems: 'flex-start', gap: '16px' } });
      const col = (title, groups, other, dirLabel, moveCost) => {
        const c = h('div', { class: 'grow panel' }, h('div', { class: 'row between' }, h('h3', null, title), h('span', { class: 'muted' }, `${G.Army.stacks(groups)}/${G.CFG.maxStacks} stacks`)));
        groups.forEach((g, gi) => c.append(this.groupRow(groups, gi, { redraw: draw, canDismiss: true, transfer: other ? (i => { const go = () => this.moveUnits(groups, other, i, () => { if (hero) hero.mp = 0; draw(); G.WorldUI.renderSide(); }); if (moveCost && hero && hero.mp > 0) G.UI.confirm('Doc rule: exchanging units ends the hero\'s movement for today. Continue?', go); else go(); }) : null, transferLabel: dirLabel, transferTip: 'Move creatures' })));
        if (!groups.length) c.append(h('div', { class: 'muted' }, 'Empty'));
        c.append(this.mountPanel(groups, draw));
        return c;
      };
      if (hero) cols.append(col(`♛ ${hero.name}`, hero.army, t ? t.garrison : null, '→ town', true));
      if (t) cols.append(col(`♜ ${t.name} garrison`, t.garrison, hero ? hero.army : null, '→ hero', true));
      box.append(h('h2', null, 'Armies'), cols);
      if (hero && G.Heroes.skill(hero, 'fieldcraft') >= 1 && !t) box.append(h('button', { class: 'small', onclick: () => G.TownUI.upgradeModal(hero.id, null) }, 'Upgrade in the field (Fieldcraft)'));
      box.append(h('div', { class: 'row', style: { justifyContent: 'flex-end' } }, h('button', { class: 'primary', onclick: () => { G.UI.closeModal(); G.WorldUI.renderSide(); onClose && onClose(); } }, 'Done')));
      G.UI.modal(box);
    };
    draw();
  },

  exchange(h1id, h2id) {
    const h = G.UI.h, A = G.World.hero(h1id), B = G.World.hero(h2id);
    const draw = () => {
      const cols = h('div', { class: 'row', style: { alignItems: 'flex-start', gap: '16px' } });
      for (const [X, Y] of [[A, B], [B, A]]) {
        const c = h('div', { class: 'grow panel' }, h('h3', null, '♛ ' + X.name));
        X.army.forEach((g, gi) => c.append(this.groupRow(X.army, gi, { redraw: draw, transfer: i => this.moveUnits(X.army, Y.army, i, () => { A.mp = 0; B.mp = 0; draw(); }), transferLabel: '→ ' + Y.name })));
        c.append(this.mountPanel(X.army, draw));
        cols.append(c);
      }
      G.UI.modal(h('div', { class: 'col', style: { minWidth: '720px' } }, h('h2', null, 'Exchange'), h('div', { class: 'muted' }, 'Doc rule: both heroes lose all movement when they exchange units.'), cols,
        h('div', { class: 'row', style: { justifyContent: 'flex-end' } }, h('button', { class: 'primary', onclick: () => { G.UI.closeModal(); G.WorldUI.renderSide(); } }, 'Done'))));
    };
    draw();
  },

  heroScreen(hid) {
    const h = G.UI.h, hero = G.World.hero(hid), U = G.util;
    const draw = () => {
      const box = h('div', { class: 'col', style: { minWidth: '700px' } });
      box.append(h('div', { class: 'row between' }, h('h2', { style: { margin: 0, cursor: 'pointer' }, onclick: () => G.UI.prompt('Rename hero', hero.name, v => { if (v) { hero.name = v; draw(); } }) }, '♛ ' + hero.name), h('span', { class: 'muted' }, G.CLASSES[hero.cls].name + ' · ' + G.FACTIONS[hero.faction].name)));
      box.append(h('div', { class: 'muted', style: { fontSize: '12px' } }, G.CLASSES[hero.cls].desc + ' Primary skills grow by use: each level costs 3× (skilled ★) or 4× (unskilled) the next level in experience.'));
      const pt = h('table', { class: 'tbl' }, h('tr', null, h('th', null, 'Primary'), h('th', null, 'Level'), h('th', null, 'Experience'), h('th', null, 'Earned by')));
      const how = { attack: 'killing enemy creatures (tier each)', defence: 'losing creatures to damage (tier each)', courage: 'starting a battle at ≤0 courage; your creatures deserting', initiative: 'rounds where your hero does not act first', power: 'casting spells', knowledge: '+3 when your spells fill your knowledge; +3 per spell when you run out' };
      for (const k of G.PRIMARY) {
        const sk = G.CLASSES[hero.cls].skilled.includes(k);
        pt.append(h('tr', null, h('td', null, (sk ? '★ ' : '') + k), h('td', null, k === 'initiative' ? G.Heroes.initStr(G.Heroes.stat(hero, k)) : G.Heroes.stat(hero, k)), h('td', null, `${U.fmt(hero.xp[k])} / ${G.Heroes.primaryCost(hero, k)}`), h('td', { class: 'muted', style: { fontSize: '12px' } }, how[k])));
      }
      box.append(pt);
      // secondary
      if (!G.CLASSES[hero.cls].noSecondary) {
        const st = h('table', { class: 'tbl' }, h('tr', null, h('th', null, 'Skill'), h('th', null, 'Tier'), h('th', null, 'XP / next'), h('th', null, 'Next tier')));
        for (const k in G.SKILLS) {
          const S = G.SKILLS[k], tier = G.Heroes.skill(hero, k), maxed = G.Heroes.skillMaxed(hero, k);
          st.append(h('tr', null, h('td', { tip: S.tiers.map((t, i) => `${'I'.repeat(i + 1)}: ${t}`).join('<br>') }, S.name, h('span', { class: 'muted' }, ` (${S.cat})`)), h('td', null, tier ? 'I'.repeat(tier) : '–'),
            h('td', null, maxed ? 'max' : `${U.fmt(hero.skillXp[k] || 0)} / ${G.Heroes.skillCost(hero, k)}`), h('td', { class: 'muted', style: { fontSize: '12px' } }, maxed ? '' : S.tiers[tier])));
        }
        box.append(h('h3', { style: { marginTop: '8px' } }, 'Secondary skills'), h('div', { class: 'muted', style: { fontSize: '12px' } }, 'All skills gather XP by use. When two or more are ready you choose one; the other loses XP equal to its cost. Every skill you know makes the others cost more.'), st);
        if (hero.pendingSkillChoice) box.append(h('button', { class: 'primary', onclick: () => this.skillChoice(hid, draw) }, '★ Choose a new skill'));
      }
      // spells
      const know = G.Heroes.stat(hero, 'knowledge'), cost = G.Heroes.equippedCost(hero, hero.equipped);
      const sp = h('div', { class: 'panel' }, h('div', { class: 'row between' }, h('h3', null, 'Spells'), h('span', { class: 'chip ' + (cost > know && hero.equipped.length > 1 ? 'warn' : '') }, `Knowledge ${cost} / ${know}`)),
        h('div', { class: 'muted', style: { fontSize: '12px' } }, `Equip spells up to your knowledge (copies allowed; any single spell is always allowed). Casts per round: ${U.fmt(G.Heroes.castsPerRound(hero))}; uses per copy per battle: ${U.fmt(G.Heroes.usesPerSpell(hero))}. Spells refresh after every battle.`));
      const eq = h('div', { class: 'row wrap', style: { margin: '6px 0' } }, h('b', null, 'Equipped:'));
      hero.equipped.forEach((id, i) => eq.append(h('span', { class: 'chip', tip: G.SPELLS[id].desc }, G.SPELLS[id].name, ` (${G.Heroes.spellCost(hero, id)})`, h('a', { style: { cursor: 'pointer', color: 'var(--danger)' }, onclick: () => { hero.equipped.splice(i, 1); draw(); } }, ' ✕'))));
      sp.append(eq);
      const book = h('div', { class: 'row wrap' }, h('b', null, 'Spellbook:'));
      for (const id of hero.spellbook) {
        const next = hero.equipped.concat([id]);
        book.append(h('button', { class: 'small', disabled: !G.Heroes.canEquip(hero, next), tip: `<b>${G.SPELLS[id].name}</b> (${G.SPELLS[id].kind}) cost ${G.Heroes.spellCost(hero, id)}<br>${G.SPELLS[id].desc}`, onclick: () => { hero.equipped.push(id); draw(); } }, '+ ' + G.SPELLS[id].name));
      }
      sp.append(book);
      box.append(sp);
      if (hero.artifacts.length) box.append(h('div', { class: 'panel' }, h('h3', null, 'Artifacts'), ...hero.artifacts.map(a => h('div', null, h('b', { class: 'goldt' }, G.ARTIFACTS[a].name), ' — ', G.ARTIFACTS[a].desc))));
      box.append(h('div', { class: 'row', style: { justifyContent: 'flex-end' } }, h('button', { class: 'primary', onclick: () => { G.UI.closeModal(); G.WorldUI.renderSide(); } }, 'Close')));
      G.UI.modal(box);
    };
    draw();
  },

  skillChoice(hid, then) {
    const h = G.UI.h, hero = G.World.hero(hid);
    const pair = hero.pendingSkillChoice || G.Heroes.maybeOfferSkill(hero, G.Game.rng);
    if (!pair) { then && then(); return; }
    G.UI.modal(h('div', { class: 'col', style: { minWidth: '520px' } }, h('h2', null, `${hero.name}: a new skill`), h('div', { class: 'muted' }, 'Two skills are ready. Choose one — the other loses experience equal to the cost of the one you take.'),
      h('div', { class: 'pop-choice' }, pair.map(k => {
        const S = G.SKILLS[k], next = G.Heroes.skill(hero, k);
        return h('div', { onclick: () => { G.Heroes.chooseSkill(hero, k); G.UI.closeModal(); G.WorldUI.renderSide(); then && then(); } }, h('b', { class: 'goldt' }, `${S.name} ${'I'.repeat(next + 1)}`), h('div', null, S.tiers[next]), h('div', { class: 'muted', style: { fontSize: '12px' } }, `cost ${G.Heroes.skillCost(hero, k)} XP`));
      }))), { locked: true });
  },
};
