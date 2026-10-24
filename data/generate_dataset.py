#!/usr/bin/env python3
"""
Generador del dataset sintético de la demo de data lineage (Financial Services).

Fuente única de verdad del contenido del dataset: define sistemas, jobs, columnas y
transformaciones en un solo sitio y escribe los CSV de esta carpeta. Los CSV son los
artefactos que se cargan con `00_load_live.cypher`; este script sólo existe para
mantenerlos coherentes entre sí (ids, hashes, HOSTS/PROCESSES derivados, etc.).

Uso:
    python3 generate_dataset.py          # reescribe los CSV
    python3 validate_dataset.py          # comprueba integridad referencial y criterios de aceptación

Todo el contenido es SINTÉTICO. No representa a ningún cliente real.

Columnas auxiliares `load_batch` (P1..P5): sólo las usa el script de carga para segmentar
la ingesta "en vivo" por proyecto. NO se persisten como propiedad en el grafo.
"""
import csv
import hashlib
from pathlib import Path

OUT = Path(__file__).parent

# --------------------------------------------------------------------------------------
# Datos de referencia (se cargan en el "segmento 0" del script de carga)
# --------------------------------------------------------------------------------------
SOURCE_SYSTEMS = [
    # id, name, technology, type, criticality
    ("SS01", "Core Banking PL/SQL", "PL/SQL", "Core banking", "High"),
    ("SS02", "Customer CRM", "PostgreSQL", "CRM", "Medium"),
    ("SS03", "SAS Risk Engine", "SAS", "Risk", "High"),
    ("SS04", "Cards Processing Platform", "DB2", "Cards", "High"),
    ("SS05", "Commercial BI", "Qlik", "BI", "Medium"),
    ("SS06", "Cloud Data Platform", "BigQuery", "Data platform", "High"),
    ("SS07", "Legacy Data Mart", "Teradata", "Data warehouse", "Low"),
]

OWNERS = [
    # id, name, role
    ("O01", "Core Data Engineering", "Technical Lead"),
    ("O02", "Credit Risk Data Office", "Data Owner"),
    ("O03", "Risk Analytics Engineering", "Technical Lead"),
    ("O04", "Regulatory Reporting Office", "Data Owner"),
    ("O05", "Retail Analytics", "Data Owner"),
    ("O06", "Marketing Data Team", "Technical Lead"),
    ("O07", "Data Platform Team", "Technical Lead"),
]

FINAL_CONSUMERS = [
    # id, name, type, regulation, periodicity
    ("FC01", "Solvency Report", "Regulatory", "COREP", "Quarterly"),
    ("FC02", "Large Exposures Report", "Regulatory", "COREP", "Quarterly"),
    ("FC03", "Balance Sheet Report", "Regulatory", "FINREP", "Quarterly"),
    ("FC04", "Risk Data Aggregation Dashboard", "Dashboard", "BCBS239", "Monthly"),
    ("FC05", "Expense Dashboard", "Dashboard", "N/A", "Monthly"),
    ("FC06", "Customer Churn Model", "AI Model", "N/A", "Weekly"),
]

# --------------------------------------------------------------------------------------
# Jobs ETL (EtlJob). batch = proyecto (segmento de carga en vivo).
# --------------------------------------------------------------------------------------
JOBS = [
    # id, name, frequency, owning_team, estimated_compute_cost (EUR/año), status, batch
    ("J01", "LOAD_CORE_ACCOUNTS", "Daily", "Core Data Engineering", 118000, "Active", "P1"),
    ("J02", "LOAD_CORE_LOANS", "Daily", "Core Data Engineering", 96000, "Active", "P1"),
    ("J03", "LOAD_CRM_CUSTOMERS", "Daily", "Core Data Engineering", 64000, "Active", "P1"),
    ("J04", "LOAD_RISK_RATINGS", "Daily", "Risk Analytics Engineering", 71000, "Active", "P2"),
    ("J05", "CALC_EXPOSURE", "Daily", "Risk Analytics Engineering", 185000, "Active", "P2"),
    ("J06", "CALC_RWA", "Daily", "Risk Analytics Engineering", 142000, "Active", "P2"),
    ("J07", "BUILD_COREP_SOLVENCY", "Weekly batch", "Regulatory Reporting Office", 58000, "Active", "P3"),
    ("J08", "BUILD_FINREP_BALANCE", "Weekly batch", "Regulatory Reporting Office", 47000, "Active", "P3"),
    ("J09", "LOAD_CARD_TRANSACTIONS", "Real-time", "Data Platform Team", 210000, "Active", "P4"),
    ("J10", "BUILD_EXPENSE_DASHBOARD", "Daily", "Retail Analytics", 52000, "Active", "P4"),
    ("J11", "BUILD_CHURN_FEATURES", "Weekly batch", "Retail Analytics", 89000, "Active", "P4"),
    ("J12", "PROMO_SEGMENT_EXTRACT", "Weekly batch", "Marketing Data Team", 42000, "Active", "P5"),
    ("J13", "LEGACY_BRANCH_REPORT", "Daily", "Legacy Applications Support", 85000, "Deprecated", "P5"),
]
JOB_BY_NAME = {j[1]: j for j in JOBS}

# MAINTAINED_BY: (job_name, owner_id). LEGACY_BRANCH_REPORT queda SIN propietario a propósito
# (job huérfano: argumento de accountability BCBS 239).
MAINTAINED_BY = [
    ("LOAD_CORE_ACCOUNTS", "O01"), ("LOAD_CORE_LOANS", "O01"), ("LOAD_CRM_CUSTOMERS", "O01"),
    ("LOAD_RISK_RATINGS", "O03"),
    ("CALC_EXPOSURE", "O03"), ("CALC_EXPOSURE", "O02"),
    ("CALC_RWA", "O03"), ("CALC_RWA", "O02"),
    ("BUILD_COREP_SOLVENCY", "O04"), ("BUILD_FINREP_BALANCE", "O04"),
    ("LOAD_CARD_TRANSACTIONS", "O07"),
    ("BUILD_EXPENSE_DASHBOARD", "O05"), ("BUILD_CHURN_FEATURES", "O05"),
    ("PROMO_SEGMENT_EXTRACT", "O06"),
]

# --------------------------------------------------------------------------------------
# Columnas. (fqn, kind, data_type, field_type, evidence, hosting system id)
# `name` se deriva del último segmento del fqn. `load_batch` se deriva del primer job
# (en orden de carga) que toca la columna.
# --------------------------------------------------------------------------------------
C = "COLUMN"
COLUMNS = [
    # ---- Fuentes crudas ----
    ("CORE.ACCOUNT.ACCOUNT_ID", C, "NUMBER(12)", "identifier", "Name ends in _ID and type is integer NUMBER", "SS01"),
    ("CORE.ACCOUNT.PRODUCT_CODE", C, "VARCHAR(6)", "category", "Short code with low cardinality (<50 distinct values)", "SS01"),
    ("CORE.ACCOUNT.BALANCE", C, "NUMBER(18,2)", "amount", "Name contains BALANCE and type is NUMBER with 2 decimals", "SS01"),
    ("CORE.ACCOUNT.CURRENCY", C, "VARCHAR(3)", "currency_code", "3-letter uppercase values matching ISO 4217", "SS01"),
    ("CORE.LOAN.LOAN_ID", C, "NUMBER(12)", "identifier", "Name ends in _ID and type is integer NUMBER", "SS01"),
    ("CORE.LOAN.CUSTOMER_ID", C, "NUMBER(10)", "identifier", "Name ends in _ID and type is integer NUMBER", "SS01"),
    ("CORE.LOAN.DRAWN_AMOUNT", C, "NUMBER(18,2)", "amount", "Name contains AMOUNT and type is NUMBER with 2 decimals", "SS01"),
    ("CORE.LOAN.UNDRAWN_AMOUNT", C, "NUMBER(18,2)", "amount", "Name contains AMOUNT and type is NUMBER with 2 decimals", "SS01"),
    ("CORE.LOAN.ASSET_CLASS", C, "VARCHAR(12)", "category", "Short code with low cardinality (<20 distinct values)", "SS01"),
    ("CRM.CUSTOMER.CUSTOMER_ID", C, "NUMBER(10)", "identifier", "Name ends in _ID and type is integer NUMBER", "SS02"),
    ("CRM.CUSTOMER.SEGMENT_CODE", C, "VARCHAR(4)", "category", "Short code with low cardinality (<10 distinct values)", "SS02"),
    ("CRM.CUSTOMER.ONBOARDING_DATE", C, "DATE", "date", "Native DATE type; name contains DATE", "SS02"),
    ("SAS_RISK.RATING.INTERNAL_RATING", C, "NUMBER(2)", "rating", "Integer in range 1-10 with ordinal semantics", "SS03"),
    ("SAS_RISK.RATING.PD", C, "NUMBER(9,8)", "probability", "Values strictly within [0,1]; name is a known acronym (probability of default)", "SS03"),
    ("SAS_RISK.RISK_WEIGHT.RISK_WEIGHT", C, "NUMBER(5,2)", "rate", "Name contains WEIGHT; values between 0 and 1.5", "SS03"),
    ("CARDS.CARD_TX.CUSTOMER_ID", C, "NUMBER(10)", "identifier", "Name ends in _ID and type is integer NUMBER", "SS04"),
    ("CARDS.CARD_TX.AMOUNT", C, "NUMBER(12,2)", "amount", "Name is AMOUNT and type is NUMBER with 2 decimals", "SS04"),
    ("CARDS.CARD_TX.MCC", C, "VARCHAR(4)", "category", "4-digit merchant category code", "SS04"),
    ("CARDS.CARD_TX.CHANNEL", C, "VARCHAR(10)", "category", "Low cardinality text (POS, ONLINE, ATM)", "SS04"),
    ("CARDS.CARD_TX.TX_DATE", C, "DATE", "date", "Native DATE type; name contains DATE", "SS04"),
    ("LEGACY_DM.BRANCH_MONTHLY.BRANCH_ID", C, "NUMBER(6)", "identifier", "Name ends in _ID and type is integer NUMBER", "SS07"),
    ("LEGACY_DM.BRANCH_MONTHLY.TOTAL_DEPOSITS", C, "NUMBER(18,2)", "amount", "Name starts with TOTAL_ and type is NUMBER with 2 decimals", "SS07"),
    ("LEGACY_DM.BRANCH_MONTHLY.TOTAL_LOANS", C, "NUMBER(18,2)", "amount", "Name starts with TOTAL_ and type is NUMBER with 2 decimals", "SS07"),
    # ---- Constante y referencias a tabla completa ----
    ("CONST.LITERAL.EUR", "CONSTANT", "VARCHAR(3)", "constant", "Fixed literal 'EUR' with no source column", "SS06"),
    ("STG.STG_ACCOUNT.*", "TABLE", "TABLE", "counter", "Whole-table reference used by COUNT(*)", "SS06"),
    ("STG.STG_CARD_TX.*", "TABLE", "TABLE", "counter", "Whole-table reference used by COUNT(*)", "SS06"),
    ("RISK_MART.RWA.*", "TABLE", "TABLE", "counter", "Whole-table reference used by COUNT(*)", "SS06"),
    # ---- Staging (Cloud Data Platform) ----
    ("STG.STG_ACCOUNT.ACCOUNT_ID", C, "NUMBER(12)", "identifier", "Pass-through of an identifier column", "SS06"),
    ("STG.STG_ACCOUNT.PRODUCT_CODE", C, "VARCHAR(6)", "category", "Normalised copy of a low-cardinality code", "SS06"),
    ("STG.STG_ACCOUNT.BALANCE", C, "NUMBER(18,2)", "amount", "Pass-through of a monetary amount", "SS06"),
    ("STG.STG_ACCOUNT.CURRENCY", C, "VARCHAR(3)", "currency_code", "Normalised 3-letter currency code", "SS06"),
    ("STG.STG_LOAN.LOAN_ID", C, "NUMBER(12)", "identifier", "Pass-through of an identifier column", "SS06"),
    ("STG.STG_LOAN.CUSTOMER_ID", C, "NUMBER(10)", "identifier", "Pass-through of an identifier column", "SS06"),
    ("STG.STG_LOAN.DRAWN_AMOUNT", C, "NUMBER(18,2)", "amount", "Pass-through of a monetary amount", "SS06"),
    ("STG.STG_LOAN.UNDRAWN_AMOUNT", C, "NUMBER(18,2)", "amount", "Pass-through of a monetary amount", "SS06"),
    ("STG.STG_LOAN.ASSET_CLASS", C, "VARCHAR(12)", "category", "Pass-through of a low-cardinality code", "SS06"),
    ("STG.STG_CUSTOMER.CUSTOMER_ID", C, "NUMBER(10)", "identifier", "Pass-through of an identifier column", "SS06"),
    ("STG.STG_CUSTOMER.SEGMENT_CODE", C, "VARCHAR(4)", "category", "Pass-through of a low-cardinality code", "SS06"),
    ("STG.STG_CUSTOMER.ONBOARDING_DATE", C, "DATE", "date", "Pass-through of a DATE column", "SS06"),
    ("STG.STG_RATING.INTERNAL_RATING", C, "NUMBER(2)", "rating", "Pass-through of an ordinal rating", "SS06"),
    ("STG.STG_RATING.PD", C, "NUMBER(9,8)", "probability", "Pass-through of a probability in [0,1]", "SS06"),
    ("STG.STG_RISK_WEIGHT.RISK_WEIGHT", C, "NUMBER(5,2)", "rate", "Pass-through of a regulatory weight", "SS06"),
    ("STG.STG_CARD_TX.CUSTOMER_ID", C, "NUMBER(10)", "identifier", "Pass-through of an identifier column", "SS06"),
    ("STG.STG_CARD_TX.AMOUNT", C, "NUMBER(12,2)", "amount", "Pass-through of a monetary amount", "SS06"),
    ("STG.STG_CARD_TX.MCC", C, "VARCHAR(4)", "category", "Pass-through of a merchant category code", "SS06"),
    ("STG.STG_CARD_TX.CHANNEL", C, "VARCHAR(10)", "category", "Pass-through of a low-cardinality text", "SS06"),
    ("STG.STG_CARD_TX.TX_DATE", C, "DATE", "date", "Pass-through of a DATE column", "SS06"),
    # ---- Credit risk mart ----
    ("RISK_MART.EXPOSURE.LOAN_ID", C, "NUMBER(12)", "identifier", "Pass-through of an identifier column", "SS06"),
    ("RISK_MART.EXPOSURE.CUSTOMER_ID", C, "NUMBER(10)", "identifier", "Pass-through of an identifier column", "SS06"),
    ("RISK_MART.EXPOSURE.ASSET_CLASS", C, "VARCHAR(12)", "category", "Pass-through of a low-cardinality code", "SS06"),
    ("RISK_MART.EXPOSURE.EAD", C, "NUMBER(18,2)", "amount", "Computed monetary amount (exposure at default)", "SS06"),
    ("RISK_MART.EXPOSURE.RATING_BUCKET", C, "VARCHAR(6)", "category", "CASE WHEN output with 3 fixed labels (LOW/MEDIUM/HIGH)", "SS06"),
    ("RISK_MART.EXPOSURE.EXPOSURE_ADJ_LEGACY", C, "NUMBER(18,2)", "amount", "Computed monetary amount; legacy adjustment factor", "SS06"),
    ("RISK_MART.RWA.LOAN_ID", C, "NUMBER(12)", "identifier", "Pass-through of an identifier column", "SS06"),
    ("RISK_MART.RWA.ASSET_CLASS", C, "VARCHAR(12)", "category", "Pass-through of a low-cardinality code", "SS06"),
    ("RISK_MART.RWA.RATING_BUCKET", C, "VARCHAR(6)", "category", "Pass-through of a 3-label bucket", "SS06"),
    ("RISK_MART.RWA.RWA_AMOUNT", C, "NUMBER(18,2)", "amount", "Product of an amount and a weight (risk-weighted assets)", "SS06"),
    # ---- Regulatory mart ----
    ("REG_MART.SOLVENCY.REPORTING_CURRENCY", C, "VARCHAR(3)", "constant", "Single distinct value 'EUR' propagated from a literal", "SS06"),
    ("REG_MART.SOLVENCY.TOTAL_RWA", C, "NUMBER(20,2)", "amount", "SUM aggregation of a monetary amount", "SS06"),
    ("REG_MART.SOLVENCY.TOTAL_EAD", C, "NUMBER(20,2)", "amount", "SUM aggregation of a monetary amount", "SS06"),
    ("REG_MART.SOLVENCY.RWA_HIGH_BUCKET_SHARE", C, "NUMBER(9,8)", "ratio", "Ratio of two SUM aggregations; values within [0,1]", "SS06"),
    ("REG_MART.SOLVENCY.LOAN_COUNT", C, "NUMBER(12)", "counter", "COUNT(*) over a whole table", "SS06"),
    ("REG_MART.BALANCE_SHEET.REPORTING_CURRENCY", C, "VARCHAR(3)", "constant", "Single distinct value 'EUR' propagated from a literal", "SS06"),
    ("REG_MART.BALANCE_SHEET.PRODUCT_CODE", C, "VARCHAR(6)", "category", "Grouping key copied from a low-cardinality code", "SS06"),
    ("REG_MART.BALANCE_SHEET.TOTAL_BALANCE_EUR", C, "NUMBER(20,2)", "amount", "SUM aggregation of a monetary amount", "SS06"),
    ("REG_MART.BALANCE_SHEET.ACCOUNT_COUNT", C, "NUMBER(12)", "counter", "COUNT(*) over a whole table", "SS06"),
    # ---- Retail analytics ----
    ("BI_MART.EXPENSE.CUSTOMER_ID", C, "NUMBER(10)", "identifier", "Pass-through of an identifier column", "SS05"),
    ("BI_MART.EXPENSE.CUSTOMER_SEGMENT", C, "VARCHAR(4)", "category", "Pass-through of a low-cardinality code", "SS05"),
    ("BI_MART.EXPENSE.SPEND_CATEGORY", C, "VARCHAR(12)", "category", "CASE WHEN output with fixed labels", "SS05"),
    ("BI_MART.EXPENSE.MONTHLY_SPEND", C, "NUMBER(14,2)", "amount", "SUM aggregation of a monetary amount grouped by month", "SS05"),
    ("BI_MART.EXPENSE.TX_COUNT", C, "NUMBER(12)", "counter", "COUNT(*) over a whole table", "SS05"),
    ("ML_FEAT.CHURN.CUSTOMER_ID", C, "NUMBER(10)", "identifier", "Pass-through of an identifier column", "SS06"),
    ("ML_FEAT.CHURN.TENURE_MONTHS", C, "NUMBER(4)", "duration", "DATEDIFF in months from a DATE column", "SS06"),
    ("ML_FEAT.CHURN.AVG_BALANCE", C, "NUMBER(18,2)", "amount", "AVG aggregation of a monetary amount", "SS06"),
    ("ML_FEAT.CHURN.NUM_ACCOUNTS", C, "NUMBER(3)", "counter", "COUNT(DISTINCT id) aggregation", "SS06"),
    ("ML_FEAT.CHURN.CARD_ACTIVITY_FLAG", C, "NUMBER(1)", "flag", "CASE WHEN output with values 0/1", "SS06"),
    ("ML_FEAT.CHURN.CHURN_RISK_FLAG", C, "NUMBER(1)", "flag", "CASE WHEN output with values 0/1", "SS06"),
    # ---- Zonas muertas (marketing y legacy) ----
    ("MKT_STG.PROMO.TARGET_SEGMENT", C, "VARCHAR(4)", "category", "Pass-through of a low-cardinality code", "SS06"),
    ("MKT_STG.PROMO.PROMO_SCORE", C, "NUMBER(5,4)", "score", "CASE WHEN output with numeric labels in [0,1]", "SS06"),
    ("LEGACY_RPT.BRANCH_SUMMARY.BRANCH_ID", C, "NUMBER(6)", "identifier", "Pass-through of an identifier column", "SS07"),
    ("LEGACY_RPT.BRANCH_SUMMARY.NET_POSITION", C, "NUMBER(18,2)", "amount", "Difference of two monetary amounts", "SS07"),
]
COL_BY_FQN = {c[0]: c for c in COLUMNS}

# --------------------------------------------------------------------------------------
# Transformaciones: una entrada por (job, target, expresión) con TODAS sus fuentes.
# Se expande a N relaciones TRANSFORMS_TO (una por fuente) con la misma expresión.
# (job_name, target_fqn, [source_fqns], expression, filters)
# --------------------------------------------------------------------------------------
ACC_FILTER = ["STATUS <> 'CLOSED'"]
LOAN_FILTER = ["LOAN_STATUS IN ('PERFORMING','DEFAULTED')"]
RATING_FILTER = ["RATING_DATE = MAX(RATING_DATE)"]

TRANSFORMS = [
    # ---- P1: ingesta core / CRM -> staging ----
    ("LOAD_CORE_ACCOUNTS", "STG.STG_ACCOUNT.ACCOUNT_ID", ["CORE.ACCOUNT.ACCOUNT_ID"], "ACCOUNT_ID", ACC_FILTER),
    ("LOAD_CORE_ACCOUNTS", "STG.STG_ACCOUNT.PRODUCT_CODE", ["CORE.ACCOUNT.PRODUCT_CODE"], "UPPER(TRIM(PRODUCT_CODE))", ACC_FILTER),
    ("LOAD_CORE_ACCOUNTS", "STG.STG_ACCOUNT.BALANCE", ["CORE.ACCOUNT.BALANCE"], "BALANCE", ACC_FILTER),
    ("LOAD_CORE_ACCOUNTS", "STG.STG_ACCOUNT.CURRENCY", ["CORE.ACCOUNT.CURRENCY"], "UPPER(CURRENCY)", ACC_FILTER),
    ("LOAD_CORE_LOANS", "STG.STG_LOAN.LOAN_ID", ["CORE.LOAN.LOAN_ID"], "LOAN_ID", LOAN_FILTER),
    ("LOAD_CORE_LOANS", "STG.STG_LOAN.CUSTOMER_ID", ["CORE.LOAN.CUSTOMER_ID"], "CUSTOMER_ID", LOAN_FILTER),
    ("LOAD_CORE_LOANS", "STG.STG_LOAN.DRAWN_AMOUNT", ["CORE.LOAN.DRAWN_AMOUNT"], "DRAWN_AMOUNT", LOAN_FILTER),
    ("LOAD_CORE_LOANS", "STG.STG_LOAN.UNDRAWN_AMOUNT", ["CORE.LOAN.UNDRAWN_AMOUNT"], "UNDRAWN_AMOUNT", LOAN_FILTER),
    ("LOAD_CORE_LOANS", "STG.STG_LOAN.ASSET_CLASS", ["CORE.LOAN.ASSET_CLASS"], "UPPER(ASSET_CLASS)", LOAN_FILTER),
    ("LOAD_CRM_CUSTOMERS", "STG.STG_CUSTOMER.CUSTOMER_ID", ["CRM.CUSTOMER.CUSTOMER_ID"], "CUSTOMER_ID", []),
    ("LOAD_CRM_CUSTOMERS", "STG.STG_CUSTOMER.SEGMENT_CODE", ["CRM.CUSTOMER.SEGMENT_CODE"], "UPPER(SEGMENT_CODE)", []),
    ("LOAD_CRM_CUSTOMERS", "STG.STG_CUSTOMER.ONBOARDING_DATE", ["CRM.CUSTOMER.ONBOARDING_DATE"], "ONBOARDING_DATE", []),
    # ---- P2: riesgo de crédito ----
    ("LOAD_RISK_RATINGS", "STG.STG_RATING.INTERNAL_RATING", ["SAS_RISK.RATING.INTERNAL_RATING"], "INTERNAL_RATING", RATING_FILTER),
    ("LOAD_RISK_RATINGS", "STG.STG_RATING.PD", ["SAS_RISK.RATING.PD"], "PD", RATING_FILTER),
    ("LOAD_RISK_RATINGS", "STG.STG_RISK_WEIGHT.RISK_WEIGHT", ["SAS_RISK.RISK_WEIGHT.RISK_WEIGHT"], "RISK_WEIGHT", []),
    ("CALC_EXPOSURE", "RISK_MART.EXPOSURE.LOAN_ID", ["STG.STG_LOAN.LOAN_ID"], "LOAN_ID", []),
    ("CALC_EXPOSURE", "RISK_MART.EXPOSURE.CUSTOMER_ID", ["STG.STG_LOAN.CUSTOMER_ID"], "CUSTOMER_ID", []),
    ("CALC_EXPOSURE", "RISK_MART.EXPOSURE.ASSET_CLASS", ["STG.STG_LOAN.ASSET_CLASS"], "ASSET_CLASS", []),
    ("CALC_EXPOSURE", "RISK_MART.EXPOSURE.EAD",
     ["STG.STG_LOAN.DRAWN_AMOUNT", "STG.STG_LOAN.UNDRAWN_AMOUNT"],
     "DRAWN_AMOUNT + 0.5 * UNDRAWN_AMOUNT", []),
    # Fórmula multi-origen (CASE WHEN con 3 columnas de entrada de DOS tablas distintas)
    ("CALC_EXPOSURE", "RISK_MART.EXPOSURE.RATING_BUCKET",
     ["STG.STG_RATING.PD", "STG.STG_RATING.INTERNAL_RATING", "STG.STG_LOAN.ASSET_CLASS"],
     "CASE WHEN PD < 0.01 AND INTERNAL_RATING <= 3 THEN 'LOW' "
     "WHEN ASSET_CLASS = 'RETAIL' AND INTERNAL_RATING <= 6 THEN 'MEDIUM' ELSE 'HIGH' END", []),
    # ZONA MUERTA 3: rama que se bifurca de un dato vivo (DRAWN_AMOUNT) dentro de un job vivo
    ("CALC_EXPOSURE", "RISK_MART.EXPOSURE.EXPOSURE_ADJ_LEGACY", ["STG.STG_LOAN.DRAWN_AMOUNT"], "DRAWN_AMOUNT * 1.05", []),
    ("CALC_RWA", "RISK_MART.RWA.LOAN_ID", ["RISK_MART.EXPOSURE.LOAN_ID"], "LOAN_ID", []),
    ("CALC_RWA", "RISK_MART.RWA.ASSET_CLASS", ["RISK_MART.EXPOSURE.ASSET_CLASS"], "ASSET_CLASS", []),
    ("CALC_RWA", "RISK_MART.RWA.RATING_BUCKET", ["RISK_MART.EXPOSURE.RATING_BUCKET"], "RATING_BUCKET", []),
    ("CALC_RWA", "RISK_MART.RWA.RWA_AMOUNT",
     ["RISK_MART.EXPOSURE.EAD", "STG.STG_RISK_WEIGHT.RISK_WEIGHT"], "EAD * RISK_WEIGHT", []),
    # ---- P3: reporting regulatorio (consume salidas de P2: auto-conexión entre proyectos) ----
    ("BUILD_COREP_SOLVENCY", "REG_MART.SOLVENCY.REPORTING_CURRENCY", ["CONST.LITERAL.EUR"], "'EUR'", []),
    ("BUILD_COREP_SOLVENCY", "REG_MART.SOLVENCY.TOTAL_RWA", ["RISK_MART.RWA.RWA_AMOUNT"], "SUM(RWA_AMOUNT)", []),
    ("BUILD_COREP_SOLVENCY", "REG_MART.SOLVENCY.TOTAL_EAD", ["RISK_MART.EXPOSURE.EAD"], "SUM(EAD)", []),
    ("BUILD_COREP_SOLVENCY", "REG_MART.SOLVENCY.RWA_HIGH_BUCKET_SHARE",
     ["RISK_MART.RWA.RATING_BUCKET", "RISK_MART.RWA.RWA_AMOUNT"],
     "SUM(CASE WHEN RATING_BUCKET = 'HIGH' THEN RWA_AMOUNT ELSE 0 END) / SUM(RWA_AMOUNT)", []),
    ("BUILD_COREP_SOLVENCY", "REG_MART.SOLVENCY.LOAN_COUNT", ["RISK_MART.RWA.*"], "COUNT(*)", []),
    ("BUILD_FINREP_BALANCE", "REG_MART.BALANCE_SHEET.REPORTING_CURRENCY", ["CONST.LITERAL.EUR"], "'EUR'", []),
    ("BUILD_FINREP_BALANCE", "REG_MART.BALANCE_SHEET.PRODUCT_CODE", ["STG.STG_ACCOUNT.PRODUCT_CODE"], "PRODUCT_CODE", []),
    ("BUILD_FINREP_BALANCE", "REG_MART.BALANCE_SHEET.TOTAL_BALANCE_EUR",
     ["STG.STG_ACCOUNT.BALANCE", "STG.STG_ACCOUNT.CURRENCY"],
     "SUM(CASE WHEN CURRENCY = 'EUR' THEN BALANCE ELSE 0 END)", []),
    ("BUILD_FINREP_BALANCE", "REG_MART.BALANCE_SHEET.ACCOUNT_COUNT", ["STG.STG_ACCOUNT.*"], "COUNT(*)", []),
    # ---- P4: analítica retail ----
    ("LOAD_CARD_TRANSACTIONS", "STG.STG_CARD_TX.CUSTOMER_ID", ["CARDS.CARD_TX.CUSTOMER_ID"], "CUSTOMER_ID", []),
    ("LOAD_CARD_TRANSACTIONS", "STG.STG_CARD_TX.AMOUNT", ["CARDS.CARD_TX.AMOUNT"], "AMOUNT", []),
    ("LOAD_CARD_TRANSACTIONS", "STG.STG_CARD_TX.MCC", ["CARDS.CARD_TX.MCC"], "MCC", []),
    ("LOAD_CARD_TRANSACTIONS", "STG.STG_CARD_TX.CHANNEL", ["CARDS.CARD_TX.CHANNEL"], "UPPER(CHANNEL)", []),
    ("LOAD_CARD_TRANSACTIONS", "STG.STG_CARD_TX.TX_DATE", ["CARDS.CARD_TX.TX_DATE"], "TX_DATE", []),
    ("BUILD_EXPENSE_DASHBOARD", "BI_MART.EXPENSE.CUSTOMER_ID", ["STG.STG_CARD_TX.CUSTOMER_ID"], "CUSTOMER_ID", []),
    ("BUILD_EXPENSE_DASHBOARD", "BI_MART.EXPENSE.CUSTOMER_SEGMENT", ["STG.STG_CUSTOMER.SEGMENT_CODE"], "SEGMENT_CODE", []),
    ("BUILD_EXPENSE_DASHBOARD", "BI_MART.EXPENSE.SPEND_CATEGORY",
     ["STG.STG_CARD_TX.MCC", "STG.STG_CARD_TX.CHANNEL"],
     "CASE WHEN MCC IN ('5411','5499') THEN 'GROCERY' WHEN CHANNEL = 'ONLINE' THEN 'E-COMMERCE' ELSE 'OTHER' END", []),
    ("BUILD_EXPENSE_DASHBOARD", "BI_MART.EXPENSE.MONTHLY_SPEND",
     ["STG.STG_CARD_TX.AMOUNT", "STG.STG_CARD_TX.TX_DATE"],
     "SUM(AMOUNT) GROUP BY TRUNC(TX_DATE, 'MM')", []),
    ("BUILD_EXPENSE_DASHBOARD", "BI_MART.EXPENSE.TX_COUNT", ["STG.STG_CARD_TX.*"], "COUNT(*)", []),
    ("BUILD_CHURN_FEATURES", "ML_FEAT.CHURN.CUSTOMER_ID", ["STG.STG_CUSTOMER.CUSTOMER_ID"], "CUSTOMER_ID", []),
    ("BUILD_CHURN_FEATURES", "ML_FEAT.CHURN.TENURE_MONTHS", ["STG.STG_CUSTOMER.ONBOARDING_DATE"],
     "DATEDIFF(MONTH, ONBOARDING_DATE, CURRENT_DATE)", []),
    ("BUILD_CHURN_FEATURES", "ML_FEAT.CHURN.AVG_BALANCE", ["STG.STG_ACCOUNT.BALANCE"], "AVG(BALANCE)", []),
    ("BUILD_CHURN_FEATURES", "ML_FEAT.CHURN.NUM_ACCOUNTS", ["STG.STG_ACCOUNT.ACCOUNT_ID"], "COUNT(DISTINCT ACCOUNT_ID)", []),
    ("BUILD_CHURN_FEATURES", "ML_FEAT.CHURN.CARD_ACTIVITY_FLAG",
     ["STG.STG_CARD_TX.AMOUNT", "STG.STG_CARD_TX.TX_DATE"],
     "CASE WHEN SUM(CASE WHEN TX_DATE >= CURRENT_DATE - 90 THEN AMOUNT ELSE 0 END) > 0 THEN 1 ELSE 0 END", []),
    ("BUILD_CHURN_FEATURES", "ML_FEAT.CHURN.CHURN_RISK_FLAG",
     ["ML_FEAT.CHURN.TENURE_MONTHS", "ML_FEAT.CHURN.AVG_BALANCE", "ML_FEAT.CHURN.CARD_ACTIVITY_FLAG"],
     "CASE WHEN TENURE_MONTHS < 12 AND AVG_BALANCE < 500 AND CARD_ACTIVITY_FLAG = 0 THEN 1 ELSE 0 END", []),
    # ---- P5: zonas muertas ----
    # ZONA MUERTA 2: job ACTIVO cuya salida no la consume nadie (rama de un dato vivo: SEGMENT_CODE)
    ("PROMO_SEGMENT_EXTRACT", "MKT_STG.PROMO.TARGET_SEGMENT", ["STG.STG_CUSTOMER.SEGMENT_CODE"], "SEGMENT_CODE",
     ["ONBOARDING_DATE > ADD_MONTHS(CURRENT_DATE, -24)"]),
    ("PROMO_SEGMENT_EXTRACT", "MKT_STG.PROMO.PROMO_SCORE", ["MKT_STG.PROMO.TARGET_SEGMENT"],
     "CASE WHEN TARGET_SEGMENT = 'MASS' THEN 0.2 WHEN TARGET_SEGMENT = 'PREM' THEN 0.6 ELSE 0.4 END", []),
    # ZONA MUERTA 1: componente totalmente aislado (job deprecado, sin propietario)
    ("LEGACY_BRANCH_REPORT", "LEGACY_RPT.BRANCH_SUMMARY.BRANCH_ID", ["LEGACY_DM.BRANCH_MONTHLY.BRANCH_ID"], "BRANCH_ID", []),
    ("LEGACY_BRANCH_REPORT", "LEGACY_RPT.BRANCH_SUMMARY.NET_POSITION",
     ["LEGACY_DM.BRANCH_MONTHLY.TOTAL_DEPOSITS", "LEGACY_DM.BRANCH_MONTHLY.TOTAL_LOANS"],
     "TOTAL_DEPOSITS - TOTAL_LOANS", []),
]

# FEEDS: (column_fqn, consumer_id)
FEEDS = (
    [(f"REG_MART.SOLVENCY.{c}", "FC01") for c in
     ("REPORTING_CURRENCY", "TOTAL_RWA", "TOTAL_EAD", "RWA_HIGH_BUCKET_SHARE", "LOAN_COUNT")]
    + [(f"RISK_MART.EXPOSURE.{c}", "FC02") for c in ("LOAN_ID", "CUSTOMER_ID", "ASSET_CLASS", "EAD")]
    + [(f"REG_MART.BALANCE_SHEET.{c}", "FC03") for c in
       ("REPORTING_CURRENCY", "PRODUCT_CODE", "TOTAL_BALANCE_EUR", "ACCOUNT_COUNT")]
    + [(f"RISK_MART.RWA.{c}", "FC04") for c in ("LOAN_ID", "ASSET_CLASS", "RATING_BUCKET", "RWA_AMOUNT")]
    + [(f"BI_MART.EXPENSE.{c}", "FC05") for c in
       ("CUSTOMER_ID", "CUSTOMER_SEGMENT", "SPEND_CATEGORY", "MONTHLY_SPEND", "TX_COUNT")]
    + [(f"ML_FEAT.CHURN.{c}", "FC06") for c in ("CUSTOMER_ID", "NUM_ACCOUNTS", "CHURN_RISK_FLAG")]
)


# --------------------------------------------------------------------------------------
# Derivación y escritura
# --------------------------------------------------------------------------------------
def write(name, header, rows):
    with open(OUT / name, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)
    print(f"  {name}: {len(rows)} filas")


def transform_id(scenario, src, tgt, expr):
    """Hash propio de deduplicación (no es el id interno de Neo4j)."""
    return hashlib.sha1(f"{scenario}|{src}|{tgt}|{expr}".encode()).hexdigest()[:12]


def main():
    job_order = {j[1]: i for i, j in enumerate(JOBS)}

    # Relaciones TRANSFORMS_TO expandidas + columnas tocadas por cada job
    transforms_rows, touched = [], {j[1]: [] for j in JOBS}
    for job, tgt, srcs, expr, filters in sorted(TRANSFORMS, key=lambda t: job_order[t[0]]):
        for src in srcs:
            is_synth = "true" if COL_BY_FQN[src][1] == "CONSTANT" else "false"
            transforms_rows.append([
                transform_id(job, src, tgt, expr), src, tgt, job, expr,
                "|".join(filters), is_synth, JOB_BY_NAME[job][6],
            ])
            for fqn in (src, tgt):
                if fqn not in touched[job]:
                    touched[job].append(fqn)

    # load_batch de cada columna = batch del primer job (en orden de carga) que la toca
    col_batch = {}
    for job in sorted(touched, key=lambda n: job_order[n]):
        for fqn in touched[job]:
            col_batch.setdefault(fqn, JOB_BY_NAME[job][6])
    missing = [c[0] for c in COLUMNS if c[0] not in col_batch]
    assert not missing, f"Columnas definidas pero no usadas por ningún job: {missing}"

    print("Escribiendo CSV en", OUT)
    write("source_systems.csv", ["id", "name", "technology", "type", "criticality"], SOURCE_SYSTEMS)
    write("owners.csv", ["id", "name", "role"], OWNERS)
    write("final_consumers.csv", ["id", "name", "type", "regulation", "periodicity"], FINAL_CONSUMERS)
    write("etl_jobs.csv",
          ["id", "name", "frequency", "owning_team", "estimated_compute_cost", "status", "load_batch"],
          [list(j) for j in JOBS])
    write("columns.csv",
          ["fqn", "name", "kind", "data_type", "field_type", "field_type_evidence", "load_batch"],
          [[c[0], c[0].split(".")[-1], c[1], c[2], c[3], c[4], col_batch[c[0]]] for c in COLUMNS])
    write("transforms_to.csv",
          ["id", "source_fqn", "target_fqn", "scenario", "transformation_expression",
           "filters", "is_synthetic_source", "load_batch"], transforms_rows)
    write("hosts.csv", ["source_system_id", "column_fqn", "load_batch"],
          [[c[5], c[0], col_batch[c[0]]] for c in COLUMNS])
    write("processes.csv", ["job_id", "column_fqn", "load_batch"],
          [[JOB_BY_NAME[job][0], fqn, JOB_BY_NAME[job][6]]
           for job in sorted(touched, key=lambda n: job_order[n]) for fqn in touched[job]])
    write("feeds.csv", ["column_fqn", "consumer_id", "load_batch"],
          [[fqn, fc, col_batch[fqn]] for fqn, fc in FEEDS])
    write("maintained_by.csv", ["job_id", "owner_id", "load_batch"],
          [[JOB_BY_NAME[job][0], owner, JOB_BY_NAME[job][6]] for job, owner in MAINTAINED_BY])


if __name__ == "__main__":
    main()
