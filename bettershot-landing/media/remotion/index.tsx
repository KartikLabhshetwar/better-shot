import React from 'react'
import { AbsoluteFill, Composition, Img, interpolate, registerRoot, staticFile, useCurrentFrame } from 'remotion'

// Only genuine captures of the production editor views. No recreated app chrome.
const scenes = [
  { image: 'video-editor.jpg', title: 'Your recording, in BetterShot.', detail: 'The video editor · Background, preview, and timeline' },
  { image: 'video-timeline.jpg', title: 'Refine the timing.', detail: 'Zoom & Clips · Clip speed and the original timeline controls' },
  { image: 'video-effects.jpg', title: 'Focus on what matters.', detail: 'Effects · Crop, blur, and pixelate' },
  { image: 'screenshot-editor.jpg', title: 'A home for your screenshots, too.', detail: 'The screenshot editor · Annotations and background controls' },
]
function Demo() {
  const frame = useCurrentFrame()
  const index = Math.floor(frame / 150)
  const scene = scenes[index]
  const fade = interpolate(frame % 150, [0, 8], [0, 1], {extrapolateRight: 'clamp'})
  return <AbsoluteFill style={{background:'#f4f2f8', color:'#27232e', fontFamily:'Arial, sans-serif'}}>
    <div style={{position:'absolute', left:34, top:26, right:34, display:'flex', alignItems:'center', justifyContent:'space-between'}}>
      <div style={{display:'flex', alignItems:'center', gap:10}}><Img src={staticFile('logo.png')} style={{width:26,height:26}} /><span style={{fontSize:18,fontWeight:600}}>Better Shot</span></div>
      <span style={{fontSize:13,color:'#6e6775'}}>THE REAL EDITORS</span>
    </div>
    <div style={{position:'absolute',top:80,left:34,right:34,opacity:fade}}>
      <h1 style={{fontSize:35,fontWeight:500,margin:0}}>{scene.title}</h1>
      <p style={{fontSize:16,color:'#6e6775',marginTop:9}}>{scene.detail}</p>
    </div>
    <Img src={staticFile(`features/${scene.image}`)} style={{position:'absolute',left:34,top:175,width:1212,height:767,objectFit:'contain',objectPosition:'top',maxHeight:660,borderRadius:12,boxShadow:'0 12px 30px #30263d20',opacity:fade}} />
    <div style={{position:'absolute',bottom:25,left:34,right:34,display:'flex',justifyContent:'space-between',fontSize:12,color:'#6e6775'}}>
      <span>Actual app screenshots · Bundled sample media · Edited with Remotion</span><span>{index+1} / 4</span>
    </div>
  </AbsoluteFill>
}
registerRoot(() => <Composition id="BetterShotDemo" component={Demo} width={1280} height={900} fps={30} durationInFrames={600} />)
