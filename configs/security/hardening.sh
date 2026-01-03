#!/bin/bash
# MixOS-GO Security Hardening Script
# Applies security configurations to the rootfs

set -e

ROOTFS="${1:-/rootfs}"

echo "Applying security hardening to $ROOTFS..."

# Create sysctl security configuration
mkdir -p "$ROOTFS/etc/sysctl.d"
cat > "$ROOTFS/etc/sysctl.d/99-mixos-security.conf" << 'EOF'
# MixOS-GO Security Hardening - Sysctl Parameters

# Kernel hardening
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.printk = 3 3 3 3
kernel.unprivileged_bpf_disabled = 1
kernel.perf_event_paranoid = 3
kernel.yama.ptrace_scope = 2
kernel.kexec_load_disabled = 1
kernel.sysrq = 0
kernel.core_uses_pid = 1
kernel.randomize_va_space = 2

# Network hardening
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_timestamps = 0

# IPv6 hardening
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# File system hardening
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
fs.suid_dumpable = 0

# Memory hardening
vm.mmap_min_addr = 65536
vm.mmap_rnd_bits = 32
vm.mmap_rnd_compat_bits = 16
EOF

# Create default iptables rules (default deny)
mkdir -p "$ROOTFS/etc/iptables"
cat > "$ROOTFS/etc/iptables/rules.v4" << 'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Allow loopback
-A INPUT -i lo -j ACCEPT
-A OUTPUT -o lo -j ACCEPT

# Allow established connections
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH (rate limited)
-A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m limit --limit 3/min --limit-burst 3 -j ACCEPT

# Allow ICMP ping (rate limited)
-A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 4 -j ACCEPT

# Log dropped packets
-A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables-dropped: " --log-level 4

COMMIT
EOF

cat > "$ROOTFS/etc/iptables/rules.v6" << 'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Allow loopback
-A INPUT -i lo -j ACCEPT
-A OUTPUT -o lo -j ACCEPT

# Allow established connections
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH (rate limited)
-A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m limit --limit 3/min --limit-burst 3 -j ACCEPT

# Allow ICMPv6
-A INPUT -p ipv6-icmp -j ACCEPT

COMMIT
EOF

# Configure SSH for key-only authentication
mkdir -p "$ROOTFS/etc/ssh"
cat > "$ROOTFS/etc/ssh/sshd_config" << 'EOF'
# MixOS-GO SSH Server Configuration - Security Hardened

# Network
Port 22
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

# Protocol
Protocol 2

# Host keys
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Ciphers and algorithms
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,rsa-sha2-512,rsa-sha2-256

# Authentication
LoginGraceTime 30
PermitRootLogin prohibit-password
StrictModes yes
MaxAuthTries 3
MaxSessions 5
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM no

# Security
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
PrintMotd yes
PrintLastLog yes
TCPKeepAlive yes
PermitUserEnvironment no
ClientAliveInterval 300
ClientAliveCountMax 2
UseDNS no
PermitTunnel no
Banner /etc/ssh/banner

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Subsystems
Subsystem sftp /usr/lib/ssh/sftp-server -f AUTHPRIV -l INFO
EOF

# Create SSH banner
cat > "$ROOTFS/etc/ssh/banner" << 'EOF'
***************************************************************************
                            AUTHORIZED ACCESS ONLY
***************************************************************************
This system is for authorized users only. All activities are monitored and
logged. Unauthorized access attempts will be reported to law enforcement.
***************************************************************************
EOF

# Create secure /etc/passwd (no root password login)
cat > "$ROOTFS/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/sh
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
sys:x:3:3:sys:/dev:/usr/sbin/nologin
sync:x:4:65534:sync:/bin:/bin/sync
games:x:5:60:games:/usr/games:/usr/sbin/nologin
man:x:6:12:man:/var/cache/man:/usr/sbin/nologin
lp:x:7:7:lp:/var/spool/lpd:/usr/sbin/nologin
mail:x:8:8:mail:/var/mail:/usr/sbin/nologin
news:x:9:9:news:/var/spool/news:/usr/sbin/nologin
uucp:x:10:10:uucp:/var/spool/uucp:/usr/sbin/nologin
proxy:x:13:13:proxy:/bin:/usr/sbin/nologin
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
backup:x:34:34:backup:/var/backups:/usr/sbin/nologin
list:x:38:38:Mailing List Manager:/var/list:/usr/sbin/nologin
irc:x:39:39:ircd:/run/ircd:/usr/sbin/nologin
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
sshd:x:100:65534:sshd:/run/sshd:/usr/sbin/nologin
EOF

# Create /etc/shadow (locked root password - key auth only)
cat > "$ROOTFS/etc/shadow" << 'EOF'
root:!:19722:0:99999:7:::
daemon:*:19722:0:99999:7:::
bin:*:19722:0:99999:7:::
sys:*:19722:0:99999:7:::
sync:*:19722:0:99999:7:::
games:*:19722:0:99999:7:::
man:*:19722:0:99999:7:::
lp:*:19722:0:99999:7:::
mail:*:19722:0:99999:7:::
news:*:19722:0:99999:7:::
uucp:*:19722:0:99999:7:::
proxy:*:19722:0:99999:7:::
www-data:*:19722:0:99999:7:::
backup:*:19722:0:99999:7:::
list:*:19722:0:99999:7:::
irc:*:19722:0:99999:7:::
nobody:*:19722:0:99999:7:::
sshd:*:19722:0:99999:7:::
EOF

# Create /etc/group
cat > "$ROOTFS/etc/group" << 'EOF'
root:x:0:
daemon:x:1:
bin:x:2:
sys:x:3:
adm:x:4:
tty:x:5:
disk:x:6:
lp:x:7:
mail:x:8:
news:x:9:
uucp:x:10:
man:x:12:
proxy:x:13:
kmem:x:15:
dialout:x:20:
fax:x:21:
voice:x:22:
cdrom:x:24:
floppy:x:25:
tape:x:26:
sudo:x:27:
audio:x:29:
dip:x:30:
www-data:x:33:
backup:x:34:
operator:x:37:
list:x:38:
irc:x:39:
src:x:40:
shadow:x:42:
utmp:x:43:
video:x:44:
sasl:x:45:
plugdev:x:46:
staff:x:50:
games:x:60:
users:x:100:
nogroup:x:65534:
EOF

# Set secure permissions
chmod 600 "$ROOTFS/etc/shadow"
chmod 644 "$ROOTFS/etc/passwd"
chmod 644 "$ROOTFS/etc/group"
chmod 600 "$ROOTFS/etc/ssh/sshd_config"
chmod 644 "$ROOTFS/etc/ssh/banner"

# Create secure /etc/securetty (restrict root login to console)
cat > "$ROOTFS/etc/securetty" << 'EOF'
console
tty1
ttyS0
EOF
chmod 600 "$ROOTFS/etc/securetty"


# Create /etc/hosts.deny and /etc/hosts.allow
cat > "$ROOTFS/etc/hosts.deny" << 'EOF'
# Deny all by default
ALL: ALL
EOF

cat > "$ROOTFS/etc/hosts.allow" << 'EOF'
# Allow SSH from anywhere (firewall handles rate limiting)
sshd: ALL
EOF

# Create login.defs with secure defaults
cat > "$ROOTFS/etc/login.defs" << 'EOF'
# MixOS-GO Login Definitions

MAIL_DIR        /var/mail
FAILLOG_ENAB    yes
LOG_UNKFAIL_ENAB    no
LOG_OK_LOGINS   yes
SYSLOG_SU_ENAB  yes
SYSLOG_SG_ENAB  yes
FTMP_FILE       /var/log/btmp
SU_NAME         su
HUSHLOGIN_FILE  .hushlogin
ENV_SUPATH      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV_PATH        PATH=/usr/local/bin:/usr/bin:/bin
TTYGROUP        tty
TTYPERM         0600
ERASECHAR       0177
KILLCHAR        025
UMASK           027
PASS_MAX_DAYS   90
PASS_MIN_DAYS   7
PASS_WARN_AGE   14
UID_MIN         1000
UID_MAX         60000
GID_MIN         1000
GID_MAX         60000
LOGIN_RETRIES   3
LOGIN_TIMEOUT   60
CHFN_RESTRICT   rwh
DEFAULT_HOME    no
USERGROUPS_ENAB yes
ENCRYPT_METHOD  SHA512
SHA_CRYPT_MIN_ROUNDS    5000
SHA_CRYPT_MAX_ROUNDS    10000
EOF

# Create /etc/profile.d/security.sh
mkdir -p "$ROOTFS/etc/profile.d"
cat > "$ROOTFS/etc/profile.d/security.sh" << 'EOF'
# Security settings for all users
umask 027
export HISTSIZE=1000
export HISTFILESIZE=2000
export HISTCONTROL=ignoredups:ignorespace
export HISTTIMEFORMAT="%F %T "
readonly HISTFILE
EOF

# Create audit rules directory
mkdir -p "$ROOTFS/etc/audit/rules.d"
cat > "$ROOTFS/etc/audit/rules.d/mixos.rules" << 'EOF'
# MixOS-GO Audit Rules

# Delete all existing rules
-D

# Set buffer size
-b 8192

# Failure mode (1=printk, 2=panic)
-f 1

# Monitor file access
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd

# Monitor privileged commands
-a always,exit -F path=/usr/bin/sudo -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged
-a always,exit -F path=/usr/bin/su -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged

# Monitor network configuration changes
-w /etc/hosts -p wa -k network
-w /etc/network/ -p wa -k network

# Monitor kernel module loading
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
EOF

echo "Security hardening applied successfully!"
