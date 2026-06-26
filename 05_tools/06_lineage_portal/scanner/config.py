from __future__ import annotations

import os
from dataclasses import dataclass


DEFAULT_TENANT_ID = "5a9d9cfd-c32e-4ac1-a9ed-fe83df4f9e4d"
DEFAULT_WORKSPACE_ID = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"
DEFAULT_WORKSPACE_NAME = "Enterprise SupplyChain-Dev"
DEFAULT_SQL_SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
DEFAULT_SEMANTIC_MODEL_ID = "f06a2361-15fd-4f91-9d37-941fefe62aaf"
DEFAULT_SEMANTIC_MODEL_NAME = "sc_control_tower"

ETL_DATABASE = "ETL_Framework"
PROCESSING_DATABASE = "SupplyChain_Processing_Warehouse"
GOLD_DATABASE = "SupplyChain_Gold_Warehouse"
SOURCE_DATABASE = "Enterprise_Lakehouse"


@dataclass(frozen=True)
class ScannerConfig:
    tenant_id: str
    client_id: str
    client_secret: str
    workspace_id: str
    workspace_name: str
    sql_server: str
    semantic_model_id: str
    semantic_model_name: str

    @classmethod
    def from_env(cls) -> "ScannerConfig":
        required = {
            "FABRIC_CLIENT_ID": os.getenv("FABRIC_CLIENT_ID"),
            "FABRIC_CLIENT_SECRET": os.getenv("FABRIC_CLIENT_SECRET"),
        }
        missing = [name for name, value in required.items() if not value]
        if missing:
            raise RuntimeError(
                "Missing required environment variables: " + ", ".join(missing)
            )
        return cls(
            tenant_id=os.getenv("FABRIC_TENANT_ID") or DEFAULT_TENANT_ID,
            client_id=required["FABRIC_CLIENT_ID"] or "",
            client_secret=required["FABRIC_CLIENT_SECRET"] or "",
            workspace_id=os.getenv("FABRIC_WORKSPACE_ID") or DEFAULT_WORKSPACE_ID,
            workspace_name=os.getenv("FABRIC_WORKSPACE_NAME") or DEFAULT_WORKSPACE_NAME,
            sql_server=os.getenv("FABRIC_SQL_SERVER") or DEFAULT_SQL_SERVER,
            semantic_model_id=os.getenv("FABRIC_SEMANTIC_MODEL_ID") or DEFAULT_SEMANTIC_MODEL_ID,
            semantic_model_name=os.getenv("FABRIC_SEMANTIC_MODEL_NAME") or DEFAULT_SEMANTIC_MODEL_NAME,
        )
