// ============================================================================
// Main menu, design flags screen, boot.
// ============================================================================
G.VERSION = '0.1';
G.Main = {
  menu() {
    const h = G.UI.h, el = G.UI.clear(document.getElementById('menu'));
    const hasGame = !!(G.Game && G.Game.state);
    el.append(h('div', { class: 'menu-box' },
      h('div', { class: 'sigil' }, 'α β γ δ'),
      h('h1', null, 'Heroes of the Four Tiers'),
      h('div', { class: 'muted', style: { marginBottom: '18px' } }, 'An abstract prototype · v' + G.VERSION),
      hasGame ? h('button', { class: 'primary', onclick: () => G.Game.resume() }, 'Continue game') : null,
      G.Game ? h('button', { class: hasGame ? '' : 'primary', onclick: () => G.Game.newGameDialog() }, 'New hotseat game') : null,
      G.Game ? h('button', { onclick: () => G.Game.loadDialog() }, 'Load game') : null,
      h('button', { onclick: () => G.Sandbox.init() }, 'Combat sandbox'),
      h('button', { onclick: () => this.flags() }, `Design flags (${G.FLAGS.length})`),
      h('button', { onclick: () => G.BattleUI.showRules() }, 'Combat rules'),
      h('div', { class: 'row center', style: { marginTop: '10px' } }, h('span', { class: 'muted' }, 'Music'), G.Music.control()),
    ));
    G.UI.show('menu');
  },

  flags() {
    const h = G.UI.h;
    const areas = [...new Set(G.FLAGS.map(f => f.area))];
    const box = h('div', { class: 'flags-list', style: { maxWidth: '720px' } },
      h('h2', null, 'Design flags'),
      h('div', { class: 'muted' }, 'Everything below was assumed, invented or interpreted because the design doc left it open. Items marked ⚑ in-game are placeholders to revisit.'));
    for (const a of areas) {
      box.append(h('h3', { style: { marginTop: '12px' } }, a));
      for (const f of G.FLAGS.filter(x => x.area === a)) box.append(h('div', { class: 'f' }, f.text));
    }
    box.append(h('div', { class: 'row', style: { justifyContent: 'flex-end', marginTop: '10px' } }, h('button', { class: 'primary', onclick: () => G.UI.closeModal() }, 'Close')));
    G.UI.modal(box);
  },

  boot() {
    // no browser right-click menu anywhere (text boxes keep theirs for copy/paste)
    document.addEventListener('contextmenu', e => { if (!e.target.closest('input, textarea')) e.preventDefault(); });
    G.UI.initTips();
    this.menu();
  },
};
window.addEventListener('DOMContentLoaded', () => G.Main.boot());
