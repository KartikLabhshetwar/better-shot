import React from 'react'
import { Composition, registerRoot } from 'remotion'
import { FeatureDemo, featureDemos, featureFrames } from './feature-demos'

registerRoot(() => <>
  {(Object.keys(featureDemos) as Array<keyof typeof featureDemos>).map(feature => <Composition key={feature} id={feature} component={FeatureDemo} defaultProps={{feature}} width={1280} height={900} fps={30} durationInFrames={featureFrames} />)}
</>)
