import asyncio
from playwright.async_api import async_playwright
URL = 'file:///home/claude/heroes/dist/heroes.html'
async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch()
        pg = await br.new_page(viewport={'width': 1440, 'height': 900})
        errs = []
        pg.on('console', lambda m: errs.append(m.text) if m.type == 'error' else None)
        pg.on('pageerror', lambda e: errs.append('PAGEERR ' + str(e)))
        await pg.goto(URL); await pg.wait_for_timeout(300)
        await pg.evaluate("G.Game.newGame({names:['Ann','Bob'],factions:['beta','gamma'],cls:['warlord','mage'],seed:21})")
        await pg.click('#handoff button'); await pg.wait_for_timeout(400)
        # --- town: build T2 dwelling + drill yard, recruit to hero, upgrade with essence
        await pg.evaluate("(()=>{const S=G.Game.state; S.players[0].gold=20000; S.players[0].essence[1]=50; })()")
        hid = await pg.evaluate("G.WorldUI.selHero")
        await pg.evaluate(f"G.TownUI.open(G.Game.state.players[0].capital, '{hid}')"); await pg.wait_for_timeout(300)
        await pg.click('.bcard:has-text("T1 drill yard") button'); await pg.wait_for_timeout(200)
        await pg.click('.bcard:has-text("Tier 1 ·") button:has-text("→ Hero")'); await pg.wait_for_timeout(200)
        await pg.screenshot(path='test/shots/town2.png')
        await pg.click('button:has-text("Upgrade creatures")'); await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/upgrade.png')
        btns = pg.locator('#modal button:not(.primary)')
        n = await btns.count(); print('upgrade options', n)
        if n: await btns.first.click(); await pg.wait_for_timeout(200)
        await pg.click('#modal button.primary'); await pg.wait_for_timeout(200)
        print('army', await pg.evaluate(f"JSON.stringify(G.World.hero('{hid}').army)"))
        # --- recruit more T1 past weekly pool to check escalation
        print('price 6', await pg.evaluate("(()=>{const t=G.Game.state.towns[G.Game.state.players[0].capital]; return [G.World.priceFor(t,1,1), G.World.priceFor(t,1,6), G.World.priceFor(t,1,12)]})()"))
        await pg.click('button:has-text("◂ Map")'); await pg.wait_for_timeout(300)
        # --- mount riders in army screen
        await pg.evaluate(f"(()=>{{const h=G.World.hero('{hid}'); h.army=[{{key:'beta.1.1.',count:10,splits:1,name:''}},{{key:'beta.2.0.',count:12,splits:1,name:''}}]; G.ArmyUI.armyScreen('{hid}')}})()"); await pg.wait_for_timeout(300)
        await pg.fill('#modal input[type=number]', '4')
        await pg.dispatch_event('#modal input[type=number]', 'change')
        await pg.click('#modal button:has-text("Mount")'); await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/mounted.png')
        print('after mount', await pg.evaluate(f"JSON.stringify(G.World.hero('{hid}').army.map(g=>[g.key,g.count]))"))
        await pg.click('#modal button.primary'); await pg.wait_for_timeout(200)
        # --- skill choice
        await pg.evaluate(f"(()=>{{const h=G.World.hero('{hid}'); h.skillXp.scouting=10; h.skillXp.tactics=10; G.Game.checkSkillChoices();}})()"); await pg.wait_for_timeout(300)
        await pg.screenshot(path='test/shots/skillchoice.png')
        await pg.click('#modal .pop-choice > div >> nth=0'); await pg.wait_for_timeout(200)
        print('skills', await pg.evaluate(f"JSON.stringify(G.World.hero('{hid}').skills)"), await pg.evaluate(f"JSON.stringify([G.World.hero('{hid}').skillXp.scouting, G.World.hero('{hid}').skillXp.tactics])"))
        # --- park train and go off-road
        r = await pg.evaluate(f"""(()=>{{const W=G.World,h=W.hero('{hid}'),P=G.Game.state.players[0]; h.mp=20; G.Game.parkTrain(h);
            const off=[]; for(const n of W.neighbors(0,h,h.pos)) off.push(W.enterable(h,n,P)); return JSON.stringify(off); }})()""")
        print('after park, neighbour enterability', r)
        # --- transcendence: teleport hero onto own trans card edge and cross twice
        await pg.evaluate(f"""(()=>{{const S=G.Game.state,W=G.World,h=W.hero('{hid}'),P=S.players[0]; W.revealAll(0); h.train.state='none'; h.mp=50;
           const T=P.trans.cards[0]; const tc=W.card(T); h.pos={{c:T,x:0,y:0}};
           // simulate having stepped in from outside
           const x=W.cx(T), y=W.cy(T); let n=null; for(let e=0;e<4;e++){{ const r=W.cross(0,h,T,e===1?tc.size-1:0,e===2?tc.size-1:0,e); if(r) {{ n=r; break; }} }}
           h.pos={{c:n.c,x:n.x,y:n.y}}; W.computeVisible(0);
           const back=W.neighbors(0,h,h.pos).find(q=>q.c===T); W.step(h,back);
           const out=W.neighbors(0,h,h.pos).find(q=>q.c!==T); W.step(h,out);
           for(let k=0;k<6;k++){{ const nb=W.neighbors(0,h,h.pos).filter(q=>!W.enterable(h,q,P)&&P.trans.active&&P.trans.active.region.includes(q.c)); if(!nb.length) break; W.step(h,nb[nb.length-1]); }}
           G.WorldUI.enter(); G.WorldUI.cam.z=46; G.WorldUI.centerOnSel(); }})()""")
        await pg.wait_for_timeout(500)
        await pg.screenshot(path='test/shots/transcend.png')
        print('trans', await pg.evaluate("JSON.stringify({active:!!G.Game.state.players[0].trans.active, links:G.Game.state.players[0].trans.links.length})"))
        print('errors', errs[:10])
        await br.close()
asyncio.run(main())
