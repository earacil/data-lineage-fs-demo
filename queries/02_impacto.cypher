// =====================================================================================
// 02_impacto.cypher — Ángulo 2: impacto ascendente/descendente, blast radius y centralidad
// Demo de Data Lineage para Financial Services · Neo4j 5.x
//
// ⚠️  NO VALIDADO contra una instancia Neo4j real hasta que alguien lo ejecute en Aura/Desktop
//     (ver CONTEXTO_IA.md, restricción 4). Tratar como "a validar".
//
// PRERREQUISITO: dataset cargado con data/00_load_live.cypher. No requiere GDS (Cypher puro).
//
// CONVENCIONES
//   · Para reutilizar una query con otra columna/sistema/job, cambia el literal marcado con «← CAMBIA».
//   · Las variable-length usan límite superior (*..10) como guarda de rendimiento: la cadena más larga del
//     dataset tiene 5 saltos. En producción conviene dejarlo acotado a la profundidad real del linaje.
//   · Un "origen crudo" (raíz) es una Column sin TRANSFORMS_TO entrante.
//
// ÍNDICE
//   1. Ascendente: ¿de dónde sale este dato?
//   2. Descendente: ¿qué rompe si cambia esta columna?
//   3. Camino completo sistema → informe
//   4. Blast radius por SourceSystem y por EtlJob
//   5. Casos especiales del modelo: CASE WHEN multi-origen, CONSTANT, TABLE
//   6. Centralidad: columnas, sistemas y jobs más críticos
//   7. Trazabilidad BCBS 239 por informe regulatorio
// =====================================================================================


// -------------------------------------------------------------------------------------
// 1. ASCENDENTE — ¿de dónde sale `REG_MART.SOLVENCY.TOTAL_RWA`?
// -------------------------------------------------------------------------------------

// 1.a · Visual (Browser/Bloom): todos los caminos hasta los orígenes crudos
MATCH p = (root:Column)-[:TRANSFORMS_TO*1..10]->(:Column {fqn: 'REG_MART.SOLVENCY.TOTAL_RWA'})   // ← CAMBIA
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
RETURN p;

// 1.b · Tabular: origen crudo, sistema que lo aloja, saltos y jobs atravesados
//       Esperado para TOTAL_RWA: CORE.LOAN.* (Core Banking) y SAS_RISK.RISK_WEIGHT.RISK_WEIGHT (SAS Risk Engine)
//       → un dato regulatorio que mezcla DOS sistemas origen a través de CINCO jobs de TRES proyectos.
MATCH p = (root:Column)-[:TRANSFORMS_TO*1..10]->(:Column {fqn: 'REG_MART.SOLVENCY.TOTAL_RWA'})   // ← CAMBIA
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
MATCH (ss:SourceSystem)-[:HOSTS]->(root)
RETURN ss.name AS source_system, root.fqn AS origin_column, length(p) AS hops,
       [r IN relationships(p) | r.scenario] AS jobs_in_path
ORDER BY hops DESC, origin_column;

// 1.c · Un solo salto: expresión exacta y filtros de cada arista que entra en la columna
MATCH (src:Column)-[t:TRANSFORMS_TO]->(:Column {fqn: 'RISK_MART.RWA.RWA_AMOUNT'})                  // ← CAMBIA
RETURN src.fqn AS source, t.scenario AS job, t.transformation_expression AS expression, t.filters AS filters;


// -------------------------------------------------------------------------------------
// 2. DESCENDENTE — ¿qué rompe si cambia `CORE.LOAN.DRAWN_AMOUNT`?
// -------------------------------------------------------------------------------------

// 2.a · Visual: todo lo que cuelga de la columna hasta los consumidores finales
//       (incluye la rama muerta EXPOSURE_ADJ_LEGACY: el cambio también la afecta aunque nadie la use)
MATCH p = (:Column {fqn: 'CORE.LOAN.DRAWN_AMOUNT'})-[:TRANSFORMS_TO*1..10]->(:Column)             // ← CAMBIA
RETURN p;

// 2.b · Informes afectados (lenguaje de negocio): consumidor, tipo, regulación, nº de columnas implicadas
MATCH (c:Column {fqn: 'CORE.LOAN.DRAWN_AMOUNT'})                                                    // ← CAMBIA
MATCH (c)-[:TRANSFORMS_TO*0..10]->(d:Column)-[:FEEDS]->(fc:FinalConsumer)
RETURN fc.name AS affected_consumer, fc.type AS type, fc.regulation AS regulation,
       count(DISTINCT d) AS affected_columns
ORDER BY regulation DESC, affected_consumer;

// 2.c · Jobs que habrá que revisar/volver a ejecutar si cambia la columna (los que tocan algo aguas abajo)
MATCH (:Column {fqn: 'CORE.LOAN.DRAWN_AMOUNT'})-[:TRANSFORMS_TO*0..10]->(d:Column)                  // ← CAMBIA
MATCH (j:EtlJob)-[:PROCESSES]->(d)
OPTIONAL MATCH (j)-[:MAINTAINED_BY]->(o:Owner)
RETURN j.name AS job, j.status AS status, j.frequency AS frequency,
       collect(DISTINCT o.name) AS owners, count(DISTINCT d) AS affected_columns
ORDER BY job;


// -------------------------------------------------------------------------------------
// 3. CAMINO COMPLETO sistema origen → informe (cadena de valor entera)
// -------------------------------------------------------------------------------------

// 3.a · Visual: SourceSystem → … → FinalConsumer para un informe concreto
//       (los orígenes con HOSTS en "Cloud Data Platform" son la constante 'EUR' y las referencias a tabla)
MATCH (fc:FinalConsumer {name: 'Solvency Report'})                                                  // ← CAMBIA
MATCH p = (:SourceSystem)-[:HOSTS]->(root:Column)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc)
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
RETURN p;

// 3.b · Tabular: qué sistemas aportan datos a cada informe y con cuántas columnas origen
MATCH (fc:FinalConsumer)
MATCH (ss:SourceSystem)-[:HOSTS]->(root:Column)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc)
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
RETURN fc.name AS consumer, fc.type AS type, ss.name AS source_system, count(DISTINCT root) AS origin_columns
ORDER BY consumer, origin_columns DESC;


// -------------------------------------------------------------------------------------
// 4. BLAST RADIUS
// -------------------------------------------------------------------------------------

// 4.a · "Si cae el Core Banking, ¿qué informes se ven afectados?"
MATCH (ss:SourceSystem {name: 'Core Banking PL/SQL'})                                               // ← CAMBIA
MATCH (ss)-[:HOSTS]->(root:Column)
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
MATCH (root)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc:FinalConsumer)
RETURN fc.name AS affected_consumer, fc.type AS type, fc.regulation AS regulation,
       count(DISTINCT root) AS origin_columns_involved
ORDER BY regulation DESC, affected_consumer;

// 4.b · Ranking de sistemas origen por alcance (consumidores y consumidores regulatorios afectados)
MATCH (ss:SourceSystem)-[:HOSTS]->(root:Column)
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
OPTIONAL MATCH (root)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc:FinalConsumer)
RETURN ss.name AS source_system, ss.criticality AS declared_criticality,
       count(DISTINCT fc) AS consumers_affected,
       count(DISTINCT CASE WHEN fc.type = 'Regulatory' THEN fc END) AS regulatory_consumers_affected
ORDER BY regulatory_consumers_affected DESC, consumers_affected DESC;

// 4.c · "Si falla el job CALC_EXPOSURE esta noche, ¿qué informes se quedan sin dato y a quién llamo?"
//       El job se vincula a sus columnas de salida a través de TRANSFORMS_TO.scenario = EtlJob.name.
MATCH (j:EtlJob {name: 'CALC_EXPOSURE'})                                                            // ← CAMBIA
MATCH ()-[t:TRANSFORMS_TO {scenario: j.name}]->(out:Column)
WITH j, collect(DISTINCT out) AS outputs
UNWIND outputs AS out
MATCH (out)-[:TRANSFORMS_TO*0..10]->(d:Column)-[:FEEDS]->(fc:FinalConsumer)
WITH j, fc, count(DISTINCT d) AS affected_columns
OPTIONAL MATCH (j)-[:MAINTAINED_BY]->(o:Owner)
RETURN j.name AS failed_job, fc.name AS starved_consumer, fc.type AS type, fc.regulation AS regulation,
       affected_columns, collect(DISTINCT o.name) AS who_to_call
ORDER BY regulation DESC, starved_consumer;


// -------------------------------------------------------------------------------------
// 5. CASOS ESPECIALES DEL MODELO (el motivo de que `Column`/`TRANSFORMS_TO` sean como son)
// -------------------------------------------------------------------------------------

// 5.a · Fórmulas multi-origen: mismo job + misma expresión repartida en N aristas
//       (un CASE WHEN con 3 columnas de entrada de 2 tablas distintas = RISK_MART.EXPOSURE.RATING_BUCKET)
MATCH (s:Column)-[t:TRANSFORMS_TO]->(tgt:Column)
WITH tgt, t.scenario AS job, t.transformation_expression AS expression, collect(s.fqn) AS sources
WHERE size(sources) > 1 AND expression CONTAINS 'CASE WHEN'
RETURN tgt.fqn AS target, job, size(sources) AS n_sources, sources, expression
ORDER BY n_sources DESC, target;

// 5.b · Valores fijos (kind = CONSTANT) y referencias a tabla completa (kind = TABLE)
//       CONSTANT → is_synthetic_source = true; TABLE → COUNT(*) sin columna concreta
MATCH (c:Column) WHERE c.kind IN ['CONSTANT', 'TABLE']
MATCH (c)-[t:TRANSFORMS_TO]->(tgt:Column)
RETURN c.kind AS kind, c.fqn AS source, t.transformation_expression AS expression,
       t.is_synthetic_source AS is_synthetic_source, tgt.fqn AS target, t.scenario AS job
ORDER BY kind, source, target;

// 5.c · Filtros aplicados en origen (modelados aparte de la expresión)
MATCH (s:Column)-[t:TRANSFORMS_TO]->(tgt:Column)
WHERE size(t.filters) > 0
RETURN t.scenario AS job, t.filters AS filters, count(*) AS edges_with_filter
ORDER BY job;


// -------------------------------------------------------------------------------------
// 6. CENTRALIDAD — dónde duele más que algo falle
// -------------------------------------------------------------------------------------

// 6.a · Columnas con más dependientes aguas abajo (columnas derivadas alcanzables) y consumidores alcanzados
MATCH (c:Column)
OPTIONAL MATCH (c)-[:TRANSFORMS_TO*1..10]->(d:Column)
WITH c, count(DISTINCT d) AS downstream_columns
OPTIONAL MATCH (c)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc:FinalConsumer)
RETURN c.fqn AS column, downstream_columns, count(DISTINCT fc) AS consumers_reached,
       COUNT { (c)-[:TRANSFORMS_TO]->() } AS direct_children
ORDER BY consumers_reached DESC, downstream_columns DESC, column
LIMIT 15;

// 6.b · Columnas que alimentan a MÁS DE UN informe (puntos únicos de fallo con efecto multiplicador)
MATCH (c:Column)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc:FinalConsumer)
WITH c, collect(DISTINCT fc.name) AS consumers
WHERE size(consumers) > 1
RETURN c.fqn AS column, size(consumers) AS n_consumers, consumers
ORDER BY n_consumers DESC, column;

// 6.c · Jobs por consumidores finales que dependen de ellos (cuántos informes mueren si ese job se cae)
MATCH (j:EtlJob)
OPTIONAL MATCH ()-[t:TRANSFORMS_TO {scenario: j.name}]->(out:Column)
OPTIONAL MATCH (out)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc:FinalConsumer)
RETURN j.name AS job, j.status AS status, j.estimated_compute_cost AS annual_cost_eur,
       count(DISTINCT fc) AS consumers_depending
ORDER BY consumers_depending DESC, annual_cost_eur DESC;


// -------------------------------------------------------------------------------------
// 7. TRAZABILIDAD BCBS 239 — por informe regulatorio: ¿hasta dónde llega la traza y quién responde?
// -------------------------------------------------------------------------------------

// 7.a · Por informe regulatorio: nº de columnas origen, sistemas, jobs implicados
MATCH (fc:FinalConsumer {type: 'Regulatory'})<-[:FEEDS]-(leaf:Column)
MATCH p = (root:Column)-[:TRANSFORMS_TO*1..10]->(leaf)
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
UNWIND relationships(p) AS r
WITH fc, collect(DISTINCT root) AS roots, collect(DISTINCT r.scenario) AS jobs
UNWIND roots AS root
OPTIONAL MATCH (ss:SourceSystem)-[:HOSTS]->(root)
WITH fc, jobs, size(roots) AS origin_columns, collect(DISTINCT ss.name) AS source_systems
RETURN fc.name AS report, fc.regulation AS regulation, origin_columns, source_systems,
       size(jobs) AS jobs_involved, jobs
ORDER BY report;

// 7.b · Brechas de accountability: jobs SIN propietario cuyas salidas son (o no) consumidas por un informe
//       Un job sin dueño y sin consumidor es candidato a retirada; sin dueño y CON consumidor regulatorio
//       es un incumplimiento. En el dataset de ejemplo el primer caso es LEGACY_BRANCH_REPORT.
MATCH (j:EtlJob)
WHERE NOT EXISTS { MATCH (j)-[:MAINTAINED_BY]->(:Owner) }
OPTIONAL MATCH ()-[t:TRANSFORMS_TO {scenario: j.name}]->(out:Column)
OPTIONAL MATCH (out)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc:FinalConsumer)
RETURN j.name AS ownerless_job, j.status AS status, collect(DISTINCT fc.name) AS consumers_served,
       count(DISTINCT CASE WHEN fc.type = 'Regulatory' THEN fc END) AS regulatory_consumers_served;
