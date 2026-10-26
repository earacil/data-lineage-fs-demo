# Contexto para IA — léeme primero

> Si eres una IA (u otra persona) que retoma este proyecto sin haber visto la conversación original, este documento te da todo el contexto operativo que necesitas. Los demás `.md` del proyecto son la fuente de verdad del contenido; este fichero es el mapa y las reglas para moverte entre ellos.

## Misión

Construir una **demo genérica y reutilizable de data lineage sobre Neo4j para Financial Services**: un dataset sintético + queries Cypher/GDS + una perspectiva de Bloom que, juntos, respondan a 5 preguntas de negocio típicas de un cliente bancario (ver "Los 5 ángulos" en `README.md`). La demo debe poder presentarse a cualquier cliente del sector sin modificaciones salvo una capa de personalización deliberada.

## Restricciones duras (no negociables salvo que la persona lo pida explícitamente)

1. **Cero referencias a clientes concretos.** Ningún nombre de empresa, persona, fecha de reunión o captura de pantalla de un cliente real debe aparecer en ningún fichero de este proyecto. Si se detecta alguna, es un error a corregir, no una decisión de diseño.
2. **Idioma**: todos los identificadores del modelo de datos (labels de nodo, tipos de relación, nombres de propiedad) van **en inglés**. La prosa de los `.md` (explicaciones, narrativa, comentarios) va **en español**, salvo que la persona indique lo contrario.
3. **`Column` y `TRANSFORMS_TO` no se modifican.** Están inspirados en un patrón real de linaje visto en un cliente bancario (detalle en `data-model/NOTAS_DISENO.md`) y son el ancla de credibilidad de toda la demo ("esto ya lo hemos visto funcionar"). Cualquier cambio en sus propiedades o semántica rompe esa credibilidad.
4. **Validado en Aura por el autor:** `data/00_load_live.cypher` (24-oct-2026, recuentos correctos) y `queries/01_ingesta.cypher` (26-oct-2026). `queries/02_impacto.cypher` está validada por el autor (26-oct-2026; 1 y 2 en Bloom, el resto en el dashboard), salvo la sección 4 (casos especiales), que no se usa en la demo y queda como material de apoyo sin probar. **Siguen sin validar:** `queries/03_zonas_muertas_gds.cypher` (incluida la sesión de Aura Graph Analytics y los pasos de `AURA_SETUP.md` que dependen de ella). La validación la hizo la persona, no el agente que generó los ficheros (su entorno no tiene Neo4j ni GDS). `queries/04_productivizacion.md` es una nota de buenas prácticas, no se ejecuta de punta a punta. Todo Cypher **nuevo o modificado** debe tratarse como "a validar" hasta que se pruebe en Aura o Desktop real.
5. **El dataset es y debe seguir siendo sintético.** No rellenar `data/` con datos reales de ningún cliente, aunque se tenga acceso a ellos para otra tarea.

## Estado exacto del proyecto ahora mismo

| Fichero/carpeta | Estado | Contenido |
|---|---|---|
| `README.md` | ✅ completo | Qué es, por qué un grafo, los 5 ángulos, estructura, estado |
| `data-model/SCHEMA.md` | ✅ completo | Los 6 tipos de nodo y 5 tipos de relación, con propiedades en inglés |
| `data-model/NOTAS_DISENO.md` | ✅ completo | Por qué cada decisión de modelado, qué es real vs sintético, fuentes |
| `RUNBOOK_DEMO.md` | 🟡 parcial | Estructura y timing de 1h + comandos exactos de los bloques 1, 2, 3 y 5; el bloque Bloom se rellenará al exportar la perspectiva |
| `data/` | ✅ completo; **`00_load_live.cypher` validado en Aura el 24-oct-2026** (recuentos 81/7/13/6/7 y 66/81/113/25/14 correctos) | 10 CSV, `00_load_live.cypher` (segmentos P0–P5), `generate_dataset.py` (fuente de verdad) y `validate_dataset.py` (consistencia OK) |
| `queries/` | ✅ completo; `01` validada en Aura (26-oct-2026); `02` validada (salvo la sección 4, fuera de la demo); **`03` pendiente de validar** | `01_ingesta.cypher`, `02_impacto.cypher`, `03_zonas_muertas_gds.cypher`, `04_productivizacion.md` |
| `AURA_SETUP.md` | ✅ completo; `baseUrl` validado, **flujo de sesión AGA pendiente de validar** (depende de `03`) | Requisitos de Aura, parámetros del Query tool (`baseUrl`, `sessionName`, `sessionMemory`, `sessionTtl`, `sessionId`), flujo de sesión AGA, problemas típicos |
| `dashboard/` | ✅ dashboard de Aura «Data Lineage Impact» creado, verificado y exportado (`data_lineage_fs_impact_dashboard.json`, 26-oct-2026) | 5 tarjetas + 1 filtro (`$source_system`), alimentado por las queries `▣` de `02_impacto.cypher` |
| `bloom/` | 🟡 perspectiva creada y probada en Aura (según el autor); **pendiente exportar** el JSON al repo | Falta el JSON de perspectiva (se descargará de Bloom al terminar las pruebas), la guía y el guion de escenas |

## Próximos pasos, en orden, con criterio de aceptación

### 1. Dataset sintético (`data/`) — ✅ HECHO
Incluye (todo verificado por `data/validate_dataset.py`), como mínimo, para que las queries de los pasos siguientes tengan algo real que mostrar:
- Al menos 2 proyectos ETL (`EtlJob`) distintos cuya salida de uno sea entrada del otro (auto-conexión entre proyectos vía un `fqn` de `Column` compartido) — es el argumento de venta más fuerte del modelo.
- Al menos un caso de `kind = "CONSTANT"` (valor fijo sin columna de origen) y uno de `kind = "TABLE"` (referencia a tabla completa, ej. `COUNT(*)`).
- Al menos un caso de fórmula multi-origen (`CASE WHEN` con 2-3 columnas de entrada → misma `transformation_expression` en N relaciones `TRANSFORMS_TO`).
- Al menos 2-3 "zonas muertas" deliberadas — y al menos una debe ser una **rama que se bifurca de un dato vivo** (no solo un nodo totalmente aislado), para demostrar que la detección funciona a nivel de ruta, no solo de componente conexo.
- Consistencia estricta: todo valor de `TRANSFORMS_TO.scenario` debe tener un `EtlJob.name` correspondiente; todo `Column` debe colgar de al menos un `SourceSystem` vía `HOSTS`.
- Verificar con un script (Python u otro) que no queden referencias huérfanas antes de dar el dataset por bueno.

### 2. Queries (`queries/`) — ✅ HECHO; `01` validada en Aura, `02` y `03` pendientes
- `01_ingesta.cypher`: patrón `MERGE` idempotente por `fqn`/`id`, pensado para ejecutarse en vivo y demostrar la auto-conexión del punto anterior.
- `02_impacto.cypher`: camino variable descendente por `fqn` (en forma de paths, para Bloom), camino completo sistema → informe y blast radius por sistema (el linaje ascendente se enseña en `01_ingesta.cypher`, C.2/C.2b), más una sección de criticidad por alcance (qué columnas/jobs afectan a más informes; conteo de caminos, no centralidad de grafo).
- `03_zonas_muertas_gds.cypher`: proyección GDS + BFS en reversa desde `FinalConsumer`, **más un fallback en Cypher puro** (`NOT EXISTS` de alcanzabilidad) por si GDS falla o no está disponible en el entorno de la demo. Incluye además la parte D (extra): centralidad de verdad con PageRank y betweenness sobre la proyección ya creada, para localizar cuellos de botella.
- `04_productivizacion.md`: no es Cypher ejecutable — son buenas prácticas (ingesta idempotente, separación de la capa semántica, informe periódico de zonas muertas) con 1-2 queries de ejemplo.

### 3. Bloom (`bloom/`) — 🟡 perspectiva creada en Aura; pendiente exportarla al repo
- El autor descargará el fichero de perspectiva de Bloom al final de las pruebas y lo guardará como `bloom/data_lineage_fs_perspective.json`. Después: redactar `BLOOM_GUIDE.md` y `BLOOM_DEMO_FLOW.md` a partir de lo que realmente se configuró (no inventar estilos ni scene actions sin ver el JSON).
- Solo tiene sentido después del dataset y las queries, porque las scene actions y search phrases dependen de los valores reales del dataset.
- Seguir el formato de "guion en actos con talking points entre comillas" descrito en `data-model/NOTAS_DISENO.md` (inspirado en `BLOOM_DEMO_FLOW.md` del repo de referencia).

### 4. Cerrar `RUNBOOK_DEMO.md` — 🟡 parcial (falta el bloque Bloom)
- Una vez existan queries y escenas concretas, sustituir las descripciones genéricas de cada bloque por los comandos/acciones exactas a ejecutar.

## Mapa de ficheros

```
data-lineage-fs-demo/
├── CONTEXTO_IA.md          ← este fichero (léelo primero)
├── README.md               ← punto de entrada para humanos: qué es y por qué
├── RUNBOOK_DEMO.md          ← guion de la demo de 1h
├── AURA_SETUP.md            ← la demo se hace en Aura: `baseUrl` = GitHub raw, y parámetros de Aura Graph Analytics (GDS serverless)
├── .gitignore               ← NO añadir reglas amplias (`*.csv`, `*.json`): romperían la carga desde GitHub y la perspectiva de Bloom
├── dashboard/
│   └── data_lineage_fs_impact_dashboard.json     ← export del dashboard de Aura (5 tarjetas + filtro); ver las marcas `▣` de `queries/02_impacto.cypher`
├── data-model/
│   ├── SCHEMA.md            ← fuente de verdad del modelo de datos
│   └── NOTAS_DISENO.md      ← por qué el modelo es así, fuentes, qué es sintético
├── data/
│   ├── README.md            ← qué contiene el dataset, qué casos cubre, cómo cargarlo
│   ├── *.csv                ← 10 CSV (nodos y relaciones); columna auxiliar `load_batch` NO va al grafo
│   ├── 00_load_live.cypher  ← LOAD CSV segmentado por proyecto (P1..P5)
│   ├── generate_dataset.py  ← fuente de verdad: editar AQUÍ y regenerar los CSV
│   └── validate_dataset.py  ← integridad referencial + criterios de aceptación
├── queries/
│   ├── README.md
│   ├── 01_ingesta.cypher · 02_impacto.cypher · 03_zonas_muertas_gds.cypher
│   └── 04_productivizacion.md
└── bloom/README.md          ← plan de Bloom (perspectiva creada en Aura, pendiente de exportar)
```

## Fuentes de inspiración (resumen — detalle completo en `data-model/NOTAS_DISENO.md`)

- Repo [`neo4j-data-asset-intelligence-graph`](https://github.com/halftermeyer/neo4j-data-asset-intelligence-graph): de aquí se copia la **estructura** (no el dominio — es un hedge fund, no un banco): README con el problema de negocio primero, `SCHEMA.md` separado, queries organizadas por ángulo de negocio, y un guion de Bloom en "actos".
- Artículo de LinkedIn de Michael Down sobre Neo4j y BCBS 239: de aquí se copia el **framing regulatorio** (por qué un grafo encaja mejor que un modelo relacional para lineage en banca) usado como narrativa de apertura y cierre de la demo.

## Cómo verificar que un cambio no rompe nada

1. `grep -ri` en todo el proyecto por nombres propios de cualquier cliente conocido — debe salir limpio.
2. Si se toca `data-model/SCHEMA.md`, revisar que `RUNBOOK_DEMO.md`, `data/README.md` y `queries/README.md` sigan usando los mismos nombres de nodo/relación — están escritos para mantenerse sincronizados a mano, no hay generación automática.
3. Cualquier Cypher nuevo se marca como no validado hasta que se ejecute en una instancia Neo4j real — decirlo explícitamente en el propio fichero o en el commit/mensaje de entrega.
