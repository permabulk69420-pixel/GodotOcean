"""Run with: blender --background --python tools/make_seagrass.py
Builds two low-poly seagrass clumps and exports world/vegetation/seagrass.glb.
Vertex colour: R = height along the blade (sway weight), G = per-blade random (tint and phase)."""
import bpy, bmesh, math, random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'world' / 'vegetation'
OUTPUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def point(p):
    # Author in the game's Y-up frame; Blender is Z-up.
    return (p[0], -p[2], p[1])

def clump(name, seed, blades, min_len, max_len, spread, segments=5):
    rng = random.Random(seed)
    verts, faces, colours = [], [], []
    for b in range(blades):
        length = rng.uniform(min_len, max_len)
        base_angle = rng.uniform(0, math.tau)
        radius = spread * math.sqrt(rng.random())
        base = (math.cos(base_angle) * radius, 0.0, math.sin(base_angle) * radius)
        lean_dir = base_angle + rng.uniform(-0.6, 0.6)   # blades fan outward from the clump
        lean = rng.uniform(0.15, 0.55) * (0.6 + 0.4 * radius / max(spread, 1e-4))
        facing = rng.uniform(0, math.tau)                  # the direction the flat side faces
        width = rng.uniform(0.045, 0.085) * (0.7 + 0.5 * length)
        tint = rng.random()
        start = len(verts)
        for s in range(segments + 1):
            t = s / segments
            # The blade bends over progressively towards its tip.
            bend = lean * t * t * length
            centre = (base[0] + math.cos(lean_dir) * bend,
                      base[1] + t * length * (1.0 - 0.22 * lean * t),
                      base[2] + math.sin(lean_dir) * bend)
            half = width * 0.5 * (1.0 - 0.82 * t * t)      # tapers to a narrow tip
            side = (math.cos(facing + math.pi / 2), 0.0, math.sin(facing + math.pi / 2))
            verts.append((centre[0] - side[0] * half, centre[1], centre[2] - side[2] * half))
            verts.append((centre[0] + side[0] * half, centre[1], centre[2] + side[2] * half))
            colours.extend([(t, tint, 0.0, 1.0)] * 2)
        for s in range(segments):
            a = start + s * 2
            faces.append((a, a + 1, a + 3, a + 2))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([point(v) for v in verts], [], faces)
    mesh.update()
    for poly in mesh.polygons:
        poly.use_smooth = True
    attribute = mesh.color_attributes.new('Color', 'FLOAT_COLOR', 'POINT')
    for i, c in enumerate(colours):
        attribute.data[i].color = c
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    # Fix winding so normals are consistent.
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    return obj

material = bpy.data.materials.new('Seagrass')
material.diffuse_color = (0.12, 0.38, 0.14, 1)
for name, seed, blades, lo, hi, spread in [
    ('SeagrassShort', 11, 13, 0.45, 0.95, 0.22),
    ('SeagrassTall', 29, 10, 1.05, 1.85, 0.28),
]:
    obj = clump(name, seed, blades, lo, hi, spread)
    obj.data.materials.append(material)

# Lay the two variants side by side only for the preview; the game uses each mesh on its own.
bpy.ops.export_scene.gltf(filepath=str(OUTPUT / 'seagrass.glb'), export_format='GLB', export_yup=True,
                          export_animations=False, export_cameras=False, export_lights=False,
                          export_attributes=True)
total = sum(len(o.data.polygons) * 2 for o in bpy.data.objects if o.type == 'MESH')
print('SEAGRASS triangles', total, [ (o.name, len(o.data.polygons)*2) for o in bpy.data.objects if o.type=='MESH'])
