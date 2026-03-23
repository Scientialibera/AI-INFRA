#!/usr/bin/env python3
"""
Generate architecture/network diagrams from config.toml.

Outputs:
- Mermaid diagram (.mmd)
- Markdown summary (.md)
"""

from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import sys
from typing import Any

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore


PE_ZONE_MAP = {
    "openai": ["privatelink.openai.azure.com"],
    "cosmosdb": ["privatelink.documents.azure.com"],
    "datalake": ["privatelink.blob.core.windows.net", "privatelink.dfs.core.windows.net"],
    "sqldb": ["privatelink.database.windows.net"],
    "aisearch": ["privatelink.search.windows.net"],
    "containerRegistry": ["privatelink.azurecr.io"],
    "keyVault": ["privatelink.vaultcore.azure.net"],
    "redis": ["privatelink.redis.cache.windows.net"],
}

SERVICE_LABELS = {
    "openai": "Azure OpenAI",
    "cosmosdb": "Cosmos DB",
    "datalake": "Data Lake",
    "sqldb": "SQL DB",
    "aisearch": "AI Search",
    "containerApps": "Container Apps",
    "containerRegistry": "Container Registry",
    "keyVault": "Key Vault",
    "monitoring": "Monitoring",
    "apim": "API Management",
    "frontDoor": "Front Door",
    "redis": "Redis",
}


def as_bool(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)


def load_config(path: pathlib.Path) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"Config file not found: {path}")
    with path.open("rb") as f:
        return tomllib.load(f)


def get_enabled_services(config: dict[str, Any]) -> dict[str, dict[str, Any]]:
    services = config.get("services", {})
    enabled: dict[str, dict[str, Any]] = {}
    for key, value in services.items():
        if not isinstance(value, dict):
            continue
        if as_bool(value.get("enabled"), False):
            enabled[key] = value
    return enabled


def pe_enabled_for(service_name: str, service_cfg: dict[str, Any], networking_enabled: bool) -> bool:
    if not networking_enabled:
        return False
    if service_name not in PE_ZONE_MAP:
        return False
    return as_bool(service_cfg.get("privateEndpointEnabled"), True)


def generate_mermaid(config: dict[str, Any]) -> str:
    project = config.get("project", {})
    name = str(project.get("name", "project"))
    prefixes = project.get("prefixes", [])
    if isinstance(prefixes, str):
        prefixes = [prefixes]
    if not prefixes:
        env = project.get("environment", "dev")
        prefixes = [env]

    networking = config.get("networking", {})
    networking_enabled = as_bool(networking.get("enabled"), True)
    enabled_services = get_enabled_services(config)

    # Determine subnet needs following current IaC rules.
    needs_containerapps_subnet = "containerApps" in enabled_services
    needs_sql_subnet = "sqldb" in enabled_services
    needs_apim_subnet = "apim" in enabled_services

    pe_services = [
        svc for svc, svc_cfg in enabled_services.items() if pe_enabled_for(svc, svc_cfg, networking_enabled)
    ]
    needs_pe_subnet = len(pe_services) > 0

    lines: list[str] = []
    lines.append("flowchart LR")
    lines.append(f'  title["{name} Architecture ({", ".join(prefixes)})"]')
    lines.append('  rg["Resource Group(s)"]')

    if networking_enabled:
        lines.append('  subgraph net["Virtual Network"]')
        lines.append('    vnet["VNet"]')
        if needs_pe_subnet:
            lines.append('    pe_subnet["snet-privateendpoints"]')
            lines.append('    pe_nsg["privateendpoint-nsg"]')
            lines.append("    vnet --> pe_subnet")
            lines.append("    pe_subnet --> pe_nsg")
        if needs_containerapps_subnet:
            lines.append('    ca_subnet["snet-containerapps"]')
            lines.append('    ca_nsg["containerapps-nsg"]')
            lines.append("    vnet --> ca_subnet")
            lines.append("    ca_subnet --> ca_nsg")
        if needs_sql_subnet:
            lines.append('    sql_subnet["snet-sql"]')
            lines.append('    sql_nsg["sql-nsg"]')
            lines.append("    vnet --> sql_subnet")
            lines.append("    sql_subnet --> sql_nsg")
        if needs_apim_subnet:
            lines.append('    apim_subnet["snet-apim"]')
            lines.append('    apim_nsg["apim-nsg"]')
            lines.append("    vnet --> apim_subnet")
            lines.append("    apim_subnet --> apim_nsg")
        lines.append("  end")
        lines.append("  rg --> vnet")

    lines.append('  subgraph svc["Enabled Services"]')
    for svc in enabled_services:
        label = SERVICE_LABELS.get(svc, svc)
        node_id = f"svc_{svc}"
        lines.append(f'    {node_id}["{label}"]')
    lines.append("  end")
    lines.append("  rg --> svc")

    if networking_enabled and needs_pe_subnet:
        for svc in pe_services:
            lines.append(f"  pe_subnet --> svc_{svc}")

    if networking_enabled:
        for svc, cfg in enabled_services.items():
            if svc in PE_ZONE_MAP:
                if pe_enabled_for(svc, cfg, networking_enabled):
                    lines.append(f'  svc_{svc} -. "Public access: Disabled" .-> rg')
                else:
                    lines.append(f'  svc_{svc} -. "Public access: Enabled" .-> rg')

    if networking_enabled and pe_services:
        lines.append('  subgraph dns["Private DNS Zones"]')
        zone_ix = 0
        for svc in pe_services:
            for zone in PE_ZONE_MAP.get(svc, []):
                zone_ix += 1
                zone_id = f"dns_{zone_ix}"
                lines.append(f'    {zone_id}["{zone}"]')
                lines.append(f"    svc_{svc} --> {zone_id}")
        lines.append("  end")
        if needs_pe_subnet:
            lines.append("  pe_subnet --> dns")

    return "\n".join(lines) + "\n"


def generate_summary(config: dict[str, Any]) -> str:
    project = config.get("project", {})
    name = str(project.get("name", "project"))
    locations = project.get("locations", [])
    if isinstance(locations, str):
        locations = [locations]

    networking = config.get("networking", {})
    networking_enabled = as_bool(networking.get("enabled"), True)
    enabled_services = get_enabled_services(config)

    lines = []
    lines.append(f"# Architecture Summary: {name}")
    lines.append("")
    lines.append(f"- Generated: {dt.datetime.now(dt.timezone.utc).isoformat()}")
    lines.append(f"- Networking enabled: {networking_enabled}")
    lines.append(f"- Preferred regions: {', '.join(locations) if locations else '(not set)'}")
    lines.append("")
    lines.append("## Enabled Services")
    for svc, cfg in enabled_services.items():
        label = SERVICE_LABELS.get(svc, svc)
        pe = pe_enabled_for(svc, cfg, networking_enabled)
        if svc in PE_ZONE_MAP:
            lines.append(f"- {label}: private endpoint {'ON' if pe else 'OFF'}")
        else:
            lines.append(f"- {label}")
    lines.append("")
    lines.append("## Private DNS Zones")
    any_zone = False
    for svc, cfg in enabled_services.items():
        if pe_enabled_for(svc, cfg, networking_enabled):
            for zone in PE_ZONE_MAP.get(svc, []):
                any_zone = True
                lines.append(f"- {zone} ({SERVICE_LABELS.get(svc, svc)})")
    if not any_zone:
        lines.append("- none")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate architecture diagram files from config.toml.")
    parser.add_argument("--config", default="config.toml", help="Path to TOML config file")
    parser.add_argument("--out-dir", default="diagrams", help="Output directory")
    parser.add_argument("--name", default="architecture", help="Base output name")
    args = parser.parse_args()

    config_path = pathlib.Path(args.config).resolve()
    out_dir = pathlib.Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    cfg = load_config(config_path)
    mermaid = generate_mermaid(cfg)
    summary = generate_summary(cfg)

    mermaid_path = out_dir / f"{args.name}.mmd"
    summary_path = out_dir / f"{args.name}-summary.md"

    mermaid_path.write_text(mermaid, encoding="utf-8")
    summary_path.write_text(summary, encoding="utf-8")

    print(f"Wrote: {mermaid_path}")
    print(f"Wrote: {summary_path}")
    print("Tip: render Mermaid with mermaid.live or `mmdc` (Mermaid CLI).")
    return 0


if __name__ == "__main__":
    sys.exit(main())

