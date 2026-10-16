// Render the current embedded Windows UI with empty credentials and offline state.
// Setup: npm install --no-save --prefix Windows/tests playwright@1.58.2
// Run from the repository: node scripts/capture-screenshots.cjs
const { chromium } = require(require.resolve('playwright', { paths: [require('node:path').join(__dirname, '../Windows/tests')] }));
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

(async () => {
  const root = path.resolve(__dirname, '..');
  const output = path.join(root, 'docs/screenshots');
  await fs.mkdir(output, { recursive: true });
  const project = await fs.readFile(path.join(root, 'Windows/source/CampusConnect.csproj'), 'utf8');
  const version = project.match(/<Version>([^<]+)<\/Version>/)[1];
  const browser = await chromium.launch(process.env.CAMPUS_CHROME_PATH
    ? { executablePath: process.env.CAMPUS_CHROME_PATH, headless: true } : { headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 860 }, colorScheme: 'light', deviceScaleFactor: 1 });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    // Only local application assets are permitted; no school pages or accounts are used.
    await page.route(/^https?:/, route => route.abort());
    await page.addInitScript(() => {
      window.chrome = { webview: { postMessage() {}, addEventListener() {} } };
    });
    await page.goto(pathToFileURL(path.join(root, 'Windows/source/Desktop.html')).href);
    await page.evaluate(() => campus.receive({ kind: 'startup', enabled: false, available: true }));
    assert.equal(await page.locator('.version').textContent(), `v${version} · Windows`);
    const profile = {
      ssid: 'HNPI-STU', portalUrl: 'http://192.168.0.123', username: '', serviceOption: '',
      useSavedWifiProfile: false, portalEnabled: true, autoSubmit: true, automatic: false,
      userSelector: '', passwordSelector: '', submitSelector: ''
    };
    const state = {
      target: 'HNPI-STU', wiredMode: false, currentSsid: null, campusConnected: false,
      internetOnline: false, connectionTitle: '当前未连接 Wi-Fi', automatic: false, busy: false,
      permissionNeeded: false, lastScan: '', status: '准备就绪',
      portalStatus: '连接校园网后，在这里完成上网认证。', portalAddress: '', networks: []
    };
    async function load(profile, state) {
      await page.evaluate(({ profile, state }) => {
        campus.receive({ kind: 'profile', profile, password: '' });
        campus.receive({ kind: 'state', state });
      }, { profile, state });
      assert.equal(await page.locator('#username').inputValue(), '');
      assert.equal(await page.locator('#password').inputValue(), '');
    }
    async function capture(name, target) {
      await page.setViewportSize({ width: 1280, height: 860 });
      await page.evaluate(target => campus.receive({ kind: 'page', page: target }), target);
      await page.waitForFunction(() => document.getAnimations().length === 0);
      if (target === 'settings') {
        const overflow = await page.locator('#page-settings').evaluate(e => e.scrollHeight - e.clientHeight);
        if (overflow > 0) await page.setViewportSize({ width: 1280, height: 860 + overflow });
      }
      await page.locator('#page-' + target).evaluate(e => { e.scrollTop = 0; });
      await page.evaluate(() => document.fonts.ready);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
      assert.equal(await page.locator('#page-' + target).evaluate(e => e.scrollHeight > e.clientHeight), false);
      const file = path.join(output, name + '.png');
      await page.screenshot({ path: file, animations: 'disabled' });
      console.log(`Captured ${name}.png (${page.viewportSize().width}×${page.viewportSize().height})`);
    }
    await load(profile, state);
    await capture('windows-dashboard', 'dashboard');
    await capture('windows-settings', 'settings');
    await capture('windows-portal', 'portal');
    await load({ ...profile, ssid: '' }, {
      ...state, target: '有线网络', wiredMode: true, connectionTitle: '有线网络未连接，请插好网线',
      status: '有线网络未连接，请插好网线并在系统中启用以太网。'
    });
    await capture('windows-wired-settings', 'settings');
    await capture('windows-wired-dashboard', 'dashboard');
    assert.deepEqual(errors, []);
    console.log(`PASS: five ${version} UI screenshots, empty credentials, no overflow or script errors.`);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
