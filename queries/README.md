# queries/

Organizado por **ángulo de negocio**, no por tipo de nodo (mismo criterio que `queries/` en el repo de referencia).

> ✅ `01_ingesta` validada en Aura por el autor (26-oct-2026). ⚠️ **`02_impacto` y `03_zonas_muertas_gds` siguen sin validar** (ver `../CONTEXTO_IA.md`, restricción 4); en `03` las llamadas `gds.*` dependen de Aura Graph Analytics. `04` es una nota, no se ejecuta entera. Cualquier cambio posterior vuelve a ser "a validar". Requiere haber cargado antes `../data/00_load_live.cypher`. Para `03` hace falta además **Aura Graph Analytics** (GDS serverless) y los parámetros `sessionName`, `sessionMemory`, `sessionTtl` y `sessionId`: ver [`../AURA_SETUP.md`](../AURA_SETUP.md).

| Fichero | Ángulo | Qué contiene |
|---|---|---|
| `01_ingesta.cypher` | 1 · Ingesta | Foto antes/después, ingesta de un proyecto nuevo (`BUILD_RWA_DENSITY`) con `MERGE` idempotente que se auto-conecta a columnas de otros proyectos, evidencia de la auto-conexión, mapa de dependencias entre jobs, comprobaciones de salud de la ingesta, reset del demo |
| `02_impacto.cypher` | 2 · Impacto | Linaje ascendente y descendente por `fqn`, camino sistema → informe, blast radius por sistema y por job, casos especiales (`CASE WHEN` multi-origen, `CONSTANT`, `TABLE`), centralidad, trazabilidad BCBS 239 por informe regulatorio. Cypher puro |
| `03_zonas_muertas_gds.cypher` | 3 · Zonas muertas | Parte 0: crear la sesión AGA. Parte A: proyección (dirección invertida) + BFS en reversa desde `FinalConsumer`. Parte B: por qué WCC no basta. Parte Z: borrar la sesión. Parte C: **fallback en Cypher puro** (`NOT EXISTS` de alcanzabilidad), puntos de bifurcación, jobs muertos con ahorro (127.000 €/año), salud por sistema |
| `04_productivizacion.md` | 5 · Productivización | **No ejecutable.** Buenas prácticas (ingesta idempotente, separación de capas técnica/semántica, informe periódico de zonas muertas, escala) con 3 queries de ejemplo |

Los literales que se cambian al reutilizar una query en 02 (columna, sistema, job, informe) están marcados con `← CAMBIA`.

## Resultados esperados con el dataset de ejemplo

Calculados sobre los CSV con `../data/validate_dataset.py` (no con Neo4j):

- `REG_MART.SOLVENCY.TOTAL_RWA` tiene 3 orígenes crudos en **2 sistemas** (`Core Banking PL/SQL`, `SAS Risk Engine`) a través de **5 jobs de 3 proyectos**.
- 8 columnas muertas: 5 en una zona aislada, 2 en una rama de un dato vivo con job activo (`PROMO_SEGMENT_EXTRACT`), 1 en un job vivo (`CALC_EXPOSURE` → `EXPOSURE_ADJ_LEGACY`).
- 2 jobs muertos (`PROMO_SEGMENT_EXTRACT` 42.000 € + `LEGACY_BRANCH_REPORT` 85.000 €) = **127.000 €/año**; `LEGACY_BRANCH_REPORT` además sin propietario.
