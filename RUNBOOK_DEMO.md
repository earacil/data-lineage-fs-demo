# Guion de demo — plantilla genérica (1 hora)

> Estado: bloques 1, 2, 3, 4 y 5 con los comandos exactos. **El bloque Bloom es un borrador** construido sobre la perspectiva exportada (`bloom/`), pendiente de ensayo. Estructura y timing reutilizables para cualquier cliente de Financial Services.
>
> ⚠️ Todo el Cypher referenciado **no se ha ejecutado contra una instancia Neo4j real** — ensayar entera en el entorno de la demo (Aura/Desktop + GDS) antes de usarla.

| Bloque | Duración | Contenido | Ángulo |
|---|---|---|---|
| Intro | 5 min | Por qué un grafo para lineage en banca (gobierno de datos, trazabilidad de informes regulatorios hasta su origen) | — |
| Ingesta en vivo | 10 min | Cargar 2-3 proyectos ETL en directo; mostrar cómo un `EtlJob` nuevo se autoconecta a columnas ya existentes de otro proyecto, sin integración manual | 1 |
| Impacto ascendente/descendente | 15 min | Trazado de linaje completo y "¿qué rompe si cambia esta columna/este sistema?" (sin entrar en el detalle de cómo está modelado el dato sintético) | 2 |
| Zonas muertas con GDS | 10 min | Proyección GDS + BFS reverso desde `FinalConsumer`; candidatos a retirada de `EtlJob` con coste de cómputo asociado | 3 |
| Bloom | 10 min | Guion en escenas sobre la perspectiva ya preparada (ver `bloom/BLOOM_DEMO_FLOW.md`) | 4 |
| Productivización + cierre | 8 min | Buenas prácticas de ingesta idempotente, propiedad por job, informe periódico de zonas muertas | 5 |
| Q&A | 2 min | — | — |

## Preparación (antes de la sesión)

1. Instancia AuraDB con **Aura Graph Analytics activado** (ver `AURA_SETUP.md` §1). Subir el repo a GitHub (público) y fijar en el Query tool el parámetro `baseUrl` de `AURA_SETUP.md` §2 (apuntando a una **etiqueta/SHA**, no a `main`). Comprobarlos con `:params` (se pierden al refrescar).
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
| 0-4 | **1** (una sola query, en grafo/Bloom) sobre `CORE.LOAN.DRAWN_AMOUNT` | "Si cambia esta columna: 3 informes y 4 jobs a revisar, y a quién llamar." Señalar la columna muerta `EXPOSURE_ADJ_LEGACY` (gancho al bloque 3). El linaje ascendente ya se vio en el bloque 1 (C.2b) |
| 4-8 | **2.a** (grafo sistema → informe) y **2.b** (tabla) sobre `Solvency Report` | "De dónde sale un informe regulatorio: qué sistemas y cuántas columnas origen aporta cada uno." |
| 8-10 | **3.a** (si cae el Core) y **3.b** (ranking de sistemas) | "Blast radius a nivel de sistema." |
| 10-15 | **5** (jobs por informes que dependen de ellos) y **6.a** (trazabilidad BCBS 239 por informe) | "Dónde duele más que algo falle y cuántos orígenes tiene cada informe regulatorio." |
| (opcional, 2-3 min) | **Dashboard de Aura** `Data Lineage Impact` (`dashboards/data_lineage_fs_impact_dashboard.json`) con las 5 tarjetas marcadas `▣` en `02_impacto.cypher` (3.b, 3.a con filtro, 5, 6.a, 6.b) | "Lo que acabamos de ver en grafo, resumido en una pantalla." Mejor como cierre del bloque o como material para dejar al cliente que como parte del flujo en vivo |

### 3 · Zonas muertas con GDS (10 min) — `queries/03_zonas_muertas_gds.cypher`

| Min | Acción | Qué decir |
|---|---|---|
| 0-2 | Definir "muerto": un dato que se carga y se paga pero del que no sale ninguna flecha hasta un informe, dashboard o modelo (`FinalConsumer`) | "No es un flag: se calcula con el grafo. Es un candidato a retirada, no una orden." |
| 2-5 | Parte **A**: A.1 proyección (crea la sesión), A.2 BFS por informe, A.3 resumen vivas/muertas, A.5 en grafo | Explicar el BFS ("echar tinta en el informe y ver por dónde se tiñe aguas arriba"). Esperado: 8 columnas muertas |
| 5-8 | **D.1 / D.4 / D.5** (columnas muertas, jobs muertos y ahorro), mejor en el dashboard «Data Lineage Dead Zones» | "127.000 € al año en jobs que nadie consume, uno de ellos deprecado y sin propietario." |
| 8-10 | **D.6** y **D.7** (idem, dashboard «Data Lineage Dead Zones») | "Una columna sobra en un job que sí se queda; un sistema entero al 0 %." |
| +2 (opcional) | Parte **C** (C.1/C.1b PageRank, C.2/C.2b y C.3 betweenness), con la sesión aún viva | "Cypher cuenta hasta dónde llega un dato; el algoritmo dice por dónde pasa todo: CALC_EXPOSURE y CALC_RWA son los cuellos de botella." Aviso: betweenness no distingue vivo de muerto (PROMO_SEGMENT_EXTRACT también puntúa); por eso va después de A. Ejecutarla ANTES de Z |
| 10 | Parte **Z**: borrar las proyecciones (y con ellas la sesión) al terminar: deja de facturar | — |
| — | La parte **B** de `03` (por qué WCC no basta) queda como material de apoyo: no se cuenta, pero sirve si preguntan por qué BFS y no componentes conexos | — |
| — | **Plan B si GDS falla:** ir directamente a la parte **D** (mismo resultado en Cypher puro) | — |

### 4 · Bloom (10 min) — `bloom/BLOOM_DEMO_FLOW.md` *(borrador, por ensayar)*

Perspectiva: `bloom/data_lineage_fs_perspective.json` (6 search phrases con desplegable; estilo por defecto). Bloom ya se ha usado en los bloques 1 y 2; este bloque es un repaso en modo exploración.

| Min | Acción | Qué decir |
|---|---|---|
| 0-2 | Acto 1: `C3a` (y `C3b`) — mapa de dependencias entre jobs | "Ninguna dependencia está declarada: salen de los datos." |
| 2-5 | Acto 2: `1. Column $column impact` con `CORE.LOAN.DRAWN_AMOUNT` (o la columna que elija el público) | "A quién avisar y qué volver a ejecutar, en una pantalla." Señalar `EXPOSURE_ADJ_LEGACY` sin informe |
| 5-8 | Acto 3: `2. Full Path to FinalConsumer $finalConsumer` con `Solvency Report`; `C2` con `REG_MART.CAPITAL.RWA_DENSITY` | "BCBS 239: cada cifra traza hasta su sistema de origen." |
| 8-10 | Acto 4: puente al dashboard «Data Lineage Dead Zones» | "Bloom enseña la estructura; el dashboard cuenta cuánto sobra y cuesta." |

Si el tiempo aprieta, este bloque se puede suprimir y repartir sus 10 minutos entre los bloques 2 y 3.

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
- Antes de la demo, revisar sesiones AGA olvidadas de un ensayo (`CALL gds.session.list()`) y borrarlas (`gds.graph.drop` de sus proyecciones, o `gds.session.delete`): se facturan por minuto (mínimo 10 min) hasta que expiran. Ensayar con el mismo plan de Aura que se usará en la demo: tamaño máximo, TTL y nº de sesiones varían por plan.
- Al preparar una sesión para un cliente concreto, anotar fecha/asistentes/ajustes específicos en el `Context.md` de ese cliente dentro de `Customers/`, no en este fichero.
