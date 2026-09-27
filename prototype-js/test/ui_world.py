import asyncio
from playwright.async_api import async_playwright
URL = 'file:///home/claude/heroes/dist/heroes.html'
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch()
        pg = await br.new_page(viewport={'width': 1440, 'height': 900})
        errs = []
        pg.on('console', lambda m: errs.append(m.text) if m.type in ('error',) else None)
        pg.on('pageerror', lambda e: errs.append('PAGEERR ' + str(e)))
        await pg.goto(URL); await pg.wait_for_timeout(300)
        await pg.click('text=New hotseat game'); await pg.wait_for_timeout(200)
        await pg.screenshot(path='test/shots/newgame.png')
        await pg.click('button:has-text("Start")'); await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/handoff.png')
        await pg.click('button:has-text("show my lands")'); await pg.wait_for_timeout(600)
        await pg.screenshot(path='test/shots/world1.png')
        # plan a path to a road tile a few cards away via JS helper, then click it twice
        info = await pg.evaluate('''(() => { const S=G.Game.state, h=G.World.hero(G.WorldUI.selHero);
          // find the farthest reachable node within mp along road via BFS
          const P=S.players[S.cur]; let best=null;
          for (let c=0;c<S.map.cards.length;c++){ if(!P.seen[c]) continue; const card=S.map.cards[c];
            for (const [x,y] of G.WorldGen.roadTiles(card)) { if (G.World.objAt(c,x,y)) continue; const p=G.World.path(h,{c,x,y}); if(p && p.length<=h.mp && (!best||p.length>best.len)) best={c,x,y,len:p.length}; } }
          const r=G.WorldUI.tileRect(best.c,best.x,best.y); const cv=G.WorldUI.cv.getBoundingClientRect(); return {x:cv.left+r.cx, y:cv.top+r.cy, best}; })()''')
        print('target', info)
        await pg.mouse.click(info['x'], info['y']); await pg.wait_for_timeout(200)
        await pg.screenshot(path='test/shots/world_path.png')
        await pg.mouse.click(info['x'], info['y']); await pg.wait_for_timeout(1500)
        await pg.screenshot(path='test/shots/world_moved.png')
        if await pg.evaluate("document.getElementById('modal-bg').classList.contains('on')"):
            print('site modal:', (await pg.evaluate("document.getElementById('modal').innerText"))[:80].replace('\n',' '))
            if await pg.locator('#modal .pop-choice > div').count(): await pg.click('#modal .pop-choice > div >> nth=0')
            else: await pg.click('#modal button >> nth=-1')
            await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/world_after_site.png')
        # open town screen
        await pg.evaluate('G.TownUI.open(G.Game.state.players[0].capital)'); await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/town.png')
        await pg.click('button:has-text("◂ Map")'); await pg.wait_for_timeout(300)
        # hero screen
        await pg.evaluate('G.ArmyUI.heroScreen(G.WorldUI.selHero)'); await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/hero.png')
        await pg.evaluate('G.UI.closeModal()')
        await pg.evaluate('G.ArmyUI.armyScreen(G.WorldUI.selHero)'); await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/army.png')
        await pg.evaluate('G.UI.closeModal()')
        # end turn -> handoff p2 -> begin -> end turn -> day 2
        await pg.evaluate('G.Game.endTurn()'); await pg.wait_for_timeout(300)
        await pg.click('button:has-text("show my lands")'); await pg.wait_for_timeout(400)
        await pg.screenshot(path='test/shots/world_p2.png')
        await pg.evaluate('G.Game.endTurn()'); await pg.wait_for_timeout(300)
        print('day', await pg.evaluate('G.Game.state.day'))
        print('errors:', errs[:10])
        await br.close()
asyncio.run(main())
