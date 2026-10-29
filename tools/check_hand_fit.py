"""blender --background --python tools/check_hand_fit.py -- snapshot.json"""
import json
import sys
from mathutils.bvhtree import BVHTree
from mathutils import Vector

path = sys.argv[sys.argv.index('--') + 1]
snapshot = json.load(open(path))
failures = []
directions = [Vector((.873,.371,-.316)).normalized(),Vector((-.448,.86,.243)).normalized(),Vector((.235,-.254,.938)).normalized()]
def inside(tree, point):
    votes = 0
    for direction in directions:
        origin = Vector(point)
        crossings = 0
        for _ in range(128):
            hit,normal,index,distance = tree.ray_cast(origin,direction,10.0)
            if hit is None: break
            crossings += 1
            origin = hit + direction*.00001
        votes += crossings % 2
    return votes >= 2
for side, data in snapshot.items():
    trees = []
    for name in ['hand', 'thruster']:
        geometry = data[name]
        ids = geometry['indices']
        triangles = [ids[i:i+3] for i in range(0, len(ids), 3)]
        trees.append(BVHTree.FromPolygons(geometry['vertices'], triangles, all_triangles=True))
    pairs = trees[0].overlap(trees[1])
    skin = data['hand']['vertices']
    tool = data['thruster']['vertices']
    contained_skin = sum(inside(trees[1],p) for p in skin)
    contained_tool = sum(inside(trees[0],p) for p in tool[::8])
    clearance = min(trees[1].find_nearest(Vector(p))[3] for p in skin)
    print(f'{side}: {len(pairs)} intersecting triangle pairs; {contained_skin} contained skin vertices; {contained_tool} contained tool samples; nearest sampled skin clearance {clearance*1000:.3f} mm', flush=True)
    if pairs or contained_skin or contained_tool or clearance < .0005:
        failures.append(side)
if failures:
    print('HAND GEOMETRY: FAIL', flush=True)
    raise RuntimeError('Hand/tool penetration detected: ' + ', '.join(failures))
print('HAND GEOMETRY: PASS', flush=True)
