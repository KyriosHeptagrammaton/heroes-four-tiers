import asyncio
from playwright.async_api import async_playwright
URL = 'file:///home/claude/heroes/dist/heroes.html'
AUTOPLAY = '''(async () => { const b = G.BattleUI.b; b.sides[0].ai = true; b.sides[1].ai = true; G.BattleUI.aiDelay = 5; G.BattleUI.render(); })()'''
async def wait_battle_end(pg):
    for i in range(400):
        if await pg.evaluate('!!(G.BattleUI.b && G.BattleUI.b.over && G.BattleUI.ended)'): break
        await pg.wait_for_timeout(50)
    await pg.wait_for_timeout(600)
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch()
        pg = await br.new_page(viewport={'width': 1440, 'height': 900})
        errs = []
        pg.on('console', lambda m: errs.append(m.text) if m.type in ('error',) else None)
        pg.on('pageerror', lambda e: errs.append('PAGEERR ' + str(e)))
        await pg.goto(URL); await pg.wait_for_timeout(300)
        await pg.evaluate("G.Game.newGame({names:['Ann','Bob'],factions:['alpha','delta'],cls:['warlord','mage'],seed:11})")
        await pg.click('button:has-text("show my lands")'); await pg.wait_for_timeout(300)
        # --- 1. fight a monster
        r = await pg.evaluate('''(() => { const S=G.Game.state, W=G.World; const h=W.heroesOf(0)[0];
          let found=null; S.map.cards.forEach((c,i)=>c.objs.forEach(o=>{ if(!found && o.type==='monster') found={c:i,o}; }));
          const nb = W.neighbors(0,h,{c:found.c,x:found.o.x,y:found.o.y}).find(n=>!W.objAt(n.c,n.x,n.y));
          h.pos={c:nb.c,x:nb.x,y:nb.y}; h.mp=10; h.army=[{key:'alpha.1.1.',count:40,splits:2,name:''},{key:'alpha.2.1.r',count:12,splits:1,name:''},{key:'alpha.3.0.',count:8,splits:1,name:''}];
          W.revealAll(0); G.WorldUI.enter();
          G.Game.interact(h,{c:found.c,x:found.o.x,y:found.o.y}); return G.WorldUI.monsterText(found.o.army); })()''')
        print('monster:', r)
        await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/time_choice.png')
        await pg.click('button:has-text("Dawn")'); await pg.wait_for_timeout(500)
        await pg.screenshot(path='test/shots/world_battle.png')
        await pg.evaluate(AUTOPLAY)
        await wait_battle_end(pg)
        await pg.click('#modal button:has-text("Continue")'); await pg.wait_for_timeout(500)
        await pg.screenshot(path='test/shots/after_battle.png')
        print('report:', await pg.evaluate("document.getElementById('modal').innerText"))
        await pg.click('#modal button:has-text("OK")'); await pg.wait_for_timeout(300)
        # --- 2. hero vs hero: Bob attacks Ann (defender chooses ground)
        await pg.evaluate('''(() => { const S=G.Game.state, W=G.World; const a=W.heroesOf(0)[0], b=W.heroesOf(1)[0];
          const nb = W.neighbors(1,b,a.pos).find(n=>!W.objAt(n.c,n.x,n.y) && !W.heroAt(n.c,n.x,n.y));
          b.pos={c:nb.c,x:nb.x,y:nb.y}; b.mp=10; b.army=[{key:'delta.1.0.',count:30,splits:3,name:''},{key:'delta.2.0.',count:9,splits:1,name:''}];
          S.cur=1; W.revealAll(1); G.WorldUI.enter(); G.WorldUI.selHero=b.id;
          G.Game.interact(b, a.pos); })()''')
        await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/def_handoff.png')
        await pg.click('#handoff button'); await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/ground_choice.png')
        await pg.click('#modal button >> nth=0'); await pg.wait_for_timeout(300)
        await pg.click('#handoff button'); await pg.wait_for_timeout(300)
        await pg.click('button:has-text("Night")'); await pg.wait_for_timeout(400)
        await pg.screenshot(path='test/shots/pvp_battle.png')
        await pg.evaluate(AUTOPLAY)
        await wait_battle_end(pg)
        await pg.click('#modal button:has-text("Continue")'); await pg.wait_for_timeout(500)
        print('report2:', await pg.evaluate("document.getElementById('modal').innerText"))
        await pg.click('#modal button:has-text("OK")'); await pg.wait_for_timeout(300)
        # --- 3. siege of a neutral town by whoever is alive
        res = await pg.evaluate('''(() => { const S=G.Game.state, W=G.World; S.cur=0; W.revealAll(0); const hs=W.heroesOf(S.cur); if(!hs.length) return 'no hero';
          const h=hs[0]; const t=Object.values(S.towns).find(t=>t.owner<0);
          const nb = W.neighbors(S.cur,h,{c:t.c,x:t.x,y:t.y}).find(n=>!W.objAt(n.c,n.x,n.y)&&!W.heroAt(n.c,n.x,n.y));
          h.pos={c:nb.c,x:nb.x,y:nb.y}; h.mp=10; h.army=[{key:G.Units.key(h.faction,1,1,''),count:60,splits:3,name:''},{key:G.Units.key(h.faction,3,1,''),count:10,splits:1,name:''}];
          W.computeVisible(S.cur); G.WorldUI.enter(); G.Game.interact(h,{c:t.c,x:t.x,y:t.y}); return t.name+' garrison '+JSON.stringify(t.garrison); })()''')
        print('siege:', res)
        await pg.wait_for_timeout(300)
        await pg.click('button:has-text("Midday")'); await pg.wait_for_timeout(400)
        await pg.evaluate(AUTOPLAY)
        await wait_battle_end(pg)
        await pg.click('#modal button:has-text("Continue")'); await pg.wait_for_timeout(500)
        print('report3:', await pg.evaluate("document.getElementById('modal').innerText"))
        print('town owners', await pg.evaluate("JSON.stringify(Object.values(G.Game.state.towns).map(t=>t.owner))"))
        print('errors:', errs[:10])
        await br.close()
asyncio.run(main())
