const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const template = fs.readFileSync(path.join(__dirname, '../source/PortalTemplate.js'), 'utf8');
// Verify the Mac embedded script stays identical, including regex escaping.
const core = fs.readFileSync(path.join(__dirname, '../../macOS/source/Core.swift'), 'utf8');
const macScript = core.slice(core.indexOf('        (() => {'), core.indexOf('        """', core.indexOf('        (() => {')))
  .split('\n').map(line => line.startsWith('        ') ? line.slice(8) : line).join('\n')
  .replace('\\(json)', '/*CAMPUS_CONFIG*/').replaceAll('\\\\', '\\');
// Windows alone adds optional service selection; shared credential handling stays aligned.
assert.equal(macScript, template.replace(/  \/\/ WINDOWS_SERVICE_OPTION_BEGIN[\s\S]*?  \/\/ WINDOWS_SERVICE_OPTION_END\n/, ''));
const cfg = {origin:'http://portal.test', username:'test-account\'"', password:'test-password\'"',
  userSelector:'', passwordSelector:'', submitSelector:'', submit:true};
const script = overrides => template.replace('/*CAMPUS_CONFIG*/', JSON.stringify({...cfg, ...overrides}));
// Reduced from the school's ePortal markup: visible readonly tips, hidden
// inputs, blur re-hiding empty fields and an image-only anchor login control.
const fixture = `<!doctype html><html><body>
<input id="username_tip" name="username_tip" readonly value="用户名">
<input id="username" name="username" type="text" style="display:none">
<input id="pwd_tip" readonly value="密码">
<input id="pwd" type="password" style="display:none">
<a id="loginLink" tabindex="-1"><div style="width:275px;height:54px;background:blue"></div></a>
<script>
window.clicks = 0; window.events = [];
for (const id of ['username','pwd']) {
  const input = document.getElementById(id), tip = document.getElementById(id+'_tip');
  tip.onfocus = () => {input.style.display='';input.focus();tip.style.display='none';};
  input.onblur = () => {if (!input.value) {input.style.display='none';tip.style.display='';}};
  for (const event of ['input','change']) input.addEventListener(event,()=>events.push(id+':'+event));
}
document.getElementById('loginLink').onclick = () => clicks++;
</script></body></html>`;
(async () => {
  const browser = await chromium.launch(process.env.CAMPUS_CHROME_PATH ? {executablePath:process.env.CAMPUS_CHROME_PATH,headless:true} : {headless:true});
  try {
    const page = await browser.newPage();
    await page.route('http://portal.test/**', route => route.fulfill({contentType:'text/html; charset=utf-8',body:fixture}));
    const reset = () => page.goto('http://portal.test/eportal/index.jsp');
    await reset();
    assert.equal(await page.evaluate(script()), 'submitted');
    assert.equal(await page.locator('#username').inputValue(),cfg.username);
    assert.equal(await page.locator('#pwd').inputValue(),cfg.password);
    assert.equal(await page.locator('#username').isVisible(),true);
    assert.equal(await page.locator('#pwd').isVisible(),true);
    assert.equal(await page.locator('#username_tip').inputValue(),'用户名');
    assert.equal(await page.locator('#pwd_tip').inputValue(),'密码');
    assert.equal(await page.evaluate(script()), 'already-submitted');
    assert.equal(await page.evaluate(()=>clicks),1);
    assert.deepEqual(await page.evaluate(()=>events),['username:input','username:change','pwd:input','pwd:change']);
    // An inactive/hidden WebView can fail to deliver native focus events.
    await reset();
    await page.evaluate(() => {
      for (const id of ['username_tip','pwd_tip']) document.getElementById(id).focus = () => {};
    });
    assert.equal(await page.evaluate(script()), 'submitted');
    assert.equal(await page.locator('#pwd').inputValue(), cfg.password);
    assert.equal(await page.evaluate(() => clicks), 1);
    assert.equal(await page.evaluate(script()), 'already-submitted');
    // Some portal variants reveal the password only from a click handler.
    await reset();
    await page.evaluate(() => {
      const tip = document.getElementById('pwd_tip');
      tip.onclick = tip.onfocus; tip.onfocus = null;
    });
    assert.equal(await page.evaluate(script()), 'submitted');
    assert.equal(await page.locator('#pwd').inputValue(), cfg.password);
    assert.equal(await page.evaluate(() => clicks), 1);
    // Delegated focus handlers must also work without native focus.
    await reset();
    await page.evaluate(() => {
      const tip = document.getElementById('pwd_tip'), activate = tip.onfocus;
      tip.onfocus = null; tip.focus = () => {};
      document.addEventListener('focusin', event => { if (event.target === tip) activate(); });
    });
    assert.equal(await page.evaluate(script()), 'submitted');
    assert.equal(await page.locator('#pwd').inputValue(), cfg.password);
    // Do not submit if school input handlers discard the supplied password.
    await reset();
    await page.locator('#pwd').evaluate(input => input.onchange = () => { input.value = ''; });
    assert.equal(await page.evaluate(script()), 'missing-fields');
    assert.equal(await page.evaluate(() => clicks), 0);
    await page.locator('#pwd').evaluate(input => input.onchange = null);
    assert.equal(await page.evaluate(script()), 'submitted');
    await reset();
    assert.equal(await page.evaluate(script({submit:false})), 'filled');
    assert.equal(await page.evaluate(()=>clicks),0);
    await reset();
    assert.equal(await page.evaluate(script({origin:'http://different.test'})), 'wrong-origin');
    assert.equal(await page.locator('#pwd').inputValue(),'');
    assert.equal(await page.locator('#pwd').isVisible(),false);
    assert.equal(await page.evaluate(script({userSelector:'['})), 'invalid-selector');
    assert.equal(await page.locator('#username').inputValue(),'');
    assert.equal(await page.evaluate(script({userSelector:'#username_tip'})), 'missing-fields');
    assert.equal(await page.evaluate(script({userSelector:'#username',passwordSelector:'#pwd',submitSelector:'#loginLink'})), 'submitted');
    await reset();
    await page.locator('#loginLink').evaluate(e=>e.disabled=true);
    assert.equal(await page.evaluate(script()), 'missing-submit');
    assert.equal(await page.evaluate(()=>clicks),0);
    await page.locator('#loginLink').evaluate(e=>e.disabled=false);
    assert.equal(await page.evaluate(script()), 'submitted');
    assert.equal(await page.evaluate(()=>clicks),1);
    await reset();
    await page.locator('#pwd_tip').evaluate(e=>e.onfocus=null);
    assert.equal(await page.evaluate(script()), 'missing-fields');
    assert.equal(await page.locator('#pwd').inputValue(),'');
    assert.equal(await page.evaluate(()=>clicks),0);
    await reset();
    await page.locator('#pwd').evaluate(e=>e.disabled=true);
    assert.equal(await page.evaluate(script()), 'missing-fields');
    assert.equal(await page.evaluate(()=>clicks),0);
    await reset();
    await page.setContent('<input readonly name="username_tip" value="提示"><input name="account"><input type="password"><a href="#" onclick="window.genericClicks=(window.genericClicks||0)+1">认证</a>');
    assert.equal(await page.evaluate(script()),'submitted');
    assert.equal(await page.locator('[name=account]').inputValue(),cfg.username);
    assert.equal(await page.locator('[readonly]').inputValue(),'提示');
    assert.equal(await page.evaluate(()=>genericClicks),1);
    // Native select: exact visible name, events, no selection when blank, no wrong submission.
    const nativeService = '<input name="username"><input type="password"><select id="service"><option value="">请选择服务</option><option value="unicom">联通接入服务</option><option value="mobile">移动接入服务</option></select><button type="submit" onclick="window.clicks++">登录</button>';
    await reset();
    await page.setContent(nativeService);
    await page.evaluate(() => { window.clicks=0; window.serviceEvents=[]; for (const type of ['input','change']) document.querySelector('select').addEventListener(type,()=>serviceEvents.push(type)); });
    assert.equal(await page.evaluate(script({serviceOption:'  联通接入服务  '})), 'submitted');
    assert.equal(await page.locator('#service').inputValue(),'unicom');
    assert.deepEqual(await page.evaluate(()=>serviceEvents),['input','change']);
    assert.equal(await page.evaluate(()=>clicks),1);
    await reset(); await page.setContent(nativeService);
    assert.equal(await page.evaluate(script({serviceOption:''})), 'submitted');
    assert.equal(await page.locator('#service').inputValue(),'');
    await reset(); await page.setContent(nativeService);
    assert.equal(await page.evaluate(script({serviceOption:'联通'})), 'missing-service');
    assert.equal(await page.evaluate(()=>clicks),0);
    assert.equal(await page.evaluate(script({serviceOption:'不存在'})), 'missing-service');
    await page.locator('option[value=unicom]').evaluate(e=>e.disabled=true);
    assert.equal(await page.evaluate(script({serviceOption:'联通接入服务'})), 'missing-service');
    await page.locator('option[value=unicom]').evaluate(e=>e.disabled=false);
    await page.locator('#service').evaluate(e=>e.onchange=()=>{e.value='';});
    assert.equal(await page.evaluate(script({serviceOption:'联通接入服务'})), 'missing-service');
    assert.equal(await page.evaluate(()=>clicks),0);
    await reset(); await page.setContent(nativeService + '<select><option>联通接入服务</option></select>');
    assert.equal(await page.evaluate(script({serviceOption:'联通接入服务'})), 'missing-service');
    // Delayed services can arrive between retries.
    await reset(); await page.setContent(nativeService.replace('<option value="unicom">联通接入服务</option>',''));
    assert.equal(await page.evaluate(script({serviceOption:'联通接入服务'})), 'missing-service');
    await page.locator('#service').evaluate(e=>e.add(new Option('联通接入服务','unicom')));
    assert.equal(await page.evaluate(script({serviceOption:'联通接入服务',submit:false})), 'filled');
    assert.equal(await page.locator('#service').inputValue(),'unicom');
    assert.equal(await page.evaluate(()=>clicks),0);
    // School ePortal uses clickable divs and a hidden value, not a native select.
    const addServiceMenu = async (lazy=false) => page.evaluate(lazy => {
      document.body.insertAdjacentHTML('beforeend', '<input type="hidden" id="net_access_type"><div id="serviceShowHideTop"><span id="selectDisname">请选择服务</span></div><div id="serviceShowHide" style="display:none"></div>');
      window.menuOpens=0; window.serviceClicks=0;
      window.populateServices = () => {
        const menu=document.getElementById('serviceShowHide');
        menu.innerHTML='<div id="bch_service_0"><div><div id="_service_0">联通接入服务</div></div></div>';
        document.getElementById('bch_service_0').onclick=()=>{
          window.serviceClicks++;
          document.getElementById('net_access_type').value='unicom-internal';
          document.getElementById('selectDisname').textContent='联通接入服务';
          menu.style.display='none';
          window.domainSelected='school.example';
        };
      };
      if(!lazy) populateServices();
      document.getElementById('serviceShowHideTop').onclick=()=>{
        window.menuOpens++; document.getElementById('serviceShowHide').style.display='block';
      };
    },lazy);
    await reset(); await addServiceMenu();
    assert.equal(await page.evaluate(script({serviceOption:'联通接入服务'})), 'submitted');
    assert.equal(await page.locator('#net_access_type').inputValue(),'unicom-internal');
    assert.equal(await page.evaluate(()=>domainSelected),'school.example');
    assert.equal(await page.evaluate(()=>serviceClicks),1);
    assert.equal(await page.evaluate(()=>clicks),1);
    await reset(); await addServiceMenu(true);
    assert.equal(await page.evaluate(script({serviceOption:'联通接入服务'})), 'missing-service');
    assert.equal(await page.evaluate(script({serviceOption:'联通接入服务'})), 'missing-service');
    assert.equal(await page.evaluate(()=>menuOpens),1);
    await page.evaluate(()=>populateServices());
    assert.equal(await page.evaluate(script({serviceOption:'联通接入服务',submit:false})), 'filled');
    assert.equal(await page.evaluate(()=>clicks),0);
    assert.equal(await page.evaluate(script({serviceOption:'联通接入服务'})), 'submitted');
    assert.equal(await page.evaluate(()=>serviceClicks),1);
    await reset(); await addServiceMenu();
    await page.locator('#bch_service_0').evaluate(e=>e.onclick=()=>{});
    assert.equal(await page.evaluate(script({serviceOption:'联通接入服务'})), 'missing-service');
    assert.equal(await page.evaluate(()=>clicks),0);
    await reset(); await addServiceMenu();
    await page.locator('#bch_service_0').evaluate(e=>{
      const handler=e.onclick;
      e.onclick=()=>{handler();document.body.insertAdjacentHTML('beforeend','<input id="operatorPwd">');};
    });
    assert.equal(await page.evaluate(script({serviceOption:'联通接入服务'})), 'manual-required');
    assert.equal(await page.evaluate(()=>clicks),0);
    await reset();
    assert.equal(await page.evaluate(script({serviceOption:'联通接入服务'})), 'missing-service');
    assert.equal(await page.evaluate(()=>clicks),0);
    await reset();
    assert.equal(await page.evaluate(script({serviceOption:''})), 'submitted');
    console.log('PASS: service selection (native/ePortal/lazy/blank/missing/disabled/ambiguous/rejected/operator fields) and ePortal real DOM, hidden inputs, readonly tips, focus/blur, image link, delayed button, explicit selectors, origin, deduplication and shared Mac/Windows credential script parity.');
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
