import assert from 'node:assert/strict'

const base = process.env.BETTERSHOT_SITE_URL || 'http://localhost:3010'
const routes = ['/', '/video-recording', '/screenshots']
const assets = new Set()

for (const route of routes) {
  const response = await fetch(new URL(route, base))
  assert.equal(response.status, 200, `${route} must load`)
  const html = await response.text()
  assert.equal((html.match(/<h1\b/g) || []).length, 1, `${route} needs one main heading`)
  for (const destination of routes.slice(1)) {
    assert.ok(html.includes(`href="${destination}"`), `${route} must link to ${destination}`)
  }
  assert.ok(html.includes(`href="https://bettershot.site${route === '/' ? '' : route}"`), `${route} needs its own canonical URL`)
  const navigation = html.match(/<nav\b[^>]*aria-label="Main"[\s\S]*?<\/nav>/)?.[0] || ''
  assert.ok(navigation.includes('Product'), 'Navigation needs a Product dropdown')
  assert.ok(!navigation.includes('href="/download"'), 'Use the download button, not a separate navigation link')
  assert.ok(navigation.includes('Download'), 'Keep the download button in navigation')
  const sources = [...html.matchAll(/(?:src|poster)="(\/features\/[^"?]+)"/g)].map(match => match[1])
  assert.ok(sources.length > 0, `${route} needs product imagery`)
  sources.forEach(source => assets.add(source))
  const demos = [...html.matchAll(/data-demo="([^"]+)"/g)].map(match => match[1])
  assert.equal(demos.length, route === '/' ? 4 : route === '/screenshots' ? 2 : 3, `${route} must show its relevant demos`)
  assert.ok(html.includes('preload="none"'), `${route} must defer video downloads`)
  assert.ok(!html.includes('/features/recording-demo'), `${route} must not use the retired slideshow`)
  for (const demo of demos) {
    assets.add(`/features/${demo}-demo.mp4`)
    assets.add(`/features/${demo}-poster.webp`)
  }
  const videos = [...html.matchAll(/<video\b[^>]*>/g)].map(match => match[0])
  const launchVideos = videos.filter(video => video.includes('aria-label="BetterShot launch video"'))
  assert.equal(launchVideos.length, route === '/' ? 1 : 0, 'Only the homepage features the launch film')
  assert.equal(videos.length, demos.length + launchVideos.length, `${route} needs an individual video for each demo`)
  for (const video of videos.filter(video => !launchVideos.includes(video))) {
    assert.ok(!/\bcontrols(?:=|\s|>)/.test(video), 'Demos must not display player controls')
    assert.ok(video.includes('loop=""') && video.includes('muted=""') && video.includes('playsInline=""'), 'Demos must loop silently inline')
    assert.ok(video.includes('data-autoplay="visible"'), 'Demos autoplay only while visible')
  }
  assert.equal((html.match(/data-demo-row="true"/g) || []).length, demos.length - (route === '/' ? 0 : 1), 'Use alternating feature rows below the main demo')
  if (route === '/') {
    const launch = launchVideos[0]
    assert.ok(launch.includes('controls=""') && launch.includes('playsInline=""'), 'Launch video needs native inline playback controls')
    assert.ok(launch.includes('preload="none"'), 'Defer downloading the launch video until playback')
    assert.ok(!/\b(?:autoPlay|loop|muted)(?:=|\s|>)/.test(launch), 'Play the launch soundtrack only after a user starts it')
    assert.ok(html.includes('src="/videos/bettershot-launch.mp4"'), 'Use the approved launch film')
    assert.ok(html.includes('href="#demo"') && html.includes('Watch the launch video'), 'Hero CTA leads to the launch video')
    assets.add('/videos/bettershot-launch.mp4')
    assets.add('/videos/bettershot-launch-poster.webp')
    assert.ok(html.includes('Capture clearly.'), 'Home needs the revised hero')
    assert.ok(html.includes('BetterShot contributor'), 'Home restores contributor avatars')
  }
  else assert.ok(html.includes('editor-tools-backdrop'), `${route} needs its dark editor detail banner`)
}
for (const asset of assets) {
  const response = await fetch(new URL(asset, base))
  assert.equal(response.status, 200, `${asset} must load`)
  assert.ok(/^(image|video)\//.test(response.headers.get('content-type') || ''), `${asset} must be media`)
  assert.ok((await response.arrayBuffer()).byteLength > 0, `${asset} must not be empty`)
}
const legacy = await fetch(new URL('/image-processing', base), {redirect:'manual'})
assert.equal(legacy.status, 308)
assert.equal(legacy.headers.get('location'), '/screenshots')
const download = await fetch(new URL('/download', base), {redirect:'manual'})
assert.equal(download.status, 308)
assert.equal(download.headers.get('location'), '/#download')
const homepage = await (await fetch(base)).text()
assert.ok(homepage.includes('id="download"'), 'The old download URL must lead to download options')
const sitemap = await (await fetch(new URL('/sitemap.xml', base))).text()
assert.ok(!sitemap.includes('https://bettershot.site/download'), 'Do not index the retired download page')
for (const route of routes.slice(1)) assert.ok(sitemap.includes(`https://bettershot.site${route}`), `${route} must be discoverable`)
console.log(`PASS: ${routes.length} pages, navigation, canonical URLs, sitemap, and ${assets.size} product media files`)
