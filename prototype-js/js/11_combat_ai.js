// ============================================================================
// Combat AI: one-ply heuristic over the legal actions.
// ============================================================================
G.CombatAI = {
  // Decide & perform one decision for whoever acts now (hero slot or stack).
  step(b) {
    if (b.over) return false;
    if (b.preCombat) { b.endPreCombat(); return true; }
    const e = b.current();
    if (!e) return false;
    const side = e.side;
    // commander casts at its slot / friendly turn starts
    if (b.heroCanAct(side)) {
      const c = this.bestCast(b, side);
      if (c && c.score > 0.4) { const err = b.cast(side, c.id, c.t, c.t2); if (!err) return true; }
    }
    if (e.type === 'hero') { b.heroEnd(side); return true; }
    const s = b.stack(e.id);
    const d = this.decide(b, s);
    const err = b.act(d.action, d.target, d.opt);
    if (err) b.act('seek');
    return true;
  },

  valueOf(b, s) { return G.Units.value(s.def) * (1 + s.def.hp / 4); },

  decide(b, a) {
    const cands = [];
    const enemies = b.enemiesOf(a), allies = b.alliesOf(a);
    const underAssault = b.assaulters(a).length > 0;
    const myVal = this.valueOf(b, a);
    // attacks
    for (const t of enemies) {
      if (b.checkAttack(a, t)) continue;
      const hit = b.expectedHit(a, t);
      let score = hit.removed * this.valueOf(b, t) + hit.frac * t.count * this.valueOf(b, t) * 0.5;
      const willRet = (t.retaliating || t.def.sp.alwaysRetaliate) && !(b.isRanged(a) && !b.isRanged(t));
      if (willRet) { const back = b.expectedHit(t, a); score -= 0.8 * (back.removed * myVal + back.frac * a.count * myVal * 0.5); }
      const engaged = b.engagedWith(a, t) || b.engagedWith(t, a);
      if (!engaged && !(b.isRanged(a) && !underAssault)) score -= 0.15 * a.adv * myVal + (a.guarding != null ? 0.5 * myVal : 0);
      if (b.isRanged(t)) score *= 1.15;
      cands.push({ action: 'attack', target: t.id, score });
    }
    if (b.wall && b.wall.hp > 0 && !b.checkWallAttack(a)) cands.push({ action: 'attack', target: 'wall', score: 0.4 * a.count * myVal * 0.2 });
    const bestAtt = Math.max(0, ...cands.map(c => c.score));
    // engage
    for (const t of enemies) {
      if (b.checkEngage(a, t)) continue;
      let score = 0.15 * this.valueOf(b, t) * Math.min(t.count, 10) / 5;
      if (b.round <= b.slowLevel(a)) score += 0.3 * t.count * this.valueOf(b, t) * 0.2;
      if (b.isRanged(t)) score *= 1.6;
      if (b.isGuarded(t)) score *= 1.5;
      score -= 0.15 * a.adv * myVal;
      cands.push({ action: 'engage', target: t.id, score });
    }
    // rally
    for (const t of allies) {
      if (b.checkRally(a, t)) continue;
      const cap = Math.max(1, t.count * Math.max(0.5, t.moraleVal - 1));
      const ratio = t.mor / cap;
      if (ratio < 0.35) continue;
      const amt = Math.min(t.mor, 2 * a.moraleVal);
      const score = (amt / Math.max(1, t.moraleVal * 2)) * this.valueOf(b, t) * (0.6 + ratio);
      cands.push({ action: 'rally', target: t.id, score });
    }
    // guard a ranged ally
    if (!underAssault && !b.isRanged(a)) for (const t of allies) {
      if (t === a || !b.isRanged(t) || b.isGuarded(t) || b.checkGuard(a, t)) continue;
      cands.push({ action: 'guard', target: t.id, score: 0.25 * t.count * this.valueOf(b, t) * 0.3 });
    }
    // deny: escape engagement if ranged
    for (const t of enemies) {
      if (b.checkDeny(a, t)) continue;
      const opts = b.denyOptions(a, t);
      opts.forEach((o, i) => {
        let score = 0;
        if (o.type === 'engage' && o.id === a.id && b.isRanged(a)) score = 0.6 * a.count * myVal * 0.3;
        if (o.type === 'adv' && t.adv >= 2) score = 0.1 * t.adv * t.count * this.valueOf(b, t) * 0.2;
        if (o.type === 'guard') score = 0.1 * bestAtt;
        if (score > 0) cands.push({ action: 'deny', target: t.id, opt: i, score });
      });
    }
    // retaliate: if enemies with melee can reach us
    const threats = enemies.filter(e => !b.isRanged(e)).length;
    if (threats && !b.isRanged(a)) cands.push({ action: 'retaliate', score: 0.25 * bestAtt + 0.05 * a.count * myVal * (a.def.sp.alwaysRetaliate ? 0 : 1) * 0.3 });
    // seek advantage baseline
    cands.push({ action: 'seek', score: 0.12 * Math.max(bestAtt, 0.3 * a.count * myVal * 0.3) + 0.01 });
    cands.sort((x, y) => y.score - x.score);
    return cands[0];
  },

  bestCast(b, side) {
    const sd = b.sides[side];
    if (!sd.hs) return null;
    const left = b.spellUsesLeft(side);
    let best = null;
    const consider = (id, t, score, t2) => { if (!b.checkCast(side, id, t, t2) && (!best || score > best.score)) best = { id, t, t2, score }; };
    const enemies = b.stacksOf(1 - side), allies = b.stacksOf(side);
    for (const id in left) {
      if (left[id] <= 0) continue;
      const sp = G.SPELLS[id], pm = b.spellPowerMult(side, id);
      for (const t of enemies) {
        const v = this.valueOf(b, t);
        if (id === 'flame') { const k = b.simulatePhys(t, sp.amount * pm); consider(id, t.id, k * v + 0.2); }
        if (id === 'dread') consider(id, t.id, 0.3 * v * 2 + 0.1);
        if (id === 'blunt' || id === 'misfortune' || id === 'diminish') consider(id, t.id, 0.08 * t.count * v);
        if (id === 'halve' || id === 'equalize') consider(id, t.id, 0.1 * t.count * v * (t.def.tier >= 3 ? 1.5 : 1));
      }
      for (const t of allies) {
        const v = this.valueOf(b, t);
        if (['sharpen', 'fortune', 'valor', 'quicken', 'haste'].includes(id)) {
          let s = 0.08 * t.count * v;
          if (id === 'quicken' && b.slowLevel(t) === 0) s = 0;
          if (id === 'valor') s *= 0.8;
          consider(id, t.id, s);
        }
        if (id === 'mend' && t.phys > 1) consider(id, t.id, Math.min(t.phys, sp.amount * pm) / b.health(t) * v * 0.6);
        if (id === 'ward') consider(id, t.id, 0.05 * t.count * v);
      }
    }
    return best;
  },
};
