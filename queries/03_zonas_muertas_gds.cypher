// =====================================================================================
// 03_zonas_muertas_gds.cypher — Ángulo 3: zonas muertas con GDS (+ cuellos de botella y Cypher puro)
// Demo de Data Lineage para Financial Services · AuraDB + Aura Graph Analytics (GDS serverless)
//
// ESTADO DE VALIDACIÓN (ver CONTEXTO_IA.md, restricción 4)
//   ✅ Validado en Aura por el autor (26-oct-2026): partes A, B, C, Z y D completas (incluidas D.2 y D.3), con sesión
//      AGA implícita. D.1, D.4, D.5 (variante de una sola columna), D.6 y D.7 corren además en el dashboard
//      «Data Lineage Dead Zones». Las cifras «esperado» de betweenness salen de un cálculo en Python, no de GDS.
//      Cualquier cambio posterior vuelve a ser "a validar".
//   Si algo de GDS falla, la PARTE D da el mismo resultado sin sesión.
//
// PRERREQUISITOS
//   · Dataset cargado con data/00_load_live.cypher.
//   · Aura Graph Analytics activado en la organización (ver ../AURA_SETUP.md). NO hacen falta parámetros ni
//     un paso previo de sesión: se usa una SESIÓN IMPLÍCITA (ver abajo).
//
// CÓMO FUNCIONA AGA (por qué difiere de un plugin GDS clásico)
//   El algoritmo NO corre en la base de datos: corre en una SESIÓN efímera y aislada. Aquí la sesión es
//   IMPLÍCITA: la primera proyección (`gds.graph.project(..., {memory: '2GB'})`) crea la sesión por su cuenta, y la
//   sesión se elimina cuando se borran todos sus grafos proyectados (parte Z). Flujo: (1) PROYECTAR el grafo,
//   (2) ejecutar algoritmos, (3) borrar las proyecciones. Se factura por minuto (mínimo 10 min por sesión).
//   Los `nodeId` que devuelven los algoritmos son los ids de nodo de la BD: se vuelve a los nodos con
//   `MATCH (n) WHERE id(n) = nodeId` (`gds.util.asNode` no se usa porque no está garantizado en sesiones).
//   `id()` está deprecado en Neo4j 5 pero es lo que GDS espera aquí.
//
// QUÉ SIGNIFICA «MUERTO»
//   Un FinalConsumer es el FINAL de la cadena: un informe regulatorio, un dashboard o un modelo que alguien
//   usa. Un dato está VIVO si, siguiendo las flechas desde él, se llega a algún FinalConsumer; está MUERTO si
//   no se llega a ninguno: se carga, se transforma y se paga, pero nadie lo recibe.
//     · Columna muerta = Column sin NINGUNA ruta dirigida hasta un FinalConsumer.
//         Viva si:  (c)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer)
//     · Job muerto = ninguna de sus columnas de salida está viva (salidas = destinos de las TRANSFORMS_TO
//       cuyo `scenario` es el `name` del job). Es un job que produce datos que nadie consume.
//   Ojo, "muerto" NO significa que el job falle ni que el dato sea incorrecto. Significa «según el grafo,
//   ningún consumidor declarado depende de esto». Si falta un consumidor en el grafo (p. ej. un uso no
//   catalogado), lo que se muestra como muerto podría no serlo: es un CANDIDATO a retirada, no una orden.
//
// RESULTADO ESPERADO EN EL DATASET DE EJEMPLO (8 columnas muertas, 2 jobs muertos, 127.000 €/año)
//   Zona 1 · isla aislada     LEGACY_DM.BRANCH_MONTHLY.BRANCH_ID → LEGACY_RPT.BRANCH_SUMMARY.BRANCH_ID
//                             LEGACY_DM.BRANCH_MONTHLY.{TOTAL_DEPOSITS,TOTAL_LOANS} → LEGACY_RPT.BRANCH_SUMMARY.NET_POSITION
//                             (dos islas pequeñas, 5 columnas) · job LEGACY_BRANCH_REPORT (Deprecated, sin propietario)
//   Zona 2 · rama de dato vivo STG.STG_CUSTOMER.SEGMENT_CODE (VIVO) → MKT_STG.PROMO.TARGET_SEGMENT → PROMO_SCORE
//                             job PROMO_SEGMENT_EXTRACT (Active, pero nadie consume su salida)
//   Zona 3 · rama de dato vivo STG.STG_LOAN.DRAWN_AMOUNT (VIVO) → RISK_MART.EXPOSURE.EXPOSURE_ADJ_LEGACY
//                             dentro de CALC_EXPOSURE, que SÍ está vivo (una columna muerta en un job vivo)
//
// CIFRAS DEL GRAFO PROYECTADO: dependen de si has cargado el proyecto nuevo de 01_ingesta.cypher (bloque B)
//   · Sin bloque B: 81 Column + 6 FinalConsumer = 87 nodos; 66 TRANSFORMS_TO + 25 FEEDS = 91 relaciones
//   · Con bloque B: 82 + 6 = 88 nodos; 68 + 26 = 94 relaciones (RWA_DENSITY y 3 aristas más)  ← caso del autor
//   Las columnas muertas son 8 en ambos casos.
//
// ESTRUCTURA
//   A. BFS en reversa desde cada FinalConsumer → qué está vivo y qué está muerto
//   B. Por qué un componente conexo (WCC) NO basta (solo ve las islas, no las ramas) — MATERIAL DE APOYO: no se cuenta en la demo
//   C. Cuellos de botella con algoritmos de centralidad (PageRank, betweenness) — extra
//   Z. Borrar las proyecciones y la sesión (DESPUÉS de A, B y C)
//   D. Cypher puro (sin GDS): fallback / verificación cruzada y el informe de negocio (jobs, ahorro, sistemas).
//      Sus queries marcadas ▣ alimentan un dashboard de Aura.
// =====================================================================================


// =====================================================================================
// PARTE A · BFS EN REVERSA DESDE LOS CONSUMIDORES FINALES
//
// ¿Qué es un BFS? (Breadth-First Search, búsqueda en anchura)
//   Parte de UN nodo y visita todos los nodos alcanzables siguiendo la dirección de las flechas, por niveles:
//   primero los vecinos directos (1 salto), luego los vecinos de esos (2 saltos), y así hasta agotar el camino.
//   `gds.bfs.stream` devuelve en `nodeIds` la lista de nodos visitados (el nodo de partida incluido).
//
// ¿Para qué lo usamos? Para seguir el linaje HACIA ATRÁS desde cada informe. Los datos fluyen
//   origen → … → informe, así que proyectamos el grafo con las flechas INVERTIDAS (informe → … → origen):
//   un BFS desde un informe visita entonces justo las columnas de las que depende, directa o indirectamente
//   (es como echar tinta en el informe y ver por dónde se tiñe aguas arriba).
//   Lo que NINGÚN informe tiñe está muerto.
//
// En AGA la orientación por tipo no se puede indicar en la proyección nativa, así que la inversión se hace
// en la proyección Cypher: el destino de la arista real (b) pasa a ser el ORIGEN en la sesión.
// =====================================================================================

// A.1 · Proyección Cypher hacia la sesión, con la dirección invertida (crea la sesión implícita)
//       esperado: 87 nodos / 91 relaciones (sin bloque B) · 88 nodos / 94 relaciones (con bloque B)
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
  { memory: '2GB' }
) AS projection;

// A.1b · Comprobar qué hay en la sesión
//        esperado: lineage_rev · 88 nodos · 94 relaciones (con bloque B; 87 / 91 sin él)
CALL gds.graph.list('lineage_rev')
YIELD graphName, nodeCount, relationshipCount
RETURN graphName, nodeCount, relationshipCount;

// A.2 · BFS desde CADA FinalConsumer: cuántas columnas hay en el linaje de cada informe
//       (gds.bfs.stream acepta UN solo nodo de partida → se ejecuta una vez por consumidor)
//       `size(nodeIds) - 1` = nodos visitados menos el propio informe = columnas de su linaje.
//       esperado (sin bloque B → con bloque B): Solvency Report 23 · Large Exposures Report 14 ·
//         Balance Sheet Report 12 · Risk Data Aggregation Dashboard 22 → 25 · Expense Dashboard 18 · Customer Churn Model 18
//       Lectura: "cada informe tiene su árbol de linaje". Las columnas de ningún árbol son las muertas (A.3 y A.4).
//       Si tu entorno no admite un CALL de procedimiento GDS dentro de un subquery, salta a la PARTE D.
MATCH (fc:FinalConsumer)
CALL (fc) {
  CALL gds.bfs.stream('lineage_rev', {sourceNode: id(fc)})
  YIELD nodeIds
  RETURN size(nodeIds) - 1 AS columns_in_lineage
}
RETURN fc.name AS consumer, fc.type AS type, columns_in_lineage
ORDER BY columns_in_lineage DESC;

// A.3 · Unión de todos los linajes: ¿cuántas columnas están vivas y cuántas muertas?
//       esperado: con bloque B 82 columnas = 74 vivas + 8 muertas (sin bloque B: 81 = 73 + 8)
MATCH (fc:FinalConsumer)
CALL (fc) {
  CALL gds.bfs.stream('lineage_rev', {sourceNode: id(fc)})
  YIELD nodeIds
  UNWIND nodeIds AS nodeId
  RETURN DISTINCT nodeId
}
WITH collect(DISTINCT nodeId) AS visited_ids
MATCH (c:Column)
RETURN count(c) AS total_columns,
       count(CASE WHEN id(c) IN visited_ids THEN 1 END) AS live_columns,
       count(CASE WHEN NOT id(c) IN visited_ids THEN 1 END) AS dead_columns;

// A.4 · Las columnas muertas (las que ningún BFS visitó), con su sistema y el job que las produce
//       esperado: 8 filas. Las 3 raíces LEGACY_DM.* sin job (se cargan fuera del grafo); LEGACY_RPT.* ← LEGACY_BRANCH_REPORT;
//       MKT_STG.PROMO.* ← PROMO_SEGMENT_EXTRACT; RISK_MART.EXPOSURE.EXPOSURE_ADJ_LEGACY ← CALC_EXPOSURE
MATCH (fc:FinalConsumer)
CALL (fc) {
  CALL gds.bfs.stream('lineage_rev', {sourceNode: id(fc)})
  YIELD nodeIds
  UNWIND nodeIds AS nodeId
  RETURN DISTINCT nodeId
}
WITH collect(DISTINCT nodeId) AS visited_ids
MATCH (c:Column)
WHERE NOT id(c) IN visited_ids
OPTIONAL MATCH (ss:SourceSystem)-[:HOSTS]->(c)
OPTIONAL MATCH (:Column)-[t:TRANSFORMS_TO]->(c)
RETURN c.fqn AS dead_column, ss.name AS hosted_in, collect(DISTINCT t.scenario) AS produced_by_jobs
ORDER BY dead_column;

// A.5 · Lo mismo VISUAL (Browser/Bloom): cada columna muerta con sus vecinos directos
//       Verás dos tipos de figura:
//         · 2 islas pequeñas (zona 1), sin ningún enlace con lo vivo;
//         · 2 ramas (zonas 2 y 3) que cuelgan de UNA columna viva: es la columna viva que aparece enlazada a ellas.
//       esperado: 8 columnas muertas + las columnas vecinas (las vivas de las que cuelgan las ramas)
MATCH (fc:FinalConsumer)
CALL (fc) {
  CALL gds.bfs.stream('lineage_rev', {sourceNode: id(fc)})
  YIELD nodeIds
  UNWIND nodeIds AS nodeId
  RETURN DISTINCT nodeId
}
WITH collect(DISTINCT nodeId) AS visited_ids
MATCH (d:Column)
WHERE NOT id(d) IN visited_ids
OPTIONAL MATCH p = (d)-[:TRANSFORMS_TO]-(:Column)
RETURN d, p;


// =====================================================================================
// PARTE B · POR QUÉ UN COMPONENTE CONEXO NO BASTA
// ➖ MATERIAL DE APOYO: no se cuenta en la demo (por simplicidad). Se conserva porque explica por qué se usa BFS y no
//    WCC. Se puede saltar sin consecuencias: ninguna otra parte depende de ella (si la saltas, en Z omite el
//    `gds.graph.drop('lineage_undirected')`, que no existirá).
//
// ¿Qué queremos averiguar? Si un algoritmo más simple que el BFS —los COMPONENTES CONEXOS (WCC)— bastaría
// para encontrar lo muerto, que es lo primero que se le ocurre a mucha gente.
//   · WCC (Weakly Connected Components) agrupa los nodos que están unidos por ALGÚN camino, SIN mirar la dirección
//     de las flechas. Cada grupo es un «componente».
//   · Idea ingenua: «un componente en el que no hay ningún FinalConsumer es una isla muerta».
// Respuesta (queries B.1 a B.3): sirve para las ISLAS, pero NO para las RAMAS. Una rama muerta que cuelga de un dato
// vivo pertenece al MISMO componente que los informes (están conectados, aunque las flechas no lleguen a ellos), así
// que WCC no la marca. Solo la detección a nivel de RUTA con dirección (parte A) encuentra las zonas 2 y 3.
// =====================================================================================

// B.0 · Proyección nativa no dirigida (en AGA: etiquetas/tipos como lista + configuración global)
//       esperado: 87 nodos / 182 relaciones (sin bloque B) · 88 / 188 (con bloque B): cada arista no dirigida cuenta dos veces
//       (esta proyección puede crear una segunda sesión implícita: se verá en Z.2)
CALL gds.graph.project(
  'lineage_undirected',
  ['Column', 'FinalConsumer'],
  ['TRANSFORMS_TO', 'FEEDS'],
  {memory: '2GB', undirectedRelationshipTypes: ['*']}
)
YIELD graphName, nodeCount, relationshipCount, projectMillis
RETURN graphName, nodeCount, relationshipCount, projectMillis;

// B.1 · Componentes y cuántos FinalConsumer contiene cada uno
//       Resultado observado en Aura (con bloque B): 3 componentes
//         · 2 nodos, 0 consumidores:  LEGACY_DM.BRANCH_MONTHLY.BRANCH_ID ↔ LEGACY_RPT.BRANCH_SUMMARY.BRANCH_ID
//         · 3 nodos, 0 consumidores:  TOTAL_DEPOSITS, TOTAL_LOANS → NET_POSITION (las otras 3 columnas legacy)
//         · 83 nodos, 6 consumidores: todo lo demás (82 sin bloque B)
//       Lectura: los 2 componentes SIN consumidores son las islas de la zona 1 (5 columnas en total).
CALL gds.wcc.stream('lineage_undirected')
YIELD nodeId, componentId
MATCH (n) WHERE id(n) = nodeId
WITH componentId, collect(n) AS members
RETURN componentId,
       size(members) AS size,
       size([m IN members WHERE m:FinalConsumer]) AS final_consumers,
       [m IN members WHERE m:Column | m.fqn][..3] AS sample_columns
ORDER BY final_consumers ASC;

// B.2 · Veredicto columna a columna: de las 8 columnas realmente muertas, ¿cuáles encuentra WCC?
//       `found_by_wcc` = el componente de la columna no tiene ningún consumidor.
//       esperado: 5 filas con found_by_wcc = true (las islas) y 3 con false:
//                 MKT_STG.PROMO.TARGET_SEGMENT, MKT_STG.PROMO.PROMO_SCORE y RISK_MART.EXPOSURE.EXPOSURE_ADJ_LEGACY
//       Esas 3 están DENTRO del componente grande: están conectadas a datos vivos, pero ninguna flecha las lleva a un informe.
CALL gds.wcc.stream('lineage_undirected')
YIELD nodeId, componentId
MATCH (n) WHERE id(n) = nodeId
WITH componentId, collect(n) AS members
WITH [m IN members WHERE m:Column] AS columns,
     size([m IN members WHERE m:FinalConsumer]) = 0 AS wcc_flags_it
UNWIND columns AS c
WITH c, wcc_flags_it
WHERE wcc_flags_it OR NOT EXISTS { MATCH (c)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
RETURN c.fqn AS dead_column, wcc_flags_it AS found_by_wcc
ORDER BY found_by_wcc DESC, dead_column;

// B.3 · Visual: por qué WCC se equivoca. Para cada columna muerta que WCC NO ve, el camino más corto —ignorando la
//       dirección de las flechas— hasta el informe más cercano.
//       esperado: 3 caminos (uno por columna). Verás que la columna muerta está a pocos saltos de un informe: por eso
//       WCC la mete en el componente grande, aunque las flechas no vayan hacia allí (la rama sale de una columna viva
//       hacia un callejón sin salida).
MATCH (d:Column)
WHERE NOT EXISTS { MATCH (d)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
MATCH (fc:FinalConsumer)
MATCH p = shortestPath((d)-[:TRANSFORMS_TO|FEEDS*..20]-(fc))
WITH d, p
ORDER BY length(p)
WITH d, collect(p)[0] AS path_to_nearest_report
RETURN path_to_nearest_report;


// =====================================================================================
// PARTE C · CUELLOS DE BOTELLA CON ALGORITMOS DE CENTRALIDAD  (extra; requiere A.1 y la sesión activa)
// Es lo que 02_impacto no puede hacer con conteos de caminos: medir cuánto "pasa por" un nodo.
//   · 02·5 (Cypher)      → "¿a cuántos informes llega esto?"            (alcance aguas abajo, desde un nodo)
//   · PageRank (C.1)     → "¿de qué columnas depende, transitivamente, todo lo demás?"  (importancia aguas arriba)
//   · Betweenness (C.2)  → "¿por qué columnas pasan más caminos origen→informe?"        (cuello de botella)
// Se usa la proyección `lineage_rev` de A.1 (dirección invertida: informe → … → origen crudo).
// Betweenness da el mismo resultado en el grafo natural y en el invertido; PageRank NO: aquí la puntuación
// fluye de los consumidores hacia los orígenes, y por eso destacan las columnas de las que cuelga mucho linaje.
// Los nodos FinalConsumer están en la proyección, pero se filtran con `:Column` al volver a la BD.
// Las columnas muertas puntúan lo mínimo en PageRank (0.15, sin aristas entrantes en la proyección).
// Ni PageRank ni betweenness "saben" qué está vivo: para eso, parte A.
// Las cifras de betweenness "esperado" salen de un cálculo en Python sobre los CSV (algoritmo de Brandes), NO de GDS.
// =====================================================================================

// C.1 · PageRank: columnas de las que más depende el resto del linaje
//       Resultado observado en Aura (con bloque B), top 5:
//         CRM.CUSTOMER.SEGMENT_CODE 0.605 · CORE.LOAN.ASSET_CLASS 0.604 · CORE.LOAN.DRAWN_AMOUNT 0.578 ·
//         CORE.ACCOUNT.BALANCE 0.554 · STG.STG_CUSTOMER.SEGMENT_CODE 0.535
//       Lectura: arriba quedan los orígenes crudos de Core Banking y CRM, y sus copias en staging: de ellos cuelga más linaje.
CALL gds.pageRank.stream('lineage_rev')
YIELD nodeId, score
MATCH (c:Column) WHERE id(c) = nodeId
OPTIONAL MATCH (ss:SourceSystem)-[:HOSTS]->(c)
RETURN c.fqn AS column, ss.name AS hosted_in, round(score, 3) AS pagerank
ORDER BY pagerank DESC
LIMIT 10;

// C.1b · Visual: de qué cuelga el top 3 de PageRank — todos los caminos desde esas columnas hasta los informes
//        (es el "abanico" que se abre desde cada origen importante)
CALL gds.pageRank.stream('lineage_rev')
YIELD nodeId, score
WITH nodeId, score
ORDER BY score DESC
LIMIT 3
MATCH (c:Column) WHERE id(c) = nodeId
MATCH p = (c)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(:FinalConsumer)
RETURN p;

// C.2 · Betweenness: columnas por las que pasan más caminos mínimos entre origen e informe (puntos de estrangulamiento)
//       esperado: RISK_MART.EXPOSURE.EAD (28), RISK_MART.EXPOSURE.RATING_BUCKET (23), RISK_MART.RWA.RWA_AMOUNT (23),
//       RISK_MART.RWA.RATING_BUCKET (20) → todas en el motor de riesgo; CHURN_RISK_FLAG (11) queda lejos
//       Lectura: son las columnas intermedias donde "se juntan" varios proyectos. Si fallan, no cae un origen:
//       se corta el tramo que une varios.
CALL gds.betweenness.stream('lineage_rev')
YIELD nodeId, score
WHERE score > 0
MATCH (c:Column) WHERE id(c) = nodeId
OPTIONAL MATCH ()-[t:TRANSFORMS_TO]->(c)
RETURN c.fqn AS column, collect(DISTINCT t.scenario) AS produced_by_jobs, round(score, 1) AS betweenness
ORDER BY betweenness DESC
LIMIT 10;

// C.2b · Visual: el "reloj de arena" del cuello de botella nº 1 — todos los caminos que pasan por la columna con más
//        betweenness: muchos orígenes entran por un lado, se estrechan en ella y se abren hacia los informes.
//        (cambia `LIMIT 1` por `LIMIT 2`… para ver más cuellos de botella a la vez)
CALL gds.betweenness.stream('lineage_rev')
YIELD nodeId, score
WITH nodeId, score
ORDER BY score DESC
LIMIT 1
MATCH (hub:Column) WHERE id(hub) = nodeId
MATCH p = (:SourceSystem)-[:HOSTS]->(root:Column)-[:TRANSFORMS_TO*0..10]->(hub)-[:TRANSFORMS_TO*0..10]->(:Column)-[:FEEDS]->(:FinalConsumer)
WHERE NOT EXISTS { ()-[:TRANSFORMS_TO]->(root) }
RETURN p
LIMIT 200;

// C.3 · Betweenness agregada por job: ¿qué EtlJob es el cuello de botella? (suma de las columnas que produce)
//       esperado: CALC_EXPOSURE (64), CALC_RWA (48), LOAD_CORE_LOANS y BUILD_CHURN_FEATURES (31 cada uno)…
//       Matiz: PROMO_SEGMENT_EXTRACT (2) sale con valor > 0 aunque es un job MUERTO: betweenness mide posición
//       en el grafo, no si hay consumidor. Cruza siempre con la parte A / D.4 para no retirar lo que aparece aquí.
CALL gds.betweenness.stream('lineage_rev')
YIELD nodeId, score
MATCH (c:Column) WHERE id(c) = nodeId
MATCH ()-[t:TRANSFORMS_TO]->(c)
WITH c, score, collect(DISTINCT t.scenario) AS jobs
UNWIND jobs AS job
RETURN job, count(c) AS output_columns, round(sum(score), 1) AS betweenness_sum
ORDER BY betweenness_sum DESC;


// =====================================================================================
// PARTE Z · BORRAR LAS PROYECCIONES Y LA SESIÓN (deja de facturar; el grafo de la BD no se toca)
// Con sesión implícita, la sesión se elimina cuando se borra su último grafo proyectado.
// Ejecuta Z DESPUÉS de las partes A, B y C. La parte D no necesita la sesión.
// =====================================================================================

// Z.1 · Borrar las proyecciones (una consulta por línea). Si te saltaste la parte B, ejecuta solo la primera.
CALL gds.graph.drop('lineage_rev')
YIELD graphName
RETURN graphName;

CALL gds.graph.drop('lineage_undirected')
YIELD graphName
RETURN graphName;

// Z.2 · Comprobar que no queda ninguna sesión (esperado: 0 filas). Si B.0 creó una segunda sesión, también
//       debería haber desaparecido al borrar su grafo.
CALL gds.session.list()
YIELD id, name, status, memory, expiryDate
RETURN id, name, status, memory, expiryDate;

// Z.3 · Solo si Z.2 devuelve alguna sesión: bórrala por nombre (el que muestre Z.2)
// CALL gds.session.delete('<name>')
// YIELD deleted
// RETURN deleted;


// =====================================================================================
// PARTE D · CYPHER PURO — FALLBACK, VERIFICACIÓN CRUZADA E INFORME DE NEGOCIO
// Sin GDS ni sesión. Equivale a la parte A. Usa EXISTS { } con camino variable sin cota superior (*0..): válido
// porque el linaje es un DAG; en grafos muy grandes conviene acotar (*0..20) o materializar el resultado
// (se menciona en el cierre de productivización de la demo, RUNBOOK_DEMO.md).
//
// Recordatorio de qué es «muerto» (ver cabecera): una columna es muerta si NINGÚN camino con dirección sale de ella
// hasta un FinalConsumer; un job es muerto si ninguna de sus columnas de salida está viva. Las queries de esta
// parte clasifican, ponen coste y señalan dónde cortar.
//
// DASHBOARD (Aura Dashboards) — dashboard aparte del de impacto, creado y verificado por el autor (26-oct-2026):
//   título «Data Lineage Dead Zones» · fichero dashboards/data_lineage_fs_dead_zones_dashboard.json
//   (mismo patrón que dashboards/data_lineage_fs_impact_dashboard.json, «Data Lineage Impact»).
// Las queries se marcan con «▣ DASHBOARD». Tarjetas (según el export), de arriba abajo:
//     ▣ «1. Potential Annual Saving (EUR)» ........ D.5  Single value (variante de una sola columna)
//     ▣ «2. Source System Health (live vs dead)» .. D.7  Bar chart vertical, valores agrupados (live_columns, dead_columns)
//     ▣ «3. Dead Columns» ......................... D.1  Tabla, `dead branch` en amarillo
//     ▣ «4. Dead Jobs (retirement candidates)» .... D.4  Tabla, `Deprecated` en rojo
//     ▣ «5. Dead Columns inside Live Jobs» ........ D.6  Tabla pequeña, sin estilo
//     ▣ (opcional) D.3 como tarjeta de GRAFO (devuelve paths; layout jerárquico de izquierda a derecha)
//   Queda fuera D.2 (puntos de bifurcación), que es la misma información que D.3 en formato tabla.
// =====================================================================================

// D.1 · Columnas muertas (debe coincidir con A.4) + clasificación de la zona
//       · "isolated zone"  → ningún ancestro vivo: no cuelga de nada que se use (islas)
//       · "dead branch"    → algún ancestro está vivo: se bifurca de un dato vivo (el caso difícil)
//       ▣ DASHBOARD · «3. Dead Columns» — TABLA, query SIN cambios. Estilo aplicado: la celda `zone_type` en amarillo
//         cuando contiene 'dead branch' (las difíciles de ver sin el grafo). esperado: 8 filas
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

// D.2 · Puntos de bifurcación: dónde un dato VIVO empieza a alimentar una rama MUERTA
//       (la pieza de información más accionable: "corta aquí")
MATCH (live:Column)-[t:TRANSFORMS_TO]->(dead:Column)
WHERE EXISTS { MATCH (live)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
  AND NOT EXISTS { MATCH (dead)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
RETURN live.fqn AS live_column, t.scenario AS job, t.transformation_expression AS expression, dead.fqn AS dead_column;

// D.3 · Visual: ruta muerta junto a su ancestro vivo (para Browser/Bloom)
//       ▣ DASHBOARD (opcional) — tarjeta de GRAFO, query SIN cambios
MATCH p = (live:Column)-[:TRANSFORMS_TO]->(dead:Column)-[:TRANSFORMS_TO*0..]->(:Column)
WHERE EXISTS { MATCH (live)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
  AND NOT EXISTS { MATCH (dead)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
RETURN p;

// D.4 · Jobs muertos = candidatos a retirada, con coste y propietario
//       (LEGACY_BRANCH_REPORT no devuelve propietario: segunda razón para retirarlo)
//       ▣ DASHBOARD · «4. Dead Jobs (retirement candidates)» — TABLA, query SIN cambios. Estilo aplicado: `status` en rojo
//         cuando vale 'Deprecated'.
//         esperado: PROMO_SEGMENT_EXTRACT (42.000 €) y LEGACY_BRANCH_REPORT (85.000 €, sin propietario)
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

// D.5 · Ahorro potencial total (€ / año) por retirar los jobs muertos      esperado: 127000
MATCH (j:EtlJob)
WHERE NOT EXISTS {
  MATCH (:Column)-[t:TRANSFORMS_TO]->(out:Column)
  WHERE t.scenario = j.name
    AND EXISTS { MATCH (out)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
}
RETURN count(j) AS dead_jobs, sum(j.estimated_compute_cost) AS potential_annual_saving_eur;

// ▣ DASHBOARD · «1. Potential Annual Saving (EUR)» · VARIANTE de D.5 — tipo: SINGLE VALUE
//   Cambio: una sola columna (la tarjeta "Single value" muestra un único número). El recuento de jobs muertos
//   se ve en las filas de la tabla D.4.
MATCH (j:EtlJob)
WHERE NOT EXISTS {
  MATCH (:Column)-[t:TRANSFORMS_TO]->(out:Column)
  WHERE t.scenario = j.name
    AND EXISTS { MATCH (out)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
}
RETURN sum(j.estimated_compute_cost) AS potential_annual_saving_eur;

// D.6 · Columnas muertas DENTRO de jobs vivos (limpieza parcial: el job se queda, la columna sobra)
//       esperado: CALC_EXPOSURE → RISK_MART.EXPOSURE.EXPOSURE_ADJ_LEGACY
//       ▣ DASHBOARD · «5. Dead Columns inside Live Jobs» — TABLA pequeña (1 fila), query SIN cambios.
MATCH (j:EtlJob)
WHERE EXISTS {
  MATCH (:Column)-[t:TRANSFORMS_TO]->(out:Column)
  WHERE t.scenario = j.name
    AND EXISTS { MATCH (out)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
}
MATCH (:Column)-[t2:TRANSFORMS_TO {scenario: j.name}]->(dead:Column)
WHERE NOT EXISTS { MATCH (dead)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
RETURN j.name AS live_job_with_dead_output, collect(DISTINCT dead.fqn) AS dead_columns;

// D.7 · Salud por sistema: % de columnas vivas. Un sistema con 0 % vivo es candidato a decommission.
//       esperado: Legacy Data Mart → 0 de 5 vivas
//       ▣ DASHBOARD · «2. Source System Health (live vs dead)» — BAR CHART vertical, valores agrupados, query SIN cambios.
//         Category = source_system · Value = live_columns y dead_columns. No selecciones `hosted_columns` ni
//         `pct_live` como valores (`criticality` es texto).
MATCH (ss:SourceSystem)-[:HOSTS]->(c:Column)
WITH ss, c, EXISTS { MATCH (c)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) } AS is_live
WITH ss, count(c) AS hosted_columns, sum(CASE WHEN is_live THEN 1 ELSE 0 END) AS live_columns
RETURN ss.name AS source_system, ss.criticality AS criticality, hosted_columns, live_columns,
       hosted_columns - live_columns AS dead_columns,
       round(100.0 * live_columns / hosted_columns, 1) AS pct_live
ORDER BY pct_live ASC, hosted_columns DESC;
