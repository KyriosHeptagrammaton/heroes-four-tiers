// Dump all rules data from the JS game into data.json for the Godot port.
const X = require('./load');
const fs = require('fs');
const clean = o => JSON.parse(JSON.stringify(o, (k, v) => (v === Infinity ? 1e9 : v)));
const data = {
  CFG: X.CFG, FACTIONS: X.FACTIONS, FACTION_IDS: X.FACTION_IDS, UNIT_BASE: X.UNIT_BASE, MAGI: X.MAGI,
  SECOND_UPGRADE: X.SECOND_UPGRADE, ABILITY_TEXT: X.ABILITY_TEXT, UNIT_NAMES: X.UNIT_NAMES,
  SPELLS: X.SPELLS, TERRAIN: X.TERRAIN, TIMES: X.TIMES, WEATHER: X.WEATHER, SKILLS: X.SKILLS, ARTIFACTS: X.ARTIFACTS,
  PRIMARY: X.PRIMARY, CLASSES: X.CLASSES, HERO_NAMES: X.HERO_NAMES, OBJ: X.OBJ, MINES: X.MINES, BUILDINGS: X.BUILDINGS,
  MUSIC: { TRACKS: X.Music.TRACKS, TERRAIN: X.Music.TERRAIN },
  FLAGS: X.FLAGS,
};
fs.writeFileSync(require('path').join(__dirname, '../../data/data.json'), JSON.stringify(clean(data), null, 1));
console.log('flags', X.FLAGS.length, 'bytes', fs.statSync(require('path').join(__dirname, '../../data/data.json')).size);
