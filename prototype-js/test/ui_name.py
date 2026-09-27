import asyncio
from playwright.async_api import async_playwright
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch()
        pg = await br.new_page(viewport={'width': 1440, 'height': 900})
        errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto('file:///home/claude/heroes/dist/heroes.html'); await pg.wait_for_timeout(300)
        await pg.evaluate("G.Game.newGame({names:['Ann','Bob'],factions:['alpha','beta'],cls:['warlord','mage'],seed:5})")
        await pg.click('#handoff button'); await pg.wait_for_timeout(500)
        pos = await pg.evaluate("(()=>{const h=G.World.hero(G.WorldUI.selHero); const W=G.Game.state.map.W; const c=h.pos.c+1; const r=G.WorldUI.cardCenter(c); const b=G.WorldUI.cv.getBoundingClientRect(); return {x:b.left+r.x,y:b.top+r.y};})()")
        await pg.mouse.click(pos['x'], pos['y'], button='right'); await pg.wait_for_timeout(300)
        await pg.fill('#modal input', 'Whispering Vale'); await pg.keyboard.press('Enter'); await pg.wait_for_timeout(300)
        await pg.mouse.move(pos['x'], pos['y']); await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/named.png')
        print('name', await pg.evaluate("(()=>{const h=G.World.hero(G.WorldUI.selHero); return G.Game.state.map.cards[h.pos.c+1].name})()"), 'errors', errs)
        await br.close()
asyncio.run(main())
