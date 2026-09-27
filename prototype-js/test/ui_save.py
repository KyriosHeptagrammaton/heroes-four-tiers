import asyncio
from playwright.async_api import async_playwright
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch()
        pg = await br.new_page(viewport={'width': 1440, 'height': 900})
        errs = []
        pg.on('pageerror', lambda e: errs.append('PAGEERR ' + str(e)))
        await pg.goto('http://127.0.0.1:46763/'); await pg.wait_for_timeout(600)
        print('api', await pg.evaluate('G.Game.api'))
        await pg.evaluate("G.Game.newGame({names:['Ann','Bob'],factions:['gamma','beta'],cls:['scholar','paragon'],seed:77})")
        await pg.click('#handoff button'); await pg.wait_for_timeout(300)
        ok = await pg.evaluate("G.Game.save('test save')")
        print('saved', ok, await pg.evaluate("G.Game.listSaves().then(l=>JSON.stringify(l.map(x=>x.name)))"))
        before = await pg.evaluate("JSON.stringify(Object.values(G.Game.state.heroes).map(h=>h.name))")
        await pg.evaluate("G.Game.state=null; G.Main.menu()")
        await pg.click('text=Load game'); await pg.wait_for_timeout(400)
        await pg.click('#modal button:has-text("test save")'); await pg.wait_for_timeout(400)
        await pg.click('#handoff button'); await pg.wait_for_timeout(500)
        after = await pg.evaluate("JSON.stringify(Object.values(G.Game.state.heroes).map(h=>h.name))")
        print('roundtrip ok', before == after, after)
        await pg.screenshot(path='test/shots/loaded.png')
        print('errors', errs)
        await br.close()
asyncio.run(main())
