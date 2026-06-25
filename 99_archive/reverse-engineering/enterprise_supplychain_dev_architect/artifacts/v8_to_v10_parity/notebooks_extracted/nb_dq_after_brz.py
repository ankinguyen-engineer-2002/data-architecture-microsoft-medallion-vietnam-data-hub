# ─── Cell 0 ───
# Fabric notebook source
# Notebook: nb_dq_after_brz
# Purpose: Run DQ checks for BRZ layer
# Called by: pl_master_daily (after pl_brz_daily)

# ─── Cell 1 ───
# Cell 1 — Execute DQ Engine with BRZ parameter

# ─── Cell 2 ───
notebookutils.notebook.run("nb_dq_engine", 900, {"DQ_LAYER": "BRZ"})

