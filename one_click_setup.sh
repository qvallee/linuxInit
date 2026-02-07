#!/usr/bin/env bash
set -euo pipefail

LRZSZ_RPM_URL="https://rpmfind.net/linux/centos-stream/9-stream/BaseOS/x86_64/os/Packages/lrzsz-0.12.20-55.el9.x86_64.rpm"
SWAPFILE="/swapfile"
SWAP_SIZE_MB=4096
AMAZON_NTP_SERVER="169.254.169.123"
AMAZON_NTP_FQDN="time.aws.com"
CRON_TAG="# one_click_setup_time_sync"

log() {
  echo "[$(date '+%F %T')] $*"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "请使用 root 运行，或: sudo bash $0"
    exit 1
  fi
}

detect_pkg_mgr() {
  if command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
  else
    echo "未找到 dnf/yum，无法继续。"
    exit 1
  fi
}

install_base_packages() {
  log "1/5 安装基础包"
  "${PKG_MGR}" install -y gcc gcc-c++ autoconf automake wget bzip2 telnet git npm screen cronie crontabs
}

install_lrzsz() {
  log "2/5 安装 lrzsz"
  local rpm_file
  rpm_file="/tmp/$(basename "${LRZSZ_RPM_URL}")"

  if command -v rz >/dev/null 2>&1 && command -v sz >/dev/null 2>&1; then
    log "lrzsz 已安装，跳过。"
    return
  fi

  wget -O "${rpm_file}" "${LRZSZ_RPM_URL}"
  "${PKG_MGR}" install -y "${rpm_file}"
}

install_python_and_pip_packages() {
  log "3/5 安装 Python 与 pip 包"
  "${PKG_MGR}" install -y python3 python3-pip python3-devel
  python3 -m pip install httpx h2
}

ensure_swap_persistent() {
  log "4/5 增加 4G 交换分区并持久化"

  if swapon --show | awk '{print $1}' | grep -qx "${SWAPFILE}"; then
    log "${SWAPFILE} 已启用，检查持久化配置。"
  else
    if [[ ! -f "${SWAPFILE}" ]]; then
      log "创建 ${SWAPFILE} (${SWAP_SIZE_MB}MB)"
      if command -v fallocate >/dev/null 2>&1; then
        fallocate -l 4G "${SWAPFILE}"
      else
        dd if=/dev/zero of="${SWAPFILE}" bs=1M count="${SWAP_SIZE_MB}" status=progress
      fi
      chmod 600 "${SWAPFILE}"
      mkswap "${SWAPFILE}"
    else
      log "${SWAPFILE} 已存在，直接启用。"
      chmod 600 "${SWAPFILE}"
    fi

    swapon "${SWAPFILE}"
  fi

  if ! grep -Eq "^${SWAPFILE}[[:space:]]+none[[:space:]]+swap[[:space:]]+sw" /etc/fstab; then
    echo "${SWAPFILE} none swap sw 0 0" >> /etc/fstab
    log "已写入 /etc/fstab 持久化配置。"
  else
    log "/etc/fstab 已有 ${SWAPFILE} 配置，跳过。"
  fi

  log "当前 swap 状态："
  swapon --show || true
  free -h || true
}

configure_time_sync() {
  log "5/5 配置时间同步（Amazon NTP + 每小时第5分钟）"
  local chrony_conf="/etc/chrony.conf"
  local chronyc_bin
  local cron_line

  "${PKG_MGR}" install -y chrony
  "${PKG_MGR}" install -y cronie

  if [[ -f "${chrony_conf}" ]]; then
    cp -n "${chrony_conf}" "${chrony_conf}.bak" || true
    sed -i '/^[[:space:]]*server[[:space:]]\+/d' "${chrony_conf}"
    sed -i '/^[[:space:]]*pool[[:space:]]\+/d' "${chrony_conf}"
  else
    touch "${chrony_conf}"
  fi

  {
    echo "server ${AMAZON_NTP_SERVER} prefer iburst"
    echo "server ${AMAZON_NTP_FQDN} iburst"
  } >> "${chrony_conf}"

  systemctl enable --now chronyd
  systemctl restart chronyd
  systemctl enable --now crond || true

  chronyc_bin="$(command -v chronyc || true)"
  if [[ -z "${chronyc_bin}" ]]; then
    chronyc_bin="/usr/bin/chronyc"
  fi

  if ! command -v crontab >/dev/null 2>&1; then
    echo "未找到 crontab 命令（cronie 未正确安装），无法写入定时任务。"
    exit 1
  fi

  cron_line="5 * * * * ${chronyc_bin} -a makestep >/dev/null 2>&1 ${CRON_TAG}"
  (
    crontab -l 2>/dev/null | grep -vF "${CRON_TAG}" || true
    echo "${cron_line}"
  ) | crontab -

  "${chronyc_bin}" sources || true
  "${chronyc_bin}" tracking || true
}

main() {
  require_root
  detect_pkg_mgr
  install_base_packages
  install_lrzsz
  install_python_and_pip_packages
  ensure_swap_persistent
  configure_time_sync
  log "全部完成。"
}

main "$@"
