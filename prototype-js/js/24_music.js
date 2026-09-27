// ============================================================================
// Music: terrain themes on the map, a town theme in towns (HoMM style).
// A watcher checks which screen/terrain is active and crossfades between tracks.
// ============================================================================
G.Music = {
  TRACKS: {
    path:  { file: 'music/the-path-winds-true.mp3', name: 'The Path Winds True' },
    woods: { file: 'music/the-woods-weep.mp3', name: 'The Woods Weep' },
    water: { file: 'music/water-familiar-song.mp3', name: 'Water Familiar Song' },
    sad:   { file: 'music/sad-ages.mp3', name: 'Sad Ages' },
    sad2:  { file: 'music/sad-ages-2.mp3', name: 'Sad Ages (second version)' },
    town:  { file: 'music/we-stand.mp3', name: 'We Stand' },
  },
  // terrain -> track
  TERRAIN: {
    plains: 'path', field: 'path', steppe: 'path', hill: 'path', crossroads: 'path', village: 'path', stones: 'path', arena: 'path', nexus: 'path', watchfort: 'path',
    forest: 'woods', dreamwood: 'woods', grove: 'woods', tundra: 'woods',
    swamp: 'water', moor: 'water',
    ashlands: 'sad', badlands: 'sad', canyon: 'sad', chasm: 'sad',
    mountain: 'sad2', escarpment: 'sad2', bluffs: 'sad2',
    town: 'town',
  },
  cur: null, audio: null, vol: 0.6, muted: false, blocked: false,

  init() {
    try { const v = JSON.parse(localStorage.getItem('h4t_music') || 'null'); if (v) { this.vol = v.vol; this.muted = v.muted; } } catch (e) { }
    const unlock = () => { if (this.blocked && this.audio) { this.audio.play().then(() => { this.blocked = false; }).catch(() => { }); } };
    document.addEventListener('pointerdown', unlock); document.addEventListener('keydown', unlock);
    setInterval(() => this.tick(), 400);
  },
  save() { try { localStorage.setItem('h4t_music', JSON.stringify({ vol: this.vol, muted: this.muted })); } catch (e) { } },
  target() { return this.muted ? 0 : this.vol; },

  // which track should be playing right now?
  wanted() {
    const on = id => { const e = document.getElementById(id); return e && e.classList.contains('on'); };
    if (on('town')) return 'town';
    if (on('battle') && G.BattleUI.b) return this.TERRAIN[G.BattleUI.b.terrainId] || 'path';
    if (on('world') && G.Game.state) {
      const h = G.WorldUI.selHero && G.World.hero(G.WorldUI.selHero);
      if (!h) return 'path';
      const o = G.World.objAt(h.pos.c, h.pos.x, h.pos.y);
      if (o && o.type === 'town') return 'town';
      return this.TERRAIN[G.World.card(h.pos.c).t] || 'path';
    }
    if (on('handoff')) return this.cur || 'town';
    return 'path'; // menu, sandbox
  },
  tick() {
    const w = this.wanted();
    if (w !== this.cur) this.play(w);
  },
  play(id) {
    const T = this.TRACKS[id]; if (!T) return;
    const old = this.audio;
    if (old) this.fade(old, 0, 1500, () => { old.pause(); old.src = ''; });
    const a = new Audio(T.file);
    a.loop = true; a.volume = 0;
    this.audio = a; this.cur = id;
    a.play().then(() => { this.blocked = false; }).catch(() => { this.blocked = true; });
    this.fade(a, this.target(), 1800);
  },
  fade(a, to, ms, done) {
    clearInterval(a._fade);
    const from = a.volume, t0 = performance.now();
    a._fade = setInterval(() => {
      const k = Math.min(1, (performance.now() - t0) / ms);
      a.volume = Math.max(0, Math.min(1, from + (to - from) * k));
      if (k >= 1) { clearInterval(a._fade); done && done(); }
    }, 50);
  },
  setVol(v) { this.vol = v; this.save(); if (this.audio) this.fade(this.audio, this.target(), 200); },
  toggle() { this.muted = !this.muted; this.save(); if (this.audio) this.fade(this.audio, this.target(), 400); },
  nowPlaying() { return this.cur ? this.TRACKS[this.cur].name : ''; },

  // small control: ♪ button + volume slider
  control() {
    const h = G.UI.h;
    const btn = h('button', { class: 'small', tip: 'Music on/off', onclick: () => { this.toggle(); btn.textContent = this.muted ? '♪ off' : '♪'; } }, this.muted ? '♪ off' : '♪');
    const sl = h('input', { type: 'range', min: 0, max: 100, value: Math.round(this.vol * 100), style: { width: '70px', verticalAlign: 'middle' }, tip: 'Music volume', oninput: e => this.setVol(+e.target.value / 100) });
    return h('span', { class: 'row', style: { gap: '4px' } }, btn, sl);
  },
};
G.flag('music', 'Audio', 'Music by terrain (your tracks): open land & roads = The Path Winds True; forest, dreamwood, sacred grove, tundra = The Woods Weep; swamp & haunted moor = Water Familiar Song; ashlands, badlands, box canyon, chasm = Sad Ages; mountains, escarpment, bluffs = Sad Ages (second version); towns = We Stand. Battles play the battlefield terrain\'s track (sieges play We Stand). Menus play The Path Winds True.');
if (typeof window !== 'undefined') window.addEventListener('DOMContentLoaded', () => G.Music.init());
