// ============================================================================
// Core namespace, RNG, helpers, and the DESIGN FLAGS registry.
// Every rule or number that was invented/assumed (not in the design doc) is
// registered with G.flag(id, text) so it shows up in the in-game "Design Flags"
// screen and can be revisited later.
// ============================================================================
var G = (typeof window !== 'undefined' ? (window.G = window.G || {}) : (globalThis.G = globalThis.G || {}));

G.FLAGS = [];
G.flag = function (id, area, text) {
  if (!G.FLAGS.find(f => f.id === id)) G.FLAGS.push({ id, area, text });
};

// ---- Seedable RNG (mulberry32) ---------------------------------------------
G.RNG = function (seed) {
  let a = (seed >>> 0) || 1;
  const r = function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  r.int = (lo, hi) => lo + Math.floor(r() * (hi - lo + 1)); // inclusive
  r.pick = arr => arr[Math.floor(r() * arr.length)];
  r.shuffle = arr => { for (let i = arr.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [arr[i], arr[j]] = [arr[j], arr[i]]; } return arr; };
  r.state = () => a;
  r.setState = s => { a = s; };
  return r;
};

G.util = {
  clamp: (v, lo, hi) => Math.max(lo, Math.min(hi, v)),
  round2: v => Math.round(v * 100) / 100,
  fmt: v => {
    if (v === Infinity) return '∞';
    return String(Math.round(v));
  },
  deepClone: o => JSON.parse(JSON.stringify(o)),
  uid: (() => { let n = 1; return (p = 'id') => p + (n++) + '_' + Math.floor(Math.random() * 1e6).toString(36); })(),
  sum: arr => arr.reduce((a, b) => a + b, 0),
  esc: s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
};
