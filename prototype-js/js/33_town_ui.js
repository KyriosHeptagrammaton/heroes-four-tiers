// ============================================================================
// Town screen, recruiting (incl. remote recruiting posts) and upgrades.
// ============================================================================
G.TownUI = {
  tid: null, hid: null,
  open(tid, hid) { this.tid = tid; this.hid = hid || null; G.UI.show('town'); this.render(); },
  close() { G.WorldUI.enter(); },

  render() {
    const h = G.UI.h, S = G.Game.state, t = S.towns[this.tid], P = S.players[S.cur], U = G.util;
    const hero = this.hid && G.World.hero(this.hid);
    const inTown = hero && hero.pos.c === t.c && hero.pos.x === t.x && hero.pos.y === t.y;
    const el = G.UI.clear(document.getElementById('town'));
    el.append(h('div', { class: 'bar-top' },
      h('button', { onclick: () => this.close() }, '◂ Map'),
      h('h2', { style: { margin: 0, cursor: 'pointer' }, tip: 'Click to rename', onclick: () => G.UI.prompt('Rename town', t.name, v => { if (v) { t.name = v; this.render(); } }) }, (t.capital ? '♛ ' : '♜ ') + t.name),
      h('span', { class: 'chip', style: { color: G.FACTIONS[t.faction].color } }, G.FACTIONS[t.faction].name),
      t.capital ? h('span', { class: 'chip warn', tip: 'If this town falls, you lose the game.' }, 'Capital') : null,
      h('span', { class: 'grow' }),
      h('span', null, '● ', h('b', { class: 'goldt' }, U.fmt(P.gold))),
      ...[1, 2, 3, 4].map(k => h('span', { class: 'muted', tip: `Tier ${k} upgrade essence` }, `⬡${k} ${P.essence[k]}`)),
    ));
    const body = h('div', { class: 'body' });
    el.append(body);
    // visiting hero line
    body.append(h('div', { class: 'panel row wrap', style: { marginBottom: '10px' } },
      inTown ? h('span', null, 'Visiting hero: ', h('b', { class: 'goldt' }, hero.name)) : h('span', { class: 'muted' }, 'No hero in town — recruits go to the garrison.'),
      h('span', { class: 'grow' }),
      h('span', { class: 'muted' }, 'Garrison: '), G.WorldUI.armyText ? h('span', { html: t.garrison.length ? t.garrison.map(g => `${g.count} ${U.esc(g.name || G.Units.resolve(g.key).name)}`).join(', ') : '<span class="muted">empty</span>' }) : null,
      h('button', { class: 'small', onclick: () => G.ArmyUI.armyScreen(inTown ? hero.id : null, t.id, () => this.render()) }, 'Manage armies'),
      inTown ? h('button', { class: 'small', onclick: () => this.upgradeModal(hero.id, t.id) }, 'Upgrade creatures') : h('button', { class: 'small', onclick: () => this.upgradeModal(null, t.id) }, 'Upgrade garrison')));
    // recruit
    const rec = h('div', { class: 'panel', style: { marginBottom: '10px' } }, h('h3', null, 'Recruit'),
      h('div', { class: 'muted', style: { fontSize: '12px', marginBottom: '6px' } }, 'The weekly muster is sold at the base price. You may keep buying beyond it: the next week-sized batch costs ×2, then ×3, and so on. Prices reset each week.'));
    const grid = h('div', { class: 'cards' });
    for (let tier = 1; tier <= 4; tier++) {
      const bk = tier === 1 ? 'dwell1' : 'dwell' + tier;
      const d = G.Units.resolve(G.Units.key(t.faction, tier, 0, ''));
      const card = h('div', { class: 'bcard' + (t.built[bk] ? ' built' : '') });
      card.append(h('div', { class: 'row' }, G.UI.sym(d, 32), h('div', null, h('div', { class: 't', tip: G.UI.unitTip(d) }, d.name), h('div', { class: 'muted' }, `Tier ${tier} · base ${G.CFG.unitPrice[tier]} gold · growth ${G.World.growth(t, tier)}/week`))));
      if (!t.built[bk]) { card.append(h('div', { class: 'muted' }, 'Build the dwelling first.')); grid.append(card); continue; }
      const inp = h('input', { type: 'number', min: 1, value: Math.max(1, t.pool[tier] || 1) });
      const price = h('span', { class: 'muted' });
      const upd = () => { const n = Math.max(1, +inp.value || 1); price.textContent = `${G.World.priceFor(t, tier, n)} gold`; };
      inp.oninput = upd; upd();
      const buy = dest => {
        const n = Math.max(1, +inp.value || 1), cost = G.World.priceFor(t, tier, n);
        if (P.gold < cost) return G.UI.toast('Not enough gold');
        const army = dest === 'hero' ? hero.army : t.garrison;
        if (!G.Army.canAdd(army, d.key)) return G.UI.toast('No free stack slot');
        P.gold -= cost; G.World.buy(t, tier, n); G.Army.add(army, d.key, n);
        G.UI.toast(`Recruited ${n} ${d.name}`); this.render(); G.WorldUI.renderSide();
      };
      card.append(h('div', { class: 'row', style: { marginTop: '6px' } }, h('span', null, `At base price: ${t.pool[tier]}`)),
        h('div', { class: 'row wrap', style: { marginTop: '4px' } }, inp, price,
          inTown ? h('button', { class: 'small primary', onclick: () => buy('hero') }, '→ Hero') : null,
          h('button', { class: 'small', onclick: () => buy('garrison') }, '→ Garrison')));
      grid.append(card);
    }
    rec.append(grid); body.append(rec);
    // buildings
    const bp = h('div', { class: 'panel', style: { marginBottom: '10px' } }, h('h3', null, 'Build ' + (t.builtToday ? '(already built today)' : '(one per day)')));
    const bgrid = h('div', { class: 'cards' });
    for (const k in G.BUILDINGS) {
      const B = G.BUILDINGS[k];
      if (k === 'up1_4' && !t.built.dwell4 && !t.built.dwell3) continue;
      const built = !!t.built[k], reqOk = B.req.every(r => t.built[r]);
      const path = k.startsWith('up2_') ? G.SECOND_UPGRADE[t.faction][+k.slice(4)] : null;
      bgrid.append(h('div', { class: 'bcard' + (built ? ' built' : '') },
        h('div', { class: 't' }, B.name + (path != null ? (path === 'r' ? ' (ranged II)' : ' (melee II)') : '')),
        h('div', { class: 'muted', style: { fontSize: '12px' } }, B.desc),
        built ? h('div', { class: 'good' }, '✓ Built') : h('div', { class: 'row', style: { marginTop: '6px' } },
          h('button', { class: 'small', disabled: t.builtToday || !reqOk || P.gold < B.cost, onclick: () => { P.gold -= B.cost; t.built[k] = true; t.builtToday = true; this.render(); G.WorldUI.renderSide(); } }, `Build · ${B.cost}`),
          !reqOk ? h('span', { class: 'muted' }, 'needs ' + B.req.map(r => G.BUILDINGS[r] ? G.BUILDINGS[r].name : r).join(', ')) : null)));
    }
    bp.append(bgrid); body.append(bp);
    // treasury / tavern / wagons
    const misc = h('div', { class: 'cards' });
    misc.append(h('div', { class: 'bcard' }, h('div', { class: 't' }, 'Treasury'), h('div', { class: 'muted', style: { fontSize: '12px' } }, '"A wise king invests in his town: 3 gold now for 1 gold forever." Invest 300 gold for +100 gold every week.'),
      h('div', { class: 'row', style: { marginTop: '6px' } }, h('span', null, `Weekly return: ${P.invest}`), h('button', { class: 'small', disabled: P.gold < 300, onclick: () => { P.gold -= 300; P.invest += 100; this.render(); G.WorldUI.renderSide(); } }, 'Invest 300'))));
    misc.append(h('div', { class: 'bcard' }, h('div', { class: 't' }, 'Tavern'), h('div', { class: 'muted', style: { fontSize: '12px' } }, `Hire a new hero (${G.CFG.heroCost} gold). They arrive with a few recruits and a supply train.`),
      h('div', { class: 'row wrap', style: { marginTop: '6px' } }, ...Object.keys(G.CLASSES).map(c => h('button', { class: 'small', disabled: P.gold < G.CFG.heroCost || !!G.World.heroAt(t.c, t.x, t.y), tip: G.CLASSES[c].desc + (G.World.heroAt(t.c, t.x, t.y) ? '<br><b>A hero is already standing in town.</b>' : ''), onclick: () => {
        P.gold -= G.CFG.heroCost; const nh = G.Game.spawnHero(S.cur, c, t, false); nh.faction = t.faction; nh.army = [{ key: G.Units.key(t.faction, 1, 0, ''), count: 6, splits: 1, name: '' }];
        G.World.computeVisible(S.cur); G.WorldUI.selHero = nh.id; this.hid = nh.id; G.UI.toast(`${nh.name} joins you`); this.render(); G.WorldUI.renderSide();
      } }, G.CLASSES[c].name)))));
    if (inTown && (!hero.train || hero.train.state === 'none')) misc.append(h('div', { class: 'bcard' }, h('div', { class: 't' }, 'Wagon works'), h('div', { class: 'muted', style: { fontSize: '12px' } }, 'Your hero has no supply train.'),
      h('button', { class: 'small', disabled: P.gold < G.CFG.trainCost, onclick: () => { P.gold -= G.CFG.trainCost; hero.train = { state: 'with', at: null, wounded: [] }; this.render(); G.WorldUI.renderSide(); } }, `Buy supply train · ${G.CFG.trainCost}`)));
    body.append(misc);
  },

  // ---- upgrades (town buildings, or an arcane font when font=true) ---------------------
  upgradeModal(hid, tid, font) {
    const h = G.UI.h, S = G.Game.state, P = S.players[S.cur];
    const hero = hid && G.World.hero(hid), t = tid && S.towns[tid];
    const armies = [];
    if (hero) armies.push({ label: hero.name, groups: hero.army });
    if (t && !font) armies.push({ label: t.name + ' garrison', groups: t.garrison });
    // Fieldcraft I: upgrade away from town using buildings of any own town of that faction
    let ctxTown = t;
    const draw = () => {
      const box = h('div', { class: 'col', style: { minWidth: '560px' } }, h('h2', null, font ? '◎ Arcane font' : 'Upgrade creatures'),
        h('div', { class: 'muted' }, `Cost per creature: 1 essence of its tier + a gold fee. You have ${P.gold} gold and essence ${[1, 2, 3, 4].map(k => 'T' + k + ':' + P.essence[k]).join(' ')}.`));
      let any = false;
      for (const A of armies) {
        box.append(h('h3', { style: { marginTop: '8px' } }, A.label));
        A.groups.forEach(g => {
          const opts = G.World.upgradeOptions(g.key, { town: ctxTown || this.anyTownWith(g.key), font, hero });
          if (!opts.length) return;
          any = true;
          const d = G.Units.resolve(g.key);
          const row = h('div', { class: 'row wrap', style: { margin: '4px 0' } }, G.UI.sym(d, 24), h('b', null, `${g.count} ${d.name}`), h('span', null, '→'));
          for (const k of opts) {
            const nd = G.Units.resolve(k), cost = G.World.upgradeCost(g.key, g.count);
            const can = P.gold >= cost.gold && P.essence[cost.tier] >= cost.essence;
            row.append(h('button', { class: 'small', disabled: !can, tip: G.UI.unitTip(nd, `<div style="margin-top:4px">Cost for all ${g.count}: ${cost.gold} gold + ${cost.essence} tier-${cost.tier} essence</div>`), onclick: () => {
              P.gold -= cost.gold; P.essence[cost.tier] -= cost.essence;
              const ex = A.groups.find(x => x.key === k && x !== g);
              if (ex) { ex.count += g.count; A.groups.splice(A.groups.indexOf(g), 1); G.Army.normalize(ex); } else g.key = k;
              if (hero) G.Heroes.addSkillXp(hero, 'craft', 1);
              draw(); G.WorldUI.renderSide();
            } }, G.UI.sym(nd, 18), ' ' + nd.name + (nd.placeholder ? ' ⚑' : '')));
          }
          box.append(row);
        });
      }
      if (!any) box.append(h('div', { class: 'muted' }, font ? 'Only un-upgraded creatures can become Magi.' : 'Nothing can be upgraded here — build drill yards / war colleges / the arcane sanctum first.'));
      box.append(h('div', { class: 'row', style: { justifyContent: 'flex-end' } }, h('button', { class: 'primary', onclick: () => { G.UI.closeModal(); if (document.getElementById('town').classList.contains('on')) this.render(); } }, 'Done')));
      G.UI.modal(box);
    };
    draw();
  },
  anyTownWith(key) {
    // Fieldcraft I lets heroes upgrade away from town using their towns' buildings
    const S = G.Game.state, hero = G.World.hero(G.WorldUI.selHero);
    if (!hero || G.Heroes.skill(hero, 'fieldcraft') < 1) return null;
    const f = G.Units.parse(key.split('@')[0]).faction;
    return G.World.townsOf(S.cur).find(t => t.faction === f) || null;
  },

  // ---- recruiting post: buy from own towns while abroad (+25%) ------------------------------
  remoteRecruit(hid) {
    const h = G.UI.h, S = G.Game.state, P = S.players[S.cur], hero = G.World.hero(hid);
    const draw = () => {
      const box = h('div', { class: 'col', style: { minWidth: '520px' } }, h('h2', null, '⚑ Recruiting post'), h('div', { class: 'muted' }, 'Buy creatures from your towns\' musters at +25%. They march out to meet you.'));
      for (const t of G.World.townsOf(S.cur)) {
        box.append(h('h3', null, t.name));
        for (let tier = 1; tier <= 4; tier++) {
          if (!t.built[tier === 1 ? 'dwell1' : 'dwell' + tier]) continue;
          const d = G.Units.resolve(G.Units.key(t.faction, tier, 0, ''));
          const one = G.World.priceFor(t, tier, 1, 1.25);
          box.append(h('div', { class: 'row' }, G.UI.sym(d, 22), h('span', { class: 'grow' }, `${d.name} (${t.pool[tier]} at base)`),
            ...[1, 5].map(n => h('button', { class: 'small', disabled: P.gold < G.World.priceFor(t, tier, n, 1.25) || !G.Army.canAdd(hero.army, d.key), onclick: () => { const c = G.World.priceFor(t, tier, n, 1.25); P.gold -= c; G.World.buy(t, tier, n); G.Army.add(hero.army, d.key, n); draw(); G.WorldUI.renderSide(); } }, `+${n} · ${G.World.priceFor(t, tier, n, 1.25)}`))));
        }
      }
      box.append(h('button', { class: 'primary', onclick: () => G.UI.closeModal() }, 'Done'));
      G.UI.modal(box);
    };
    draw();
  },
};
