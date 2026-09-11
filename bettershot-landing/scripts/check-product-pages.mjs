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
  const sources = [...html.matchAll(/(?:src|poster)="(\/features\/[^"?]+)"/g)].map(match => match[1])
  assert.ok(sources.length > 0, `${route} needs product imagery`)
  sources.forEach(source => assets.add(source))
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
const sitemap = await (await fetch(new URL('/sitemap.xml', base))).text()
for (const route of routes.slice(1)) assert.ok(sitemap.includes(`https://bettershot.site${route}`), `${route} must be discoverable`)
console.log(`PASS: ${routes.length} pages, navigation, canonical URLs, sitemap, and ${assets.size} product media files`)
