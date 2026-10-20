/* Run against an isolated native WebUI fixture, as tests/webui_browser.cjs does.
 * Release and installer transport are mocked; alerts use real native handlers. */
const {chromium}=require(process.env.PLAYWRIGHT_PATH || 'playwright');
const assert=require('node:assert/strict');const fs=require('node:fs');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH || '/usr/bin/chromium'});
 const page=await browser.newPage({viewport:{width:1504,height:1046},reducedMotion:'reduce'});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const tag='v0.6.0-alpha.6',name='PS5_RetroArch-'+tag+'.zip';
 await page.route('https://api.github.com/**',r=>r.fulfill({json:[{tag_name:tag,published_at:'2026-10-02T10:00:00Z',body:'Fixture release notes',assets:[{name},{name:name+'.sha256'}]}]}));
 await page.goto(process.env.WEBUI_TEST_URL || 'http://127.0.0.1:6770');await page.locator('#download-update:not([disabled])').waitFor();
 await page.waitForFunction(()=>document.querySelector('#alerts-count').textContent>0);await page.locator('#alerts-details summary').click();
 await page.evaluate(()=>document.fonts.ready);fs.mkdirSync('build/verification/webui-update',{recursive:true});
 for(const [name,width,height] of [['desktop',1504,1046],['mobile',390,844]]) {
  await page.setViewportSize({width,height});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,name+' overflow');
  await page.screenshot({path:'build/verification/webui-update/'+name+'.png',fullPage:true});
 }
 // A failed initiation must survive successful idle-status polling.
 await page.route('**/api/update',r=>r.fulfill({json:{state:'idle',message:'',tag:''}}));
 await page.route('**/api/update/download?*',r=>r.fulfill({status:409,json:{error:'Could not start the update. Please retry.'}}));
 await page.locator('#download-update').click();await page.locator('#update-error').waitFor();
 await page.waitForTimeout(2300);
 assert.equal(await page.locator('#update-error').isVisible(),true,'request error remains visible after idle poll');
 await page.unroute('**/api/update/download?*');await page.unroute('**/api/update');
 await page.route('**/api/update/download?*',r=>r.fulfill({status:202,json:{state:'downloading',message:'Downloading the release to your console…',tag,received:12345678}}));
 await page.route('**/api/update',r=>r.fulfill({json:{state:'ready',message:'Download verified. Installing will close RetroArch. Save your game first.',tag,received:12345678}}));
 await page.locator('#download-update').click();await page.locator('#install-update').waitFor();
 assert.equal(await page.locator('#download-update').isDisabled(),true);
 await page.route('**/api/update/install',r=>r.fulfill({status:202,json:{state:'installing',message:'Closing RetroArch to install the update…',tag}}));
 await page.locator('#install-update').click();await page.waitForFunction(()=>document.querySelector('#update-message').textContent.includes('Closing'));
 await page.unroute('**/api/update');await page.route('**/api/update',r=>r.fulfill({json:{state:'error',message:'Download failed. Check your connection and retry.',tag}}));
 await page.waitForFunction(()=>document.querySelector('#update-message').textContent.includes('Download failed'));
 await page.route('**/api/alerts',r=>r.fulfill({json:{alerts:[]}}));await page.locator('#refresh-alerts').click();await page.waitForFunction(()=>document.querySelector('#alerts-summary').textContent.startsWith('No missing'));
 await page.unroute('**/api/alerts');await page.route('**/api/alerts',r=>r.abort());await page.locator('#refresh-alerts').click();await page.waitForFunction(()=>document.querySelector('#alerts-summary').textContent.startsWith('Couldn’t'));
 await page.route('**/version.json',r=>r.fulfill({json:{release:tag,build:'updated-fixture'}}));
 await page.locator('#check-release').click();await page.waitForFunction(expected=>document.querySelector('#release-title').textContent===expected,tag);
 assert.deepEqual(errors,[]);console.log('PASS desktop/mobile layout, alerts/empty/error, download/ready/install/error UI states (mocked update transport).');
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
