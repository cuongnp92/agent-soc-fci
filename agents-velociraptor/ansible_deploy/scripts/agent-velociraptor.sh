#!/usr/bin/env bash
#
# install_velociraptor_agent.sh
# Cài đặt Agent Velociraptor trên Linux (Debian-based) để thu thập log về SIEM
# Dựa theo tài liệu: Agent_Velociraptor_Linux.docx
#
# Cách dùng:
#   sudo ./install_velociraptor_agent.sh
#
# Có thể ghi đè các biến qua biến môi trường, ví dụ:
#   DEB_URL="https://.../file.deb" sudo -E ./install_velociraptor_agent.sh
#

set -euo pipefail

# ------------------------- Cấu hình -------------------------

# URL raw của file .deb trên GitHub (repo có thể là private -> cần token)
DEB_URL="${DEB_URL:-https://raw.githubusercontent.com/cuongnp92/agent-soc-fci/main/agents-velociraptor/velociraptor_client_0.76.3_amd64.deb}"

# Nếu repo GitHub là private, set GITHUB_TOKEN để xác thực khi tải file
# export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Server SIEM để kiểm tra kết nối trước khi cài (Private / Public)
PRIVATE_HOST="172.22.123.57"
PRIVATE_PORT="8000"
PUBLIC_HOST="192.223.12.200"
PUBLIC_PORT="8000"

# Tên service Velociraptor
SERVICE_NAME="velociraptor_client"

# Thư mục tạm để tải file .deb
WORK_DIR="$(mktemp -d)"
DEB_FILE="${WORK_DIR}/velociraptor_client_0.76.3_amd64.deb"

# ------------------------- Hàm tiện ích -------------------------

log()  { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        err "Script này cần chạy với quyền root. Hãy chạy lại với: sudo $0"
        exit 1
    fi
}

check_connectivity() {
    log "Kiểm tra kết nối tới SIEM server (Private/Public)..."

    local private_ok=0
    local public_ok=0

    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/${PRIVATE_HOST}/${PRIVATE_PORT}" 2>/dev/null; then
        log "  -> Kết nối Private (${PRIVATE_HOST}:${PRIVATE_PORT}): OK"
        private_ok=1
    else
        warn "  -> Kết nối Private (${PRIVATE_HOST}:${PRIVATE_PORT}): FAIL"
    fi

    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/${PUBLIC_HOST}/${PUBLIC_PORT}" 2>/dev/null; then
        log "  -> Kết nối Public (${PUBLIC_HOST}:${PUBLIC_PORT}): OK"
        public_ok=1
    else
        warn "  -> Kết nối Public (${PUBLIC_HOST}:${PUBLIC_PORT}): FAIL"
    fi

    if [[ "${private_ok}" -eq 0 && "${public_ok}" -eq 0 ]]; then
        err "Không kết nối được tới cả 2 endpoint SIEM."
        err "Hãy tạo ticket request yêu cầu đội FW mở kết nối trước khi tiếp tục."
        exit 1
    fi
}

download_package() {
    log "Tải file cài đặt từ GitHub..."

    local curl_auth_args=()
    if [[ -n "${GITHUB_TOKEN}" ]]; then
        curl_auth_args=(-H "Authorization: token ${GITHUB_TOKEN}")
    fi

    if ! curl -fSL "${curl_auth_args[@]}" -o "${DEB_FILE}" "${DEB_URL}"; then
        err "Tải file .deb thất bại. Nếu repo là private, hãy set biến GITHUB_TOKEN với Personal Access Token có quyền đọc repo."
        exit 1
    fi

    log "  -> Đã tải về: ${DEB_FILE} ($(du -h "${DEB_FILE}" | cut -f1))"
}

install_package() {
    log "Cài đặt gói .deb (dpkg -i)..."
    if ! dpkg -i "${DEB_FILE}"; then
        warn "dpkg báo lỗi phụ thuộc, thử fix bằng apt-get -f install..."
        apt-get -f install -y
    fi
    log "  -> Cài đặt hoàn tất."
}

check_service_status() {
    log "Kiểm tra trạng thái service (${SERVICE_NAME})..."

    if command -v systemctl >/dev/null 2>&1; then
        # Hệ thống dùng systemd
        if systemctl is-active --quiet "${SERVICE_NAME}"; then
            log "  -> Service đang chạy (active/running)."
        else
            warn "  -> Service không active, thử khởi động lại..."
            systemctl restart "${SERVICE_NAME}" || systemctl start "${SERVICE_NAME}"
            sleep 2
            if systemctl is-active --quiet "${SERVICE_NAME}"; then
                log "  -> Service đã chạy thành công sau khi khởi động lại."
            else
                err "  -> Service vẫn không chạy được. Liên hệ team SOC để hỗ trợ."
                systemctl status "${SERVICE_NAME}" --no-pager || true
                exit 1
            fi
        fi
    elif command -v service >/dev/null 2>&1; then
        # Hệ thống dùng SysVinit
        if service "${SERVICE_NAME}" status | grep -qi "running"; then
            log "  -> Service đang chạy."
        else
            warn "  -> Service không chạy, thử khởi động lại..."
            service "${SERVICE_NAME}" restart || service "${SERVICE_NAME}" start
            sleep 2
            if service "${SERVICE_NAME}" status | grep -qi "running"; then
                log "  -> Service đã chạy thành công sau khi khởi động lại."
            else
                err "  -> Service vẫn không chạy được. Liên hệ team SOC để hỗ trợ."
                exit 1
            fi
        fi
    else
        err "Không tìm thấy systemctl hoặc service. Không thể kiểm tra trạng thái service."
        exit 1
    fi
}

main() {
    require_root
    check_connectivity
    download_package
    install_package
    check_service_status
    log "Hoàn tất cài đặt Agent Velociraptor."
}

main "$@"
