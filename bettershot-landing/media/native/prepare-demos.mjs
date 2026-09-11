import {execFileSync} from 'node:child_process'
import {mkdir, readdir, writeFile} from 'node:fs/promises'
import {createRequire} from 'node:module'
import {fileURLToPath} from 'node:url'
import path from 'node:path'

// Usage: node media/native/prepare-demos.mjs /path/to/recordings
// Originals stay untouched. All stills are real dark-mode frames, never recolored UI.
const require = createRequire(import.meta.url)
const sharp = require(require.resolve('sharp', {paths:[path.dirname(require.resolve('next/package.json'))]}))
const sourceDir = process.argv[2]
if (!sourceDir) throw new Error('Pass the directory containing the five numbered demo recordings.')
const files = await readdir(sourceDir)
const output = fileURLToPath(new URL('../../public/features/', import.meta.url))
await mkdir(output, {recursive:true})
const clips = [
  ['01-screenshot-background.mp4', 'screenshot-background', 2],
  ['02-screenshot-annotation.mp4', 'screenshot-annotation', 22.9],
  ['03-video-trimming.mp4', 'video-trimming', 3.5],
  ['04-video-zoom.mp4', 'video-zoom', 1],
  ['05-video-export.mp4', 'video-export', 1.1],
]
const sources = {}
let originalBytes = 0
let optimizedBytes = 0
for (const [name, stem, posterTime] of clips) {
  const actual = files.find(file => file.trim() === name)
  if (!actual) throw new Error(`Missing ${name}`)
  const source = path.join(sourceDir, actual)
  sources[stem] = source
  const probe = JSON.parse(execFileSync('ffprobe', ['-v','error','-show_format','-show_streams','-of','json',source]))
  // These supplied demos have silent audio; -an prevents shipping an empty audio track.
  execFileSync('ffmpeg', ['-v','error','-y','-i',source,'-map','0:v:0','-an','-vf','scale=1280:800:force_original_aspect_ratio=decrease:force_divisible_by=2,pad=1280:800:(ow-iw)/2:(oh-ih)/2:color=0x1c1c1e,setsar=1','-r','30','-c:v','libx264','-preset','slow','-crf','23','-pix_fmt','yuv420p','-movflags','+faststart',path.join(output,`${stem}-demo.mp4`)],{stdio:'inherit'})
  const frame = execFileSync('ffmpeg',['-v','error','-ss',String(posterTime),'-i',source,'-frames:v','1','-f','image2pipe','-vcodec','png','-'],{maxBuffer:20*1024*1024})
  await sharp(frame).resize(1280,800,{fit:'contain',background:'#1c1c1e'}).webp({quality:85}).toFile(path.join(output,`${stem}-poster.webp`))
  const optimized = JSON.parse(execFileSync('ffprobe',['-v','error','-show_format','-of','json',path.join(output,`${stem}-demo.mp4`)]))
  originalBytes += Number(probe.format.size)
  optimizedBytes += Number(optimized.format.size)
  console.log(`${stem}: ${(Number(probe.format.size)/1e6).toFixed(2)} → ${(Number(optimized.format.size)/1e6).toFixed(2)} MB`)
}
const stills = [
  ['screenshot-editor-dark','screenshot-annotation',22.9],
  ['screenshot-tools-dark','screenshot-annotation',22.9,[155,48,665,53]],
  ['screenshot-tools-detail-dark','screenshot-annotation',22.9,[382,48,135,53]],
  ['screenshot-background-dark','screenshot-background',2,[8,110,330,655]],
  ['screenshot-canvas-dark','screenshot-annotation',22.9,[530,270,1030,583]],
  ['screenshot-copy-dark','screenshot-annotation',22.9,[1638,1025,98,48]],
  ['video-editor-dark','video-zoom',1],
  ['video-background-dark','video-trimming',2.5,[68,55,325,665]],
  ['video-timeline-dark','video-zoom',4.4,[975,842,620,195]],
  ['video-zoom-dark','video-zoom',4.4,[70,64,332,650]],
  ['video-export-dark','video-export',1.1,[1390,58,322,660]],
  ['video-timeline-wide-dark','video-zoom',4.4,[8,750,1710,290]],
]
for (const [name,stem,time,crop] of stills) {
  const frame = execFileSync('ffmpeg',['-v','error','-ss',String(time),'-i',sources[stem],'-frames:v','1','-f','image2pipe','-vcodec','png','-'],{maxBuffer:20*1024*1024})
  let image = sharp(frame)
  if (crop) {const [left,top,width,height] = crop; image = image.extract({left,top,width,height})}
  await image.resize({width:1600,withoutEnlargement:true}).webp({quality:90}).toFile(path.join(output,`${name}.webp`))
}
await writeFile(new URL('./sources.json',import.meta.url),JSON.stringify({
  description:'Real BetterShot dark-mode recordings supplied by the maintainer. No fabricated controls or recolored interface.',
  videos:clips.map(([source,stem,time])=>({source,output:`${stem}-demo.mp4`,poster:`${stem}-poster.webp`,posterTime:time})),
  images:stills.map(([name,stem,time,crop])=>({output:`${name}.webp`,source:clips.find(clip=>clip[1]===stem)[0],time,...(crop?{crop}: {})})),
  encoding:'H.264, 1280×800, 30 fps, CRF 23, yuv420p, faststart, silent audio removed; original files untouched.',
  originalBytes,optimizedBytes,
},null,2)+'\n')
console.log(`Total ${(originalBytes/1e6).toFixed(2)} → ${(optimizedBytes/1e6).toFixed(2)} MB`)
