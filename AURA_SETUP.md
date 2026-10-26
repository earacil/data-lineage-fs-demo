# Preparar la demo en Aura (carga desde GitHub + Aura Graph Analytics serverless)

> ✅ `baseUrl` y la sesión implícita (proyecciones con `memory`, partes A–C de `03`) los ha probado el autor en Aura el 26-oct-2026 (ver `CONTEXTO_IA.md`, restricción 4); lo nuevo de la parte Z sigue "a validar". Está escrito a partir de la documentación de Neo4j consultada el 22-oct-2026; los límites por plan (tamaño, TTL, nº de sesiones) cambian — **confírmalos en la consola de Aura antes de la demo**.

La demo usa **Aura Graph Analytics (AGA)**, el GDS "serverless": sesiones efímeras y aisladas de la base de datos, que se crean y se destruyen bajo demanda. Se manejan **desde el propio Query tool de Aura con Cypher**, sin Python ni credenciales de la Aura API, y la sesión es **implícita**: la crea la primera proyección y se elimina al borrar sus proyecciones. Esto afecta sólo a `queries/03_zonas_muertas_gds.cypher` (partes A, B, C y Z); `00_load_live.cypher`, `01`, `02` y la parte D de `03` son Cypher normal.

## 1. Requisitos

| Requisito | Detalle |
|---|---|
| Instancia AuraDB | Neo4j 5 o superior. La API Cypher de AGA está documentada para **Professional, Business Critical y Virtual Dedicated Cloud**; en AuraDB Free hay límites más estrictos (1 sesión, 2 GB, TTL corto) — si usas Free, verifica antes que una proyección con `memory` (A.1 de `03`) crea la sesión |
| AGA activado en la organización | Lo hace **un admin de la organización una sola vez**: Aura Console → nombre de la organización → *Settings* → *Feature access* → activar **Aura Graph Analytics**. Ahí mismo se fijan memoria máxima por sesión y nº máximo de sesiones simultáneas |
| La instancia usa AGA, no el plugin GDS clásico | En AuraDB Professional puede elegirse el plugin clásico; este proyecto asume AGA (en *Configure* de la instancia se puede cambiar). Si tu instancia tiene el plugin, `gds.graph.project` clásico funciona en la propia BD y las proyecciones de `03` habría que adaptarlas |
| Coste | Las sesiones se facturan por minuto, **mínimo 10 min por sesión**. Free y Pro Trial no se facturan. Borra la sesión al terminar |
| Credenciales de la Aura API | **No hacen falta** al lanzar la sesión desde el Query tool de tu instancia (te autoriza implícitamente). Sólo son necesarias para administrar sesiones de todo el proyecto en Cypher o para el cliente Python (ver §5) |

## 2. Parámetros que vas a necesitar

Solo hace falta un parámetro, definido en el **Query tool** de la instancia (Aura Console → *Query*). Cada `:param` se ejecuta **por separado**, no mezclado con una query.

| Parámetro | Valor para la demo | Para qué | Cuándo |
|---|---|---|---|
| `baseUrl` | `'https://raw.githubusercontent.com/earacil/data-lineage-fs-demo/main/data/'` | Ruta base de los CSV en `LOAD CSV` (§3). **Con la `/` final** | Antes de la carga |
| `clientId`, `clientSecret`, `projectId` | *(opcionales)* | Sólo para administrar sesiones de todo el proyecto (ver §5). **No** forman parte del flujo normal de la demo | Normalmente nunca |

Cópialo en el Query tool:

```
:param baseUrl => 'https://raw.githubusercontent.com/earacil/data-lineage-fs-demo/main/data/'
```

Notas del Query tool:
- El lado derecho de `=>` se evalúa como Cypher con un `RETURN` implícito (por eso `duration({...})` funciona). Los mapas van entre paréntesis: `:param p => ({a: 1})`.
- Alternativa: el cajón de parámetros `{}` de la interfaz.
- **Los parámetros no se guardan** al refrescar la página ni al cambiar de instancia. Compruébalos con `:params` antes de empezar; bórralos con `:params clear`.
- Los parámetros no sirven para etiquetas, tipos de relación ni claves de propiedad (no se usan en este proyecto).

## 3. `baseUrl`: cargar los CSV desde GitHub

Aura **no puede leer `file:///`**: los CSV tienen que estar en una URL `https` pública. Al subir el proyecto a GitHub, la URL base es:

```
https://raw.githubusercontent.com/earacil/data-lineage-fs-demo/main/data/
```

- Repositorio: `earacil/data-lineage-fs-demo`, rama `main`, carpeta `data/` (equivale a `https://github.com/earacil/data-lineage-fs-demo/tree/main/data`).
- **Rama vs. etiqueta:** `raw.githubusercontent.com` cachea unos minutos. Si editas los CSV y recargas con `main` puedes leer la versión anterior. Para la demo, mejor fijar una etiqueta o un SHA y sustituir `main` en la URL (p. ej. `.../data-lineage-fs-demo/v1.0/data/`).
- **El repositorio debe ser público** (Aura no puede autenticarse contra GitHub). El dataset es sintético y no contiene datos de ningún cliente, por lo que es seguro publicarlo; aun así, repasa el punto 1 de "Cómo verificar" en `CONTEXTO_IA.md` antes del primer push.
- Mantén las rutas de carpeta tal cual: el script espera `columns.csv`, `etl_jobs.csv`, etc. directamente bajo `data/`.

Prueba de humo (debe devolver 7):

```cypher
LOAD CSV WITH HEADERS FROM $baseUrl + 'owners.csv' AS row
RETURN count(row) AS owners;
```

Si falla con *"Couldn't load the external resource"*: comprueba que la URL abre en el navegador, que termina en `/`, que el repo es público y que la rama/etiqueta existe.

## 4. Flujo de una sesión AGA durante la demo (sesión implícita)

```
 proyectar (crea la sesión) → ejecutar algoritmos → borrar las proyecciones (elimina la sesión)
        (03·A.1, B.0)              (03·A.2…C.3)                    (03·Z)
```

1. **Proyecta:** `03`, A.1 usa `gds.graph.project(..., {memory: '2GB'})`, y eso crea la sesión por su cuenta (se aprovisiona en segundos o pocos minutos). B.0 proyecta un segundo grafo; puede crear una segunda sesión implícita.
2. **Ejecuta** los algoritmos de las partes A, B y C contra los grafos proyectados (`lineage_rev`, `lineage_undirected`).
3. **Al terminar, ejecuta la parte Z** (`gds.graph.drop` de cada proyección): al borrarse el último grafo, la sesión se elimina. Comprueba con `gds.session.list()` que no queda ninguna; si queda alguna, `gds.session.delete('<name>')`. Si te olvidas, expira por TTL (1 h por defecto), pero se factura hasta entonces.
4. **Sin sesión, el plan B es la parte D de `03`** (Cypher puro, mismo resultado).

Alternativa (no usada): crear la sesión a mano con `gds.session.getOrCreate(nombre, memoria, ttl)` y pasar `sessionId` a cada proyección, para que todas compartan sesión y no se facture más de una. Hace falta guardar el `id` como parámetro.

## 5. Alternativa: cliente Python (no usada en la demo)

Sólo si algún día se orquesta desde fuera de Aura (CI, notebook). Requiere **credenciales de la Aura API** (distintas de las de la base de datos):

1. Aura Console → *Account settings / API keys* → crear clave → guardar `CLIENT_ID` y `CLIENT_SECRET` **en el momento** (no se pueden ver después).
2. Guardarlas en un `.env` local (**ignorado por `.gitignore`**), nunca en el repositorio ni en un `:param` guardado en un script:
   ```
   CLIENT_ID=...
   CLIENT_SECRET=...
   PROJECT_ID=...        # sólo si tu usuario pertenece a varios proyectos
   ```
3. `GdsSessions(api_credentials=AuraAPICredentials(CLIENT_ID, CLIENT_SECRET, PROJECT_ID))` y `sessions.get_or_create(...)` con `DbmsConnectionInfo(aura_instance_id, username, password)`.
4. Desde fuera de Aura, abrir el puerto de salida **TCP 8491** (Apache Arrow) además de los de AuraDB.

En ese modo no se usa la proyección Cypher de `03` sino `gds.graph.project.cypher(...)` con `gds.graph.project.remote(...)` del cliente Python.

## 6. Problemas típicos

| Síntoma | Causa probable |
|---|---|
| `LOAD CSV` falla al leer la URL | `baseUrl` sin `/` final, repo privado, rama inexistente o caché de `raw.githubusercontent.com` |
| `Variable $baseUrl not defined` / parámetro nulo | Los `:param` se perdieron al refrescar o al cambiar de instancia: ejecuta `:params` y redefínelos |
| La proyección con `memory` falla / `gds.session.*` no existe / no autorizado | AGA sin activar en la organización (§1), instancia con plugin clásico, o plan sin soporte de la API Cypher |
| `Graph with name ... does not exist` al ejecutar un algoritmo | La sesión expiró (TTL) o se borró con Z; vuelve a ejecutar A.1 (y B.0) para proyectar de nuevo |
| El BFS devuelve nodos distintos de los de la BD | Los `nodeId` de la sesión son los ids de nodo de la BD: usa `MATCH (n) WHERE id(n) = nodeId` para volver a los nodos (el script lo hace así) |
| Sesión "olvidada" facturando | Parte Z de `03`; si no basta, `CALL gds.session.list()` y `gds.session.delete`; también visible en la página *Graph Analytics* de la consola |
