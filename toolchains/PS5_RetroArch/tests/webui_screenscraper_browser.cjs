/* ScreenScraper's sign-in on the Download Media tab in Chromium (tests/
 * test_scraper_screenscraper.py starts the server and a fake ScreenScraper): clicking the
 * source opens the form, a wrong password is refused in it, the right one shows a green
 * check on the chip, the account panel shows the quota, and signing out removes the check.
 * The password never reaches an answer of the console. */
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_PATH || 'playwright');
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium' });
  try {
    const page = await browser.newPage();
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    const answers = [];
    page.on('response', async r => { if (r.url().includes('/api/')) answers.push(await r.text().catch(() => '')); });
    await page.route('https://api.github.com/**', route => route.fulfill({ json: [] }));
    await page.goto(process.env.WEBUI_TEST_URL + '/#media');
    await page.waitForFunction(() => document.querySelectorAll('.kind-tile').length === 10);
    const item = page.locator('.source-item[data-source="screenscraper"]'), libretro = page.locator('.source-item[data-source="libretro"]');
    const toggle = item.locator('.source-toggle'), order = item.locator('.source-order');
    // Not signed in: a Sign in button instead of its switch; libretro alone is on.
    assert.equal(await item.getByRole('button', { name: 'Sign in' }).count(), 1);
    assert.equal(await toggle.count(), 0);
    assert.equal(await libretro.locator('.source-order').innerText(), '1');
    await item.getByRole('button', { name: 'Sign in' }).click();
    const dialog = page.locator('#sign-in');
    await dialog.waitFor({ state: 'visible' });
    assert.equal(await page.locator('#sign-in-user').evaluate(n => n === document.activeElement), true);
    assert.equal(await page.locator('#sign-in-password').getAttribute('type'), 'password');
    await page.locator('#sign-in-user').fill(process.env.SS_USER);
    await page.locator('#sign-in-password').fill('wrong-password');
    await page.locator('#sign-in-submit').click();
    await page.waitForFunction(() => /did not accept/.test(document.querySelector('#sign-in-error').textContent));
    assert.equal(await item.locator('.signed-check').count(), 0);
    await page.locator('#sign-in-password').fill(process.env.SS_PASSWORD);
    await page.locator('#sign-in-submit').click();
    await page.waitForFunction(() => !document.querySelector('#sign-in-account').hidden);
    assert.match(await page.locator('#sign-in-who').innerText(), new RegExp(`Signed in as ${process.env.SS_USER}`));
    assert.match(await page.locator('#sign-in-quota').innerText(), /12 of 20,000/);
    assert.equal(await page.locator('#sign-in-password').inputValue(), '', 'the password is cleared from the page');
    await page.locator('#sign-in-submit').click(); // Done
    await dialog.waitFor({ state: 'hidden' });
    // Signed in: the green check, and it joins the chain after libretro.
    assert.equal(await item.locator('.signed-check').count(), 1);
    assert.equal(await toggle.getAttribute('aria-checked'), 'true');
    assert.equal(await order.innerText(), '2');
    assert.match(await page.locator('#scrape-source-hint').innerText(), /libretro thumbnails goes through every game first, at full speed; then ScreenScraper only for what is still missing/);
    assert.equal(await page.locator('.kind-tile:disabled').count(), 0);
    assert.match(await page.locator('.kind-tile', { hasText: 'Box art (front)' }).getAttribute('title'), /Asked of libretro thumbnails, then ScreenScraper/);
    assert.equal(await page.locator('#scrape-language-pick').isVisible(), true);
    assert.equal(await page.locator('input[name="scrape-method"][value="pc"]').isDisabled(), true);
    assert.match(await page.locator('#scrape-account-text').innerText(), /Signed in to ScreenScraper/);
    // The order changes with the arrows; a source can be turned off.
    await item.getByRole('button', { name: 'Ask ScreenScraper earlier' }).click();
    assert.equal(await order.innerText(), '1');
    assert.equal(await libretro.locator('.source-order').innerText(), '2');
    await libretro.locator('.source-toggle').click();
    assert.equal(await libretro.locator('.source-toggle').getAttribute('aria-checked'), 'false');
    assert.equal(await page.locator('.source-item.on').count(), 1);
    await libretro.locator('.source-toggle').click();
    // Still signed in after a reload (kept on the console, not in the page).
    await page.reload();
    await page.waitForFunction(() => document.querySelectorAll('.kind-tile').length === 10);
    assert.equal(await item.locator('.signed-check').count(), 1);
    // Manage, then sign out: the check and the switch go, libretro alone again.
    await page.locator('.source-item[data-source="screenscraper"] .source-toggle').click();
    await page.locator('#scrape-account-manage').click();
    await dialog.waitFor({ state: 'visible' });
    await page.locator('#sign-in-forget').click();
    await dialog.waitFor({ state: 'hidden' });
    assert.equal(await item.locator('.signed-check').count(), 0);
    assert.equal(await item.getByRole('button', { name: 'Sign in' }).count(), 1);
    assert.equal(await page.locator('.source-item.on').count(), 1);
    assert.equal(await page.locator('input[name="scrape-method"][value="pc"]').isDisabled(), false);
    for (const text of answers) assert.ok(!text.includes(process.env.SS_PASSWORD), 'an answer held the password');
    assert.deepEqual(errors, []);
    console.log('screenscraper sign-in browser test: ok');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
