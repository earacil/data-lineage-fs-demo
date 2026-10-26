# Guion de demo — plantilla genérica (1 hora)

> Estado: el Cypher, la perspectiva de Bloom y los dos dashboards están probados en Aura por el autor (26-oct-2026). Los tiempos son una estimación: ensayar con cronómetro antes de usarlo. Estructura reutilizable para cualquier cliente de Financial Services.
>
> Hilo conductor: *un dato cambia → quién lo usa (impacto) → de dónde viene (trazabilidad) → qué sobra (zonas muertas)*. Bloom y los dashboards **no son bloques aparte**: se usan dentro de la ingesta y el impacto, donde aportan.

| Bloque | Duración | Contenido | Herramienta | Ángulo |
|---|---|---|---|---|
| Intro | 5 min | Por qué un grafo para lineage en banca (gobierno de datos, trazabilidad de informes regulatorios hasta su origen) | — | — |
| El modelo | 6 min | Los 5 nodos y sus relaciones, capa técnica frente a capa semántica, qué contiene el dataset sintético | Bloom (esquema) | — |
| Ingesta en vivo | 12 min | Cargar un proyecto ETL en directo y un job nuevo que se autoconecta a columnas ya existentes de otros proyectos, sin integración manual | Query tool + Bloom | 1 |
| Impacto y trazabilidad | 17 min | "¿Qué rompe si cambia esta columna / cae este sistema?" y "¿de dónde sale este informe?" | Bloom + dashboard «Data Lineage Impact» | 2 |
| Zonas muertas con GDS | 12 min | Proyección GDS + BFS reverso desde `FinalConsumer`; candidatos a retirada de `EtlJob` con coste asociado | Query tool + dashboard «Data Lineage Dead Zones» | 3 |
| Cierre (productivización) | 3 min | Ingesta idempotente, dos capas (técnica y semántica), informe periódico de zonas muertas sin borrado automático | — | 5 |
| Q&A | 5 min | — | — | — |

## Preparación (antes de la sesión)

1. Instancia AuraDB con **Aura Graph Analytics activado** (ver `AURA_SETUP.md` §1). Subir el repo a GitHub (público) y fijar en el Query tool el parámetro `baseUrl` de `AURA_SETUP.md` §2 (apuntando a una **etiqueta/SHA**, no a `main`). Comprobarlo con `:params` (se pierde al refrescar).
2. **Pre-cargar el segmento 0 y los proyectos P1, P2, P4 y P5** de `data/00_load_live.cypher`. Dejar **P3** (reporting regulatorio) y el **proyecto nuevo del bloque B** de `01_ingesta.cypher` para cargarlos en directo. Si prefieres una demo más corta, pre-cargar los 5 proyectos y usar solo el bloque B.
3. Verificar con el último bloque de `00_load_live.cypher` los recuentos esperados **una vez cargados los 5 proyectos** (81 / 7 / 13 / 6 / 7 nodos; 66 / 81 / 113 / 25 / 14 aristas).
4. Si en un ensayo se cargó el bloque B, ejecutar antes `queries/01_ingesta.cypher` bloque E (reset).
5. Importar la perspectiva `bloom/data_lineage_fs_perspective.json` (ver `bloom/BLOOM_GUIDE.md`) y los dos dashboards de `dashboards/` (ver `dashboards/DASHBOARDS_GUIDE.md`); comprobar que las search phrases devuelven valores en sus desplegables.
6. Revisar sesiones AGA olvidadas de un ensayo (`CALL gds.session.list()`).

## Escaleta con comandos

Los bloques se numeran desde el 2: el 1 es la preparación.

Las cifras son «con el bloque B cargado» salvo que se indique lo contrario.

### 2 · Intro (5 min) y 3 · El modelo (6 min)

| Min | Acción | Qué decir |
|---|---|---|
| 0-5 | Sin pantalla | "Tres preguntas cuesta contestar: de dónde sale esta cifra del informe regulatorio (BCBS 239), qué rompo si cambio esta columna, qué pago que nadie usa." |
| 5-8 | Bloom: esquema del grafo | Los 5 nodos (`Column`, `EtlJob`, `SourceSystem`, `FinalConsumer`, `Owner`) y las relaciones (`TRANSFORMS_TO`, `HOSTS`, `PROCESSES`, `FEEDS`, `MAINTAINED_BY`) |
| 8-11 | Dos capas | "Técnica: se calcula del código. Semántica (informes, propietarios, coste): la pone el negocio." Dejar explícito que el dataset es **sintético**: 5 proyectos ETL, 14 jobs con el bloque B |

### 4 · Ingesta en vivo (12 min) — `data/00_load_live.cypher`, `queries/01_ingesta.cypher`

| Min | Acción | Qué decir |
|---|---|---|
| 0-2 | Mostrar las restricciones y el segmento 0 (ya cargados) | "Primero el contexto de negocio: 7 sistemas origen, 6 informes finales. La unicidad está en la base de datos." |
| 2-5 | Ejecutar el segmento **P3** (reporting regulatorio); Bloom: `C3a` (mapa de jobs) | "Este lote no trae ninguna columna de riesgo y aun así sus transformaciones leen `RISK_MART.*`: el `MERGE` por `fqn` las encuentra ya cargadas." |
| 5-9 | `01_ingesta.cypher`: foto de números → **B.1** (el grafo ANTES, en vista de grafo) → **B.2–B.4** (ingesta de `BUILD_RWA_DENSITY`) → **B.5** (qué se ha cargado) | "Cero aristas escritas a mano entre proyectos: el job nuevo se engancha a columnas que ya existían." |
| 9-11 | Bloom: `C1` (`BUILD_RWA_DENSITY`), `C2` (`REG_MART.CAPITAL.RWA_DENSITY`), `C3a` (con el job nuevo; opcional `C3b`) | "Su dato traza hasta el Core Banking y el motor de riesgo SAS, cruzando tres proyectos." |
| 11-12 | Repetir B.2–B.4 y la foto de números | "Idempotente: mismos números. Eso es lo que permite cargar cada noche sin miedo." |

### 5 · Impacto y trazabilidad (17 min) — `queries/02_impacto.cypher`, Bloom y dashboard

| Min | Acción | Qué decir |
|---|---|---|
| 0-4 | Bloom: `1. Column $column impact` con `CORE.LOAN.DRAWN_AMOUNT` | "Si cambia esta columna: 3 informes y 5 jobs a revisar (4 sin el bloque B), y a quién llamar." Señalar la columna muerta `EXPOSURE_ADJ_LEGACY` (gancho al bloque 6) |
| 4-9 | Bloom: `2. Full Path to FinalConsumer $finalConsumer` con `Solvency Report`; tabla 2.b | "De dónde sale un informe regulatorio: qué sistemas y cuántas columnas origen aporta cada uno (BCBS 239)." |
| 9-17 | Dashboard «Data Lineage Impact»: sistemas por impacto (3.b) → filtro de sistema + informes afectados (3.a) → informes afectados si cae un job (5) → datos de informes regulatorios (6.a) → brechas de accountability (6.b) | "Lo que acabamos de ver en grafo, resumido en una pantalla: blast radius por sistema, dónde duele más que algo falle y qué jobs no tienen dueño." |

### 6 · Zonas muertas con GDS (12 min) — `queries/03_zonas_muertas_gds.cypher`

| Min | Acción | Qué decir |
|---|---|---|
| 0-2 | Definir "muerto": un dato que se carga y se paga pero del que no sale ninguna flecha hasta un informe, dashboard o modelo (`FinalConsumer`) | "No es un flag: se calcula con el grafo. Es un candidato a retirada, no una orden." |
| 2-7 | Parte **A**: A.1 proyección (crea la sesión), A.2 BFS por informe, A.3 resumen vivas/muertas, A.5 en grafo | Explicar el BFS ("echar tinta en el informe y ver por dónde se tiñe aguas arriba"). Esperado: 74 vivas y 8 muertas |
| (opcional, +2) | Parte **C** (C.1/C.1b PageRank, C.2/C.2b y C.3 betweenness), con la sesión aún viva | "Cypher cuenta hasta dónde llega un dato; el algoritmo dice por dónde pasa todo: CALC_EXPOSURE y CALC_RWA son los cuellos de botella." Betweenness no distingue vivo de muerto. Ejecutarla ANTES de Z |
| 7 | Parte **Z**: borrar la proyección (y con ella la sesión); comprobar que no queda ninguna | "Sesión efímera: se levanta para calcular y se tira." |
| 7-12 | Dashboard «Data Lineage Dead Zones»: columnas muertas (D.1) → jobs muertos (D.4) → ahorro (D.5) → columnas muertas en jobs vivos (D.6) → salud por sistema (D.7); opcional D.2/D.3 | "127.000 € al año en jobs que nadie consume, uno deprecado y sin propietario. Una columna sobra en un job que sí se queda; un sistema entero al 0 %." |
| — | La parte **B** (por qué WCC no basta) es material de apoyo, no se cuenta; sirve si preguntan por qué BFS | — |
| — | **Plan B si GDS falla:** ir directamente a la parte **D** (mismo resultado en Cypher puro) | — |

### 7 · Cierre (3 min)

| Idea | Qué decir |
|---|---|
| Ingesta idempotente | "El scanner es desechable; el grafo, no." `MERGE` por clave natural, restricciones, mark & sweep por `scenario` cuando un job cambia |
| Dos capas | "El linaje se calcula; el consumo final y los propietarios los pone el negocio." `FEEDS` es el eslabón crítico; el catálogo del cliente se integra, no se sustituye |
| Informe periódico | Las queries de zonas muertas, programadas (semanal / mensual) con KPIs de tendencia. **Sin borrado automático**: una zona muerta es un candidato |
| Cierre BCBS 239 | "Cada cifra reportada traza hasta su origen y tiene un responsable." |

Si preguntan por producción: acotar la profundidad de los caminos variables, validar que el linaje sea un DAG tras cada carga, sesiones GDS efímeras (se facturan por minuto), RBAC sobre el grafo (son metadatos, pero las expresiones pueden ser sensibles).

## Notas de preparación

- El dataset es sintético; dejarlo explícito al abrir la demo (ver `data-model/NOTAS_DISENO.md`).
- Dejar 1-2 minutos de margen entre bloques: la ingesta en vivo es la parte con más riesgo de imprevistos. Plan B de ingesta: tener todo pre-cargado y ejecutar solo el bloque B de `01_ingesta.cypher` (pocas líneas, sin dependencia de URLs de CSV).
- Antes de la demo, revisar sesiones AGA olvidadas de un ensayo (`CALL gds.session.list()`) y borrarlas (`gds.graph.drop` de sus proyecciones, o `gds.session.delete`): se facturan por minuto (mínimo 10 min) hasta que expiran. Ensayar con el mismo plan de Aura que se usará en la demo: tamaño máximo, TTL y nº de sesiones varían por plan.
- Si Bloom falla, el bloque de impacto se puede dar entero en el dashboard; las queries originales de grafo están en `02_impacto.cypher`, secciones 1 y 2.a.
- Al preparar una sesión para un cliente concreto, anotar fecha/asistentes/ajustes específicos en el `Context.md` de ese cliente dentro de `Customers/`, no en este fichero.
