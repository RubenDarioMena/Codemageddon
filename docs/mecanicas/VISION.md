# Visión de mecánicas

Documento vivo: describe cómo **deben** funcionar hoy las mecánicas de código de Codemageddon, tanto en los bancos HTML como en el juego final. Se reescribe en cada iteración para que siempre se lea completo. La historia de cada decisión, con el feedback que la originó y los datos, está en el [DIARIO](DIARIO.md).

Última actualización: 2026-10-27 (bancos 01, 02 y 03).

## 1. Principios

- **El jugador aprende JavaScript y SQL programando una fábrica.** Cada mecánica hace *necesario* un concepto (bucle, condición, `??`, variable de estado), no solo posible.
- **Profundidad antes que complejidad.** Pocas reglas que se combinan; se mide en decisiones con sentido (ver la skill `deep-game-systems`).
- **Toda regla se ve.** El fallo físico es visible y tiene nombre (`viaje_vacio`, `derrame`, `atascado`); la línea que corre se ilumina; los valores devueltos se registran.
- **Determinismo.** Paso fijo de simulación; el reloj de juego se congela mientras el código piensa; el azar viene de una semilla visible. El mismo programa con la misma semilla da el mismo resultado.
- **Un banco HTML prueba una pregunta.** Lo que necesita economía, ciudad o historia se anota en «Fuera de los HTML» (§10).

## 2. Máquinas como objetos del código

### 2.1 Identidad

| Dónde | Forma | Ejemplo |
| --- | --- | --- |
| En pantalla | ID con guion | `LAU-01`, `FUN` |
| Variable en el código | ID con guion bajo | `LAU_01` |
| Lugar como argumento (API de robots) | texto | `yo.entregar("FUN")` |
| Dentro de su propio programa | sin prefijo, o `yo.` | `failureRate`, `stopFire()` |

En el juego final cada máquina será además un objeto (`maquinas["FUN-01"]` ya existe en Concepto2). Unificar textos y variables está abierto (§9).

### 2.2 Inspector

Al seleccionar una máquina, un robot o un enemigo aparece un panel con tres zonas, siempre en este orden:

1. **Para tu código** (columna izquierda): lo que más se escribe. Nombre o variable; contenido o lista (lo que guarda, lo que espera en la entrada); funciones, con su firma y lo que devuelven.
2. **Datos** (columna derecha): lo que se lee para decidir. Entrada y salida; ratio de conversión; velocidad por ciclo; propiedades vivas (`failureRate`, `mode`, `jammed`…); sensores y alcances.
3. **Métricas** (debajo, aparte): cómo le va a esa máquina en este intento. No se usan en el código; miden la fábrica (§5).

Ejemplos de contenido:

| Máquina | Para tu código | Datos |
| --- | --- | --- |
| Fundidora `FUN` | `"FUN"`; entrada `"cobre"` = 0 de 3 huecos; `yo.entregar("FUN")`; `yo.cuantos("FUN", "cobre")` | input cobre · output placas de cobre · 2 placas por cada 1 cobre · 3,0 s por ciclo · estado |
| Bodega `ENT-1` | `"ENT-1"`; `"cobre"` = 3, `"silicio"` = 3; `yo.recoger("ENT-1", material)`; `yo.cuantos(...)` | bodega · acepta todo |
| Lanzamisiles `LAU-01` | `LAU_01`; `missiles` = 8; `autoTarget(tipo, sensor)`, `regularShoot(lugar)`, `burstFire(lugar)`, `stopFire()` | entrada misiles · salida lanzamientos · `fireRate` · `failureRate` (con barra) · `mode` · `jammed` · `target` · `sensors` · alcances · tipos de enemigo |
| Sensor `VIB-01` | `VIB_01`; `VIB_01.detect(tipo)`; `VIB_01.count` | vibración del suelo · alcance · solo enemigos de suelo · sin predicción |
| Robot `R1` | `yo`; `yo.recoger`, `yo.entregar`, `yo.esperar`, `yo.cuantos` | velocidad · duración de cada orden · carga · posición |
| Enemigo `D3` | `"drone"`; sensores que lo ven | vida · velocidad · altura · posición |

Las funciones de otra máquina que solo puede dar su propio programa se muestran tachadas, con la explicación.

### 2.3 Colores por tipo

| Tipo | Ejemplo | Uso |
| --- | --- | --- |
| Máquina o variable | `LAU_01`, `yo` | azul |
| Función | `autoTarget()` | violeta |
| Propiedad | `failureRate` | turquesa |
| Número | `0.02` | magenta |
| Texto | `"thermal"` | verde |

Los mismos colores se usan en el editor (resaltado del 03), en la ayuda y en la leyenda del inspector. Hay variantes para modo claro y oscuro.

### 2.4 Insertar en el código

- **Un clic** arma la palabra y dice qué hará; **doble clic** (o doble toque) la usa. En escritorio también se puede **arrastrar** al editor.
- **En JavaScript** se inserta en el cursor. Las funciones llegan con huecos comentados, `autoTarget(/* tipo de enemigo */, /* sensor */) // → posición {x, y, z} o null`, y el primer hueco queda seleccionado. El siguiente doble clic en un valor (`"drone"`) lo rellena y salta al siguiente hueco. El comentario de retorno solo se añade si no hay nada más en la línea. Si se ejecuta con un hueco sin rellenar, el aviso dice la línea.
- **En bloques y pseudocódigo** rellena el valor abierto del bloque si es compatible; si no, añade el bloque que corresponde (`yo.entregar("FUN")` → «entrega en FUN»; `yo.cuantos(...)` → «si» o «mientras» con esa condición, según lo que permita el reto).
- Los huecos usan `/* … */` porque `//` dentro de una llamada la rompe.

## 3. Escribir programas

### 3.1 Tres vistas (02)

Bloques, pseudocódigo y JavaScript son pieles del mismo árbol. El texto vuelve a bloques si solo usa lo que los bloques conocen; si no, el aviso dice la línea. El pseudocódigo está en inglés por defecto, con opción en español.

### 3.2 Edición directa

- **Arrastrar y soltar**: ladrillos desde la paleta hasta cualquier punto del programa, bloques entre listas y dentro de contenedores. Soltar sobre la paleta borra. Una línea azul marca dónde caerá. Ratón: arrastrar más de 6 px. Táctil: mantener pulsado 0,28 s; los ladrillos de la paleta se arrastran hacia arriba o abajo. Tocar sigue funcionando como antes.
- **Código de partida comentado**: en JavaScript, todo programa de partida llega comentado con una cabecera `/* … */` que explica cómo usarlo. En bloques sigue activo. Si se vuelve a bloques sin tocar el texto, se recuperan los bloques de partida.
- **Comentar y descomentar**: `Ctrl+/` (`⌘/`) o el botón «// comentar», sobre las líneas elegidas. Los bloques `/* … */` no se tocan.
- **Deshacer**: las inserciones usan el historial del navegador (`Ctrl+Z`).

### 3.3 Quién ejecuta y con qué alcance

- **Un programa por robot o máquina**, cada uno en su propio worker. En su programa, lo suyo va sin prefijo (o con `yo.`); otra máquina se nombra por su variable.
- **Leer** cualquier máquina está permitido; **ordenar** solo a la propia. Así varios programas no se pisan y el resultado no depende del orden en que llegan los mensajes.
- **Copiar a los demás**: un botón copia el programa de una máquina a sus hermanas.

### 3.4 Tiempo

- Las órdenes que mueven el mundo físico de un robot (`yo.recoger`) son `await` y duran tiempo de juego.
- Los sensores (`yo.cuantos`, `autoTarget`, `VIB_01.detect`) y las propiedades no gastan tiempo.
- Las órdenes de modo de una máquina (`regularShoot`, `stopFire`) son instantáneas y devuelven un texto. Solo `await esperar(s)` deja pasar tiempo.
- Con varios programas, el reloj avanza solo cuando todos esperan (*lockstep*). Un bucle sin espera se detiene con una explicación: por vigilancia de 2,5 s o por superar 4000 órdenes seguidas.

## 4. Consola y avisos

- `console.log`, `info`, `warn` y `error` (y `log()`) escriben en la consola con la máquina y la línea.
- Cada tipo se configura: **globo** que sale de la máquina, **pantalla** (aviso grande arriba del campo con enlace a la máquina) o **solo consola**. Valores por defecto: log, info y warn en globo; error en pantalla.
- **Referencia a la máquina**: el nombre en consola y en avisos es un enlace que la selecciona y centra la cámara.
- Los avisos repetidos se agrupan («×5») y caducan; como máximo 3 a la vez.
- Los hechos físicos (atasco, reparado, sin misiles, brecha) usan el mismo canal con estilo de sistema.

## 5. Métricas y optimización

- **Métricas por máquina**, separadas del código: productos, ciclos, ocupación, tiempo medio por pieza, derrames (logística); lanzados, impactos, precisión, derribos, atascos, tiempo en ráfaga, fallo máximo, gasto (defensa).
- **Ficha de producto**: cada pieza terminada guarda cuánto tardó cada tramo, por ejemplo «viaje R1 2,1 s → espera 0,5 s → proceso 3,0 s = 5,6 s». En el juego final, una fila por pieza y por tramo en la base de datos.
- **Número a optimizar**: cada reto tiene uno, con récord personal y diferencia al terminar. Logística: tiempo de juego. Defensa: ₵ por derribo (₵ 10 por misil y ₵ 40 por reparación).
- **Consecuencias** (juego final): dinero e investigación más rápida; preferencia del público por el producto; percepción del gobierno propio y del rival; relación con IA o compañías rivales de las dos naciones. Las difusas usan modelos probabilísticos como el de la ciudad.

## 6. Mecánicas

### 6.1 Logística (bancos 01 y 02)

| Verbo | Duración | Devuelve |
| --- | --- | --- |
| `await yo.recoger(origen, material)` | camino a 4 casillas/s + 0,5 s | `"ok"`, `"viaje_vacio"`, `"manos_llenas"` |
| `await yo.entregar(destino)` | camino + 0,5 s | `"ok"`, `"rechazado"`, `"derrame"`, `"manos_vacias"` |
| `await yo.esperar(segundos)` | esos segundos | `"ok"` |
| `await yo.cuantos(lugar, material)` | 0 s (sensor) | número |

Máquinas: una pieza a la vez, entrada con huecos limitados y salida con ratio (fundidora 2 placas por cobre; ensambladora 1 oblea por silicio).

### 6.2 Defensa (banco 03)

**Lanzamisiles `LAU`**

| Función o propiedad | Qué hace |
| --- | --- |
| `autoTarget(tipo, sensor)` | Elige el enemigo de ese tipo más cercano a la base que vea ese sensor. Devuelve dónde estará cuando llegue el próximo misil, `{x, y, z, id, tipo}`, o `null`. Ignora a los que ya tienen misiles suficientes en el aire. No gasta tiempo. |
| `regularShoot(lugar)` | Modo regular: 1 misil/s a ese lugar hasta otra orden. Con `null`, deja de disparar. Devuelve `"ok"`, `"sin_objetivo"`, `"sin_misiles"` o `"atascado"`. |
| `burstFire(lugar)` | Ráfaga: 2,2 misiles/s. Sube `failureRate`. |
| `stopFire()` | Deja de disparar. Enfría el doble que el modo regular. |
| `failureRate` | Probabilidad media de fallo por disparo: 0,02 de base; al entrar en ráfaga 0,04, más 0,06 por segundo; fuera de ráfaga baja 0,10/s (0,20/s parado). |
| `missiles`, `mode`, `jammed`, `fireRate`, `target`, `sensors` | Cargador, modo (`"idle"`, `"regular"` o `"burst"`), atasco, cadencia, a dónde apunta y sensores montados. |

- **Fallo**: cada disparo suma su `failureRate` a un riesgo acumulado; al pasar un umbral aleatorio entre 0,75 y 1,25, el lanzador se atasca y pierde ese misil. La reparación la hace un robot reparador: viaja hasta el lanzador y tarda 1,5 s + 12 s × `failureRate` al fallar.
- **Suministro**: cada lanzador recibe misiles del depósito a un ritmo fijo hasta llenar su cargador. Por eso la ráfaga se sostiene solo con un flujo constante de misiles y suficientes reparadores.
- **Misil**: vuela a 14 casillas/s en arco y estalla en el lugar pedido, **a su altura**. Daña lo que esté a 1,3 m o menos en 3D. Un lugar construido a mano sin `z` estalla en el suelo.

**Sensores**

| Sensor | Dónde | Alcance (niebla) | Ve |
| --- | --- | --- | --- |
| `"visual"` (cámara) | montado | 14 (5,5) | todo |
| `"thermal"` | montado | 11 (7) | todo menos drones fríos |
| `VIB_01.detect(tipo)` | red | propio de cada sensor (8) | solo enemigos de suelo; posición actual, sin predicción |

**Enemigos**

| Tipo | Vida | Velocidad | Altura |
| --- | --- | --- | --- |
| `"crawler"` (oruga) | 2 (blindada: 3) | 0,8 casillas/s | suelo |
| `"drone"` | 1 | 2,0 (enjambre: 2,4) | 2,5 m |
| `"stealth"` (dron frío) | 1 | 1,5 | 2,0 m |

**Retos y lo que hacen necesario**: 1, bucle con espera; 2, prioridad con `??` o `if/else`; 3, elegir sensor por enemigo y usar la red; 4, leer `failureRate` para alternar modos (gana la histéresis con `let enfriando`); 5, un programa por máquina y leer el estado de la otra.

**Vista**: campo de 32 × 18 casillas en 3D (la altura se ve) o en plano (la altura se codifica con sombra desplazada, línea y «↑2.5»).

## 7. Retos propios

Cada banco tiene un reto o escenario propio:
- El jugador escribe **título, enunciado y pista**.
- Define **metas** (llegar a, vaciar, brechas máximas, derribos mínimos, atascos máximos) y **límites** (tiempo, derrames, viajes vacíos).
- Ajusta el **mapa** o las **oleadas**, y los bloques disponibles.
- Cualquier reto fijo se puede usar como base.
- Se exporta e importa como **JSON**, para compartir enunciados.

En el juego final, este editor sirve para los retos de la comunidad y para que el diseño pruebe variantes sin tocar código.

## 8. Telemetría

Cada intento se guarda en local y se copia como JSON desde la pestaña Registro. Campos comunes:
- banco, reto, intento, semilla o cantidad oculta;
- resultado, motivo, mensaje y línea del error;
- tiempo de juego, líneas de código, el código;
- usos por función, resultados por tipo, consolas por nivel;
- inserciones por doble clic, arrastre y atajo.

Campos propios:
- **02**: vista (bloques, pseudo o JS), idioma, número de bloques, derrames, viajes vacíos.
- **03**: vista (3D o plano), brechas, derribos, misiles, precisión, atascos con su `failureRate` y su tiempo de reparación, coste por derribo y estadística por lanzador.

## 9. Decisiones abiertas

- Idioma de la API: inglés (como el ejemplo del lanzador) o español (como `yo.recoger`).
- Prefijo en el programa de una máquina: suelto o siempre `yo.`.
- Nombres de máquina: textos (`"FUN"`) o variables (`FUN_01`), o los dos.
- Si conviene mostrar el desgaste acumulado además de `failureRate`.
- Si el 3D compensa su coste en móvil (decidir con la telemetría de `vista`).
- Un ladrillo de «propiedad» para usar `failureRate` y similares en bloques.

## 10. Fuera de los HTML (para el juego final)

- Configuración global de la consola en Opciones y bitácora revisable de avisos.
- Fichas de producto y número a optimizar en la base de datos, consultables con SQL.
- Consecuencias difusas de optimizar: público, gobiernos, IA y compañías rivales.
- Misiles producidos por la propia fábrica; reparadores como robots con programa propio; red de sensores como edificios con tabla en la base.
- Modo historia: dos naciones, gobiernos y compañías rivales como fuentes de enemigos y de presión.
