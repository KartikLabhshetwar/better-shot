import { bundle } from '@remotion/bundler'
import { renderMedia, renderStill, selectComposition } from '@remotion/renderer'
import { mkdir, access } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

// node render-features.mjs [Background|Timeline|Screenshot] [video path relative to public/]
// No footage produces explicitly labelled motion previews, never website deliverables.
const root = path.dirname(fileURLToPath(import.meta.url))
const publicDir = path.resolve(root, '../../public')
const features = ['Background', 'Timeline', 'Screenshot']
const selected = process.argv[2] ? [process.argv[2]] : features
if (selected.some(id => !features.includes(id))) throw new Error(`Choose ${features.join(', ')}`)
const footage = process.argv[3]
if (footage) await access(path.join(publicDir, footage))
const outputDir = path.resolve(process.env.REMOTION_OUTPUT_DIR || path.join(root, '.cache/feature-previews'))
await mkdir(outputDir, {recursive:true})
const serveUrl = await bundle({entryPoint:path.join(root, 'index.tsx'), publicDir, outDir:path.join(root, '.cache/feature-bundle')})
const browserExecutable = process.env.REMOTION_BROWSER_EXECUTABLE
for (const id of selected) {
  const inputProps = {feature:id, ...(footage ? {footage} : {})}
  const composition = await selectComposition({serveUrl, id, browserExecutable, inputProps})
  const stem = `${id.toLowerCase()}${footage ? '' : '-motion-preview'}`
  const shared = {serveUrl, composition, browserExecutable, inputProps}
  await renderStill({...shared, frame:30, imageFormat:'jpeg', jpegQuality:90, output:path.join(outputDir, `${stem}.jpg`)})
  console.log(`Rendering ${id}`)
  await renderMedia({...shared, codec:'h264', crf:20, concurrency:2, outputLocation:path.join(outputDir, `${stem}.mp4`)})
  console.log(`Created ${path.join(outputDir, `${stem}.mp4`)}`)
}
