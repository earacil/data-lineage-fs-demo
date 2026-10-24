// =====================================================================================
// 01_ingesta.cypher — Ángulo 1: ingesta end-to-end, idempotente y con auto-conexión
// Demo de Data Lineage para Financial Services · Neo4j 5.x
//
// ⚠️  NO VALIDADO contra una instancia Neo4j real hasta que alguien lo ejecute en Aura/Desktop
//     (ver CONTEXTO_IA.md, restricción 4). Tratar como "a validar".
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
//   B. Llega un proyecto nuevo → MERGE idempotente (se puede ejecutar 2 veces: no duplica nada)
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
// Reglas del patrón (son el contenido de la nota de productivización, ver 04_productivizacion.md):
//   1. Todo nodo se identifica por una clave natural estable (`fqn`, `id`) → MERGE por esa clave sola.
//   2. Las propiedades descriptivas van en ON CREATE SET: una columna que ya existe NO se sobrescribe
//      desde un proyecto que sólo la lee.
//   3. Cada arista TRANSFORMS_TO lleva un `id` determinista (aquí: concatenación de job|origen|destino;
//      en el CSV es un hash corto) → reejecutar el script no crea aristas duplicadas.
// -------------------------------------------------------------------------------------

// B.1 · El job (con su propietario)
MERGE (j:EtlJob {id: 'J90'})
  ON CREATE SET j.name = 'BUILD_RWA_DENSITY',
                j.frequency = 'Weekly batch',
                j.owning_team = 'Regulatory Reporting Office',
                j.estimated_compute_cost = 39000,
                j.status = 'Active'
WITH j
MATCH (o:Owner {id: 'O04'})
MERGE (j)-[:MAINTAINED_BY]->(o);

// B.2 · Las columnas. Dos ya existen (se reutilizan), una es nueva.
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

// B.3 · El linaje (una arista por origen; misma expresión → multi-origen, igual que en el CSV)
UNWIND [
  {src: 'RISK_MART.RWA.RWA_AMOUNT'},
  {src: 'STG.STG_ACCOUNT.BALANCE'}
] AS s
MATCH (src:Column {fqn: s.src})
MATCH (tgt:Column {fqn: 'REG_MART.CAPITAL.RWA_DENSITY'})
MERGE (src)-[t:TRANSFORMS_TO {id: 'BUILD_RWA_DENSITY|' + src.fqn + '|' + tgt.fqn}]->(tgt)
  ON CREATE SET t.scenario = 'BUILD_RWA_DENSITY',
                t.transformation_expression = 'SUM(RWA_AMOUNT) / SUM(BALANCE)',
                t.filters = [],
                t.is_synthetic_source = false;

// B.4 · Qué job toca qué columnas, y quién consume el resultado
MATCH (j:EtlJob {id: 'J90'})
UNWIND ['RISK_MART.RWA.RWA_AMOUNT', 'STG.STG_ACCOUNT.BALANCE', 'REG_MART.CAPITAL.RWA_DENSITY'] AS fqn
MATCH (c:Column {fqn: fqn})
MERGE (j)-[:PROCESSES]->(c);

MATCH (c:Column {fqn: 'REG_MART.CAPITAL.RWA_DENSITY'})
MATCH (f:FinalConsumer {id: 'FC04'})   // Risk Data Aggregation Dashboard
MERGE (c)-[:FEEDS]->(f);

// >>> Ejecuta de nuevo A: +1 EtlJob, +1 Column, +2 TRANSFORMS_TO. Ejecuta B.1–B.4 otra vez y A de nuevo:
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

// C.2 · Linaje completo del dato nuevo hasta sus orígenes crudos y los sistemas que los alojan:
//       cruza ingesta core (P1) + riesgo (P2) + SAS (SS03) sin una sola arista escrita "a mano".
MATCH p = (root:Column)-[:TRANSFORMS_TO*1..10]->(:Column {fqn: 'REG_MART.CAPITAL.RWA_DENSITY'})
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
MATCH (ss:SourceSystem)-[:HOSTS]->(root)
RETURN ss.name AS source_system, root.fqn AS origin_column, length(p) AS hops,
       [r IN relationships(p) | r.scenario] AS jobs_in_path
ORDER BY hops DESC, origin_column;

// C.2b · Mismo linaje para visualizar en Browser/Bloom
MATCH p = (root:Column)-[:TRANSFORMS_TO*1..10]->(:Column {fqn: 'REG_MART.CAPITAL.RWA_DENSITY'})
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
RETURN p;

// C.3 · Mapa de dependencias ENTRE JOBS (derivado de los datos, no declarado en ningún sitio):
//       el job `producer` escribe una columna que el job `consumer` lee.
MATCH (:Column)-[w:TRANSFORMS_TO]->(c:Column)-[r:TRANSFORMS_TO]->(:Column)
WHERE w.scenario <> r.scenario
RETURN w.scenario AS producer_job, r.scenario AS consumer_job,
       count(DISTINCT c) AS shared_columns, collect(DISTINCT c.fqn)[..3] AS sample_columns
ORDER BY producer_job, consumer_job;


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
