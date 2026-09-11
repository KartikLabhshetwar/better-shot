import { bundle } from '@remotion/bundler'
import { renderMedia, renderStill, selectComposition } from '@remotion/renderer'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.dirname(fileURLToPath(import.meta.url))
const serveUrl = await bundle({entryPoint:path.join(root,'index.tsx'),publicDir:path.resolve(root,'../../public'),outDir:path.join(root,'.cache/bundle')})
const browserExecutable = process.env.REMOTION_BROWSER_EXECUTABLE
console.log('Resolving composition')
const composition = await selectComposition({serveUrl,id:'BetterShotDemo',browserExecutable})
console.log('Rendering poster')
await renderStill({serveUrl,composition,browserExecutable,frame:90,imageFormat:'jpeg',jpegQuality:85,output:path.resolve(root,'../../public/features/recording-demo-poster.jpg')})
console.log('Rendering 600 frames')
await renderMedia({serveUrl,composition,browserExecutable,codec:'h264',crf:23,concurrency:2,outputLocation:path.resolve(root,'../../public/features/recording-demo.mp4'),onProgress:({renderedFrames})=>{if(renderedFrames%150===0)console.log(`Rendered ${renderedFrames}/600 frames`)}})
