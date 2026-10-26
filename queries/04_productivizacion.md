# Productivización — del demo a un servicio de linaje (ángulo 5)

> ⚠️ **No es Cypher ejecutable de punta a punta.** Es una nota de buenas prácticas con 3 queries de ejemplo. Las queries **no se han validado contra una instancia Neo4j real** (ver `CONTEXTO_IA.md`, restricción 4): tratarlas como "a validar". Los números de esta nota (coste, nº de jobs…) salen del dataset sintético de `data/`.

El demo carga unos CSV a mano. En producción el linaje lo producen **scanners/parsers** (SQL, ETL, BI) y el grafo debe aguantar cargas repetidas, cambios de código y auditoría. Cinco decisiones concentran casi todo el valor.

---

## 1. Ingesta idempotente

**Regla:** cualquier carga se puede ejecutar 1 o 10 veces y el grafo queda igual.

| Práctica | Cómo se aplica en este modelo |
|---|---|
| Clave natural estable por nodo | `Column.fqn` (`SCHEMA.TABLE.COLUMN`), `EtlJob.id`/`name`, `SourceSystem.id`, `FinalConsumer.id`, `Owner.id` |
| `MERGE` sólo por la clave | `MERGE (c:Column {fqn: $fqn})` — nunca incluir propiedades descriptivas en el patrón del `MERGE` (crearía duplicados al cambiar una) |
| Quién puede sobrescribir qué | `ON CREATE SET` para metadatos descriptivos de una columna que un proyecto sólo **lee**; `SET` sólo desde el proyecto que la **escribe** (dueño del `fqn`) |
| Arista con identidad propia | `TRANSFORMS_TO.id` = hash determinista de `scenario + origen + destino + expresión` (el CSV usa SHA-1 truncado). Es **distinto** del id interno de Neo4j y es lo que evita aristas duplicadas |
| Restricciones de unicidad antes de cargar | Ya incluidas en `data/00_load_live.cypher` (`REQUIRE ... IS UNIQUE`, también sobre `TRANSFORMS_TO.id`) — además crean el índice que hace rápido el `MERGE` |
| Carga por lotes | `UNWIND $rows` + `CALL { ... } IN TRANSACTIONS OF 10000 ROWS`, nunca una transacción gigante |
| Carga por proyecto | Un lote por proyecto ETL (como los segmentos P1…P5 de `00_load_live.cypher`): permite reintentar uno sin tocar el resto |

### Query de ejemplo 1 — upsert por lotes de aristas de linaje (desde un driver o conector)

```cypher
// $edges = [{id, source_fqn, target_fqn, scenario, expression, filters, is_synthetic}, ...]
UNWIND $edges AS e
CALL (e) {
  MATCH (src:Column {fqn: e.source_fqn})
  MATCH (tgt:Column {fqn: e.target_fqn})
  MERGE (src)-[t:TRANSFORMS_TO {id: e.id}]->(tgt)
  SET t.scenario = e.scenario,
      t.transformation_expression = e.expression,
      t.filters = e.filters,
      t.is_synthetic_source = e.is_synthetic
} IN TRANSACTIONS OF 10000 ROWS;
```

> `CALL (e) { ... }` requiere Neo4j 5.23+. En versiones anteriores: `CALL { WITH e ... }`.

### Re-ingesta de un job que ha cambiado (mark & sweep)

Si `CALC_EXPOSURE` cambia su código, el scanner vuelve a emitir **todas** sus aristas. Las que ya no existen deben desaparecer, y sólo las de ese job:

```cypher
// $scenario = 'CALC_EXPOSURE' ; $current_ids = ids de TRANSFORMS_TO emitidos en esta ejecución
MATCH ()-[t:TRANSFORMS_TO {scenario: $scenario}]->()
WHERE NOT t.id IN $current_ids
DELETE t;
```

Esta es la razón práctica de que `EtlJob.name` deba coincidir con `scenario`: es la frontera de "lo que posee" cada carga.

---

## 2. Separación de capas: linaje técnico vs. capa semántica

El modelo mezcla dos tipos de información con **ciclo de vida y dueños distintos**. Conviene tratarlos como dos pipelines de carga independientes aunque vivan en el mismo grafo:

| Capa | Nodos / relaciones | Quién la produce | Cadencia | Si se rompe… |
|---|---|---|---|---|
| **Técnica** (derivable) | `Column`, `TRANSFORMS_TO`, `HOSTS`, `PROCESSES` | Scanners/parsers automáticos | Cada despliegue de ETL o noche | Se puede **recalcular entera** desde el código |
| **Semántica / gobierno** (curada) | `EtlJob` (frecuencia, coste, estado), `Owner`, `MAINTAINED_BY`, `FinalConsumer`, `FEEDS` | Data Office, FinOps, equipos de reporting | Cuando cambia el negocio | **No** se puede derivar del código: hay que protegerla |

Consecuencias prácticas:

1. **El scanner no borra la capa semántica.** Un re-escaneo sólo toca `Column`/`TRANSFORMS_TO`/`HOSTS`/`PROCESSES`. `FEEDS` y `MAINTAINED_BY` se cargan desde el catálogo de gobierno.
2. **`FEEDS` es el eslabón crítico.** Sin él, todo lo del grafo es "zona muerta" por definición. Debe provenir de una fuente fiable (inventario de informes regulatorios, catálogo de BI) y su calidad se monitoriza como cualquier otra.
3. **Integrar, no sustituir.** El catálogo existente del cliente (OpenMetadata, Purview…) sigue siendo la fuente de verdad de glosario y propietarios; el grafo se alimenta de él para `Owner`/`FinalConsumer` y le devuelve el linaje relacional que el catálogo no resuelve bien.
4. **Cuándo ampliar el modelo.** Si hace falta ver "qué versión del código produjo esta arista" o "cuándo se vio por última vez", añadir propiedades de auditoría **a la arista o al job**, no tocar `Column`/`TRANSFORMS_TO` (restricción de diseño del proyecto).

---

## 3. Informe periódico de zonas muertas

El detector del ángulo 3 deja de ser un truco de demo cuando se programa. Propuesta:

- **Cuándo:** semanal (tras la carga nocturna del lunes); mensual para el comité de Data Governance.
- **Cómo:** un job orquestado (Airflow, cron, el scheduler del cliente) que ejecuta la query de abajo y publica el resultado (tabla, correo, ticket). Si el grafo es grande, usar la variante GDS de `03_zonas_muertas_gds.cypher` (BFS en reversa) en lugar del `EXISTS` con camino variable.
- **Qué entrega:** KPIs de tendencia **y** la lista accionable (jobs a retirar, con coste y propietario).
- **Qué NO hace:** borrar nada automáticamente. Una zona muerta es un *candidato*: el job puede alimentar un consumidor que aún no está registrado como `FinalConsumer`. Primero se revisa; después se retira.

### Query de ejemplo 2 — KPIs del informe (una fila, apta para guardar en una tabla de tendencia)

```cypher
MATCH (c:Column)
WITH count(c) AS total_columns,
     sum(CASE WHEN EXISTS { MATCH (c)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
              THEN 0 ELSE 1 END) AS dead_columns
MATCH (j:EtlJob)
WITH total_columns, dead_columns, j,
     EXISTS {
       MATCH (:Column)-[t:TRANSFORMS_TO]->(out:Column)
       WHERE t.scenario = j.name
         AND EXISTS { MATCH (out)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(:FinalConsumer) }
     } AS job_is_live
RETURN datetime() AS report_date,
       total_columns,
       dead_columns,
       round(100.0 * dead_columns / total_columns, 1)                                          AS pct_dead_columns,
       count(j)                                                                                  AS total_jobs,
       sum(CASE WHEN job_is_live THEN 0 ELSE 1 END)                                              AS dead_jobs,
       sum(CASE WHEN job_is_live THEN 0 ELSE j.estimated_compute_cost END)                       AS potential_saving_eur_year;
```

Con el dataset de ejemplo debería devolver **81 columnas, 8 muertas (9,9 %), 13 jobs, 2 muertos y 127.000 €/año** (cifras comprobadas con `data/validate_dataset.py`, no con Neo4j).

### Query de ejemplo 3 — brecha de accountability (para el mismo informe)

```cypher
// Jobs sin propietario, con su coste y si sirven (o no) a algún informe
MATCH (j:EtlJob)
WHERE NOT EXISTS { MATCH (j)-[:MAINTAINED_BY]->(:Owner) }
OPTIONAL MATCH ()-[t:TRANSFORMS_TO {scenario: j.name}]->(out:Column)
OPTIONAL MATCH (out)-[:TRANSFORMS_TO*0..]->(:Column)-[:FEEDS]->(fc:FinalConsumer)
RETURN j.name AS ownerless_job, j.status AS status, j.estimated_compute_cost AS cost_eur_year,
       collect(DISTINCT fc.name) AS consumers_served;
```

Un job **sin dueño y sin consumidores** es el candidato perfecto a retirada; uno **sin dueño y con un informe regulatorio** es un incumplimiento de accountability (BCBS 239) a corregir con prioridad.

---

## 4. Escala y rendimiento

| Tema | Práctica |
|---|---|
| Caminos variables | Acotar profundidad (`*..10`, `*0..20`) con la profundidad real del linaje; sin cota sólo es seguro en DAG pequeños |
| Consultas de "vivo/muerto" frecuentes | Calcularlas con GDS (BFS en reversa) y **materializar** el resultado si se consulta mucho; es una extensión del modelo, no forma parte de `SCHEMA.md` — decidir explícitamente antes de añadirla |
| Ciclos | `TRANSFORMS_TO` debe ser un DAG. `data/validate_dataset.py` lo comprueba para el dataset de ejemplo; en producción, validar tras cada carga (un ciclo hace que los `*` recorran caminos sin fin lógico) |
| Volumen | Los índices vienen de las restricciones de unicidad; medir `PROFILE` de las queries de impacto con datos reales antes de prometer tiempos |
| GDS (Aura Graph Analytics) | Proyectar sólo `Column` y `FinalConsumer` con `TRANSFORMS_TO`/`FEEDS`; las sesiones son efímeras y se facturan por minuto (mínimo 10 min): en un informe periódico, proyectar (la sesión implícita se crea sola), ejecutar y borrar las proyecciones (`gds.graph.drop`, que elimina la sesión) en el mismo job. Si la orquestación es externa a Aura, usar el cliente Python con credenciales de la Aura API guardadas en un gestor de secretos |

---

## 5. Seguridad y gobierno del propio grafo

- El grafo de linaje contiene **metadatos** (nombres de tablas, jobs, expresiones), no datos de negocio. Aun así las expresiones pueden revelar lógica sensible: aplicar RBAC por rol (Data Office ve todo; consumidores de negocio ven sólo `FinalConsumer` y rutas hasta él).
- Versionar los CSV/scripts de carga como cualquier artefacto de código.
- Antes de reutilizar el dataset de ejemplo con otro cliente, comprobar que no contiene nombres reales (ver `CONTEXTO_IA.md`, "Cómo verificar que un cambio no rompe nada").

---

## Checklist de productivización

- [ ] Restricciones de unicidad creadas antes de la primera carga
- [ ] Cargas con `MERGE` por clave natural, por lotes y por proyecto
- [ ] Hash determinista en `TRANSFORMS_TO.id`
- [ ] Mark & sweep por `scenario` en re-ingestas
- [ ] Capa técnica (scanner) y capa semántica (`FEEDS`, `Owner`) con pipelines separados
- [ ] Informe semanal de zonas muertas + KPIs de tendencia, sin borrado automático
- [ ] Comprobaciones de salud tras cada carga (`queries/01_ingesta.cypher`, bloque D)
- [ ] Validación de ausencia de ciclos tras cada carga
- [ ] RBAC y retención definidos para el grafo de linaje
