import asyncio
from playwright.async_api import async_playwright
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch(args=['--autoplay-policy=no-user-gesture-required'])
        pg = await br.new_page(viewport={'width': 1440, 'height': 900})
        errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
        bad = []; pg.on('response', lambda r: bad.append((r.status, r.url)) if 'music' in r.url and r.status >= 400 else None)
        await pg.goto('http://127.0.0.1:40433/'); await pg.wait_for_timeout(1500)
        async def state(label):
            print(label, await pg.evaluate("JSON.stringify({cur:G.Music.cur, blocked:G.Music.blocked, paused:G.Music.audio&&G.Music.audio.paused, t:G.Music.audio&&Math.round(G.Music.audio.currentTime*10)/10, ready:G.Music.audio&&G.Music.audio.readyState})"))
        await state('menu:')
        await pg.screenshot(path='test/shots/menu_music.png')
        await pg.evaluate("G.Game.newGame({names:['Ann','Bob'],factions:['alpha','beta'],cls:['warlord','mage'],seed:5})")
        await pg.click('#handoff button'); await pg.wait_for_timeout(1500)
        await state('world at capital:')
        # put hero on a forest and a swamp card
        for t in ['forest','swamp','mountain','badlands','plains']:
            await pg.evaluate(f"(()=>{{const S=G.Game.state,h=G.World.hero(G.WorldUI.selHero); const c=S.map.cards.findIndex(c=>c.t==='{t}'); h.pos={{c,x:0,y:0}}; }})()")
            await pg.wait_for_timeout(900)
            await state(f'hero on {t}:')
        await pg.evaluate("G.TownUI.open(G.Game.state.players[0].capital)"); await pg.wait_for_timeout(900)
        await state('town screen:')
        await pg.evaluate("G.Sandbox.init(); G.Sandbox.cfg.terrain='forest'; G.Sandbox.fight()"); await pg.wait_for_timeout(900)
        await state('forest battle:')
        await pg.evaluate("G.Music.toggle()"); await pg.wait_for_timeout(800)
        print('muted volume', await pg.evaluate("G.Music.audio.volume"))
        print('http errors', bad, 'errors', errs)
        await br.close()
asyncio.run(main())
