import React from 'react'
import { AbsoluteFill, Easing, Img, interpolate, OffthreadVideo, staticFile, useCurrentFrame } from 'remotion'

// The interface is always a production capture. Motion frames it; it never redraws controls.
export const featureDemos = {
  Background: { image: 'video-editor.jpg', label: 'MAKE IT YOURS', title: 'A little room. A better frame.', focus: [0.12, 0.43], zoom: 1.8, background: 'radial-gradient(ellipse at 0% 10%, #fac9b8, transparent 70%), radial-gradient(ellipse at 100% 100%, #b8abd9, transparent 70%), #e7d0df' },
  Timeline: { image: 'video-timeline.jpg', label: 'VIDEO RECORDING', title: 'Keep the good parts.', focus: [0.5, 0.82], zoom: 1.65, background: 'radial-gradient(ellipse at 0% 0%, #e1d9ff, transparent 70%), radial-gradient(ellipse at 100% 100%, #8e89d0, transparent 70%), #c5bbe5' },
  Screenshot: { image: 'screenshot-editor.jpg', label: 'SCREENSHOTS', title: 'Make your point.', focus: [0.63, 0.42], zoom: 1.45, background: 'radial-gradient(ellipse at 0% 100%, #baded5, transparent 70%), radial-gradient(ellipse at 100% 0%, #d8bce7, transparent 70%), #d6dfdf' },
} as const

export type FeatureDemoProps = { feature: keyof typeof featureDemos; footage?: string }
export const featureFrames = 360

export function FeatureDemo({ feature, footage }: FeatureDemoProps) {
  const frame = useCurrentFrame()
  const shot = featureDemos[feature]
  // Hold the full editor, move toward the feature, hold, then return for a clean loop.
  const progress = interpolate(frame, [0, 45, 100, 245, 310, 359], [0, 0, 1, 1, 0, 0], {
    extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.inOut(Easing.cubic),
  })
  const scale = 1 + (shot.zoom - 1) * progress
  const width = 1080
  const height = width * 768 / 1214
  const x = (0.5 - shot.focus[0]) * width * (scale - 1)
  const y = (0.5 - shot.focus[1]) * height * (scale - 1)
  const mediaStyle: React.CSSProperties = { display: 'block', width: '100%', height: '100%', objectFit: 'contain' }
  return <AbsoluteFill style={{ background: shot.background, color: '#292331', fontFamily: '-apple-system, BlinkMacSystemFont, Arial, sans-serif' }}>
    <div style={{ position: 'absolute', top: 42, left: 72, right: 72, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
      <div><div style={{ fontSize: 11, fontWeight: 600, marginBottom: 10, color: '#65566e' }}>{shot.label}</div><div style={{ fontSize: 30, fontWeight: 600 }}>{shot.title}</div></div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, fontSize: 17, fontWeight: 600 }}><Img src={staticFile('logo.png')} style={{ width: 26, height: 26, borderRadius: 7 }} />Better Shot</div>
    </div>
    <div style={{ position: 'absolute', top: 146, left: 36, right: 36, bottom: 50, overflow: 'hidden', borderRadius: 20 }}>
      <div style={{ position: 'absolute', width, height, left: '50%', top: '50%', marginLeft: -width / 2, marginTop: -height / 2, transform: `translate(${x}px, ${y}px) scale(${scale})`, borderRadius: 12, overflow: 'hidden', boxShadow: '0 18px 45px #39294b25, 0 1px 4px #39294b18' }}>
        {footage ? <OffthreadVideo src={staticFile(footage)} muted style={mediaStyle} /> : <Img src={staticFile(`features/${shot.image}`)} style={mediaStyle} />}
      </div>
    </div>
    <div style={{ position: 'absolute', bottom: 20, left: 72, fontSize: 12, color: '#65566e' }}>{footage ? 'BetterShot · Native on Mac' : 'Motion preview · Actual editor capture · Interactions awaiting recording'}</div>
  </AbsoluteFill>
}
