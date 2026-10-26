# DASHBOARDS_GUIDE — dashboards de Aura de la demo

Referencia de **lo que contienen realmente** los dos exports de esta carpeta (Aura Dashboards, `version: 2`, creados y verificados en Aura por el autor el 26-oct-2026). Todo sale de los JSON; las queries completas están en los ficheros `.cypher` (las marcadas `▣`).

| Dashboard | Fichero | Ángulo | Query origen | Tarjetas | Parámetros |
|---|---|---|---|---|---|
| **Data Lineage Impact** | `data_lineage_fs_impact_dashboard.json` | 2 · Impacto | `queries/02_impacto.cypher` | 5 + 1 filtro | `$source_system` |
| **Data Lineage Dead Zones** | `data_lineage_fs_dead_zones_dashboard.json` | 3 · Zonas muertas | `queries/03_zonas_muertas_gds.cypher`, parte D | 5 | ninguno |

Los dos tienen una sola página («Main page») y solo ejecutan **Cypher puro**: no necesitan GDS ni sesión de Aura Graph Analytics.

## Cómo importarlos

1. Dataset cargado en la instancia (`data/00_load_live.cypher`). Para que las cifras cuadren con el guion, también el bloque B de `01_ingesta.cypher` si se va a enseñar ya cargado (cambia en uno el nº de jobs/columnas).
2. Aura → Dashboards → importar el JSON → elegir la instancia.
3. Los exports llevan `"databaseName": "neo4j"` en cada tarjeta (la base por defecto de Aura). Si la instancia usa otro nombre de base, hay que cambiarlo en cada tarjeta.
4. Los exports no contienen credenciales ni identificadores de instancia.

## Data Lineage Impact

Pensado para usarse como cierre del bloque 2 o material para dejar al cliente (el flujo en vivo va en Bloom). Recorrido de arriba a abajo, de izquierda a derecha.

| # | Tarjeta | Query | Tipo y estilo |
|---|---|---|---|
| 1 | Source Systems by Impact | 02 · 3.b | Bar chart vertical, valores agrupados (`consumers_affected`, `regulatory_consumers_affected`) |
| — | Filtro «2. Source System» | — | Filtro de propiedad `SourceSystem.name`, enlazado a `$source_system`; valor inicial `Core Banking PL/SQL` |
| 2 | Affected Reports (Consumer) | 02 · 3.a (variante con `$source_system`, `LIMIT 25`) | Tabla; columna `type` en amarillo cuando contiene `Regulatory` |
| 3 | #Reports Affected if a Job Fails | 02 · 5 | Bar chart horizontal sobre `consumers_depending` (ejes «ETL Job» / «Reports»); orden ascendente |
| 4 | Regulatory Report Data | 02 · 6.a (con la lista de jobs) | Tabla; escala de blanco a rojo en `origin_columns` (de 1 a 20) |
| 5 | Accountability Gaps | 02 · 6.b | Tabla pequeña; `regulatory_consumers_served` en amarillo cuando es 0 |

**Qué enseñar**
- **1** — «Qué sistema sostiene más informes.» Los sistemas con 0 salen sin barra (p. ej. Legacy Data Mart).
- **Filtro + 2** — cambiar de sistema y ver cómo cambia la lista de informes. Con `Legacy Data Mart` se espera la tabla vacía (sistema sin ningún consumidor; es lo que dice `02`, no se ha anotado como comprobado): enlace con el bloque 3.
- **3** — dónde duele más que falle un job.
- **4** — trazabilidad BCBS 239: cuántas columnas origen y qué jobs hay detrás de cada informe regulatorio.
- **5** — jobs sin propietario y a qué informes sirven; en amarillo los que no sirven a ningún informe regulatorio.

**Cuidado**
- `$source_system` solo existe dentro del dashboard. Si se pega la query de la tarjeta 2 en el Query tool hay que definir antes `:param source_system => '...'`.
- La tarjeta 3 guarda en `meta` dos versiones de la query (orden ascendente y descendente); la activa es la ascendente. Con una única serie, `barArrangement: stacked` no tiene efecto visible.

## Data Lineage Dead Zones

Se enseña tras la parte A de `03` (BFS) o, si GDS falla, en su lugar (plan B: es el mismo resultado en Cypher puro).

| # | Tarjeta | Query | Tipo y estilo |
|---|---|---|---|
| 1 | Potential Annual Saving (EUR) | 03 · D.5 (variante de una sola columna) | Single value |
| 2 | Source System Health (live vs dead) | 03 · D.7 | Bar chart vertical, valores agrupados (`live_columns`, `dead_columns`) |
| 3 | Dead Columns | 03 · D.1 | Tabla; `zone_type` en amarillo cuando contiene `dead branch` |
| 4 | Dead Jobs (retirement candidates) | 03 · D.4 | Tabla; `status` en rojo cuando es `Deprecated` |
| 5 | Dead Columns inside Live Jobs | 03 · D.6 | Tabla pequeña, sin estilo |

**Qué enseñar** (cifras calculadas sobre los CSV, no ejecutadas por el agente)
- **1** — 127.000 € al año: `PROMO_SEGMENT_EXTRACT` (42.000) + `LEGACY_BRANCH_REPORT` (85.000).
- **2** — un sistema con 0 % de columnas vivas; el resto, casi todo vivo.
- **3** — 8 columnas muertas: las dos islas aisladas (`isolated zone`, 2 y 3 columnas) y las ramas muertas que cuelgan de columnas vivas (en amarillo).
- **4** — los 2 jobs muertos; uno deprecado (en rojo) y sin propietario.
- **5** — una columna muerta dentro de un job vivo (`EXPOSURE_ADJ_LEGACY` en `CALC_EXPOSURE`): se retira la columna, no el job.

Recordatorio de semántica (de `03`): «muerto» es candidato a retirada, no una orden.

## Diferencias entre los exports y el repo

- El título del filtro del dashboard de impacto es `2. Source System ` **con un espacio final** en el export. Es inocuo; para quitarlo, editarlo en Aura y reexportar.
- Las queries de las tarjetas son copias de las `▣` de los `.cypher` (la 3.a con `$source_system` y `LIMIT 25`). No hay vínculo automático: si se modifica una query en el `.cypher`, hay que actualizarla también en la tarjeta y reexportar.
- Ninguno de los dos dashboards usa gráficos de grafo: la parte visual de cada ángulo está en Bloom (impacto) y en `03` A.5 / D.3 (zonas muertas).
- La parte D de `03` que no está en el dashboard (D.2 y D.3) sigue sin validar.
