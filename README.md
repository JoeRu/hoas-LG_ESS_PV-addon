# PV Sync Add-on for Home Assistant

This add-on fetches energy data from a local PV system via SSH and publishes 15 sensors directly to Home Assistant without requiring MQTT, Node-RED, or external automation.

## What It Does

The add-on:
1. Connects to a remote PV system over SSH using key-based authentication
2. Extracts SQLite WAL files (`ems_DEU.db`) from the PV system
3. Parses time-series data and stores it in MariaDB (via the Home Assistant MariaDB add-on)
4. Publishes 15 sensors to Home Assistant using the Supervisor REST API
5. Runs on a configurable schedule (default: every 15 minutes)

## Prerequisites

- Home Assistant OS with the official **MariaDB add-on** (`core-mariadb`) installed and running
- MariaDB add-on configured with `local_infile = 1`. Add this to the MariaDB add-on configuration:
  ```
  [mysqld]
  local_infile = 1
  ```
- A MariaDB user with CREATE, INSERT, SELECT, and DELETE privileges on two databases: `dbfiles` and `dbfiles2`
- Network connectivity to the PV system (SSH, port 22 by default)

## Installation

1. Copy the `hoas_pv/` directory to your Home Assistant add-ons directory:
   - On HAOS: `/addons/pv_sync/` (create the directory if needed)
   - On HA Container/Supervised: check your add-ons path in `configuration.yaml`

2. In Home Assistant UI: Settings → Add-ons → Add-on Store → (reload icon) → Find "PV Sync" → Install

3. Configure the add-on options:
   - `pv_host`: IP address or hostname of the PV system
   - `pv_user`: SSH username (typically `root`)
   - `interval`: How often to sync in minutes (default: 15)
   - `db_user`: MariaDB username
   - `db_password`: MariaDB password
   - `db_name`: Database name (default: `dbfiles`)
   - `energy_unit`: Unit used by the PV database — `Wh` or `kWh` (default: `Wh`). The LG ESS stores energy in Wh per 15-min interval; this option divides by 1000 before publishing sensors so they show correct kWh values.
   - `history_hours`: How many hours of data to include in the time-series sensors (default: `1`, max: `24`)

4. Start the add-on from the UI

## SSH Key Setup (First Run)

On first start, the add-on generates an RSA key pair in `/data/ssh/`:
- The public key is printed in the add-on log (Settings → Add-ons → Logs)
- Copy the public key and add it to `/root/.ssh/authorized_keys` on the PV system
- The add-on retries every 30 seconds until SSH succeeds, then enters the main sync loop

## Sensors Published

**Counter Sensors (total_increasing, unit: kWh):**
- `sensor.pv_zaehler` — PV energy total
- `sensor.pv_direct_zaehler` — Direct PV consumption
- `sensor.batt_charge_zaehler` — Battery energy charged
- `sensor.batt_discharge_zaehler` — Battery energy discharged

**Instantaneous Sensors (current values):**
- `sensor.pv_power` — Current PV output (W)
- `sensor.pv_direct_consumption` — Direct consumption (W)
- `sensor.batt_charge` — Battery charge current (W)
- `sensor.batt_discharge` — Battery discharge current (W)
- `sensor.batt_soc` — Battery state of charge (%)
- `sensor.grid_power_purchase` — Grid import (W)
- `sensor.grid_feed_in` — Grid export (W)
- `sensor.load_power` — Load consumption (W)

**Time-Series Sensors (configurable window, data in attributes):**
- `sensor.pv_1h` — PV power history (`history_hours` window)
- `sensor.battery_1h` — Battery history (`history_hours` window)
- `sensor.consumption_1h` — Consumption history (`history_hours` window)

## Troubleshooting

- **SSH connection failed**: Check that the public key is correctly added to the PV system's `authorized_keys` and that the IP/hostname is reachable
- **MariaDB connection failed**: Verify credentials and that `local_infile = 1` is set in the MariaDB add-on config
- **No sensors appearing**: Check the add-on logs for errors; the add-on must complete one full sync cycle to create sensors
