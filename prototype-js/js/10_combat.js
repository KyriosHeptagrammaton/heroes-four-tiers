// ============================================================================
// COMBAT ENGINE (pure logic, no DOM)
// Abstract battlefield: two rows of stacks. Positioning is carried entirely by
// the actions: attack, engage, guard, deny, fall back, seek advantage,
// retaliate, rally (+ wait with Tactics).
// Side 0 = attacker, side 1 = defender.
// ============================================================================
(function () {
  const C = G.CFG, U = G.util;

  class Battle {
    constructor(o) {
      this.rng = G.RNG(o.seed || (Math.random() * 1e9) | 0);
      this.terrainId = o.terrain || 'field';
      this.timeId = o.time || 'dawn';
      this.weatherId = o.weather || 'clear';
      this.fx = Object.assign({}, G.TERRAIN[this.terrainId].fx);
      // merge time + weather effects (numbers add)
      for (const src of [G.TIMES[this.timeId].fx, G.WEATHER[this.weatherId].fx]) for (const k in src) this.fx[k] = (this.fx[k] || 0) + src[k];
      this.round = 0;
      this.log = [];
      this.over = null;
      this.stacks = [];
      this.queue = []; this.qi = 0;
      this.damageThisRound = false;
      this.attackedThisRound = [false, false];
      this.attackedLastRound = [true, true];
      this.nextId = 1;
      this.sides = [0, 1].map(i => {
        const s = o.sides[i];
        return {
          idx: i, name: s.name || (i === 0 ? 'Attacker' : 'Defender'), hero: s.hero || null, ai: !!s.ai, neutral: !!s.neutral, trainless: !!s.trainless,
          faction: s.faction || (s.stacks[0] && G.Units.parse(s.stacks[0].key.split('@')[0]).faction) || 'alpha',
          courage: 0, hs: null,
          st: { killTier: 0, lostTier: 0, desertedByEnemy: 0, spells: 0, notFirst: 0, knowledgeXP: 0, startCourageLE0: false, killsByTier: { 1: 0, 2: 0, 3: 0, 4: 0 } },
        };
      });
      for (let i = 0; i < 2; i++) for (const s of o.sides[i].stacks) this.addStack(i, s.key, s.count, s.name, s.uid);
      // terrain stack gifts
      if (this.fx.defMilitia) this.addStack(1, G.Units.key(this.sides[1].faction, 1, 0, ''), C.villageMilitia, 'Militia');
      if (this.fx.bothMercs) for (let i = 0; i < 2; i++) this.addStack(i, G.Units.key(this.sides[i].faction, 1, 0, ''), C.crossroadsMercs, 'Mercenaries');
      if (this.fx.walls) { const n = this.stacksOf(1).length; this.wall = { hp: n * C.wallPerStack, max: n * C.wallPerStack }; }
      // defender chose to ignore the attack: 1-3 random units get slow
      if (o.ignoredAttack) {
        const own = this.rng.shuffle(this.stacksOf(1).slice());
        const n = this.rng.int(1, 3);
        own.slice(0, n).forEach(s => { s.extraSlow += 1; this.say(`${s.name} was caught unprepared (+1 slow).`); });
      }
      this.setupSides();
      this.preCombat = [0, 1].some(i => this.sides[i].hs && this.sides[i].hs.freeCast > 0 && !this.sides[i].ai);
      if (!this.preCombat) this.startRound();
      else this.say('Pre-combat: a Herald\'s Scroll lets a commander cast one spell before battle.');
    }

    // ---------------------------------------------------------------- setup
    addStack(side, key, count, name, uid) {
      const def = G.Units.resolve(key);
      const s = {
        id: this.nextId++, uid: uid || null, side, key, def, name: name || def.name, count, start: count,
        phys: 0, mor: 0, moraleVal: 0, adv: 0, engaging: [], guarding: null, guardedBy: null,
        fallenBack: false, retaliating: false, hero: false, spells: {}, extraHp: 0, extraMor: 0, extraSlow: 0,
        deserters: 0, dead: 0, gained: 0, waited: false, extraTurnUsed: false, lastLossDead: false,
      };
      this.stacks.push(s);
      return s;
    }

    setupSides() {
      for (const side of this.sides) {
        const h = side.hero;
        const stacks = this.stacksOf(side.idx);
        if (h) {
          const t4 = U.sum(stacks.filter(s => s.def.tier >= 4 && !s.def.mounted).map(s => s.count));
          side.courage = G.Heroes.stat(h, 'courage') - stacks.length - t4;
          side.st.startCourageLE0 = side.courage <= 0;
          const equipped = h.equipped.slice();
          side.hs = {
            active: false, castsLeft: 0, uses: equipped.map(() => G.Heroes.usesPerSpell(h)), equipped,
            pips: 0, spareKnowledge: Math.max(0, G.Heroes.stat(h, 'knowledge') - G.Heroes.equippedCost(h, equipped)),
            freeCast: G.Heroes.has(h, 'herald') ? 1 : 0, gone: null, ranOut: false, haste: 0,
          };
          if (G.Heroes.stat(h, 'knowledge') <= G.Heroes.equippedCost(h, equipped)) side.st.knowledgeXP += 3;
        } else side.courage = 0;
      }
      for (const s of this.stacks) {
        const hs = this.sides[s.side].hero;
        if (hs) {
          const w = G.Heroes.skill(hs, 'warding'); if (w) s.phys -= [0, 3, 6, 12][w];
          if (G.Heroes.skill(hs, 'tactics') >= 3) s.adv += 1;
        }
        if (this.fx.defAdv && s.side === 1) s.adv += this.fx.defAdv;
        if (s.count <= this.alwaysHeroN(s.side)) s.hero = true;
        this.recalcMorale(s);
      }
      // Beta T4: at start of combat 1 creature flees from every other stack
      for (const b of this.stacks.filter(s => s.def.sp.scatterOnStart)) {
        for (const o of this.stacks) if (o !== b && o.count > 0 && !o.def.sp.ignoreNegSpecials) {
          o.count -= 1; o.deserters += 1; this.say(`${o.name} loses 1 creature fleeing from ${b.name}.`);
          if (o.count <= 0) this.eliminated(o);
        }
      }
    }

    endPreCombat() { this.preCombat = false; for (const sd of this.sides) if (sd.hs) sd.hs.freeCast = 0; this.startRound(); }

    // ---------------------------------------------------------------- queries
    say(t, cls) { this.log.push({ r: this.round, t, cls: cls || '' }); }
    stack(id) { return this.stacks.find(s => s.id === id); }
    alive(s) { return s && s.count > 0; }
    stacksOf(side) { return this.stacks.filter(s => s.side === side && s.count > 0); }
    enemiesOf(s) { return this.stacks.filter(o => o.side !== s.side && o.count > 0); }
    alliesOf(s) { return this.stacks.filter(o => o.side === s.side && o.count > 0); }
    heroOf(side) { const sd = this.sides[side]; return sd.hs && !sd.hs.gone ? sd.hero : null; }
    anyHas(art) { return this.sides.some(sd => sd.hero && G.Heroes.has(sd.hero, art)); }
    heroSkill(side, k) { const h = this.sides[side].hero; return h ? G.Heroes.skill(h, k) : 0; }
    heroStat(side, k) { const h = this.sides[side].hero; if (!h) return 0; let v = G.Heroes.stat(h, k); if (k === 'power' && this.fx.doublePower) v *= 2; return v; }
    ign(s) { return !!s.def.sp.ignoreNegSpecials; }
    current() { const e = this.queue[this.qi]; return e || null; }
    currentStack() { const e = this.current(); return e && e.type === 'stack' ? this.stack(e.id) : null; }
    assaulters(s) { return this.stacks.filter(o => o.count > 0 && o.side !== s.side && o.engaging.includes(s.id)); }
    engagedWith(a, t) { return a.engaging.includes(t.id); }
    protectorOf(t) { const p = t.guardedBy != null ? this.stack(t.guardedBy) : null; return p && p.count > 0 ? p : null; }
    isGuarded(t) { return !!this.protectorOf(t); }
    wallProtected(t) {
      if (!this.wall || t.side !== 1 || this.wall.hp <= 0) return false;
      const defs = this.stacksOf(1);
      const k = Math.ceil(this.wall.hp / C.wallPerStack);
      return defs.indexOf(t) < k; // bottom stacks lose protection first
    }

    effCount(s) {
      let n = s.count - (s.spells.diminish || 0);
      if (s.spells.halve) n = Math.round(n / 2);
      return Math.max(0, n);
    }
    isRanged(s) {
      let r = !!s.def.ab.ranged || !!this.fx.allRanged || (!!this.fx.defRanged && s.side === 1) || (!!this.fx.defHalfRanged && s.side === 1);
      if (this.fx.noRanged) r = false;
      return r;
    }
    halfRangedOnly(s) { return !!this.fx.defHalfRanged && s.side === 1 && !s.def.ab.ranged && !this.fx.allRanged && !this.fx.defRanged; }
    isCavalry(s) {
      let c = !!s.def.ab.cavalry || !!this.fx.allCavalry || (!!this.fx.attCavalry && s.side === 0);
      if (this.fx.noCavalry) c = false;
      if (this.fx.attNoCavR1 && s.side === 0 && this.round <= 1) c = false;
      return c;
    }
    canFly(s) { return !!s.def.ab.fly; }
    slowLevel(s) {
      let v = (s.def.ab.slow || 0) + s.extraSlow + (this.fx.slowMod || 0) - (s.spells.quicken || 0);
      if (this.fx.slowModNonRanged && !this.isRanged(s)) v += this.fx.slowModNonRanged;
      if (this.fx.rangedSlow && this.isRanged(s)) v += Math.max(1, this.fx.rangedSlow) ;
      const h = this.sides[s.side].hero;
      if (h && G.Heroes.has(h, 'horseshoe')) v -= 1;
      if (h && s.def.mounted && G.Heroes.skill(h, 'horsemanship') >= 3) v -= 1;
      return Math.max(0, v);
    }
    health(s) { const h = this.sides[s.side].hero; return Math.max(1, s.def.hp + s.extraHp + (h && G.Heroes.has(h, 'heart') ? 1 : 0)); }
    rawHealth(s) { return s.def.hp + s.extraHp; }
    countBonus(s, per) {
      if (per === 'ad' && this.anyHas('banner')) return 0;
      if (per === 'mor' && this.anyHas('stoic')) return 0;
      const b = per === 'mor' ? C.perUnitMoraleBonus : C.perUnitAttDefBonus;
      return b * this.effCount(s) * (s.def.sp.doubleBonuses ? 2 : 1);
    }
    attack(s) {
      if (this.fx.attDef10 || s.spells.equalize) return 10;
      const h = this.sides[s.side].hero;
      let v = s.def.att * (1 + this.countBonus(s, 'ad')) + s.def.flatAtt + s.adv * (s.def.sp.doubleBonuses ? 2 : 1);
      if (h) v += G.Heroes.stat(h, 'attack');
      if (s.hero) v += C.heroUnitBonus.att;
      if (h && s.def.mounted) v += [0, 1, 2, 2][G.Heroes.skill(h, 'horsemanship')];
      return Math.round(v);
    }
    defence(s) {
      if (this.fx.attDef10 || s.spells.equalize) return 10;
      const h = this.sides[s.side].hero;
      let v = s.def.def * (1 + this.countBonus(s, 'ad')) + s.def.flatDef + s.adv * (s.def.sp.doubleBonuses ? 2 : 1);
      if (h) v += G.Heroes.stat(h, 'defence');
      if (s.hero) v += C.heroUnitBonus.def;
      if (h && s.def.mounted) v += [0, 1, 2, 2][G.Heroes.skill(h, 'horsemanship')];
      return Math.round(v);
    }
    recalcMorale(s) {
      const h = this.sides[s.side].hero;
      let v = s.def.mor * (1 + this.countBonus(s, 'mor')) + s.def.flatMor + s.extraMor + (s.spells.valor || 0);
      if (s.hero) v += C.heroUnitBonus.mor;
      if (h) v += [0, 1, 2, 4][G.Heroes.skill(h, 'inspiration')];
      for (const o of this.alliesOf(s)) if (o !== s && o.def.sp.moraleAura) v += o.def.sp.moraleAura;
      if (this.fx.defMoraleX && s.side === 1) v *= this.fx.defMoraleX;
      if (this.fx.moraleHalf) v *= 0.5;
      const hs = this.sides[s.side];
      if (hs.hero && hs.trainless) v -= 1;
      s.moraleVal = Math.max(0, Math.round(v));
      return s.moraleVal;
    }
    dmgTriple(s, target) {
      let d = s.def.dmg.slice();
      const add = (s.spells.sharpen || 0) - (s.spells.blunt || 0) + (s.hero ? C.heroUnitBonus.dmg : 0)
        - (target && target.def.sp.dmgAuraMinus1 && !this.ign(s) ? 1 : 0);
      return d.map(x => Math.max(0, x + add));
    }
    initiative(s) {
      let v = s.def.ini + (s.spells.haste || 0);
      if (this.fx.attackerInit && s.side === 0) v += this.fx.attackerInit;
      return v;
    }
    heroInit(side) {
      const h = this.sides[side].hero, hs = this.sides[side].hs;
      let v = (G.Heroes.stat(h, 'initiative') - hs.pips + hs.haste * 3) / 3;
      if (this.fx.attackerInit && side === 0) v += this.fx.attackerInit;
      return v;
    }
    alwaysHeroN(side) { const t = this.heroSkill(side, 'heroics'); return [C.heroUnitAlways, 3, 6, 12][t]; }
    heroFrac(side) { return this.heroSkill(side, 'heroics') ? 0.5 : C.heroUnitFraction; }
    strength(side) { return U.sum(this.stacksOf(side).map(s => s.count * G.Units.value(s.def) * (1 + s.def.hp / 4))); }

    // ---------------------------------------------------------------- rounds & turns
    startRound() {
      if (this.over) return;
      this.round++;
      this.attackedLastRound = this.attackedThisRound.slice();
      if (this.round === 1) this.attackedLastRound = [true, true];
      this.attackedThisRound = [false, false];
      this.damageThisRound = false;
      this.say(`— Round ${this.round} —`, 'round');
      // terrain damage each round
      if (this.fx.physPerRound || this.fx.moraleDmgPerRound) {
        for (const s of this.stacks.filter(x => x.count > 0)) {
          const t = Math.min(4, s.def.tier);
          this.dealDamage(s, Math.round((this.fx.physPerRound || 0) / t), Math.round((this.fx.moraleDmgPerRound || 0) / t), { kind: 'terrain' });
        }
        if (this.checkEnd()) return;
      }
      // AI flee rules
      for (const sd of this.sides) if (sd.ai && sd.neutral && C.monsterFlee && this.round >= 2 && this.aiShouldFlee(sd.idx)) {
        this.say(`${sd.name} flee the field!`, 'big');
        this.over = { winner: 1 - sd.idx, reason: 'fled', fled: sd.idx };
        return;
      }
      for (const sd of this.sides) if (sd.hs) { sd.hs.active = false; sd.hs.castsLeft = G.Heroes.castsPerRound(sd.hero); }
      // build initiative queue
      const q = [];
      this.stacks.forEach((s, i) => {
        if (s.count <= 0) return;
        s.waited = false; s.extraTurnUsed = false;
        q.push({ type: 'stack', id: s.id, side: s.side, init: this.initiative(s), tie: (s.def.sp.firstOnTie ? 1 : 0), pos: i });
        if (s.def.sp.twoTurns) q.push({ type: 'stack', id: s.id, side: s.side, init: this.initiative(s) - 0.5, tie: 0, pos: i, second: true });
      });
      for (const sd of this.sides) if (sd.hs && !sd.hs.gone) q.push({ type: 'hero', side: sd.idx, init: this.heroInit(sd.idx), tie: 2, pos: -1 });
      q.sort((a, b) => (b.init - a.init) || (a.side - b.side) || (b.tie - a.tie) || (a.pos - b.pos));
      this.queue = q; this.qi = 0;
      for (const sd of this.sides) if (sd.hs && !sd.hs.gone && !(q[0].type === 'hero' && q[0].side === sd.idx)) sd.st.notFirst += 1;
      this.beginTurn();
    }

    beginTurn() {
      if (this.over) return;
      while (this.qi < this.queue.length) {
        const e = this.queue[this.qi];
        if (e.type === 'stack') { const s = this.stack(e.id); if (s && s.count > 0) break; }
        if (e.type === 'hero' && this.sides[e.side].hs && !this.sides[e.side].hs.gone) break;
        this.qi++;
      }
      if (this.qi >= this.queue.length) return this.endRound();
      const e = this.queue[this.qi];
      this.turnActed = false;
      if (e.type === 'hero') {
        this.sides[e.side].hs.active = true;
        return;
      }
      const s = this.stack(e.id);
      if (e.second) this.say(`${s.name} acts again.`);
      if (e.resumed) return;
      // start-of-turn effects
      s.fallenBack = false; s.retaliating = false;
      const prior = s.mor;
      if (s.def.sp.purgeMoraleOnTurn) s.mor = Math.min(0, s.mor);
      else if (prior > 0) s.mor = Math.max(0, prior - s.moraleVal);
      else if (s.def.sp.negMoraleOverflow) s.mor = prior - Math.round(s.moraleVal / 2);
      if (s.def.sp.regenPerUnit && s.phys > 0) s.phys = Math.max(0, s.phys - s.count);
      if (s.def.sp.moralePerTurn) { s.extraMor += s.def.sp.moralePerTurn; }
      if (s.def.sp.advPerTurn) s.adv += 1;
      this.recalcMorale(s);
    }

    endTurn(actionKind) {
      const e = this.current();
      if (this.checkEnd()) return;
      if (e && e.type === 'stack') {
        const s = this.stack(e.id);
        if (s && s.count > 0 && s.def.sp.extraTurnNonAttack && actionKind !== 'attack' && actionKind !== 'wait' && !s.extraTurnUsed) {
          s.extraTurnUsed = true;
          const entry = { type: 'stack', id: s.id, side: s.side, init: 2, tie: 0, pos: 99, second: true };
          let at = this.queue.findIndex((x, i) => i > this.qi && x.init < 2);
          if (at < 0) at = this.queue.length;
          if ((e.init || 0) <= 2) at = this.qi + 1;
          this.queue.splice(at, 0, entry);
        }
      }
      this.qi++;
      this.beginTurn();
    }

    endRound() {
      for (const sd of this.sides) if (sd.hero) sd.st.rounds = (sd.st.rounds || 0) + 1;
      if (!this.damageThisRound) {
        this.say('No damage was dealt this round — the battle ends.', 'big');
        this.over = { winner: null, reason: 'stalemate' };
        return;
      }
      if (this.round >= C.roundCap) { this.over = { winner: null, reason: 'exhaustion' }; this.say('Both armies are exhausted.', 'big'); return; }
      this.startRound();
    }

    checkEnd() {
      if (this.over) return true;
      const a = this.stacksOf(0).length, d = this.stacksOf(1).length;
      if (!a || !d) {
        this.over = { winner: !a && !d ? null : (a ? 0 : 1), reason: 'destroyed' };
        this.say(this.over.winner === null ? 'Both armies are gone.' : `${this.sides[this.over.winner].name} win!`, 'big');
        return true;
      }
      return false;
    }

    // ---------------------------------------------------------------- damage
    rollDamage(a, t, opts) {
      const n = this.effCount(a);
      const X = Math.max(C.minDice, Math.round(n));
      const r = this.rng.int(1, X);
      const crit = (a.def.sp.crit && !this.ign(t)) ? a.def.sp.crit : 0;
      const tri = this.dmgTriple(a, t);
      let per, how;
      if (a.spells.fortune && !a.spells.misfortune) { per = tri[2]; how = 'max'; }
      else if (a.spells.misfortune && !a.spells.fortune) { per = tri[0]; how = 'min'; }
      else if (opts && opts.average) { per = tri[1]; how = 'avg'; }
      // crit adds to the roll itself: a boosted 1 is no longer a natural 1, so crit units never roll minimum
      else if (r + crit >= X) { per = tri[2]; how = r === X ? 'max' : 'crit'; }
      else if (r + crit === 1) { per = tri[0]; how = 'min'; }
      else { per = tri[1]; how = 'avg'; }
      return { per, how, roll: r, X };
    }
    hitNumbers(a, t, opts) {
      const roll = this.rollDamage(a, t, opts);
      const n = this.effCount(a);
      let total = roll.per * n;
      if (opts && opts.half) total *= 0.5;
      const A = this.attack(a), D = this.defence(t);
      const mult = A > D ? Math.min(1 + C.attCap, 1 + C.attPerPoint * (A - D)) : Math.max(1 - C.defCap, 1 - C.defPerPoint * (D - A));
      total = Math.round(total * mult);
      let phys, mor;
      if (a.def.sp.allPhysical) { phys = total; mor = 0; }
      else if (a.def.sp.split5050) { mor = Math.round(total / 2); phys = total - mor; }
      else { mor = Math.round(total * C.moraleShare); phys = total - mor; }
      if (a.def.sp.extraMoraleDmg && !this.ign(t)) mor += Math.round(a.moraleVal * (C.beta2PerCreature ? n : 1) * mult);
      if (t.def.sp.extraDamageTaken && !(t.def.sp.extraDamageOnlyIfAttLE && A > D)) phys += 1;
      return { phys, mor, total, mult, A, D, roll };
    }

    // Returns {killed, deserted}
    dealDamage(t, phys, mor, ctx) {
      ctx = ctx || {};
      if (t.count <= 0) return { killed: 0, deserted: 0 };
      if (this.fx.swapDamage && ctx.kind !== 'spellPure') { const x = phys; phys = mor; mor = x; }
      if (this.fx.noPhysical && phys > 0) phys = 0;
      if (t.def.sp.lastStandConvert && phys > 0) {
        const sim = this.simulatePhys(t, phys);
        if (sim >= t.count) { mor += phys; phys = 0; }
      }
      if (phys > 0 || mor > 0) this.damageThisRound = true;
      const courage = this.sides[t.side].courage;
      let deserted = 0, killed = 0;
      if (mor > 0) {
        const mv = t.moraleVal; // "calculate morale before damage"
        t.mor += mor;
        const h = this.health(t);
        while (t.count > 0 && t.mor > t.count * (mv - 1)) {
          t.count--; deserted++; t.deserters++;
          t.mor -= Math.max(1, 2 * mv + courage);
          if (t.phys > 0) t.phys = Math.max(0, t.phys - (h - 1));
        }
        if (deserted) t.mor = Math.max(0, t.mor);
      }
      if (phys !== 0) {
        t.phys += phys;
        const h = this.health(t);
        const extra = t.def.sp.courageHealth ? courage : 0;
        while (t.count > 0 && t.phys > t.count * (h - 1)) {
          t.count--; killed++; t.dead++;
          t.phys -= Math.max(1, 2 * h + extra);
        }
        if (killed) t.phys = Math.max(0, t.phys);
      }
      if (this.fx.desertersDie && deserted) { t.deserters -= deserted; t.dead += deserted; }
      t.lastLossDead = killed > 0;
      if (killed || deserted) this.onLosses(t, killed, deserted, ctx);
      return { killed, deserted };
    }
    simulatePhys(t, phys) {
      let p = t.phys + phys, c = t.count, k = 0; const h = this.health(t);
      while (c > 0 && p > c * (h - 1)) { c--; k++; p -= 2 * h; }
      return k;
    }

    onLosses(t, killed, deserted, ctx) {
      const src = ctx.source;
      const tier = Math.min(4, t.def.tier);
      const enemySrc = (src && src.side !== t.side) || (ctx.kind === 'spell' && ctx.spellSide !== t.side);
      if (enemySrc) {
        const oside = 1 - t.side;
        this.sides[oside].st.killTier += killed * tier;
        this.sides[oside].st.killsByTier[tier] += killed;
        this.sides[t.side].st.lostTier += killed * tier;
        this.sides[t.side].st.desertedByEnemy += deserted;
      }
      const lost = killed + deserted;
      if (t.def.sp.lossMoraleHeal) t.mor = Math.max(0, t.mor - t.def.sp.lossMoraleHeal * lost);
      if (t.def.sp.lossGainMorale) t.extraMor += lost;
      // Delta T1 necromancy
      if (killed > 0) for (const o of this.stacks) {
        if (o === t || o.count <= 0) continue;
        let g = 0;
        if (o.def.sp.necroAny) g += killed;
        else if (o.def.sp.necroPhys === 'base' && tier >= Math.min(4, o.def.tier)) g += 1;
        else if (o.def.sp.necroPhys === 'melee') g += Math.floor(tier / Math.min(4, o.def.tier));
        if (g > 0) { o.count += g; o.gained += g; this.say(`${o.name} gains ${g} creature${g > 1 ? 's' : ''}.`, 'good'); }
      }
      // killer effects
      if (src && src.count > 0 && src.side !== t.side && killed > 0) {
        if (src.def.sp.killMoraleHeal) src.mor = Math.max(0, src.mor - tier * killed);
        if (src.def.sp.bigKillMorale && tier >= 3) src.extraMor += killed;
        const g = src.def.sp.gainHealthOnKill;
        if (g) { const th = this.rawHealth(t), mh = this.rawHealth(src); if ((g === 'gt' && th > mh) || (g === 'ge' && th >= mh)) { src.extraHp += 1; this.say(`${src.name} grows stronger (+1 health).`, 'good'); } }
        if (src.def.sp.killRecoverDeserter) { const r = Math.min(killed, src.deserters); if (r) { src.deserters -= r; src.count += r; } }
        this.recalcMorale(src);
      }
      const bits = [];
      if (killed) bits.push(`${killed} killed`);
      if (deserted) bits.push(`${deserted} deserted`);
      this.say(`${t.name}: ${bits.join(', ')}.`, 'loss');
      if (t.count <= 0) return this.eliminated(t);
      this.recalcMorale(t);
      this.checkHeroUnit(t);
    }

    checkHeroUnit(s) {
      if (s.hero || s.count <= 0) return;
      if (s.count <= s.start * this.heroFrac(s.side) || s.count <= this.alwaysHeroN(s.side)) {
        s.hero = true;
        this.sides[s.side].courage += 1;
        this.recalcMorale(s);
        s.mor = Math.max(0, s.mor - 2 * s.moraleVal); // "a unit rallies when it becomes a hero"
        this.say(`${s.name} become HEROES! (+1 courage, rallies)`, 'hero');
      }
    }

    eliminated(s) {
      for (const o of this.stacks) { o.engaging = o.engaging.filter(id => id !== s.id); if (o.guardedBy === s.id) o.guardedBy = null; if (o.guarding === s.id) o.guarding = null; }
      s.engaging = []; s.guarding = null; s.guardedBy = null;
      this.say(`${s.name} are gone from the field.`, 'big');
      const sd = this.sides[s.side];
      if (s.hero) { sd.courage -= 1; }
      for (const o of this.alliesOf(s)) this.recalcMorale(o);
      if (s.def.tier >= 4 && !s.def.mounted && sd.hs && !sd.hs.gone) {
        sd.hs.gone = s.lastLossDead ? 'dead' : 'fled';
        this.say(`${sd.hero.name} ${sd.hs.gone === 'dead' ? 'falls with' : 'flees with'} the ${s.name}!`, 'big');
      }
    }

    // ---------------------------------------------------------------- legality
    turnStack() { return this.over || this.preCombat ? null : this.currentStack(); }

    checkAttack(a, t) {
      if (!a || !t || t.count <= 0 || t.side === a.side) return 'Invalid target';
      if (t.fallenBack) return 'Fallen back (only guard may target it)';
      const ass = this.assaulters(a);
      if (ass.length && !ass.includes(t)) return 'Must target an assaulter';
      const eng = this.engagedWith(a, t);
      if (this.round <= this.slowLevel(a) && !eng) return `Slow: can't attack in round ${this.round} unless engaged with target`;
      if (this.wallProtected(t) && !eng) return 'Behind the walls';
      const tEngaged = t.engaging.length > 0 || this.assaulters(t).length > 0;
      if (this.isRanged(t) && this.round === 1 && !eng && !tEngaged) {
        if (this.canFly(t)) { if (!this.isRanged(a)) return 'Flying archers cannot be attacked in round 1 except by ranged units'; }
        else if (!this.isCavalry(a)) return 'Ranged units cannot be attacked in round 1 (except by cavalry)';
      }
      const p = this.protectorOf(t);
      if (p && !eng) {
        const rangedOk = this.isRanged(a) && !p.def.sp.guardVsRanged;
        if (!(rangedOk || this.canFly(a) || a.def.ab.teleport)) return `Guarded by ${p.name}`;
      }
      if (this.isGuarded(a) && !eng && !this.isRanged(a)) return 'Guarded units may only attack units they are engaged with';
      return null;
    }
    checkEngage(a, t) {
      if (!a || !t || t.count <= 0 || t.side === a.side) return 'Invalid target';
      if (t.fallenBack) return 'Fallen back';
      const ass = this.assaulters(a);
      if (ass.length && !ass.includes(t)) return 'Must target an assaulter';
      if (this.engagedWith(a, t)) return 'Already engaged';
      if (this.isCavalry(t) && !this.isCavalry(a)) return 'Only cavalry can engage cavalry';
      if (this.wallProtected(t)) return 'Behind the walls';
      if (this.isRanged(t) && this.round === 1 && !this.isCavalry(a)) return 'Ranged units cannot be engaged in round 1 (except by cavalry)';
      const p = this.protectorOf(t);
      if (p) {
        const pike = this.heroSkill(p.side, 'pikemanship') >= 1;
        if (!(this.isCavalry(a) && !this.isCavalry(p) && !pike)) return `Guarded by ${p.name}`;
      }
      return null;
    }
    checkGuard(a, t) {
      if (!a || !t || t === a || t.count <= 0 || t.side !== a.side) return 'Pick another friendly stack';
      if (this.assaulters(a).length) return 'Cannot guard while under assault';
      const p = this.protectorOf(t);
      if (p && p !== a) return `Already guarded by ${p.name}`;
      if (a.guarding === t.id) return 'Already guarding it';
      return null;
    }
    denyOptions(a, t) {
      const out = [];
      if (!t || t.count <= 0 || t.side === a.side || t.fallenBack) return out;
      for (const id of t.engaging) { const x = this.stack(id); if (x) out.push({ type: 'engage', id, label: `Break its engagement on ${x.name}` }); }
      const pikeBlock = st => st && st.adv > 0 && this.heroSkill(st.side, 'pikemanship') >= 2;
      if (t.guarding != null && this.stack(t.guarding) && !pikeBlock(t)) out.push({ type: 'guard', sub: 'out', label: `End its guard over ${this.stack(t.guarding).name}` });
      if (t.guardedBy != null && this.protectorOf(t) && !pikeBlock(this.protectorOf(t))) out.push({ type: 'guard', sub: 'in', label: `End ${this.protectorOf(t).name}'s guard over it` });
      if (t.adv > 0) out.push({ type: 'adv', label: a.def.sp.denyMulti ? `Strip up to ${a.adv + 1} advantages` : 'Strip one advantage' });
      if (a.adv > 0) for (const id in t.spells) if (t.spells[id] > 0) out.push({ type: 'spell', id, label: `Cancel one level of ${G.SPELLS[id].name} (spends 1 advantage)` });
      return out;
    }
    checkDeny(a, t) {
      if (!a || !t || t.count <= 0 || t.side === a.side) return 'Invalid target';
      if (t.fallenBack) return 'Fallen back';
      const ass = this.assaulters(a);
      if (ass.length && !ass.includes(t)) return 'Must target an assaulter';
      if (!this.denyOptions(a, t).length) return 'Nothing to deny';
      return null;
    }
    checkFallback(a) {
      const others = this.alliesOf(a).filter(o => o !== a && !o.fallenBack);
      if (!others.length) return 'Cannot fall back as the last unit standing';
      return null;
    }
    checkRally(a, t) {
      if (!t || t.count <= 0) return 'Invalid target';
      if (t.side !== a.side) return a.def.sp.rallyEnemy ? (t.fallenBack ? 'Fallen back' : null) : 'Rally targets friendly units';
      if (t.fallenBack && t !== a) return 'Fallen back (only guard may target it)';
      return null;
    }
    canWait(a) { return this.heroSkill(a.side, 'tactics') >= 1 && !a.waited && this.qi < this.queue.length - 1; }

    // ---------------------------------------------------------------- actions
    act(action, targetId, opt) {
      const a = this.turnStack();
      if (!a) return 'Not a unit turn';
      const t = targetId != null ? this.stack(targetId) : null;
      let err = null;
      switch (action) {
        case 'attack': err = targetId === 'wall' ? this.checkWallAttack(a) : this.checkAttack(a, t); break;
        case 'engage': err = this.checkEngage(a, t); break;
        case 'guard': err = this.checkGuard(a, t); break;
        case 'deny': err = this.checkDeny(a, t); break;
        case 'fallback': err = this.checkFallback(a); break;
        case 'rally': err = this.checkRally(a, t); break;
        case 'seek': case 'retaliate': break;
        case 'wait': err = this.canWait(a) ? null : 'Cannot wait'; break;
        default: err = 'Unknown action';
      }
      if (err) return err;
      this.turnActed = true;
      const loseAdv = () => { if (!this.fx.keepAdv) a.adv = 0; };
      switch (action) {
        case 'attack': {
          if (targetId === 'wall') { this.attackWall(a); break; }
          this.doAttack(a, t);
          break;
        }
        case 'engage':
          a.engaging.push(t.id); this.unguard(a); this.unprotect(a); loseAdv();
          this.say(`${a.name} engage ${t.name}.`);
          break;
        case 'guard':
          this.unprotect(a); this.unguard(a); loseAdv(); a.engaging = [];
          a.guarding = t.id; t.guardedBy = a.id;
          if (a.def.sp.advAfterGuard) a.adv += 1;
          if (this.heroSkill(a.side, 'pikemanship') >= 3) a.adv += 1;
          this.say(`${a.name} guard ${t.name}.`);
          break;
        case 'deny': {
          const opts = this.denyOptions(a, t);
          const o = (opt != null && opts[opt]) || opts[0];
          let spent = 1;
          if (o.type === 'engage') { t.engaging = t.engaging.filter(id => id !== o.id); }
          else if (o.type === 'guard') {
            if (o.sub === 'out') { const g = this.stack(t.guarding); if (g) g.guardedBy = null; t.guarding = null; }
            else { const p = this.protectorOf(t); if (p) p.guarding = null; t.guardedBy = null; }
          } else if (o.type === 'adv') {
            const n = a.def.sp.denyMulti ? Math.min(t.adv, a.adv + 1) : 1;
            t.adv -= n; spent = a.def.sp.denyMulti ? n : 1;
          } else if (o.type === 'spell') { t.spells[o.id]--; if (t.spells[o.id] <= 0) delete t.spells[o.id]; this.recalcMorale(t); }
          this.unprotect(a); this.unguard(a);
          if (!this.fx.keepAdv) a.adv = Math.max(0, a.adv - spent);
          a.engaging = a.engaging.filter(id => id === t.id);
          this.say(`${a.name} deny ${t.name}: ${o.label.toLowerCase()}.`);
          break;
        }
        case 'fallback':
          for (const o of this.stacks) o.engaging = o.engaging.filter(id => id !== a.id);
          a.engaging = []; this.unguard(a); this.unprotect(a); a.adv = 0; a.retaliating = false; a.fallenBack = true;
          if (a.def.sp.fallbackRecover && a.deserters > 0) { a.deserters--; a.count++; this.say(`${a.name} recover a deserter.`, 'good'); }
          this.recalcMorale(a);
          this.say(`${a.name} fall back.`);
          break;
        case 'seek': a.adv += 1; this.say(`${a.name} seek advantage (${a.adv}).`); break;
        case 'retaliate': a.retaliating = true; this.say(`${a.name} ready to retaliate.`); break;
        case 'rally': this.doRally(a, t); break;
        case 'wait': {
          a.waited = true;
          const e = this.queue.splice(this.qi, 1)[0];
          e.resumed = true;
          this.queue.push(e);
          this.say(`${a.name} wait.`);
          this.beginTurn();
          return null;
        }
      }
      this.endTurn(action);
      return null;
    }

    unguard(a) { const p = this.protectorOf(a); if (p) p.guarding = null; a.guardedBy = null; }
    unprotect(a) { if (a.guarding != null) { const g = this.stack(a.guarding); if (g) g.guardedBy = null; a.guarding = null; } }

    checkWallAttack(a) {
      if (!this.wall || this.wall.hp <= 0 || a.side !== 0) return 'No wall';
      const ass = this.assaulters(a);
      if (ass.length) return 'Must target an assaulter';
      if (this.round <= this.slowLevel(a)) return 'Slow';
      return null;
    }
    attackWall(a) {
      const fake = { def: { sp: {}, dmg: [0, 0, 0] }, spells: {}, side: 1, count: 1, adv: 0 };
      const roll = this.rollDamage(a, fake);
      const A = this.attack(a), D = 10;
      const mult = A > D ? Math.min(1 + C.attCap, 1 + C.attPerPoint * (A - D)) : Math.max(1 - C.defCap, 1 - C.defPerPoint * (D - A));
      const dmg = Math.round(roll.per * this.effCount(a) * mult);
      this.wall.hp = Math.max(0, this.wall.hp - dmg);
      this.damageThisRound = true; this.attackedThisRound[a.side] = true;
      this.say(`${a.name} batter the walls for ${U.fmt(dmg)} (${U.fmt(this.wall.hp)} left).`, 'dmg');
    }

    strike(a, t, opts) {
      opts = opts || {};
      if (a.count <= 0 || t.count <= 0) return null;
      const n = this.hitNumbers(a, t, { half: opts.half });
      const what = opts.ret ? 'retaliate against' : 'hit';
      this.say(`${a.name} ${what} ${t.name}: ${U.fmt(n.phys + n.mor)} dmg (${n.roll.how} roll ${n.roll.roll}/${n.roll.X}, ${n.mult >= 1 ? '+' : ''}${Math.round((n.mult - 1) * 100)}%) → ${U.fmt(n.mor)} morale, ${U.fmt(n.phys)} health.`, 'dmg');
      const res = this.dealDamage(t, n.phys, n.mor, { source: a, kind: 'attack' });
      if (a.def.sp.lifesteal && a.count > 0 && n.phys > 0) a.phys = Math.max(Math.min(a.phys, 0), a.phys - n.phys);
      if (t.def.sp.thorns && t.count > 0 && !opts.ret && !this.ign(a)) {
        const x = t.count;
        const xm = Math.round(x * C.moraleShare);
        this.dealDamage(a, x - xm, xm, { source: t, kind: 'attack' });
        this.say(`${a.name} take ${x} thorn damage from ${t.name}.`, 'dmg');
      }
      return res;
    }

    doAttack(a, t) {
      const engaged = this.engagedWith(a, t) || this.engagedWith(t, a);
      const underAssault = this.assaulters(a).length > 0;
      const ranged = this.isRanged(a);
      const half = ranged && this.halfRangedOnly(a) && !engaged;
      this.attackedThisRound[a.side] = true;
      if (a.def.sp.fleeOnAttack && !this.ign(t) && t.count > 0) {
        t.count--; t.deserters++; this.say(`1 of ${t.name} flees before ${a.name}!`, 'loss');
        if (t.count <= 0) { this.eliminated(t); return; }
      }
      const canRet = (t.retaliating || t.def.sp.alwaysRetaliate) && !(ranged && !this.isRanged(t) && !engaged);
      if (canRet && t.def.sp.firstStrikeRetaliate) {
        this.strike(t, a, { ret: true });
        this.strike(a, t, { half });
      } else {
        this.strike(a, t, { half });
        if (canRet) this.strike(t, a, { ret: true });
      }
      if (a.def.sp.attackAllEngaged) for (const id of a.engaging.slice()) { const e = this.stack(id); if (e && e !== t && e.count > 0) this.strike(a, e); }
      if (t.count > 0 && t.def.sp.counterEngage && a.count > 0 && (t.def.sp.counterEngage === 'any' || !ranged) && !t.engaging.includes(a.id)) {
        t.engaging.push(a.id); this.say(`${t.name} engage ${a.name} in return.`);
      }
      if (a.count <= 0) return;
      if (!engaged && !(ranged && !underAssault)) {
        this.unprotect(a); this.unguard(a);
        if (!a.def.sp.keepAdvOnAttack && !this.fx.keepAdv) a.adv = 0;
        a.engaging = [];
      }
      if (a.def.sp.engageAfterAttack && t.count > 0 && !a.engaging.includes(t.id)) { a.engaging.push(t.id); this.say(`${a.name} engage ${t.name}.`); }
    }

    doRally(a, t) {
      if (t.side !== a.side) {
        const amt = 2 * a.moraleVal;
        this.say(`${a.name} terrify ${t.name} (${U.fmt(amt)} morale damage).`, 'dmg');
        this.dealDamage(t, 0, amt, { source: a, kind: 'attack' });
        this.attackedThisRound[a.side] = true;
        return;
      }
      let amt = Math.round(2 * a.moraleVal * (a.def.sp.rallyBoost ? 1.5 : 1));
      const heal = x => {
        if (t.mor <= 0 && t.def.sp.negMoraleOverflow) t.mor -= Math.round(x / 2);
        else t.mor = Math.max(0, t.mor - x);
      };
      if (a.def.sp.rallyConvert) {
        const p = Math.min(Math.max(t.phys, 0), amt);
        t.phys -= p; t.mor += 2 * p; amt -= p;
        if (p) this.say(`${a.name} convert ${U.fmt(p)} physical damage on ${t.name} into ${U.fmt(2 * p)} morale damage.`);
      }
      heal(amt);
      if (a.def.sp.rallyHealsPhys && t.phys > 0) t.phys = Math.max(0, t.phys - a.count);
      this.recalcMorale(t);
      this.say(`${a.name} rally ${t === a ? 'themselves' : t.name} (−${U.fmt(amt)} morale damage).`, 'good');
    }

    // ---------------------------------------------------------------- hero
    heroCanAct(side) {
      const sd = this.sides[side];
      if (this.over || !sd.hs || sd.hs.gone) return false;
      if (this.preCombat) return sd.hs.freeCast > 0;
      if (!sd.hs.active || sd.hs.castsLeft <= 0) return false;
      const e = this.current();
      if (!e) return false;
      if (e.type === 'hero') return e.side === side;
      return e.side === side && !this.turnActed;
    }
    heroTurnNow(side) { const e = this.current(); return !this.over && !this.preCombat && e && e.type === 'hero' && e.side === side; }
    spellUsesLeft(side) {
      const hs = this.sides[side].hs; const out = {};
      if (!hs) return out;
      hs.equipped.forEach((id, i) => { out[id] = (out[id] || 0) + hs.uses[i]; });
      return out;
    }
    spellMaxLevel(side, id, t) {
      const sp = G.SPELLS[id];
      const lay = this.heroSkill(side, 'layering');
      const extra = [0, 1, 2, Infinity][lay];
      if (sp.stack === true) return Infinity;
      if (sp.stack === 'copies') return this.sides[side].hs.equipped.filter(x => x === id).length + extra;
      return 1 + extra;
    }
    spellPowerMult(side, id) {
      const h = this.sides[side].hero;
      const p = this.heroStat(side, 'power') + ((h && h.spellPower[id]) || 0);
      const ev = [0, 0.10, 0.25, 0.50][this.heroSkill(side, 'evocation')];
      return (1 + C.spellPowerPct * p) * (1 + ev * Math.max(0, this.round - 1));
    }
    checkCast(side, id, tId, t2Id) {
      if (!this.heroCanAct(side)) return 'Commander cannot act now';
      const left = this.spellUsesLeft(side)[id] || 0;
      if (left <= 0) return 'No uses left';
      const sp = G.SPELLS[id];
      if (sp.target === 'stackOrHero' && (tId === 'hero0' || tId === 'hero1')) return null;
      const t = this.stack(tId);
      if (!t || t.count <= 0) return 'Pick a target';
      if (sp.target === 'pair') { const t2 = this.stack(t2Id); if (!t2 || t2.count <= 0 || t2 === t) return 'Pick a second target'; }
      if (!sp.instant) { const lvl = t.spells[id] || 0; if (lvl >= this.spellMaxLevel(side, id, t)) return 'Cannot stack further'; }
      return null;
    }
    cast(side, id, tId, t2Id) {
      const err = this.checkCast(side, id, tId, t2Id);
      if (err) return err;
      const sd = this.sides[side], hs = sd.hs, sp = G.SPELLS[id], h = sd.hero;
      // consume a copy with uses left
      const i = hs.equipped.findIndex((x, k) => x === id && hs.uses[k] > 0);
      hs.uses[i] -= 1;
      if (this.preCombat) hs.freeCast--; else hs.castsLeft--;
      sd.st.spells += 1;
      const pm = this.spellPowerMult(side, id);
      if (tId === 'hero0' || tId === 'hero1') {
        const hsT = this.sides[+tId.slice(4)].hs; hsT.haste += 1;
        this.say(`${h.name} casts ${sp.name} on ${this.sides[+tId.slice(4)].hero.name}.`, 'spell');
      } else {
        const t = this.stack(tId);
        this.say(`${h.name} casts ${sp.name} on ${t.name}.`, 'spell');
        switch (id) {
          case 'flame': this.dealDamage(t, Math.round(sp.amount * pm), 0, { kind: 'spell', source: null, spellSide: side }); if (t.side !== side) this.attackedThisRound[side] = true; break;
          case 'dread': { const tot = Math.round(sp.amount * pm), dm = Math.round(tot * C.moraleShare); this.dealDamage(t, tot - dm, dm, { kind: 'spell', spellSide: side }); if (t.side !== side) this.attackedThisRound[side] = true; break; }
          case 'ward': t.phys -= Math.round(sp.amount * pm); break;
          case 'mend': if (t.phys > 0) t.phys = Math.max(0, t.phys - Math.round(sp.amount * pm)); break;
          case 'dispel': t.spells = {}; this.recalcMorale(t); break;
          case 'transfer': {
            const t2 = this.stack(t2Id); const amt = Math.max(0, t.mor); t.mor = Math.min(0, t.mor);
            this.say(`${U.fmt(amt)} morale damage moves from ${t.name} to ${t2.name}.`, 'spell');
            this.dealDamage(t2, 0, amt, { kind: 'spell', spellSide: side });
            break;
          }
          default:
            t.spells[id] = (t.spells[id] || 0) + 1;
            this.recalcMorale(t);
        }
      }
      // spellthief (enemy): gains power on their copy
      const other = this.sides[1 - side];
      if (other.hero && G.Heroes.skill(other.hero, 'spellthief') >= 2 && other.hero.spellbook.includes(id)) {
        other.hero.spellPower[id] = (other.hero.spellPower[id] || 0) + 1;
        this.say(`${other.hero.name}'s ${sp.name} grows stronger.`, 'spell');
      }
      if (!hs.ranOut && hs.uses.every(u => u <= 0)) { hs.ranOut = true; sd.st.knowledgeXP += 3 * hs.equipped.length; }
      this.checkEnd();
      return null;
    }
    commandOptions(side) {
      const sd = this.sides[side], hs = sd.hs;
      if (!hs) return [];
      return [
        { id: 'recall', label: 'Recall deserter', desc: 'Spend courage = tier to return 1 deserter to a stack.', need: 'stack' },
        { id: 'revive', label: 'Revive fallen', desc: `Spend spare knowledge (${U.fmt(hs.spareKnowledge)}) = tier to revive 1 dead.`, need: 'stack' },
        { id: 'embolden', label: 'Embolden', desc: 'Spend one initiative pip: +1 advantage to a stack.', need: 'stack' },
        { id: 'steel', label: 'Steel nerves', desc: '+1 courage.', need: null },
      ];
    }
    command(side, cmd, tId) {
      if (!this.heroCanAct(side) || this.preCombat) return 'Commander cannot act now';
      const sd = this.sides[side], hs = sd.hs, h = sd.hero;
      const t = tId != null ? this.stack(tId) : null;
      const tier = t ? Math.min(4, t.def.tier) : 0;
      switch (cmd) {
        case 'recall':
          if (!t || t.side !== side || t.count <= 0) return 'Pick a friendly stack';
          if (t.deserters <= 0) return 'No deserters';
          if (sd.courage < tier) return 'Not enough courage';
          sd.courage -= tier; t.deserters--; t.count++; this.recalcMorale(t);
          this.say(`${h.name} recalls a deserter to ${t.name}.`, 'hero'); break;
        case 'revive':
          if (!t || t.side !== side || t.count <= 0) return 'Pick a friendly stack';
          if (t.dead <= 0) return 'No dead to revive';
          if (hs.spareKnowledge < tier) return 'Not enough spare knowledge';
          hs.spareKnowledge -= tier; t.dead--; t.count++; this.recalcMorale(t);
          this.say(`${h.name} revives one of ${t.name}.`, 'hero'); break;
        case 'embolden':
          if (!t || t.side !== side || t.count <= 0) return 'Pick a friendly stack';
          if (G.Heroes.stat(h, 'initiative') - hs.pips <= 0) return 'No initiative pips left';
          hs.pips += 1; t.adv += 1;
          this.say(`${h.name} emboldens ${t.name} (+1 advantage).`, 'hero'); break;
        case 'steel':
          sd.courage += 1; this.say(`${h.name} steels the army (+1 courage).`, 'hero'); break;
        default: return 'Unknown command';
      }
      hs.castsLeft--;
      return null;
    }
    heroEnd(side) {
      if (!this.heroTurnNow(side)) return 'Not the commander\'s turn';
      this.endTurn('hero');
      return null;
    }
    flee(side) {
      if (this.over) return 'Battle over';
      this.over = { winner: 1 - side, reason: 'fled', fled: side };
      this.say(`${this.sides[side].name} retreat!`, 'big');
      return null;
    }

    // ---------------------------------------------------------------- results
    summary() {
      return this.sides.map(sd => ({
        side: sd.idx, st: sd.st, heroGone: sd.hs ? sd.hs.gone : null, courage: sd.courage,
        stacks: this.stacks.filter(s => s.side === sd.idx).map(s => ({
          uid: s.uid, key: s.key, name: s.name, start: s.start, survivors: Math.max(0, s.count), dead: s.dead, deserters: s.deserters, gained: s.gained,
          terrainGift: s.uid == null && (s.name === 'Militia' || s.name === 'Mercenaries'),
        })),
      }));
    }

    // ---------------------------------------------------------------- AI helpers
    aiShouldFlee(side) {
      const opp = 1 - side;
      if (this.attackedLastRound[opp]) return false;
      const weak = this.strength(side) <= 0.5 * this.strength(opp);
      let canKill = false;
      for (const a of this.stacksOf(side)) for (const t of this.stacksOf(opp)) {
        if (this.expectedHit(a, t).removed >= 1) { canKill = true; break; }
      }
      return weak || !canKill;
    }
    expectedHit(a, t) {
      const n = this.hitNumbers(a, t, { average: true });
      const saveRng = this.rng.state();
      const clone = Object.assign({}, t, { spells: Object.assign({}, t.spells) });
      const save = { log: this.log.length, dmg: this.damageThisRound };
      // quick simulation without side effects
      const mv = clone.moraleVal, h = this.health(clone), cour = this.sides[t.side].courage;
      let c = clone.count, m = clone.mor + n.mor, p = clone.phys + n.phys, removed = 0;
      while (c > 0 && m > c * (mv - 1)) { c--; removed++; m -= Math.max(1, 2 * mv + cour); }
      while (c > 0 && p > c * (h - 1)) { c--; removed++; p -= Math.max(1, 2 * h); }
      this.rng.setState(saveRng); this.log.length = save.log; this.damageThisRound = save.dmg;
      return { removed, total: n.total, frac: (n.mor / Math.max(1, mv * t.count)) + (n.phys / Math.max(1, h * t.count)) };
    }
  }

  G.Battle = Battle;
})();
