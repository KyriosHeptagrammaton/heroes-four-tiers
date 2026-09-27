import asyncio, sys
from playwright.async_api import async_playwright
URL = 'file:///home/claude/heroes/dist/heroes.html'
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch()
        pg = await br.new_page(viewport={'width': 1440, 'height': 900})
        errs = []
        pg.on('console', lambda m: errs.append(m.text) if m.type in ('error','warning') else None)
        pg.on('pageerror', lambda e: errs.append('PAGEERR ' + str(e)))
        await pg.goto(URL)
        await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/menu.png')
        await pg.click('text=Combat sandbox')
        await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/sandbox.png')
        await pg.click('text=Fight!')
        await pg.wait_for_timeout(600)
        await pg.screenshot(path='test/shots/battle1.png')
        # play: human is attacker side 0. Repeatedly: if our stack's turn press A then click first valid target; else wait
        for i in range(60):
            over = await pg.evaluate('G.BattleUI.b.over')
            if over: break
            human = await pg.evaluate('G.BattleUI.humanTurn()')
            if not human:
                await pg.wait_for_timeout(450); continue
            kind = await pg.evaluate('(G.BattleUI.b.current()||{}).type')
            if kind == 'hero':
                # cast flame on an enemy if possible, then end
                ok = await pg.evaluate('''(() => { const b=G.BattleUI.b; const e=b.stacksOf(1)[0]; if(!e) return false; const err=b.cast(0,'flame',e.id); G.BattleUI.render(); return !err; })()''')
                await pg.wait_for_timeout(150)
                btn = pg.locator('button:has-text("End command")')
                if await btn.count(): await btn.first.click()
                await pg.wait_for_timeout(150); continue
            await pg.keyboard.press('a')
            await pg.wait_for_timeout(120)
            v = pg.locator('.stack.valid')
            if await v.count():
                await v.first.click()
            else:
                await pg.keyboard.press('Escape'); await pg.keyboard.press('s')
            await pg.wait_for_timeout(200)
            if i == 6:
                await pg.screenshot(path='test/shots/battle2.png')
        await pg.wait_for_timeout(900)
        await pg.screenshot(path='test/shots/battle_end.png')
        print('over:', await pg.evaluate('JSON.stringify(G.BattleUI.b.over)'), 'round', await pg.evaluate('G.BattleUI.b.round'))
        print('errors:', errs[:10])
        await br.close()
asyncio.run(main())
