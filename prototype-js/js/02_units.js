// ============================================================================
// Units: four factions (Alpha, Beta, Gamma, Delta), tiers 1-4.
// Stats are taken verbatim from the design doc where given.
// Key format:  faction.tier.up.mod    up: 0 base, 1 first upgrade, 2 second
//              mod: '' (melee), 'r' (ranged modifier), 'm' (magi modifier)
// Riders:      riderKey@mountKey
// ============================================================================
G.FACTIONS = {
  alpha: { name: 'Alpha', color: '#d0543f', glyph: 'α' },
  beta:  { name: 'Beta',  color: '#3f7fd0', glyph: 'β' },
  gamma: { name: 'Gamma', color: '#3fa64f', glyph: 'γ' },
  delta: { name: 'Delta', color: '#9a52c9', glyph: 'δ' },
};
G.FACTION_IDS = ['alpha', 'beta', 'gamma', 'delta'];

// Base forms and "Melee I" deltas straight from the doc.
G.UNIT_BASE = {
  alpha: {
    1: { hp: 1, mor: 2, dmg: [1, 2, 3], ini: 1, att: 5, def: 5, w: 1, s: 1, sp: { lossMoraleHeal: 2 },
         I: { sp: { lossMoraleHeal: 4 } } },
    2: { hp: 2, mor: 4, dmg: [1, 2.5, 4], ini: 2, att: 7.5, def: 7.5, w: 3, s: 3, ab: { cavalry: true }, sp: { split5050: true },
         I: { dmg: [1, 3, 5] } },
    3: { hp: 3, mor: 4, dmg: [3, 4, 5], ini: 4, att: 10, def: 10, w: 2, s: 2, sp: { lossGainMorale: true, regenPerUnit: true },
         I: { sp: { moraleCasualtiesRejoin: true } } },
    4: { hp: 6, mor: 12, dmg: [6, 8, 10], ini: 4, att: 20, def: 20, w: 4, s: 4, sp: { dmgAuraMinus1: true, advPerTurn: true } },
  },
  beta: {
    1: { hp: 1, mor: 2, dmg: [1, 1, 3], ini: 1, att: 5, def: 5, w: 1, s: 1, sp: { crit: 2 },
         I: { dmg: [1, 1, 4], sp: { crit: 4 } } },
    2: { hp: 2, mor: 4, dmg: [2, 3, 4], ini: 2, att: 7.5, def: 7.5, w: 3, s: 3, ab: { cavalry: true }, sp: { extraMoraleDmg: true },
         I: { mor: 5 } },
    3: { hp: 4, mor: 6, dmg: [4, 4, 5], ini: 3, att: 12, def: 12, w: 2, s: 2, sp: {},
         I: { hp: 5, mor: 9, dmg: [4, 5, 5], att: 13, def: 13 } },
    4: { hp: 6, mor: 12, dmg: [6, 8, 10], ini: 4, att: 20, def: 20, w: 4, s: 4, sp: { scatterOnStart: true, fleeOnAttack: true } },
  },
  gamma: {
    1: { hp: 1, mor: 2, dmg: [1, 2, 3], ini: 1, att: 5, def: 5, w: 1, s: 1, ab: { slow: 1 }, sp: { advAfterGuard: true, firstOnTie: true },
         I: { ini: 2, sp: { firstStrikeRetaliate: true } } },
    2: { hp: 3, mor: 4, dmg: [2, 3, 4], ini: 2, att: 7.5, def: 7.5, w: 3, s: 3, ab: { cavalry: true, mountKeepsSlow: true },
         sp: { engageAfterAttack: true, extraDamageTaken: true, killMoraleHeal: true, bigKillMorale: true, keepAdvOnAttack: true },
         I: { sp: { negMoraleOverflow: true, extraDamageOnlyIfAttLE: true } } },
    3: { hp: 0, mor: 1, dmg: [4, 5, 6], ini: 1, att: 8, def: 12, w: 4, s: 1, ab: { slow: 1 },
         sp: { gainHealthOnKill: 'gt', moralePerTurn: 1, counterEngage: 'melee', fallbackRecover: true, doubleGrowth: true },
         I: { dmg: [4, 6, 6], sp: { gainHealthOnKill: 'ge', counterEngage: 'any' } } },
    4: { hp: 6, mor: 12, dmg: [6, 8, 10], ini: 4, att: 20, def: 20, w: 4, s: 4, sp: { ignoreNegSpecials: true, moraleAura: 1 } },
  },
  delta: {
    1: { hp: 1, mor: 2, dmg: [1, 1.5, 2], ini: 1, att: 5, def: 5, w: 1, s: 1, sp: { necroPhys: 'base' },
         I: { sp: { necroPhys: 'melee' } } },
    2: { hp: 2, mor: 4, dmg: [2, 3, 4], ini: 2, att: 7.5, def: 7.5, w: 3, s: 3, sp: { alwaysRetaliate: true },
         I: { dmg: [2, 3.5, 5] } },
    3: { hp: 3, mor: 6, dmg: [3, 4, 5], ini: 3, att: 10, def: 10, w: 2, s: 2, sp: { rallyConvert: true },
         I: { mor: 8 } },
    4: { hp: 6, mor: 12, dmg: [6, 8, 10], ini: 4, att: 20, def: 20, w: 4, s: 4, sp: { courageHealth: true, rallyEnemy: true } },
  },
};
G.flag('gamma3dmg', 'Units', 'Gamma T3 damage written "546" / Melee I "646": read as min-mid-max 4-5-6 and 4-6-6.');
G.flag('delta2mi', 'Units', 'Delta T2 Melee I damage "23.55" read as 2 / 3.5 / 5.');
G.flag('delta4rally', 'Units', 'Delta T4 "rallying applies negative morale instead of positive": its Rally may target an ENEMY stack, dealing 2x its morale as morale damage (it can still rally friends normally).');
G.flag('delta1', 'Units', 'Delta T1: whenever ANY other stack loses creatures to physical damage and that stack\'s tier >= this tier, gain 1 creature (Melee I: gain floor(lost tier / this tier)). Magi: gain 1 creature per creature that dies anywhere.');
G.CFG.beta2PerCreature = true;
G.flag('beta2', 'Units', 'Beta T2 "additional morale damage equal to its current morale" is applied per creature (x stack size). In AI-vs-AI sims this makes Beta win almost every matchup. Toggle G.CFG.beta2PerCreature = false to add it once per attack instead.');
G.flag('alpha3regen', 'Units', 'Alpha T3 "remove damage equal to number of units at start of turn" removes PHYSICAL damage.');

// Magi: one unique effect per faction per tier (user). Doc gave some; others picked from the doc's ability list.
G.MAGI = {
  alpha: { 1: { rallyHealsPhys: true }, 2: { attackAllEngaged: true }, 3: { extraTurnNonAttack: true }, 4: { doubleBonuses: true } },
  beta:  { 1: { thorns: true }, 2: { denyMulti: true }, 3: { twoTurns: true }, 4: { lastStandConvert: true } },
  gamma: { 1: { guardVsRanged: true }, 2: { lifesteal: true }, 3: { dmgAuraMinus1: true }, 4: { killRecoverDeserter: true } },
  delta: { 1: { necroAny: true }, 2: { rallyBoost: true }, 3: { allPhysical: true }, 4: { purgeMoraleOnTurn: true } },
};
G.flag('magi-invented', 'Units', 'Magi effects NOT in the doc (taken from the doc\'s ability list): Alpha1 rally also heals physical = stack size; Alpha2 attacks all engaged units; Alpha4 double bonuses from numbers & advantage; Beta1 deals damage = its size when attacked; Beta2 deny strips (advantage+1) advantages; Beta4 lethal physical converts to morale; Gamma4 each kill recovers a deserter; Delta2 morale +50% for rallying; Delta4 clears all morale damage at turn start.');
G.flag('magi-stats', 'Units', 'Magi (and Ranged) versions use the Melee I stats + their modifier. T4 Magi uses T4 base stats + effect.');

// Which second upgrade each town offers per tier (doc: "ranged or not ranged ... depending on the town")
G.SECOND_UPGRADE = {
  alpha: { 1: '', 2: '', 3: 'r' },
  beta:  { 1: 'r', 2: '', 3: '' },
  gamma: { 1: '', 2: '', 3: 'r' },
  delta: { 1: 'r', 2: '', 3: 'r' },
};
G.flag('secondup-choice', 'Units', 'Which 2nd upgrade (melee II or ranged II) each town offers per tier was chosen arbitrarily.');
G.flag('upgrade2', 'Units', 'PLACEHOLDER ⚑: second upgrades (and the T4 normal upgrade) just add "+1" bonuses (attack 5+1, defence 5+1, morale +1). Needs real design.');

G.SPECIAL_TEXT = {
  lossMoraleHeal: v => `Each creature lost removes ${v} morale damage from this stack`,
  split5050: () => 'Its damage is split 50/50 between morale and health',
  lossGainMorale: () => 'Gains +1 morale each time it loses a creature',
  regenPerUnit: () => 'Start of turn: removes physical damage equal to its size',
  moraleCasualtiesRejoin: () => 'After battle all its deserters rejoin the army',
  dmgAuraMinus1: () => 'Creatures attacking it have -1 damage',
  advPerTurn: () => 'Gains 1 advantage at the start of each turn',
  crit: v => `Critical: +${v} to its damage roll when trying to roll the top face (maximum damage)`,
  extraMoraleDmg: () => 'Deals extra morale damage equal to its current morale',
  scatterOnStart: () => 'Start of combat: 1 creature flees from every other stack (both sides)',
  fleeOnAttack: () => 'When it attacks, 1 creature flees the target first',
  advAfterGuard: () => 'Gains 1 advantage after guarding',
  firstOnTie: () => 'Acts first when tied on initiative with allies',
  firstStrikeRetaliate: () => 'Strikes first when retaliating',
  engageAfterAttack: () => 'Engages its target after attacking',
  extraDamageTaken: () => 'Takes 1 extra damage whenever it is hit',
  extraDamageOnlyIfAttLE: () => '...but not if the attacker\'s attack beats its defence',
  killMoraleHeal: () => 'Removes morale damage = tier x creatures it kills',
  bigKillMorale: () => '+1 morale for every tier 3+ creature it kills',
  keepAdvOnAttack: () => 'Does not lose advantage when attacking',
  negMoraleOverflow: () => 'Morale recovery with no morale damage becomes a buffer (half)',
  gainHealthOnKill: v => `+1 health when it kills a creature with ${v === 'ge' ? '>=' : 'more'} health`,
  moralePerTurn: v => `+${v} morale at the start of each turn`,
  counterEngage: v => `Engages anything that ${v === 'any' ? 'attacks' : 'melee-attacks'} it`,
  fallbackRecover: () => 'Recovers 1 deserter when it falls back',
  doubleGrowth: () => 'Twice the weekly growth',
  ignoreNegSpecials: () => 'Ignores enemy specials that would hurt it',
  moraleAura: v => `+${v} morale to all other friendly stacks`,
  necroPhys: v => v === 'melee' ? 'When another stack loses creatures to damage, gains (its tier / this tier) creatures' : 'When a stack of equal/higher tier loses creatures to damage, gains 1 creature',
  alwaysRetaliate: () => 'Always retaliates when attacked',
  rallyConvert: () => 'Its rally removes physical damage first, turning it into 2x morale damage',
  courageHealth: () => 'Courage also applies to health casualties',
  rallyEnemy: () => 'Its rally can target enemies (deals morale damage)',
  rallyHealsPhys: () => 'Magi: its rally also removes physical damage = its size',
  attackAllEngaged: () => 'Magi: attacks every unit it is engaged with',
  extraTurnNonAttack: () => 'Magi: after any non-attack action, acts again at initiative 2',
  doubleBonuses: () => 'Magi: double bonus from numbers and advantage',
  thorns: () => 'Magi: deals damage equal to its size to attackers',
  denyMulti: () => 'Magi: deny strips (its advantage + 1) advantages',
  twoTurns: () => 'Magi: acts twice each round',
  lastStandConvert: () => 'Magi: damage that would destroy the stack becomes morale damage',
  guardVsRanged: () => 'Magi: its guard also blocks ranged attacks',
  lifesteal: () => 'Magi: heals physical damage equal to the physical damage it deals',
  killRecoverDeserter: () => 'Magi: each kill recovers one deserter',
  necroAny: () => 'Magi: gains 1 creature whenever any creature dies',
  rallyBoost: () => 'Magi: morale counts 50% higher for rallying',
  allPhysical: () => 'Magi: converts all its damage into physical damage',
  purgeMoraleOnTurn: () => 'Magi: removes all its morale damage at turn start',
};
G.ABILITY_TEXT = {
  ranged: 'Ranged: may hit guarded units without losing guard/advantage; cannot be attacked or engaged in round 1 except by cavalry',
  cavalry: 'Cavalry: only cavalry may engage it; may engage guarded units unless guarded by cavalry',
  fly: 'Flying: may attack guarded units',
  teleport: 'Teleport: may attack guarded units',
  slow: 'Slow: may not attack in the first round(s) unless engaged with the target',
};

// Proper names for units (others fall back to "Faction tier N")
G.UNIT_NAMES = {
  'alpha.1': 'Berserker',
  'alpha.2': 'Dire Wolf',
  'alpha.3': 'Troll',
  'beta.1': 'Martial Saint',
  'beta.2': 'Lion',
  'beta.3': 'Archon',
  'gamma.1': 'Pikeman',
  'gamma.2': 'War Horse',
  'gamma.4': 'Angel',
  'delta.1': 'Skeleton',
  'delta.2': 'Giant Scorpion',
};

G.Units = {
  cache: {},
  key(f, t, up = 0, mod = '') { return `${f}.${t}.${up}.${mod}`; },
  parse(key) { const [f, t, up, mod] = key.split('.'); return { faction: f, tier: +t, up: +up, mod: mod || '' }; },

  resolve(key) {
    if (this.cache[key]) return this.cache[key];
    let d;
    if (key.includes('@')) d = this.resolveRider(key);
    else d = this.resolveSingle(key);
    this.cache[key] = d;
    return d;
  },

  resolveSingle(key) {
    const p = this.parse(key);
    const base = G.UNIT_BASE[p.faction][p.tier];
    const d = {
      key, faction: p.faction, tier: p.tier, up: p.up, mod: p.mod,
      hp: base.hp, mor: base.mor, dmg: base.dmg.slice(), ini: base.ini, att: base.att, def: base.def, w: base.w, s: base.s,
      ab: Object.assign({}, base.ab || {}), sp: Object.assign({}, base.sp || {}),
      flatAtt: 0, flatDef: 0, flatMor: 0, placeholder: false, mounted: false,
    };
    const baseMin = base.dmg[0];
    if (p.up >= 1 && base.I) {
      const I = base.I;
      for (const k of ['hp', 'mor', 'ini', 'att', 'def', 'w', 's']) if (I[k] !== undefined) d[k] = I[k];
      if (I.dmg) d.dmg = I.dmg.slice();
      if (I.sp) Object.assign(d.sp, I.sp);
      if (I.ab) Object.assign(d.ab, I.ab);
    }
    if (p.up >= 1 && p.tier === 4 && p.mod !== 'm') { d.flatAtt += 1; d.flatDef += 1; d.flatMor += 1; d.placeholder = true; }
    if (p.up >= 2) { d.flatAtt += 1; d.flatDef += 1; d.flatMor += 1; d.placeholder = true; }
    if (p.mod === 'r') { d.ab.ranged = true; d.dmg[0] = baseMin / 2; }
    if (p.mod === 'm') Object.assign(d.sp, G.MAGI[p.faction][p.tier]);
    d.name = this.nameFor(p);
    d.baseKey = this.key(p.faction, p.tier, 0, '');
    return d;
  },

  // Plain descriptive names: "Alpha tier 1", "Alpha tier 2 Ranged I", "Beta tier 3 Magi"...
  // unless the unit has a proper name in G.UNIT_NAMES (upgrades keep it: "Troll Ranged I").
  nameFor(p) {
    let s = G.UNIT_NAMES[p.faction + '.' + p.tier] || `${G.FACTIONS[p.faction].name} tier ${p.tier}`;
    if (p.mod === 'm') return s + ' Magi';
    if (p.up >= 1) s += ` ${p.mod === 'r' ? 'Ranged' : p.tier === 4 ? 'Upgraded' : 'Melee'} ${p.up >= 2 ? 'II' : 'I'}`;
    return s;
  },

  // Doc: rider/mount combination rules
  resolveRider(key) {
    const [rk, mk] = key.split('@');
    const R = this.resolve(rk), M = this.resolve(mk);
    const mounts = Math.ceil(R.w / M.s);
    const models = [R].concat(Array(mounts).fill(M));
    const avg = f => G.util.sum(models.map(f)) / models.length;
    // damage: lowest, mode of all constituent models (or rider's if none), highest
    const mids = models.map(m => m.dmg[1]);
    const counts = {}; mids.forEach(v => counts[v] = (counts[v] || 0) + 1);
    let best = null, bestN = 0, tie = false;
    for (const v in counts) { if (counts[v] > bestN) { best = +v; bestN = counts[v]; tie = false; } else if (counts[v] === bestN) tie = true; }
    const mid = (tie || bestN <= 1) ? R.dmg[1] : best;
    let slow = (R.ab.slow || 0) + (M.ab.slow || 0) + mounts;
    if (M.ab.cavalry && !M.ab.mountKeepsSlow) slow -= 1;
    const d = {
      key, faction: R.faction, tier: R.tier + mounts * M.tier, up: R.up, mod: R.mod,
      hp: Math.max(M.hp * mounts, R.hp),
      mor: Math.round(avg(m => m.mor)),
      dmg: [Math.min(...models.map(m => m.dmg[0])), mid, Math.max(...models.map(m => m.dmg[2]))],
      ini: M.ini,
      att: Math.round(Math.max(R.att, avg(m => m.att))),
      def: Math.round(Math.max(M.def, avg(m => m.def))),
      w: 1, s: 1,
      ab: { ranged: !!R.ab.ranged, cavalry: !!M.ab.cavalry, fly: !!M.ab.fly, teleport: !!R.ab.teleport, slow: Math.max(0, slow) },
      sp: Object.assign({}, M.sp, R.sp),
      flatAtt: R.flatAtt, flatDef: M.flatDef, flatMor: Math.max(R.flatMor, M.flatMor),
      placeholder: R.placeholder || M.placeholder,
      mounted: true, riderKey: rk, mountKey: mk, mountsPer: mounts,
      name: `${R.name} on ${M.name}`, baseKey: R.baseKey,
    };
    d.mid = mid;
    return d;
  },

  // Human readable stat line pieces with "+1" placeholder style
  statStr(d, stat) {
    const flat = { att: d.flatAtt, def: d.flatDef, mor: d.flatMor }[stat] || 0;
    const v = G.util.fmt(d[stat]);
    return flat ? `${v}+${flat}` : v;
  },

  allBaseKeys() {
    const out = [];
    for (const f of G.FACTION_IDS) for (let t = 1; t <= 4; t++) out.push(this.key(f, t, 0, ''));
    return out;
  },

  // Every legal single-unit variant for a faction/tier
  variants(f, t) {
    if (t === 4) return [this.key(f, 4, 0, ''), this.key(f, 4, 1, ''), this.key(f, 4, 1, 'm')];
    const out = [this.key(f, t, 0, ''), this.key(f, t, 1, ''), this.key(f, t, 1, 'r'), this.key(f, t, 1, 'm')];
    out.push(this.key(f, t, 2, ''), this.key(f, t, 2, 'r'));
    return out;
  },

  value(d) { return ({ 1: 1, 2: 2, 3: 3, 4: 6 })[Math.min(4, d.tier)] || d.tier * 1.5; },
};
G.flag('rider-specials', 'Units', 'Riders: combined unit keeps the specials of both rider and mount; ranged/teleport come from the rider, cavalry/fly from the mount. Combined tier = rider + mounts. Cost = 1 rider + N mounts from your army.');
