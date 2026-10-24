# Modelo de datos — Data Lineage Demo (Financial Services)

Convención: **todos los nombres de nodo, relación y propiedad están en inglés** (son los identificadores que se usarán en Cypher). La prosa descriptiva de este documento se mantiene en español.

Cada nodo/relación indica su procedencia: **PATRÓN REAL** (inspirado en un caso real de linaje a nivel de columna observado en banca, ver `NOTAS_DISENO.md`), o **NUEVO** (diseñado para esta demo genérica).

---

## Nodos

### `Column` — PATRÓN REAL

Unidad mínima del linaje técnico: una columna física en una tabla o vista.

| Propiedad | Tipo | Procedencia | Descripción |
|---|---|---|---|
| `fqn` | string | PATRÓN REAL | Nombre totalmente cualificado (`SCHEMA.TABLE.COLUMN`) — identificador lógico único |
| `name` | string | PATRÓN REAL | Nombre de la columna |
| `kind` | string | PATRÓN REAL (ampliado) | `"COLUMN"` \| `"TABLE"` \| `"CONSTANT"` — cubre los casos de referencia a tabla completa (ej. `COUNT(*)`) y valores fijos sin columna de origen |
| `data_type` | string | PATRÓN REAL (renombrada de `formato`) | Tipo de dato de origen (ej. `"NUMBER(4)"`) |
| `field_type` | string | PATRÓN REAL | Clasificación semántica automática inferida (ej. `"counter"`) |
| `field_type_evidence` | string | PATRÓN REAL | Texto que justifica la inferencia de `field_type` |

### `TRANSFORMS_TO` (relación `Column → Column`) — PATRÓN REAL

| Propiedad | Tipo | Procedencia | Descripción |
|---|---|---|---|
| `id` | string | PATRÓN REAL | Hash propio de deduplicación, distinto del `<id>` interno de Neo4j |
| `scenario` | string | PATRÓN REAL (renombrada de `escenario`) | Nombre del job/paquete ETL de origen — ver nodo `EtlJob` (NUEVO) para la versión promocionada; debe coincidir con `EtlJob.name` |
| `transformation_expression` | string | PATRÓN REAL (renombrada de `expresion_transformacion`) | Expresión u origen de la transformación |
| `filters` | list[string] | PATRÓN REAL (renombrada de `filtros`) | Condiciones de filtro aplicadas, modeladas aparte de la expresión principal |
| `is_synthetic_source` | boolean | PATRÓN REAL (renombrada y tipada de `fuente_sintetica`) | `true` si el origen es un valor fijo/constante en vez de una columna real |

---

### `SourceSystem` — NUEVO

Sistema del que procede físicamente un dato, antes de cualquier transformación. Hace explícita la heterogeneidad de fuentes típica en banca (core bancario, herramientas de BI, plataformas cloud).

| Propiedad | Tipo | Descripción |
|---|---|---|
| `id` | string | Identificador único |
| `name` | string | Ej. `"Core Banking PL/SQL"`, `"SAS Risk Engine"`, `"Commercial BI"`, `"Cloud Data Platform"` |
| `technology` | string | Ej. `"PL/SQL"`, `"SAS"`, `"Qlik"`, `"BigQuery"` |
| `type` | string | Ej. `"Core banking"`, `"CRM"`, `"Risk"`, `"BI"` |
| `criticality` | string | `"High"` \| `"Medium"` \| `"Low"` |

### `EtlJob` — NUEVO

Promociona el concepto de job/paquete ETL (hoy un simple string `scenario` en `TRANSFORMS_TO`) a nodo de primer nivel. Resuelve una limitación habitual: con fórmulas multi-origen se repite el mismo `scenario` en N aristas distintas, sin forma de preguntar por el job en sí (coste, propietario, estado).

| Propiedad | Tipo | Descripción |
|---|---|---|
| `id` | string | Identificador único |
| `name` | string | Debe coincidir con los valores de `scenario` usados en `TRANSFORMS_TO` |
| `frequency` | string | `"Daily"` \| `"Weekly batch"` \| `"Real-time"` |
| `owning_team` | string | Equipo responsable |
| `estimated_compute_cost` | int | Coste anual estimado (€) — habilita el argumento de ahorro en el ángulo de zonas muertas |
| `status` | string | `"Active"` \| `"Deprecated"` |

### `FinalConsumer` — NUEVO

Sustituye a un simple flag booleano de "consumo final" por un nodo con sustancia de negocio: un informe regulatorio, un cuadro de mando o un modelo de IA que realmente usa el dato. Es el ancla del argumento de BCBS 239: poder demostrar que cada cifra reportada traza hasta su origen.

| Propiedad | Tipo | Descripción |
|---|---|---|
| `id` | string | Identificador único |
| `name` | string | Ej. `"Solvency Report"`, `"Expense Dashboard"` |
| `type` | string | `"Regulatory"` \| `"Dashboard"` \| `"AI Model"` |
| `regulation` | string | Ej. `"BCBS239"`, `"COREP"`, `"FINREP"` — `"N/A"` si no es regulatorio |
| `periodicity` | string | Ej. `"Monthly"`, `"Quarterly"` |

### `Owner` — NUEVO

Accountability explícita por job/columna — requisito directo de marcos como BCBS 239.

| Propiedad | Tipo | Descripción |
|---|---|---|
| `id` | string | Identificador único |
| `name` | string | Persona o equipo |
| `role` | string | Ej. `"Data Owner"`, `"Technical Lead"` |

---

## Relaciones nuevas

| Relación | Patrón | Descripción |
|---|---|---|
| `HOSTS` | `(SourceSystem)-[:HOSTS]->(Column)` | El sistema origen contiene físicamente esta columna/tabla en su estado crudo |
| `PROCESSES` | `(EtlJob)-[:PROCESSES]->(Column)` | El job lee o escribe esta columna (no diferencia lectura/escritura; para eso ya existe `TRANSFORMS_TO` a nivel columna) |
| `FEEDS` | `(Column)-[:FEEDS]->(FinalConsumer)` | La columna es consumida por un informe, dashboard o modelo final |
| `MAINTAINED_BY` | `(EtlJob)-[:MAINTAINED_BY]->(Owner)` | Quién es responsable de mantener el job |

---

## Diagrama conceptual

```
(SourceSystem) -[:HOSTS]-> (Column) -[:TRANSFORMS_TO*]-> (Column) -[:FEEDS]-> (FinalConsumer)
                                 ↑
                          (EtlJob) -[:PROCESSES]-> (Column)
                                 |
                          [:MAINTAINED_BY]
                                 ↓
                            (Owner)
```

Una "zona muerta" (ángulo 3) deja de ser un flag arbitrario: es cualquier `Column` (o `EtlJob`) sin ninguna ruta dirigida hasta un `FinalConsumer`.

## Nota de nomenclatura

Esta versión en inglés reemplaza una iteración anterior donde las entidades nuevas usaban nombres en español (`SistemaOrigen`, `JobETL`, `ConsumidorFinal`, `Propietario`, `ALBERGA`, `PROCESA`, `ALIMENTA_A`, `MANTENIDO_POR`) y algunas propiedades del patrón real mantenían el término original (`escenario`, `formato`, `expresion_transformacion`, `filtros`, `fuente_sintetica`). Si se encuentra cualquier referencia a esos nombres en otro documento de este proyecto, está desactualizada y debe corregirse a la tabla de arriba.
