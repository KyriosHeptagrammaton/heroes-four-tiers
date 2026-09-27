// ============================================================================
// Tunable numbers. Anything here that is not from the design doc is flagged.
// ============================================================================
G.CFG = {
  // --- combat (from doc) ---
  perUnitAttDefBonus: 0.05,     // every unit in a stack adds 5% to base attack/defence
  perUnitMoraleBonus: 0.10,     // ...and 10% to morale
  attPerPoint: 0.10, attCap: 3.0,   // +10% dmg per attack point over defence, max +300%
  defPerPoint: 0.05, defCap: 0.75,  // -5% per defence point over attack, max -75%
  moraleShare: 0.75,            // 75% of a hit goes to morale, 25% to health
  minDice: 3,                   // roll 1dX with X = max(3, units)
  maxStacks: 6,
  heroUnitFraction: 1 / 3,      // stack becomes heroes at <= 1/3 of starting size
  heroUnitAlways: 2,            // stacks of 1-2 are always heroes
  heroUnitBonus: { att: 1, def: 1, dmg: 1, mor: 1 },
  spellPowerPct: 0.10,          // +10% per power to non-utility spells
  roundCap: 60,

  // --- overworld / economy ---
  mapSize: 20,
  growth: { 1: 6, 2: 3, 3: 2, 4: 1 },   // doc: 6 / 3 / 2 / 1
  speed: { cavalry: 12, normal: 6, slow: 4 },
  transcendentPerPlayer: 9,
  sightDefault: 3,
  sightScale: 1,         // sight is measured in tiles (user); was halved when measured in cards
  scoutTilesPerXP: 10,   // user: scouting XP divided by 10 (1 XP per 10 tiles revealed)
};

// ---- invented numbers (flagged) --------------------------------------------
G.CFG.unitPrice = { 1: 30, 2: 80, 3: 200, 4: 800 };
G.flag('price', 'Economy', 'Unit gold prices (T1 30, T2 80, T3 200, T4 800) are placeholders.');
G.CFG.priceEscalation = [1, 2, 3, 4, 5]; // weekly growth at x1, next batch x2, next x3...
G.flag('escalation', 'Economy', 'Buying past the weekly growth: each further "week-sized batch" costs x2, x3, x4... Doc only says "doubles then triples or whatever".');
G.CFG.upgradeFee = { 1: 20, 2: 50, 3: 120, 4: 400 };
G.flag('upgradefee', 'Economy', 'Upgrade gold fee per creature (T1 20, T2 50, T3 120, T4 400) plus 1 essence of that tier per creature.');
G.CFG.startGold = 2500;
G.CFG.townIncome = 500;
G.flag('income', 'Economy', 'Town base income 500 gold/day, start with 2500 gold.');
G.CFG.heroCost = 1500;
G.CFG.trainCost = 300;
G.flag('trainrules', 'Overworld', 'Supply train: with train you may only walk on roads and have -1 movement. Parking the train lets you go off-road (still -1 movement) but your units get -1 morale and lose 1 creature from the largest stack per day (attrition) until you return to it. Wounded ride in the train; if an enemy walks over a parked train it is destroyed with its wounded. A new train costs 300 gold in town.');
G.CFG.monsterFlee = true;
G.CFG.essenceMinusXP = false;
G.flag('essence', 'Economy', 'Upgrade essence: +1 essence of tier N per tier-N enemy creature killed. The doc also says "-1 per primary skill experience gained" but attack XP alone equals kills x tier, which would cancel essence completely, so that subtraction is OFF (toggle G.CFG.essenceMinusXP).');

G.CFG.heroStart = {
  warlord: { attack: 1, defence: 1, courage: 5, initiative: 3, power: 0, knowledge: 3 },
  mage:    { attack: 0, defence: 0, courage: 4, initiative: 3, power: 2, knowledge: 6 },
  paragon: { attack: 1, defence: 1, courage: 4, initiative: 3, power: 1, knowledge: 4 },
  scholar: { attack: 0, defence: 1, courage: 4, initiative: 3, power: 1, knowledge: 5 },
};
G.flag('herostart', 'Heroes', 'Starting primary stats per class are placeholders (courage ~5 because every stack costs 1 courage in battle).');
G.flag('neutralcourage', 'Combat', 'Neutral armies (no hero) fight with courage 0 and do not pay the -1 courage per stack.');
G.flag('villageX', 'Terrain', 'Village: defender gains a militia stack of 6 tier-1s of its faction. Crossroads: both sides gain 4 tier-1 mercenaries. ("X" was open in the doc.)');
G.CFG.villageMilitia = 6; G.CFG.crossroadsMercs = 4;
G.flag('wallX', 'Terrain', 'Town walls: wall has 12 HP per defending stack; every 12 damage it protects one fewer defender (bottom first).');
G.CFG.wallPerStack = 12;
