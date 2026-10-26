// =====================================================================================
// 02_impacto.cypher — Ángulo 2: impacto descendente, camino completo, blast radius y criticidad por alcance
// Demo de Data Lineage para Financial Services · Neo4j 5.x
//
// ESTADO DE VALIDACIÓN (ver CONTEXTO_IA.md, restricción 4)
//   ✅ Validadas en Aura por el autor (26-oct-2026): 1, 2.a y 2.b (en Bloom) y 3.a (variante con $source_system),
//      3.b, 5, 6.a y 6.b (en el dashboard).
//   ➖ La sección 4 (casos especiales) NO se usa en la demo y no se ha probado: se conserva como material de apoyo.
//
// PRERREQUISITO: dataset cargado con data/00_load_live.cypher. No requiere GDS (Cypher puro).
//
// CONVENCIONES
//   · Para reutilizar una query con otra columna/sistema/job, cambia el literal marcado con «← CAMBIA»
//     (o conviértelo en parámetro de la herramienta de visualización: Bloom admite parámetros en las
//     search phrases).
//   · Las variable-length usan límite superior (*..10) como guarda de rendimiento: la cadena más larga del
//     dataset tiene 5 saltos. En producción conviene dejarlo acotado a la profundidad real del linaje.
//   · Un "origen crudo" (raíz) es una Column sin TRANSFORMS_TO entrante.
//   · Las queries 1 y 2.a devuelven PATHS pensados para verse como grafo (Browser/Bloom); el resto son tablas.
//
// NOTA: el linaje ASCENDENTE ("¿de dónde sale este dato?") no está aquí: se enseña en 01_ingesta.cypher
//       (C.2 / C.2b, con los sistemas que alojan los orígenes) justo después de cargar el proyecto nuevo.
//
// ÍNDICE
//   1. Descendente: ¿qué rompe si cambia esta columna? (una sola query en grafo: linaje, jobs, dueños e informes)
//   2. Camino completo sistema → informe
//   3. Blast radius por SourceSystem
//   4. Casos especiales del modelo: CASE WHEN multi-origen, CONSTANT, TABLE  (material de apoyo, fuera de la demo)
//   5. Criticidad por alcance: jobs por informes que dependen de ellos (conteo de caminos, no centralidad
//      GDS; los algoritmos de centralidad reales —PageRank, betweenness— están en 03, parte D)
//   6. Trazabilidad BCBS 239 por informe regulatorio
//
// DASHBOARD (Aura Dashboards) — export en dashboard/data_lineage_fs_impact_dashboard.json, título «Data Lineage Impact»
//   Creado y verificado en Aura por el autor el 26-oct-2026. Las queries usadas se marcan con «▣ DASHBOARD».
//   Idea: Bloom enseña caminos y estructura; el dashboard enseña los AGREGADOS (rankings, tablas) de un vistazo.
//   Solo Cypher puro. Quedan fuera: las secciones 1 y 2.a (son grafos, para Bloom), la 4 (casos especiales, material
//   de apoyo) y los algoritmos de 03·D.
//
//   Tarjetas (según el export):
//     ▣ «1. Source Systems by Impact» ......... 3.b  Bar chart vertical, valores agrupados
//     ▣ filtro «2. Source System» .............. parámetro $source_system (filtro de propiedad SourceSystem.name,
//                                                valor inicial 'Core Banking PL/SQL')
//     ▣ «2. Affected Reports (Consumer)» ....... 3.a  Tabla (variante con $source_system)
//     ▣ «3. #Reports Affected if a Job Fails» .. 5    Bar chart horizontal
//     ▣ «4. Regulatory Report Data» ............ 6.a  Tabla (con la lista de jobs)
//     ▣ «5. Accountability Gaps» ............... 6.b  Tabla pequeña con estilo condicional
//
//   Notas de montaje (documentación: neo4j.com/docs/aura/dashboards):
//     · Los parámetros se llaman «$nombre» (sin prefijo `neodash_`) y se crean en el cajón `{}` o al crear un
//       filtro. NO son los `:param` del Query tool, así que fuera del dashboard hay que fijarlos a mano.
//     · Bar chart: 1 columna de texto (Category) + 1 o más numéricas (Value). Tabla: pinta todas las columnas.
//     · Mantén un LIMIT razonable en las tarjetas que puedan crecer (recomendación de la propia documentación).
// =====================================================================================


// -------------------------------------------------------------------------------------
// 1. DESCENDENTE — ¿qué rompe si cambia `CORE.LOAN.DRAWN_AMOUNT`?
//    Esperado: 8 columnas en su descendencia (ella incluida), 3 informes (Solvency Report, Large Exposures
//    Report y Risk Data Aggregation Dashboard) y 4 jobs que la tocan (LOAD_CORE_LOANS, CALC_EXPOSURE,
//    CALC_RWA y BUILD_COREP_SOLVENCY). Cifras calculadas sobre los CSV, no con Neo4j.
// -------------------------------------------------------------------------------------

// 1 · Impacto descendente en UNA sola query, para verla como grafo en Bloom/Browser.
//     Devuelve cuatro paths para que Bloom lo pinte todo junto:
//       lineage        = columna que cambia → … → columnas derivadas (TRANSFORMS_TO)
//       touched_by     = job → columna afectada (PROCESSES): los jobs que habrá que revisar / volver a ejecutar
//       maintained_by  = job → dueño (MAINTAINED_BY): a quién avisar
//       final_customer = columna afectada → informe (FEEDS): qué informes se ven afectados
//     Los informes salen solo donde hay camino vivo; la columna muerta EXPOSURE_ADJ_LEGACY (colgada de
//     CALC_EXPOSURE) sale SIN informe: es el gancho hacia el ángulo 3 (zonas muertas).
MATCH lineage = (:Column {fqn: 'CORE.LOAN.DRAWN_AMOUNT'})-[:TRANSFORMS_TO*0..10]->(d:Column)            // ← CAMBIA
MATCH touched_by = (j:EtlJob)-[:PROCESSES]->(d)
OPTIONAL MATCH maintained_by = (j)-[:MAINTAINED_BY]->(:Owner)
OPTIONAL MATCH final_customer = (d)-[:FEEDS]->(:FinalConsumer)
RETURN lineage, touched_by, maintained_by, final_customer;


// -------------------------------------------------------------------------------------
// 2. CAMINO COMPLETO sistema origen → informe (cadena de valor entera)
// -------------------------------------------------------------------------------------

// 2.a · Visual: SourceSystem → … → FinalConsumer para un informe concreto
//       (los orígenes con HOSTS en "Cloud Data Platform" son la constante 'EUR' y las referencias a tabla)
MATCH (fc:FinalConsumer {name: 'Solvency Report'})                                                  // ← CAMBIA
MATCH p = (:SourceSystem)-[:HOSTS]->(root:Column)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc)
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
RETURN p;

// 2.b · Tabular: qué sistemas aportan datos a cada informe y con cuántas columnas origen
MATCH (fc:FinalConsumer)
MATCH (ss:SourceSystem)-[:HOSTS]->(root:Column)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc)
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
RETURN fc.name AS consumer, fc.type AS type, ss.name AS source_system, count(DISTINCT root) AS origin_columns
ORDER BY consumer, origin_columns DESC;


// -------------------------------------------------------------------------------------
// 3. BLAST RADIUS por SourceSystem
// -------------------------------------------------------------------------------------

// 3.a · "Si cae el Core Banking, ¿qué informes se ven afectados?"
MATCH (ss:SourceSystem {name: 'Core Banking PL/SQL'})                                               // ← CAMBIA
MATCH (ss)-[:HOSTS]->(root:Column)
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
MATCH (root)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc:FinalConsumer)
RETURN fc.name AS affected_consumer, fc.type AS type, fc.regulation AS regulation,
       count(DISTINCT root) AS origin_columns_involved
ORDER BY regulation DESC, affected_consumer;

// ▣ DASHBOARD · «2. Affected Reports (Consumer)» · VARIANTE de 3.a — TABLA con un FILTRO que elige el sistema
//   Cambio: el literal pasa a ser el parámetro $source_system, enlazado al filtro «2. Source System»
//   (Node property → `SourceSystem.name`, valor inicial 'Core Banking PL/SQL').
//   Estilo aplicado: la columna `type` se resalta en amarillo cuando contiene 'Regulatory'.
//   Esperado: con 'Core Banking PL/SQL', varios informes (los mismos que 3.a); con 'Legacy Data Mart', 0 filas
//   (sistema sin ningún consumidor: aquí se ve el aspecto "decommission" del ángulo 3).
//   (En el Query tool/Browser esta query solo corre si defines antes `:param source_system => '...'`.)
MATCH (ss:SourceSystem {name: $source_system})
MATCH (ss)-[:HOSTS]->(root:Column)
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
MATCH (root)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc:FinalConsumer)
RETURN fc.name AS affected_consumer, fc.type AS type, fc.regulation AS regulation,
       count(DISTINCT root) AS origin_columns_involved
ORDER BY regulation DESC, affected_consumer
LIMIT 25;

// 3.b · Ranking de sistemas origen por alcance (consumidores y consumidores regulatorios afectados)
//       ▣ DASHBOARD · «1. Source Systems by Impact» · query SIN cambios — BAR CHART vertical, valores agrupados
//         Category = source_system · Value = consumers_affected y regulatory_consumers_affected
//         (`declared_criticality` queda sin seleccionar: es texto). Es la tarjeta de entrada: se ve de un vistazo
//         qué sistema "sostiene" más informes. Los sistemas con 0 salen sin barra (p. ej. Legacy Data Mart).
MATCH (ss:SourceSystem)-[:HOSTS]->(root:Column)
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
OPTIONAL MATCH (root)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc:FinalConsumer)
RETURN ss.name AS source_system, ss.criticality AS declared_criticality,
       count(DISTINCT fc) AS consumers_affected,
       count(DISTINCT CASE WHEN fc.type = 'Regulatory' THEN fc END) AS regulatory_consumers_affected
ORDER BY regulatory_consumers_affected DESC, consumers_affected DESC;


// -------------------------------------------------------------------------------------
// 4. CASOS ESPECIALES DEL MODELO (el motivo de que `Column`/`TRANSFORMS_TO` sean como son)
//    ➖ MATERIAL DE APOYO: no se usa en la demo (para no entrar en el detalle de cómo se modelan los datos
//       sintéticos) y no se ha probado en Aura. Se conserva por si un cliente pregunta por casos concretos.
// -------------------------------------------------------------------------------------

// 4.a · Fórmulas multi-origen: mismo job + misma expresión repartida en N aristas
//       (un CASE WHEN con 3 columnas de entrada de 2 tablas distintas = RISK_MART.EXPOSURE.RATING_BUCKET)
MATCH (s:Column)-[t:TRANSFORMS_TO]->(tgt:Column)
WITH tgt, t.scenario AS job, t.transformation_expression AS expression, collect(s.fqn) AS sources
WHERE size(sources) > 1 AND expression CONTAINS 'CASE WHEN'
RETURN tgt.fqn AS target, job, size(sources) AS n_sources, sources, expression
ORDER BY n_sources DESC, target;

// 4.b · Valores fijos (kind = CONSTANT) y referencias a tabla completa (kind = TABLE)
//       CONSTANT → is_synthetic_source = true; TABLE → COUNT(*) sin columna concreta
MATCH (c:Column) WHERE c.kind IN ['CONSTANT', 'TABLE']
MATCH (c)-[t:TRANSFORMS_TO]->(tgt:Column)
RETURN c.kind AS kind, c.fqn AS source, t.transformation_expression AS expression,
       t.is_synthetic_source AS is_synthetic_source, tgt.fqn AS target, t.scenario AS job
ORDER BY kind, source, target;

// 4.c · Filtros aplicados en origen (modelados aparte de la expresión)
MATCH (s:Column)-[t:TRANSFORMS_TO]->(tgt:Column)
WHERE size(t.filters) > 0
RETURN t.scenario AS job, t.filters AS filters, count(*) AS edges_with_filter
ORDER BY job;


// -------------------------------------------------------------------------------------
// 5. CRITICIDAD POR ALCANCE — dónde duele más que algo falle
//    Aquí se CUENTA hasta dónde llega cada nodo (fan-out aguas abajo). No es centralidad de grafo:
//    para "por dónde pasan más caminos" (betweenness) o "de qué depende todo" (PageRank) ver
//    03_zonas_muertas_gds.cypher, parte D.
// -------------------------------------------------------------------------------------

// 5 · Jobs por consumidores finales que dependen de ellos (cuántos informes mueren si ese job se cae)
//     ▣ DASHBOARD · «3. #Reports Affected if a Job Fails» — BAR CHART horizontal
//       Category = job · Value = consumers_depending SOLO (no selecciones `annual_cost_eur`: otra escala).
//       Orden ASCENDENTE (como en el dashboard): arriba quedan los jobs sin ningún informe, que salen sin barra →
//       gancho al ángulo 3 (zonas muertas). Caben todos sin LIMIT (13 jobs; 14 con el bloque B de 01 cargado).
MATCH (j:EtlJob)
OPTIONAL MATCH ()-[t:TRANSFORMS_TO {scenario: j.name}]->(out:Column)
OPTIONAL MATCH (out)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc:FinalConsumer)
RETURN j.name AS job, j.status AS status, j.estimated_compute_cost AS annual_cost_eur,
       count(DISTINCT fc) AS consumers_depending
ORDER BY consumers_depending ASC, annual_cost_eur DESC;


// -------------------------------------------------------------------------------------
// 6. TRAZABILIDAD BCBS 239 — por informe regulatorio: ¿hasta dónde llega la traza y quién responde?
// -------------------------------------------------------------------------------------

// 6.a · Por informe regulatorio: nº de columnas origen, sistemas, jobs implicados
//       ▣ DASHBOARD · «4. Regulatory Report Data» · query SIN cambios — TABLA (con la lista `jobs`)
//         Es la tarjeta más cercana al lenguaje del cliente: informe, normativa y cuántos orígenes, sistemas y
//         jobs hay detrás. Estilo aplicado: escala de blanco a rojo sobre `origin_columns` (de 1 a 20).
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

// 6.b · Brechas de accountability: jobs SIN propietario cuyas salidas son (o no) consumidas por un informe
//       Un job sin dueño y sin consumidor es candidato a retirada; sin dueño y CON consumidor regulatorio
//       es un incumplimiento. En el dataset de ejemplo el primer caso es LEGACY_BRANCH_REPORT.
//       ▣ DASHBOARD · «5. Accountability Gaps» · query SIN cambios — TABLA pequeña (1 fila en el dataset de ejemplo).
//         Estilo aplicado: `regulatory_consumers_served` en amarillo cuando vale 0 (candidato a retirada, no
//         incumplimiento). Con una sola fila el efecto es "esto no debería existir".
MATCH (j:EtlJob)
WHERE NOT EXISTS { MATCH (j)-[:MAINTAINED_BY]->(:Owner) }
OPTIONAL MATCH ()-[t:TRANSFORMS_TO {scenario: j.name}]->(out:Column)
OPTIONAL MATCH (out)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(fc:FinalConsumer)
RETURN j.name AS ownerless_job, j.status AS status, collect(DISTINCT fc.name) AS consumers_served,
       count(DISTINCT CASE WHEN fc.type = 'Regulatory' THEN fc END) AS regulatory_consumers_served;
