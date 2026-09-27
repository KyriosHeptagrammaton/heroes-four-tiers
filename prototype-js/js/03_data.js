// ============================================================================
// Spells, terrain, time of day, weather, secondary skills, artifacts, classes
// ============================================================================

// kind: 'utility' (scales with creature numbers by nature) or 'damage' (scales with Power +10%/pt)
// stack: true = unlimited stacking, false = one instance, 'copies' = max levels = copies equipped
// target: 'stack' | 'ally' | 'enemy' | 'stackOrHero' | 'pair'
G.SPELLS = {
  quicken:   { name: 'Quicken',    cost: 2, kind: 'utility', stack: true,  target: 'stack', desc: 'Target loses one slow.' },
  valor:     { name: 'Valor',      cost: 4, kind: 'utility', stack: true,  target: 'stack', desc: '+1 morale.' },
  sharpen:   { name: 'Sharpen',    cost: 3, kind: 'utility', stack: 'copies', target: 'stack', desc: '+1 damage. Max levels = copies of this spell you have equipped.' },
  blunt:     { name: 'Blunt',      cost: 3, kind: 'utility', stack: 'copies', target: 'stack', desc: '-1 damage. Max levels = copies equipped.' },
  fortune:   { name: 'Fortune',    cost: 6, kind: 'utility', stack: false, target: 'stack', desc: 'Always does maximum damage.' },
  misfortune:{ name: 'Misfortune', cost: 6, kind: 'utility', stack: false, target: 'stack', desc: 'Always does minimum damage.' },
  transfer:  { name: 'Transference', cost: 4, kind: 'utility', instant: true, target: 'pair', desc: 'Move ALL morale damage from one stack onto another.' },
  flame:     { name: 'Flame',      cost: 2, kind: 'damage', instant: true, target: 'stack', amount: 5, desc: '5 physical damage (x power).' },
  dread:     { name: 'Dread',      cost: 2, kind: 'damage', instant: true, target: 'stack', amount: 10, desc: '10 damage, split 75% morale / 25% health (x power).' },
  haste:     { name: 'Haste',      cost: 4, kind: 'utility', stack: true,  target: 'stackOrHero', desc: '+1 initiative. May be cast on heroes.' },
  ward:      { name: 'Ward',       cost: 3, kind: 'damage', instant: true, target: 'stack', amount: 3, desc: '3 negative physical damage (a buffer, x power).' },
  mend:      { name: 'Mend',       cost: 1, kind: 'damage', instant: true, target: 'stack', amount: 5, desc: 'Remove 5 physical damage (x power).' },
  dispel:    { name: 'Dispel',     cost: 4, kind: 'utility', instant: true, target: 'stack', desc: 'Remove all spell effects on target.' },
  equalize:  { name: 'Equalize',   cost: 5, kind: 'utility', stack: false, target: 'stack', desc: 'Attack and defence become 10.' },
  diminish:  { name: 'Diminish',   cost: 2, kind: 'utility', stack: true,  target: 'stack', desc: 'Stack counts as having one less creature.' },
  halve:     { name: 'Halve',      cost: 6, kind: 'utility', stack: false, target: 'stack', desc: 'Stack counts as having half as many creatures.' },
};
G.flag('spellcosts', 'Spells', 'Knowledge costs for Equalize (5), Diminish (2) and Halve (6) were not in the doc. Spell names are invented.');
G.flag('spellscale', 'Spells', 'Only "damage" spells (Flame, Dread, Ward, Mend) scale with Power (+10%/pt). Everything else scales with creature numbers.');
G.flag('commander', 'Combat', 'Commander actions (instead of a spell): Recall (spend courage = tier to return 1 deserter), Revive (spend spare knowledge = tier to revive 1 dead), Embolden (spend an initiative pip for +1 advantage), Steel (+1 courage; the doc asked about +0.5, raised to 1 so all numbers stay whole).');

// ---- Terrain ---------------------------------------------------------------
// size: NxN interior sub-tiles of the overworld card; sight: bonus when standing on it; vis: seen from this far
G.TERRAIN = {
  plains:     { name: 'Plains', size: 1, sight: 1, vis: 3, color: '#c9d48a', fx: { slowMod: -1 }, desc: 'All units lose one slow.' },
  field:      { name: 'Field', size: 2, sight: 0, vis: 3, color: '#b2c56e', fx: {}, desc: 'No effect.' },
  forest:     { name: 'Forest', size: 3, sight: -1, vis: 3, color: '#4f8a45', fx: { noRanged: 1, noCavalry: 1 }, desc: 'All units lose ranged and cavalry.' },
  hill:       { name: 'Hills', size: 2, sight: 2, vis: 5, color: '#a9a26a', fx: { defAdv: 1, attNoCavR1: 1 }, desc: 'Defenders start with 1 advantage; attackers lose cavalry in round 1.' },
  canyon:     { name: 'Box Canyon', size: 2, sight: -1, vis: 3, color: '#b87a4b', fx: { defMoraleX: 4, desertersDie: 1 }, desc: 'Defenders get quadruple morale; morale casualties become physical casualties.' },
  ashlands:   { name: 'Ashlands', size: 2, sight: 0, vis: 3, color: '#6d5f5a', fx: { physPerRound: 3 }, desc: 'All units take 3 / tier physical damage each round.' },
  moor:       { name: 'Haunted Moor', size: 3, sight: -1, vis: 3, color: '#7a8a8a', fx: { moraleDmgPerRound: 9 }, desc: 'All units take 9 / tier morale damage each round.' },
  steppe:     { name: 'Steppe', size: 1, sight: 1, vis: 4, color: '#d8c98a', fx: { allCavalry: 1 }, desc: 'All units count as cavalry.' },
  badlands:   { name: 'Badlands', size: 2, sight: 1, vis: 3, color: '#c29a6b', fx: { allRanged: 1 }, desc: 'All units count as ranged.' },
  escarpment: { name: 'Escarpment', size: 2, sight: 2, vis: 5, color: '#9c8f70', fx: { defRanged: 1 }, desc: 'All defenders count as ranged.' },
  bluffs:     { name: 'Bluffs', size: 2, sight: 1, vis: 4, color: '#b3a07d', fx: { defRanged: 1, attCavalry: 1 }, desc: 'Defenders count as ranged, attackers count as cavalry.' },
  swamp:      { name: 'Swamp', size: 4, sight: -1, vis: 2, color: '#5d7a55', fx: { slowMod: 1 }, desc: 'All units gain one slow.' },
  tundra:     { name: 'Tundra', size: 3, sight: 0, vis: 3, color: '#dfe8ec', fx: { slowModNonRanged: 1 }, desc: 'All units except ranged gain one slow.' },
  dreamwood:  { name: 'Dreamwood', size: 3, sight: -1, vis: 3, color: '#6f5d95', fx: { swapDamage: 1 }, desc: 'Physical and morale damage are reversed.' },
  stones:     { name: 'Standing Stones', size: 1, sight: 0, vis: 3, color: '#a3a3b3', fx: { keepAdv: 1 }, desc: 'Units do not lose advantages.' },
  village:    { name: 'Village', size: 2, sight: 0, vis: 3, color: '#c8b27a', fx: { defMilitia: 1 }, desc: 'Defender gains a stack of militia.' },
  watchfort:  { name: 'Watchfort', size: 1, sight: 3, vis: 5, color: '#9a8a6a', fx: { defHalfRanged: 1 }, desc: 'Defenders all gain a ranged attack at half damage.' },
  crossroads: { name: 'Crossroads', size: 1, sight: 0, vis: 3, color: '#cdbb8e', fx: { bothMercs: 1 }, desc: 'Defender and attacker each gain a stack of mercenaries.' },
  grove:      { name: 'Sacred Grove', size: 2, sight: -1, vis: 3, color: '#79b36a', fx: { noPhysical: 1 }, desc: 'Units cannot take physical damage.' },
  arena:      { name: 'Old Arena', size: 1, sight: 0, vis: 3, color: '#c9a58a', fx: { attDef10: 1 }, desc: 'Attack and defence are 10 for all units.' },
  nexus:      { name: 'Ley Nexus', size: 1, sight: 0, vis: 4, color: '#8fb4d9', fx: { doublePower: 1 }, desc: "Double the commanders' power." },
  mountain:   { name: 'Mountains', size: 3, sight: 6, vis: 9, color: '#8a8580', occlude: true, fx: { defRanged: 1 }, desc: 'Blocks sight behind it. Defenders count as ranged.' },
  chasm:      { name: 'Chasm', size: 1, sight: 0, vis: 3, color: '#2b2622', impassable: true, fx: {}, desc: 'Impassable (Logistics II lets an army cross).' },
  town:       { name: 'Town', size: 2, sight: 1, vis: 4, color: '#c9b79a', fx: { walls: 1 }, desc: 'Walls protect the defenders.' },
};
G.flag('terrain-names', 'Terrain', 'Terrain names for the unnamed doc effects are invented (Ashlands, Haunted Moor, Steppe, Badlands, Escarpment, Bluffs, Tundra, Dreamwood, Standing Stones, Village, Watchfort, Crossroads, Sacred Grove, Old Arena, Ley Nexus). Card sizes/sight numbers are placeholders except mountain (+6 / seen from 9) and forest (-1).');
G.flag('mountain-fx', 'Terrain', 'Mountain battles use "defenders count as ranged"; Tundra = "all except archers gain one slow"; Swamp = "all units gain one slow".');

G.TIMES = {
  dawn:   { name: 'Dawn',   fx: {}, desc: 'No change.' },
  midday: { name: 'Midday', fx: { slowMod: -1 }, desc: 'All units lose one slow.' },
  dusk:   { name: 'Dusk',   fx: { attackerInit: 1 }, desc: 'All attacking units (and commander) +1 initiative.' },
  night:  { name: 'Night',  fx: { moraleHalf: 1, noRanged: 1 }, desc: 'Morale is halved; all units lose ranged.' },
};
G.flag('dusk', 'Terrain', 'The unnamed attacker time effect "+1 initiative to own units incl. commander" is called Dusk.');
G.WEATHER = {
  clear: { name: 'Clear', fx: {}, desc: 'No effect.' },
  rain:  { name: 'Rain',  fx: { rangedSlow: 1 }, desc: 'All ranged units are slow.' },
};
G.CFG.rainChance = 0.25;

// ---- Secondary skills --------------------------------------------------------
// cat decides how XP is earned: martial (+1 per fight & per round), magic (+1 per spell cast),
// scouting (+1 per 10 tiles revealed), logistics (+1 per card entered), craft (+1 per upgrade / battle won)
G.SKILLS = {
  sorcery:     { name: 'Spellweaving', cat: 'magic', tiers: ['Cast 2 spells per round', 'Cast 4 spells per round', 'Cast unlimited spells per round'] },
  arcana:      { name: 'Deep Memory', cat: 'magic', tiers: ['Each equipped spell usable 2x per battle', '4x per battle', 'Unlimited uses (knowledge cost doubles)'] },
  heroics:     { name: 'Heroics', cat: 'martial', tiers: ['Stacks become heroes below 50%; 3 or fewer is always a hero', '6 or fewer is always a hero', '12 or fewer is always a hero'] },
  warding:     { name: 'Warding', cat: 'martial', tiers: ['All creatures start combat with 3 negative physical damage', '6', '12'] },
  inspiration: { name: 'Inspiration', cat: 'martial', tiers: ['All creatures +1 morale', '+2 morale', '+4 morale'] },
  horsemanship:{ name: 'Horsemanship', cat: 'martial', tiers: ['Mounted creatures +1 attack & defence', '+2 / +2', '+2 / +2 and -1 slow'] },
  pikemanship: { name: 'Pikemanship', cat: 'martial', tiers: ['Your guards also stop cavalry', 'Your guards cannot be denied while the guard has advantage', 'Guarding grants +1 advantage'] },
  tactics:     { name: 'Tactics', cat: 'martial', tiers: ['Stacks may Wait (act later this round)', 'Commander +1 initiative pip', 'All stacks start combat with 1 advantage'] },
  evocation:   { name: 'Evocation', cat: 'magic', tiers: ['Damage spells +10% stronger every round', '+25% every round', '+50% every round'] },
  layering:    { name: 'Layering', cat: 'magic', tiers: ['Non-stacking spells may stack 1 extra time', '2 extra times', 'Unlimited'] },
  spellthief:  { name: 'Spellthief', cat: 'magic', tiers: ['Get a copy of an escaping enemy hero\'s spellbook', 'When an enemy casts a spell you know, your copy gains +1 power'] },
  logistics:   { name: 'Logistics', cat: 'logistics', tiers: ['No supply train needed and no train penalties', 'May cross chasms', 'Double movement'] },
  scouting:    { name: 'Scouting', cat: 'scouting', tiers: ['+1 sight (tiles)', '+2 sight (tiles)', '+4 sight (tiles)'] },
  fieldcraft:  { name: 'Fieldcraft', cat: 'craft', tiers: ['Upgrade creatures away from town (if your town has the building)', 'Creatures auto-upgrade at the start of battle if you have the essence'] },
  ascension:   { name: 'Ascension', cat: 'craft', tiers: ['Tier 1 may take the 2nd upgrade your town does not offer', 'Tier 2 too', 'Tier 3 too'] },
};
G.flag('skill-invented', 'Skills', 'Skill names are invented. Tier texts marked with no doc source: Pikemanship III, Tactics II & III, Spellthief has 2 tiers, Fieldcraft 2 tiers. The doc\'s logistics clause "may only add an even number of troops..." was unclear and is omitted.');
G.flag('skill-xp', 'Skills', 'Secondary XP sources beyond the doc: magic skills +1 per spell cast; craft skills +1 per upgrade and per battle won; logistics +1 per card entered.');

// ---- Artifacts ---------------------------------------------------------------
G.ARTIFACTS = {
  banner:   { name: 'Banner of Equals', desc: 'Unit numbers do not affect attack or defence (both sides).', value: 3 },
  stoic:    { name: 'Stoic Standard', desc: 'Unit numbers do not affect morale (both sides).', value: 3 },
  horseshoe:{ name: 'Horseshoe of Haste', desc: 'All your creatures -1 slow.', value: 2 },
  herald:   { name: "Herald's Scroll", desc: 'Cast one spell before combat begins.', value: 2 },
  heart:    { name: 'Heartstone', desc: 'All your creatures +1 health.', value: 5 },
  blade:    { name: 'Keen Blade', desc: '+1 attack.', value: 1, stat: { attack: 1 } },
  aegis:    { name: 'Aegis', desc: '+1 defence.', value: 1, stat: { defence: 1 } },
  lion:     { name: 'Lion Badge', desc: '+2 courage.', value: 1, stat: { courage: 2 } },
  tome:     { name: 'Old Tome', desc: '+2 knowledge.', value: 1, stat: { knowledge: 2 } },
  orb:      { name: 'Power Orb', desc: '+1 power.', value: 1, stat: { power: 1 } },
  hourglass:{ name: 'Hourglass', desc: '+1 initiative (one pip).', value: 1, stat: { initiative: 1 } },
  boots:    { name: 'Road Boots', desc: '+2 movement per day.', value: 2 },
};
G.flag('artifacts', 'Artifacts', 'The five doc artifacts are in (Banner of Equals, Stoic Standard, Horseshoe, Herald\'s Scroll, Heartstone). The stat trinkets and Road Boots are filler.');

// ---- Hero classes ------------------------------------------------------------
G.PRIMARY = ['attack', 'defence', 'courage', 'initiative', 'power', 'knowledge'];
G.CLASSES = {
  warlord: { name: 'Warlord', skilled: ['attack', 'defence', 'courage'], skills: {} , desc: 'Might hero. Skilled in attack, defence, courage.' },
  mage:    { name: 'Mage', skilled: ['power', 'knowledge', 'initiative'], skills: { sorcery: 1, arcana: 1 }, desc: 'Starts with Spellweaving I and Deep Memory I.' },
  paragon: { name: 'Paragon', skilled: G.PRIMARY.slice(), skills: {}, noSecondary: true, flatPrimary: true, desc: 'All primary skills cost 3 XP/level and never lose XP, but cannot learn secondary skills.' },
  scholar: { name: 'Scholar', skilled: ['knowledge', 'courage', 'defence'], skills: {}, learner: true, desc: 'Its skills raise the cost of other skills by only (tier x 2 - 2).' },
};
G.flag('classes', 'Heroes', 'Class names & skilled sets are invented. Paragon = doc "Beta hero specialty"; Scholar = doc "Hero specialty learning".');

G.HERO_NAMES = ['Aldric', 'Brenna', 'Corvin', 'Dagny', 'Edda', 'Faolan', 'Gisela', 'Hakon', 'Isolde', 'Joran', 'Kestrel', 'Lysa', 'Morwen', 'Niall', 'Oriel', 'Perrin', 'Quill', 'Rowan', 'Sabine', 'Tamsin', 'Ulric', 'Vesna', 'Wystan', 'Yrsa'];

// ---- Doc ideas not built yet (listed so they are easy to find) ----------------
G.flag('todo-captains', 'Not yet implemented', 'Captains (town guards that level 3x faster; hero + captain splitting tactics/spells in sieges).');
G.flag('todo-refugees', 'Not yet implemented', 'Refugee camp for deserters whose home town lacks the building; buying them back until week end.');
G.flag('todo-disguise', 'Not yet implemented', 'Disguise skill (creatures appear strongest / weakest / random).');
G.flag('todo-roads', 'Not yet implemented', 'Building new roads; surveyors building mines with time + wages instead of materials.');
G.flag('todo-portals', 'Not yet implemented', 'Portals on transcendent edges that reconnect the map "the way it is supposed to be". Moons / astrological events.');
G.flag('todo-alt', 'Not yet implemented', 'Alternatives the doc floated but did not settle, left out: spells upgrading after battles won; attributes increasing by use Bethesda-style for attack/defence totals; sacrificing units to upgrade; moving after exchanging troops; hero specialty with unlimited +1/-1 damage stacks; Entrenchment (doc: only if necessary).');
G.flag('todo-ai', 'Not yet implemented', 'A computer-controlled rival hero on the overworld (hotseat only for now; neutral monsters are AI in battle).');
G.flag('whole', 'Combat', 'All calculated values are rounded to whole numbers (half rounds up): attack, defence, morale per creature, every hit (morale share rounded, health gets the rest), spells, rally, terrain damage. Base stats from the doc that are halves (7.5 attack, 2.5 / 1.5 / 3.5 damage, ranged minimum halved) are kept as written and only rounded after they are scaled.');
G.flag('sight', 'Overworld', 'Sight is measured in tiles and cards are revealed tile by tile: a tile is seen if its walking distance in tiles from the hero (diagonals allowed inside a card) is within that card\'s visibility + your standing bonus + Scouting; the 8 tiles around you are always seen. Mountains still hide the cards just behind them. Towns see 2 whole cards around, watchtowers reveal 5 whole cards around. Scouting XP: 1 per 10 tiles revealed. Hidden treasures are still only found right next to the hero.');
