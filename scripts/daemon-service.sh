#!/usr/bin/env bash
set -euo pipefail

PLIST_NAME="com.blazeros.primesettler.plist"
SOURCE_PLIST="/Users/thagreat/BlazerOS/LaunchAgents/${PLIST_NAME}"
TARGET_DIR="${HOME}/Library/LaunchAgents"
TARGET_PLIST="${TARGET_DIR}/${PLIST_NAME}"
LOG_DIR="${HOME}/Library/Logs/BlazerOS"
LOG_FILE="${LOG_DIR}/primesettler.log"
BINARY="/Users/thagreat/BlazerOS/.build/out/Products/Release/ForwardTest"

mkdir -p "${TARGET_DIR}" "${LOG_DIR}"

action="${1:-status}"

case "$action" in
    install|start)
        echo "==> Building optimized release ForwardTest binary..."
        swift build -c release --target ForwardTest
        
        echo "==> Installing LaunchAgent to ${TARGET_PLIST}..."
        cp "${SOURCE_PLIST}" "${TARGET_PLIST}"
        
        echo "==> Loading background daemon with launchctl..."
        launchctl unload "${TARGET_PLIST}" 2>/dev/null || true
        launchctl load -w "${TARGET_PLIST}"
        
        sleep 1
        echo "==> Daemon loaded successfully!"
        echo "==> Tail logs with: $0 logs"
        echo "==> Check status with: $0 status"
        ;;
        
    stop)
        echo "==> Unloading background daemon..."
        launchctl unload "${TARGET_PLIST}" 2>/dev/null || true
        echo "==> Daemon stopped."
        ;;
        
    status)
        echo "=========================================================="
        echo "      BLAZEROS PRIME AUTO-SETTLER BACKGROUND DAEMON       "
        echo "=========================================================="
        if launchctl list | grep "com.blazeros.primesettler" >/dev/null 2>&1; then
            pid=$(launchctl list | grep "com.blazeros.primesettler" | awk '{print $1}')
            if [[ "$pid" == "-" || -z "$pid" ]]; then
                echo " Status: RUNNING (Managed by launchd)"
            else
                echo " Status: RUNNING (PID: ${pid})"
            fi
        else
            echo " Status: STOPPED"
        fi
        echo " Plist:  ${TARGET_PLIST}"
        echo " Logs:   ${LOG_FILE}"
        echo "----------------------------------------------------------"
        echo " Recent Log Activity:"
        if [[ -f "${LOG_FILE}" ]]; then
            tail -n 12 "${LOG_FILE}"
        else
            echo " (No log file generated yet)"
        fi
        echo "=========================================================="
        ;;
        
    logs)
        if [[ -f "${LOG_FILE}" ]]; then
            tail -f "${LOG_FILE}"
        else
            echo "Waiting for log file ${LOG_FILE}..."
            touch "${LOG_FILE}"
            tail -f "${LOG_FILE}"
        fi
        ;;
        
    *)
        echo "Usage: $0 {install|start|stop|status|logs}"
        exit 1
        ;;
esac
