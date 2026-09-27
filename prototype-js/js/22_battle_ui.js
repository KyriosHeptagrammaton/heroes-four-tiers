// ============================================================================
// Battle screen
// ============================================================================
G.BattleUI = {
  b: null, mode: null, sel: null, spell: null, cmd: null, onEnd: null, aiDelay: 380, busy: false, ended: false,
  ACTIONS: [
    { id: 'attack', key: 'A', label: 'Attack', tip: 'Hit a target. Must target an assaulter if you are under assault. Attacking something you are NOT engaged with costs your guard, protector status, advantages and engagements (ranged units keep them).' },
    { id: 'engage', key: 'E', label: 'Engage', tip: 'Put an enemy under assault: it must target you (or another assaulter). Lets you attack it even if guarded, and without losing status. Costs your guard/protector status and advantages.' },
    { id: 'guard', key: 'G', label: 'Guard', tip: 'Protect a friendly stack: it cannot be attacked or engaged except by units already engaged with it (and ranged/flying). Cannot guard while under assault. Costs advantages and engagements.' },
    { id: 'deny', key: 'D', label: 'Deny', tip: 'End one of the target\'s engagements, a guard, or one advantage; or (spending an advantage) one level of a spell on it. Costs guard/protector status, one advantage, and engagements with anyone else.' },
    { id: 'rally', key: 'R', label: 'Rally', tip: 'Remove morale damage equal to twice your morale from a friendly stack (or yourself).' },
    { id: 'seek', key: 'S', label: 'Seek Adv.', tip: '+1 advantage (+1 attack, +1 defence) until lost.' },
    { id: 'retaliate', key: 'T', label: 'Retaliate', tip: 'Hit back against every attack on you until your next turn.' },
    { id: 'fallback', key: 'F', label: 'Fall Back', tip: 'Drop all engagements, guards and advantages. Until your next turn only guard can target you. Not allowed for your last standing unit.' },
    { id: 'wait', key: 'W', label: 'Wait', tip: 'Tactics: act at the end of this round.' },
  ],

  start(battle, onEnd) {
    this.b = battle; this.onEnd = onEnd; this.mode = null; this.sel = null; this.spell = null; this.cmd = null; this.ended = false;
    G.UI.show('battle');
    this.build();
    this.render();
  },

  build() {
    const h = G.UI.h, el = G.UI.clear(document.getElementById('battle'));
    const T = G.TERRAIN[this.b.terrainId], TM = G.TIMES[this.b.timeId], W = G.WEATHER[this.b.weatherId];
    this.top = h('div', { class: 'b-top' });
    this.queueEl = h('div', { class: 'queue' });
    this.statusEl = h('div', { class: 'row wrap' });
    this.top.append(
      h('span', { class: 'chip gold', tip: `<b>${T.name}</b><br>${T.desc}` }, '⛰ ' + T.name),
      h('span', { class: 'chip', tip: `<b>${TM.name}</b> (chosen by attacker)<br>${TM.desc}` }, '◐ ' + TM.name),
      h('span', { class: 'chip', tip: `<b>${W.name}</b><br>${W.desc}` }, (this.b.weatherId === 'rain' ? '☂ ' : '☀ ') + W.name),
      this.statusEl, this.queueEl,
      G.Music.control(),
      h('button', { class: 'small', onclick: () => this.showRules(), tip: 'Quick rules reference' }, '? Rules'),
    );
    this.field = h('div', { class: 'b-field' });
    this.bg = h('canvas', { class: 'terrain-tex' });
    this.svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); this.svg.setAttribute('class', 'b-lines');
    this.rowEls = [h('div', { class: 'b-row' }), h('div', { class: 'b-row' })];
    this.midEl = h('div', { class: 'b-mid' });
    this.field.append(this.bg, this.rowEls[1], this.midEl, this.rowEls[0], this.svg);
    this.actEl = h('div', { class: 'b-actions' });
    this.infoEl = h('div', { class: 'b-info' });
    this.logEl = h('div', { class: 'b-log' });
    const side = h('div', { class: 'b-side' }, this.actEl, this.infoEl, this.logEl);
    el.append(this.top, h('div', { class: 'b-main' }, this.field, side));
    this.field.style.setProperty('--terrain', T.color);
    this.field.addEventListener('contextmenu', e => { e.preventDefault(); if (this.mode || this.spell || this.cmd) { this.mode = null; this.spell = null; this.cmd = null; this.render(); } });
    if (!this._keys) {
      this._keys = true;
      document.addEventListener('keydown', e => this.key(e));
      window.addEventListener('resize', () => { if (document.getElementById('battle').classList.contains('on')) { this.paintBg(); this.drawLines(); } });
    }
    setTimeout(() => this.paintBg(), 0);
  },

  paintBg() {
    const r = this.field.getBoundingClientRect();
    this.bg.width = r.width; this.bg.height = r.height;
    this.bg.style.width = r.width + 'px'; this.bg.style.height = r.height + 'px';
    this.bg.style.opacity = 0.55;
    G.Paint.terrain(this.bg.getContext('2d'), this.b.terrainId, 0, 0, r.width, r.height, 7, { unit: 34, density: 0.6 });
  },

  key(e) {
    if (!document.getElementById('battle').classList.contains('on') || document.getElementById('modal-bg').classList.contains('on')) return;
    if (e.key === 'Escape') { this.mode = null; this.spell = null; this.cmd = null; this.render(); return; }
    const a = this.ACTIONS.find(x => x.key.toLowerCase() === e.key.toLowerCase());
    if (a) this.pickAction(a.id);
  },

  humanTurn() {
    const b = this.b; if (b.over) return false;
    if (b.preCombat) return true;
    const e = b.current(); return e && !b.sides[e.side].ai;
  },

  pickAction(id) {
    const b = this.b, a = b.turnStack();
    if (!a || !this.humanTurn()) return;
    this.spell = null; this.cmd = null;
    if (['seek', 'retaliate', 'fallback', 'wait'].includes(id)) {
      const err = b.act(id);
      if (err) G.UI.toast(err);
      this.mode = null; this.render(); return;
    }
    this.mode = this.mode === id ? null : id;
    if (id === 'attack' && this.mode) {
      // auto-hint when nothing is attackable
      const any = b.enemiesOf(a).some(t => !b.checkAttack(a, t)) || (b.wall && !b.checkWallAttack(a));
      if (!any) G.UI.toast('No legal attack targets — hover enemies to see why.');
    }
    this.render();
  },

  clickStack(s) {
    const b = this.b;
    if (b.over) return;
    if (this.spell) return this.spellTarget(s.id);
    if (this.cmd) {
      const err = b.command(this.cmd.side, this.cmd.id, s.id);
      if (err) G.UI.toast(err); this.cmd = null; this.render(); return;
    }
    if (this.mode && this.humanTurn()) {
      const a = b.turnStack();
      if (this.mode === 'deny') {
        const err0 = b.checkDeny(a, s);
        if (err0) { G.UI.toast(err0); return; }
        const opts = b.denyOptions(a, s);
        if (opts.length === 1) return this.doAct('deny', s.id, 0);
        const h = G.UI.h;
        G.UI.modal(h('div', { class: 'col' }, h('h2', null, `Deny ${s.name}`), ...opts.map((o, i) => h('button', { onclick: () => { G.UI.closeModal(); this.doAct('deny', s.id, i); } }, o.label)),
          h('button', { onclick: () => G.UI.closeModal() }, 'Cancel')));
        return;
      }
      return this.doAct(this.mode, s.id);
    }
    this.sel = s.id; this.render();
  },

  doAct(action, target, opt) {
    const err = this.b.act(action, target, opt);
    if (err) { G.UI.toast(err); return; }
    this.mode = null; this.render();
  },

  // ---- spells ------------------------------------------------------------
  pickSpell(side, id) {
    if (!this.b.heroCanAct(side)) return;
    this.mode = null; this.cmd = null;
    this.spell = (this.spell && this.spell.id === id) ? null : { side, id, t1: null };
    this.render();
  },
  spellTarget(tid) {
    const sp = this.spell, S = G.SPELLS[sp.id];
    if (S.target === 'pair' && sp.t1 == null) { sp.t1 = tid; G.UI.toast('Now pick the stack that receives the morale damage'); this.render(); return; }
    const err = S.target === 'pair' ? this.b.cast(sp.side, sp.id, sp.t1, tid) : this.b.cast(sp.side, sp.id, tid);
    if (err) G.UI.toast(err);
    this.spell = null; this.render();
  },

  // ---- rendering ----------------------------------------------------------
  render() {
    const b = this.b, h = G.UI.h, U = G.util;
    // status chips
    G.UI.clear(this.statusEl);
    this.statusEl.append(h('span', { class: 'chip' }, 'Round ' + Math.max(1, b.round)));
    if (!b.over && b.round >= 1 && !b.damageThisRound) this.statusEl.append(h('span', { class: 'chip warn', tip: 'If neither side takes damage during a round, the battle ends.' }, 'No damage yet this round'));
    for (const sd of b.sides) this.statusEl.append(h('span', { class: 'chip', tip: `${sd.name} courage. Each point removes 1 extra morale damage when a creature deserts. Starts at hero courage − stacks − tier-4 creatures.` }, `${sd.idx ? '▲' : '▼'} Courage ${U.fmt(sd.courage)}`));
    // queue
    G.UI.clear(this.queueEl);
    b.queue.forEach((e, i) => {
      let lbl, sym;
      if (e.type === 'hero') { lbl = b.sides[e.side].hero.name; sym = h('span', { style: { fontSize: '18px', color: 'var(--gold2)' } }, '♛'); }
      else { const s = b.stack(e.id); if (!s) return; lbl = s.name; sym = G.UI.sym(s.def, 22); if (s.count <= 0) sym.style.opacity = .3; }
      const cls = 'qitem' + (i === b.qi && !b.preCombat ? ' cur' : '') + (i < b.qi ? ' done' : '');
      const iv = e.type === 'hero' ? G.Heroes.initStr(Math.round(e.init * 3)) : String(Math.max(0, Math.round(e.init)));
      this.queueEl.append(h('div', { class: cls, tip: `${U.esc(lbl)} — initiative ${iv} (${e.side ? 'defender' : 'attacker'})` }, sym, h('span', null, (e.side ? '▲' : '▼') + iv)));
    });
    // rows
    for (let side = 0; side < 2; side++) {
      const row = G.UI.clear(this.rowEls[side]);
      row.append(this.heroCard(side));
      const st = h('div', { class: 'stacks' });
      if (side === 1 && b.wall) st.append(this.wallCard());
      for (const s of b.stacks.filter(x => x.side === side)) st.append(this.stackCard(s));
      row.append(st);
    }
    // middle banner
    G.UI.clear(this.midEl);
    const cur = b.current();
    if (b.over) this.midEl.append(h('b', null, 'Battle over'));
    else if (b.preCombat) this.midEl.append(h('span', null, 'Pre-combat spells — then '), h('button', { class: 'primary small', onclick: () => { b.endPreCombat(); this.render(); } }, 'Begin battle'));
    else if (cur) {
      if (cur.type === 'hero') this.midEl.append(h('span', null, `${b.sides[cur.side].hero.name} (${b.sides[cur.side].name}) may cast or command.`));
      else { const s = b.stack(cur.id); this.midEl.append(h('span', null, `${s.name} (${b.sides[s.side].name}) to act`)); }
      if (this.mode) this.midEl.append(h('span', { class: 'goldt' }, ` — choose a target to ${this.mode}  (Esc to cancel)`));
      if (this.spell) this.midEl.append(h('span', { style: { color: 'var(--spell)' } }, ` — casting ${G.SPELLS[this.spell.id].name}: pick ${this.spell.t1 != null ? 'the receiving' : 'a'} target (Esc to cancel)`));
      if (this.cmd) this.midEl.append(h('span', { class: 'goldt' }, ` — ${this.cmd.label}: pick a friendly stack`));
    }
    this.renderActions();
    this.renderInfo();
    this.renderLog();
    requestAnimationFrame(() => this.drawLines());
    this.maybeAI();
    if (b.over && !this.ended) { this.ended = true; setTimeout(() => this.finish(), 450); }
  },

  heroCard(side) {
    const b = this.b, h = G.UI.h, sd = b.sides[side], U = G.util;
    const card = h('div', { class: 'hero-card' });
    if (!sd.hero) { card.append(h('div', { class: 'hn' }, sd.name), h('div', { class: 'muted' }, sd.neutral ? 'Neutral creatures' : 'No commander')); return card; }
    const hs = sd.hs, hero = sd.hero, canAct = b.heroCanAct(side) && !sd.ai;
    if (b.heroTurnNow(side) || (b.preCombat && hs.freeCast)) card.classList.add('cur');
    const init = G.Heroes.initStr(G.Heroes.stat(hero, 'initiative') - hs.pips);
    card.append(
      h('div', { class: 'row between' }, h('span', { class: 'hn', tip: this.heroTip(side) }, '♛ ' + hero.name), h('span', { class: 'muted' }, sd.name)),
      h('div', { class: 'muted', style: { fontSize: '11px' } }, `${G.CLASSES[hero.cls].name} · A${G.Heroes.stat(hero, 'attack')} D${G.Heroes.stat(hero, 'defence')} P${b.heroStat(side, 'power')} Init ${init}`),
    );
    if (hs.gone) { card.append(h('div', { class: 'bad' }, hs.gone === 'dead' ? 'Fallen in battle' : 'Fled the field')); return card; }
    card.append(h('div', { class: 'muted', style: { fontSize: '11px' } }, b.preCombat ? `Free pre-combat casts: ${hs.freeCast}` : `Casts left this round: ${hs.castsLeft === Infinity ? '∞' : (hs.active ? hs.castsLeft : '— (acts at its initiative)')}`));
    const left = b.spellUsesLeft(side);
    for (const id of Object.keys(left)) {
      const S = G.SPELLS[id];
      const btn = h('button', { class: 'spell-btn' + (this.spell && this.spell.id === id && this.spell.side === side ? ' sel' : ''), disabled: !canAct || left[id] <= 0, onclick: () => this.pickSpell(side, id), tip: `<b>${S.name}</b> (${S.kind}, cost ${S.cost})<br>${S.desc}${S.kind === 'damage' ? `<br>Right now: ${Math.round(S.amount * b.spellPowerMult(side, id))} (power +${Math.round((b.spellPowerMult(side, id) - 1) * 100)}%)` : ''}` },
        h('span', null, S.name), h('span', { class: 'muted' }, left[id] === Infinity ? '∞' : '×' + left[id]));
      card.append(btn);
    }
    if (!sd.ai && !b.preCombat) {
      const cmds = h('div', { class: 'cmd-row' });
      for (const c of b.commandOptions(side)) {
        cmds.append(h('button', { class: 'small' + (this.cmd && this.cmd.id === c.id ? ' sel' : ''), disabled: !canAct, tip: c.desc, onclick: () => {
          if (!c.need) { const err = b.command(side, c.id); if (err) G.UI.toast(err); this.render(); return; }
          this.mode = null; this.spell = null; this.cmd = { side, id: c.id, label: c.label }; this.render();
        } }, c.label));
      }
      card.append(cmds);
      const r2 = h('div', { class: 'cmd-row' });
      if (b.heroTurnNow(side)) r2.append(h('button', { class: 'small primary', onclick: () => { b.heroEnd(side); this.spell = null; this.cmd = null; this.render(); } }, 'End command ▸'));
      r2.append(h('button', { class: 'small danger', onclick: () => G.UI.confirm(`${sd.name}: retreat from the battle?`, () => { b.flee(side); this.render(); }) }, 'Retreat'));
      card.append(r2);
    }
    card.addEventListener('click', e => { if (this.spell && G.SPELLS[this.spell.id].target === 'stackOrHero' && !e.target.closest('button')) this.spellTarget('hero' + side); });
    return card;
  },

  heroTip(side) {
    const b = this.b, sd = b.sides[side], hero = sd.hero, U = G.util;
    let s = `<b>${U.esc(hero.name)}</b> — ${G.CLASSES[hero.cls].name}<div class="kv">`;
    for (const k of G.PRIMARY) s += `<b>${k}</b><span>${k === 'initiative' ? G.Heroes.initStr(G.Heroes.stat(hero, k)) : G.Heroes.stat(hero, k)}</span>`;
    s += '</div>';
    const sk = Object.keys(hero.skills).filter(k => hero.skills[k]);
    if (sk.length) s += '<div style="margin-top:4px">' + sk.map(k => `${G.SKILLS[k].name} ${'I'.repeat(hero.skills[k])}`).join(', ') + '</div>';
    if (hero.artifacts.length) s += '<div style="margin-top:4px;color:#d9b45a">' + hero.artifacts.map(a => G.ARTIFACTS[a].name).join(', ') + '</div>';
    if (sd.hs) s += `<div style="margin-top:4px" class="muted">Spare knowledge ${U.fmt(sd.hs.spareKnowledge)} · pips spent ${sd.hs.pips}</div>`;
    return s;
  },

  wallCard() {
    const b = this.b, h = G.UI.h;
    const a = b.turnStack();
    const card = h('div', { class: 'wall-card', tip: 'Town walls. While standing they protect defenders (every ' + G.CFG.wallPerStack + ' damage uncovers one more defender, from the bottom of the line).' },
      h('div', { style: { fontSize: '26px' } }, '▙▟▙'), h('b', null, 'Walls'), h('div', null, `${G.util.fmt(b.wall.hp)} / ${b.wall.max}`));
    if (b.wall.hp <= 0) card.style.opacity = .3;
    if (this.mode === 'attack' && a) { const err = b.checkWallAttack(a); card.style.borderColor = err ? '' : 'var(--good)'; card.onclick = () => err ? G.UI.toast(err) : this.doAct('attack', 'wall'); }
    return card;
  },

  stackCard(s) {
    const b = this.b, h = G.UI.h, U = G.util;
    const cur = b.turnStack();
    const cls = ['stack', 'side' + s.side];
    if (s.count <= 0) cls.push('dead');
    if (cur === s && !b.over) cls.push('active');
    if (this.sel === s.id) cls.push('sel');
    if (s.fallenBack) cls.push('fallen');
    let reason = null;
    if (s.count > 0 && this.mode && cur && this.humanTurn()) {
      reason = this.checkFor(this.mode, cur, s);
      cls.push(reason ? 'invalid' : 'valid');
    }
    if (s.count > 0 && this.spell) { const S = G.SPELLS[this.spell.id]; const err = b.checkCast(this.spell.side, this.spell.id, s.id, S.target === 'pair' && this.spell.t1 != null ? s.id : undefined); reason = (S.target === 'pair' && this.spell.t1 === s.id) ? 'first target' : (S.target === 'pair' && this.spell.t1 != null ? (this.spell.t1 === s.id ? 'same' : null) : err); cls.push(reason ? 'invalid' : 'valid'); }
    if (s.count > 0 && this.cmd) { cls.push(s.side === this.cmd.side ? 'valid' : 'invalid'); }
    const mv = s.moraleVal, hp = b.health(s);
    const mcap = Math.max(0, s.count * (mv - 1)), hcap = Math.max(0, s.count * (hp - 1));
    const mfrac = mcap > 0 ? Math.min(1, Math.max(0, s.mor) / mcap) : (s.mor > 0 ? 1 : 0);
    const hfrac = hcap > 0 ? Math.min(1, Math.max(0, s.phys) / hcap) : (s.phys > 0 ? 1 : 0);
    const slow = b.slowLevel(s);
    const badges = [];
    if (s.adv > 0) badges.push(h('span', { class: 'bdg adv', tip: `+${s.adv} attack and defence` }, '◆' + s.adv));
    const eng = s.engaging.map(id => b.stack(id)).filter(Boolean);
    if (eng.length) badges.push(h('span', { class: 'bdg eng', tip: 'Engaging: ' + eng.map(x => U.esc(x.name)).join(', ') }, '⚔→' + eng.length));
    const ass = b.assaulters(s);
    if (ass.length) badges.push(h('span', { class: 'bdg eng', tip: 'Under assault from: ' + ass.map(x => U.esc(x.name)).join(', ') + '<br>Must target one of them.' }, '⚠ assault'));
    if (b.isGuarded(s)) badges.push(h('span', { class: 'bdg grd', tip: 'Guarded by ' + U.esc(b.protectorOf(s).name) }, '🛡'));
    if (s.guarding != null && b.stack(s.guarding)) badges.push(h('span', { class: 'bdg grd', tip: 'Guarding ' + U.esc(b.stack(s.guarding).name) }, '⛨→'));
    if (s.retaliating || s.def.sp.alwaysRetaliate) badges.push(h('span', { class: 'bdg ret', tip: 'Will retaliate' }, '↺'));
    if (s.fallenBack) badges.push(h('span', { class: 'bdg', tip: 'Fallen back: only guard can target it until its next turn' }, '⤺'));
    if (slow && s.count > 0) badges.push(h('span', { class: 'bdg slow', tip: `Slow ${slow}: cannot attack in rounds 1-${slow} unless engaged with the target` }, '⌛' + slow));
    if (b.isRanged(s)) badges.push(h('span', { class: 'bdg', tip: G.ABILITY_TEXT.ranged + (b.halfRangedOnly(s) ? ' (half damage, from the Watchfort)' : '') }, '➶'));
    if (b.isCavalry(s)) badges.push(h('span', { class: 'bdg', tip: G.ABILITY_TEXT.cavalry }, '»'));
    if (b.wallProtected(s)) badges.push(h('span', { class: 'bdg grd', tip: 'Protected by the walls' }, '▙'));
    for (const id in s.spells) badges.push(h('span', { class: 'bdg spell', tip: G.SPELLS[id].desc }, G.SPELLS[id].name + (s.spells[id] > 1 ? ' ' + s.spells[id] : '')));
    if (s.phys < 0) badges.push(h('span', { class: 'bdg adv', tip: 'Negative physical damage (buffer)' }, '⛊' + U.fmt(-s.phys)));
    let tip = G.UI.unitTip(s.def, this.liveTip(s));
    if (reason && reason !== 'first target') tip = `<b class="bad">✗ ${U.esc(reason)}</b><br>` + tip;
    else if (this.mode === 'attack' && cur && s.count > 0 && !reason) tip = this.previewTip(cur, s) + tip;
    const card = h('div', { class: cls.join(' '), tip, onclick: () => s.count > 0 && this.clickStack(s), 'data-sid': s.id },
      s.hero && s.count > 0 ? h('span', { class: 'crown', tip: 'Hero unit: +1 attack, defence, damage, morale' }, '♛') : null,
      h('div', { class: 'top' }, G.UI.sym(s.def, 38), h('div', { class: 'grow', style: { minWidth: 0 } }, h('div', { class: 'cnt' }, s.count), h('div', { class: 'nm' }, s.name))),
      h('div', { class: 'stats' }, `A${U.fmt(b.attack(s))} D${U.fmt(b.defence(s))} I${b.initiative(s)}`),
      h('div', { class: 'bar m' }, h('i', { style: { width: (mfrac * 100) + '%' } })),
      h('div', { class: 'barlbl' }, h('span', null, 'M ' + U.fmt(mv)), h('span', null, U.fmt(Math.max(0, s.mor)) + '/' + U.fmt(mcap))),
      h('div', { class: 'bar h' + (s.phys < 0 ? ' neg' : '') }, h('i', { style: { width: (s.phys < 0 ? 100 : hfrac * 100) + '%' } })),
      h('div', { class: 'barlbl' }, h('span', null, 'H ' + U.fmt(hp)), h('span', null, U.fmt(Math.max(0, s.phys)) + '/' + U.fmt(hcap))),
      h('div', { class: 'badges' }, badges),
    );
    card.addEventListener('dblclick', () => G.UI.prompt('Rename stack', s.name, v => { if (v) { s.name = v; this.render(); } }));
    // right-click: cancel any targeting, otherwise show this stack's details (HoMM style)
    card.addEventListener('contextmenu', e => { e.preventDefault(); e.stopPropagation(); if (this.mode || this.spell || this.cmd) { this.mode = null; this.spell = null; this.cmd = null; } else this.sel = s.id; this.render(); });
    return card;
  },

  checkFor(mode, a, t) {
    const b = this.b;
    switch (mode) {
      case 'attack': return b.checkAttack(a, t);
      case 'engage': return b.checkEngage(a, t);
      case 'guard': return b.checkGuard(a, t);
      case 'deny': return b.checkDeny(a, t);
      case 'rally': return b.checkRally(a, t);
    }
    return 'n/a';
  },

  previewTip(a, t) {
    const b = this.b, U = G.util;
    const n = b.hitNumbers(a, t, { average: true });
    const e = b.expectedHit(a, t);
    const ret = (t.retaliating || t.def.sp.alwaysRetaliate) && !(b.isRanged(a) && !b.isRanged(t));
    return `<div style="border-bottom:1px solid #444;padding-bottom:4px;margin-bottom:4px"><b class="good">Attack preview (average roll)</b><br>` +
      `A ${U.fmt(n.A)} vs D ${U.fmt(n.D)} → ${n.mult >= 1 ? '+' : ''}${Math.round((n.mult - 1) * 100)}% damage<br>${U.fmt(n.mor)} morale + ${U.fmt(n.phys)} health damage<br>≈ ${e.removed} creature(s) removed` +
      (ret ? `<br><span class="bad">Target will retaliate</span>` : '') + '</div>';
  },

  liveTip(s) {
    const b = this.b, U = G.util;
    const tri = b.dmgTriple(s);
    return `<div style="margin-top:6px;border-top:1px solid #444;padding-top:4px"><b>In this battle</b><div class="kv">` +
      `<b>Creatures</b><span>${s.count} / ${s.start} (${s.dead} dead, ${s.deserters} deserted${s.gained ? ', ' + s.gained + ' gained' : ''})</span>` +
      `<b>Attack</b><span>${U.fmt(b.attack(s))}</span><b>Defence</b><span>${U.fmt(b.defence(s))}</span>` +
      `<b>Morale</b><span>${U.fmt(s.moraleVal)} each · dmg ${U.fmt(s.mor)}</span><b>Health</b><span>${U.fmt(b.health(s))} each · dmg ${U.fmt(s.phys)}</span>` +
      `<b>Damage</b><span>${tri.map(U.fmt).join(' / ')} × ${U.fmt(b.effCount(s))} (d${Math.max(3, Math.round(b.effCount(s)))})</span>` +
      `<b>Initiative</b><span>${b.initiative(s)}</span></div></div>`;
  },

  renderActions() {
    const b = this.b, h = G.UI.h, el = G.UI.clear(this.actEl);
    const a = b.turnStack();
    if (b.over) { el.append(h('div', { class: 'hint' }, 'The battle is over.')); return; }
    if (b.preCombat) { el.append(h('div', { class: 'hint' }, 'Pre-combat: cast your Herald\'s Scroll spell, then Begin battle.')); return; }
    const cur = b.current();
    if (!this.humanTurn()) { el.append(h('div', { class: 'hint' }, `${b.sides[cur.side].name} (AI) is thinking…`)); return; }
    if (cur.type === 'hero') {
      el.append(h('div', { class: 'hint' }, `Your commander's turn: cast a spell or use a command (left card), then "End command". From now until the round ends, the commander may also act at the start of any of your stacks' turns.`));
      return;
    }
    el.append(h('div', { class: 'row between', style: { marginBottom: '6px' } }, h('b', { class: 'goldt' }, a.name), h('span', { class: 'muted' }, b.sides[a.side].name)));
    const ass = b.assaulters(a);
    if (ass.length) el.append(h('div', { class: 'hint' }, 'Under assault — attacks, engages and denies must target: ' + ass.map(x => x.name).join(', ')));
    const grid = h('div', { class: 'grid' });
    for (const A of this.ACTIONS) {
      if (A.id === 'wait' && !b.canWait(a)) continue;
      let disabled = false;
      if (A.id === 'fallback') disabled = !!b.checkFallback(a);
      grid.append(h('button', { class: this.mode === A.id ? 'sel' : '', disabled, onclick: () => this.pickAction(A.id), tip: `<b>${A.label}</b> <kbd>${A.key}</kbd><br>${A.tip}` }, A.label));
    }
    el.append(grid);
    if (b.heroCanAct(a.side) && b.sides[a.side].hero) el.append(h('div', { class: 'muted', style: { marginTop: '6px', fontSize: '12px' } }, 'Your commander may cast before this stack acts.'));
  },

  renderInfo() {
    const b = this.b, h = G.UI.h, el = G.UI.clear(this.infoEl);
    const s = (this.sel && b.stack(this.sel)) || b.turnStack();
    if (!s) { el.append(h('div', { class: 'muted' }, 'Click a stack for details. Hover anything for help.')); return; }
    const wrap = h('div', { html: G.UI.unitTip(s.def, this.liveTip(s)) });
    el.append(h('div', { class: 'row between' }, h('h3', null, 'Details'), h('button', { class: 'small', onclick: () => G.UI.prompt('Rename stack', s.name, v => { if (v) { s.name = v; this.render(); } }) }, 'Rename')), wrap);
  },

  renderLog() {
    const el = this.logEl, b = this.b;
    const n = el.childElementCount;
    if (n > b.log.length) G.UI.clear(el);
    for (let i = el.childElementCount; i < b.log.length; i++) {
      const L = b.log[i]; const d = document.createElement('div'); d.className = L.cls; d.textContent = L.t; el.appendChild(d);
    }
    el.scrollTop = el.scrollHeight;
  },

  drawLines() {
    const b = this.b, svg = this.svg;
    while (svg.firstChild) svg.removeChild(svg.firstChild);
    const fr = this.field.getBoundingClientRect();
    const box = id => { const e = this.field.querySelector(`[data-sid="${id}"]`); if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.left - fr.left, y: r.top - fr.top, w: r.width, h: r.height }; };
    const NS = 'http://www.w3.org/2000/svg';
    const defs = document.createElementNS(NS, 'defs');
    defs.innerHTML = `<marker id="arE" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#e0604a"/></marker>`;
    svg.appendChild(defs);
    for (const s of b.stacks) {
      if (s.count <= 0) continue;
      const A = box(s.id); if (!A) continue;
      for (const id of s.engaging) {
        const t = b.stack(id); const B = box(id); if (!B || !t || t.count <= 0) continue;
        const x1 = A.x + A.w / 2, y1 = s.side === 0 ? A.y : A.y + A.h, x2 = B.x + B.w / 2, y2 = t.side === 0 ? B.y : B.y + B.h;
        const p = document.createElementNS(NS, 'path');
        const my = (y1 + y2) / 2;
        p.setAttribute('d', `M${x1},${y1} C${x1},${my} ${x2},${my} ${x2},${y2}`);
        p.setAttribute('stroke', '#e0604a'); p.setAttribute('stroke-width', '3'); p.setAttribute('fill', 'none'); p.setAttribute('marker-end', 'url(#arE)'); p.setAttribute('opacity', '.9');
        svg.appendChild(p);
      }
      if (s.guarding != null) {
        const t = b.stack(s.guarding); const B = box(s.guarding); if (!B || !t || t.count <= 0) continue;
        const x1 = A.x + A.w / 2, x2 = B.x + B.w / 2;
        const y = s.side === 0 ? A.y + A.h + 4 : A.y - 4, dy = s.side === 0 ? 22 : -22;
        const p = document.createElementNS(NS, 'path');
        p.setAttribute('d', `M${x1},${y} C${x1},${y + dy} ${x2},${y + dy} ${x2},${y}`);
        p.setAttribute('stroke', '#5aa0e0'); p.setAttribute('stroke-width', '3'); p.setAttribute('stroke-dasharray', '6 4'); p.setAttribute('fill', 'none');
        svg.appendChild(p);
        const tx = document.createElementNS(NS, 'text'); tx.setAttribute('x', (x1 + x2) / 2); tx.setAttribute('y', y + dy * 0.8 + 5); tx.setAttribute('text-anchor', 'middle'); tx.setAttribute('font-size', '14'); tx.setAttribute('fill', '#9cc8f0'); tx.textContent = '🛡';
        svg.appendChild(tx);
      }
    }
  },

  // ---- AI & end -----------------------------------------------------------
  maybeAI() {
    const b = this.b;
    if (b.over || this.busy) return;
    const e = b.current();
    const aiNow = b.preCombat ? b.sides.every(sd => sd.ai || !(sd.hs && sd.hs.freeCast)) : (e && b.sides[e.side].ai);
    if (!aiNow) return;
    this.busy = true;
    setTimeout(() => { this.busy = false; if (this.b !== b) return; G.CombatAI.step(b); this.render(); }, this.aiDelay);
  },

  finish() {
    const b = this.b, h = G.UI.h, U = G.util;
    const o = b.over;
    const title = o.winner === null ? (o.reason === 'stalemate' ? 'Stalemate' : 'Draw') : `${b.sides[o.winner].name} win`;
    const reason = { destroyed: 'An army was destroyed or routed.', fled: `${b.sides[o.fled != null ? o.fled : 0].name} retreated.`, stalemate: 'No damage was dealt in a whole round.', exhaustion: 'Round limit reached.' }[o.reason] || '';
    const tbl = h('table', { class: 'tbl' }, h('tr', null, h('th', null, 'Stack'), h('th', null, 'Start'), h('th', null, 'Left'), h('th', null, 'Dead'), h('th', null, 'Deserted')));
    for (const s of b.stacks) tbl.append(h('tr', null, h('td', null, (s.side ? '▲ ' : '▼ ') + s.name), h('td', null, s.start), h('td', null, Math.max(0, s.count)), h('td', null, s.dead), h('td', null, s.deserters)));
    G.UI.modal(h('div', { class: 'col', style: { minWidth: '420px' } }, h('h2', null, title), h('div', { class: 'muted' }, reason + ` (${b.round} rounds)`), tbl,
      h('div', { class: 'row', style: { justifyContent: 'flex-end' } }, h('button', { class: 'primary', onclick: () => { G.UI.closeModal(); this.onEnd && this.onEnd(b); } }, 'Continue'))), { locked: true });
  },

  showRules() {
    const h = G.UI.h;
    G.UI.modal(h('div', { html: G.RULES_HTML, style: { maxWidth: '680px' } }));
  },
};

G.RULES_HTML = `<h2>Combat quick reference</h2>
<p><b>Turn order.</b> Every stack acts once per round by initiative (ties: attacker first). Your commander acts at its initiative (3 points = 1, shown as 1, 1+, 1++…) and from then until the round ends may cast at the start of any of your stacks' turns.</p>
<p><b>Damage.</b> Roll 1dX (X = creatures, min 3): 1 = minimum, X = maximum, otherwise middle damage. × creatures. Each attack point above the target's defence +10% (max +300%); each defence point above attack −5% (max −75%). 75% goes to morale, 25% to health.</p>
<p><b>Casualties.</b> When damage exceeds creatures × (value − 1), one creature is removed and damage drops by twice its value (+courage for morale). Morale casualties desert, health casualties die. Deserters also remove (health − 1) physical damage. Every turn a stack recovers morale damage equal to its morale.</p>
<p><b>Numbers.</b> Each creature adds +5% base attack/defence and +10% morale. Stacks at ≤ ⅓ of their start (or ≤ 2) become <b>heroes</b>: +1 attack, defence, damage, morale; they rally; +1 courage (−1 when a hero stack is lost).</p>
<p><b>Courage</b> = hero courage − 1 per stack − 1 per tier-4 creature. Each point removes 1 extra morale damage when a creature deserts.</p>
<p><b>Mouse.</b> Left-click an action then a target. Right-click cancels targeting, or shows a stack's details. Double-click a stack to rename it.</p>
<p><b>Actions.</b> Attack · Engage · Guard · Deny · Rally · Seek Advantage · Retaliate · Fall Back (· Wait with Tactics). Hover each button for exact rules. Red arrows = engagements, blue dashed = guards.</p>
<p><b>Slow</b> units can't attack in the first round(s) unless engaged with the target. <b>Ranged</b> units can't be attacked/engaged in round 1 except by cavalry. <b>Cavalry</b> can only be engaged by cavalry.</p>
<p><b>End.</b> An army is destroyed, someone retreats, or a full round passes with no damage.</p>`;
