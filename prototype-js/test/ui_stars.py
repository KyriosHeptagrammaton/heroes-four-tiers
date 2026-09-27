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
        await pg.evaluate("G.WorldUI.zoom(1.6)"); await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/stars1.png')
        await pg.wait_for_timeout(1200)
        await pg.screenshot(path='test/shots/stars2.png', clip={'x':600,'y':450,'width':400,'height':300})
        fps = await pg.evaluate("new Promise(r=>{let n=0;const t0=performance.now();const o=G.WorldUI.draw.bind(G.WorldUI);G.WorldUI.draw=function(){n++;o();};setTimeout(()=>{G.WorldUI.draw=o;r(n/((performance.now()-t0)/1000));},2000);})")
        print('redraws/sec', round(fps,1), 'errors', errs)
        await br.close()
asyncio.run(main())
