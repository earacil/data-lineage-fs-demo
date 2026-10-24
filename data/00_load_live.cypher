// =====================================================================================
// 00_load_live.cypher — carga del dataset sintético, segmentada por proyecto ETL
// Demo de Data Lineage para Financial Services · Neo4j 5.x
//
// ⚠️  NO VALIDADO contra una instancia Neo4j real hasta que alguien lo ejecute en Aura/Desktop
//     (ver CONTEXTO_IA.md, restricción 4). Tratar como "a validar".
//
// CÓMO USARLO (detalle completo en ../AURA_SETUP.md)
//   1. Define de dónde se leen los CSV (una sola vez por sesión del Query tool; cada :param se ejecuta
//      por separado y NO sobrevive a un refresco de la página):
//        Aura (caso de esta demo): los CSV se leen de GitHub. El repositorio debe ser público.
//            :param baseUrl => 'https://raw.githubusercontent.com/<owner>/<repo>/<ref>/data/'
//            (con la `/` final; <ref> = rama, o mejor etiqueta/SHA para evitar la caché de raw.githubusercontent.com)
//        Neo4j Desktop / Docker / local (alternativa): copiar data/*.csv a la carpeta `import/` y usar
//            :param baseUrl => 'file:///'
//      Prueba de humo (debe devolver 7):
//            LOAD CSV WITH HEADERS FROM $baseUrl + 'owners.csv' AS row RETURN count(row);
//   2. Ejecuta el segmento 0 (restricciones + datos maestros) y luego los segmentos P1..P5 EN ORDEN,
//      narrando cada uno. Cada segmento es idempotente (MERGE): se puede repetir sin duplicar.
//      Si el editor sólo ejecuta una sentencia por vez, ve sentencia a sentencia (separadas por `;`).
//
// IDEAS PARA NARRAR EN VIVO
//   · Tras P1 + P2 el grafo tiene dos "islas": ingesta core y riesgo de crédito (ya conectadas
//     entre sí porque P2 lee `STG.STG_LOAN.*`, columnas escritas por P1).
//   · P3 (reporting regulatorio) NO trae ninguna columna de riesgo en su carga: sus transformaciones
//     leen `RISK_MART.*`, que ya existe por P2. El MERGE por `fqn` conecta los dos proyectos solo.
//   · P5 añade las "zonas muertas": se cargan igual que todo lo demás — el grafo no sabe que sobran
//     hasta que se pregunta (ver queries/03_zonas_muertas_gds.cypher).
//
// COLUMNAS AUXILIARES `load_batch`: sólo sirven para segmentar la carga; no se guardan en el grafo.
// =====================================================================================


// -------------------------------------------------------------------------------------
// SEGMENTO 0 · Restricciones y datos maestros (sistemas, propietarios, consumidores finales)
// -------------------------------------------------------------------------------------

CREATE CONSTRAINT column_fqn IF NOT EXISTS FOR (c:Column) REQUIRE c.fqn IS UNIQUE;
CREATE CONSTRAINT source_system_id IF NOT EXISTS FOR (s:SourceSystem) REQUIRE s.id IS UNIQUE;
CREATE CONSTRAINT etl_job_id IF NOT EXISTS FOR (j:EtlJob) REQUIRE j.id IS UNIQUE;
CREATE CONSTRAINT etl_job_name IF NOT EXISTS FOR (j:EtlJob) REQUIRE j.name IS UNIQUE;
CREATE CONSTRAINT final_consumer_id IF NOT EXISTS FOR (f:FinalConsumer) REQUIRE f.id IS UNIQUE;
CREATE CONSTRAINT owner_id IF NOT EXISTS FOR (o:Owner) REQUIRE o.id IS UNIQUE;
// Deduplicación de aristas por el hash propio `id` (no el id interno de Neo4j)
CREATE CONSTRAINT transforms_to_id IF NOT EXISTS FOR ()-[t:TRANSFORMS_TO]-() REQUIRE t.id IS UNIQUE;

LOAD CSV WITH HEADERS FROM $baseUrl + 'source_systems.csv' AS row
MERGE (s:SourceSystem {id: row.id})
SET s.name = row.name,
    s.technology = row.technology,
    s.type = row.type,
    s.criticality = row.criticality;

LOAD CSV WITH HEADERS FROM $baseUrl + 'owners.csv' AS row
MERGE (o:Owner {id: row.id})
SET o.name = row.name,
    o.role = row.role;

LOAD CSV WITH HEADERS FROM $baseUrl + 'final_consumers.csv' AS row
MERGE (f:FinalConsumer {id: row.id})
SET f.name = row.name,
    f.type = row.type,
    f.regulation = row.regulation,
    f.periodicity = row.periodicity;


// =====================================================================================
// SEGMENTOS POR PROYECTO ETL
// Patrón de cada segmento (7 sentencias):
//   a) EtlJob   b) Column   c) HOSTS   d) TRANSFORMS_TO   e) PROCESSES   f) FEEDS   g) MAINTAINED_BY
// =====================================================================================


// -------------------------------------------------------------------------------------
// P1 · Ingesta core banking y CRM  →  capa staging (STG)
// Jobs: LOAD_CORE_ACCOUNTS, LOAD_CORE_LOANS, LOAD_CRM_CUSTOMERS
// -------------------------------------------------------------------------------------

// P1.a · Jobs
LOAD CSV WITH HEADERS FROM $baseUrl + 'etl_jobs.csv' AS row
WITH row WHERE row.load_batch = 'P1'
MERGE (j:EtlJob {id: row.id})
SET j.name = row.name,
    j.frequency = row.frequency,
    j.owning_team = row.owning_team,
    j.estimated_compute_cost = toInteger(row.estimated_compute_cost),
    j.status = row.status;

// P1.b · Columnas (MERGE por fqn: si la columna ya existía por otro proyecto, se reutiliza)
LOAD CSV WITH HEADERS FROM $baseUrl + 'columns.csv' AS row
WITH row WHERE row.load_batch = 'P1'
MERGE (c:Column {fqn: row.fqn})
SET c.name = row.name,
    c.kind = row.kind,
    c.data_type = row.data_type,
    c.field_type = row.field_type,
    c.field_type_evidence = row.field_type_evidence;

// P1.c · Dónde vive físicamente cada columna
LOAD CSV WITH HEADERS FROM $baseUrl + 'hosts.csv' AS row
WITH row WHERE row.load_batch = 'P1'
MATCH (s:SourceSystem {id: row.source_system_id})
MATCH (c:Column {fqn: row.column_fqn})
MERGE (s)-[:HOSTS]->(c);

// P1.d · Linaje a nivel columna
LOAD CSV WITH HEADERS FROM $baseUrl + 'transforms_to.csv' AS row
WITH row WHERE row.load_batch = 'P1'
MATCH (src:Column {fqn: row.source_fqn})
MATCH (tgt:Column {fqn: row.target_fqn})
MERGE (src)-[t:TRANSFORMS_TO {id: row.id}]->(tgt)
SET t.scenario = row.scenario,
    t.transformation_expression = row.transformation_expression,
    t.filters = CASE WHEN coalesce(row.filters, '') = '' THEN [] ELSE split(row.filters, '|') END,
    t.is_synthetic_source = (row.is_synthetic_source = 'true');

// P1.e · Qué job toca qué columna
LOAD CSV WITH HEADERS FROM $baseUrl + 'processes.csv' AS row
WITH row WHERE row.load_batch = 'P1'
MATCH (j:EtlJob {id: row.job_id})
MATCH (c:Column {fqn: row.column_fqn})
MERGE (j)-[:PROCESSES]->(c);

// P1.f · Consumo final
LOAD CSV WITH HEADERS FROM $baseUrl + 'feeds.csv' AS row
WITH row WHERE row.load_batch = 'P1'
MATCH (c:Column {fqn: row.column_fqn})
MATCH (f:FinalConsumer {id: row.consumer_id})
MERGE (c)-[:FEEDS]->(f);

// P1.g · Responsables
LOAD CSV WITH HEADERS FROM $baseUrl + 'maintained_by.csv' AS row
WITH row WHERE row.load_batch = 'P1'
MATCH (j:EtlJob {id: row.job_id})
MATCH (o:Owner {id: row.owner_id})
MERGE (j)-[:MAINTAINED_BY]->(o);


// -------------------------------------------------------------------------------------
// P2 · Riesgo de crédito (exposición y RWA)
// Jobs: LOAD_RISK_RATINGS, CALC_EXPOSURE, CALC_RWA
// Conexión con P1: CALC_EXPOSURE lee STG.STG_LOAN.* (columnas creadas en P1)
// -------------------------------------------------------------------------------------

// P2.a · Jobs
LOAD CSV WITH HEADERS FROM $baseUrl + 'etl_jobs.csv' AS row
WITH row WHERE row.load_batch = 'P2'
MERGE (j:EtlJob {id: row.id})
SET j.name = row.name,
    j.frequency = row.frequency,
    j.owning_team = row.owning_team,
    j.estimated_compute_cost = toInteger(row.estimated_compute_cost),
    j.status = row.status;

// P2.b · Columnas
LOAD CSV WITH HEADERS FROM $baseUrl + 'columns.csv' AS row
WITH row WHERE row.load_batch = 'P2'
MERGE (c:Column {fqn: row.fqn})
SET c.name = row.name,
    c.kind = row.kind,
    c.data_type = row.data_type,
    c.field_type = row.field_type,
    c.field_type_evidence = row.field_type_evidence;

// P2.c · HOSTS
LOAD CSV WITH HEADERS FROM $baseUrl + 'hosts.csv' AS row
WITH row WHERE row.load_batch = 'P2'
MATCH (s:SourceSystem {id: row.source_system_id})
MATCH (c:Column {fqn: row.column_fqn})
MERGE (s)-[:HOSTS]->(c);

// P2.d · TRANSFORMS_TO (aquí aparecen las aristas que cruzan de P1 a P2 y el CASE WHEN de 3 orígenes)
LOAD CSV WITH HEADERS FROM $baseUrl + 'transforms_to.csv' AS row
WITH row WHERE row.load_batch = 'P2'
MATCH (src:Column {fqn: row.source_fqn})
MATCH (tgt:Column {fqn: row.target_fqn})
MERGE (src)-[t:TRANSFORMS_TO {id: row.id}]->(tgt)
SET t.scenario = row.scenario,
    t.transformation_expression = row.transformation_expression,
    t.filters = CASE WHEN coalesce(row.filters, '') = '' THEN [] ELSE split(row.filters, '|') END,
    t.is_synthetic_source = (row.is_synthetic_source = 'true');

// P2.e · PROCESSES
LOAD CSV WITH HEADERS FROM $baseUrl + 'processes.csv' AS row
WITH row WHERE row.load_batch = 'P2'
MATCH (j:EtlJob {id: row.job_id})
MATCH (c:Column {fqn: row.column_fqn})
MERGE (j)-[:PROCESSES]->(c);

// P2.f · FEEDS
LOAD CSV WITH HEADERS FROM $baseUrl + 'feeds.csv' AS row
WITH row WHERE row.load_batch = 'P2'
MATCH (c:Column {fqn: row.column_fqn})
MATCH (f:FinalConsumer {id: row.consumer_id})
MERGE (c)-[:FEEDS]->(f);

// P2.g · MAINTAINED_BY
LOAD CSV WITH HEADERS FROM $baseUrl + 'maintained_by.csv' AS row
WITH row WHERE row.load_batch = 'P2'
MATCH (j:EtlJob {id: row.job_id})
MATCH (o:Owner {id: row.owner_id})
MERGE (j)-[:MAINTAINED_BY]->(o);


// -------------------------------------------------------------------------------------
// P3 · Reporting regulatorio (COREP / FINREP)
// Jobs: BUILD_COREP_SOLVENCY, BUILD_FINREP_BALANCE
// Conexión con P1 y P2: lee RISK_MART.* (P2) y STG.STG_ACCOUNT.* (P1) SIN que este lote los defina.
// Incluye el caso CONSTANT ('EUR') y los casos TABLE (COUNT(*)).
// -------------------------------------------------------------------------------------

// P3.a · Jobs
LOAD CSV WITH HEADERS FROM $baseUrl + 'etl_jobs.csv' AS row
WITH row WHERE row.load_batch = 'P3'
MERGE (j:EtlJob {id: row.id})
SET j.name = row.name,
    j.frequency = row.frequency,
    j.owning_team = row.owning_team,
    j.estimated_compute_cost = toInteger(row.estimated_compute_cost),
    j.status = row.status;

// P3.b · Columnas
LOAD CSV WITH HEADERS FROM $baseUrl + 'columns.csv' AS row
WITH row WHERE row.load_batch = 'P3'
MERGE (c:Column {fqn: row.fqn})
SET c.name = row.name,
    c.kind = row.kind,
    c.data_type = row.data_type,
    c.field_type = row.field_type,
    c.field_type_evidence = row.field_type_evidence;

// P3.c · HOSTS
LOAD CSV WITH HEADERS FROM $baseUrl + 'hosts.csv' AS row
WITH row WHERE row.load_batch = 'P3'
MATCH (s:SourceSystem {id: row.source_system_id})
MATCH (c:Column {fqn: row.column_fqn})
MERGE (s)-[:HOSTS]->(c);

// P3.d · TRANSFORMS_TO
LOAD CSV WITH HEADERS FROM $baseUrl + 'transforms_to.csv' AS row
WITH row WHERE row.load_batch = 'P3'
MATCH (src:Column {fqn: row.source_fqn})
MATCH (tgt:Column {fqn: row.target_fqn})
MERGE (src)-[t:TRANSFORMS_TO {id: row.id}]->(tgt)
SET t.scenario = row.scenario,
    t.transformation_expression = row.transformation_expression,
    t.filters = CASE WHEN coalesce(row.filters, '') = '' THEN [] ELSE split(row.filters, '|') END,
    t.is_synthetic_source = (row.is_synthetic_source = 'true');

// P3.e · PROCESSES
LOAD CSV WITH HEADERS FROM $baseUrl + 'processes.csv' AS row
WITH row WHERE row.load_batch = 'P3'
MATCH (j:EtlJob {id: row.job_id})
MATCH (c:Column {fqn: row.column_fqn})
MERGE (j)-[:PROCESSES]->(c);

// P3.f · FEEDS
LOAD CSV WITH HEADERS FROM $baseUrl + 'feeds.csv' AS row
WITH row WHERE row.load_batch = 'P3'
MATCH (c:Column {fqn: row.column_fqn})
MATCH (f:FinalConsumer {id: row.consumer_id})
MERGE (c)-[:FEEDS]->(f);

// P3.g · MAINTAINED_BY
LOAD CSV WITH HEADERS FROM $baseUrl + 'maintained_by.csv' AS row
WITH row WHERE row.load_batch = 'P3'
MATCH (j:EtlJob {id: row.job_id})
MATCH (o:Owner {id: row.owner_id})
MERGE (j)-[:MAINTAINED_BY]->(o);


// -------------------------------------------------------------------------------------
// P4 · Analítica retail (dashboard de gasto y modelo de churn)
// Jobs: LOAD_CARD_TRANSACTIONS, BUILD_EXPENSE_DASHBOARD, BUILD_CHURN_FEATURES
// Conexión con P1: reutiliza STG.STG_CUSTOMER.* y STG.STG_ACCOUNT.*
// -------------------------------------------------------------------------------------

// P4.a · Jobs
LOAD CSV WITH HEADERS FROM $baseUrl + 'etl_jobs.csv' AS row
WITH row WHERE row.load_batch = 'P4'
MERGE (j:EtlJob {id: row.id})
SET j.name = row.name,
    j.frequency = row.frequency,
    j.owning_team = row.owning_team,
    j.estimated_compute_cost = toInteger(row.estimated_compute_cost),
    j.status = row.status;

// P4.b · Columnas
LOAD CSV WITH HEADERS FROM $baseUrl + 'columns.csv' AS row
WITH row WHERE row.load_batch = 'P4'
MERGE (c:Column {fqn: row.fqn})
SET c.name = row.name,
    c.kind = row.kind,
    c.data_type = row.data_type,
    c.field_type = row.field_type,
    c.field_type_evidence = row.field_type_evidence;

// P4.c · HOSTS
LOAD CSV WITH HEADERS FROM $baseUrl + 'hosts.csv' AS row
WITH row WHERE row.load_batch = 'P4'
MATCH (s:SourceSystem {id: row.source_system_id})
MATCH (c:Column {fqn: row.column_fqn})
MERGE (s)-[:HOSTS]->(c);

// P4.d · TRANSFORMS_TO
LOAD CSV WITH HEADERS FROM $baseUrl + 'transforms_to.csv' AS row
WITH row WHERE row.load_batch = 'P4'
MATCH (src:Column {fqn: row.source_fqn})
MATCH (tgt:Column {fqn: row.target_fqn})
MERGE (src)-[t:TRANSFORMS_TO {id: row.id}]->(tgt)
SET t.scenario = row.scenario,
    t.transformation_expression = row.transformation_expression,
    t.filters = CASE WHEN coalesce(row.filters, '') = '' THEN [] ELSE split(row.filters, '|') END,
    t.is_synthetic_source = (row.is_synthetic_source = 'true');

// P4.e · PROCESSES
LOAD CSV WITH HEADERS FROM $baseUrl + 'processes.csv' AS row
WITH row WHERE row.load_batch = 'P4'
MATCH (j:EtlJob {id: row.job_id})
MATCH (c:Column {fqn: row.column_fqn})
MERGE (j)-[:PROCESSES]->(c);

// P4.f · FEEDS
LOAD CSV WITH HEADERS FROM $baseUrl + 'feeds.csv' AS row
WITH row WHERE row.load_batch = 'P4'
MATCH (c:Column {fqn: row.column_fqn})
MATCH (f:FinalConsumer {id: row.consumer_id})
MERGE (c)-[:FEEDS]->(f);

// P4.g · MAINTAINED_BY
LOAD CSV WITH HEADERS FROM $baseUrl + 'maintained_by.csv' AS row
WITH row WHERE row.load_batch = 'P4'
MATCH (j:EtlJob {id: row.job_id})
MATCH (o:Owner {id: row.owner_id})
MERGE (j)-[:MAINTAINED_BY]->(o);


// -------------------------------------------------------------------------------------
// P5 · Marketing y legado (aquí viven las zonas muertas)
// Jobs: PROMO_SEGMENT_EXTRACT (activo, sin consumidor), LEGACY_BRANCH_REPORT (deprecado, sin propietario)
// Conexión con P1: PROMO_SEGMENT_EXTRACT cuelga de STG.STG_CUSTOMER.SEGMENT_CODE (dato vivo).
// -------------------------------------------------------------------------------------

// P5.a · Jobs
LOAD CSV WITH HEADERS FROM $baseUrl + 'etl_jobs.csv' AS row
WITH row WHERE row.load_batch = 'P5'
MERGE (j:EtlJob {id: row.id})
SET j.name = row.name,
    j.frequency = row.frequency,
    j.owning_team = row.owning_team,
    j.estimated_compute_cost = toInteger(row.estimated_compute_cost),
    j.status = row.status;

// P5.b · Columnas
LOAD CSV WITH HEADERS FROM $baseUrl + 'columns.csv' AS row
WITH row WHERE row.load_batch = 'P5'
MERGE (c:Column {fqn: row.fqn})
SET c.name = row.name,
    c.kind = row.kind,
    c.data_type = row.data_type,
    c.field_type = row.field_type,
    c.field_type_evidence = row.field_type_evidence;

// P5.c · HOSTS
LOAD CSV WITH HEADERS FROM $baseUrl + 'hosts.csv' AS row
WITH row WHERE row.load_batch = 'P5'
MATCH (s:SourceSystem {id: row.source_system_id})
MATCH (c:Column {fqn: row.column_fqn})
MERGE (s)-[:HOSTS]->(c);

// P5.d · TRANSFORMS_TO
LOAD CSV WITH HEADERS FROM $baseUrl + 'transforms_to.csv' AS row
WITH row WHERE row.load_batch = 'P5'
MATCH (src:Column {fqn: row.source_fqn})
MATCH (tgt:Column {fqn: row.target_fqn})
MERGE (src)-[t:TRANSFORMS_TO {id: row.id}]->(tgt)
SET t.scenario = row.scenario,
    t.transformation_expression = row.transformation_expression,
    t.filters = CASE WHEN coalesce(row.filters, '') = '' THEN [] ELSE split(row.filters, '|') END,
    t.is_synthetic_source = (row.is_synthetic_source = 'true');

// P5.e · PROCESSES
LOAD CSV WITH HEADERS FROM $baseUrl + 'processes.csv' AS row
WITH row WHERE row.load_batch = 'P5'
MATCH (j:EtlJob {id: row.job_id})
MATCH (c:Column {fqn: row.column_fqn})
MERGE (j)-[:PROCESSES]->(c);

// P5.f · FEEDS (este lote no aporta ninguna arista FEEDS: es justo lo que lo hace "muerto")
LOAD CSV WITH HEADERS FROM $baseUrl + 'feeds.csv' AS row
WITH row WHERE row.load_batch = 'P5'
MATCH (c:Column {fqn: row.column_fqn})
MATCH (f:FinalConsumer {id: row.consumer_id})
MERGE (c)-[:FEEDS]->(f);

// P5.g · MAINTAINED_BY (LEGACY_BRANCH_REPORT no aparece: job huérfano de propietario)
LOAD CSV WITH HEADERS FROM $baseUrl + 'maintained_by.csv' AS row
WITH row WHERE row.load_batch = 'P5'
MATCH (j:EtlJob {id: row.job_id})
MATCH (o:Owner {id: row.owner_id})
MERGE (j)-[:MAINTAINED_BY]->(o);


// -------------------------------------------------------------------------------------
// VERIFICACIÓN POST-CARGA (esperado: 81 Column · 7 SourceSystem · 13 EtlJob · 6 FinalConsumer ·
// 7 Owner · 66 TRANSFORMS_TO · 81 HOSTS · 113 PROCESSES · 25 FEEDS · 14 MAINTAINED_BY)
// -------------------------------------------------------------------------------------

CALL { MATCH (n:Column) RETURN 'Column' AS item, count(n) AS total
  UNION ALL MATCH (n:SourceSystem) RETURN 'SourceSystem', count(n)
  UNION ALL MATCH (n:EtlJob) RETURN 'EtlJob', count(n)
  UNION ALL MATCH (n:FinalConsumer) RETURN 'FinalConsumer', count(n)
  UNION ALL MATCH (n:Owner) RETURN 'Owner', count(n)
  UNION ALL MATCH ()-[r:TRANSFORMS_TO]->() RETURN 'TRANSFORMS_TO', count(r)
  UNION ALL MATCH ()-[r:HOSTS]->() RETURN 'HOSTS', count(r)
  UNION ALL MATCH ()-[r:PROCESSES]->() RETURN 'PROCESSES', count(r)
  UNION ALL MATCH ()-[r:FEEDS]->() RETURN 'FEEDS', count(r)
  UNION ALL MATCH ()-[r:MAINTAINED_BY]->() RETURN 'MAINTAINED_BY', count(r)
}
RETURN item, total;
