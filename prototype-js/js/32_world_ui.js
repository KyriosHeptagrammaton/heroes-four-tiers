// ============================================================================
// Overworld screen: canvas map + side panel
// ============================================================================
G.WorldUI = {
  cam: { x: 0, y: 0, z: 88 }, selHero: null, pathFor: null, path: null, hover: null, dirty: true, anim: false, BASE: 96,

  enter() {
    G.UI.show('world');
    if (!this.built) this.build();
    const S = G.Game.state;
    const mine = G.World.heroesOf(S.cur);
    if (!this.selHero || !G.World.hero(this.selHero) || G.World.hero(this.selHero).owner !== S.cur || !G.World.hero(this.selHero).alive) this.selHero = mine.length ? mine[0].id : null;
    this.path = null;
    if (!this.cache || this.cacheSeed !== S.seed) this.buildCache();
    this.resize();
    this.centerOnSel();
    this.renderSide();
    this.redraw();
  },

  build() {
    const h = G.UI.h, el = G.UI.clear(document.getElementById('world'));
    this.mapEl = h('div', { class: 'w-map' });
    this.cv = h('canvas');
    this.hoverEl = h('div', { class: 'w-hover', style: { display: 'none' } });
    this.toolEl = h('div', { class: 'w-toolbar' },
      h('button', { class: 'small', onclick: () => this.zoom(1.2), tip: 'Zoom in (mouse wheel)' }, '+'),
      h('button', { class: 'small', onclick: () => this.zoom(1 / 1.2), tip: 'Zoom out' }, '−'),
      h('button', { class: 'small', onclick: () => G.Main.menu(), tip: 'Main menu (game stays open)' }, '☰ Menu'),
      h('button', { class: 'small', onclick: () => G.Game.saveDialog() }, '💾 Save'),
      h('button', { class: 'small', onclick: () => G.Main.flags() }, '⚑ Flags'),
      h('button', { class: 'small', onclick: () => this.help() }, '? Help'),
      G.Music.control());
    this.mapEl.append(this.cv, this.hoverEl, this.toolEl);
    this.side = h('div', { class: 'w-side' });
    el.append(this.mapEl, this.side);
    this.ctx = this.cv.getContext('2d');
    // input
    let down = null;
    this.cv.addEventListener('mousedown', e => { down = { x: e.clientX, y: e.clientY, cx: this.cam.x, cy: this.cam.y, moved: false, btn: e.button }; });
    window.addEventListener('mousemove', e => {
      if (down) {
        const dx = e.clientX - down.x, dy = e.clientY - down.y;
        if (Math.abs(dx) + Math.abs(dy) > 5) down.moved = true;
        if (down.moved) { this.cam.x = down.cx - dx; this.cam.y = down.cy - dy; this.redraw(); }
      }
      if (e.target === this.cv) this.onHover(e);
    });
    window.addEventListener('mouseup', e => { if (down && !down.moved && e.target === this.cv) this.onClick(e, down.btn); down = null; });
    this.cv.addEventListener('contextmenu', e => e.preventDefault());
    this.cv.addEventListener('wheel', e => { e.preventDefault(); this.zoom(e.deltaY < 0 ? 1.15 : 1 / 1.15, e); }, { passive: false });
    this.cv.addEventListener('mouseleave', () => { this.hoverEl.style.display = 'none'; this.hover = null; this.redraw(); });
    window.addEventListener('resize', () => { if (this.on()) { this.resize(); this.redraw(); } });
    document.addEventListener('keydown', e => {
      if (!this.on() || document.getElementById('modal-bg').classList.contains('on')) return;
      const k = e.key.toLowerCase(), step = 60;
      if (k === 'arrowleft' || k === 'a') { this.cam.x -= step; this.redraw(); }
      if (k === 'arrowright' || k === 'd') { this.cam.x += step; this.redraw(); }
      if (k === 'arrowup' || k === 'w') { this.cam.y -= step; this.redraw(); }
      if (k === 'arrowdown' || k === 's') { this.cam.y += step; this.redraw(); }
      if (k === 'h') this.nextHero();
      if (k === ' ' && this.path) { e.preventDefault(); this.go(); }
      if (k === 'escape') { this.path = null; this.redraw(); }
      if (k === 'n' && this.hover) this.renameCard(this.hover.c);
    });
    this.built = true;
    this.loop();
  },
  on() { return document.getElementById('world').classList.contains('on'); },
  resize() { const r = this.mapEl.getBoundingClientRect(); this.cv.width = r.width; this.cv.height = r.height; this.dirty = true; },
  zoom(f, e) {
    const old = this.cam.z, nz = G.util.clamp(old * f, 34, 220);
    const r = this.mapEl.getBoundingClientRect();
    const mx = e ? e.clientX - r.left : r.width / 2, my = e ? e.clientY - r.top : r.height / 2;
    this.cam.x = (this.cam.x + mx) * nz / old - mx; this.cam.y = (this.cam.y + my) * nz / old - my;
    this.cam.z = nz; this.redraw();
  },
  centerOn(c, x, y) {
    const W = G.World, z = this.cam.z, card = W.card(c), s = card.size;
    const px = (W.cx(c) + (x + 0.5) / s) * z, py = (W.cy(c) + (y + 0.5) / s) * z;
    this.cam.x = px - this.cv.width / 2; this.cam.y = py - this.cv.height / 2; this.redraw();
  },
  centerOnSel() { const h = this.selHero && G.World.hero(this.selHero); if (h) this.centerOn(h.pos.c, h.pos.x, h.pos.y); else { const t = G.World.townsOf(G.Game.state.cur)[0]; if (t) this.centerOn(t.c, t.x, t.y); } },
  redraw() { this.dirty = true; },
  loop() { let last = 0; const f = now => { if (this.dirty && this.on() && now - last > 30) { this.dirty = false; last = now; this.draw(); } requestAnimationFrame(f); }; requestAnimationFrame(f); },

  // ---- cached terrain layer ----------------------------------------------------
  buildCache() {
    const S = G.Game.state, W = S.map.W, H = S.map.H, B = this.BASE;
    const cv = document.createElement('canvas'); cv.width = W * B; cv.height = H * B;
    const ctx = cv.getContext('2d');
    S.map.cards.forEach((card, c) => {
      const x = (c % W) * B, y = ((c / W) | 0) * B;
      G.Paint.terrain(ctx, card.t, x, y, B, B, c * 31 + 7, { unit: B / 7 });
      // interior grid
      const s = card.size;
      if (s > 1) { ctx.strokeStyle = '#00000026'; ctx.lineWidth = 1; for (let k = 1; k < s; k++) { ctx.beginPath(); ctx.moveTo(x + k * B / s, y); ctx.lineTo(x + k * B / s, y + B); ctx.moveTo(x, y + k * B / s); ctx.lineTo(x + B, y + k * B / s); ctx.stroke(); } }
      // roads
      if (card.road.some(Boolean)) {
        const m = s >> 1, cx = x + (m + 0.5) * B / s, cy = y + (m + 0.5) * B / s;
        ctx.strokeStyle = '#8a6d45'; ctx.lineWidth = B * 0.09; ctx.lineCap = 'round';
        ctx.beginPath();
        if (card.road[0]) { ctx.moveTo(cx, cy); ctx.lineTo(cx, y); }
        if (card.road[2]) { ctx.moveTo(cx, cy); ctx.lineTo(cx, y + B); }
        if (card.road[3]) { ctx.moveTo(cx, cy); ctx.lineTo(x, cy); }
        if (card.road[1]) { ctx.moveTo(cx, cy); ctx.lineTo(x + B, cy); }
        ctx.stroke();
        ctx.strokeStyle = '#c9a877'; ctx.lineWidth = B * 0.035; ctx.stroke();
      }
      ctx.strokeStyle = '#00000055'; ctx.lineWidth = 1.5; ctx.strokeRect(x + 0.5, y + 0.5, B - 1, B - 1);
    });
    this.cache = cv; this.cacheSeed = S.seed;
  },

  // ---- starry unexplored space (a HoMM nod): a static sky + three twinkling star layers ----
  buildStars() {
    const N = 384, r = G.RNG(4242);
    const mk = () => { const c = document.createElement('canvas'); c.width = N; c.height = N; return c; };
    const base = mk(), bctx = base.getContext('2d');
    bctx.fillStyle = '#05060a'; bctx.fillRect(0, 0, N, N);
    // faint nebula wisps (drawn wrapped so the tile repeats seamlessly)
    for (let i = 0; i < 7; i++) {
      const x = r() * N, y = r() * N, rad = 40 + r() * 90, hue = r() < 0.5 ? '70,60,140' : '40,80,130';
      for (const ox of [-N, 0, N]) for (const oy of [-N, 0, N]) {
        const g = bctx.createRadialGradient(x + ox, y + oy, 0, x + ox, y + oy, rad);
        g.addColorStop(0, `rgba(${hue},0.16)`); g.addColorStop(1, `rgba(${hue},0)`);
        bctx.fillStyle = g; bctx.fillRect(x + ox - rad, y + oy - rad, rad * 2, rad * 2);
      }
    }
    for (let i = 0; i < 260; i++) { bctx.fillStyle = `rgba(210,215,235,${0.15 + r() * 0.35})`; bctx.fillRect(Math.floor(r() * N), Math.floor(r() * N), 1, 1); }
    const layers = [0, 1, 2].map(() => {
      const c = mk(), x = c.getContext('2d');
      for (let i = 0; i < 26; i++) {
        const sx = Math.floor(r() * N) + 0.5, sy = Math.floor(r() * N) + 0.5, big = r() < 0.25;
        const col = r() < 0.2 ? '255,236,190' : r() < 0.3 ? '190,210,255' : '245,245,255';
        x.fillStyle = `rgba(${col},0.95)`; x.fillRect(sx - 0.5, sy - 0.5, big ? 2 : 1.5, big ? 2 : 1.5);
        if (big) { x.fillStyle = `rgba(${col},0.35)`; x.fillRect(sx - 3, sy, 7, 1); x.fillRect(sx + 0.5, sy - 3.5, 1, 7); }
      }
      return c;
    });
    const ctx = this.ctx;
    this.stars = { base: ctx.createPattern(base, 'repeat'), tw: layers.map(l => ctx.createPattern(l, 'repeat')), alpha: [1, 1, 1] };
  },
  starPhase() {
    if (!this.stars) this.buildStars();
    const t = performance.now() / 900;
    this.stars.alpha = [0, 1, 2].map(i => 0.15 + 0.85 * Math.pow(0.5 + 0.5 * Math.sin(t + i * 2.09), 2));
    const m = new DOMMatrix().translate(-this.cam.x * 0.6, -this.cam.y * 0.6); // slight parallax
    this.stars.base.setTransform(m); this.stars.tw.forEach(p => p.setTransform(m));
    this.dirty = true; // keep twinkling
  },
  fillStars(x, y, w, h) {
    const ctx = this.ctx, S = this.stars;
    ctx.fillStyle = S.base; ctx.fillRect(x, y, w, h);
    for (let i = 0; i < 3; i++) { ctx.globalAlpha = S.alpha[i]; ctx.fillStyle = S.tw[i]; ctx.fillRect(x, y, w, h); }
    ctx.globalAlpha = 1;
  },

  // ---- drawing ---------------------------------------------------------------------
  tileRect(c, x, y) {
    const W = G.World, z = this.cam.z, s = W.card(c).size;
    const X = W.cx(c) * z - this.cam.x, Y = W.cy(c) * z - this.cam.y;
    return { x: X + x * z / s, y: Y + y * z / s, w: z / s, h: z / s, cx: X + (x + 0.5) * z / s, cy: Y + (y + 0.5) * z / s };
  },
  cardCenter(c) { const W = G.World, z = this.cam.z; return { x: (W.cx(c) + 0.5) * z - this.cam.x, y: (W.cy(c) + 0.5) * z - this.cam.y }; },

  clampCam() {
    const S = G.Game.state, z = this.cam.z, mw = S.map.W * z, mh = S.map.H * z, cw = this.cv.width, ch = this.cv.height, m = z * 1.5;
    this.cam.x = mw + 2 * m < cw ? (mw - cw) / 2 : G.util.clamp(this.cam.x, -m, mw - cw + m);
    this.cam.y = mh + 2 * m < ch ? (mh - ch) / 2 : G.util.clamp(this.cam.y, -m, mh - ch + m);
  },
  draw() {
    this.clampCam();
    const S = G.Game.state, ctx = this.ctx, W = S.map.W, H = S.map.H, z = this.cam.z, B = this.BASE;
    const P = S.players[S.cur];
    if (!P._vmask) G.World.computeVisible(S.cur);
    const Wd = G.World;
    this.starPhase(); this.fillStars(0, 0, this.cv.width, this.cv.height);
    ctx.imageSmoothingEnabled = true;
    ctx.drawImage(this.cache, this.cam.x * B / z, this.cam.y * B / z, this.cv.width * B / z, this.cv.height * B / z, 0, 0, this.cv.width, this.cv.height);
    const x0 = Math.max(0, Math.floor(this.cam.x / z)), y0 = Math.max(0, Math.floor(this.cam.y / z));
    const x1 = Math.min(W - 1, Math.floor((this.cam.x + this.cv.width) / z)), y1 = Math.min(H - 1, Math.floor((this.cam.y + this.cv.height) / z));
    // transcendent: own unspent cards + active region
    const act = P.trans.active;
    for (let cy = y0; cy <= y1; cy++) for (let cx = x0; cx <= x1; cx++) {
      const c = cy * W + cx;
      const X = cx * z - this.cam.x, Y = cy * z - this.cam.y;
      if (P.seen[c] && P.trans.cards.includes(c)) {
        const pulse = 0.5 + 0.5 * Math.sin(performance.now() / 400 + c);
        ctx.strokeStyle = `rgba(190,140,255,${0.45 + 0.4 * pulse})`; ctx.lineWidth = 3; ctx.strokeRect(X + 4, Y + 4, z - 8, z - 8);
        ctx.fillStyle = '#d8b8ff'; ctx.font = `${Math.max(10, z * 0.16)}px sans-serif`; ctx.fillText('✧', X + 6, Y + z * 0.2);
        this.dirty = true;
      }
      if (act && act.region.includes(c) && P.seen[c]) { ctx.fillStyle = 'rgba(160,110,255,0.13)'; ctx.fillRect(X, Y, z, z); }
    }
    // objects
    for (let cy = y0; cy <= y1; cy++) for (let cx = x0; cx <= x1; cx++) {
      const c = cy * W + cx; if (!P.seen[c]) continue;
      const card = S.map.cards[c];
      for (const o of card.objs) {
        if (!Wd.tileSeen(P, c, o.x, o.y)) continue;
        if (o.hidden && !G.World.subSeen(P, c, o.x, o.y)) continue;
        this.drawObj(o, c);
      }
    }
    // parked trains
    for (const h of Object.values(S.heroes)) if (h.alive && h.train && h.train.state === 'parked' && (h.owner === S.cur || Wd.tileVis(P, h.train.at.c, h.train.at.x, h.train.at.y))) {
      const r = this.tileRect(h.train.at.c, h.train.at.x, h.train.at.y);
      const rr = Math.min(r.w, r.h) * 0.32;
      ctx.fillStyle = S.players[h.owner].color; ctx.strokeStyle = '#000'; ctx.lineWidth = 1.5;
      ctx.fillRect(r.cx - rr, r.cy - rr * 0.5, rr * 2, rr); ctx.strokeRect(r.cx - rr, r.cy - rr * 0.5, rr * 2, rr);
      ctx.fillStyle = '#222'; ctx.beginPath(); ctx.arc(r.cx - rr * 0.6, r.cy + rr * 0.55, rr * 0.3, 0, 7); ctx.arc(r.cx + rr * 0.6, r.cy + rr * 0.55, rr * 0.3, 0, 7); ctx.fill();
    }
    // fog
    for (let cy = y0; cy <= y1; cy++) for (let cx = x0; cx <= x1; cx++) {
      const c = cy * W + cx, X = cx * z - this.cam.x, Y = cy * z - this.cam.y;
      if (!P.seen[c]) { this.fillStars(X - 0.5, Y - 0.5, z + 1, z + 1); continue; }
      // tile by tile: unexplored tiles are black, remembered-but-not-visible tiles are dimmed
      const s = S.map.cards[c].size, full = Wd.fullMask(c), seenM = P.tmask[c] & full, visM = (P._vmask.get(c) || 0) & full;
      if (seenM === full && visM === full) continue;
      if (seenM === full && !visM) { ctx.fillStyle = 'rgba(8,9,12,0.45)'; ctx.fillRect(X, Y, z, z); continue; }
      const ts = z / s;
      for (let ty = 0; ty < s; ty++) for (let tx = 0; tx < s; tx++) {
        const bit = 1 << (ty * s + tx);
        if (!(seenM & bit)) this.fillStars(X + tx * ts - 0.5, Y + ty * ts - 0.5, ts + 1, ts + 1);
        else if (!(visM & bit)) { ctx.fillStyle = 'rgba(8,9,12,0.45)'; ctx.fillRect(X + tx * ts, Y + ty * ts, ts, ts); }
      }
    }
    // transcendent lines
    const lines = P.trans.lines.slice(); if (act) lines.push(act.line);
    for (const line of lines) this.drawLine(line);
    // heroes
    for (const h of Object.values(S.heroes)) {
      if (!h.alive) continue;
      if (h.owner !== S.cur && !Wd.tileVis(P, h.pos.c, h.pos.x, h.pos.y)) continue;
      this.drawHero(h);
    }
    // path
    if (this.path) {
      const hero = G.World.hero(this.selHero);
      let mp = hero ? hero.mp : 0;
      this.path.forEach((n, i) => {
        const r = this.tileRect(n.c, n.x, n.y);
        const ok = i < mp;
        ctx.fillStyle = ok ? '#7fe08a' : '#e0b050';
        const last = i === this.path.length - 1;
        ctx.beginPath(); ctx.arc(r.cx, r.cy, Math.max(2.5, Math.min(r.w, r.h) * (last ? 0.16 : 0.09)), 0, 7); ctx.fill();
        if (last) { ctx.strokeStyle = '#000'; ctx.lineWidth = 1; ctx.stroke(); }
      });
    }
    // player-given card names
    if (z >= 44) {
      ctx.font = `600 ${Math.max(10, Math.min(15, z * 0.12))}px sans-serif`; ctx.textAlign = 'center'; ctx.textBaseline = 'top';
      for (let cy = y0; cy <= y1; cy++) for (let cx = x0; cx <= x1; cx++) {
        const c = cy * W + cx, card = S.map.cards[c]; if (!card.name || !P.seen[c]) continue;
        const X = cx * z - this.cam.x + z / 2, Y = cy * z - this.cam.y + 3, tw = ctx.measureText(card.name).width;
        ctx.fillStyle = '#000000a8'; ctx.fillRect(X - tw / 2 - 4, Y - 1, tw + 8, Math.min(15, z * 0.12) + 5);
        ctx.fillStyle = '#f0d68e'; ctx.fillText(card.name, X, Y + 1);
      }
      ctx.textBaseline = 'alphabetic';
    }
    // hover highlight
    if (this.hover) { const r = this.tileRect(this.hover.c, this.hover.x, this.hover.y); ctx.strokeStyle = '#fff8'; ctx.lineWidth = 1.5; ctx.strokeRect(r.x + 1, r.y + 1, r.w - 2, r.h - 2); const cc = this.cardCenter(this.hover.c); ctx.strokeStyle = '#ffffff30'; ctx.strokeRect(cc.x - z / 2 + 0.5, cc.y - z / 2 + 0.5, z - 1, z - 1); }
  },

  drawLine(line) {
    const ctx = this.ctx; if (line.length < 2) return;
    ctx.save();
    ctx.shadowColor = '#c89bff'; ctx.shadowBlur = 12;
    ctx.strokeStyle = '#d6b4ffdd'; ctx.lineWidth = 3; ctx.lineCap = 'round';
    for (let i = 1; i < line.length; i++) {
      const a = this.cardCenter(line[i - 1]), b = this.cardCenter(line[i]);
      const jump = G.World.cheb(line[i - 1], line[i]) > 1;
      ctx.setLineDash(jump ? [8, 8] : []);
      ctx.beginPath(); ctx.moveTo(a.x, a.y);
      if (jump) { const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2 - Math.hypot(b.x - a.x, b.y - a.y) * 0.25; ctx.quadraticCurveTo(mx, my, b.x, b.y); }
      else ctx.lineTo(b.x, b.y);
      ctx.stroke();
    }
    ctx.restore();
  },

  drawObj(o, c) {
    const ctx = this.ctx, S = G.Game.state, r = this.tileRect(c, o.x, o.y);
    const R = Math.max(7, Math.min(r.w * 0.38, this.cam.z * 0.19));
    const def = G.OBJ[o.type];
    if (o.type === 'town') {
      const t = S.towns[o.town], col = t.owner >= 0 ? S.players[t.owner].color : '#999';
      const rr = R * 1.25;
      ctx.fillStyle = '#2a2622'; ctx.strokeStyle = col; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.rect(r.cx - rr, r.cy - rr * 0.7, rr * 2, rr * 1.4); ctx.fill(); ctx.stroke();
      ctx.fillStyle = col; for (let k = 0; k < 4; k++) ctx.fillRect(r.cx - rr + k * rr * 0.62, r.cy - rr * 0.95, rr * 0.3, rr * 0.3);
      ctx.fillStyle = '#e8dcc0'; ctx.font = `${Math.round(rr * 0.9)}px serif`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(t.capital ? '♛' : '♜', r.cx, r.cy + 1);
      if (this.cam.z > 50) { ctx.font = `600 ${Math.max(10, this.cam.z * 0.13)}px sans-serif`; ctx.fillStyle = '#000a'; const tw = ctx.measureText(t.name).width; ctx.fillRect(r.cx - tw / 2 - 3, r.cy + rr * 0.8, tw + 6, this.cam.z * 0.17); ctx.fillStyle = '#fff'; ctx.fillText(t.name, r.cx, r.cy + rr * 0.8 + this.cam.z * 0.085); }
      return;
    }
    if (o.type === 'monster' || (o.guard && false)) {
      const st = o.army.stacks.slice().sort((a, b) => G.Units.resolve(b.key).tier - G.Units.resolve(a.key).tier)[0];
      const d = G.Units.resolve(st.key);
      ctx.fillStyle = '#000a'; ctx.beginPath(); ctx.arc(r.cx, r.cy, R * 1.05, 0, 7); ctx.fill();
      ctx.fillStyle = G.FACTIONS[d.faction].color; ctx.strokeStyle = '#000'; ctx.lineWidth = 1.5;
      ctx.beginPath(); this.shape(Math.min(4, d.tier), r.cx, r.cy, R * 0.75); ctx.fill(); ctx.stroke();
      const n = G.util.sum(o.army.stacks.map(s => s.count));
      ctx.font = `700 ${Math.max(9, R * 0.62)}px sans-serif`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillStyle = '#fff'; ctx.strokeStyle = '#000'; ctx.lineWidth = 3; ctx.strokeText(this.countWord(n), r.cx, r.cy + R * 1.05); ctx.fillText(this.countWord(n), r.cx, r.cy + R * 1.05);
      return;
    }
    let ring = null;
    if (o.type === 'mine') ring = o.owner >= 0 ? S.players[o.owner].color : '#777';
    ctx.fillStyle = '#101116dd'; ctx.strokeStyle = ring || (o.guard ? '#ff7a6a' : '#000'); ctx.lineWidth = o.guard || ring ? 2.5 : 1;
    ctx.beginPath(); ctx.arc(r.cx, r.cy, R, 0, 7); ctx.fill(); ctx.stroke();
    ctx.fillStyle = def.color; ctx.font = `${Math.round(R * 1.2)}px serif`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(def.glyph, r.cx, r.cy + 1);
    if (o.guard) { ctx.fillStyle = '#ff7a6a'; ctx.font = `700 ${Math.max(8, R * 0.6)}px sans-serif`; ctx.fillText('!', r.cx + R * 0.85, r.cy - R * 0.75); }
  },
  shape(tier, cx, cy, r) {
    const ctx = this.ctx;
    if (tier === 1) ctx.arc(cx, cy, r, 0, 7);
    else if (tier === 2) { ctx.moveTo(cx, cy - r); ctx.lineTo(cx + r * 0.95, cy + r * 0.8); ctx.lineTo(cx - r * 0.95, cy + r * 0.8); ctx.closePath(); }
    else if (tier === 3) ctx.rect(cx - r * 0.85, cy - r * 0.85, r * 1.7, r * 1.7);
    else { for (let i = 0; i < 10; i++) { const a = -Math.PI / 2 + i * Math.PI / 5, rr = i % 2 ? r * 0.45 : r; i ? ctx.lineTo(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr) : ctx.moveTo(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr); } ctx.closePath(); }
  },
  countWord(n) { return n < 5 ? 'Few' : n < 10 ? 'Several' : n < 20 ? 'Pack' : n < 50 ? 'Lots' : n < 100 ? 'Horde' : 'Throng'; },
  drawHero(h) {
    const ctx = this.ctx, S = G.Game.state, r = this.tileRect(h.pos.c, h.pos.x, h.pos.y);
    const R = Math.max(8, Math.min(r.w * 0.42, this.cam.z * 0.22)), col = S.players[h.owner].color;
    if (h.id === this.selHero && h.owner === S.cur) { ctx.strokeStyle = '#f0d68e'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(r.cx, r.cy, R * 1.15 + Math.sin(performance.now() / 250) * 1.5, 0, 7); ctx.stroke(); this.dirty = true; }
    ctx.fillStyle = '#000'; ctx.fillRect(r.cx - R * 0.55 - 1, r.cy - R, 3, R * 1.9);
    ctx.fillStyle = col; ctx.strokeStyle = '#000'; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.moveTo(r.cx - R * 0.5, r.cy - R); ctx.lineTo(r.cx + R * 0.8, r.cy - R * 0.6); ctx.lineTo(r.cx - R * 0.5, r.cy - R * 0.1); ctx.closePath(); ctx.fill(); ctx.stroke();
    ctx.fillStyle = '#fff'; ctx.font = `${Math.round(R * 0.7)}px serif`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText('♛', r.cx + R * 0.05, r.cy + R * 0.45);
  },

  // ---- input -------------------------------------------------------------------------
  pick(e) {
    const rct = this.cv.getBoundingClientRect();
    const px = e.clientX - rct.left + this.cam.x, py = e.clientY - rct.top + this.cam.y, z = this.cam.z, S = G.Game.state;
    const cx = Math.floor(px / z), cy = Math.floor(py / z);
    if (cx < 0 || cy < 0 || cx >= S.map.W || cy >= S.map.H) return null;
    const c = cy * S.map.W + cx, s = S.map.cards[c].size;
    return { c, x: Math.min(s - 1, Math.floor((px / z - cx) * s)), y: Math.min(s - 1, Math.floor((py / z - cy) * s)) };
  },
  onHover(e) {
    const n = this.pick(e);
    const same = n && this.hover && n.c === this.hover.c && n.x === this.hover.x && n.y === this.hover.y;
    this.hover = n; if (!same) this.redraw();
    if (!n) { this.hoverEl.style.display = 'none'; return; }
    const S = G.Game.state, P = S.players[S.cur];
    if (!G.World.tileSeen(P, n.c, n.x, n.y)) { this.hoverEl.style.display = 'block'; this.hoverEl.innerHTML = '<span class="muted">Unexplored</span>'; return; }
    const card = S.map.cards[n.c], T = G.TERRAIN[card.t];
    let s = (card.name ? `<b style="color:#f0d68e">${G.util.esc(card.name)}</b> · ` : '') + `<b>${T.name}</b> <span class="muted">${card.size}×${card.size} · seen from ${G.World.sightRange(card.t, 0, 0)} tiles · your sight ${T.sight >= 0 ? '+' : ''}${Math.round(T.sight * G.CFG.sightScale)} when standing here</span><br><span style="color:#d9d0b0">Battle: ${T.desc}</span><br><span class="muted">Right-click or press N to ${card.name ? 'rename' : 'name'} this card.</span>`;
    if (card.road.some(Boolean)) s += G.World.isRoad(n.c, n.x, n.y) ? '<br><span class="muted">Road</span>' : '<br><span class="muted">Off-road (supply train cannot go here)</span>';
    if (P.trans.cards.includes(n.c)) s += '<br><span style="color:#d8b8ff">✧ One of your transcendent cards: entering it opens a jump to a far part of the map.</span>';
    const o = G.World.objAt(n.c, n.x, n.y);
    if (o && (!o.hidden || G.World.subSeen(P, n.c, n.x, n.y))) s += '<hr style="border-color:#333">' + this.objInfo(o);
    const hh = G.World.heroAt(n.c, n.x, n.y);
    if (hh && (hh.owner === S.cur || G.World.tileVis(P, n.c, n.x, n.y))) s += `<hr style="border-color:#333"><b style="color:${S.players[hh.owner].color}">♛ ${G.util.esc(hh.name)}</b> (${S.players[hh.owner].name})<br>${this.armyText(hh.army, hh.owner === S.cur)}`;
    if (this.path && this.path.length) s += `<hr style="border-color:#333">Path: ${this.path.length} steps (movement left: ${G.World.hero(this.selHero).mp}). Click again or press Space to go.`;
    this.hoverEl.innerHTML = s; this.hoverEl.style.display = 'block';
  },
  armyText(groups, exact) {
    return groups.map(g => { const d = G.Units.resolve(g.key); const n = G.util.sum([g.count]); return `${exact ? n : this.countWord(n)} ${G.util.esc(g.name || d.name)}${g.splits > 1 ? ' ×' + g.splits + ' stacks' : ''}`; }).join('<br>');
  },
  objInfo(o) {
    const S = G.Game.state, def = G.OBJ[o.type];
    let s = `<b>${def.glyph} ${o.type === 'mine' ? G.MINES[o.kind].name : o.type === 'town' ? S.towns[o.town].name : def.name}</b><br><span class="muted">${def.desc}</span>`;
    if (o.type === 'town') { const t = S.towns[o.town]; s += `<br>${G.FACTIONS[t.faction].name} town · ${t.owner >= 0 ? 'owned by ' + S.players[t.owner].name : 'neutral'}`; if (t.garrison.length && t.owner !== S.cur) s += '<br>Garrison: ' + this.armyText(t.garrison, false); }
    if (o.type === 'mine') s += `<br>+${G.MINES[o.kind].income} gold/day · claim cost ${G.MINES[o.kind].cost} · ${o.owner >= 0 ? 'owned by ' + S.players[o.owner].name : 'unclaimed'}`;
    if (o.type === 'monster') s += '<br>' + this.monsterText(o.army);
    if (o.guard) s += '<br><span class="bad">Guarded:</span> ' + this.monsterText(o.guard);
    if (o.type === 'shrine') s += `<br>Spell: ${G.SPELLS[o.spell].name}`;
    if (o.type === 'artifact' && !o.guard) s += `<br>${G.ARTIFACTS[o.art].name}`;
    if (o.type === 'hermit') s += `<br>+${o.amount} ${o.stat} experience`;
    if (o.join) s += `<br>${o.join.count} × ${G.Units.resolve(o.join.key).name}${o.price ? ' for ' + o.price + ' gold' : ''}`;
    return s;
  },
  monsterText(a) {
    const val = G.util.fmt(G.util.sum(a.stacks.map(s => s.count * G.Units.value(G.Units.resolve(s.key)))));
    return a.stacks.map(s => `${this.countWord(s.count)} ${G.Units.resolve(s.key).name}`).join(', ') + ` <span class="muted">(level ${a.level}, value ≈${val})</span>`;
  },
  onClick(e, btn) {
    if (this.anim) return;
    const n = this.pick(e); if (!n) return;
    const S = G.Game.state;
    if (btn === 2) { if (this.path) { this.path = null; this.redraw(); } else this.renameCard(n.c); return; }
    // click own hero to select
    const hh = G.World.heroAt(n.c, n.x, n.y);
    if (hh && hh.owner === S.cur && hh.id !== this.selHero) { this.selHero = hh.id; this.path = null; this.renderSide(); this.redraw(); return; }
    // click own town tile with no hero selected -> open town
    const o = G.World.objAt(n.c, n.x, n.y);
    const hero = this.selHero && G.World.hero(this.selHero);
    if (!hero) { if (o && o.type === 'town' && S.towns[o.town].owner === S.cur) G.TownUI.open(o.town); return; }
    if (hh && hh.id === hero.id) { if (o && o.type === 'town' && S.towns[o.town].owner === S.cur) G.TownUI.open(o.town, hero.id); return; }
    if (this.path && this.path.length) { const last = this.path[this.path.length - 1]; if (last.c === n.c && last.x === n.x && last.y === n.y) { this.go(); return; } }
    const p = G.World.path(hero, n);
    if (!p) { const why = G.World.enterable(hero, n, S.players[S.cur]); G.UI.toast(why && why !== 'stop' ? why : 'No route'); this.path = null; this.redraw(); return; }
    this.path = p; this.redraw();
  },
  renameCard(c) {
    const S = G.Game.state, P = S.players[S.cur], card = S.map.cards[c];
    if (!P.seen[c]) { G.UI.toast('You can only name land you have seen'); return; }
    G.UI.prompt(`Name this ${G.TERRAIN[card.t].name.toLowerCase()} (leave empty to clear)`, card.name || '', v => { card.name = v ? v.slice(0, 32) : undefined; this.redraw(); });
  },
  go() {
    const hero = G.World.hero(this.selHero);
    if (!hero || !this.path) return;
    G.Game.walk(hero, this.path);
  },
  nextHero() {
    const hs = G.World.heroesOf(G.Game.state.cur); if (!hs.length) return;
    const i = hs.findIndex(h => h.id === this.selHero);
    this.selHero = hs[(i + 1) % hs.length].id; this.path = null; this.centerOnSel(); this.renderSide();
  },

  // ---- side panel ---------------------------------------------------------------------
  renderSide() {
    const h = G.UI.h, S = G.Game.state, P = S.players[S.cur], U = G.util, el = G.UI.clear(this.side);
    const week = Math.floor((S.day - 1) / 7) + 1, dow = (S.day - 1) % 7 + 1;
    el.append(h('div', { class: 'sec' },
      h('div', { class: 'row between' }, h('h2', { style: { margin: 0, color: P.color } }, P.name), h('span', { class: 'chip' }, `Day ${dow} · Week ${week}`)),
      h('div', { class: 'res', style: { marginTop: '6px' } },
        h('span', { tip: 'Gold' }, '● ', h('b', null, U.fmt(P.gold))), h('span', { class: 'muted', tip: 'Income per day' }, `+${G.World.income(S.cur)}/day`),
        P.invest ? h('span', { class: 'muted', tip: 'Treasury pays weekly' }, `+${P.invest}/wk`) : null),
      h('div', { class: 'res', style: { marginTop: '4px' }, tip: 'Upgrade essence by tier (from killing creatures of that tier)' },
        ...[1, 2, 3, 4].map(t => h('span', null, `⬡${t} `, h('b', null, P.essence[t])))),
    ));
    // heroes
    const hs = G.World.heroesOf(S.cur);
    const hsec = h('div', { class: 'sec' }, h('h3', null, 'Heroes'));
    for (const hr of hs) {
      const tab = h('div', { class: 'hero-tab' + (hr.id === this.selHero ? ' sel' : ''), onclick: () => { this.selHero = hr.id; this.path = null; this.centerOnSel(); this.renderSide(); } },
        h('span', { style: { color: P.color } }, '♛'), h('b', null, hr.name), h('span', { class: 'muted grow' }, G.CLASSES[hr.cls].name),
        h('span', { class: 'chip', tip: 'Movement left today' }, `${hr.mp}/${G.World.mpMax(hr)}`), hr.pendingSkillChoice ? h('span', { class: 'chip gold', tip: 'Skill choice waiting' }, '★') : null);
      hsec.append(tab);
    }
    if (!hs.length) hsec.append(h('div', { class: 'muted' }, 'No heroes. Hire one in a town tavern.'));
    el.append(hsec);
    const hero = this.selHero && G.World.hero(this.selHero);
    if (hero) {
      const trainTxt = !hero.train || hero.train.state === 'none' ? 'no supply train' : hero.train.state === 'with' ? `supply train with army${hero.train.wounded.length ? ` (${U.sum(hero.train.wounded.map(w => w.count))} wounded)` : ''}` : 'supply train parked';
      const sec = h('div', { class: 'sec' },
        h('div', { class: 'row between' }, h('b', { class: 'goldt' }, hero.name), h('span', { class: 'muted' }, 'A' + G.Heroes.stat(hero, 'attack') + ' D' + G.Heroes.stat(hero, 'defence') + ' C' + G.Heroes.stat(hero, 'courage') + ' I' + G.Heroes.initStr(G.Heroes.stat(hero, 'initiative')) + ' P' + G.Heroes.stat(hero, 'power') + ' K' + G.Heroes.stat(hero, 'knowledge'))),
        h('div', { class: 'army-mini', style: { margin: '6px 0' } }, hero.army.map(g => { const d = G.Units.resolve(g.key); return h('span', { class: 'am', tip: G.UI.unitTip(d) }, G.UI.sym(d, 18), g.count + (g.splits > 1 ? `÷${g.splits}` : '')); })),
        h('div', { class: 'muted', style: { fontSize: '12px' }, tip: G.FLAGS.find(f => f.id === 'trainrules').text }, '⛟ ' + trainTxt + (G.Heroes.skill(hero, 'logistics') ? ' (Logistics: not needed)' : '')),
        h('div', { class: 'row wrap', style: { marginTop: '6px' } },
          h('button', { class: 'small', onclick: () => G.ArmyUI.heroScreen(hero.id) }, 'Hero' + (hero.pendingSkillChoice ? ' ★' : '')),
          h('button', { class: 'small', onclick: () => G.ArmyUI.armyScreen(hero.id) }, 'Army'),
          hero.train && hero.train.state === 'with' ? h('button', { class: 'small', onclick: () => G.Game.parkTrain(hero) }, 'Park train') : null,
          (() => { const o = G.World.objAt(hero.pos.c, hero.pos.x, hero.pos.y); return o && o.type === 'town' && S.towns[o.town].owner === S.cur ? h('button', { class: 'small', onclick: () => G.TownUI.open(o.town, hero.id) }, 'Town') : null; })(),
          (() => { const o = G.World.objAt(hero.pos.c, hero.pos.x, hero.pos.y); return o && ['post', 'font', 'mine', 'mercs'].includes(o.type) ? h('button', { class: 'small', onclick: () => G.Game.useSite(hero, o) }, 'Use ' + G.OBJ[o.type].name) : null; })(),
          h('button', { class: 'small', onclick: () => this.centerOnSel() }, '◎')),
      );
      el.append(sec);
    }
    const ts = G.World.townsOf(S.cur);
    const tsec = h('div', { class: 'sec' }, h('h3', null, 'Towns'));
    for (const t of ts) tsec.append(h('div', { class: 'hero-tab', onclick: () => { this.centerOn(t.c, t.x, t.y); G.TownUI.open(t.id, (() => { const hh = G.World.heroAt(t.c, t.x, t.y); return hh && hh.owner === S.cur ? hh.id : null; })()); } }, h('span', null, t.capital ? '♛' : '♜'), h('b', null, t.name), h('span', { class: 'muted grow' }, G.FACTIONS[t.faction].name)));
    el.append(tsec);
    const logSec = h('div', { class: 'sec grow scroll', style: { flex: '1', fontSize: '12px', minHeight: '60px' } });
    for (const L of S.log.slice(-40).reverse()) logSec.append(h('div', { class: L.p === S.cur ? '' : 'muted' }, `D${L.day}: ${L.t}`));
    el.append(logSec);
    el.append(h('div', { class: 'sec' }, h('button', { class: 'primary', style: { width: '100%', padding: '10px' }, onclick: () => G.Game.endTurnConfirm() }, 'End turn ▸')));
  },

  help() {
    const h = G.UI.h;
    G.UI.modal(h('div', { style: { maxWidth: '640px' }, html: `<h2>Overworld</h2>
<p><b>Cards.</b> The map is 20×20 cards. Each card is a small NxN world of its own (prairie 1×1 … swamp 4×4): every square inside is explorable, and walking across a big card takes more steps. Hover a card for its battle effect.</p>
<p><b>Moving.</b> Select a hero, click a destination to see the path (green = reachable today), click again or press <kbd>Space</kbd> to go. Right-click / <kbd>Esc</kbd> cancels a path. With no path shown, right-click a card (or hover it and press <kbd>N</kbd>) to name it. <kbd>H</kbd> cycles heroes; drag or <kbd>WASD</kbd> to pan; wheel zooms.</p>
<p><b>Supply train.</b> While your train is with you, you may only walk on roads. Park it to go off-road (your troops get −1 morale and suffer attrition until you return to it). Wounded ride in the train and rejoin in town.</p>
<p><b>Sight.</b> Sight is counted in tiles and cards are uncovered tile by tile: you see a tile if it is within the card's visibility of your hero, counting every square in between, so a 4×4 swamp in the way blocks more than a 1×1 prairie. Most cards are seen from 3 tiles, hills from 5, mountains from 9. Dark tiles are unexplored; dim tiles are remembered but not currently in view. Standing on high ground helps, forests and swamps hurt. Mountains hide the cards just behind them. Small hidden things inside a card are only found by walking near them.</p>
<p><b>Transcendent cards (✧).</b> Each player has secret cards. Entering one lifts a distant part of the map beside you: the next edge you cross takes you there, and a glowing line records your route. Walk back along the line to return; step off it and you are in that far place for real. Your opponent just sees you vanish and reappear.</p>
<p><b>Battles.</b> The defender chooses the ground (its card or any of the 8 around it) or ignores the attack; the attacker then chooses the time of day, or feints.</p>
<p><b>Winning.</b> Capture the enemy capital (♛).</p>` }));
  },
};
