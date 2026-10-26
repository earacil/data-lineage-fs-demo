# Guion de demo — plantilla genérica (1 hora)

> Estado: bloques 1, 2, 3 y 5 con los comandos exactos. **El bloque Bloom está pendiente de redactar:** la perspectiva ya existe en Aura y se rellenará con `bloom/BLOOM_DEMO_FLOW.md` cuando se exporte. Estructura y timing reutilizables para cualquier cliente de Financial Services.
>
> ⚠️ Todo el Cypher referenciado **no se ha ejecutado contra una instancia Neo4j real** — ensayar entera en el entorno de la demo (Aura/Desktop + GDS) antes de usarla.

| Bloque | Duración | Contenido | Ángulo |
|---|---|---|---|
| Intro | 5 min | Por qué un grafo para lineage en banca (gobierno de datos, trazabilidad de informes regulatorios hasta su origen) | — |
| Ingesta en vivo | 10 min | Cargar 2-3 proyectos ETL en directo; mostrar cómo un `EtlJob` nuevo se autoconecta a columnas ya existentes de otro proyecto, sin integración manual | 1 |
| Impacto ascendente/descendente | 15 min | Trazado de linaje completo y "¿qué rompe si cambia esta columna/este sistema?"; incluir un caso de `CASE WHEN` multi-origen ya resuelto en el dataset | 2 |
| Zonas muertas con GDS | 10 min | Proyección GDS + BFS reverso desde `FinalConsumer`; candidatos a retirada de `EtlJob` con coste de cómputo asociado | 3 |
| Bloom | 10 min | Guion en escenas sobre la perspectiva ya preparada (ver `bloom/BLOOM_DEMO_FLOW.md`) | 4 |
| Productivización + cierre | 8 min | Buenas prácticas de ingesta idempotente, propiedad por job, informe periódico de zonas muertas | 5 |
| Q&A | 2 min | — | — |

## Preparación (antes de la sesión)

1. Instancia AuraDB con **Aura Graph Analytics activado** (ver `AURA_SETUP.md` §1). Subir el repo a GitHub (público) y fijar en el Query tool los parámetros de `AURA_SETUP.md` §2: `baseUrl` (apuntando a una **etiqueta/SHA**, no a `main`) y `sessionName`, `sessionMemory`, `sessionTtl`. Comprobarlos con `:params` (se pierden al refrescar).
2. **Pre-cargar el segmento 0 y los proyectos P1, P2, P4 y P5** de `data/00_load_live.cypher`, dejando **P3** (reporting regulatorio) para cargarlo en directo, más el proyecto nuevo del bloque B de `01_ingesta.cypher`. Si prefieres una demo más corta, pre-cargar los 5 proyectos y usar sólo el bloque B.
3. Verificar con el último bloque del script los recuentos esperados (81 / 7 / 13 / 6 / 7 nodos; 66 / 81 / 113 / 25 / 14 aristas) **una vez cargados los 5 proyectos** (ensayar la carga completa antes en una instancia aparte).
4. Ejecutar una vez entero `queries/01_ingesta.cypher` bloque E (reset) para dejar el grafo sin el proyecto del bloque B.

## Escaleta con comandos

### 1 · Ingesta en vivo (10 min) — `data/00_load_live.cypher`, `queries/01_ingesta.cypher`

| Min | Acción | Qué decir |
|---|---|---|
| 0-2 | Mostrar las restricciones y el segmento 0 (sistemas, propietarios, informes) | "Primero el contexto de negocio: 7 sistemas origen, 6 informes finales." |
| 2-5 | Ejecutar el segmento **P3** (reporting regulatorio) | "Este lote no trae ninguna columna de riesgo y aun así sus transformaciones leen `RISK_MART.*`: el `MERGE` por `fqn` las encuentra ya cargadas." Mostrar en Browser el camino P3 → P2 → P1 |
| 5-8 | `01_ingesta.cypher`: **B.1** (el grafo ANTES, en vista de grafo) → **B.2–B.4** (ingesta del proyecto nuevo `BUILD_RWA_DENSITY`) → **B.5** (qué se ha cargado) → **C.1b** (cómo se engancha) → **C.2b** (por dónde fluye el dato) → **C.3b / C.3c** (mapa completo de jobs) | "Cero aristas escritas a mano entre proyectos: el job nuevo se engancha a columnas que ya existían y su dato traza hasta el Core Banking y el motor de riesgo SAS." |
| 8-10 | Repetir bloque B y bloque **A** | "Idempotente: mismos números. Eso es lo que permite cargar cada noche sin miedo." |

### 2 · Impacto (15 min) — `queries/02_impacto.cypher`

| Min | Acción | Qué decir |
|---|---|---|
| 0-4 | **1.a / 1.b** sobre `REG_MART.SOLVENCY.TOTAL_RWA` | "De dónde sale una cifra de solvencia: 2 sistemas, 5 jobs, 3 proyectos." |
| 4-8 | **2.a / 2.b** sobre `CORE.LOAN.DRAWN_AMOUNT` | "Si cambia esta columna, estos informes se ven afectados." Señalar la rama muerta que también cuelga de ella (gancho al bloque 3) |
| 8-10 | **4.a** (si cae el Core) y **4.c** (falla `CALC_EXPOSURE`, con "a quién llamo") | "Blast radius a nivel de sistema y de job." |
| 10-12 | **5.a** (`CASE WHEN` de 3 orígenes) y **5.b** (CONSTANT/TABLE) | "Lógica SQL abstracta que un modelo relacional representa mal." |
| 12-15 | **6.a / 6.b** (centralidad) y **7.a** (trazabilidad BCBS 239 por informe) | "Dónde duele más que algo falle y cuántos orígenes tiene cada informe regulatorio." |

### 3 · Zonas muertas con GDS (10 min) — `queries/03_zonas_muertas_gds.cypher`

| Min | Acción | Qué decir |
|---|---|---|
| 0-2 | Definir "zona muerta" (sin ruta hasta un `FinalConsumer`) | "No es un flag: se calcula con el grafo." |
| 2-5 | Parte **A** (A.1 proyección, A.2 BFS en reversa) | Esperado: 8 columnas muertas |
| 5-6 | Parte **B** (WCC) | "Un componente conexo sólo ve 5 de las 8: la rama que cuelga de un dato vivo no se ve así." |
| 6-8 | **C.2** (puntos de bifurcación) y **C.4/C.5** (jobs muertos y ahorro) | "127.000 € al año en jobs que nadie consume, uno de ellos deprecado y sin propietario." |
| 8-10 | **C.6** y **C.7** | "Una columna sobra en un job que sí se queda; un sistema entero al 0 %." |
| −5 | **Antes del bloque:** parte **0** (crear la sesión AGA y `:param sessionId`) — tarda en pasar a `Ready` | — |
| 10 | Parte **Z**: borrar la sesión al terminar (deja de facturar) | — |
| — | **Plan B si GDS falla:** ir directamente a la parte **C** (mismo resultado en Cypher puro) | — |

### 4 · Bloom (10 min) — *perspectiva creada en Aura; guion pendiente*

Rellenar cuando se exporte la perspectiva a `bloom/` y existan `bloom/BLOOM_GUIDE.md` y `bloom/BLOOM_DEMO_FLOW.md`.

### 5 · Productivización + cierre (8 min) — `queries/04_productivizacion.md`

| Min | Acción | Qué decir |
|---|---|---|
| 0-3 | Tabla "ingesta idempotente" y mark & sweep por `scenario` | "El scanner es desechable; el grafo, no." |
| 3-5 | Tabla de **capas técnica vs. semántica** | "El linaje se calcula; el consumo final y los propietarios los pone el negocio." |
| 5-7 | Query de ejemplo 2 (KPIs del informe semanal) y 3 (brecha de accountability) | "Informe semanal con tendencia, sin borrado automático." |
| 7-8 | Cierre: BCBS 239 — cada cifra reportada traza hasta su origen y tiene responsable | — |

## Notas de preparación

- Todo debe probarse antes en un entorno real (Aura/Desktop + GDS) — nada de lo construido en este proyecto se ha ejecutado contra una base de datos.
- El dataset es sintético; dejarlo explícito al abrir la demo (ver `data-model/NOTAS_DISENO.md`).
- Dejar 1-2 minutos de margen entre bloques — la ingesta en vivo es la parte con más riesgo de imprevistos. Plan B de ingesta: tener todo pre-cargado y ejecutar sólo el bloque B de `01_ingesta.cypher` (pocas líneas, sin dependencia de URLs de CSV).
- Antes de la demo, revisar sesiones AGA olvidadas de un ensayo (`CALL gds.session.list()`) y borrarlas (`gds.session.delete`): se facturan por minuto (mínimo 10 min) hasta que expiran. Ensayar con el mismo plan de Aura que se usará en la demo: tamaño máximo, TTL y nº de sesiones varían por plan.
- Al preparar una sesión para un cliente concreto, anotar fecha/asistentes/ajustes específicos en el `Context.md` de ese cliente dentro de `Customers/`, no en este fichero.
