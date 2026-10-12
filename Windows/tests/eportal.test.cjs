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
assert.equal(macScript, template);
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
    console.log('PASS: ePortal real DOM, hidden inputs, readonly tips, focus/blur, image link, delayed button, explicit selectors, origin, deduplication and Mac/Windows script parity.');
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
