// =====================================================================================
// 01_ingesta.cypher — Ángulo 1: ingesta end-to-end, idempotente y con auto-conexión
// Demo de Data Lineage para Financial Services · Neo4j 5.x
//
// ✅ Validado en Aura por el autor (26-oct-2026; ver CONTEXTO_IA.md, restricción 4). Cualquier cambio posterior
//    vuelve a ser "a validar".
//
// PRERREQUISITO: haber ejecutado data/00_load_live.cypher (segmento 0 + P1..P5).
//
// IDEA CENTRAL DEL ÁNGULO
//   Un proyecto ETL nuevo llega al grafo SIN trabajo de integración manual: basta con hacer MERGE de sus
//   columnas por `fqn`. Si el `fqn` ya existe (porque otro proyecto lo escribió antes), la columna se
//   REUTILIZA y las aristas nuevas la conectan solas a todo el linaje anterior.
//
// GUION EN VIVO (≈10 min)
//   A. Foto "antes"            → contadores
//   B. Llega un proyecto nuevo → B.1 dibujo de "qué había" (ANTES de cargar), B.2–B.4 MERGE idempotente
//                                (se puede ejecutar 2 veces: no duplica nada), B.5 dibujo de "qué se ha cargado"
//   C. Evidencia de auto-conexión → qué columnas compartía con otros proyectos, linaje completo sin
//                                   haber escrito ninguna arista "entre proyectos"
//   D. Salud de la ingesta     → comprobaciones de consistencia (scenario ↔ EtlJob, HOSTS, etc.)
//   E. Reset del demo          → deja el grafo como estaba para repetir la demo
// =====================================================================================


// -------------------------------------------------------------------------------------
// A. FOTO "ANTES" (anota los números; tras B deben cambiar sólo +1 job, +1 columna, etc.)
// -------------------------------------------------------------------------------------

MATCH (c:Column) WITH count(c) AS columns
MATCH (j:EtlJob) WITH columns, count(j) AS jobs
MATCH ()-[t:TRANSFORMS_TO]->() RETURN columns, jobs, count(t) AS transforms_to;


// -------------------------------------------------------------------------------------
// B. PROYECTO NUEVO "P6 · Capital adequacy" — ingesta idempotente con MERGE
//
// Escenario: el equipo de Regulatory Reporting despliega BUILD_RWA_DENSITY, que calcula
//   REG_MART.CAPITAL.RWA_DENSITY = SUM(RWA_AMOUNT) / SUM(BALANCE)
// leyendo dos columnas que YA existen en el grafo y que escribieron otros proyectos:
//   · RISK_MART.RWA.RWA_AMOUNT   → escrita por CALC_RWA            (proyecto P2, riesgo de crédito)
//   · STG.STG_ACCOUNT.BALANCE    → escrita por LOAD_CORE_ACCOUNTS  (proyecto P1, ingesta core)
//
// Orden de la historia:
//   B.1  Cómo está el grafo ANTES de cargar nada (el linaje que ya existe alrededor de esas dos columnas)
//   B.2–B.4  La ingesta: job → columnas → linaje y resto de relaciones
//   B.5  Qué se ha cargado (sólo lo nuevo)      B.6  (opcional) lo mismo en tabla
//
// Reglas del patrón (son la base del cierre de productivización de la demo, ver RUNBOOK_DEMO.md):
//   1. Todo nodo se identifica por una clave natural estable (`fqn`, `id`) → MERGE por esa clave sola.
//   2. Las propiedades descriptivas van en ON CREATE SET: una columna que ya existe NO se sobrescribe
//      desde un proyecto que sólo la lee.
//   3. Cada arista TRANSFORMS_TO lleva un `id` determinista (aquí: concatenación de job|origen|destino;
//      en el CSV es un hash corto) → reejecutar el script no crea aristas duplicadas.
// -------------------------------------------------------------------------------------

// B.1 · ANTES DE CARGAR — LO QUE YA HAY: el linaje preexistente de las dos columnas que usará el proyecto
//       nuevo. Ejecútalo ANTES de B.2 y mira el resultado en vista de grafo (no de tabla).
//       Se ven los orígenes crudos (Core Banking, SAS…), los jobs de otros proyectos que ya procesan esas
//       columnas y las transformaciones que las producen. Ahí es donde se va a enganchar el job nuevo.
//       Esperado: orígenes CORE.LOAN.DRAWN_AMOUNT/UNDRAWN_AMOUNT y SAS_RISK.RISK_WEIGHT.RISK_WEIGHT
//       (hacia RWA_AMOUNT) y CORE.ACCOUNT.BALANCE (hacia BALANCE). Los nodos EtlJob que se dibujan son los
//       que ya procesaban esas columnas: CALC_RWA y BUILD_COREP_SOLVENCY (RWA_AMOUNT); LOAD_CORE_ACCOUNTS,
//       BUILD_FINREP_BALANCE y BUILD_CHURN_FEATURES (BALANCE). Los jobs aguas arriba (CALC_EXPOSURE,
//       LOAD_CORE_LOANS, LOAD_RISK_RATINGS) aparecen como `scenario` en las aristas.
//       (Usa los fqn directamente porque el job nuevo todavía no existe; el filtro por nombre hace que el
//       dibujo siga mostrando el "antes" aunque lo ejecutes de nuevo después de cargar.)
MATCH (shared:Column)
WHERE shared.fqn IN ['RISK_MART.RWA.RWA_AMOUNT', 'STG.STG_ACCOUNT.BALANCE']
MATCH lineage = (root:Column)-[:TRANSFORMS_TO*1..10]->(shared)
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
MATCH touched_by = (other:EtlJob)-[:PROCESSES]->(shared)
WHERE other.name <> 'BUILD_RWA_DENSITY'
RETURN lineage, touched_by;

// B.2 · El job (con su propietario)
MERGE (j:EtlJob {id: 'J90'})
  ON CREATE SET j.name = 'BUILD_RWA_DENSITY',
                j.frequency = 'Weekly batch',
                j.owning_team = 'Regulatory Reporting Office',
                j.estimated_compute_cost = 39000,
                j.status = 'Active'
WITH j
MATCH (o:Owner {id: 'O04'})
MERGE (j)-[:MAINTAINED_BY]->(o);

// B.3 · Las columnas. Dos ya existen (se reutilizan), una es nueva.
UNWIND [
  {fqn: 'RISK_MART.RWA.RWA_AMOUNT',        name: 'RWA_AMOUNT',   kind: 'COLUMN', data_type: 'NUMBER(18,2)',
   field_type: 'amount', evidence: 'Product of an amount and a weight (risk-weighted assets)', host: 'SS06'},
  {fqn: 'STG.STG_ACCOUNT.BALANCE',         name: 'BALANCE',      kind: 'COLUMN', data_type: 'NUMBER(18,2)',
   field_type: 'amount', evidence: 'Pass-through of a monetary amount', host: 'SS06'},
  {fqn: 'REG_MART.CAPITAL.RWA_DENSITY',    name: 'RWA_DENSITY',  kind: 'COLUMN', data_type: 'NUMBER(9,8)',
   field_type: 'ratio',  evidence: 'Ratio of two SUM aggregations; values within [0,1]', host: 'SS06'}
] AS col
MERGE (c:Column {fqn: col.fqn})
  ON CREATE SET c.name = col.name, c.kind = col.kind, c.data_type = col.data_type,
                c.field_type = col.field_type, c.field_type_evidence = col.evidence
WITH c, col
MATCH (s:SourceSystem {id: col.host})
MERGE (s)-[:HOSTS]->(c);

// B.4 · El linaje y el resto de relaciones, en una sola sentencia:
//         · TRANSFORMS_TO  una arista por origen (misma expresión → multi-origen, igual que en el CSV)
//         · PROCESSES      qué job toca qué columnas (los dos orígenes y el destino)
//         · FEEDS          quién consume el resultado (Risk Data Aggregation Dashboard)
MATCH (j:EtlJob {id: 'J90'})
MATCH (tgt:Column {fqn: 'REG_MART.CAPITAL.RWA_DENSITY'})
MATCH (f:FinalConsumer {id: 'FC04'})
UNWIND ['RISK_MART.RWA.RWA_AMOUNT', 'STG.STG_ACCOUNT.BALANCE'] AS src_fqn
MATCH (src:Column {fqn: src_fqn})
MERGE (src)-[t:TRANSFORMS_TO {id: 'BUILD_RWA_DENSITY|' + src.fqn + '|' + tgt.fqn}]->(tgt)
  ON CREATE SET t.scenario = 'BUILD_RWA_DENSITY',
                t.transformation_expression = 'SUM(RWA_AMOUNT) / SUM(BALANCE)',
                t.filters = [],
                t.is_synthetic_source = false
MERGE (j)-[:PROCESSES]->(src)
MERGE (j)-[:PROCESSES]->(tgt)
MERGE (tgt)-[:FEEDS]->(f);

// B.5 · AHORA — LO QUE SE HA CARGADO: sólo lo que aporta el proyecto nuevo (6 nodos, 7 relaciones):
//       el job y su propietario, las 3 columnas que toca, las 2 aristas TRANSFORMS_TO (misma expresión,
//       multi-origen) y el informe que consume el resultado. Vista de grafo, como B.1.
//       Las 2 columnas de origen son las MISMAS que has visto en B.1: ahí es donde el proyecto nuevo
//       "se engancha" al linaje que ya existía. Sólo `RWA_DENSITY` y `BUILD_RWA_DENSITY` son nodos nuevos.
//       Idea a transmitir: la carga sólo ha AÑADIDO 1 job, 1 columna y 2 aristas de linaje; todo lo demás
//       que se veía en B.1 (orígenes, sistemas, otros jobs) ya estaba y ahora queda enganchado.
MATCH (new:EtlJob {name: 'BUILD_RWA_DENSITY'})
MATCH job_edges = (new)-[:PROCESSES|MAINTAINED_BY]->()
MATCH new_lineage = (:Column)-[:TRANSFORMS_TO {scenario: new.name}]->(:Column)-[:FEEDS]->(:FinalConsumer)
RETURN job_edges, new_lineage;

// B.6 · (opcional, tabla) La misma historia en una línea por columna: ¿nueva o reutilizada?
MATCH (new:EtlJob {name: 'BUILD_RWA_DENSITY'})-[:PROCESSES]->(c:Column)
OPTIONAL MATCH (other:EtlJob)-[:PROCESSES]->(c) WHERE other <> new
WITH c, collect(DISTINCT other.name) AS already_processed_by
RETURN c.fqn AS column,
       CASE WHEN size(already_processed_by) = 0 THEN 'NEW (created by this load)'
            ELSE 'REUSED (already in the graph)' END AS status,
       already_processed_by
ORDER BY status DESC, column;

// >>> Ejecuta de nuevo A: +1 EtlJob, +1 Column, +2 TRANSFORMS_TO. Ejecuta B.2–B.4 otra vez y A de nuevo:
//     los números no se mueven (idempotencia).


// -------------------------------------------------------------------------------------
// C. EVIDENCIA DE AUTO-CONEXIÓN
// -------------------------------------------------------------------------------------

// C.1 · ¿Con qué otros proyectos se ha conectado el job nuevo, sin que lo escribiéramos explícitamente?
//       (columnas que el job toca y que otros jobs también tocan)
MATCH (j:EtlJob {name: 'BUILD_RWA_DENSITY'})-[:PROCESSES]->(c:Column)
OPTIONAL MATCH (other:EtlJob)-[:PROCESSES]->(c) WHERE other <> j
RETURN c.fqn AS shared_column, collect(DISTINCT other.name) AS also_processed_by
ORDER BY shared_column;

// C.1b · Mismo resultado para VISUALIZAR en Browser/Bloom (devuelve paths) — paso 1 de la historia:
//        "¿cómo se ha conectado el job nuevo?"  Dibuja el job nuevo, las columnas que comparte con el
//        resto del grafo y los jobs que ya las tocaban:
//            (BUILD_RWA_DENSITY) → [columna compartida] ← (job que ya la procesaba)
//        Esperado: 1 job nuevo + 2 columnas compartidas (RISK_MART.RWA.RWA_AMOUNT y STG.STG_ACCOUNT.BALANCE)
//        + 5 jobs existentes (CALC_RWA y BUILD_COREP_SOLVENCY; LOAD_CORE_ACCOUNTS, BUILD_FINREP_BALANCE y
//        BUILD_CHURN_FEATURES). La columna nueva RWA_DENSITY no aparece: no se comparte con nadie.
//        Hilo de la demo:  C.1b (el job se engancha) → C.2b (por dónde fluye el dato: columnas) →
//        C.3b / C.3c (el mapa completo de jobs).
MATCH p = (new:EtlJob {name: 'BUILD_RWA_DENSITY'})-[:PROCESSES]->(c:Column)<-[:PROCESSES]-(other:EtlJob)
WHERE other <> new
RETURN p;

// C.2 · Linaje completo del dato nuevo hasta sus orígenes crudos y los sistemas que los alojan:
//       cruza ingesta core (P1) + riesgo (P2) + SAS (SS03) sin una sola arista escrita "a mano".
MATCH p = (root:Column)-[:TRANSFORMS_TO*1..10]->(:Column {fqn: 'REG_MART.CAPITAL.RWA_DENSITY'})
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
MATCH (ss:SourceSystem)-[:HOSTS]->(root)
RETURN ss.name AS source_system, root.fqn AS origin_column, length(p) AS hops,
       [r IN relationships(p) | r.scenario] AS jobs_in_path
ORDER BY hops DESC, origin_column;

// C.2b · Mismo linaje para visualizar en Browser/Bloom — paso 2 de la historia: "¿por dónde fluye el dato?"
//        (desde el sistema que aloja cada origen crudo hasta RWA_DENSITY)
//        ► AÑADIDO: el tramo (SourceSystem)-[:HOSTS]->(origen) al principio del path, para que el grafo
//          enseñe también DE QUÉ SISTEMA sale cada dato, no solo las columnas. (Es el único linaje
//          ascendente de la demo: 02_impacto ya no repite esta consulta.)
MATCH p = (:SourceSystem)-[:HOSTS]->(root:Column)-[:TRANSFORMS_TO*1..10]->(:Column {fqn: 'REG_MART.CAPITAL.RWA_DENSITY'})   // ◄ HOSTS añadido
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
RETURN p;

// C.3 · Mapa de dependencias ENTRE JOBS (derivado de los datos, no declarado en ningún sitio):
//       el job `producer` escribe una columna que el job `consumer` lee.
MATCH (:Column)-[w:TRANSFORMS_TO]->(c:Column)-[r:TRANSFORMS_TO]->(:Column)
WHERE w.scenario <> r.scenario
RETURN w.scenario AS producer_job, r.scenario AS consumer_job,
       count(DISTINCT c) AS shared_columns, collect(DISTINCT c.fqn)[..3] AS sample_columns
ORDER BY producer_job, consumer_job;
//       Esperado: 13 pares productor→consumidor entre 12 jobs (15 pares y 13 jobs si ya has ejecutado el
//       bloque B: BUILD_RWA_DENSITY depende de CALC_RWA y de LOAD_CORE_ACCOUNTS). LEGACY_BRANCH_REPORT no
//       aparece: es el único job sin ninguna dependencia con otro.

// C.3b · Mismo mapa de dependencias entre jobs, para VISUALIZAR en Browser/Bloom (devuelve paths)
//        Cada dependencia se dibuja como  (job productor) → [columna compartida] ← (job consumidor).
//        La columna puente es lo que "pega" los dos jobs: es el dato que uno escribe y el otro lee.
//        Se usa TRANSFORMS_TO.scenario para distinguir quién ESCRIBE y quién LEE (PROCESSES no lo distingue).
//        Esperado: 12 EtlJob, 26 columnas puente y 13 pares de jobs (con el bloque B cargado: 13 EtlJob y
//        15 pares; las columnas puente siguen siendo 26 porque BUILD_RWA_DENSITY reutiliza dos que ya lo
//        eran). Los jobs aparecen enlazados en cadena LOAD_* → CALC_* → BUILD_*, y LOAD_CRM_CUSTOMERS,
//        LOAD_CORE_ACCOUNTS y LOAD_CARD_TRANSACTIONS se abren en abanico hacia varios consumidores.
MATCH p = (producer:EtlJob)-[:PROCESSES]->(c:Column)<-[:PROCESSES]-(consumer:EtlJob)
WHERE producer <> consumer
  AND EXISTS { MATCH (:Column)-[:TRANSFORMS_TO {scenario: producer.name}]->(c) }   // producer ESCRIBE c
  AND EXISTS { MATCH (c)-[:TRANSFORMS_TO {scenario: consumer.name}]->(:Column) }   // consumer LEE c
RETURN p;

// C.3c · (opcional) La versión más limpia: aristas job → job directas, sin columnas intermedias.
//        Usa relaciones VIRTUALES de APOC: se dibujan pero NO se guardan en la base de datos (el modelo no
//        cambia). Requiere APOC (`apoc.create.vRelationship`) disponible en tu instancia y que la
//        herramienta de visualización admita relaciones virtuales — pruébalo en Query/Explore; si no se
//        dibuja, usa C.3b. Cada arista lleva cuántas columnas comparten los dos jobs.
MATCH (producer:EtlJob)-[:PROCESSES]->(c:Column)<-[:PROCESSES]-(consumer:EtlJob)
WHERE producer <> consumer
  AND EXISTS { MATCH (:Column)-[:TRANSFORMS_TO {scenario: producer.name}]->(c) }
  AND EXISTS { MATCH (c)-[:TRANSFORMS_TO {scenario: consumer.name}]->(:Column) }
WITH producer, consumer, collect(DISTINCT c.fqn) AS shared_columns
RETURN producer, consumer,
       apoc.create.vRelationship(producer, 'DEPENDENCY', {shared_columns: size(shared_columns),
                                                          sample: shared_columns[..3]}, consumer) AS dependency;


// -------------------------------------------------------------------------------------
// D. SALUD DE LA INGESTA — deben devolver 0 filas tras cualquier carga
// -------------------------------------------------------------------------------------

// D.1 · Aristas con `scenario` sin EtlJob correspondiente (invariante del modelo)
MATCH ()-[t:TRANSFORMS_TO]->()
WHERE NOT EXISTS { MATCH (:EtlJob {name: t.scenario}) }
RETURN DISTINCT t.scenario AS scenario_without_job;

// D.2 · Columnas sin ningún SourceSystem que las aloje
MATCH (c:Column)
WHERE NOT EXISTS { MATCH (:SourceSystem)-[:HOSTS]->(c) }
RETURN c.fqn AS column_without_host;

// D.3 · Columnas sin ninguna arista de linaje (ni entrante ni saliente): carga a medias o columna huérfana
MATCH (c:Column)
WHERE NOT EXISTS { MATCH (c)-[:TRANSFORMS_TO]-() }
RETURN c.fqn AS column_without_lineage;

// D.4 · Jobs que no procesan ninguna columna
MATCH (j:EtlJob)
WHERE NOT EXISTS { MATCH (j)-[:PROCESSES]->(:Column) }
RETURN j.name AS job_without_columns;

// D.5 · Jobs sin propietario (este SÍ devuelve una fila en el dataset de ejemplo: LEGACY_BRANCH_REPORT.
//       Es deliberado: accountability BCBS 239 incumplida y candidato a retirada, ver ángulos 3 y 5)
MATCH (j:EtlJob)
WHERE NOT EXISTS { MATCH (j)-[:MAINTAINED_BY]->(:Owner) }
RETURN j.name AS job_without_owner, j.status AS status, j.estimated_compute_cost AS annual_cost_eur;

// D.6 · Propiedades obligatorias de TRANSFORMS_TO ausentes
MATCH ()-[t:TRANSFORMS_TO]->()
WHERE t.id IS NULL OR t.scenario IS NULL OR t.transformation_expression IS NULL
RETURN t;


// -------------------------------------------------------------------------------------
// E. RESET DEL DEMO — elimina SÓLO lo que añadió el bloque B (las columnas compartidas se quedan)
// -------------------------------------------------------------------------------------

MATCH ()-[t:TRANSFORMS_TO {scenario: 'BUILD_RWA_DENSITY'}]->() DELETE t;
MATCH (j:EtlJob {id: 'J90'}) DETACH DELETE j;
MATCH (c:Column {fqn: 'REG_MART.CAPITAL.RWA_DENSITY'}) DETACH DELETE c;
