#!/bin/bash
# Container entrypoint (the image's CMD, exec'd by nvidia_entrypoint.sh).
#
# Two jobs: bring up sshd, and keep the container alive. The second is not
# optional -- when this script returns the container stops, which is what
# RunPod reports as "container is not running" when you try to SSH in.
#
# sshd is backgrounded rather than run as `exec sshd -D` on purpose: if sshd
# fails, the container stays up and remains reachable through RunPod's web
# terminal, which is where you would debug it from. For the same reason there
# is no `set -e` here -- no single step should be able to take the pod down.

set -u

log() { echo "[start] $*"; }

# Host keys are generated per container, never baked into the image: a shared
# host key in a published image lets anyone who pulls it impersonate this pod.
# -A only creates the key types that are missing, so restarts keep the same
# identity and your known_hosts stays valid.
setup_host_keys() {
    ssh-keygen -A
}

# RunPod injects the account's public keys as $PUBLIC_KEY, newline separated.
# Appended, not overwritten, so the key baked into the image survives; deduped
# so a pod restart doesn't grow the file.
setup_authorized_keys() {
    local keyfile=/root/.ssh/authorized_keys

    mkdir -p /root/.ssh
    touch "$keyfile"

    if [[ -n "${PUBLIC_KEY:-}" ]]; then
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            grep -qxF "$key" "$keyfile" && continue
            printf '%s\n' "$key" >> "$keyfile"
            log "authorized key added: $(awk '{print $1, $NF}' <<< "$key")"
        done <<< "$PUBLIC_KEY"
    else
        log "no \$PUBLIC_KEY in the environment; using the image's baked-in key only"
    fi

    chmod 700 /root/.ssh
    chmod 600 "$keyfile"
}

# sshd builds a fresh environment for every session, so nothing set via Docker
# ENV or injected by RunPod reaches an SSH login -- PATH would lose
# /usr/local/cargo/bin and /usr/local/cuda/bin, and cargo and nvcc would look
# like they aren't installed. Snapshot PID 1's environment to a file that
# /etc/profile.d and /root/.bashrc source (wired up in the Dockerfile).
#
# Session-scoped and shell-internal variables are skipped: re-exporting TERM or
# PWD into every shell actively breaks them. %q quoting keeps values with
# spaces or quotes intact.
export_environment() {
    local skip='^(PUBLIC_KEY|TERM|PWD|OLDPWD|SHLVL|HOME|USER|LOGNAME|MAIL|HOSTNAME|SSH_[A-Z_]+|_)='

    printenv | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' | grep -vE "$skip" | \
        while IFS='=' read -r name value; do
            printf 'export %s=%q\n' "$name" "$value"
        done > /etc/container_env.sh

    log "environment exported to /etc/container_env.sh"
}

start_sshd() {
    # Privilege separation directory: sshd refuses to start without it, and it
    # lives on tmpfs in some images.
    mkdir -p /run/sshd

    if ! /usr/sbin/sshd -t; then
        log "sshd config test failed, not starting sshd" >&2
        return 1
    fi

    # -e logs to stderr so failures land in `docker logs` / the RunPod log
    # pane, instead of a syslog that nothing is running to collect.
    /usr/sbin/sshd -e && log "sshd listening on port 22"
}

setup_host_keys
setup_authorized_keys
export_environment
start_sshd

log "container ready"

# Hold PID 1 open for the life of the container. Backgrounding the sleep and
# waiting on it (rather than a bare `sleep infinity`) lets bash run the trap
# immediately on SIGTERM, so `docker stop` and pod shutdowns don't sit through
# the 10s kill timeout.
trap 'log "shutting down"; exit 0' TERM INT
sleep infinity &
wait $!
