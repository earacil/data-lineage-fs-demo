# Notas de diseño — conocimiento del proyecto

## Qué es real y qué es sintético (importante no confundir)

- **Patrón real**: el nodo `Column` y la relación `TRANSFORMS_TO`, con sus propiedades, están inspirados en un caso real de linaje a nivel de columna visto en un cliente de banca (modelo genérico por proyecto ETL: nodos se autoconectan entre proyectos distintos porque la salida de uno es la entrada de otro, sin trabajo de integración manual).
- **Sintético, diseñado para esta demo**: todo el dataset final (nombres de sistemas, jobs, informes, propietarios y valores concretos) y los 4 tipos de nodo nuevos (`SourceSystem`, `EtlJob`, `FinalConsumer`, `Owner`). No representan el grafo real de ningún cliente — son una historia plausible de banca construida para que los 5 ángulos de la demo tengan sentido narrativo y técnico.
- Esto debe quedar explícito en cualquier presentación: se trata de "un dataset de ejemplo de Financial Services", no de un acceso a datos reales de un cliente.

## Por qué este modelo (decisiones de diseño)

- **`Column`/`TRANSFORMS_TO` sin modificar**: es el patrón mínimo que ya ha demostrado funcionar en un caso real (ver arriba); cambiarlo rompería la credibilidad de "esto ya lo hemos visto funcionar en banca".
- **`EtlJob` como nodo y no solo como propiedad `scenario`**: las fórmulas multi-origen (`CASE WHEN` con varias columnas) generan N aristas con el mismo `scenario` repetido — sin nodo propio no se puede preguntar por coste, frecuencia o propietario de un job. Promocionarlo resuelve esto y añade una dimensión de FinOps/gobierno.
- **`FinalConsumer` en vez de un booleano de "consumo final"**: un flag no cuenta ninguna historia. Un nodo con `type`/`regulation` conecta directamente con el argumento central de BCBS 239 — poder demostrar que cada cifra de un informe regulatorio traza hasta su origen — y convierte el ángulo de "zonas muertas" en lenguaje de negocio, no solo técnico.
- **`SourceSystem`**: hace explícita la heterogeneidad de fuentes (core bancario, SAS, BI, plataformas cloud) típica en banca — permite que el ángulo de "impacto" también se cuente a nivel de sistema ("si cae este sistema origen, ¿qué informes se ven afectados?").
- **`Owner`**: requisito explícito de accountability de BCBS 239.
- **Todos los identificadores del modelo (nodos, relaciones, propiedades) en inglés**: es la convención habitual en Cypher y hace el proyecto entendible sin depender del español — la prosa de estos documentos sí se mantiene en español.

## Fuentes de inspiración

- [`neo4j-data-asset-intelligence-graph`](https://github.com/halftermeyer/neo4j-data-asset-intelligence-graph) — no es de Financial Services ni de lineage puro (es un grafo de atribución de ROI de datos alternativos para un hedge fund), pero se tomó de ahí: la estructura de repo (`README.md` con el problema de negocio primero, `data-model/SCHEMA.md`, `queries/` organizadas por ángulo de negocio y no por entidad, `bloom/` con guía de estilos + guion en "actos" con talking points entre comillas), y el patrón de encadenar varios tipos de nodo en una única cadena de valor en vez de un solo nodo genérico.
- Artículo de LinkedIn de Michael Down, "Neo4j Graph Data Platform & BCBS 239 - Data Lineage" — framing regulatorio específico de banca (BCBS 239, caso de referencia UBS) y los 5 argumentos de por qué un grafo encaja mejor que un modelo relacional para lineage: modelado de relaciones y dirección del dato, flexibilidad para representar lógica SQL abstracta (`CASE WHEN`), trazabilidad de cambios en tiempo real o batch, integración (no sustitución) de catálogos de metadatos existentes, y escalabilidad a volúmenes muy grandes.

## Antes de usar esta demo con un cliente concreto

- Personalizar nombres de sistemas, jobs e informes al contexto del cliente (sector, regulación aplicable, jerga interna) — hacerlo en una copia o capa aparte, sin modificar esta versión genérica.
- Confirmar con el equipo técnico del cliente los casos de uso reales que se quieren representar, en vez de asumir que el dataset de ejemplo encaja tal cual.
- Validar todo el Cypher y el pipeline GDS en un entorno real (Aura o Desktop con GDS) antes de cualquier demo en vivo — este proyecto se diseñó sin acceso a una instancia Neo4j para ejecutarlo.
- Revisar que ningún nombre, cifra o captura de un cliente real se haya colado en el dataset de ejemplo antes de reutilizarlo con otro cliente.
