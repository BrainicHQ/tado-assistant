#!/bin/bash

# Source the environment variables if the file exists
[ -f /etc/tado-assistant.env ] && source /etc/tado-assistant.env

# Create log directory if it doesn't exist
LOG_DIR=$(dirname "$LOG_FILE")
mkdir -p "$LOG_DIR"

declare -A OPEN_WINDOW_ACTIVATION_TIMES HOME_IDS API_BASE_URLS LAST_FLOW_TEMP_ADJUSTMENT
LAST_MESSAGE="" # Used to prevent duplicate messages

# Reset the log file if it's older than 10 days
reset_log_if_needed() {
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi

    local max_age_days=10
    local current_time=$(date +%s)
    local last_modified=$(date -r "$LOG_FILE" +%s)
    local age_days=$(( (current_time - last_modified) / 86400 ))

    if [ "$age_days" -ge "$max_age_days" ]; then
        local timestamp=$(date '+%Y%m%d%H%M%S')
        local backup_log="${LOG_FILE}.${timestamp}"
        mv "$LOG_FILE" "$backup_log"
        touch "$LOG_FILE"
        echo "🔄 Log reset: $backup_log"
    fi
}

# Error handling for curl
handle_curl_error() {
    if [ $? -ne 0 ]; then
        log_message "Curl command failed. Retrying in 60 seconds."
        sleep 60
        return 1
    fi
    return 0
}

normalize_base_url() {
    local url="$1"
    echo "${url%/}"
}

api_request() {
    local account_index=$1
    local method=$2
    local path=$3
    local data=${4:-}
    local base_url="${API_BASE_URLS[$account_index]}"
    local url="${base_url}${path}"
    local curl_args=(-s -X "$method")

    if [ -n "$data" ]; then
        curl_args+=(-H "Content-Type: application/json" -d "$data")
    fi

    curl "${curl_args[@]}" "$url"
}

is_local_proxy() {
    local base_url="$1"
    case "$base_url" in
        http://localhost*|http://127.0.0.1*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

ensure_proxy_running() {
    local account_index=$1
    local base_url="${API_BASE_URLS[$account_index]}"
    local env_file="/etc/tado-api-proxy/account${account_index}.env"
    local log_file="/var/log/tado-api-proxy-account${account_index}.log"
    local runtime_dir="${TADO_PROXY_RUNTIME_DIR:-/tmp/tado-api-proxy}"
    local lock_dir="${runtime_dir}/account${account_index}.lock"
    local pid_file="${runtime_dir}/account${account_index}.pid"
    local state_file="${runtime_dir}/account${account_index}.last_start"
    local backoff="${TADO_PROXY_START_BACKOFF:-30}"

    if command -v systemctl &> /dev/null && [ -d /run/systemd/system ]; then
        return 0
    fi
    if [[ "$OSTYPE" == "darwin"* ]] && command -v launchctl &> /dev/null; then
        return 0
    fi
    if ! is_local_proxy "$base_url"; then
        return 0
    fi
    if [ ! -x /usr/local/bin/tado-api-proxy ]; then
        log_message "⚠️ Account $account_index: tado-api-proxy binary not found."
        return 1
    fi
    if curl -fsS --max-time 2 "${base_url}/docs" >/dev/null 2>&1; then
        return 0
    fi
    if [ ! -f "$env_file" ]; then
        log_message "⚠️ Account $account_index: Proxy env file missing at $env_file."
        return 1
    fi

    case "$backoff" in
        ''|*[!0-9]*)
            backoff=30
            ;;
    esac

    mkdir -p "$runtime_dir"
    if [ -f "$pid_file" ]; then
        if kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
            return 0
        fi
        rm -f "$pid_file"
    fi

    if ! mkdir "$lock_dir" 2>/dev/null; then
        return 0
    fi
    trap 'rmdir "$lock_dir" 2>/dev/null' RETURN

    local now
    now=$(date +%s)
    if [ -f "$state_file" ]; then
        local last_attempt
        last_attempt=$(cat "$state_file" 2>/dev/null || true)
        if [ -n "$last_attempt" ] && [ $((now - last_attempt)) -lt "$backoff" ]; then
            return 0
        fi
    fi
    printf '%s' "$now" > "$state_file"

    log_message "🔌 Account $account_index: Starting local tado-api-proxy."
    mkdir -p "$(dirname "$log_file")"
    (
        set -a
        . "$env_file"
        set +a
        nohup /usr/local/bin/tado-api-proxy >> "$log_file" 2>&1 &
        echo $! > "$pid_file"
    )
    sleep 1
}

fetch_home_id() {
    local account_index=$1
    local home_data
    local home_id

    home_data=$(api_request "$account_index" GET "/api/v2/me")
    handle_curl_error

    home_id=$(echo "$home_data" | jq -r '.homes[0].id')
    if [ -z "$home_id" ] || [ "$home_id" == "null" ]; then
        log_message "⚠️ Error fetching home ID for account $account_index!"
        exit 1
    fi

    HOME_IDS[$account_index]=$home_id
}

log_message() {
    local message="$1"
    reset_log_if_needed
    if [ "$ENABLE_LOG" = true ] && [ "$LAST_MESSAGE" != "$message" ]; then
        echo "$(date '+%d-%m-%Y %H:%M:%S') # $message" >> "$LOG_FILE"
        LAST_MESSAGE="$message"
    fi
    echo "$(date '+%d-%m-%Y %H:%M:%S') # $message"
}

init_account() {
    local account_index=$1

    log_message "🔌 Account $account_index: Using tado-api-proxy at ${API_BASE_URLS[$account_index]}"
    ensure_proxy_running "$account_index"
    fetch_home_id "$account_index"
}

optimize_flow_temperature() {
    local account_index=$1
    local home_id=${HOME_IDS[$account_index]}
    local current_time=$(date +%s)
    
    # Note: ENABLE_FLOW_TEMP_OPTIMIZATION, FLOW_TEMP_MIN, FLOW_TEMP_MAX, and FLOW_TEMP_CURVE_SLOPE
    # are set in the main loop before this function is called, using account-specific variables
    
    # Check if flow temperature optimization is enabled
    if [ "$ENABLE_FLOW_TEMP_OPTIMIZATION" != "true" ]; then
        return 0
    fi
    
    # Check if enough time has passed since last adjustment (minimum 15 minutes)
    local min_adjustment_interval=900
    if [ -n "${LAST_FLOW_TEMP_ADJUSTMENT[$account_index]}" ]; then
        local last_adjustment=${LAST_FLOW_TEMP_ADJUSTMENT[$account_index]}
        local time_since_last=$((current_time - last_adjustment))
        if [ "$time_since_last" -lt "$min_adjustment_interval" ]; then
            return 0
        fi
    fi
    
    ensure_proxy_running "$account_index"
    
    # Fetch outdoor temperature from weather data
    local weather
    weather=$(api_request "$account_index" GET "/api/v2/homes/$home_id/weather")
    if ! handle_curl_error; then
        return 1
    fi
    
    local outdoor_temp=$(echo "$weather" | jq -r '.outsideTemperature.celsius // empty')
    if [ -z "$outdoor_temp" ] || [ "$outdoor_temp" == "null" ]; then
        log_message "⚠️ Account $account_index: Could not fetch outdoor temperature for flow temp optimization."
        return 1
    fi
    
    # Calculate optimal flow temperature using weather compensation curve
    # Formula: flow_temp = max_temp - (slope * outdoor_temp)
    # Calculate target flow temperature
    local target_flow_temp=$(awk -v max="$FLOW_TEMP_MAX" -v slope="$FLOW_TEMP_CURVE_SLOPE" -v outdoor="$outdoor_temp" -v min="$FLOW_TEMP_MIN" '
        BEGIN {
            result = max - (slope * outdoor)
            if (result > max) result = max
            if (result < min) result = min
            printf "%.1f", result
        }
    ')
    
    # Fetch zones to find heating zones
    local zones
    zones=$(api_request "$account_index" GET "/api/v2/homes/$home_id/zones")
    if ! handle_curl_error; then
        return 1
    fi
    
    # Check if zones is a valid array and not empty
    if ! echo "$zones" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        return 0
    fi
    
    # Process each heating zone (using process substitution to avoid subshell)
    local zone_processed=false
    while IFS= read -r zone; do
        local zone_id=$(echo "$zone" | jq -r '.id')
        local zone_name=$(echo "$zone" | jq -r '.name')
        local zone_type=$(echo "$zone" | jq -r '.type')
        
        # Only process HEATING zones
        if [ "$zone_type" != "HEATING" ]; then
            continue
        fi
        
        # Get current zone state
        local zone_state
        zone_state=$(api_request "$account_index" GET "/api/v2/homes/$home_id/zones/$zone_id/state")
        if ! handle_curl_error; then
            continue
        fi
        
        # Check if heating is currently active
        local heating_power=$(echo "$zone_state" | jq -r '.activityDataPoints.heatingPower.percentage // 0')
        
        # Only adjust if heating is active (> 0%)
        # Use bc for floating point comparison if available, fallback to awk
        if command -v bc &> /dev/null && [ "$(echo "$heating_power > 0" | bc -l)" -eq 1 ]; then
            local is_heating=true
        elif awk -v power="$heating_power" 'BEGIN {exit !(power > 0)}'; then
            local is_heating=true
        else
            local is_heating=false
        fi
        
        if [ "$is_heating" = true ]; then
            log_message "🌡️ Account $account_index: $zone_name: Outdoor temp: ${outdoor_temp}°C, Target flow temp: ${target_flow_temp}°C"
            
            # Apply temperature optimization via zone overlay
            # NOTE: This sets the target room temperature. The actual flow temperature
            # is controlled by the Tado system's internal logic based on the room target.
            # Some newer Tado systems with X series thermostats support direct flow
            # temperature control, but the standard API overlay sets room temperature.
            # The weather compensation curve calculates an appropriate target that 
            # encourages the system to use lower flow temperatures when outdoor temps are higher.
            local overlay_data=$(jq -n \
                --arg temp "$target_flow_temp" \
                '{
                    "setting": {
                        "type": "HEATING",
                        "power": "ON",
                        "temperature": {
                            "celsius": ($temp | tonumber)
                        }
                    },
                    "termination": {
                        "type": "TADO_MODE"
                    }
                }')
            
            # Apply overlay to optimize heating
            local overlay_response
            overlay_response=$(api_request "$account_index" PUT "/api/v2/homes/$home_id/zones/$zone_id/overlay" "$overlay_data")
            if handle_curl_error; then
                log_message "✅ Account $account_index: $zone_name: Applied optimized heating settings."
                zone_processed=true
            fi
        fi
    done < <(echo "$zones" | jq -c '.[]')
    
    # Update last adjustment time if any zone was processed
    if [ "$zone_processed" = true ]; then
        LAST_FLOW_TEMP_ADJUSTMENT[$account_index]=$current_time
    fi
}

homeState() {
    local account_index=$1
    local home_id=${HOME_IDS[$account_index]}
    local current_time=$(date +%s)

    ensure_proxy_running "$account_index"

    local home_state_response
    home_state_response=$(api_request "$account_index" GET "/api/v2/homes/$home_id/state")
    handle_curl_error
    local home_state=$(echo "$home_state_response" | jq -r '.presence')

    local mobile_devices
    mobile_devices=$(api_request "$account_index" GET "/api/v2/homes/$home_id/mobileDevices")
    handle_curl_error

    # Check if mobile_devices is a valid array and not empty
    if echo "$mobile_devices" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        mapfile -t devices_home < <(echo "$mobile_devices" | jq -r '.[] | select(.settings.geoTrackingEnabled == true and .location.atHome == true) | .name')
        handle_curl_error
    else
        devices_home=()
    fi

    if [ "$ENABLE_GEOFENCING" == true ]; then
      log_message "🏠 Account $account_index: Geofencing enabled."
      local devices_str
      if [ ${#devices_home[@]} -gt 0 ] && [ "$home_state" == "HOME" ]; then
          devices_str=$(IFS=,; echo "${devices_home[*]}")
          log_message "🏠 Account $account_index: Home is in HOME Mode, the devices $devices_str are at home."
      elif [ ${#devices_home[@]} -eq 0 ] && [ "$home_state" == "AWAY" ]; then
          log_message "🚶 Account $account_index: Home is in AWAY Mode and there are no devices at home."
      elif [ ${#devices_home[@]} -eq 0 ] && [ "$home_state" == "HOME" ]; then
          log_message "🏠 Account $account_index: Home is in HOME Mode but there are no devices at home."
          api_request "$account_index" PUT "/api/v2/homes/$home_id/presenceLock" '{"homePresence": "AWAY"}'
          handle_curl_error
          log_message "Done! Activated AWAY mode for account $account_index."
      elif [ ${#devices_home[@]} -gt 0 ] && [ "$home_state" == "AWAY" ]; then
          devices_str=$(IFS=,; echo "${devices_home[*]}")
          log_message "🚶 Account $account_index: Home is in AWAY Mode but the devices $devices_str are at home."
          api_request "$account_index" PUT "/api/v2/homes/$home_id/presenceLock" '{"homePresence": "HOME"}'
          handle_curl_error
          log_message "Done! Activated HOME mode for account $account_index."
      fi
    else
      log_message "🏠 Account $account_index: Geofencing disabled."
    fi

    # Check zones for open windows
    local zones
    zones=$(api_request "$account_index" GET "/api/v2/homes/$home_id/zones")
    handle_curl_error

    # Check if zones is a valid array and not empty
    if echo "$zones" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        echo "$zones" | jq -c '.[]' | while read -r zone; do
            local zone_id=$(echo "$zone" | jq -r '.id')
            local zone_name=$(echo "$zone" | jq -r '.name')
            local open_window_detection_supported=$(echo "$zone" | jq -r '.openWindowDetection.supported')
            local open_window_detection_enabled=$(echo "$zone" | jq -r '.openWindowDetection.enabled')

        if [ "$open_window_detection_supported" = "false" ] || [ "$open_window_detection_enabled" = "false" ]; then
            continue
        fi

        local open_window_state
        open_window_state=$(api_request "$account_index" GET "/api/v2/homes/$home_id/zones/$zone_id/state")
        handle_curl_error
        local open_window_detected=$(echo "$open_window_state" | jq -r '.openWindowDetected')

            if [ "$open_window_detected" == "true" ]; then
                current_time=$(date +%s)

                # Check if the open window mode was recently activated and MAX_OPEN_WINDOW_DURATION is set
                if [ -n "${OPEN_WINDOW_ACTIVATION_TIMES[$zone_id]}" ] && [ -n "$MAX_OPEN_WINDOW_DURATION" ]; then
                    local activation_time=${OPEN_WINDOW_ACTIVATION_TIMES[$zone_id]}
                    local time_diff=$((current_time - activation_time))

                    if [ "$time_diff" -gt "$MAX_OPEN_WINDOW_DURATION" ]; then
                        log_message "❄️ Account $account_index: $zone_name: Open window detected for more than $MAX_OPEN_WINDOW_DURATION seconds. Cancelling open window mode."
                        # Cancel open window mode for the zone
                        api_request "$account_index" DELETE "/api/v2/homes/$home_id/zones/$zone_id/state/openWindow"
                        handle_curl_error
                        log_message "✅ Account $account_index: Cancelled open window mode for $zone_name."
                        unset "OPEN_WINDOW_ACTIVATION_TIMES[$zone_id]"
                        continue
                    fi
                fi

                log_message "❄️ Account $account_index: $zone_name: Open window detected, activating OpenWindow mode."
                # Set open window mode for the zone
                api_request "$account_index" POST "/api/v2/homes/$home_id/zones/$zone_id/state/openWindow/activate"
                handle_curl_error
                log_message "🌬️ Account $account_index: Activating open window mode for $zone_name."

                # Record the activation time
                OPEN_WINDOW_ACTIVATION_TIMES[$zone_id]=$current_time
            fi
        done
    fi

    # Optimize flow temperature if enabled
    optimize_flow_temperature "$account_index"

        log_message "⏳ Account $account_index: Waiting for a change in devices location or for an open window.."
    }

# Main execution loop
for (( i=1; i<=NUM_ACCOUNTS; i++ )); do
    CHECKING_INTERVAL_VAR="CHECKING_INTERVAL_$i"
    MAX_OPEN_WINDOW_DURATION_VAR="MAX_OPEN_WINDOW_DURATION_$i"
    ENABLE_GEOFENCING_VAR="ENABLE_GEOFENCING_$i"
    ENABLE_LOG_VAR="ENABLE_LOG_$i"
    LOG_FILE_VAR="LOG_FILE_$i"
    API_BASE_URL_VAR="TADO_API_BASE_URL_$i"
    ENABLE_FLOW_TEMP_OPTIMIZATION_VAR="ENABLE_FLOW_TEMP_OPTIMIZATION_$i"
    FLOW_TEMP_MIN_VAR="FLOW_TEMP_MIN_$i"
    FLOW_TEMP_MAX_VAR="FLOW_TEMP_MAX_$i"
    FLOW_TEMP_CURVE_SLOPE_VAR="FLOW_TEMP_CURVE_SLOPE_$i"

    # Fetch dynamic variables
    CHECKING_INTERVAL=${!CHECKING_INTERVAL_VAR:-15}
    MAX_OPEN_WINDOW_DURATION=${!MAX_OPEN_WINDOW_DURATION_VAR:-}
    ENABLE_GEOFENCING=${!ENABLE_GEOFENCING_VAR:-false}
    ENABLE_LOG=${!ENABLE_LOG_VAR:-false}
    LOG_FILE=${!LOG_FILE_VAR:-'/var/log/tado-assistant.log'}
    API_BASE_URL=${!API_BASE_URL_VAR:-${TADO_API_BASE_URL:-"http://localhost:8080"}}
    ENABLE_FLOW_TEMP_OPTIMIZATION=${!ENABLE_FLOW_TEMP_OPTIMIZATION_VAR:-false}
    FLOW_TEMP_MIN=${!FLOW_TEMP_MIN_VAR:-35}
    FLOW_TEMP_MAX=${!FLOW_TEMP_MAX_VAR:-75}
    FLOW_TEMP_CURVE_SLOPE=${!FLOW_TEMP_CURVE_SLOPE_VAR:-1.5}
    API_BASE_URL=$(normalize_base_url "$API_BASE_URL")
    API_BASE_URLS[$i]="$API_BASE_URL"

    init_account "$i"

    # Loop to monitor home state
    while true; do
        homeState "$i"
        sleep "$CHECKING_INTERVAL"
    done &
done

wait
