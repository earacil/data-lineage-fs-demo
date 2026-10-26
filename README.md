# Data Lineage Demo — Financial Services

> Estado: **modelo, dataset sintético, queries, dashboards y perspectiva de Bloom hechos y validados en Aura por el autor (26-oct-2026); `02_impacto` salvo su sección 4 (material de apoyo). Pendiente solo ensayar la demo con cronómetro.**
>
> **¿Eres una IA retomando este proyecto?** Lee primero [`CONTEXTO_IA.md`](CONTEXTO_IA.md) — tiene las restricciones duras, el estado exacto y los próximos pasos con criterios de aceptación.

## Qué es esto

Demo genérica y reutilizable de **data lineage sobre Neo4j para Financial Services**: cómo trazar el origen, transformación y consumo final de un dato a través de un pipeline ETL, usando un grafo en vez de un modelo relacional. Pensada para mostrarse a cualquier cliente del sector (banca, seguros, gestión de activos) con necesidades de gobierno de datos, trazabilidad regulatoria (ej. BCBS 239) o limpieza de pipelines heredados — **sin personalizar a ningún cliente concreto** salvo que se indique lo contrario al prepararla para una reunión específica.

## Por qué un grafo (resumen)

- **Modelado de relaciones y dirección del dato**: un grafo representa de forma natural cómo fluye un dato entre sistemas; un modelo relacional lo fuerza a joins frágiles.
- **Flexibilidad para lógica de transformación abstracta**: casos como un `CASE WHEN` con varios orígenes, un valor constante sin columna de origen, o una agregación sobre una tabla completa, se modelan de forma natural como nodos y relaciones.
- **Trazabilidad de cambios**, en tiempo real o por lotes.
- **Integra con el catálogo de metadatos existente del cliente** (ej. OpenMetadata, Purview) en vez de sustituirlo — el grafo añade la capa de linaje técnico y relacional que el catálogo no resuelve bien.
- **Escalabilidad** a volúmenes grandes de columnas/transformaciones.

Fuentes de inspiración y framing regulatorio completo en [`data-model/NOTAS_DISENO.md`](data-model/NOTAS_DISENO.md).

## Los 5 ángulos de la demo

Cada uno se corresponde con un fichero de `queries/` o `bloom/`, no con una entidad del modelo:

1. **Ingesta end-to-end** — cómo cargar, mantener y escalar el grafo a medida que se añaden proyectos/pipelines ETL. → `queries/01_ingesta.cypher`
2. **Impacto ascendente/descendente** — Cypher de trazado de linaje completo e impacto de un cambio. → `queries/02_impacto.cypher`
3. **Zonas muertas con GDS** — detección de columnas/jobs que no alimentan ningún consumidor final. → `queries/03_zonas_muertas_gds.cypher`
4. **Bloom** — visualización del grafo, usada dentro de los ángulos 1 y 2. → `bloom/data_lineage_fs_perspective.json` + `bloom/BLOOM_GUIDE.md`
5. **Productivización** — buenas prácticas de ingesta idempotente, propiedad y monitorización continua. Se cuenta como cierre corto de la demo. → `RUNBOOK_DEMO.md`, bloque 7

## Estructura del proyecto

```
data-lineage-fs-demo/
├── README.md                     ← este fichero
├── RUNBOOK_DEMO.md                ← guion de la hora completa, con timing (plantilla genérica)
├── AURA_SETUP.md                  ← preparar Aura: carga desde GitHub (`baseUrl`) y parámetros de Aura Graph Analytics
├── .gitignore                     ← excluye credenciales y artefactos locales; los CSV/.cypher/.json SÍ se versionan
├── data-model/
│   ├── SCHEMA.md                  ← nodos y relaciones, qué es real y qué es nuevo
│   └── NOTAS_DISENO.md            ← decisiones de diseño, qué es sintético, fuentes
├── data/                          ← CSVs del dataset sintético, script de carga `LOAD CSV`, generador y validador
├── queries/                       ← .cypher por ángulo de negocio
├── dashboards/                    ← exports de los dashboards de Aura (impacto y zonas muertas) + DASHBOARDS_GUIDE.md
└── bloom/                         ← perspectiva exportada de Aura y BLOOM_GUIDE.md
```

## Estado actual / próximos pasos

- [x] Modelo de datos diseñado (6 tipos de nodo)
- [x] Estructura de carpetas y documentación base
- [x] Generar dataset sintético multi-proyecto (CSV + LOAD CSV, carga en vivo) — consistencia comprobada con `data/validate_dataset.py`
- [x] Escribir las 3 queries de los ángulos 1-3 — validadas en Aura
- [x] Productivización (ángulo 5): integrada como cierre corto del runbook (sin fichero aparte)
- [x] Dashboard de impacto creado y exportado (`dashboards/`)
- [x] `02_impacto` validada (la sección 4 queda fuera de la demo)
- [x] `03_zonas_muertas_gds` validada en Aura (partes A, B, C, Z y D)
- [x] Dashboard «Data Lineage Dead Zones» creado y exportado (`dashboards/`)
- [x] Configurar la perspectiva de Bloom en Aura (ángulo 4)
- [x] Perspectiva exportada a `bloom/data_lineage_fs_perspective.json` y documentada en `bloom/BLOOM_GUIDE.md`
- [x] `RUNBOOK_DEMO.md` cerrado (Bloom y dashboards integrados en los bloques de ingesta e impacto)
- [ ] Ensayar la demo con cronómetro
- [ ] Al preparar esta demo para un cliente concreto: ajustar nombres de sistemas/informes a su contexto real, sin tocar esta versión genérica — crear una copia o una capa de personalización aparte

## Uso con un cliente concreto

Esta carpeta se mantiene **sin nombre de cliente**. Si se usa para preparar una reunión con un cliente específico, la referencia a esa preparación (fecha, asistentes, contexto) debe vivir en el `Context.md` del cliente correspondiente dentro de `Customers/`, apuntando aquí — no al revés.
