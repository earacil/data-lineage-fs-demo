# BLOOM_DEMO_FLOW — guion de escenas (≈10 min)

> **Borrador** construido solo con las 6 search phrases que existen en la perspectiva exportada (ver `BLOOM_GUIDE.md`). No usa estilos condicionales ni scene actions porque no están configurados. Ensayar antes de usarlo.
>
> Estado de datos asumido: dataset completo cargado **y** bloque B de `01_ingesta.cypher` ejecutado (13 `EtlJob`, 15 pares de dependencia). Sin el bloque B, las cifras de los actos 1 y 3 bajan en uno.

## Nota de planificación

Bloom ya se usa en los bloques 1 (C1, C2, C3a/C3b) y 2 (frases «1» y «2») del `RUNBOOK_DEMO.md`. Este bloque 4 es, por tanto, un **repaso en modo exploración**: la audiencia elige la columna o el informe. Si el tiempo aprieta, se puede suprimir y repartir sus 10 minutos entre los bloques 2 y 3.

## Acto 1 · «El mapa» (2 min) — `C3a` y, si se quiere, `C3b`

- **Acción:** lanzar `C3a. Show Jobs dependency Map with Columns`; después `C3b` para ver lo mismo con aristas job → job directas.
- **Qué se ve:** los 13 jobs enlazados en cadena `LOAD_* → CALC_* → BUILD_*`, y `LOAD_CRM_CUSTOMERS`, `LOAD_CORE_ACCOUNTS` y `LOAD_CARD_TRANSACTIONS` abriéndose en abanico.
- **Decir:** «Ninguna de estas dependencias está declarada en ningún sitio. Salen de los datos: un job escribe una columna que otro lee.»

## Acto 2 · «Si cambia esto» (3 min) — `1. Column $column impact`

- **Acción:** elegir `CORE.LOAN.DRAWN_AMOUNT` en el desplegable. Dejar que el público proponga otra columna después.
- **Qué se ve:** 8 columnas en la descendencia, 4 jobs (`LOAD_CORE_LOANS`, `CALC_EXPOSURE`, `CALC_RWA`, `BUILD_COREP_SOLVENCY`), sus dueños y 3 informes (Solvency Report, Large Exposures Report, Risk Data Aggregation Dashboard).
- **Decir:** «A quién avisar y qué volver a ejecutar, en una sola pantalla.»
- **Gancho:** señalar `EXPOSURE_ADJ_LEGACY`, que aparece **sin informe** al final de su rama. «Esta columna se calcula cada noche y no la lee nadie»: enlaza con el bloque 3.

## Acto 3 · «De dónde sale» (3 min) — `2. Full Path to FinalConsumer $finalConsumer` y `C2`

- **Acción:** elegir `Solvency Report`; ver el camino sistema → origen → … → informe.
- **Decir:** «Esto es BCBS 239: cada cifra del informe traza hasta su sistema de origen.»
- **Acción:** lanzar `C2. Column $column lineage` con `REG_MART.CAPITAL.RWA_DENSITY` (la columna que carga el proyecto nuevo del bloque 1) y comparar.
- **Ojo:** hoy `C2` no pinta el `SourceSystem` y `2.` sí (ver «Diferencias» en `BLOOM_GUIDE.md`). Decidir antes del ensayo si se iguala la frase; si no, aprovecharlo como pregunta: «¿y de qué sistema viene? → esta otra frase lo dice».

## Acto 4 · «Y lo que sobra» (2 min) — puente al dashboard

- **Acción:** volver a la pantalla del acto 2 con `EXPOSURE_ADJ_LEGACY` y abrir el dashboard «Data Lineage Dead Zones».
- **Decir:** «Bloom enseña la estructura; el dashboard cuenta cuánto sobra y cuánto cuesta.» (127.000 €/año en jobs sin consumidor.)
- **Limitación actual:** no hay frase de Bloom para zonas muertas; la transición es manual.

## Plan B

- Si una frase con parámetro no devuelve resultados, comprobar el valor elegido en el desplegable y que el dataset esté cargado.
- Si `C3b` no dibuja (usa `apoc.create.vRelationship`, relaciones virtuales), quedarse con `C3a`.
