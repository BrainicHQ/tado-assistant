#!/bin/bash

# Source the environment variables
source /etc/tado-assistant.env
# Load settings from environment variables
USERNAME="${TADO_USERNAME}"
PASSWORD="${TADO_PASSWORD}"
CHECKING_INTERVAL="${CHECKING_INTERVAL:-15}"
ENABLE_LOG="${ENABLE_LOG:-false}"
LOG_FILE="${LOG_FILE:-/tado-assistant.log}"

declare -A OPEN_WINDOW_ACTIVATION_TIMES

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
    local response expires_in

    response=$(curl -s -X POST "https://auth.tado.com/oauth/token" \
        -d "client_id=public-api-preview&client_secret=4HJGRffVR8xb3XdEUQpjgZ1VplJi6Xgw&grant_type=password&password=$PASSWORD&scope=home.user&username=$USERNAME")
        handle_curl_error

    TOKEN=$(echo "$response" | jq -r '.access_token')
    if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
        log_message "Login error, check the username / password!"
        exit 1
    fi

    expires_in=$(echo "$response" | jq -r '.expires_in')
    EXPIRY_TIME=$(($(date +%s) + expires_in - 60))  # Subtracting 60 seconds as a buffer

    # Fetch the home ID
    HOME_DATA=$(curl -s -X GET "https://my.tado.com/api/v2/me" -H "Authorization: Bearer $TOKEN")
    handle_curl_error

    HOME_ID=$(echo "$HOME_DATA" | jq -r '.homes[0].id')
    if [ -z "$HOME_ID" ]; then
        log_message "Error fetching home ID!"
        exit 1
    fi
}

log_message() {
    local message="$1"
    if [ "$ENABLE_LOG" = true ] && [ "$LAST_MESSAGE" != "$message" ]; then
        echo "$(date '+%d-%m-%Y %H:%M:%S') # $message" >> "$LOG_FILE"
    fi
    echo "$(date '+%d-%m-%Y %H:%M:%S') # $message"
    LAST_MESSAGE="$message"
}

homeState() {
    local home_state mobile_devices devices_home devices_str zones zone_id zone_name

    current_time=$(date +%s)
    if [ "$current_time" -ge $EXPIRY_TIME ]; then
        login
        EXPIRY_TIME=$(($(date +%s) + $expires_in - 60))
    fi

    home_state=$(curl -s -X GET "https://my.tado.com/api/v2/homes/$HOME_ID/state" -H "Authorization: Bearer $TOKEN" | jq -r '.presence')
    handle_curl_error

    mobile_devices=$(curl -s -X GET "https://my.tado.com/api/v2/homes/$HOME_ID/mobileDevices" -H "Authorization: Bearer $TOKEN")
    handle_curl_error

    mapfile -t devices_home < <(echo "$mobile_devices" | jq -r '.[] | select(.settings.geoTrackingEnabled == true and .location.atHome == true) | .name')
    handle_curl_error

    if [ ${#devices_home[@]} -gt 0 ] && [ "$home_state" == "HOME" ]; then
        if [ ${#devices_home[@]} -eq 1 ]; then
            log_message "Your home is in HOME Mode, the device ${devices_home[0]} is at home."
        else
            devices_str=$(IFS=,; echo "${devices_home[*]}")
            log_message "Your home is in HOME Mode, the devices $devices_str are at home."
        fi
    elif [ ${#devices_home[@]} -eq 0 ] && [ "$home_state" == "AWAY" ]; then
        log_message "Your home is in AWAY Mode and there are no devices at home."
    elif [ ${#devices_home[@]} -eq 0 ] && [ "$home_state" == "HOME" ]; then
        log_message "Your home is in HOME Mode but there are no devices at home."
        log_message "Activating AWAY mode."
        curl -s -X PUT "https://my.tado.com/api/v2/homes/$HOME_ID/presenceLock" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"homePresence": "AWAY"}'
        log_message "Done!"
    elif [ ${#devices_home[@]} -gt 0 ] && [ "$home_state" == "AWAY" ]; then
        if [ ${#devices_home[@]} -eq 1 ]; then
            log_message "Your home is in AWAY Mode but the device ${devices_home[0]} is at home."
        else
            devices_str=$(IFS=,; echo "${devices_home[*]}")
            log_message "Your home is in AWAY Mode but the devices $devices_str are at home."
        fi
        log_message "Activating HOME mode."
        curl -s -X PUT "https://my.tado.com/api/v2/homes/$HOME_ID/presenceLock" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"homePresence": "HOME"}'
            handle_curl_error

        log_message "Done!"
    fi

    # Fetch zones for the home
    zones=$(curl -s -X GET "https://my.tado.com/api/v2/homes/$HOME_ID/zones" -H "Authorization: Bearer $TOKEN")
    handle_curl_error

# Check each zone for open windows
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

    open_window_detected=$(curl -s -X GET "https://my.tado.com/api/v2/homes/$HOME_ID/zones/$zone_id/state" -H "Authorization: Bearer $TOKEN" | jq -r '.openWindowDetected')
    handle_curl_error

    if [ "$open_window_detected" == "true" ]; then
        current_time=$(date +%s)

        # Check if the open window mode was recently activated and MAX_OPEN_WINDOW_DURATION is set
        if [ -n "${OPEN_WINDOW_ACTIVATION_TIMES[$zone_id]}" ] && [ -n "$MAX_OPEN_WINDOW_DURATION" ]; then
            activation_time=${OPEN_WINDOW_ACTIVATION_TIMES[$zone_id]}
            time_diff=$((current_time - activation_time))

            if [ "$time_diff" -gt "$MAX_OPEN_WINDOW_DURATION" ]; then
                log_message "$zone_name: Open window detected and activated for more than $MAX_OPEN_WINDOW_DURATION seconds. Cancelling open window mode."
                # Cancel open window mode for the zone
                curl -s -X DELETE "https://my.tado.com/api/v2/homes/$HOME_ID/zones/$zone_id/state/openWindow" \
                    -H "Authorization: Bearer $TOKEN"
                handle_curl_error
                log_message "Cancelled open window mode for $zone_name."
                unset "OPEN_WINDOW_ACTIVATION_TIMES[$zone_id]"
                continue
            fi
        fi

        log_message "$zone_name: open window detected, activating the OpenWindow mode."
        # Set open window mode for the zone
        curl -s -X POST "https://my.tado.com/api/v2/homes/$HOME_ID/zones/$zone_id/state/openWindow/activate" \
            -H "Authorization: Bearer $TOKEN"
        handle_curl_error
        log_message "Activating open window mode for $zone_name."

        # Record the activation time
        OPEN_WINDOW_ACTIVATION_TIMES[$zone_id]=$current_time
    fi
done

    log_message "Waiting for a change in devices location or for an open window.."
}

# Main execution
login
while true; do
    homeState
    sleep "$CHECKING_INTERVAL"
done