#!/usr/bin/with-contenv bashio

# ── Config ────────────────────────────────────────────────────────────────────
PV_HOST=$(bashio::config 'pv_host')
PV_USER=$(bashio::config 'pv_user')
INTERVAL=$(bashio::config 'interval')
DB_USER=$(bashio::config 'db_user')
DB_PASS=$(bashio::config 'db_password')
DB_NAME=$(bashio::config 'db_name')

readonly DB_HOST="core-mariadb"
readonly DB_PORT="3306"
readonly DB_STAGING="dbfiles2"
readonly SSH_KEY="/data/ssh/id_rsa"
readonly PV_DB="/nvdata/DBFiles/ems_DEU.db"

# ── Helpers ───────────────────────────────────────────────────────────────────
mysql_cmd() {
    mysql --local-infile -h "${DB_HOST}" -P "${DB_PORT}" \
          -u "${DB_USER}" -p"${DB_PASS}" "$@"
}

ssh_cmd() {
    ssh -i "${SSH_KEY}" \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        "${PV_USER}@${PV_HOST}" "$@"
}

ha_sensor() {
    local entity="$1"
    local payload="$2"
    curl -s -X POST \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        "http://supervisor/core/api/states/${entity}" > /dev/null
}
# ── SSH Init ──────────────────────────────────────────────────────────────────
init_ssh() {
    if [ ! -f "${SSH_KEY}" ]; then
        mkdir -p /data/ssh
        chmod 700 /data/ssh
        ssh-keygen -t rsa -b 4096 -f "${SSH_KEY}" -N "" -q
        bashio::log.info "═══════════════════════════════════════════"
        bashio::log.info "SSH key generated. Add this public key to"
        bashio::log.info "${PV_USER}@${PV_HOST}:/root/.ssh/authorized_keys:"
        bashio::log.info "$(cat "${SSH_KEY}.pub")"
        bashio::log.info "═══════════════════════════════════════════"
    fi

    bashio::log.info "Testing SSH connection to ${PV_HOST}..."
    while ! ssh_cmd true 2>/dev/null; do
        bashio::log.info "Waiting for SSH key to be authorized on PV system (retrying in 30s)..."
        sleep 30
    done
    bashio::log.info "SSH authorized — starting sync loop"
}

# ── DB Init ───────────────────────────────────────────────────────────────────
init_db() {
    bashio::log.info "Initializing databases..."

    mysql_cmd -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;"
    mysql_cmd -e "CREATE DATABASE IF NOT EXISTS \`${DB_STAGING}\`;"

    mysql_cmd "${DB_NAME}" <<'EOF'
CREATE TABLE IF NOT EXISTS my_tbl_record_quarter (
  time_utc                      INTEGER PRIMARY KEY,
  time_local                    DATETIME,
  time_gmtoff                   INTEGER,
  pv_power                      DOUBLE,
  pv_power_energy               DOUBLE,
  pv_direct_consumption         DOUBLE,
  pv_direct_consumption_energy  DOUBLE,
  batt_charge                   DOUBLE,
  batt_charge_energy            DOUBLE,
  batt_discharge                DOUBLE,
  batt_discharge_energy         DOUBLE,
  batt_soc                      DOUBLE,
  grid_power_purchase           DOUBLE,
  grid_power_purchase_energy    DOUBLE,
  grid_feed_in                  DOUBLE,
  grid_feed_in_energy           DOUBLE,
  expect_purchase_price         DOUBLE,
  expect_sales_price            DOUBLE,
  load_power                    DOUBLE,
  load_power_energy             DOUBLE,
  co2_reduction_accum           DOUBLE,
  pv_generation_sum             DOUBLE,
  load_consumption_sum          DOUBLE,
  self_consumption              DOUBLE,
  self_sufficiency              DOUBLE
);

CREATE TABLE IF NOT EXISTS my_tbl_record_day (
  time_utc                      INTEGER PRIMARY KEY,
  time_local                    DATE,
  time_gmtoff                   INTEGER,
  pv_power_energy               DOUBLE,
  pv_direct_consumption_energy  DOUBLE,
  batt_charge_energy            DOUBLE,
  batt_discharge_energy         DOUBLE,
  grid_power_purchase_energy    DOUBLE,
  grid_feed_in_energy           DOUBLE,
  expect_purchase_price         DOUBLE,
  expect_sales_price            DOUBLE,
  load_power_energy             DOUBLE,
  co2_reduction_accum           DOUBLE,
  pv_generation_sum             DOUBLE,
  load_consumption_sum          DOUBLE,
  self_consumption              DOUBLE,
  self_sufficiency              DOUBLE
);

CREATE TABLE IF NOT EXISTS my_tbl_record_month (
  time_utc                      INTEGER PRIMARY KEY,
  time_local                    DATE,
  time_gmtoff                   INTEGER,
  pv_power_energy               DOUBLE,
  pv_direct_consumption_energy  DOUBLE,
  batt_charge_energy            DOUBLE,
  batt_discharge_energy         DOUBLE,
  grid_power_purchase_energy    DOUBLE,
  grid_feed_in_energy           DOUBLE,
  expect_purchase_price         DOUBLE,
  expect_sales_price            DOUBLE,
  load_power_energy             DOUBLE,
  co2_reduction_accum           DOUBLE,
  pv_generation_sum             DOUBLE,
  load_consumption_sum          DOUBLE,
  self_consumption              DOUBLE,
  self_sufficiency              DOUBLE
);

CREATE TABLE IF NOT EXISTS my_tbl_record_week (
  time_utc                      INTEGER PRIMARY KEY,
  time_local                    DATE,
  time_gmtoff                   INTEGER,
  pv_power_energy               DOUBLE,
  pv_direct_consumption_energy  DOUBLE,
  batt_charge_energy            DOUBLE,
  batt_discharge_energy         DOUBLE,
  grid_power_purchase_energy    DOUBLE,
  grid_feed_in_energy           DOUBLE,
  expect_purchase_price         DOUBLE,
  expect_sales_price            DOUBLE,
  load_power_energy             DOUBLE,
  pv_generation_sum             DOUBLE,
  load_consumption_sum          DOUBLE,
  self_consumption              DOUBLE,
  self_sufficiency              DOUBLE
);
EOF

    mysql_cmd "${DB_STAGING}" <<'EOF'
CREATE TABLE IF NOT EXISTS x_my_tbl_record_quarter (
  time_utc                      INTEGER PRIMARY KEY,
  time_local                    DATETIME,
  time_gmtoff                   INTEGER,
  pv_power                      DOUBLE,
  pv_power_energy               DOUBLE,
  pv_direct_consumption         DOUBLE,
  pv_direct_consumption_energy  DOUBLE,
  batt_charge                   DOUBLE,
  batt_charge_energy            DOUBLE,
  batt_discharge                DOUBLE,
  batt_discharge_energy         DOUBLE,
  batt_soc                      DOUBLE,
  grid_power_purchase           DOUBLE,
  grid_power_purchase_energy    DOUBLE,
  grid_feed_in                  DOUBLE,
  grid_feed_in_energy           DOUBLE,
  expect_purchase_price         DOUBLE,
  expect_sales_price            DOUBLE,
  load_power                    DOUBLE,
  load_power_energy             DOUBLE,
  co2_reduction_accum           DOUBLE,
  pv_generation_sum             DOUBLE,
  load_consumption_sum          DOUBLE,
  self_consumption              DOUBLE,
  self_sufficiency              DOUBLE
);

CREATE TABLE IF NOT EXISTS x_my_tbl_record_day (
  time_utc                      INTEGER PRIMARY KEY,
  time_local                    DATE,
  time_gmtoff                   INTEGER,
  pv_power_energy               DOUBLE,
  pv_direct_consumption_energy  DOUBLE,
  batt_charge_energy            DOUBLE,
  batt_discharge_energy         DOUBLE,
  grid_power_purchase_energy    DOUBLE,
  grid_feed_in_energy           DOUBLE,
  expect_purchase_price         DOUBLE,
  expect_sales_price            DOUBLE,
  load_power_energy             DOUBLE,
  co2_reduction_accum           DOUBLE,
  pv_generation_sum             DOUBLE,
  load_consumption_sum          DOUBLE,
  self_consumption              DOUBLE,
  self_sufficiency              DOUBLE
);

CREATE TABLE IF NOT EXISTS x_my_tbl_record_month (
  time_utc                      INTEGER PRIMARY KEY,
  time_local                    DATE,
  time_gmtoff                   INTEGER,
  pv_power_energy               DOUBLE,
  pv_direct_consumption_energy  DOUBLE,
  batt_charge_energy            DOUBLE,
  batt_discharge_energy         DOUBLE,
  grid_power_purchase_energy    DOUBLE,
  grid_feed_in_energy           DOUBLE,
  expect_purchase_price         DOUBLE,
  expect_sales_price            DOUBLE,
  load_power_energy             DOUBLE,
  co2_reduction_accum           DOUBLE,
  pv_generation_sum             DOUBLE,
  load_consumption_sum          DOUBLE,
  self_consumption              DOUBLE,
  self_sufficiency              DOUBLE
);

CREATE TABLE IF NOT EXISTS x_my_tbl_record_week (
  time_utc                      INTEGER PRIMARY KEY,
  time_local                    DATE,
  time_gmtoff                   INTEGER,
  pv_power_energy               DOUBLE,
  pv_direct_consumption_energy  DOUBLE,
  batt_charge_energy            DOUBLE,
  batt_discharge_energy         DOUBLE,
  grid_power_purchase_energy    DOUBLE,
  grid_feed_in_energy           DOUBLE,
  expect_purchase_price         DOUBLE,
  expect_sales_price            DOUBLE,
  load_power_energy             DOUBLE,
  pv_generation_sum             DOUBLE,
  load_consumption_sum          DOUBLE,
  self_consumption              DOUBLE,
  self_sufficiency              DOUBLE
);
EOF

    bashio::log.info "DB initialization complete"
}

# ── Phase 1: Fetch ────────────────────────────────────────────────────────────
fetch() {
    bashio::log.info "Fetching SQLite DB from ${PV_HOST}..."
    ssh_cmd "cat ${PV_DB}"        > /tmp/ems.db     || return 1
    ssh_cmd "cat ${PV_DB}-wal"    > /tmp/ems.db-wal 2>/dev/null || true
    ssh_cmd "cat ${PV_DB}-shm"    > /tmp/ems.db-shm 2>/dev/null || true
    bashio::log.info "Fetch complete ($(du -sh /tmp/ems.db | cut -f1))"
}

# ── Phase 2: Extract ──────────────────────────────────────────────────────────
extract() {
    bashio::log.info "Extracting CSV from SQLite..."

    sqlite3 -header -csv /tmp/ems.db "
SELECT time_utc,
       substr(time_local,0,5)||'-'||substr(time_local,5,2)||'-'||substr(time_local,7,2)||' '||
       substr(time_local,9,2)||':'||substr(time_local,11,2)||':'||substr(time_local,13,2)||'',
       time_gmtoff, pv_power, pv_power_energy,
       pv_direct_consumption, pv_direct_consumption_energy,
       batt_charge, batt_charge_energy,
       batt_discharge, batt_discharge_energy, batt_soc,
       grid_power_purchase, grid_power_purchase_energy,
       grid_feed_in, grid_feed_in_energy,
       expect_purchase_price, expect_sales_price,
       load_power, load_power_energy, co2_reduction_accum,
       pv_generation_sum, load_consumption_sum,
       self_consumption, self_sufficiency
FROM tbl_record_quarter;
" > /tmp/quarter.csv

    sqlite3 -header -csv /tmp/ems.db "
SELECT time_utc,
       substr(time_local,0,5)||'/'||substr(time_local,5,2)||'/'||substr(time_local,7,2) as time_local,
       time_gmtoff, pv_power_energy, pv_direct_consumption_energy,
       batt_charge_energy, batt_discharge_energy,
       grid_power_purchase_energy, grid_feed_in_energy,
       expect_purchase_price, expect_sales_price,
       load_power_energy, co2_reduction_accum,
       pv_generation_sum, load_consumption_sum,
       self_consumption, self_sufficiency
FROM tbl_record_day;
" > /tmp/day.csv

    sqlite3 -header -csv /tmp/ems.db "
SELECT time_utc,
       substr(time_local,0,5)||'/'||substr(time_local,5,2)||'/'||substr(time_local,7,2),
       time_gmtoff, pv_power_energy, pv_direct_consumption_energy,
       batt_charge_energy, batt_discharge_energy,
       grid_power_purchase_energy, grid_feed_in_energy,
       expect_purchase_price, expect_sales_price,
       load_power_energy,
       pv_generation_sum, load_consumption_sum,
       self_consumption, self_sufficiency
FROM tbl_record_week;
" > /tmp/week.csv

    sqlite3 -header -csv /tmp/ems.db "
SELECT time_utc,
       substr(time_local,0,5)||'/'||substr(time_local,5,2)||'/'||substr(time_local,7,2),
       time_gmtoff, pv_power_energy, pv_direct_consumption_energy,
       batt_charge_energy, batt_discharge_energy,
       grid_power_purchase_energy, grid_feed_in_energy,
       expect_purchase_price, expect_sales_price,
       load_power_energy, co2_reduction_accum,
       pv_generation_sum, load_consumption_sum,
       self_consumption, self_sufficiency
FROM tbl_record_month;
" > /tmp/month.csv

    bashio::log.info "Extract complete: quarter=$(wc -l < /tmp/quarter.csv) day=$(wc -l < /tmp/day.csv) week=$(wc -l < /tmp/week.csv) month=$(wc -l < /tmp/month.csv) rows (incl. header)"
}

# ── Phase 3: Load ─────────────────────────────────────────────────────────────
load_staging() {
    bashio::log.info "Loading CSV into staging tables..."

    mysql_cmd "${DB_STAGING}" <<EOF
TRUNCATE TABLE x_my_tbl_record_quarter;
LOAD DATA LOCAL INFILE '/tmp/quarter.csv'
INTO TABLE x_my_tbl_record_quarter
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

TRUNCATE TABLE x_my_tbl_record_day;
LOAD DATA LOCAL INFILE '/tmp/day.csv'
INTO TABLE x_my_tbl_record_day
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

TRUNCATE TABLE x_my_tbl_record_week;
LOAD DATA LOCAL INFILE '/tmp/week.csv'
INTO TABLE x_my_tbl_record_week
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

TRUNCATE TABLE x_my_tbl_record_month;
LOAD DATA LOCAL INFILE '/tmp/month.csv'
INTO TABLE x_my_tbl_record_month
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;
EOF

    bashio::log.info "Staging load complete"
}

# ── Phase 4: Merge ────────────────────────────────────────────────────────────
merge() {
    bashio::log.info "Merging staging into production (5-day window)..."

    mysql_cmd "${DB_NAME}" <<EOF
SET @date_start = UNIX_TIMESTAMP(CURDATE() - INTERVAL 5 DAY);
SET @date_end   = UNIX_TIMESTAMP();

DELETE FROM my_tbl_record_quarter WHERE time_utc >= @date_start AND time_utc <= @date_end;
DELETE FROM my_tbl_record_day     WHERE time_utc >= @date_start AND time_utc <= @date_end;
DELETE FROM my_tbl_record_week    WHERE time_utc >= @date_start AND time_utc <= @date_end;
DELETE FROM my_tbl_record_month   WHERE time_utc >= @date_start AND time_utc <= @date_end;

INSERT INTO my_tbl_record_day
  SELECT * FROM ${DB_STAGING}.x_my_tbl_record_day t1
  WHERE t1.time_utc NOT IN (
    SELECT t1.time_utc FROM ${DB_STAGING}.x_my_tbl_record_day t1
    INNER JOIN my_tbl_record_day t2 ON t1.time_utc = t2.time_utc
  );

INSERT INTO my_tbl_record_week
  SELECT * FROM ${DB_STAGING}.x_my_tbl_record_week t1
  WHERE t1.time_utc NOT IN (
    SELECT t1.time_utc FROM my_tbl_record_week t1
    INNER JOIN ${DB_STAGING}.x_my_tbl_record_week t2 ON t1.time_utc = t2.time_utc
  );

INSERT INTO my_tbl_record_month
  SELECT * FROM ${DB_STAGING}.x_my_tbl_record_month t1
  WHERE t1.time_utc NOT IN (
    SELECT t1.time_utc FROM my_tbl_record_month t1
    INNER JOIN ${DB_STAGING}.x_my_tbl_record_month t2 ON t1.time_utc = t2.time_utc
  );

INSERT INTO my_tbl_record_quarter
  SELECT * FROM ${DB_STAGING}.x_my_tbl_record_quarter t1
  WHERE t1.time_utc NOT IN (
    SELECT t1.time_utc FROM my_tbl_record_quarter t1
    INNER JOIN ${DB_STAGING}.x_my_tbl_record_quarter t2 ON t1.time_utc = t2.time_utc
  );
EOF

    bashio::log.info "Merge complete"
}

# ── Task 9: publish_counters ───────────────────────────────────────────────────
publish_counters() {
    bashio::log.info "Publishing counter sensors..."

    local val payload

    val=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(SUM(pv_power_energy),0) FROM my_tbl_record_quarter")
    payload=$(jq -n --arg state "$val" '{state: $state, attributes: {unit_of_measurement: "kWh", device_class: "energy", state_class: "total_increasing", friendly_name: "PV Zähler"}}')
    ha_sensor "sensor.pv_zaehler" "$payload"

    val=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(SUM(pv_direct_consumption_energy),0) FROM my_tbl_record_quarter")
    payload=$(jq -n --arg state "$val" '{state: $state, attributes: {unit_of_measurement: "kWh", device_class: "energy", state_class: "total_increasing", friendly_name: "PV Direktverbrauch Zähler"}}')
    ha_sensor "sensor.pv_direct_zaehler" "$payload"

    val=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(SUM(batt_charge_energy),0) FROM my_tbl_record_quarter")
    payload=$(jq -n --arg state "$val" '{state: $state, attributes: {unit_of_measurement: "kWh", device_class: "energy", state_class: "total_increasing", friendly_name: "Batterie Laden Zähler"}}')
    ha_sensor "sensor.batt_charge_zaehler" "$payload"

    val=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(SUM(batt_discharge_energy),0) FROM my_tbl_record_quarter")
    payload=$(jq -n --arg state "$val" '{state: $state, attributes: {unit_of_measurement: "kWh", device_class: "energy", state_class: "total_increasing", friendly_name: "Batterie Entladen Zähler"}}')
    ha_sensor "sensor.batt_discharge_zaehler" "$payload"

    bashio::log.info "Counter sensors published"
}

# ── Task 10: publish_latest ────────────────────────────────────────────────────
publish_latest() {
    bashio::log.info "Publishing latest value sensors..."

    local val payload

    val=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(pv_power,0) FROM my_tbl_record_quarter ORDER BY time_utc DESC LIMIT 1")
    payload=$(jq -n --arg state "$val" '{state: $state, attributes: {unit_of_measurement: "W", device_class: "power", state_class: "measurement", friendly_name: "PV Leistung"}}')
    ha_sensor "sensor.pv_power" "$payload"

    val=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(pv_direct_consumption,0) FROM my_tbl_record_quarter ORDER BY time_utc DESC LIMIT 1")
    payload=$(jq -n --arg state "$val" '{state: $state, attributes: {unit_of_measurement: "W", device_class: "power", state_class: "measurement", friendly_name: "PV Direktverbrauch"}}')
    ha_sensor "sensor.pv_direct_consumption" "$payload"

    val=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(batt_charge,0) FROM my_tbl_record_quarter ORDER BY time_utc DESC LIMIT 1")
    payload=$(jq -n --arg state "$val" '{state: $state, attributes: {unit_of_measurement: "W", device_class: "power", state_class: "measurement", friendly_name: "Batterie Laden"}}')
    ha_sensor "sensor.batt_charge" "$payload"

    val=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(batt_discharge,0) FROM my_tbl_record_quarter ORDER BY time_utc DESC LIMIT 1")
    payload=$(jq -n --arg state "$val" '{state: $state, attributes: {unit_of_measurement: "W", device_class: "power", state_class: "measurement", friendly_name: "Batterie Entladen"}}')
    ha_sensor "sensor.batt_discharge" "$payload"

    val=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(batt_soc,0) FROM my_tbl_record_quarter ORDER BY time_utc DESC LIMIT 1")
    payload=$(jq -n --arg state "$val" '{state: $state, attributes: {unit_of_measurement: "%", device_class: "battery", state_class: "measurement", friendly_name: "Batterie SOC"}}')
    ha_sensor "sensor.batt_soc" "$payload"

    val=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(grid_power_purchase,0) FROM my_tbl_record_quarter ORDER BY time_utc DESC LIMIT 1")
    payload=$(jq -n --arg state "$val" '{state: $state, attributes: {unit_of_measurement: "W", device_class: "power", state_class: "measurement", friendly_name: "Netzbezug"}}')
    ha_sensor "sensor.grid_power_purchase" "$payload"

    val=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(grid_feed_in,0) FROM my_tbl_record_quarter ORDER BY time_utc DESC LIMIT 1")
    payload=$(jq -n --arg state "$val" '{state: $state, attributes: {unit_of_measurement: "W", device_class: "power", state_class: "measurement", friendly_name: "Netzeinspeisung"}}')
    ha_sensor "sensor.grid_feed_in" "$payload"

    val=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(load_power,0) FROM my_tbl_record_quarter ORDER BY time_utc DESC LIMIT 1")
    payload=$(jq -n --arg state "$val" '{state: $state, attributes: {unit_of_measurement: "W", device_class: "power", state_class: "measurement", friendly_name: "Verbrauch"}}')
    ha_sensor "sensor.load_power" "$payload"

    bashio::log.info "Latest value sensors published"
}

# ── Task 11: publish_1h ────────────────────────────────────────────────────────
publish_1h() {
    bashio::log.info "Publishing 1h history sensors..."

    local rows json_array row_count payload

    # sensor.pv_1h
    rows=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(time_utc,0), COALESCE(pv_power_energy,0), COALESCE(pv_direct_consumption_energy,0) FROM my_tbl_record_quarter WHERE time_utc > UNIX_TIMESTAMP(UTC_TIMESTAMP() - INTERVAL 1 HOUR) ORDER BY time_utc ASC")
    if [[ -z "$rows" ]]; then
        json_array='[]'
        row_count=0
    else
        row_count=$(echo "$rows" | grep -c . || echo 0)
        json_array=$(echo "$rows" | jq -R 'split("\t") | {time: (.[0]|tonumber), pv_power_energy: (.[1]|tonumber), pv_direct_consumption_energy: (.[2]|tonumber)}' | jq -s '.')
    fi
    payload=$(jq -n --argjson data "$json_array" --arg state "$row_count" '{"state": $state, "attributes": {"data": $data, "unit_of_measurement": "rows", "friendly_name": "PV 1H"}}')
    ha_sensor "sensor.pv_1h" "$payload"

    # sensor.battery_1h
    rows=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(time_utc,0), COALESCE(batt_charge_energy,0), COALESCE(batt_discharge_energy,0) FROM my_tbl_record_quarter WHERE time_utc > UNIX_TIMESTAMP(UTC_TIMESTAMP() - INTERVAL 1 HOUR) ORDER BY time_utc ASC")
    if [[ -z "$rows" ]]; then
        json_array='[]'
        row_count=0
    else
        row_count=$(echo "$rows" | grep -c . || echo 0)
        json_array=$(echo "$rows" | jq -R 'split("\t") | {time: (.[0]|tonumber), batt_charge_energy: (.[1]|tonumber), batt_discharge_energy: (.[2]|tonumber)}' | jq -s '.')
    fi
    payload=$(jq -n --argjson data "$json_array" --arg state "$row_count" '{"state": $state, "attributes": {"data": $data, "unit_of_measurement": "rows", "friendly_name": "Batterie 1H"}}')
    ha_sensor "sensor.battery_1h" "$payload"

    # sensor.consumption_1h
    rows=$(mysql_cmd "$DB_NAME" -sN -e "SELECT COALESCE(time_utc,0), COALESCE(pv_direct_consumption_energy,0), COALESCE(load_power_energy,0), COALESCE(batt_discharge_energy,0), COALESCE(grid_power_purchase_energy,0) FROM my_tbl_record_quarter WHERE time_utc > UNIX_TIMESTAMP(UTC_TIMESTAMP() - INTERVAL 1 HOUR) ORDER BY time_utc ASC")
    if [[ -z "$rows" ]]; then
        json_array='[]'
        row_count=0
    else
        row_count=$(echo "$rows" | grep -c . || echo 0)
        json_array=$(echo "$rows" | jq -R 'split("\t") | {time: (.[0]|tonumber), pv_direct_consumption_energy: (.[1]|tonumber), load_power_energy: (.[2]|tonumber), batt_discharge_energy: (.[3]|tonumber), grid_power_purchase_energy: (.[4]|tonumber)}' | jq -s '.')
    fi
    payload=$(jq -n --argjson data "$json_array" --arg state "$row_count" '{"state": $state, "attributes": {"data": $data, "unit_of_measurement": "rows", "friendly_name": "Verbrauch 1H"}}')
    ha_sensor "sensor.consumption_1h" "$payload"

    bashio::log.info "1h history sensors published"
}

# ── Main ──────────────────────────────────────────────────────────────────────
init_ssh
init_db

while true; do
    bashio::log.info "Starting sync cycle..."
    if fetch; then
        extract \
        && load_staging \
        && merge \
        && publish_counters \
        && publish_latest \
        && publish_1h \
        && bashio::log.info "Sync cycle complete"
    else
        bashio::log.info "Fetch failed — skipping cycle"
    fi
    bashio::log.info "Sleeping ${INTERVAL} minutes..."
    sleep $((INTERVAL * 60))
done
