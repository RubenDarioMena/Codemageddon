"""Familia de modelos 3D de Codemageddon (Concepto 2), generada por código en Blender.

Uso sin ventana (exporta todos los modelos a assets/modelos/*.glb):
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python tools/blender/modelos.py -- assets/modelos

Uso desde una sesión abierta (MCP o consola de Blender): importar este archivo y llamar
`vista_previa()`, que construye todo en una escena nueva «Codemageddon» sin tocar las demás.

Convenciones:
- 1 m = 1 casilla del mapa. Las máquinas se centran en el origen y apoyan en z = 0.
- Entrada de material por -X y salida por +X. Godot rota el modelo en pasos de 90°.
- Vehículos y robots miran hacia +Y de Blender, que en Godot es -Z (su «adelante»).
- Las piezas que Godot necesita encontrar llevan nombres fijos: «pantalla» (cara del
  robot, Godot le pone la textura pixel art), «luz_estado», «brasa», «oruga_i/d».
- Cada modelo exporta una sola animación de escena, «ciclo», que Godot reproduce en bucle.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

COLORES = {
    "acero": (0.16, 0.20, 0.27, 1),
    "acero_claro": (0.33, 0.40, 0.51, 1),
    "ambar": (0.95, 0.58, 0.13, 1),
    "neon": (0.15, 0.85, 0.95, 1),
    "goma": (0.05, 0.05, 0.06, 1),
    "ladrillo": (0.36, 0.23, 0.19, 1),
    "brasa": (1.0, 0.36, 0.05, 1),
    "blanco": (0.82, 0.85, 0.88, 1),
    "azul": (0.12, 0.30, 0.72, 1),
    "verde": (0.20, 0.62, 0.36, 1),
    "pantalla": (0.02, 0.05, 0.06, 1),
    "madera": (0.55, 0.38, 0.22, 1),
}
EMISIVOS = {"neon": 4.0, "brasa": 6.0}
SIN_METAL = {"goma", "neon", "brasa", "ladrillo", "pantalla", "madera", "blanco"}

_mats = {}


def material(nombre):
    if nombre in _mats and _mats[nombre].name in bpy.data.materials:
        return _mats[nombre]
    m = bpy.data.materials.new(nombre)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    color = COLORES[nombre]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = 0.0 if nombre in SIN_METAL else 0.6
    bsdf.inputs["Roughness"].default_value = 0.8 if nombre in SIN_METAL else 0.45
    if nombre in EMISIVOS:
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = EMISIVOS[nombre]
    _mats[nombre] = m
    return m


def _enlazar(o, col):
    for c in o.users_collection:
        c.objects.unlink(o)
    col.objects.link(o)


class Constructor:
    """Crea piezas bajo una raíz (Empty) dentro de una colección."""

    def __init__(self, nombre, col):
        self.col = col
        self.raiz = bpy.data.objects.new(nombre, None)
        col.objects.link(self.raiz)

    def _poner(self, o, nombre, mat, padre):
        o.name = nombre
        if mat:
            o.data.materials.append(material(mat))
        _enlazar(o, self.col)
        o.parent = padre or self.raiz
        return o

    def caja(self, nombre, tam, pos, mat, bisel=0.03, rot=(0, 0, 0), padre=None):
        bpy.ops.mesh.primitive_cube_add(size=1, location=pos, rotation=rot)
        o = bpy.context.active_object
        o.scale = tam
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        if bisel:
            mod = o.modifiers.new("bisel", "BEVEL")
            mod.width = bisel
            mod.segments = 2
            bpy.ops.object.modifier_apply(modifier=mod.name)
        return self._poner(o, nombre, mat, padre)

    def cilindro(self, nombre, r, h, pos, mat, rot=(0, 0, 0), verts=20, r2=None, padre=None):
        if r2 is None:
            bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=pos, rotation=rot, vertices=verts)
        else:
            bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, location=pos, rotation=rot, vertices=verts)
        o = bpy.context.active_object
        bpy.ops.object.shade_smooth()
        return self._poner(o, nombre, mat, padre)

    def pivote(self, nombre, pos, padre=None):
        """Empty con posición de mundo `pos` (para girar piezas alrededor de él)."""
        o = bpy.data.objects.new(nombre, None)
        self.col.objects.link(o)
        o.parent = padre or self.raiz
        bpy.context.view_layer.update()
        o.location = Vector(pos) - o.parent.matrix_world.translation
        return o

    def hijo_de(self, pieza, pivote):
        """Cuelga una pieza ya creada (en coordenadas de mundo) de un pivote."""
        bpy.context.view_layer.update()
        m = pieza.matrix_world.copy()
        pieza.parent = pivote
        pieza.matrix_world = m


def clave(obj, ruta, fotogramas, interp="LINEAR"):
    """fotogramas: [(frame, valor_tupla_o_escalar)] sobre obj.<ruta>."""
    for fr, v in fotogramas:
        setattr(obj, ruta, v)
        obj.keyframe_insert(ruta, frame=int(fr))
    acc = obj.animation_data.action
    curvas = getattr(acc, "fcurves", None)
    if curvas is None:  # Blender 5: acciones por capas
        curvas = [fc for capa in acc.layers for tira in capa.strips
                  for bolsa in tira.channelbags for fc in bolsa.fcurves]
    for fc in curvas:
        for k in fc.keyframe_points:
            k.interpolation = interp


N = 48  # fotogramas por ciclo a 24 fps = 2 s


# ---------------------------------------------------------------- máquinas

def base_maquina(c, ancho, fondo, alto=0.2):
    c.caja("base", (ancho, fondo, alto), (0, 0, alto / 2), "acero")
    # puertos: entrada (-X) cian, salida (+X) ámbar
    c.caja("puerto_entrada", (0.1, 0.7, 0.32), (-ancho / 2 - 0.02, 0, alto + 0.16), "neon", bisel=0)
    c.caja("puerto_salida", (0.1, 0.7, 0.32), (ancho / 2 + 0.02, 0, alto + 0.16), "ambar", bisel=0)


def luz_estado(c, pos):
    c.cilindro("luz_estado", 0.09, 0.14, pos, "blanco", verts=12)


def fundidora(col):
    c = Constructor("Fundidora", col)
    base_maquina(c, 2.8, 2.8)
    c.caja("horno", (1.7, 1.7, 1.3), (0.15, 0.1, 0.85), "ladrillo", bisel=0.06)
    c.caja("boca_brasa", (0.06, 0.8, 0.45), (0.15 - 0.87, 0.1, 0.62), "brasa", bisel=0)
    c.caja("tolva", (0.9, 1.0, 0.5), (-0.95, 0.1, 1.05), "acero_claro", rot=(0, math.radians(-12), 0))
    c.cilindro("chimenea", 0.24, 1.6, (0.55, 0.55, 2.2), "acero")
    c.cilindro("aro_chimenea", 0.3, 0.12, (0.55, 0.55, 2.95), "ambar")
    c.caja("molde_salida", (0.8, 0.6, 0.14), (1.0, -0.35, 0.3), "acero_claro")
    luz_estado(c, (-0.6, -0.95, 1.6))
    # crisol que bascula
    piv = c.pivote("crisol", (0.95, -0.35, 1.2))
    cr = c.cilindro("cuba", 0.3, 0.42, (0.95, -0.35, 1.2), "acero", verts=16, r2=0.22)
    br = c.cilindro("brasa", 0.24, 0.04, (0.95, -0.35, 1.42), "brasa", verts=16)
    c.hijo_de(cr, piv)
    c.hijo_de(br, piv)
    clave(piv, "rotation_euler", [(0, (0, 0, 0)), (N * 0.45, (0, 0, 0)), (N * 0.6, (0, math.radians(38), 0)),
                                  (N * 0.75, (0, 0, 0)), (N, (0, 0, 0))], "BEZIER")
    return c.raiz


def ensambladora(col):
    c = Constructor("Ensambladora", col)
    base_maquina(c, 2.8, 2.8)
    c.caja("cuerpo", (2.4, 1.9, 1.4), (0, 0.25, 0.9), "acero_claro")
    c.caja("franja_neon", (2.42, 0.05, 0.08), (0, 0.25 - 0.96, 1.4), "neon", bisel=0)
    for i in range(5):
        c.caja(f"raya_{i}", (0.12, 0.05, 0.3), (-1.1 + i * 0.55, -1.38, 0.38), "ambar", bisel=0,
               rot=(0, math.radians(30), 0))
    c.caja("boca", (1.1, 0.5, 0.5), (0, -0.9, 0.45), "goma")
    c.caja("soporte_piston", (0.8, 0.5, 0.18), (0, -0.9, 2.1), "acero")
    c.cilindro("chimenea", 0.2, 0.9, (0.8, 0.7, 2.05), "acero")
    luz_estado(c, (-0.95, -0.72, 1.75))
    piv = c.pivote("piston", (0, -0.9, 1.95))
    v = c.cilindro("vastago", 0.07, 0.7, (0, -0.9, 2.05), "acero_claro")
    h = c.caja("cabeza", (0.6, 0.45, 0.16), (0, -0.9, 1.65), "ambar")
    c.hijo_de(v, piv)
    c.hijo_de(h, piv)
    clave(piv, "location", [(0, (0, -0.9, 1.95)), (N * 0.35, (0, -0.9, 1.95)), (N * 0.5, (0, -0.9, 1.5)),
                            (N * 0.62, (0, -0.9, 1.95)), (N, (0, -0.9, 1.95))], "BEZIER")
    vent = c.pivote("ventilador", (-0.6, 0.6, 1.66))
    for i in range(4):
        a = c.caja(f"aspa_{i}", (0.55, 0.12, 0.03), (-0.6, 0.6, 1.66), "ambar", bisel=0.01,
                   rot=(0, 0, math.radians(45 * i)))
        c.hijo_de(a, vent)
    clave(vent, "rotation_euler", [(0, (0, 0, 0)), (N, (0, 0, math.radians(360)))])
    return c.raiz


def fabrica_robots(col):
    c = Constructor("FabricaRobots", col)
    base_maquina(c, 3.8, 3.8)
    c.caja("nave_trasera", (3.6, 1.4, 2.0), (0, 1.15, 1.2), "acero_claro")
    c.caja("techo_dientes", (3.6, 1.4, 0.3), (0, 1.15, 2.35), "azul", rot=(math.radians(-14), 0, 0))
    c.caja("franja_neon", (3.62, 0.05, 0.08), (0, 0.44, 1.9), "neon", bisel=0)
    c.caja("plataforma", (2.0, 1.6, 0.18), (0, -0.7, 0.29), "acero_claro")
    for x in (-1.6, 1.6):
        c.caja(f"poste_{x:+.0f}", (0.12, 0.12, 1.6), (x, -1.6, 1.0), "ambar")
    luz_estado(c, (1.4, 0.4, 2.3))
    # brazo de montaje que gira
    giro = c.pivote("brazo_giro", (0.9, -0.2, 0.4))
    c.hijo_de(c.cilindro("brazo_base", 0.28, 0.25, (0.9, -0.2, 0.5), "acero"), giro)
    seg = c.pivote("brazo_codo", (0.9, -0.2, 0.62), padre=giro)
    c.hijo_de(c.caja("brazo_a", (0.16, 0.16, 0.9), (0.9, -0.2, 1.05), "ambar"), seg)
    c.hijo_de(c.caja("brazo_b", (0.8, 0.14, 0.14), (0.55, -0.2, 1.5), "ambar"), seg)
    c.hijo_de(c.cilindro("soldador", 0.05, 0.3, (0.17, -0.2, 1.38), "neon", verts=8), seg)
    clave(giro, "rotation_euler", [(0, (0, 0, 0)), (N * 0.5, (0, 0, math.radians(70))), (N, (0, 0, 0))], "BEZIER")
    clave(seg, "rotation_euler", [(0, (0, 0, 0)), (N * 0.25, (math.radians(-12), 0, 0)),
                                  (N * 0.75, (math.radians(10), 0, 0)), (N, (0, 0, 0))], "BEZIER")
    return c.raiz


def recepcion(col):
    c = Constructor("Recepcion", col)
    c.caja("losa", (3.8, 2.8, 0.18), (0, 0, 0.09), "acero")
    c.caja("anden", (1.2, 2.8, 0.7), (-1.3, 0, 0.35), "acero_claro")
    c.caja("puerto_salida", (0.1, 0.7, 0.32), (1.92, 0, 0.34), "ambar", bisel=0)
    for i in range(6):
        c.caja(f"raya_{i}", (0.1, 0.4, 0.02), (-0.4 + (i % 3) * 0.9, -1.15 + (i // 3) * 2.3, 0.19), "ambar", bisel=0)
    c.caja("tejado", (2.0, 3.0, 0.08), (-1.0, 0, 2.2), "azul", rot=(0, math.radians(8), 0))
    for y in (-1.35, 1.35):
        c.caja(f"pilar_{y:+.0f}", (0.12, 0.12, 2.1), (-0.15, y, 1.1), "acero_claro")
    c.caja("rotulo", (0.06, 1.4, 0.35), (-0.12, 0, 1.75), "ambar", bisel=0)
    luz_estado(c, (-0.12, -0.9, 1.95))
    return c.raiz


def despacho(col):
    c = Constructor("Despacho", col)
    base_maquina(c, 2.8, 2.8)
    c.caja("puerto_salida", (0.1, 0.7, 0.32), (1.42, 0, 0.36), "goma", bisel=0)  # tapa la salida
    c.caja("nave", (2.2, 2.4, 1.6), (0.2, 0, 1.0), "verde")
    c.caja("puerta", (0.06, 1.6, 1.2), (1.32, 0, 0.8), "acero_claro", bisel=0)
    for i in range(6):
        c.caja(f"lama_{i}", (0.07, 1.6, 0.04), (1.35, 0, 0.3 + i * 0.18), "acero", bisel=0)
    c.caja("rampa", (1.0, 1.6, 0.12), (-0.95, 0, 0.32), "acero_claro", rot=(0, math.radians(-10), 0))
    c.caja("tejado", (2.4, 2.6, 0.12), (0.2, 0, 1.86), "acero")
    luz_estado(c, (-0.85, -1.0, 1.4))
    return c.raiz


def servidor(col):
    c = Constructor("Servidor", col)
    c.caja("base", (1.8, 1.8, 0.16), (0, 0, 0.08), "acero")
    c.caja("rack", (1.3, 1.3, 1.9), (0, 0, 1.11), "acero")
    for i in range(7):
        c.caja(f"bahia_{i}", (1.32, 0.02, 0.16), (0, -0.66, 0.4 + i * 0.24), "goma", bisel=0)
        c.caja(f"led_{i}", (0.08, 0.03, 0.05), (0.45, -0.68, 0.4 + i * 0.24), "neon", bisel=0)
    c.caja("antena", (0.04, 0.04, 0.7), (0.4, 0.4, 2.4), "acero_claro", bisel=0)
    c.cilindro("disco", 0.25, 0.06, (-0.3, 0.3, 2.12), "blanco", rot=(math.radians(25), 0, 0))
    luz_estado(c, (-0.45, -0.68, 2.0))
    return c.raiz


# ---------------------------------------------------------------- vehículos y robots

def orugas(c, ancho, largo, alto, padre=None):
    for lado, x in (("i", -ancho / 2), ("d", ancho / 2)):
        c.caja(f"oruga_{lado}", (0.16, largo, alto), (x, 0, alto / 2), "goma", bisel=0.05, padre=padre)


def camion(col):
    c = Constructor("Camion", col)
    for y in (-1.0, 0.0, 1.1):
        for x in (-0.55, 0.55):
            c.cilindro(f"rueda_{x:+.0f}_{y:+.0f}", 0.26, 0.2, (x, y, 0.26), "goma", rot=(0, math.radians(90), 0), verts=14)
    c.caja("chasis", (1.1, 3.2, 0.2), (0, 0, 0.48), "acero")
    c.caja("cabina", (1.2, 0.9, 0.95), (0, 1.15, 1.05), "blanco")
    c.caja("parabrisas", (1.0, 0.04, 0.4), (0, 1.61, 1.25), "pantalla", bisel=0)
    c.caja("caja_carga", (1.25, 2.1, 1.25), (0, -0.45, 1.2), "acero_claro")
    c.caja("franja", (1.27, 2.12, 0.14), (0, -0.45, 1.0), "ambar", bisel=0)
    c.caja("faro_i", (0.18, 0.04, 0.1), (-0.4, 1.62, 0.75), "neon", bisel=0)
    c.caja("faro_d", (0.18, 0.04, 0.1), (0.4, 1.62, 0.75), "neon", bisel=0)
    return c.raiz


def robot_mula(col):
    """T0: carretilla de orugas sin sensores. Plataforma de carga y cara-pantalla."""
    c = Constructor("RobotMula", col)
    cuerpo = c.pivote("cuerpo", (0, 0, 0))
    orugas(c, 0.62, 0.78, 0.24)
    c.caja("chasis", (0.5, 0.7, 0.2), (0, 0, 0.3), "acero_claro", padre=cuerpo)
    c.caja("plataforma", (0.56, 0.42, 0.05), (0, -0.12, 0.43), "madera", bisel=0.01, padre=cuerpo)
    c.caja("cabeza", (0.36, 0.2, 0.26), (0, 0.24, 0.55), "ambar", padre=cuerpo)
    c.caja("pantalla", (0.28, 0.02, 0.18), (0, 0.345, 0.56), "pantalla", bisel=0, padre=cuerpo)
    c.caja("luz_estado", (0.06, 0.06, 0.06), (0.13, 0.25, 0.72), "blanco", bisel=0, padre=cuerpo)
    clave(cuerpo, "location", [(0, (0, 0, 0)), (N * 0.5, (0, 0, 0.015)), (N, (0, 0, 0))], "BEZIER")
    return c.raiz


def robot_explorador(col):
    """T2: el robot del Concepto 1, ahora avanzado. Sensor giratorio, pala y cara-pantalla."""
    c = Constructor("RobotExplorador", col)
    cuerpo = c.pivote("cuerpo", (0, 0, 0))
    orugas(c, 0.7, 0.86, 0.28)
    c.caja("chasis", (0.56, 0.66, 0.32), (0, 0, 0.42), "acero", padre=cuerpo)
    c.caja("tolva", (0.46, 0.3, 0.16), (0, -0.2, 0.66), "acero_claro", padre=cuerpo)
    c.caja("cabeza", (0.42, 0.28, 0.3), (0, 0.16, 0.76), "neon", padre=cuerpo)
    c.caja("carcasa_cabeza", (0.44, 0.26, 0.31), (0, 0.15, 0.76), "acero_claro", padre=cuerpo)
    c.caja("pantalla", (0.32, 0.02, 0.2), (0, 0.29, 0.77), "pantalla", bisel=0, padre=cuerpo)
    c.caja("luz_estado", (0.06, 0.06, 0.06), (0.16, 0.12, 0.95), "blanco", bisel=0, padre=cuerpo)
    c.caja("pala", (0.5, 0.1, 0.14), (0, 0.5, 0.24), "ambar", padre=cuerpo)
    mastil = c.pivote("sensor", (-0.18, -0.2, 0.9), padre=cuerpo)
    c.hijo_de(c.cilindro("mastil", 0.025, 0.36, (-0.18, -0.2, 0.92), "acero_claro", verts=8), mastil)
    c.hijo_de(c.caja("radar", (0.2, 0.05, 0.08), (-0.18, -0.2, 1.12), "neon", bisel=0.01), mastil)
    clave(mastil, "rotation_euler", [(0, (0, 0, 0)), (N, (0, 0, math.radians(360)))])
    clave(cuerpo, "location", [(0, (0, 0, 0)), (N * 0.5, (0, 0, 0.012)), (N, (0, 0, 0))], "BEZIER")
    return c.raiz


def caja_material(col):
    """Caja de proveedor (cobre o silicio). Godot cambia el color de la franja."""
    c = Constructor("CajaMaterial", col)
    c.caja("caja", (0.42, 0.42, 0.32), (0, 0, 0.16), "madera", bisel=0.02)
    c.caja("franja", (0.44, 0.1, 0.33), (0, 0, 0.16), "ambar", bisel=0)
    return c.raiz


MODELOS = {
    "fundidora": fundidora,
    "ensambladora": ensambladora,
    "fabrica_robots": fabrica_robots,
    "recepcion": recepcion,
    "despacho": despacho,
    "servidor": servidor,
    "camion": camion,
    "robot_mula": robot_mula,
    "robot_explorador": robot_explorador,
    "caja_material": caja_material,
}


def exportar(ruta, escena):
    escena.frame_start, escena.frame_end = 0, N
    escena.render.fps = 24
    hay_anim = any(o.animation_data for o in escena.objects)
    bpy.ops.export_scene.gltf(
        filepath=ruta,
        export_format="GLB",
        export_yup=True,
        export_animations=hay_anim,
        export_animation_mode="SCENE",
        export_apply=True,
    )


def vista_previa():
    """Construye todos los modelos en fila dentro de una escena nueva, para mirarlos."""
    escena = bpy.data.scenes.get("Codemageddon") or bpy.data.scenes.new("Codemageddon")
    bpy.context.window.scene = escena
    for o in list(escena.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    _mats.clear()
    x = 0.0
    for nombre, fn in MODELOS.items():
        raiz = fn(escena.collection)
        raiz.location.x = x
        x += 5.0
    escena.frame_start, escena.frame_end = 0, N
    return escena


if __name__ == "__main__" and bpy.app.background:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    destino = argv[0] if argv else "."
    os.makedirs(destino, exist_ok=True)
    for nombre, fn in MODELOS.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        _mats.clear()
        escena = bpy.context.scene
        escena.name = "ciclo"
        fn(escena.collection)
        ruta = os.path.join(destino, nombre + ".glb")
        exportar(ruta, escena)
        print("EXPORTADO", ruta)
