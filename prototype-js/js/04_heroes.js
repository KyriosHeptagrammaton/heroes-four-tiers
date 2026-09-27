// ============================================================================
// Heroes: primary stats, secondary skills, spells, artifacts, XP rules.
// ============================================================================
G.Heroes = {
  create(cls, faction, name, rng) {
    const st = G.CFG.heroStart[cls];
    const r = rng || Math.random;
    const h = {
      id: G.util.uid('h'), name: name || G.HERO_NAMES[Math.floor((typeof r === 'function' ? r() : Math.random()) * G.HERO_NAMES.length)],
      cls, faction,
      stats: Object.assign({}, st),
      xp: { attack: 0, defence: 0, courage: 0, initiative: 0, power: 0, knowledge: 0 },
      skills: Object.assign({}, G.CLASSES[cls].skills),
      skillXp: {}, lastChosen: null, pendingSkillChoice: null,
      spellbook: cls === 'mage' ? ['flame', 'valor', 'sharpen', 'mend', 'dread', 'haste'] : ['flame', 'valor', 'mend'],
      equipped: [],
      artifacts: [],
      spellPower: {},
      level: 1,
    };
    for (const k in G.SKILLS) h.skillXp[k] = 0;
    h.equipped = this.autoEquip(h);
    return h;
  },

  stat(h, k) {
    let v = h.stats[k] || 0;
    for (const a of h.artifacts) { const A = G.ARTIFACTS[a]; if (A && A.stat && A.stat[k]) v += A.stat[k]; }
    if (k === 'initiative' && (h.skills.tactics || 0) >= 2) v += 1;
    return v;
  },
  has(h, art) { return !!h && h.artifacts.includes(art); },
  skill(h, k) { return (h && h.skills[k]) || 0; },

  // Hero initiative "0, 0+, 0++, 1, 1+ ..." (3 points = 1 initiative)
  initStr(v) { const whole = Math.floor(v / 3), pips = v - whole * 3; return whole + '+'.repeat(Math.max(0, pips)); },

  castsPerRound(h) { return [1, 2, 4, Infinity][this.skill(h, 'sorcery')]; },
  usesPerSpell(h) { return [1, 2, 4, Infinity][this.skill(h, 'arcana')]; },
  spellCost(h, id) { return G.SPELLS[id].cost * (this.usesPerSpell(h) === Infinity ? 2 : 1); },
  equippedCost(h, list) { return G.util.sum((list || h.equipped).map(id => this.spellCost(h, id))); },
  // Doc: with a spell book you may always have any ONE spell even if it exceeds knowledge
  canEquip(h, list) {
    if (list.length <= 1) return true;
    return this.equippedCost(h, list) <= this.stat(h, 'knowledge');
  },
  autoEquip(h) {
    const out = [];
    const prefs = ['flame', 'valor', 'sharpen', 'dread', 'mend', 'haste'];
    for (const p of prefs) if (h.spellbook.includes(p) && this.canEquip(h, out.concat([p]))) out.push(p);
    return out;
  },

  // ---- primary XP: "3 (skilled) or 4 (unskilled) x the next level" ----------
  primaryCost(h, k) {
    const skilled = G.CLASSES[h.cls].skilled.includes(k) || G.CLASSES[h.cls].flatPrimary;
    return (skilled ? 3 : 4) * (h.stats[k] + 1);
  },
  // Apply level-ups. Skilled skills first, then unskilled. On level up, add XP equal to the new
  // level to a random skill in the same category (skilled/unskilled), possibly the same one.
  applyPrimaryLevels(h, rng, log) {
    const r = rng || Math.random;
    const skilledSet = G.CLASSES[h.cls].skilled;
    const groups = [G.PRIMARY.filter(k => skilledSet.includes(k)), G.PRIMARY.filter(k => !skilledSet.includes(k))];
    let guard = 0, changed = true;
    while (changed && guard++ < 200) {
      changed = false;
      for (const grp of groups) {
        for (const k of grp) {
          const cost = this.primaryCost(h, k);
          if (h.xp[k] >= cost) {
            h.stats[k] += 1;
            // Paragon (doc "Beta hero specialty"): does not lose XP, so level N needs 3N total XP
            if (!G.CLASSES[h.cls].flatPrimary) h.xp[k] -= cost;
            if (log) log.push(`${h.name}: ${k} rises to ${h.stats[k]}`);
            if (grp.length) {
              const tgt = grp[Math.floor(r() * grp.length)];
              h.xp[tgt] += h.stats[k];
            }
            changed = true;
          }
        }
      }
    }
  },

  // ---- secondary skills ------------------------------------------------------
  // cost of next tier = 3 x tier, plus (known tier x 2) for every OTHER known skill
  skillCost(h, k) {
    const next = this.skill(h, k) + 1;
    let extra = 0;
    for (const o in h.skills) if (o !== k && h.skills[o] > 0) extra += G.CLASSES[h.cls].learner ? Math.max(0, h.skills[o] * 2 - 2) : h.skills[o] * 2;
    return 3 * next + extra;
  },
  skillMaxed(h, k) {
    const cur = this.skill(h, k), max = G.SKILLS[k].tiers.length;
    if (cur >= max) return true;
    // cannot reach infinite (tier 3) in both sorcery and arcana
    if (cur === 2 && ((k === 'sorcery' && this.skill(h, 'arcana') >= 3) || (k === 'arcana' && this.skill(h, 'sorcery') >= 3))) return true;
    return false;
  },
  readySkills(h) {
    if (G.CLASSES[h.cls].noSecondary) return [];
    return Object.keys(G.SKILLS).filter(k => !this.skillMaxed(h, k) && h.skillXp[k] >= this.skillCost(h, k));
  },
  // When 2+ skills are ready, offer a choice between two of them (never the one chosen last time)
  maybeOfferSkill(h, rng) {
    if (h.pendingSkillChoice) return h.pendingSkillChoice;
    let ready = this.readySkills(h).filter(k => k !== h.lastChosen);
    if (ready.length < 2) return null;
    const r = rng || Math.random;
    ready = ready.slice();
    for (let i = ready.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [ready[i], ready[j]] = [ready[j], ready[i]]; }
    h.pendingSkillChoice = [ready[0], ready[1]];
    return h.pendingSkillChoice;
  },
  chooseSkill(h, pick) {
    const pair = h.pendingSkillChoice; if (!pair) return;
    const other = pair[0] === pick ? pair[1] : pair[0];
    const cost = this.skillCost(h, pick);
    h.skillXp[pick] -= cost;
    h.skillXp[other] = Math.max(0, h.skillXp[other] - cost);
    h.skills[pick] = (h.skills[pick] || 0) + 1;
    h.lastChosen = pick;
    h.pendingSkillChoice = null;
    // infinite uses doubles spell costs: re-validate equipment
    if (!this.canEquip(h, h.equipped)) { while (h.equipped.length > 1 && !this.canEquip(h, h.equipped)) h.equipped.pop(); }
  },
  addSkillXp(h, cat, n) {
    if (!n) return;
    for (const k in G.SKILLS) if (G.SKILLS[k].cat === cat) h.skillXp[k] = (h.skillXp[k] || 0) + n;
  },
  totalLevel(h) { return G.util.sum(G.PRIMARY.map(k => h.stats[k])); },
};
G.flag('primary-category', 'Heroes', '"Randomly add experience to a skill in the same category" read as: same category = the hero\'s skilled group or unskilled group.');
