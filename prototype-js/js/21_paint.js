// ============================================================================
// Procedural terrain painter (canvas). Used by the overworld and battle backdrop.
// ============================================================================
G.Paint = {
  shade(hex, f) {
    const n = parseInt(hex.slice(1), 16);
    let r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
    if (f < 0) { r *= 1 + f; g *= 1 + f; b *= 1 + f; } else { r += (255 - r) * f; g += (255 - g) * f; b += (255 - b) * f; }
    return `rgb(${r | 0},${g | 0},${b | 0})`;
  },
  // draw terrain id into rect; density scales motif count with area
  terrain(ctx, id, x, y, w, h, seed, opts) {
    opts = opts || {};
    const T = G.TERRAIN[id] || G.TERRAIN.field;
    const r = G.RNG(seed || 1);
    const S = this.shade.bind(this);
    const base = T.color;
    ctx.save();
    ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip();
    const grd = ctx.createLinearGradient(x, y, x + w, y + h);
    grd.addColorStop(0, S(base, 0.06)); grd.addColorStop(1, S(base, -0.12));
    ctx.fillStyle = grd; ctx.fillRect(x, y, w, h);
    const area = w * h, u = opts.unit || Math.max(4, Math.min(w, h) / 10);
    const N = k => Math.max(1, Math.round(area / (u * u) * k * (opts.density || 1)));
    const rx = () => x + r() * w, ry = () => y + r() * h;
    ctx.lineCap = 'round';
    const grass = (k, col) => { ctx.strokeStyle = col; ctx.lineWidth = Math.max(0.6, u * 0.08); for (let i = 0; i < N(k); i++) { const a = rx(), b = ry(); ctx.beginPath(); ctx.moveTo(a, b); ctx.lineTo(a + u * 0.15, b - u * 0.35); ctx.moveTo(a + u * 0.2, b); ctx.lineTo(a + u * 0.28, b - u * 0.3); ctx.stroke(); } };
    const tree = (a, b, s, col, trunk) => { ctx.fillStyle = trunk || '#3b2a1a'; ctx.fillRect(a - s * 0.07, b, s * 0.14, s * 0.25); ctx.fillStyle = col; ctx.beginPath(); ctx.moveTo(a, b - s * 0.75); ctx.lineTo(a + s * 0.38, b + s * 0.05); ctx.lineTo(a - s * 0.38, b + s * 0.05); ctx.closePath(); ctx.fill(); };
    const blob = (a, b, s, col) => { ctx.fillStyle = col; ctx.beginPath(); ctx.arc(a, b, s, 0, Math.PI * 2); ctx.fill(); };
    const peak = (a, b, s, snow) => {
      ctx.fillStyle = S(base, -0.25); ctx.beginPath(); ctx.moveTo(a - s, b); ctx.lineTo(a, b - s * 1.2); ctx.lineTo(a + s, b); ctx.closePath(); ctx.fill();
      ctx.fillStyle = S(base, 0.05); ctx.beginPath(); ctx.moveTo(a, b - s * 1.2); ctx.lineTo(a + s, b); ctx.lineTo(a + s * 0.2, b); ctx.closePath(); ctx.fill();
      if (snow) { ctx.fillStyle = '#f2f4f5'; ctx.beginPath(); ctx.moveTo(a, b - s * 1.2); ctx.lineTo(a + s * 0.32, b - s * 0.8); ctx.lineTo(a - s * 0.32, b - s * 0.8); ctx.closePath(); ctx.fill(); }
    };
    switch (id) {
      case 'plains': grass(0.5, S(base, -0.25)); break;
      case 'field': grass(0.35, S(base, -0.25)); for (let i = 0; i < N(0.08); i++) blob(rx(), ry(), u * 0.08, r() < 0.5 ? '#f3e28a' : '#f0f0f0'); break;
      case 'forest': for (let i = 0; i < N(0.55); i++) tree(rx(), ry(), u * (0.9 + r() * 0.5), r() < 0.5 ? '#2f6a33' : '#3b7a3a'); break;
      case 'hill': for (let i = 0; i < N(0.12); i++) { const a = rx(), b = ry(), s = u * (0.9 + r() * 0.8); ctx.fillStyle = S(base, -0.15); ctx.beginPath(); ctx.ellipse(a, b, s, s * 0.55, 0, Math.PI, 0); ctx.fill(); ctx.fillStyle = S(base, 0.1); ctx.beginPath(); ctx.ellipse(a - s * 0.2, b, s * 0.55, s * 0.35, 0, Math.PI, 0); ctx.fill(); } grass(0.15, S(base, -0.3)); break;
      case 'canyon': ctx.strokeStyle = S(base, -0.35); ctx.lineWidth = u * 0.12; for (let i = 0; i < N(0.1); i++) { const a = rx(); ctx.beginPath(); ctx.moveTo(a, y); for (let k = 1; k <= 6; k++) ctx.lineTo(a + (r() - 0.5) * u, y + h * k / 6); ctx.stroke(); } break;
      case 'ashlands': for (let i = 0; i < N(0.6); i++) blob(rx(), ry(), u * 0.06, '#2a2422'); for (let i = 0; i < N(0.06); i++) blob(rx(), ry(), u * 0.07, '#e0522e'); break;
      case 'moor': for (let i = 0; i < N(0.08); i++) { ctx.fillStyle = '#dfe7e855'; ctx.beginPath(); ctx.ellipse(rx(), ry(), u * 1.2, u * 0.3, 0, 0, Math.PI * 2); ctx.fill(); } ctx.strokeStyle = '#3a3a36'; ctx.lineWidth = u * 0.08; for (let i = 0; i < N(0.05); i++) { const a = rx(), b = ry(); ctx.beginPath(); ctx.moveTo(a, b); ctx.lineTo(a, b - u * 0.7); ctx.lineTo(a + u * 0.25, b - u * 0.95); ctx.moveTo(a, b - u * 0.5); ctx.lineTo(a - u * 0.25, b - u * 0.7); ctx.stroke(); } break;
      case 'steppe': ctx.strokeStyle = S(base, -0.2); ctx.lineWidth = u * 0.06; for (let i = 0; i < N(0.35); i++) { const a = rx(), b = ry(); ctx.beginPath(); ctx.moveTo(a, b); ctx.lineTo(a + u * 0.8, b - u * 0.05); ctx.stroke(); } break;
      case 'badlands': for (let i = 0; i < N(0.07); i++) { const a = rx(), b = ry(), s = u * (0.8 + r()); ctx.fillStyle = S(base, -0.28); ctx.beginPath(); ctx.moveTo(a - s, b); ctx.lineTo(a - s * 0.6, b - s * 0.7); ctx.lineTo(a + s * 0.6, b - s * 0.7); ctx.lineTo(a + s, b); ctx.closePath(); ctx.fill(); } break;
      case 'escarpment': case 'bluffs': ctx.strokeStyle = S(base, -0.35); ctx.lineWidth = u * 0.12; for (let i = 0; i < N(0.05); i++) { const b = ry(); ctx.beginPath(); ctx.moveTo(x, b); let a = x; while (a < x + w) { a += u; ctx.lineTo(a, b + (r() - 0.5) * u * 0.4); } ctx.stroke(); } grass(0.1, S(base, -0.25)); break;
      case 'swamp': for (let i = 0; i < N(0.18); i++) { ctx.fillStyle = '#4c6a70aa'; ctx.beginPath(); ctx.ellipse(rx(), ry(), u * (0.4 + r() * 0.5), u * 0.22, 0, 0, Math.PI * 2); ctx.fill(); } ctx.strokeStyle = '#34482c'; ctx.lineWidth = u * 0.06; for (let i = 0; i < N(0.3); i++) { const a = rx(), b = ry(); ctx.beginPath(); ctx.moveTo(a, b); ctx.lineTo(a - u * 0.08, b - u * 0.45); ctx.moveTo(a + u * 0.1, b); ctx.lineTo(a + u * 0.14, b - u * 0.35); ctx.stroke(); } break;
      case 'tundra': ctx.strokeStyle = '#b9ccd6'; ctx.lineWidth = u * 0.07; for (let i = 0; i < N(0.2); i++) { const a = rx(), b = ry(); ctx.beginPath(); ctx.arc(a, b, u * 0.5, Math.PI * 1.1, Math.PI * 1.9); ctx.stroke(); } for (let i = 0; i < N(0.05); i++) tree(rx(), ry(), u * 0.9, '#3d5a4a'); break;
      case 'dreamwood': for (let i = 0; i < N(0.35); i++) tree(rx(), ry(), u * (0.9 + r() * 0.4), r() < 0.5 ? '#4e3a78' : '#6a4a9a', '#2a1d3a'); for (let i = 0; i < N(0.1); i++) blob(rx(), ry(), u * 0.06, '#f5e6ff'); break;
      case 'stones': grass(0.25, S(base, -0.25)); { const cx = x + w / 2, cy = y + h / 2, R = Math.min(w, h) * 0.28; for (let i = 0; i < 8; i++) { const a = i / 8 * Math.PI * 2; ctx.fillStyle = '#6c6c78'; ctx.fillRect(cx + Math.cos(a) * R - u * 0.12, cy + Math.sin(a) * R * 0.6 - u * 0.45, u * 0.24, u * 0.45); } } break;
      case 'village': grass(0.2, S(base, -0.2)); for (let i = 0; i < Math.max(2, N(0.03)); i++) { const a = rx(), b = ry(), s = u * 0.5; ctx.fillStyle = '#e8dcc0'; ctx.fillRect(a - s / 2, b - s / 2, s, s * 0.7); ctx.fillStyle = '#a0452e'; ctx.beginPath(); ctx.moveTo(a - s * 0.6, b - s / 2); ctx.lineTo(a, b - s); ctx.lineTo(a + s * 0.6, b - s / 2); ctx.fill(); } break;
      case 'watchfort': grass(0.25, S(base, -0.25)); { const cx = x + w / 2, cy = y + h / 2, s = Math.min(w, h) * 0.18; ctx.fillStyle = '#5d554a'; ctx.fillRect(cx - s / 2, cy - s, s, s * 1.4); ctx.fillStyle = '#7a7060'; for (let k = 0; k < 3; k++) ctx.fillRect(cx - s / 2 + k * s * 0.38, cy - s * 1.15, s * 0.24, s * 0.2); } break;
      case 'crossroads': grass(0.25, S(base, -0.25)); ctx.strokeStyle = '#a58e62'; ctx.lineWidth = u * 0.5; ctx.beginPath(); ctx.moveTo(x, y + h / 2); ctx.lineTo(x + w, y + h / 2); ctx.moveTo(x + w / 2, y); ctx.lineTo(x + w / 2, y + h); ctx.stroke(); break;
      case 'grove': for (let i = 0; i < N(0.2); i++) blob(rx(), ry(), u * (0.35 + r() * 0.3), r() < 0.5 ? '#4f9a45' : '#62b058'); for (let i = 0; i < N(0.08); i++) blob(rx(), ry(), u * 0.07, '#fff6c0'); break;
      case 'arena': grass(0.15, S(base, -0.2)); ctx.strokeStyle = '#8a6a50'; ctx.lineWidth = u * 0.35; ctx.beginPath(); ctx.ellipse(x + w / 2, y + h / 2, w * 0.33, h * 0.26, 0, 0, Math.PI * 2); ctx.stroke(); break;
      case 'nexus': ctx.strokeStyle = '#d8f0ffaa'; ctx.lineWidth = u * 0.08; for (let i = 0; i < 4; i++) { ctx.beginPath(); ctx.moveTo(rx(), y); ctx.bezierCurveTo(rx(), ry(), rx(), ry(), rx(), y + h); ctx.stroke(); } for (let i = 0; i < N(0.08); i++) blob(rx(), ry(), u * 0.06, '#ffffff'); break;
      case 'mountain': { const k = N(0.05); for (let i = 0; i < k; i++) peak(rx(), y + h * (0.35 + r() * 0.7), u * (1.2 + r() * 1.1), true); } break;
      case 'chasm': { ctx.fillStyle = '#0a0908'; ctx.beginPath(); ctx.moveTo(x + w * 0.35, y); for (let k = 0; k <= 8; k++) ctx.lineTo(x + w * (0.3 + r() * 0.1), y + h * k / 8); for (let k = 8; k >= 0; k--) ctx.lineTo(x + w * (0.6 + r() * 0.1), y + h * k / 8); ctx.closePath(); ctx.fill(); } break;
      case 'town': grass(0.2, S(base, -0.2)); break;
    }
    ctx.restore();
  },
};
