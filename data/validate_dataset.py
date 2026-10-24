#!/usr/bin/env python3
"""
Valida los CSV de esta carpeta de forma independiente al generador (sólo lee los CSV).

Comprueba:
  1. Integridad referencial: ninguna relación apunta a un nodo inexistente.
  2. Consistencia del modelo: todo `scenario` tiene un EtlJob.name; toda Column tiene HOSTS;
     enumeraciones válidas; ids únicos; kind CONSTANT <-> is_synthetic_source.
  3. Orden de carga: las relaciones de un lote Pn sólo referencian columnas de lotes <= Pn.
  4. Criterios de aceptación del dataset (ver ../CONTEXTO_IA.md, paso 1).
  5. Zonas muertas calculadas aquí (BFS inverso en Python) == zonas muertas esperadas.

Uso:  python3 validate_dataset.py     (código de salida != 0 si algo falla)
"""
import csv
import sys
from collections import defaultdict, deque
from pathlib import Path

D = Path(__file__).parent
errors, notes = [], []


def rd(name):
    with open(D / name, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def check(cond, msg):
    if not cond:
        errors.append(msg)


columns, systems, jobs = rd("columns.csv"), rd("source_systems.csv"), rd("etl_jobs.csv")
consumers, owners = rd("final_consumers.csv"), rd("owners.csv")
transforms, hosts, processes = rd("transforms_to.csv"), rd("hosts.csv"), rd("processes.csv")
feeds, maintained = rd("feeds.csv"), rd("maintained_by.csv")

# ---- 1. Unicidad de claves ----
for label, rows, key in [("columns", columns, "fqn"), ("source_systems", systems, "id"),
                         ("etl_jobs", jobs, "id"), ("etl_jobs.name", jobs, "name"),
                         ("final_consumers", consumers, "id"), ("owners", owners, "id"),
                         ("transforms_to", transforms, "id")]:
    vals = [r[key] for r in rows]
    check(len(vals) == len(set(vals)), f"{label}: valores duplicados en '{key}'")

col_fqns = {c["fqn"] for c in columns}
col_batch = {c["fqn"]: c["load_batch"] for c in columns}
sys_ids, job_ids = {s["id"] for s in systems}, {j["id"] for j in jobs}
job_names = {j["name"] for j in jobs}
job_batch = {j["id"]: j["load_batch"] for j in jobs}
fc_ids, owner_ids = {c["id"] for c in consumers}, {o["id"] for o in owners}

# ---- 2. Enumeraciones ----
for c in columns:
    check(c["kind"] in {"COLUMN", "TABLE", "CONSTANT"}, f"kind inválido: {c['fqn']}={c['kind']}")
    check(c["name"] == c["fqn"].split(".")[-1], f"name != último segmento de fqn: {c['fqn']}")
for j in jobs:
    check(j["frequency"] in {"Daily", "Weekly batch", "Real-time"}, f"frequency inválida: {j['name']}")
    check(j["status"] in {"Active", "Deprecated"}, f"status inválido: {j['name']}")
    check(j["estimated_compute_cost"].isdigit(), f"estimated_compute_cost no entero: {j['name']}")
for s in systems:
    check(s["criticality"] in {"High", "Medium", "Low"}, f"criticality inválida: {s['name']}")
for fc in consumers:
    check(fc["type"] in {"Regulatory", "Dashboard", "AI Model"}, f"type inválido: {fc['name']}")
    check(fc["type"] != "Regulatory" or fc["regulation"] != "N/A",
          f"consumer regulatorio sin regulation: {fc['name']}")

# ---- 3. Integridad referencial ----
for t in transforms:
    check(t["source_fqn"] in col_fqns, f"transforms_to {t['id']}: origen inexistente {t['source_fqn']}")
    check(t["target_fqn"] in col_fqns, f"transforms_to {t['id']}: destino inexistente {t['target_fqn']}")
    check(t["scenario"] in job_names, f"transforms_to {t['id']}: scenario sin EtlJob ({t['scenario']})")
    check(t["is_synthetic_source"] in {"true", "false"}, f"transforms_to {t['id']}: boolean inválido")
    src_kind = next(c["kind"] for c in columns if c["fqn"] == t["source_fqn"])
    check((src_kind == "CONSTANT") == (t["is_synthetic_source"] == "true"),
          f"transforms_to {t['id']}: is_synthetic_source incoherente con kind={src_kind}")
    check(t["source_fqn"] != t["target_fqn"], f"transforms_to {t['id']}: auto-bucle")
    for flt in (t["filters"].split("|") if t["filters"] else []):
        check(flt.strip() != "", f"transforms_to {t['id']}: filtro vacío")
for h in hosts:
    check(h["source_system_id"] in sys_ids, f"hosts: sistema inexistente {h['source_system_id']}")
    check(h["column_fqn"] in col_fqns, f"hosts: columna inexistente {h['column_fqn']}")
for p in processes:
    check(p["job_id"] in job_ids, f"processes: job inexistente {p['job_id']}")
    check(p["column_fqn"] in col_fqns, f"processes: columna inexistente {p['column_fqn']}")
for f in feeds:
    check(f["column_fqn"] in col_fqns, f"feeds: columna inexistente {f['column_fqn']}")
    check(f["consumer_id"] in fc_ids, f"feeds: consumer inexistente {f['consumer_id']}")
for m in maintained:
    check(m["job_id"] in job_ids, f"maintained_by: job inexistente {m['job_id']}")
    check(m["owner_id"] in owner_ids, f"maintained_by: owner inexistente {m['owner_id']}")

# ---- 4. Consistencia estricta (criterio de aceptación) ----
hosted = {h["column_fqn"] for h in hosts}
check(not (col_fqns - hosted), f"Columnas sin HOSTS: {sorted(col_fqns - hosted)}")
used_scenarios = {t["scenario"] for t in transforms}
check(used_scenarios <= job_names, f"scenarios sin EtlJob: {sorted(used_scenarios - job_names)}")
check(not (job_names - used_scenarios), f"EtlJob sin ninguna TRANSFORMS_TO: {sorted(job_names - used_scenarios)}")
touched_by_edges = {t["source_fqn"] for t in transforms} | {t["target_fqn"] for t in transforms}
check(not (col_fqns - touched_by_edges), f"Columnas huérfanas (sin TRANSFORMS_TO): {sorted(col_fqns - touched_by_edges)}")
proc_by_job = defaultdict(set)
for p in processes:
    proc_by_job[p["job_id"]].add(p["column_fqn"])
for t in transforms:
    jid = next(j["id"] for j in jobs if j["name"] == t["scenario"])
    check(t["source_fqn"] in proc_by_job[jid] and t["target_fqn"] in proc_by_job[jid],
          f"PROCESSES no cubre la transformación {t['id']} del job {t['scenario']}")

# ---- 5. Orden de carga por lotes ----
order = {"P1": 1, "P2": 2, "P3": 3, "P4": 4, "P5": 5}
for t in transforms:
    b = order[t["load_batch"]]
    check(order[job_batch[next(j["id"] for j in jobs if j["name"] == t["scenario"])]] == b,
          f"transforms_to {t['id']}: load_batch != batch del job")
    for fqn in (t["source_fqn"], t["target_fqn"]):
        check(order[col_batch[fqn]] <= b, f"transforms_to {t['id']}: {fqn} se carga en {col_batch[fqn]} > {t['load_batch']}")
for p in processes:
    check(order[col_batch[p["column_fqn"]]] <= order[p["load_batch"]], f"processes: {p['column_fqn']} cargada después de su job")
for f in feeds:
    check(f["load_batch"] == col_batch[f["column_fqn"]], f"feeds: load_batch incoherente para {f['column_fqn']}")
for h in hosts:
    check(h["load_batch"] == col_batch[h["column_fqn"]], f"hosts: load_batch incoherente para {h['column_fqn']}")

# ---- 6. Criterios de aceptación del contenido ----
children, parents = defaultdict(set), defaultdict(set)
for t in transforms:
    children[t["source_fqn"]].add(t["target_fqn"])
    parents[t["target_fqn"]].add(t["source_fqn"])

# 6a. Auto-conexión entre proyectos: una columna escrita por un job y leída por otro de un lote distinto
written_by = defaultdict(set)
read_by = defaultdict(set)
for t in transforms:
    written_by[t["target_fqn"]].add(t["scenario"])
    read_by[t["source_fqn"]].add(t["scenario"])
cross = [(fqn, w, r) for fqn in written_by for w in written_by[fqn] for r in read_by.get(fqn, ())
         if w != r and next(j["load_batch"] for j in jobs if j["name"] == w)
         != next(j["load_batch"] for j in jobs if j["name"] == r)]
check(len(cross) >= 1, "No hay ninguna columna que conecte dos proyectos distintos")
notes.append(f"Conexiones entre proyectos (columna compartida escrita por un job y leída por otro de otro proyecto): "
             f"{len({c[0] for c in cross})} columnas")

# 6b. CONSTANT y TABLE
check(any(c["kind"] == "CONSTANT" for c in columns), "Falta un caso kind=CONSTANT")
check(any(c["kind"] == "TABLE" for c in columns), "Falta un caso kind=TABLE")
check(any(t["is_synthetic_source"] == "true" for t in transforms), "Falta is_synthetic_source=true")

# 6c. Fórmula multi-origen: misma (scenario, target, expression) en >=2 relaciones y expresión con CASE WHEN
groups = defaultdict(list)
for t in transforms:
    groups[(t["scenario"], t["target_fqn"], t["transformation_expression"])].append(t)
multi_case = [k for k, v in groups.items() if len(v) >= 2 and "CASE WHEN" in k[2]]
check(any(len(groups[k]) >= 3 for k in multi_case), "Falta un CASE WHEN con >=3 orígenes")
check(len(multi_case) >= 1, "Falta fórmula multi-origen con CASE WHEN")
notes.append(f"Fórmulas CASE WHEN multi-origen: {len(multi_case)} "
             f"(orígenes: {sorted(len(groups[k]) for k in multi_case)})")

# 6d. Zonas muertas: BFS inverso desde los FinalConsumer (columna -> consumer vía FEEDS)
feeding = {f["column_fqn"] for f in feeds}
live, q = set(feeding), deque(feeding)
while q:
    cur = q.popleft()
    for p in parents[cur]:
        if p not in live:
            live.add(p)
            q.append(p)
dead = col_fqns - live

EXPECTED_DEAD = {
    "RISK_MART.EXPOSURE.EXPOSURE_ADJ_LEGACY",                 # zona 3: rama de un dato vivo, job vivo
    "MKT_STG.PROMO.TARGET_SEGMENT", "MKT_STG.PROMO.PROMO_SCORE",  # zona 2: rama de un dato vivo, job activo
    "LEGACY_DM.BRANCH_MONTHLY.BRANCH_ID", "LEGACY_DM.BRANCH_MONTHLY.TOTAL_DEPOSITS",
    "LEGACY_DM.BRANCH_MONTHLY.TOTAL_LOANS",
    "LEGACY_RPT.BRANCH_SUMMARY.BRANCH_ID", "LEGACY_RPT.BRANCH_SUMMARY.NET_POSITION",  # zona 1: aislada
}
check(dead == EXPECTED_DEAD, f"Zonas muertas inesperadas.\n  sobran: {sorted(dead - EXPECTED_DEAD)}\n  faltan: {sorted(EXPECTED_DEAD - dead)}")

# Rama que se bifurca de un dato vivo (debe existir al menos una)
forks = [(p, c) for c in dead for p in parents[c] if p in live]
check(len(forks) >= 1, "Ninguna zona muerta se bifurca de un dato vivo")
notes.append("Puntos de bifurcación vivo -> muerto: " + ", ".join(f"{p} -> {c}" for p, c in sorted(forks)))

# Jobs muertos = ninguna de sus columnas de salida está viva
outs = defaultdict(set)
for t in transforms:
    outs[t["scenario"]].add(t["target_fqn"])
dead_jobs = {n for n in job_names if not (outs[n] & live)}
check(dead_jobs == {"PROMO_SEGMENT_EXTRACT", "LEGACY_BRANCH_REPORT"}, f"Jobs muertos inesperados: {sorted(dead_jobs)}")
cost = sum(int(j["estimated_compute_cost"]) for j in jobs if j["name"] in dead_jobs)
notes.append(f"Jobs muertos: {sorted(dead_jobs)} -> ahorro potencial {cost:,} EUR/año")
check(len({s["id"] for s in systems} - {h["source_system_id"] for h in hosts}) == 0, "Hay SourceSystem sin ninguna columna")

# Job sin propietario a propósito
no_owner = job_ids - {m["job_id"] for m in maintained}
check(no_owner == {"J13"}, f"Jobs sin propietario inesperados: {sorted(no_owner)}")
check(all(any(c["id"] == f["consumer_id"] for f in feeds) for c in consumers), "FinalConsumer sin ninguna columna que lo alimente")

# Ciclos en TRANSFORMS_TO (el linaje debe ser un DAG; BFS/trazados dependen de ello)
indeg = defaultdict(int)
for t in transforms:
    indeg[t["target_fqn"]] += 1
ready = deque(c for c in col_fqns if indeg[c] == 0)
seen = 0
while ready:
    n = ready.popleft()
    seen += 1
    for ch in children[n]:
        indeg[ch] -= 1
        if indeg[ch] == 0:
            ready.append(ch)
check(seen == len(col_fqns), "TRANSFORMS_TO contiene ciclos")

# Marcadores de cliente (restricción dura nº 1): lista vacía por diseño; añadir aquí nombres si se detectan
FORBIDDEN = []
for path in D.glob("*.csv"):
    text = path.read_text(encoding="utf-8").lower()
    for w in FORBIDDEN:
        check(w.lower() not in text, f"Referencia prohibida '{w}' en {path.name}")

print(f"Nodos:   {len(columns)} Column | {len(systems)} SourceSystem | {len(jobs)} EtlJob | "
      f"{len(consumers)} FinalConsumer | {len(owners)} Owner")
print(f"Aristas: {len(transforms)} TRANSFORMS_TO | {len(hosts)} HOSTS | {len(processes)} PROCESSES | "
      f"{len(feeds)} FEEDS | {len(maintained)} MAINTAINED_BY")
print(f"Columnas vivas: {len(live)} | muertas: {len(dead)}")
for n in notes:
    print(" -", n)
if errors:
    print(f"\nFALLOS ({len(errors)}):")
    for e in errors:
        print(" ✗", e)
    sys.exit(1)
print("\nOK: dataset consistente, sin referencias huérfanas.")
