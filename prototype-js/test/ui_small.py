import asyncio
from playwright.async_api import async_playwright
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch()
        pg = await br.new_page(viewport={'width': 1280, 'height': 720})
        errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto('file:///home/claude/heroes/dist/heroes.html'); await pg.wait_for_timeout(300)
        await pg.click('text=Combat sandbox'); await pg.wait_for_timeout(200)
        await pg.evaluate("(()=>{const c=G.Sandbox.cfg; c.sides[0].stacks.push({key:'alpha.2.1.r',count:6},{key:'alpha.1.1.@beta.2.0.',count:4},{key:'alpha.4.0.',count:1}); c.sides[1].stacks.push({key:'beta.3.1.m',count:3},{key:'beta.1.1.r',count:12},{key:'beta.2.2.',count:4}); G.Sandbox.render();})()")
        await pg.screenshot(path='test/shots/sandbox_small.png')
        await pg.click('text=Simulate ×100'); await pg.wait_for_timeout(9000)
        print(await pg.evaluate("document.getElementById('modal').innerText"))
        await pg.click('#modal button.primary'); await pg.wait_for_timeout(200)
        await pg.click('text=Fight!'); await pg.wait_for_timeout(500)
        # engage then show lines
        await pg.evaluate("(()=>{const b=G.BattleUI.b; for(let i=0;i<4;i++){ const a=b.turnStack(); if(!a||b.sides[a.side].ai){G.CombatAI.step(b);continue;} const t=b.enemiesOf(a).find(t=>!b.checkEngage(a,t)); if(t) b.act('engage',t.id); else { const g=b.alliesOf(a).find(x=>!b.checkGuard(a,x)); g? b.act('guard',g.id): b.act('seek'); } } G.BattleUI.render();})()")
        await pg.wait_for_timeout(600)
        await pg.screenshot(path='test/shots/battle_small.png')
        print('errors', errs)
        await br.close()
asyncio.run(main())
