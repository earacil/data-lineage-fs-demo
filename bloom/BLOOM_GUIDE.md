# BLOOM_GUIDE — perspectiva «Data Lineage FS Perspective»

Referencia de **lo que contiene realmente** `data_lineage_fs_perspective.json` (exportado de Aura el 26-oct-2026, Bloom `version 2.21.0`). Todo lo de este fichero sale del export; no se ha añadido nada que no esté configurado.

## Cómo importarla

1. Aura → Explore (Bloom) conectado a la instancia de la demo, con el dataset ya cargado (`data/00_load_live.cypher`).
2. Galería de perspectivas → importar → elegir `bloom/data_lineage_fs_perspective.json`.
3. Comprobar que las 6 search phrases aparecen y que los desplegables de parámetros devuelven valores (si salen vacíos, el dataset no está cargado).

## Modelo reconocido

5 categorías (una por label) y 5 tipos de relación; la perspectiva dibuja estos caminos:

`SourceSystem -HOSTS-> Column -TRANSFORMS_TO-> Column -FEEDS-> FinalConsumer` y `EtlJob -PROCESSES-> Column`, `EtlJob -MAINTAINED_BY-> Owner`.

## Estilo (por defecto, sin personalizar)

| Categoría | Color | Caption | Tooltip |
|---|---|---|---|
| `Column` | `#FFE081` (amarillo) | `name` | `name` |
| `EtlJob` | `#C990C0` (lila) | `name` | `name` |
| `FinalConsumer` | `#F79767` (naranja) | `name` | `name` |
| `Owner` | `#57C7E3` (azul) | `name` | `name` |
| `SourceSystem` | `#F16667` (rojo) | `name` | `name` |

- Tamaño 1 y sin icono en todas las categorías; relaciones en gris con su tipo como caption.
- **Sin reglas de estilo condicional** (`styleRules` vacío en categorías y relaciones): no hay nada coloreado por `status`, `criticality`, etc.
- **Sin scene actions** (`sceneActions: []`).
- Consecuencia práctica: el guion no puede apoyarse en «los nodos rojos son…» más allá del color por tipo. Un `Column` se llama por su `name` (p. ej. `DRAWN_AMOUNT`), no por su `fqn`; para ver el `fqn` hay que abrir el nodo.

## Search phrases (en el JSON, `templates`)

Seis frases, todas de solo lectura. Las que llevan parámetro ofrecen un desplegable cuya lista sale de una query (no hay que teclear el nombre).

| Texto en Bloom | Parámetro (desplegable) | Qué dibuja | Query equivalente |
|---|---|---|---|
| `C1. Job $etlJob connection` | `$etlJob` ← nombres de `EtlJob` | Job → columnas que comparte → otros jobs que las procesan | `01` C.1b |
| `C2. Column $column lineage` | `$column` ← `fqn` de `Column` | Orígenes crudos → … → la columna (solo `Column`, **sin** el tramo `SourceSystem`) | `01` C.2b sin `HOSTS` (ver nota) |
| `C3a. Show Jobs dependency Map with Columns` | — | Job productor → columna puente ← job consumidor | `01` C.3b |
| `C3b. Show Jobs dependency Map` | — | Aristas virtuales `DEPENDENCY` job → job (usa `apoc.create.vRelationship`) | `01` C.3c |
| `1. Column $column impact` | `$column` ← `fqn` de `Column` | Linaje descendente + jobs + dueños + informes | `02` sección 1 |
| `2. Full Path to FinalConsumer $finalConsumer` | `$finalConsumer` ← `name` de `FinalConsumer` | Sistema → origen → … → columna → informe | `02` 2.a |

## Diferencias entre el export y las queries del repo, y notas

- **C2 sin `HOSTS`.** `01` C.2b ya incluye `(:SourceSystem)-[:HOSTS]->` para enseñar de qué sistema sale cada origen; la frase de Bloom no. Si se quiere el mismo resultado, la frase debería usar `MATCH p = (:SourceSystem)-[:HOSTS]->(root:Column)-[:TRANSFORMS_TO*1..10]->(:Column {fqn: $column})`.
- **Comentarios en la frase «1».** Conserva `// ← CAMBIA` en la query, pero ya es parametrizada (`$column`); el comentario sobra. En la frase C3a quedan comentarios `// producer ESCRIBE c` / `// consumer LEE c`, inocuos.
- **Nombres internos** de algunas frases (campo `name`, no el texto que ve el usuario): «Full path to FinalCustomer», «Impact produced by a change on a Query». Solo afectan a la gestión de la perspectiva, no a la demo.
- **`policy.userRoles`** se ha vaciado (`[]`) a mano en el JSON del repo para no publicar el identificador de usuario de Aura de quien exportó. Si se vuelve a exportar desde Bloom, repetir esa limpieza antes de hacer commit.

## Qué NO hay (por si se quiere ampliar)

- Frase para zonas muertas (el ángulo 3 se ve en el dashboard «Data Lineage Dead Zones», no en Bloom; la query de grafo equivalente es `03` A.5 / D.3).
- Estilo condicional (p. ej. `EtlJob.status = 'Deprecated'` en rojo).
- Scene actions («¿qué rompe si cambia esto?» sobre el nodo seleccionado).
