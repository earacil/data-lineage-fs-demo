// =====================================================================================
// 03_zonas_muertas_gds.cypher — Ángulo 3: zonas muertas con GDS (+ fallback en Cypher puro)
// Demo de Data Lineage para Financial Services · AuraDB + Aura Graph Analytics (GDS serverless)
//
// ⚠️  NO VALIDADO contra una instancia Aura real (ver CONTEXTO_IA.md, restricción 4). Las llamadas
//     `gds.*` de las partes 0, A y B dependen de la versión de GDS/AGA desplegada y de la API Cypher de
//     Aura Graph Analytics (doc consultada el 22-oct-2026). Si algo falla, la PARTE C (Cypher puro) da
//     el mismo resultado sin sesión.
//
// PRERREQUISITOS
//   · Dataset cargado con data/00_load_live.cypher.
//   · Aura Graph Analytics activado y parámetros definidos en el Query tool → ver ../AURA_SETUP.md
//       :param sessionName   => 'lineage-demo'
//       :param sessionMemory => '2GB'
//       :param sessionTtl    => duration({hours: 2})
//       :param sessionId     => '<id devuelto por el paso 0.2>'
//
// CÓMO FUNCIONA AGA (por qué difiere de un plugin GDS clásico)
//   El algoritmo NO corre en la base de datos: corre en una SESIÓN efímera y aislada. Hay que (1) crear la
//   sesión, (2) PROYECTAR el grafo a la sesión (los `gds.graph.project` clásicos con mapas por tipo y los
//   `gds.graph.project.cypher` no están soportados), (3) ejecutar los algoritmos y (4) borrar la sesión.
//   Los `nodeId` que devuelven los algoritmos son los ids de nodo de la BD: se vuelve a los nodos con
//   `MATCH (n) WHERE id(n) = nodeId` (`gds.util.asNode` no se usa porque no está garantizado en sesiones).
//   `id()` está deprecado en Neo4j 5 pero es lo que GDS espera aquí.
//
// DEFINICIÓN (ver data-model/SCHEMA.md)
//   Zona muerta = Column (o EtlJob) sin NINGUNA ruta dirigida hasta un FinalConsumer.
//   Una columna está VIVA si:  (c)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer)
//   Un job está MUERTO si ninguna de sus columnas de salida está viva (salidas = destinos de las
//   TRANSFORMS_TO cuyo `scenario` es el `name` del job).
//
// RESULTADO ESPERADO EN EL DATASET DE EJEMPLO (8 columnas muertas, 2 jobs muertos, 127.000 €/año)
//   Zona 1 · aislada          LEGACY_DM.BRANCH_MONTHLY.{BRANCH_ID,TOTAL_DEPOSITS,TOTAL_LOANS}
//                             → LEGACY_RPT.BRANCH_SUMMARY.{BRANCH_ID,NET_POSITION}
//                             job LEGACY_BRANCH_REPORT (Deprecated, sin propietario)
//   Zona 2 · rama de dato vivo STG.STG_CUSTOMER.SEGMENT_CODE (VIVO) → MKT_STG.PROMO.TARGET_SEGMENT → PROMO_SCORE
//                             job PROMO_SEGMENT_EXTRACT (Active, pero nadie consume su salida)
//   Zona 3 · rama de dato vivo STG.STG_LOAN.DRAWN_AMOUNT (VIVO) → RISK_MART.EXPOSURE.EXPOSURE_ADJ_LEGACY
//                             dentro de CALC_EXPOSURE, que SÍ está vivo (una columna muerta en un job vivo)
//
// ESTRUCTURA
//   0. Sesión AGA: estimar, crear, anotar sessionId
//   A. BFS en reversa desde FinalConsumer (proyección Cypher con la dirección invertida)
//   B. Por qué un componente conexo (WCC) NO basta (sólo ve la zona 1)
//   Z. Borrar la sesión
//   C. Cypher puro: fallback / verificación cruzada, y el informe de negocio (jobs, ahorro, sistemas)
// =====================================================================================


// =====================================================================================
// PARTE 0 · SESIÓN AGA  (hacerlo ~5 min antes del bloque; ver ../AURA_SETUP.md §4)
// =====================================================================================

// 0.1 · (Opcional) ¿Qué tamaño de sesión hace falta? Grafo proyectado: 87 nodos, 91 relaciones.
CALL gds.session.estimate(87, 91, {algorithmCategories: ['path-finding', 'community-detection']})
YIELD estimatedMemory, recommendedSize
RETURN estimatedMemory, recommendedSize;

// 0.2 · Crear (o reutilizar) la sesión. Estado `Creating` → `Ready`. COPIA el `id` y ejecuta:
//         :param sessionId => '<id>'
CALL gds.session.getOrCreate($sessionName, $sessionMemory, $sessionTtl)
YIELD id, name, status, memory, expiryDate, errorMessage
RETURN id, name, status, memory, expiryDate, errorMessage;

// 0.3 · Si no recuerdas el id, o para comprobar el estado (debe ser `Ready`)
CALL gds.session.list()
YIELD id, name, status, memory, ttl, expiryDate
WHERE name = $sessionName
RETURN id, name, status, memory, ttl, expiryDate;


// =====================================================================================
// PARTE A · BFS EN REVERSA DESDE LOS CONSUMIDORES FINALES
// Idea: proyectamos Column + FinalConsumer INVIRTIENDO la dirección de TRANSFORMS_TO y FEEDS. Un BFS desde
// cada FinalConsumer recorre entonces TODO su linaje aguas arriba; la unión de lo visitado es "lo vivo".
// Lo que no se visita, está muerto.
// En AGA la orientación por tipo no se puede indicar en la proyección nativa, así que la inversión se hace
// en la proyección Cypher: el destino de la arista real (b) pasa a ser el ORIGEN en la sesión.
// =====================================================================================

// A.1 · Proyección Cypher hacia la sesión, con la dirección invertida
//       esperado: 87 nodos (81 Column + 6 FinalConsumer) y 91 relaciones (66 TRANSFORMS_TO + 25 FEEDS)
//       (si tu versión devuelve la proyección como columna `graphName`/`nodeCount`, lo verás en el resultado;
//        si no, comprueba el recuento con el paso A.1b)
CYPHER runtime=parallel
MATCH (a)-[r:TRANSFORMS_TO|FEEDS]->(b)
RETURN gds.graph.project(
  'lineage_rev',
  b,                                   // ← origen en la sesión = destino real
  a,                                   // ← destino en la sesión = origen real
  {
    sourceNodeLabels: labels(b),
    targetNodeLabels: labels(a),
    relationshipType: type(r)
  },
  {sessionId: $sessionId}
) AS projection;

// A.1b · Comprobar qué hay en la sesión
CALL gds.graph.list('lineage_rev')
YIELD graphName, nodeCount, relationshipCount
RETURN graphName, nodeCount, relationshipCount;

// A.2 · BFS desde cada FinalConsumer (gds.bfs.stream acepta UN solo nodo origen → se ejecuta por consumidor)
//       Columnas muertas = las no visitadas por ninguno.
//       Si tu entorno no admite un CALL de procedimiento GDS dentro de un subquery, usa A.2b por consumidor
//       o salta a la PARTE C.
MATCH (fc:FinalConsumer)
CALL (fc) {
  CALL gds.bfs.stream('lineage_rev', {sourceNode: id(fc)})
  YIELD nodeIds
  UNWIND nodeIds AS nodeId
  RETURN DISTINCT nodeId
}
WITH collect(DISTINCT nodeId) AS live_ids
MATCH (c:Column)
WHERE NOT id(c) IN live_ids
OPTIONAL MATCH (ss:SourceSystem)-[:HOSTS]->(c)
RETURN c.fqn AS dead_column, ss.name AS hosted_in
ORDER BY dead_column;                                  // esperado: 8 filas

// A.2b · El mismo BFS para UN informe (útil para narrar "cada informe tiene su árbol de linaje")
//        esperado para 'Solvency Report': 23 columnas en su linaje (calculado sobre los CSV)
MATCH (fc:FinalConsumer {name: 'Solvency Report'})                                                  // ← CAMBIA
CALL gds.bfs.stream('lineage_rev', {sourceNode: id(fc)})
YIELD nodeIds
UNWIND nodeIds AS nodeId
MATCH (n:Column) WHERE id(n) = nodeId
RETURN fc.name AS consumer, count(DISTINCT n) AS columns_in_lineage;


// =====================================================================================
// PARTE B · POR QUÉ UN COMPONENTE CONEXO NO BASTA
// WCC (componentes débilmente conexos) detecta islas completas, pero una rama muerta que se bifurca de un
// dato vivo pertenece al MISMO componente que sus consumidores. Sólo la detección a nivel de ruta (parte A)
// encuentra las zonas 2 y 3.
// =====================================================================================

// B.0 · Proyección nativa no dirigida (en AGA: etiquetas/tipos como lista + configuración global)
//       esperado: 87 nodos, 182 relaciones (cada arista no dirigida cuenta dos veces)
CALL gds.graph.project(
  'lineage_undirected',
  ['Column', 'FinalConsumer'],
  ['TRANSFORMS_TO', 'FEEDS'],
  {undirectedRelationshipTypes: ['*'], sessionId: $sessionId}
)
YIELD graphName, nodeCount, relationshipCount, projectMillis
RETURN graphName, nodeCount, relationshipCount, projectMillis;

// B.1 · Componentes y cuántos FinalConsumer contiene cada uno
//       esperado: 2 componentes. El grande (con los 6 consumidores) y la isla legacy (5 columnas, 0 consumidores).
CALL gds.wcc.stream('lineage_undirected')
YIELD nodeId, componentId
MATCH (n) WHERE id(n) = nodeId
WITH componentId, collect(n) AS members
RETURN componentId,
       size(members) AS size,
       size([m IN members WHERE m:FinalConsumer]) AS final_consumers,
       [m IN members WHERE m:Column | m.fqn][..3] AS sample_columns
ORDER BY final_consumers ASC;

// B.2 · Veredicto: con WCC sólo "se ven" 5 columnas muertas (la isla). Las 3 restantes están DENTRO del
//       componente grande: están conectadas a datos vivos, pero no llegan a ningún consumidor.
CALL gds.wcc.stream('lineage_undirected')
YIELD nodeId, componentId
MATCH (n) WHERE id(n) = nodeId
WITH componentId, collect(n) AS members
WHERE size([m IN members WHERE m:FinalConsumer]) = 0
UNWIND [m IN members WHERE m:Column] AS c
RETURN 'WCC detecta' AS method, c.fqn AS dead_column
ORDER BY dead_column;


// =====================================================================================
// PARTE Z · BORRAR LA SESIÓN (deja de facturar y libera las proyecciones; el grafo de la BD no se toca)
// =====================================================================================

CALL gds.session.delete($sessionName)
YIELD deleted
RETURN deleted;


// =====================================================================================
// PARTE C · CYPHER PURO — FALLBACK, VERIFICACIÓN CRUZADA E INFORME DE NEGOCIO
// Sin GDS. Equivale a A.2. Usa EXISTS { } con camino variable sin cota superior (*0..): válido porque el
// linaje es un DAG; en grafos muy grandes conviene acotar (*0..20) o materializar el resultado (ver
// 04_productivizacion.md).
// =====================================================================================

// C.1 · Columnas muertas (debe coincidir con A.2) + clasificación de la zona
//       · "isolated zone"  → ningún ancestro vivo: no cuelga de nada que se use
//       · "dead branch"    → algún ancestro está vivo: se bifurca de un dato vivo (el caso difícil)
MATCH (c:Column)
WHERE NOT EXISTS { MATCH (c)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
OPTIONAL MATCH (ss:SourceSystem)-[:HOSTS]->(c)
RETURN c.fqn AS dead_column,
       ss.name AS hosted_in,
       CASE WHEN EXISTS {
              MATCH (anc:Column)-[:TRANSFORMS_TO*1..]->(c)
              WHERE EXISTS { MATCH (anc)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
            }
            THEN 'dead branch (forks from live data)'
            ELSE 'isolated zone'
       END AS zone_type
ORDER BY zone_type, dead_column;

// C.2 · Puntos de bifurcación: dónde un dato VIVO empieza a alimentar una rama MUERTA
//       (la pieza de información más accionable: "corta aquí")
MATCH (live:Column)-[t:TRANSFORMS_TO]->(dead:Column)
WHERE EXISTS { MATCH (live)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
  AND NOT EXISTS { MATCH (dead)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
RETURN live.fqn AS live_column, t.scenario AS job, t.transformation_expression AS expression, dead.fqn AS dead_column;

// C.3 · Visual: ruta muerta junto a su ancestro vivo (para Browser/Bloom)
MATCH p = (live:Column)-[:TRANSFORMS_TO]->(dead:Column)-[:TRANSFORMS_TO*0..]->(:Column)
WHERE EXISTS { MATCH (live)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
  AND NOT EXISTS { MATCH (dead)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
RETURN p;

// C.4 · Jobs muertos = candidatos a retirada, con coste y propietario
//       (LEGACY_BRANCH_REPORT no devuelve propietario: segunda razón para retirarlo)
MATCH (j:EtlJob)
WHERE NOT EXISTS {
  MATCH (:Column)-[t:TRANSFORMS_TO]->(out:Column)
  WHERE t.scenario = j.name
    AND EXISTS { MATCH (out)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
}
OPTIONAL MATCH (j)-[:MAINTAINED_BY]->(o:Owner)
RETURN j.name AS dead_job, j.status AS status, j.frequency AS frequency,
       j.estimated_compute_cost AS annual_cost_eur, collect(o.name) AS owners
ORDER BY annual_cost_eur DESC;

// C.5 · Ahorro potencial total (€ / año) por retirar los jobs muertos      esperado: 127000
MATCH (j:EtlJob)
WHERE NOT EXISTS {
  MATCH (:Column)-[t:TRANSFORMS_TO]->(out:Column)
  WHERE t.scenario = j.name
    AND EXISTS { MATCH (out)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
}
RETURN count(j) AS dead_jobs, sum(j.estimated_compute_cost) AS potential_annual_saving_eur;

// C.6 · Columnas muertas DENTRO de jobs vivos (limpieza parcial: el job se queda, la columna sobra)
//       esperado: CALC_EXPOSURE → RISK_MART.EXPOSURE.EXPOSURE_ADJ_LEGACY
MATCH (j:EtlJob)
WHERE EXISTS {
  MATCH (:Column)-[t:TRANSFORMS_TO]->(out:Column)
  WHERE t.scenario = j.name
    AND EXISTS { MATCH (out)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
}
MATCH (:Column)-[t2:TRANSFORMS_TO {scenario: j.name}]->(dead:Column)
WHERE NOT EXISTS { MATCH (dead)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
RETURN j.name AS live_job_with_dead_output, collect(DISTINCT dead.fqn) AS dead_columns;

// C.7 · Salud por sistema: % de columnas vivas. Un sistema con 0 % vivo es candidato a decommission.
//       esperado: Legacy Data Mart → 0 de 5 vivas
MATCH (ss:SourceSystem)-[:HOSTS]->(c:Column)
WITH ss, c, EXISTS { MATCH (c)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) } AS is_live
WITH ss, count(c) AS hosted_columns, sum(CASE WHEN is_live THEN 1 ELSE 0 END) AS live_columns
RETURN ss.name AS source_system, ss.criticality AS criticality, hosted_columns, live_columns,
       hosted_columns - live_columns AS dead_columns,
       round(100.0 * live_columns / hosted_columns, 1) AS pct_live
ORDER BY pct_live ASC, hosted_columns DESC;
