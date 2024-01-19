#!/bin/bash

# Source the environment variables if the file exists
[ -f /etc/tado-assistant.env ] && source /etc/tado-assistant.env

# Create log directory if it doesn't exist
LOG_DIR=$(dirname "$LOG_FILE")
mkdir -p "$LOG_DIR"

declare -A OPEN_WINDOW_ACTIVATION_TIMES TOKENS EXPIRY_TIMES HOME_IDS
LAST_MESSAGE="" # Used to prevent duplicate messages

# Reset the log file if it's older than 10 days
reset_log_if_needed() {
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi

    local max_age_days=10  # Max age in days (e.g., 10 days)
    local current_time
    local last_modified
    local age_days
    local timestamp
    local backup_log

     current_time=$(date +%s)
     last_modified=$(date -r "$LOG_FILE" +%s)
     age_days=$(( (current_time - last_modified) / 86400 ))

    if [ "$age_days" -ge "$max_age_days" ]; then
         timestamp=$(date '+%Y%m%d%H%M%S')
         backup_log="${LOG_FILE}.${timestamp}"
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

# Login function
login() {
    local account_index=$1
    local username_var=$2
    local password_var=$3
    local username=${!username_var}
    local password=${!password_var}
    local response expires_in token home_data home_id

    response=$(curl -s -X POST "https://auth.tado.com/oauth/token" \
        -d "client_id=public-api-preview&client_secret=4HJGRffVR8xb3XdEUQpjgZ1VplJi6Xgw&grant_type=password&password=$password&scope=home.user&username=$username")
    handle_curl_error

    token=$(echo "$response" | jq -r '.access_token')
    if [ "$token" == "null" ] || [ -z "$token" ]; then
        log_message "❌ Login error for account $account_index: Please check the username and password. Then restart the container or service."
        exit 1
    fi

    TOKENS[$account_index]=$token
    expires_in=$(echo "$response" | jq -r '.expires_in')
    EXPIRY_TIMES[$account_index]=$(($(date +%s) + expires_in - 60))

    home_data=$(curl -s -X GET "https://my.tado.com/api/v2/me" -H "Authorization: Bearer ${TOKENS[$account_index]}")
    handle_curl_error

    home_id=$(echo "$home_data" | jq -r '.homes[0].id')
    if [ -z "$home_id" ]; then
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

homeState() {
      local home_state mobile_devices devices_home devices_str zones zone_id zone_name home_id current_time account_index
      local open_window_detection_supported open_window_detection_enabled open_window_detected

     account_index=$1
     home_id=${HOME_IDS[$account_index]}
     current_time=$(date +%s)

    if [ -n "${EXPIRY_TIMES[$account_index]}" ] && [ "$current_time" -ge "${EXPIRY_TIMES[$account_index]}" ]; then
        login "$account_index" "TADO_USERNAME_$account_index" "TADO_PASSWORD_$account_index"
    fi

     home_state=$(curl -s -X GET "https://my.tado.com/api/v2/homes/$home_id/state" -H "Authorization: Bearer ${TOKENS[$account_index]}" | jq -r '.presence')
    handle_curl_error

     mobile_devices=$(curl -s -X GET "https://my.tado.com/api/v2/homes/$home_id/mobileDevices" -H "Authorization: Bearer ${TOKENS[$account_index]}")
    handle_curl_error

    mapfile -t devices_home < <(echo "$mobile_devices" | jq -r '.[] | select(.settings.geoTrackingEnabled == true and .location.atHome == true) | .name')
    handle_curl_error

    local devices_str
    if [ ${#devices_home[@]} -gt 0 ] && [ "$home_state" == "HOME" ]; then
        devices_str=$(IFS=,; echo "${devices_home[*]}")
        log_message "🏠 Account $account_index: Home is in HOME Mode, the devices $devices_str are at home."
    elif [ ${#devices_home[@]} -eq 0 ] && [ "$home_state" == "AWAY" ]; then
        log_message "🚶 Account $account_index: Home is in AWAY Mode and there are no devices at home."
    elif [ ${#devices_home[@]} -eq 0 ] && [ "$home_state" == "HOME" ]; then
        log_message "🏠 Account $account_index: Home is in HOME Mode but there are no devices at home."
        curl -s -X PUT "https://my.tado.com/api/v2/homes/$home_id/presenceLock" \
            -H "Authorization: Bearer ${TOKENS[$account_index]}" \
            -H "Content-Type: application/json" \
            -d '{"homePresence": "AWAY"}'
        handle_curl_error
        log_message "Done! Activated AWAY mode for account $account_index."
    elif [ ${#devices_home[@]} -gt 0 ] && [ "$home_state" == "AWAY" ]; then
        devices_str=$(IFS=,; echo "${devices_home[*]}")
        log_message "🚶 Account $account_index: Home is in AWAY Mode but the devices $devices_str are at home."
        curl -s -X PUT "https://my.tado.com/api/v2/homes/$home_id/presenceLock" \
            -H "Authorization: Bearer ${TOKENS[$account_index]}" \
            -H "Content-Type: application/json" \
            -d '{"homePresence": "HOME"}'
        handle_curl_error
        log_message "Done! Activated HOME mode for account $account_index."
    fi
      # Fetch zones for the home
         zones=$(curl -s -X GET "https://my.tado.com/api/v2/homes/$home_id/zones" -H "Authorization: Bearer ${TOKENS[$account_index]}")
        handle_curl_error

        echo "$zones" | jq -c '.[]' | while read -r zone; do
             zone_id=$(echo "$zone" | jq -r '.id')
             zone_name=$(echo "$zone" | jq -r '.name')

             open_window_detection_supported=$(echo "$zone" | jq -r '.openWindowDetection.supported')
            if [ "$open_window_detection_supported" = false ]; then
                continue
            fi

            open_window_detection_enabled=$(echo "$zone" | jq -r '.openWindowDetection.enabled')
            if [ "$open_window_detection_enabled" = false ]; then
                continue
            fi

            open_window_detected=$(curl -s -X GET "https://my.tado.com/api/v2/homes/$home_id/zones/$zone_id/state" -H "Authorization: Bearer ${TOKENS[$account_index]}" | jq -r '.openWindowDetected')
            handle_curl_error

            if [ "$open_window_detected" == "true" ]; then
                current_time=$(date +%s)

                # Check if the open window mode was recently activated and MAX_OPEN_WINDOW_DURATION is set
                if [ -n "${OPEN_WINDOW_ACTIVATION_TIMES[$zone_id]}" ] && [ -n "$MAX_OPEN_WINDOW_DURATION" ]; then
                    local activation_time=${OPEN_WINDOW_ACTIVATION_TIMES[$zone_id]}
                    local time_diff=$((current_time - activation_time))

                    if [ "$time_diff" -gt "$MAX_OPEN_WINDOW_DURATION" ]; then
                        log_message "❄️ Account $account_index: $zone_name: Open window detected for more than $MAX_OPEN_WINDOW_DURATION seconds. Cancelling open window mode."
                        # Cancel open window mode for the zone
                        curl -s -X DELETE "https://my.tado.com/api/v2/homes/$home_id/zones/$zone_id/state/openWindow" \
                            -H "Authorization: Bearer ${TOKENS[$account_index]}"
                        handle_curl_error
                        log_message "✅ Account $account_index: Cancelled open window mode for $zone_name."
                        unset "OPEN_WINDOW_ACTIVATION_TIMES[$zone_id]"
                        continue
                    fi
                fi

                log_message "❄️ Account $account_index: $zone_name: Open window detected, activating OpenWindow mode."
                # Set open window mode for the zone
                curl -s -X POST "https://my.tado.com/api/v2/homes/$home_id/zones/$zone_id/state/openWindow/activate" \
                    -H "Authorization: Bearer ${TOKENS[$account_index]}"
                handle_curl_error
                log_message "🌬️ Account $account_index: Activating open window mode for $zone_name."

                # Record the activation time
                OPEN_WINDOW_ACTIVATION_TIMES[$zone_id]=$current_time
            fi
        done

        log_message "⏳ Account $account_index: Waiting for a change in devices location or for an open window.."
    }

# Main execution loop
for (( i=1; i<=NUM_ACCOUNTS; i++ )); do
    USERNAME_VAR="TADO_USERNAME_$i"
    PASSWORD_VAR="TADO_PASSWORD_$i"
    CHECKING_INTERVAL_VAR="CHECKING_INTERVAL_$i"
    ENABLE_LOG_VAR="ENABLE_LOG_$i"
    LOG_FILE_VAR="LOG_FILE_$i"

    # Fetch dynamic variables
    CHECKING_INTERVAL=${!CHECKING_INTERVAL_VAR:-15}
    ENABLE_LOG=${!ENABLE_LOG_VAR:-false}
    LOG_FILE=${!LOG_FILE_VAR:-'/var/log/tado-assistant.log'}

    # Login and get the home ID
    login "$i" "$USERNAME_VAR" "$PASSWORD_VAR"

    # Loop to monitor home state
    while true; do
        homeState "$i"
        sleep "$CHECKING_INTERVAL"
    done
done