#!/usr/bin/env bash
set -euo pipefail

dotnet build ETL_Framework/ETL_Framework.sqlproj -c Release
dotnet build Enterprise_Lakehouse_Reference/Enterprise_Lakehouse_Reference.sqlproj -c Release
dotnet build SupplyChain_Processing_Warehouse/SupplyChain_Processing_Warehouse.sqlproj -c Release
dotnet build SupplyChain_Gold_Warehouse/SupplyChain_Gold_Warehouse.sqlproj -c Release
