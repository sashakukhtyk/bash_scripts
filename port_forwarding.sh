#!/bin/bash

# Define necessary variables
LOCAL_USER=$(whoami)
REMOTE_HOST="x.x.x.x"
SSH_USER="sshfwd"
SSH_KEY_DIR="/etc/ssh/sshfwd"
LOCAL_SSH_KEY="$HOME/.ssh/sshfwd/id_ed25519_to_hostname"
REMOTE_SSH_KEY="$SSH_KEY_DIR/id_ed25519_to_hostname"
REMOTE_SSH_DIR="/etc/ssh/sshfwd"
AUTOSSH_CMD="/usr/bin/autossh"
SSHFS_CMD="sshfs"

# 1. Create system user on both local and remote hosts
create_user() {
    if ! id "$SSH_USER" &>/dev/null; then
        sudo useradd -r -s /bin/false "$SSH_USER"
    else
        echo "User $SSH_USER already exists."
    fi
    id "$SSH_USER"
}

# 2. Generate SSH key pair on local host
generate_ssh_keys() {
    mkdir -m 700 -p "$HOME/.ssh/sshfwd"
    ssh-keygen -t ed25519 -C "$SSH_USER@$LOCAL_USER" -f "$LOCAL_SSH_KEY" -q -N ''
    ls -la "$HOME/.ssh/sshfwd"
}

# 3. Copy SSH public key to remote host
copy_ssh_key_to_remote() {
    rsync "$LOCAL_SSH_KEY.pub" "$REMOTE_HOST:/tmp/"
    ssh "$REMOTE_HOST" <<EOF
mkdir -m 700 $REMOTE_SSH_DIR
mv /tmp/id_ed25519_to_hostname.pub $REMOTE_SSH_DIR/authorized_keys
chown -R $SSH_USER:$SSH_USER $REMOTE_SSH_DIR
EOF
}

# 4. Setup SSH config on local host for port forwarding
setup_ssh_config() {
    sudo mkdir -p /etc/ssh/ssh_config.d
    sudo tee /etc/ssh/ssh_config.d/sshfwd-to-hostname.conf > /dev/null <<EOF
Host sshfwd-to-hostname
    HostName $REMOTE_HOST
    IdentityFile $LOCAL_SSH_KEY
    User $SSH_USER
    Port 22
    RemoteForward $REMOTE_HOST:9200 127.0.0.1:9200
    StrictHostKeyChecking no
    Compression yes
EOF
}

# 5. Setup SSH configuration on the remote host
configure_remote_sshd() {
    ssh "$REMOTE_HOST" <<EOF
sudo bash -c 'echo -e "
Match User $SSH_USER
    AuthorizedKeysFile /etc/ssh/%u/authorized_keys
    MaxSessions 0
    GatewayPorts clientspecified
" >> /etc/ssh/sshd_config'
sudo systemctl restart sshd
EOF
}

# 6. Set up autossh for persistent SSH connection
setup_autossh_service() {
    sudo tee /etc/systemd/system/sshfwd-to-hostname.service > /dev/null <<EOF
[Unit]
Description=Forward ports to $REMOTE_HOST
After=network-online.target

[Service]
User=$SSH_USER
Environment=AUTOSSH_GATETIME=0
ExecStart=$AUTOSSH_CMD \
    -M 0 \
    -TN \
    -q \
    -o 'ServerAliveInterval 60' \
    -o 'ServerAliveCountMax 3' \
    sshfwd-to-hostname
ExecStop=/usr/bin/pkill -9 -u $SSH_USER
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable sshfwd-to-hostname.service
    sudo systemctl start sshfwd-to-hostname.service
}

# 7. Install SSHFS for mounting remote filesystems
install_sshfs() {
    sudo apt install -y sshfs
}

# 8. Set up SSHFS mount
setup_sshfs_mount() {
    sudo mkdir -p /mnt/home.network.com/user-downloads
    sudo tee /etc/systemd/system/mount-remote-fs.mount > /dev/null <<EOF
[Unit]
Description=Mount a remote directory to /mnt/home.network.com/user-downloads

[Mount]
What=$SSH_USER@$REMOTE_HOST:/home/$SSH_USER/Downloads
Where=/mnt/home.network.com/user-downloads
Type=fuse.sshfs
Options=_netdev, \
        allow_other, \
        port=22, \
        default_permissions, \
        IdentityFile=$REMOTE_SSH_KEY, \
        reconnect, \
        ServerAliveInterval=30, \
        ServerAliveCountMax=5, \
        x-systemd.automount, \
        uid=33, \
        gid=33
TimeoutSec=60

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable mount-remote-fs.mount
    sudo systemctl start mount-remote-fs.mount
}

# 9. Test the port forwarding setup
test_forwarding() {
    sudo -u "$SSH_USER" ssh sshfwd-to-hostname -fTN
}

# Run all functions in sequence
create_user
generate_ssh_keys
copy_ssh_key_to_remote
setup_ssh_config
configure_remote_sshd
setup_autossh_service
install_sshfs
setup_sshfs_mount
test_forwarding

echo "Setup completed successfully!"
