# data/ — dataset sintético multi-proyecto

> Todo el contenido es **sintético**: una historia plausible de banca construida para que los 5 ángulos de la demo tengan sentido. No representa a ningún cliente real.
>
> ✅ **Validado en Aura (24-oct-2026):** `00_load_live.cypher` cargado desde GitHub (`baseUrl` = raw.githubusercontent.com) y el bloque de verificación devolvió exactamente los recuentos esperados (81 / 7 / 13 / 6 / 7 nodos; 66 / 81 / 113 / 25 / 14 aristas). Los CSV, además, pasan `validate_dataset.py`.
> ✅ Carga y `../queries/01_ingesta.cypher` validadas en Aura. ⚠️ `02` y `03` siguen **sin validar** (ver `../CONTEXTO_IA.md`, restricción 4).

Formato: **CSV + script de carga `LOAD CSV`** segmentado por proyecto, pensado para narrarse en vivo. Nombres de nodo/relación/propiedad en inglés, tal como en `../data-model/SCHEMA.md`.

## Ficheros

| Fichero | Contenido | Filas |
|---|---|---|
| `source_systems.csv` | nodos `SourceSystem` | 7 |
| `owners.csv` | nodos `Owner` | 7 |
| `final_consumers.csv` | nodos `FinalConsumer` | 6 |
| `etl_jobs.csv` | nodos `EtlJob` | 13 |
| `columns.csv` | nodos `Column` | 81 |
| `transforms_to.csv` | relaciones `TRANSFORMS_TO` | 66 |
| `hosts.csv` | relaciones `HOSTS` | 81 |
| `processes.csv` | relaciones `PROCESSES` | 113 |
| `feeds.csv` | relaciones `FEEDS` | 25 |
| `maintained_by.csv` | relaciones `MAINTAINED_BY` | 14 |
| `00_load_live.cypher` | segmento 0 (restricciones + datos maestros) y segmentos P1…P5 con `LOAD CSV` | — |
| `generate_dataset.py` | **fuente de verdad del contenido**: define el dataset en un sitio y reescribe los CSV | — |
| `validate_dataset.py` | valida los CSV (independiente del generador): integridad referencial y criterios de aceptación | — |

> `columns.csv`: 77 `COLUMN`, 3 `TABLE` y 1 `CONSTANT`. Las columnas `load_batch` de varios CSV son **auxiliares de carga** (segmentan la ingesta por proyecto); no se guardan como propiedad en el grafo. En `transforms_to.csv`, `filters` es una lista separada por `|` (vacía = sin filtros) y `is_synthetic_source` es `true`/`false`.

Para editar el dataset: modificar `generate_dataset.py`, ejecutar `python3 generate_dataset.py` y después `python3 validate_dataset.py` (sin dependencias, sólo biblioteca estándar).

## La historia: 5 proyectos ETL, 13 jobs

```
P1 Core ingestion      LOAD_CORE_ACCOUNTS · LOAD_CORE_LOANS · LOAD_CRM_CUSTOMERS          → STG.*
P2 Credit risk         LOAD_RISK_RATINGS · CALC_EXPOSURE · CALC_RWA                        → RISK_MART.*   (lee STG.* de P1)
P3 Regulatory reports  BUILD_COREP_SOLVENCY · BUILD_FINREP_BALANCE                         → REG_MART.*    (lee RISK_MART.* de P2 y STG.* de P1)
P4 Retail analytics    LOAD_CARD_TRANSACTIONS · BUILD_EXPENSE_DASHBOARD · BUILD_CHURN_FEATURES → BI_MART.*, ML_FEAT.*  (lee STG.* de P1)
P5 Marketing & legacy  PROMO_SEGMENT_EXTRACT · LEGACY_BRANCH_REPORT                        → MKT_STG.*, LEGACY_RPT.*  (zonas muertas)
```

**Sistemas origen (7):** Core Banking PL/SQL, Customer CRM, SAS Risk Engine, Cards Processing Platform, Commercial BI, Cloud Data Platform, Legacy Data Mart.
**Consumidores finales (6):** Solvency Report (COREP), Large Exposures Report (COREP), Balance Sheet Report (FINREP), Risk Data Aggregation Dashboard (BCBS239), Expense Dashboard, Customer Churn Model.

> `HOSTS` se asigna a **todas** las columnas (criterio del dataset). Las columnas derivadas cuelgan de la plataforma donde residen (Cloud Data Platform, Commercial BI, Legacy Data Mart); el análisis "si cae este sistema origen…" parte de las columnas raíz (sin `TRANSFORMS_TO` entrante).

## Qué casos cubre el dataset (criterios de aceptación de `CONTEXTO_IA.md`)

| Criterio | Dónde está |
|---|---|
| **Auto-conexión entre proyectos** (`fqn` compartido) | P3 lee `RISK_MART.RWA.RWA_AMOUNT`/`EXPOSURE.EAD` (escritas por P2) y P2 lee `STG.STG_LOAN.*` (escritas por P1): 15 columnas puente |
| **`kind = "CONSTANT"`** | `CONST.LITERAL.EUR` (`'EUR'`, `is_synthetic_source = true`) → `REPORTING_CURRENCY` en solvencia y balance |
| **`kind = "TABLE"`** | `STG.STG_ACCOUNT.*`, `STG.STG_CARD_TX.*`, `RISK_MART.RWA.*` con `COUNT(*)` |
| **Fórmula multi-origen** | `RISK_MART.EXPOSURE.RATING_BUCKET`: `CASE WHEN` con 3 columnas de 2 tablas → 3 aristas con la misma expresión. También en `SPEND_CATEGORY`, `TOTAL_BALANCE_EUR`, `RWA_HIGH_BUCKET_SHARE`, `CARD_ACTIVITY_FLAG`, `CHURN_RISK_FLAG` (3 orígenes intra-tabla) |
| **Zona muerta 1 — aislada** | `LEGACY_DM.BRANCH_MONTHLY.*` → `LEGACY_RPT.BRANCH_SUMMARY.*` (job `LEGACY_BRANCH_REPORT`, `Deprecated`, **sin propietario**) |
| **Zona muerta 2 — rama de dato vivo, job activo** | `STG.STG_CUSTOMER.SEGMENT_CODE` (vivo) → `MKT_STG.PROMO.TARGET_SEGMENT` → `PROMO_SCORE` (job `PROMO_SEGMENT_EXTRACT`, `Active`) |
| **Zona muerta 3 — columna muerta en job vivo** | `STG.STG_LOAN.DRAWN_AMOUNT` (vivo) → `RISK_MART.EXPOSURE.EXPOSURE_ADJ_LEGACY` dentro de `CALC_EXPOSURE` |
| **Consistencia estricta** | Todo `scenario` ↔ `EtlJob.name`; toda `Column` con `HOSTS`; todo job con `PROCESSES` que cubre sus aristas (validado) |

Resultado esperado de la detección de zonas muertas: **8 columnas muertas, 2 jobs muertos (127.000 €/año), 0 % de columnas vivas en `Legacy Data Mart`**.

## Cómo cargar

1. Elegir dónde se leen los CSV (detalle y problemas típicos en [`../AURA_SETUP.md`](../AURA_SETUP.md)):
   - **Aura (caso de la demo):** los CSV se leen de GitHub (repo público): `:param baseUrl => 'https://raw.githubusercontent.com/earacil/data-lineage-fs-demo/main/data/'` — con `/` final; mejor una etiqueta o SHA que `main` por la caché de `raw.githubusercontent.com`.
   - **Neo4j Desktop / Docker / local:** copiar los `*.csv` a la carpeta `import/` de la instancia y `:param baseUrl => 'file:///'`.
2. Ejecutar `00_load_live.cypher` por segmentos, en orden (0 → P1 → … → P5). Cada segmento es idempotente.
3. El último bloque del script devuelve los recuentos esperados (81 / 7 / 13 / 6 / 7 nodos; 66 / 81 / 113 / 25 / 14 aristas).

## Cómo se garantiza la consistencia

`validate_dataset.py` comprueba, sin depender del generador: claves únicas, referencias huérfanas en las 5 relaciones, enumeraciones del esquema, coherencia `is_synthetic_source` ↔ `kind = CONSTANT`, orden de carga por lotes (ninguna relación referencia una columna de un lote posterior), ausencia de ciclos, y que el conjunto de zonas muertas calculado por un BFS inverso en Python coincide **exactamente** con el esperado.
