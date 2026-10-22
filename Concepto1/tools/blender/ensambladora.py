"""Ensambladora paramétrica de Codemageddon para Blender (modo sin ventana).

Uso:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python tools/blender/ensambladora.py -- assets/ensambladora.glb

Unidad: 1 m = 1 casilla del mapa. La máquina ocupa 3x3 casillas.
Exporta una prensa con animación rígida por piezas (pistón y ventilador),
que el demo reproduce con AnimationMixer.
"""
import math
import sys

import bpy

# --- parámetros (se pueden variar para generar la familia) -----------------
P = dict(
    ancho=2.8,          # huella X
    fondo=2.8,          # huella Z (Y en Blender)
    alto_cuerpo=1.5,
    alto_base=0.22,
    radio_chimenea=0.22,
    alto_chimenea=0.9,
    carrera_piston=0.45,
    fotogramas=48,      # ciclo de la animación a 24 fps = 2 s
)

COLORES = {
    "acero": (0.16, 0.20, 0.27, 1),
    "acero_claro": (0.33, 0.40, 0.51, 1),
    "ambar": (0.95, 0.58, 0.13, 1),
    "neon": (0.15, 0.85, 0.95, 1),
    "goma": (0.05, 0.05, 0.06, 1),
}


def limpiar():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(nombre, color, metal=0.6, rugosidad=0.45, emision=0.0):
    m = bpy.data.materials.new(nombre)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rugosidad
    if emision:
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = emision
    return m


def caja(nombre, tam, pos, mat, bisel=0.04, padre=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    o = bpy.context.active_object
    o.name = nombre
    o.scale = tam
    bpy.ops.object.transform_apply(scale=True)
    if bisel:
        mod = o.modifiers.new("bisel", "BEVEL")
        mod.width = bisel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(mat)
    if padre:
        o.parent = padre
    return o


def cilindro(nombre, r, h, pos, mat, verts=20, padre=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=pos, vertices=verts)
    o = bpy.context.active_object
    o.name = nombre
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    if padre:
        o.parent = padre
    return o


def construir():
    m = {k: material(k, c, emision=(4.0 if k == "neon" else 0.0),
                     metal=(0.0 if k in ("goma", "neon") else 0.6))
         for k, c in COLORES.items()}
    a, f = P["ancho"], P["fondo"]
    hb, hc = P["alto_base"], P["alto_cuerpo"]

    bpy.ops.object.empty_add(location=(0, 0, 0))
    raiz = bpy.context.active_object
    raiz.name = "Ensambladora"

    caja("base", (a, f, hb), (0, 0, hb / 2), m["acero"], padre=raiz)
    cuerpo = caja("cuerpo", (a * 0.86, f * 0.7, hc), (0, f * 0.08, hb + hc / 2), m["acero_claro"], padre=raiz)
    # franja de estado (neón) y rayas de seguridad
    caja("franja_neon", (a * 0.87, 0.06, 0.08), (0, f * 0.08 - f * 0.35 - 0.01, hb + hc * 0.82), m["neon"], bisel=0, padre=raiz)
    for i in range(5):
        x = -a * 0.4 + i * a * 0.2
        o = caja(f"raya_{i}", (0.12, 0.05, 0.3), (x, -f * 0.5 + 0.02, hb + 0.18), m["ambar"], bisel=0, padre=raiz)
        o.rotation_euler.y = math.radians(30)
    # boca de salida
    caja("boca", (a * 0.4, 0.5, 0.5), (0, -f * 0.32, hb + 0.25), m["goma"], padre=raiz)
    # chimenea y ventilador
    cx, cy = a * 0.28, f * 0.22
    cilindro("chimenea", P["radio_chimenea"], P["alto_chimenea"],
             (cx, cy, hb + hc + P["alto_chimenea"] / 2), m["acero"], padre=raiz)
    bpy.ops.object.empty_add(location=(-a * 0.22, f * 0.2, hb + hc + 0.08))
    ventilador = bpy.context.active_object
    ventilador.name = "ventilador"
    ventilador.parent = raiz
    for i in range(4):
        aspa = caja(f"aspa_{i}", (0.55, 0.12, 0.03), (0, 0, 0), m["ambar"], bisel=0.01, padre=ventilador)
        aspa.location = (-a * 0.22, f * 0.2, hb + hc + 0.08)
        aspa.rotation_euler.z = math.radians(45 * i)
    # pistón de la prensa
    alto_piston = hb + hc + 0.35
    bpy.ops.object.empty_add(location=(0, -f * 0.32, alto_piston))
    piston = bpy.context.active_object
    piston.name = "piston"
    piston.parent = raiz
    vastago = cilindro("vastago", 0.07, 0.7, (0, -f * 0.32, alto_piston + 0.1), m["acero_claro"], padre=piston)
    cabeza = caja("cabeza", (0.6, 0.45, 0.16), (0, -f * 0.32, alto_piston - 0.3), m["ambar"], padre=piston)
    caja("soporte_piston", (0.8, 0.5, 0.18), (0, -f * 0.32, hb + hc + 0.5), m["acero"], padre=raiz)

    # piezas hijas: aplicar posición relativa al padre
    for o in (vastago, cabeza):
        o.matrix_parent_inverse = piston.matrix_world.inverted()
    for o in ventilador.children:
        o.matrix_parent_inverse = ventilador.matrix_world.inverted()

    # animación rígida
    n = P["fotogramas"]
    escena = bpy.context.scene
    escena.frame_start, escena.frame_end = 0, n
    escena.render.fps = 24
    for fr, dz in ((0, 0), (n * 0.35, 0), (n * 0.5, -P["carrera_piston"]), (n * 0.62, 0), (n, 0)):
        piston.location.z = alto_piston + dz
        piston.keyframe_insert("location", index=2, frame=int(fr))
    for fr, ang in ((0, 0), (n, 360)):
        ventilador.rotation_euler.z = math.radians(ang)
        ventilador.keyframe_insert("rotation_euler", index=2, frame=fr)
    for obj in (piston, ventilador):
        for fc in obj.animation_data.action.fcurves if hasattr(obj.animation_data.action, "fcurves") else []:
            for k in fc.keyframe_points:
                k.interpolation = "LINEAR" if obj is ventilador else "BEZIER"
    for obj in (piston, ventilador):
        obj.animation_data.action.name = f"{obj.name}_ciclo"
    return raiz


def exportar(ruta):
    bpy.ops.export_scene.gltf(
        filepath=ruta,
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_apply=True,
    )


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    salida = argv[0] if argv else "ensambladora.glb"
    limpiar()
    construir()
    exportar(salida)
    print("EXPORTADO", salida)
