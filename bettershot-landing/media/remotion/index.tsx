import React from 'react'
import { FeatureDemo, featureDemos, featureFrames } from './feature-demos'
import { AbsoluteFill, Composition, Easing, Img, interpolate, registerRoot, Sequence, staticFile, useCurrentFrame } from 'remotion'

// Editorial motion around genuine app captures; never simulate clicks or redraw controls.
const ease = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.inOut(Easing.cubic)} as const
const shots = [
  {from: 0, frames: 150, image: 'video-editor.jpg', label: 'VIDEO RECORDING', title: ['A better', 'way to show.'], detail: 'Your screen. Your story. One native Mac app.', full: true, background: 'radial-gradient(ellipse at 10% 15%, #ead4ee, transparent 65%), radial-gradient(ellipse at 95% 95%, #a49cdb, transparent 70%), #d6c3e4'},
  {from: 135, frames: 150, image: 'video-background-detail.webp', label: 'MAKE IT YOURS', title: ['A little room.', 'A lot of polish.'], detail: 'Soft gradients. Rounded corners. Just the right shadow.', full: false, background: 'radial-gradient(ellipse at 0% 0%, #ffc1a7, transparent 65%), radial-gradient(ellipse at 100% 100%, #c5b2e2, transparent 70%), #efcdd0'},
  {from: 270, frames: 150, image: 'video-timeline-detail.webp', label: 'ZOOM & CLIPS', title: ['Find your', 'rhythm.'], detail: 'Refine your clips, speed, and zooms in the video editor.', full: false, background: 'radial-gradient(ellipse at 0% 0%, #ddd4ff, transparent 65%), radial-gradient(ellipse at 100% 100%, #8f89cd, transparent 70%), #b9b1e6'},
  {from: 405, frames: 150, image: 'video-effects-detail.webp', label: 'FINISH THE FRAME', title: ['Keep the focus', 'where it belongs.'], detail: 'Crop, blur, and pixelate with the built-in effects tools.', full: false, background: 'radial-gradient(ellipse at 0% 100%, #a9d5d1, transparent 65%), radial-gradient(ellipse at 100% 0%, #d6c2e9, transparent 70%), #d2e0e3'},
  {from: 540, frames: 180, image: 'screenshot-editor.jpg', label: 'SCREENSHOTS, TOO', title: ['Make your', 'point.'], detail: 'Capture. Annotate. Share a clearer picture.', full: true, background: 'radial-gradient(ellipse at 5% 15%, #ecc1d6, transparent 65%), radial-gradient(ellipse at 100% 100%, #b2a6dc, transparent 70%), #dfc8e3'},
]

function Shot({shot}: {shot: typeof shots[number]}) {
  const f = useCurrentFrame()
  const enter = interpolate(f, [0, 18], [0, 1], ease)
  const drift = interpolate(f, [0, shot.frames], [0, 1], ease)
  const textOpacity = interpolate(f, [8, 22], [0, 1], ease)
  return <AbsoluteFill style={{background:shot.background, opacity:enter}}>
    <div style={{position:'absolute', left:56, top:shot.full?220:235, width:shot.full?295:560, opacity:textOpacity, transform:`translateY(${(1-enter)*18}px)`}}>
      <div style={{fontSize:13,fontWeight:600,marginBottom:22,color:'#5f506c'}}>{shot.label}</div>
      <h1 style={{fontSize:shot.full?55:64,fontWeight:600,lineHeight:1.04,letterSpacing:-2,margin:0}}>{shot.title.map(line=><React.Fragment key={line}>{line}<br/></React.Fragment>)}</h1>
      <p style={{fontSize:18,lineHeight:1.55,marginTop:24,maxWidth:shot.full?245:390,color:'#64556e'}}>{shot.detail}</p>
    </div>
    <div style={{position:'absolute', left:shot.full?370:700, top:shot.full?140:145, width:shot.full?865:475, height:shot.full?548:510, display:'flex',alignItems:'center',justifyContent:'center', transform:`translateX(${(1-enter)*42-drift*10}px) translateY(${-drift*6}px) scale(${0.97+enter*0.03+drift*0.025})`, transformOrigin:'center'}}>
      <Img src={staticFile(`features/${shot.image}`)} style={{maxWidth:'100%',maxHeight:'100%',width:shot.full?'100%':'auto',height:shot.full?'auto':'100%',objectFit:'contain',borderRadius:shot.full?12:18,boxShadow:'0 24px 65px #43305b28, 0 3px 8px #43305b10'}} />
    </div>
  </AbsoluteFill>
}

function Demo() {
  const frame = useCurrentFrame()
  const active = Math.min(4, Math.floor(frame/135))
  return <AbsoluteFill style={{background:'#d6c3e4',color:'#30233c',fontFamily:'-apple-system, BlinkMacSystemFont, Arial, sans-serif'}}>
    {shots.map(shot=><Sequence key={shot.from} from={shot.from} durationInFrames={shot.frames}><Shot shot={shot}/></Sequence>)}
    <div style={{position:'absolute',left:56,top:44,display:'flex',alignItems:'center',gap:11}}>
      <Img src={staticFile('logo.png')} style={{width:30,height:30,borderRadius:8}}/><span style={{fontSize:21,fontWeight:600}}>Better Shot</span>
    </div>
    <div style={{position:'absolute',bottom:42,left:56,right:56,display:'flex',alignItems:'center',justifyContent:'space-between'}}>
      <span style={{fontSize:14,color:'#64556e'}}>Free. Open source. Made for Mac.</span>
      <div style={{display:'flex',gap:8}}>{shots.map((_,i)=><div key={i} style={{width:i===active?30:7,height:7,borderRadius:7,background:i===active?'#6d4595':'#ffffff80'}}/>)}</div>
    </div>
  </AbsoluteFill>
}
registerRoot(() => <>
  <Composition id="BetterShotDemo" component={Demo} width={1280} height={800} fps={30} durationInFrames={720} />
  {(Object.keys(featureDemos) as Array<keyof typeof featureDemos>).map(feature => <Composition key={feature} id={feature} component={FeatureDemo} defaultProps={{feature}} width={1280} height={900} fps={30} durationInFrames={featureFrames} />)}
</>)
