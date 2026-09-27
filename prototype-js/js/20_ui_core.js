// ============================================================================
// UI helpers: element builder, tooltips, modal, toast, screens, unit symbols
// ============================================================================
G.UI = {
  h(tag, attrs, ...kids) {
    const el = document.createElement(tag);
    if (attrs) for (const k in attrs) {
      const v = attrs[k];
      if (v == null || v === false) continue;
      if (k === 'class') el.className = v;
      else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
      else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
      else if (k === 'html') el.innerHTML = v;
      else if (k === 'tip') { el.dataset.tip = v; }
      else el.setAttribute(k, v === true ? '' : v);
    }
    for (const kid of kids.flat(Infinity)) {
      if (kid == null || kid === false) continue;
      el.appendChild(kid.nodeType ? kid : document.createTextNode(String(kid)));
    }
    return el;
  },
  clear(el) { while (el.firstChild) el.removeChild(el.firstChild); return el; },
  $(sel) { return document.querySelector(sel); },

  show(id) {
    document.querySelectorAll('.screen').forEach(s => s.classList.toggle('on', s.id === id));
    this.hideTip();
  },

  // ---- tooltip: any element with data-tip (HTML allowed) ----------------------
  initTips() {
    const tip = document.getElementById('tip');
    document.addEventListener('mousemove', e => {
      const t = e.target.closest && e.target.closest('[data-tip]');
      if (!t || !t.dataset.tip) { tip.style.display = 'none'; return; }
      tip.innerHTML = t.dataset.tip;
      tip.style.display = 'block';
      const w = tip.offsetWidth, hh = tip.offsetHeight;
      let x = e.clientX + 14, y = e.clientY + 14;
      if (x + w > innerWidth - 6) x = e.clientX - w - 10;
      if (y + hh > innerHeight - 6) y = e.clientY - hh - 10;
      tip.style.left = x + 'px'; tip.style.top = y + 'px';
    });
  },
  hideTip() { const t = document.getElementById('tip'); if (t) t.style.display = 'none'; },

  modal(content, opts) {
    opts = opts || {};
    const bg = document.getElementById('modal-bg'), m = document.getElementById('modal');
    this.clear(m);
    m.appendChild(content);
    bg.classList.add('on');
    bg.onclick = e => { if (e.target === bg && !opts.locked) this.closeModal(); };
    this.hideTip();
  },
  closeModal() { document.getElementById('modal-bg').classList.remove('on'); },
  confirm(text, yes, no) {
    const h = this.h;
    this.modal(h('div', { class: 'col', style: { minWidth: '320px' } }, h('div', null, text),
      h('div', { class: 'row', style: { justifyContent: 'flex-end' } },
        h('button', { onclick: () => { this.closeModal(); no && no(); } }, 'Cancel'),
        h('button', { class: 'primary', onclick: () => { this.closeModal(); yes && yes(); } }, 'OK'))));
  },
  alert(title, body, then) {
    const h = this.h;
    this.modal(h('div', { class: 'col', style: { minWidth: '320px' } }, h('h2', null, title), typeof body === 'string' ? h('div', { html: body }) : body,
      h('div', { class: 'row', style: { justifyContent: 'flex-end' } }, h('button', { class: 'primary', onclick: () => { this.closeModal(); then && then(); } }, 'OK'))), { locked: true });
  },
  prompt(title, value, cb) {
    const h = this.h;
    const inp = h('input', { value: value || '', style: { width: '100%' } });
    const done = () => { this.closeModal(); cb(inp.value.trim()); };
    inp.addEventListener('keydown', e => { if (e.key === 'Enter') done(); });
    this.modal(h('div', { class: 'col', style: { minWidth: '320px' } }, h('h2', null, title), inp,
      h('div', { class: 'row', style: { justifyContent: 'flex-end' } }, h('button', { onclick: () => this.closeModal() }, 'Cancel'), h('button', { class: 'primary', onclick: done }, 'OK'))));
    setTimeout(() => inp.focus(), 30);
  },
  toast(text, ms) {
    const t = document.getElementById('toast');
    t.textContent = text; t.style.display = 'block';
    clearTimeout(this._tt); this._tt = setTimeout(() => t.style.display = 'none', ms || 2200);
  },

  // ---- abstract unit symbol (SVG) ---------------------------------------------
  // tier shape: 1 circle, 2 triangle, 3 square, 4 star. Faction colour fill.
  shapePath(tier, cx, cy, r) {
    if (tier === 1) return `<circle cx="${cx}" cy="${cy}" r="${r}"/>`;
    if (tier === 2) return `<polygon points="${cx},${cy - r} ${cx + r * 0.95},${cy + r * 0.8} ${cx - r * 0.95},${cy + r * 0.8}"/>`;
    if (tier === 3) return `<rect x="${cx - r * 0.85}" y="${cy - r * 0.85}" width="${r * 1.7}" height="${r * 1.7}" rx="2"/>`;
    const pts = []; for (let i = 0; i < 10; i++) { const a = -Math.PI / 2 + i * Math.PI / 5, rr = i % 2 ? r * 0.45 : r; pts.push((cx + Math.cos(a) * rr).toFixed(1) + ',' + (cy + Math.sin(a) * rr).toFixed(1)); }
    return `<polygon points="${pts.join(' ')}"/>`;
  },
  unitSymbol(def, size) {
    size = size || 36;
    const col = G.FACTIONS[def.faction].color;
    let inner = '';
    if (def.mounted) {
      const R = G.Units.resolve(def.riderKey), M = G.Units.resolve(def.mountKey);
      inner += `<g fill="${G.FACTIONS[M.faction].color}" stroke="#000" stroke-width="1.5" opacity=".9">${this.shapePath(Math.min(4, M.tier), 20, 26, 11)}</g>`;
      inner += `<g fill="${col}" stroke="#fff" stroke-width="1.5">${this.shapePath(Math.min(4, R.tier), 20, 13, 8)}</g>`;
    } else {
      inner += `<g fill="${col}" stroke="#000" stroke-width="1.5">${this.shapePath(Math.min(4, def.tier), 20, 20, 14)}</g>`;
      inner += `<text x="20" y="24.5" text-anchor="middle" font-size="12" font-weight="700" fill="#fff" style="paint-order:stroke" stroke="#0008" stroke-width="2">${G.FACTIONS[def.faction].glyph}</text>`;
    }
    if (def.ab.ranged) inner += `<g stroke="#fff" stroke-width="2" fill="none"><line x1="30" y1="10" x2="39" y2="1"/><polyline points="34,1 39,1 39,6"/></g>`;
    if (def.mod === 'm') inner += `<text x="3" y="11" font-size="12" fill="#e9d0ff">✦</text>`;
    if (def.up >= 1) inner += `<g fill="#f0d68e">${def.up >= 2 ? '<circle cx="36" cy="37" r="2.2"/><circle cx="30" cy="37" r="2.2"/>' : '<circle cx="36" cy="37" r="2.2"/>'}</g>`;
    if (def.ab.cavalry) inner += `<text x="1" y="38" font-size="11" fill="#fff">»</text>`;
    return `<svg width="${size}" height="${size}" viewBox="0 0 40 40">${inner}</svg>`;
  },
  sym(def, size) { const s = document.createElement('span'); s.style.display = 'inline-flex'; s.innerHTML = this.unitSymbol(def, size); return s; },

  unitTip(def, extra) {
    const U = G.util;
    const st = k => G.Units.statStr(def, k);
    let s = `<b style="color:${G.FACTIONS[def.faction].color}">${U.esc(def.name)}</b> <span class="muted">${G.FACTIONS[def.faction].name} · tier ${def.tier}${def.mounted ? ' (mounted)' : ''}</span>`;
    if (def.placeholder) s += ` <span class="flagmark" title="placeholder">⚑</span>`;
    s += `<div class="kv" style="margin-top:4px"><b>Health</b><span>${U.fmt(def.hp)}</span><b>Morale</b><span>${st('mor')}</span><b>Damage</b><span>${def.dmg.map(U.fmt).join(' / ')}</span><b>Initiative</b><span>${def.ini}</span><b>Attack</b><span>${st('att')}</span><b>Defence</b><span>${st('def')}</span><b>Weight/Str</b><span>${def.w} / ${def.s}</span></div>`;
    const ab = Object.keys(def.ab).filter(k => def.ab[k] && G.ABILITY_TEXT[k]);
    if (ab.length) s += '<div style="margin-top:4px">' + ab.map(k => `• ${k === 'slow' ? 'Slow ' + def.ab.slow : k[0].toUpperCase() + k.slice(1)}`).join('<br>') + '</div>';
    const sp = Object.keys(def.sp).filter(k => def.sp[k] && G.SPECIAL_TEXT[k]);
    if (sp.length) s += '<div style="margin-top:4px;color:#d9d0b0">' + sp.map(k => '◦ ' + G.SPECIAL_TEXT[k](def.sp[k])).join('<br>') + '</div>';
    if (def.placeholder) s += '<div style="margin-top:4px;color:#ff9f43">⚑ Placeholder "+1" second-upgrade stats</div>';
    if (extra) s += extra;
    return s;
  },
};
