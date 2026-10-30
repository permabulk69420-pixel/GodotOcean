"""Run with blender --background --python tools/make_hand_thruster.py."""
import bpy
import math
import json
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'player' / 'thrusters'
OUTPUT.mkdir(parents=True, exist_ok=True)
FIT = json.loads((ROOT/'tools'/'thruster_fit.json').read_text())
BODY_X = max(value['body_x'] for value in FIT.values())
HANDLE_FRAME = Matrix(FIT['right']['handle_frame'])
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)


def material(name, colour, metallic, roughness, emission=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*colour, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*colour, 1)
    shader.inputs['Metallic'].default_value = metallic
    shader.inputs['Roughness'].default_value = roughness
    if emission:
        shader.inputs['Emission Color'].default_value = (*colour, 1)
        shader.inputs['Emission Strength'].default_value = emission
    return mat


pearl = material('Ceramic titanium', (0.73, 0.81, 0.83), .55, .24)
graphite = material('Graphite elastomer', (.018, .032, .04), .12, .42)
titanium = material('Brushed titanium', (.19, .27, .30), .85, .28)
teal = material('Inlaid turquoise', (.012, .56, .60), .55, .22)
light = material('Status light', (.05, .75, .82), .25, .2, .8)


def point(p):
    # Author in Godot's metre/Y-up/-Z-forward frame; export from Blender's Z-up.
    return (SIDE * p[0], -p[2], p[1])


def mesh(name, vertices, faces, mat, parent=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata([point(p) for p in vertices], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for poly in data.polygons:
        poly.use_smooth = True
    obj.parent = parent
    return obj


def lathe(name, profile, mat, center=None, parent=None, count=64):
    center = (BODY_X,.022,.07) if center is None else center
    verts = []
    for z, radius in profile:
        for i in range(count):
            a = 2 * math.pi * i / count
            verts.append((center[0]+radius*math.cos(a), center[1]+radius*math.sin(a)*.78, center[2]+z))
    faces = []
    for ring in range(len(profile)-1):
        for i in range(count):
            a = ring*count+i
            b = ring*count+(i+1) % count
            faces.append((a, b, b+count, a+count))
    return mesh(name, verts, faces, mat, parent)


def ellipsoid(name, center, radii, mat, parent=None, segments=24, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=point(center))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (radii[0], radii[2], radii[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons: poly.use_smooth = True
    obj.parent = parent
    return obj


def beam(name, start, end, radius, mat, parent=None, vertices=12):
    a, b = Vector(point(start)), Vector(point(end))
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=(b-a).length, location=(a+b)/2)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    obj.data.materials.append(mat)
    for p in obj.data.polygons: p.use_smooth = len(p.vertices)==4
    obj.parent = parent
    return obj


def build():
    body = bpy.data.objects.new('Housing', None)
    bpy.context.collection.objects.link(body)
    # A long, flattened pod runs behind the hand along the outside of the forearm.
    lathe('Sculpted forearm pod', [(-.18,.029),(-.174,.037),(-.157,.043),(-.105,.049),(-.02,.050),(.08,.046),(.16,.039),(.192,.033),(.20,.029),(.20,.023),(.182,.023),(.10,.028),(-.04,.033),(-.14,.032),(-.175,.026),(-.18,.029)], pearl, parent=body)
    lathe('Dark intake lining', [(-.175,.026),(-.145,.031),(-.11,.030),(-.11,.032),(-.145,.033),(-.175,.026)], graphite, parent=body)
    lathe('Intake titanium lip', [(-.178,.030),(-.172,.037),(-.166,.040),(-.163,.039),(-.17,.033),(-.178,.030)], titanium, parent=body)
    lathe('Intake turquoise seam', [(-.16,.042),(-.155,.044),(-.149,.045),(-.147,.044),(-.16,.042)], teal, parent=body)
    lathe('Exhaust collar', [(.179,.036),(.188,.035),(.200,.029),(.201,.025),(.196,.024),(.182,.027),(.179,.036)], titanium, parent=body)
    lathe('Exhaust status ring', [(.193,.031),(.198,.030),(.201,.028),(.201,.025),(.198,.025),(.193,.031)], light, parent=body)
    # Low side panels merge with the pod; no motor perched over a pistol grip.
    ellipsoid('Inlaid outer panel', (BODY_X+.039,.028,.070), (.014,.021,.139), teal, body, 32, 12)
    ellipsoid('Lower graphite keel', (BODY_X+.003,-.013,.087), (.030,.009,.135), graphite, body, 24, 10)
    ellipsoid('Upper spine', (BODY_X+.001,.056,.055), (.018,.007,.115), titanium, body, 24, 10)
    ellipsoid('Recessed status strip', (BODY_X+.050,.032,.082), (.0017,.0025,.085), light, body, 20, 8)
    # Palm bar is the origin. An open, curved C-frame joins it to the side pod.
    # Orient the grip itself to the imported palm's actual grasp frame. The pod
    # remains aligned to the forearm; the handle no longer cuts across the palm.
    profile=[(-.057,.1),(-.055,.5),(-.048,.90),(-.040,1),(-.034,1.015),(-.032,1),(-.023,1.015),(-.021,1),(-.012,1.015),(-.010,1),(-.001,1.015),(.001,1),(.010,1.015),(.012,1),(.021,1.015),(.023,1),(.040,1),(.048,.90),(.055,.5),(.057,.1)]
    vertices=[]
    for y,r in profile:
        for i in range(48):
            angle=2*math.pi*i/48
            vertices.append(tuple(HANDLE_FRAME@Vector((.0165*r*math.cos(angle),y,.0205*r*math.sin(angle)))))
    faces=[]
    for ring in range(len(profile)-1):
        for i in range(48):
            a=ring*48+i;b=ring*48+(i+1)%48
            faces.append((a,b,b+48,a+48))
    faces.extend([tuple(reversed(range(48))),tuple((len(profile)-1)*48+i for i in range(48))])
    mesh('Fitted palm grip',vertices,faces,graphite,body)
    trigger_center=HANDLE_FRAME@Vector((0,.029,-.0205))
    trigger=ellipsoid('Index trigger',trigger_center,(.010,.012,.002),teal,body)
    conversion=Matrix(((1,0,0),(0,0,-1),(0,1,0)))
    mirror=Matrix.Diagonal((SIDE,1,1))
    trigger.rotation_euler=(conversion@mirror@HANDLE_FRAME@mirror@conversion.inverted()).to_euler()
    for direction in [-1,1]:
        start=HANDLE_FRAME@Vector((0,direction*.067,0))
        points=[tuple(start),tuple(start+Vector((.016,0,.006))),(BODY_X*.55,start.y,.025+start.z),(BODY_X-.035,start.y*.85,.060),(BODY_X-.008,.022+direction*.018,.065)]
        beam('Grip end support',tuple(HANDLE_FRAME@Vector((0,direction*.055,0))),tuple(start),.0055,graphite,body,16)
        for a,b in zip(points,points[1:]): beam('Curved titanium bridge',a,b,.0055,pearl,body,16)
        for a in points[1:-1]: ellipsoid('Bridge fillet',a,(.006,.006,.007),pearl,body,16,8)
    for i in range(3):
        z=-.005+i*.027
        ellipsoid('Inset cooling vent',(BODY_X+.047,.013,z),(.002,.008,.008),graphite,body,16,8)
    # Sparse grille and visible, independently animated hydrofoil impeller.
    for i in range(5):
        a=i*2*math.pi/5
        beam('Intake guard',(BODY_X,.022,-.104),(BODY_X+.026*math.cos(a),.022+.020*math.sin(a),-.104),.0016,titanium,body,10)
    ellipsoid('Intake centre',(BODY_X,.022,-.104),(.006,.006,.006),pearl,body,16,8)
    rotor=bpy.data.objects.new('Propeller',None)
    bpy.context.collection.objects.link(rotor)
    rotor.location=point((BODY_X,.022,.245))
    ellipsoid('Impeller hub',(0,0,0),(.007,.007,.012),titanium,rotor,20,10)
    for i in range(5):
        a=2*math.pi*i/5
        vertices=[]
        for r,sweep,width,z in [(.005,0,.004,-.002),(.012,.18,.006,-.001),(.019,.40,.006,.002),(.023,.62,.003,.004)]:
            for sign in [-1,1]:
                phi=a+sweep+sign*width/r*.5
                vertices.append((r*math.cos(phi),r*math.sin(phi),z+sign*.001))
        blade=mesh('Swept hydrofoil',vertices,[(0,1,3,2),(2,3,5,4),(4,5,7,6)],titanium,rotor)
        modifier=blade.modifiers.new('Blade thickness','SOLIDIFY');modifier.thickness=.001
        bpy.context.view_layer.objects.active=blade
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    grip=bpy.data.objects.new('GripPoint',None)
    bpy.context.collection.objects.link(grip)
    grip.empty_display_size=.025
    axis=bpy.data.objects.new('ThrustAxis',None)
    bpy.context.collection.objects.link(axis)
    axis.location=point((BODY_X,.022,.07))
    for mat in [pearl,graphite,titanium,teal,light]:
        bpy.ops.object.select_all(action='DESELECT')
        pieces=[o for o in list(bpy.data.objects) if o.type=='MESH' and o.parent==body and o.data.materials[0]==mat]
        if not pieces: continue
        for obj in pieces: obj.select_set(True)
        bpy.context.view_layer.objects.active=pieces[0]
        bpy.ops.object.join()
        pieces[0].name=mat.name.replace(' ','')
    bpy.ops.object.select_all(action='DESELECT')
    pieces=[o for o in bpy.data.objects if o.type=='MESH' and o.parent==rotor]
    for obj in pieces: obj.select_set(True)
    bpy.context.view_layer.objects.active=pieces[0]
    bpy.ops.object.join()
    pieces[0].name='Impeller'
    for obj in bpy.data.objects:
        if obj.type=='MESH':
            bpy.context.view_layer.objects.active=obj
            bpy.ops.object.select_all(action='DESELECT')
            obj.select_set(True)
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.mesh.normals_make_consistent(inside=False)
            bpy.ops.object.mode_set(mode='OBJECT')


for SIDE in [1,-1]:
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    build()
    name='hand_thruster' if SIDE==1 else 'hand_thruster_left'
    if SIDE==1: bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'tools'/'hand_thruster.blend'))
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT/(name+'.glb')),export_format='GLB',export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
    print('THRUSTER',name,sum(len(o.data.polygons) for o in bpy.data.objects if o.type=='MESH'),'faces;', (OUTPUT/(name+'.glb')).stat().st_size,'bytes')
