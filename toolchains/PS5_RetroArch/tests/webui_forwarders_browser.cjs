/* The Game Forwarder page in Chromium against the native WebUI and a stand-in for
 * ShadowMountPlus (tests/test_webui_forwarders.py): the pictures a game offers (its logo
 * fitted, its cover filling the square, the ones it lacks greyed out); a tile made from
 * its cover, cropped square and sent as a 512x512 PNG, renamed, then deleted; the page fits
 * a phone. No production console writes. */
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_PATH || 'playwright');
const base = process.env.WEBUI_TEST_URL;

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium' });
  try {
    const errors = [];
    const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, reducedMotion: 'reduce' });
    await context.route('https://api.github.com/**', route => route.fulfill({ json: [] }));
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(error.message));
    page.on('dialog', dialog => dialog.accept());
    await page.goto(base + '/#forwarders');
    await page.waitForFunction(() => /ShadowMountPlus 1\.7/.test(document.querySelector('#forwarders-status').textContent));
    assert.equal(await page.textContent('#page-title'), 'Game Forwarder');
    assert.equal(await page.getAttribute('[data-page="forwarders"]', 'aria-current'), 'page');
    assert.match(await page.textContent('#forwarders-list'), /No tiles yet/);

    // a new tile: the system first, behind its icon, then one of its games
    await page.click('#forwarder-new');
    await page.waitForSelector('#forwarder-editor:not([hidden])');
    assert.match(await page.textContent('#forwarder-system'), /Super Nintendo/);
    assert.equal(await page.locator('#forwarder-system .system-icon img').count(), 1);
    await page.click('#forwarder-system');
    const systems = page.locator('#forwarder-systems li');
    assert.ok(await page.isVisible('#forwarder-systems'));
    assert.equal(await systems.count(), 1);
    assert.equal(await systems.first().getAttribute('aria-selected'), 'true');
    assert.equal(await systems.first().locator('.system-icon img').count(), 1);
    await page.keyboard.press('Escape');
    assert.ok(await page.isHidden('#forwarder-systems'));
    await page.click('#forwarder-system');
    await systems.first().click();
    assert.ok(await page.isHidden('#forwarder-systems'));
    // the game's name and core, its cover filling the square
    assert.equal(await page.inputValue('#forwarder-game'), 'snes/Game (World).zip');
    assert.equal(await page.inputValue('#forwarder-name'), 'Game (World)');
    assert.equal(await page.inputValue('#forwarder-core'), 'snes9x');
    const picture = () => page.$eval('input[name="forwarder-media"]:checked', input => input.value);
    const kind = value => `input[name="forwarder-media"][value="${value}"]`;
    const red = () => page.waitForFunction(() => {
      const pixel = document.querySelector('#forwarder-canvas').getContext('2d').getImageData(256, 256, 1, 1).data;
      return pixel[0] > 200 && pixel[1] < 60; // the red cover, not the dark ground
    });
    assert.equal(await picture(), 'cover');
    await red();
    // the pictures: box art, 3D box, logo, cartridge or disc always (greyed out when the
    // game has none yet), the others when it has them
    assert.deepEqual(await Promise.all(['box3d', 'physical', 'logo', 'cover'].map(value => page.isDisabled(kind(value)))),
      [true, true, false, false]);
    assert.ok(await page.isVisible('#forwarder-media-hint'));
    assert.ok(await page.isHidden(kind('screenshot')) && await page.isHidden(kind('current')));
    // a logo fits in the square, a cover fills it
    await page.check(kind('logo'));
    assert.equal(await page.isChecked('#forwarder-fill'), false);
    await page.waitForFunction(() => {
      const context = document.querySelector('#forwarder-canvas').getContext('2d');
      const middle = context.getImageData(256, 256, 1, 1).data, above = context.getImageData(256, 40, 1, 1).data;
      return middle[1] > 150 && middle[0] < 80 && above[1] < 60; // the green logo, the ground above it
    });
    await page.check(kind('cover'));
    assert.equal(await page.isChecked('#forwarder-fill'), true);
    await red();
    // the system's icon in the bottom right corner, on a dark plate over the cover
    const plate = () => page.evaluate(() => [...document.querySelector('#forwarder-canvas').getContext('2d').getImageData(408, 335, 1, 1).data]);
    assert.ok((await plate())[0] > 200, 'no plate before the option');
    await page.check('#forwarder-badge');
    await page.waitForFunction(() => {
      const pixel = document.querySelector('#forwarder-canvas').getContext('2d').getImageData(408, 335, 1, 1).data;
      return pixel[0] > 40 && pixel[0] < 120 && pixel[1] < 40;
    });
    await page.fill('#forwarder-name', 'Browser tile');
    await page.click('#forwarder-save');
    await page.waitForFunction(() => /Tile created/.test(document.querySelector('#announcement').textContent));
    const card = page.locator('.forwarder-card', { hasText: 'Browser tile' });
    await card.waitFor();
    assert.match(await card.textContent(), /Appears on the home screen once RetroArch closes/);
    const icon = await page.evaluate(async () => {
      const { tiles } = await (await fetch('/api/forwarders')).json();
      const bytes = new Uint8Array(await (await fetch(`/api/forwarders/icon?id=${tiles[0].id}`)).arrayBuffer());
      const view = new DataView(bytes.buffer);
      return { id: tiles[0].id, png: bytes[1] === 0x50 && bytes[2] === 0x4e, width: view.getUint32(16), height: view.getUint32(20) };
    });
    assert.deepEqual([icon.png, icon.width, icon.height], [true, 512, 512]);

    // renamed, the picture kept
    await card.getByRole('button', { name: 'Edit' }).click();
    await page.waitForSelector('#forwarder-editor:not([hidden])');
    assert.equal(await picture(), 'current');
    assert.ok(await page.isDisabled('#forwarder-badge') && await page.isDisabled('#forwarder-fill'));
    assert.equal(await page.inputValue('#forwarder-name'), 'Browser tile');
    await page.fill('#forwarder-name', 'Renamed tile');
    await page.click('#forwarder-save');
    await page.waitForFunction(() => /Tile saved/.test(document.querySelector('#announcement').textContent));
    await page.locator('.forwarder-card', { hasText: 'Renamed tile' }).waitFor();

    // a phone: one column, nothing wider than the screen
    await page.setViewportSize({ width: 390, height: 844 });
    await page.click('#forwarder-new');
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    assert.ok(overflow <= 1, `the page is ${overflow}px wider than a phone`);
    await page.click('#forwarder-cancel');

    // deleted (not installed yet: at once)
    await page.locator('.forwarder-card', { hasText: 'Renamed tile' }).getByRole('button', { name: 'Delete' }).click();
    await page.waitForFunction(() => /Tile removed/.test(document.querySelector('#announcement').textContent));
    await page.waitForFunction(() => /No tiles yet/.test(document.querySelector('#forwarders-list').textContent));
    assert.deepEqual(errors, []);
    console.log(`PASS: tile ${icon.id} made from a cropped cover (512x512 PNG), renamed and deleted; fits a phone`);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
