"""Fit the imported skate hand skins to the authored handle; bake rigid grip poses.

python3 tools/fit_hand_thruster.py hand-fit-input.json
The input is emitted by Godot's dump_hand_fit.gd; no runtime mesh searches occur.
"""
import json
import math
import sys
from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation

ROOT = Path(__file__).resolve().parents[1]
INPUT = json.load(open(sys.argv[1]))
MARGIN = .0015
RADII = np.array([.0175, .0175, .022])
HALF_SHAFT = .04


def slerp(a, b, t):
    dot = np.dot(a, b)
    if dot < 0: b, dot = -b, -dot
    if dot > .9995:
        q = a + (b-a)*t
        return q / np.linalg.norm(q)
    angle = math.acos(np.clip(dot, -1, 1))
    return (a*math.sin((1-t)*angle) + b*math.sin(t*angle)) / math.sin(angle)


def solve(side, data):
    names = data['names']
    positions = np.array([b['position'] for b in data['poses']['Open']])
    quaternions = {p: np.array([b['rotation'] for b in data['poses'][p]]) for p in ['Open','Grip','Fist']}
    skeleton = np.array(data['skeleton_transform'])
    vertices = np.c_[data['vertices'], np.ones(len(data['vertices']))]
    weights = np.array(data['weights']).reshape(len(vertices), -1)
    ids = np.array(data['bones']).reshape(len(vertices), -1)
    joint_ids = np.array([b['bone'] for b in data['binds']])[ids]
    faces = np.array(data['indices']).reshape(-1, 3)
    amounts = np.zeros(len(names))
    fingers = {name: [i for i, bone in enumerate(names) if f'_{name}' in bone and bone[-1].isdigit()] for name in ['index','middle','ring','pinky','thumb']}

    def rotations():
        result = []
        for i, value in enumerate(amounts):
            if value <= .65:
                q = slerp(quaternions['Open'][i], quaternions['Grip'][i], value/.65)
            else:
                q = slerp(quaternions['Grip'][i], quaternions['Fist'][i], (value-.65)/.35)
            result.append(q)
        return np.array(result)

    def skin():
        bases = Rotation.from_quat(rotations()).as_matrix()
        globals_ = []
        for i, parent in enumerate(data['parents']):
            m = np.eye(4);m[:3,:3] = bases[i];m[:3,3] = positions[i]
            globals_.append(m if parent < 0 else globals_[parent] @ m)
        matrices = np.array([skeleton @ globals_[b['bone']] @ np.array(b['matrix']) for b in data['binds']])
        points = np.einsum('nkij,nj,nk->ni', matrices[ids], vertices, weights)[:,:3]
        return points, globals_

    points, globals_ = skin()
    grip_index = names.index('b_l_grip' if side == 'left' else 'b_r_grip')
    grip_matrix = skeleton @ globals_[grip_index]
    frame = grip_matrix[:3,:3] @ np.diag([-1.,-1.,1.])
    origin = np.array(data['grip_origin'])
    normal = np.array([1. if side=='left' else -1.,0,0])
    shift = 0.

    def samples(points, triangles):
        p = points[triangles]
        return np.concatenate([p.reshape(-1,3),p.mean(1),(p[:,0]+p[:,1])*.5,(p[:,1]+p[:,2])*.5,(p[:,2]+p[:,0])*.5],axis=0)

    def clearance(points, triangles=faces):
        p = (samples(points, triangles) - origin - normal*shift) @ frame
        p[:,1] -= np.clip(p[:,1], -HALF_SHAFT, HALF_SHAFT)
        k0 = np.linalg.norm(p/RADII, axis=1)
        k1 = np.linalg.norm(p/(RADII*RADII), axis=1)
        return np.min(k0*(k0-1)/np.maximum(k1,1e-9))

    # Match the skate game's palm fitting: clear the OPEN skin before curling.
    while clearance(points) < MARGIN and shift < .060:
        shift += .0005
    if clearance(points) < MARGIN:
        raise RuntimeError(f'{side}: handle cannot clear the open palm within 60 mm')

    for finger, joints in fingers.items():
        membership = np.any(np.isin(joint_ids,joints) & (weights>.01),axis=1)
        triangles = faces[np.any(membership[faces],axis=1)]

        def advance(selected):
            start = amounts.copy()
            low = 0.
            for step in range(1,21):
                high = step/20
                amounts[selected] = start[selected] + (1-start[selected])*high
                posed,_ = skin()
                if clearance(posed,triangles) < MARGIN:
                    for _ in range(7):
                        mid = (low+high)*.5
                        amounts[selected] = start[selected] + (1-start[selected])*mid
                        posed,_ = skin()
                        if clearance(posed,triangles) < MARGIN: high = mid
                        else: low = mid
                    break
                low = high
            amounts[selected] = start[selected] + (1-start[selected])*low

        advance(joints)
        for joint in reversed(joints): advance([joint])

    points,_ = skin()
    if clearance(points) < MARGIN-1e-5:
        raise RuntimeError(f'{side}: solved pose failed its final handle clearance')
    offset = normal*shift
    # Housing stays outside the outermost posed hand surface, with 6 mm margin.
    outside = -1 if side=='left' else 1
    hand_outside = np.max(points[:,0]*outside)
    mount_outside = (origin[0]+offset[0])*outside
    body_x = hand_outside - mount_outside + .050 + .006
    print(side,'palm shift mm',round(shift*1000,2),'clearance mm',round(clearance(points)*1000,3),'body x',body_x,'joint closure',amounts[amounts>0])
    return {'offset':offset.tolist(),'rotations':{names[i]:q.tolist() for i,q in enumerate(rotations()) if any(i in joints for joints in fingers.values())},'handle_frame':frame.tolist(),'body_x':body_x,'hand_bounds':[points.min(0).tolist(),points.max(0).tolist()]}


results = {side:solve(side,data) for side,data in INPUT.items()}
lines = ['extends RefCounted', '# Generated from the actual skinned hands by tools/fit_hand_thruster.py.']
for side, result in results.items():
    name = side.upper()
    lines.append(f'const {name}_OFFSET = Vector3({", ".join(f"{v:.10f}" for v in result["offset"])})')
    lines.append(f'const {name}_ROTATIONS = {{')
    for bone, q in result['rotations'].items():
        lines.append(f'\t&"{bone}": Quaternion({", ".join(f"{v:.10f}" for v in q)}),')
    lines.append('}')
(ROOT/'player/hand_grip_data.gd').write_text('\n'.join(lines)+'\n')
(ROOT/'tools/thruster_fit.json').write_text(json.dumps(results,indent=2)+'\n')
