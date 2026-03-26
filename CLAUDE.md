# CLAUDE.md — hoas_pv (PV Sync Add-on)

## What This Is

A self-contained Home Assistant OS (HAOS) local add-on that replaces a NixOS-based pipeline. Deployed to `/addons/pv_sync/` on the HAOS machine at `192.168.176.3`.

## Runtime

- Base image: `alpine:3.21` (Docker Hub — ghcr.io HA base images return 403 for anonymous pulls)
- No bashio dependency — config read via `jq -r '.key' /data/options.json`, logging via plain `echo`
- Shebang: `#!/usr/bin/env bash`

## Pipeline (run.sh)

```
init_ssh → init_db → while true:
  fetch (SSH cat WAL files) → extract (sqlite3 → CSV) →
  load_staging (LOAD DATA LOCAL INFILE) → merge (5-day window) →
  publish_counters / publish_latest / publish_1h → sleep
```

## Key Facts

- PV device (`192.168.176.17`): lge-ems, BusyBox, no auth required on SSH — key generation loop in `init_ssh()` passes immediately
- MariaDB: `core-mariadb:3306`, requires `require_secure_transport: false` in MariaDB add-on config and `mariadb --ssl=FALSE` client flag
- Options file: `/data/options.json` (injected by Supervisor)
- SSH key persisted at `/data/ssh/id_rsa` (add-on `/data` volume)
- CSV files written to `/tmp/` inside container
- HA sensors published via `curl` to `http://supervisor/core/api/states/sensor.<name>` with `SUPERVISOR_TOKEN`
- **Energy unit**: The LG ESS DB stores all `_energy` columns in **Wh** (not kWh). `publish_counters()` divides by `ENERGY_DIVISOR` (1000 when `energy_unit=Wh`, 1 when `kWh`) before publishing. Without this the values show as ~1000× too large (e.g. 20 GWh instead of 20 MWh).
- **Updating addon options**: Use the Supervisor REST API from within a privileged addon container (e.g. SSH addon): `curl -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" -H "Content-Type: application/json" -d '{"options":{...}}' http://supervisor/addons/local_pv_sync/options`

## Files

| File | Purpose |
|------|---------|
| `config.yaml` | HAOS Supervisor manifest (use YAML — JSON rejected by Supervisor 2026.03.x) |
| `Dockerfile` | `FROM alpine:3.21`, installs sqlite/mariadb-client/openssh-client/sshpass/jq/curl/bash |
| `run.sh` | Full pipeline entrypoint |
| `README.md` | User-facing installation guide |

## Sensors (15 total)

- 4 counter sensors (`total_increasing`, kWh): `sensor.pv_zaehler`, `sensor.pv_direct_zaehler`, `sensor.batt_charge_zaehler`, `sensor.batt_discharge_zaehler`
- 8 instantaneous sensors (W / %): `sensor.pv_power`, `sensor.pv_direct_consumption`, `sensor.batt_charge`, `sensor.batt_discharge`, `sensor.batt_soc`, `sensor.grid_power_purchase`, `sensor.grid_feed_in`, `sensor.load_power`
- 3 time-series sensors (configurable window via `history_hours`, array in `attributes.data`): `sensor.pv_1h`, `sensor.battery_1h`, `sensor.consumption_1h`

## Config Options

| Option | Default | Schema | Description |
|--------|---------|--------|-------------|
| `pv_host` | `192.168.176.17` | str | IP/hostname of PV system |
| `pv_user` | `root` | str | SSH user on PV system |
| `interval` | `15` | int(1,60) | Sync interval in minutes |
| `db_user` | `pvsync` | str | MariaDB username |
| `db_password` | `` | password | MariaDB password |
| `db_name` | `dbfiles` | str | Production database name (`dbfiles2` staging always hardcoded) |
| `energy_unit` | `Wh` | list(Wh\|kWh) | Unit stored in DB — controls ÷1000 factor for counter sensors |
| `history_hours` | `1` | int(1,24) | Hours of data in time-series sensors |

## GitHub Repo

`git@github.com:JoeRu/hoas-LG_ESS_PV-addon.git`
