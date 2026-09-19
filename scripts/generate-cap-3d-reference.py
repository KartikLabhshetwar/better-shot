#!/usr/bin/env python3
"""Regenerate numeric 3D fixtures from an existing Cap checkout, not a copied renderer.
Usage: python3 scripts/generate-cap-3d-reference.py /path/to/Cap
Requires bun and rustc; the normal test runner only reads the checked-in JSON.
"""
import json, pathlib, subprocess, sys, tempfile
RUST = r'''
extern crate self as cap_project;
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Camera3DProperties { pub tilt_x:f64,pub tilt_y:f64,pub roll:f64,pub rotate_x:f64,pub rotate_y:f64,pub zoom:f64,pub fov:f64,pub pan_x:f64,pub pan_y:f64 }
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub enum Camera3DBlurMode { #[default] None, Radial, Directional, TiltShift }
#[derive(Clone, Copy, Debug, Default)]
pub struct Camera3DBlur { pub mode:Camera3DBlurMode,pub strength:f64,pub falloff:f64,pub focus_x:f64,pub focus_y:f64,pub focus_size:f64,pub angle:f64,pub dir_position:f64,pub bokeh:bool }
#[derive(Clone, Debug, Default)]
pub struct Camera3DKeyframe { pub time:f64,pub value:f64,pub in_easing:Option<[f64;2]>,pub out_easing:Option<[f64;2]> }
#[derive(Clone, Debug, Default)]
pub struct Camera3DTracks { pub tilt_x:Vec<Camera3DKeyframe>,pub tilt_y:Vec<Camera3DKeyframe>,pub roll:Vec<Camera3DKeyframe>,pub rotate_x:Vec<Camera3DKeyframe>,pub rotate_y:Vec<Camera3DKeyframe>,pub zoom:Vec<Camera3DKeyframe>,pub fov:Vec<Camera3DKeyframe>,pub pan_x:Vec<Camera3DKeyframe>,pub pan_y:Vec<Camera3DKeyframe>,pub blur_strength:Vec<Camera3DKeyframe>,pub blur_falloff:Vec<Camera3DKeyframe>,pub blur_focus_x:Vec<Camera3DKeyframe>,pub blur_focus_y:Vec<Camera3DKeyframe>,pub blur_focus_size:Vec<Camera3DKeyframe>,pub blur_angle:Vec<Camera3DKeyframe>,pub blur_dir_position:Vec<Camera3DKeyframe> }
#[derive(Clone, Debug, Default)]
pub struct Camera3DSegment { pub start:f64,pub end:f64,pub enabled:bool,pub properties:Camera3DProperties,pub blur:Camera3DBlur,pub tracks:Camera3DTracks,pub transition_in:f64,pub transition_out:f64 }
#[derive(Clone, Copy, Debug, PartialEq)] pub struct XY<T> { pub x:T,pub y:T }
#[path="UPSTREAM_SOURCE"] mod camera3d;
use std::io::{self,BufRead};
fn main() {
 for line in io::stdin().lock().lines() {
 let n:Vec<f64>=line.unwrap().split(',').map(|s|s.parse().unwrap()).collect();
 let p=Camera3DProperties {tilt_x:n[0],tilt_y:n[1],roll:n[2],rotate_x:n[3],rotate_y:n[4],zoom:n[5],fov:n[6],pan_x:n[7],pan_y:n[8]};
 let seg=Camera3DSegment {start:0.,end:4.,enabled:true,properties:p,transition_in:n[12],transition_out:n[13],..Default::default()};
 let frame=camera3d::interpolate_camera3d(n[14],std::slice::from_ref(&seg),n[9]).unwrap();
 let zoom=camera3d::Camera3DScreenZoom{content_uv:XY{x:n[10],y:n[11]},amount:n[15]};
 let effective=frame.pose.unwrap_or(Camera3DProperties{zoom:camera3d::plane_half_extents(n[9]).1/(p.fov.to_radians()/2.).tan(),fov:p.fov,..Default::default()});
 let h=camera3d::camera3d_inverse_homography(&effective,n[9],Some(&zoom)).unwrap();
 println!("{:?}",[h.inverse_rows[0][0] as f64,h.inverse_rows[0][1] as f64,h.inverse_rows[0][2] as f64,h.inverse_rows[1][0] as f64,h.inverse_rows[1][1] as f64,h.inverse_rows[1][2] as f64,h.inverse_rows[2][0] as f64,h.inverse_rows[2][1] as f64,h.inverse_rows[2][2] as f64,frame.activity]);
 }
}
'''
root = pathlib.Path(__file__).resolve().parents[1]
cap = pathlib.Path(sys.argv[1]).resolve()
revision = subprocess.check_output(['git', '-C', str(cap), 'rev-parse', 'HEAD'], text=True).strip()
with tempfile.TemporaryDirectory() as temp:
    temp = pathlib.Path(temp)
    module = json.dumps(str(cap / 'apps/desktop/src/routes/editor/three-d.ts'))
    (temp / 'presets.ts').write_text(f"import {{ ANGLE_PRESETS, MOTION_TEMPLATES, anglePresetMotion }} from {module};\nconsole.log(JSON.stringify([...MOTION_TEMPLATES, ...ANGLE_PRESETS.map(anglePresetMotion)]));")
    templates = json.loads(subprocess.check_output(['bun', str(temp / 'presets.ts')], text=True))
    # Only wire-type stubs: the algorithm is compiled directly from the upstream file.
    source = RUST.replace('UPSTREAM_SOURCE', str(cap / 'crates/rendering/src/camera3d.rs'))
    (temp / 'reference.rs').write_text(source)
    subprocess.run(['rustc', '--edition=2024', '-Awarnings', str(temp / 'reference.rs'), '-o', str(temp / 'reference')], check=True)
    def camera(pose):
        return {('distance' if k == 'zoom' else 'fieldOfView' if k == 'fov' else k): v for k, v in pose.items()} | {'amount': 1}
    def blur(value):
        return {('position' if k == 'dirPosition' else k): v for k, v in value.items()} | {'mode': {'none':'None','radial':'Radial','directional':'Directional','tiltShift':'Tilt shift'}[value['mode']]}
    presets = [{'name': t['name'], 'start': camera(t['from']), 'end': camera(t['to']), 'blur': blur(t['blur'])} for t in templates]
    cases = []
    for t in templates:
        for progress in [0, 0.5, 1]:
            pose = {k: v + (t['to'][k] - v) * progress for k,v in t['from'].items()}
            for aspect in [16/9, 1, 9/16]:
                for zoom in [1, 2.25]:
                    cases.append(dict(camera=camera(pose), aspect=aspect, zoom=zoom, target=[0.38,0.61], entry=0, exit=0, time=2))
    for aspect in [16/9, 9/16]:
        for time in [0, 0.1, 0.3, 0.7, 1, 3.7, 3.9]:
            cases.append(dict(camera=presets[0]['start'], aspect=aspect, zoom=1, target=[0.5,0.5], entry=1, exit=0.5, time=time))
    rows = []
    for c in cases:
        p=c['camera']
        rows.append(','.join(str(v) for v in [p[k] for k in ['tiltX','tiltY','roll','rotateX','rotateY','distance','fieldOfView','panX','panY']] + [c['aspect'],*c['target'],c['entry'],c['exit'],c['time'],c['zoom']]))
    output = subprocess.check_output([str(temp / 'reference')], input='\n'.join(rows)+'\n', text=True)
    for case,line in zip(cases, output.splitlines(), strict=True):
        result=json.loads(line); case['inverse']=result[:9]; case['activity']=result[9]
    (root / 'Tests/Fixtures/Cap3DReference.json').write_text(json.dumps(dict(revision=revision,presets=presets,cases=cases), separators=(',',':'))+'\n')
    print(f'Generated {len(presets)} presets and {len(cases)} renderer cases from {revision}')
