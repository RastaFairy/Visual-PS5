/* The SMB page in Chromium against the native WebUI and a Samba server of the test's own
 * (tests/test_webui_smb.py): Test connection lists the shares, a wrong password is refused
 * in words, a share and folder are saved, the page shows them again without the password,
 * the page fits a phone, and the server is forgotten. */
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
    await page.goto(base + '/#smb');
    assert.equal(await page.textContent('#page-title'), 'SMB');
    assert.equal(await page.getAttribute('[data-page="smb"]', 'aria-current'), 'page');
    assert.ok(await page.isDisabled('#smb-save') && await page.isHidden('#smb-forget'));

    // a wrong password is refused in words
    await page.fill('#smb-server', process.env.SMB_SERVER);
    await page.fill('#smb-user', process.env.SMB_USER);
    await page.fill('#smb-password', 'wrong');
    await page.click('#smb-test');
    await page.waitForSelector('#smb-error:not([hidden])');
    assert.match(await page.textContent('#smb-error'), /refused this user name and password/);
    assert.ok(await page.isDisabled('#smb-save'));

    // Test connection lists the shares
    await page.fill('#smb-password', process.env.SMB_PASSWORD);
    await page.click('#smb-test');
    await page.waitForFunction(() => /Connected\. Choose the share/.test(document.querySelector('#smb-status').textContent));
    assert.ok(await page.isHidden('#smb-error'));
    assert.deepEqual(await page.$$eval('#smb-share option', options => options.map(o => o.value)), ['games', 'locked']);
    await page.selectOption('#smb-share', 'locked');
    await page.fill('#smb-folder', 'Games/Homebrew');
    await page.click('#smb-save');
    await page.waitForFunction(() => /^Saved\./.test(document.querySelector('#smb-status').textContent));
    assert.equal(await page.inputValue('#smb-password'), '');
    assert.equal(await page.getAttribute('#smb-password', 'placeholder'), 'Saved on your PS5');

    // shown again, without the password
    await page.reload();
    await page.waitForFunction(() => document.querySelector('#smb-server').value !== '');
    assert.equal(await page.inputValue('#smb-user'), process.env.SMB_USER);
    assert.equal(await page.inputValue('#smb-share'), 'locked');
    assert.equal(await page.inputValue('#smb-folder'), 'Games/Homebrew');
    assert.equal(await page.inputValue('#smb-password'), '');
    assert.ok(await page.isEnabled('#smb-save') && await page.isVisible('#smb-forget'));
    assert.ok(!(await page.content()).includes(process.env.SMB_PASSWORD));
    // another server is another list of shares
    await page.fill('#smb-server', process.env.SMB_SERVER + ' ');
    assert.ok(await page.isDisabled('#smb-save'));
    await page.reload();
    await page.waitForFunction(() => document.querySelector('#smb-server').value !== '');

    // a phone: nothing wider than the screen
    await page.setViewportSize({ width: 390, height: 844 });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    assert.ok(overflow <= 1, `the page is ${overflow}px wider than a phone`);

    // forgotten
    await page.click('#smb-forget');
    await page.waitForFunction(() => /forgotten/.test(document.querySelector('#smb-status').textContent));
    assert.equal(await page.inputValue('#smb-server'), '');
    assert.ok(await page.isHidden('#smb-forget') && await page.isDisabled('#smb-save'));
    assert.deepEqual(errors, []);
    console.log('PASS: shares listed, a wrong password refused, a share and folder saved and shown again ' +
      'without the password, fits a phone, forgotten');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
