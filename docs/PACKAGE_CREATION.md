# MixOS-GO Package Creation Guide

## Package Format

MixOS-GO packages use the `.mixpkg` format, which is a gzipped tarball containing:

```
package-version.mixpkg
├── metadata.json     # Required: Package metadata
├── files/            # Required: Files to install
│   ├── usr/
│   │   └── bin/
│   │       └── mybinary
│   └── etc/
│       └── myconfig
└── scripts/          # Optional: Install scripts
    ├── pre-install.sh
    └── post-install.sh
```

## metadata.json Schema

```json
{
  "name": "package-name",
  "version": "1.0.0",
  "description": "A brief description of the package",
  "dependencies": [
    "base-files",
    "openssl>=1.1"
  ],
  "files": [
    "/usr/bin/mybinary",
    "/etc/myconfig"
  ],
  "checksum": "sha256:abc123...",
  "pre_install": "#!/bin/sh\necho 'Pre-install script'",
  "post_install": "#!/bin/sh\necho 'Post-install script'",
  "pre_remove": "#!/bin/sh\necho 'Pre-remove script'",
  "post_remove": "#!/bin/sh\necho 'Post-remove script'"
}
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Package name (lowercase, alphanumeric, hyphens) |
| `version` | Yes | Semantic version (X.Y.Z) |
| `description` | Yes | Brief description |
| `dependencies` | No | List of required packages |
| `files` | Yes | List of installed files |
| `checksum` | No | SHA256 checksum of package |
| `pre_install` | No | Script to run before installation |
| `post_install` | No | Script to run after installation |
| `pre_remove` | No | Script to run before removal |
| `post_remove` | No | Script to run after removal |

### Dependency Syntax

```json
"dependencies": [
  "package",           // Any version
  "package>=1.0",      // Version 1.0 or higher
  "package<=2.0",      // Version 2.0 or lower
  "package=1.5.0"      // Exact version
]
```

## Creating a Package

### Step 1: Create Directory Structure

```bash
mkdir -p mypackage/{files,scripts}
cd mypackage
```

### Step 2: Add Files

```bash
# Create directory structure matching install paths
mkdir -p files/usr/bin
mkdir -p files/etc

# Add your files
cp /path/to/mybinary files/usr/bin/
cp /path/to/myconfig files/etc/
```

### Step 3: Create metadata.json

```bash
cat > metadata.json << 'EOF'
{
  "name": "mypackage",
  "version": "1.0.0",
  "description": "My awesome package",
  "dependencies": ["base-files"],
  "files": [
    "/usr/bin/mybinary",
    "/etc/myconfig"
  ]
}
EOF
```

### Step 4: Add Install Scripts (Optional)

```bash
# Pre-install script
cat > scripts/pre-install.sh << 'EOF'
#!/bin/sh
echo "Preparing to install mypackage..."
EOF

# Post-install script
cat > scripts/post-install.sh << 'EOF'
#!/bin/sh
echo "mypackage installed successfully!"
# Create required directories, set permissions, etc.
EOF
```

### Step 5: Build Package

```bash
# Create the package
tar -czf mypackage-1.0.0.mixpkg metadata.json files/

# Generate checksum
sha256sum mypackage-1.0.0.mixpkg
```

### Step 6: Test Package

```bash
# Copy to cache directory
cp mypackage-1.0.0.mixpkg /var/cache/mix/

# Update database
mix update

# Install
mix install mypackage

# Verify
mix info mypackage
mix info --files mypackage
```

## Build Script Template

Create a `build.sh` script for reproducible builds:

```bash
#!/bin/bash
set -e

PKG_NAME="mypackage"
PKG_VERSION="1.0.0"
PKG_DESC="My awesome package"
BUILD_DIR="${BUILD_DIR:-/tmp/mixos-build/packages/$PKG_NAME}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts/packages}"

echo "Building $PKG_NAME $PKG_VERSION..."

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/files"
mkdir -p "$OUTPUT_DIR"

cd "$BUILD_DIR"

# Download source (if needed)
# curl -L -o source.tar.gz "https://example.com/source.tar.gz"
# tar -xzf source.tar.gz

# Build (if needed)
# cd source-dir
# ./configure --prefix=/usr
# make
# make DESTDIR="$BUILD_DIR/files" install

# Or copy pre-built files
mkdir -p files/usr/bin
mkdir -p files/etc
# cp /path/to/binary files/usr/bin/
# cp /path/to/config files/etc/

# Create metadata
cat > metadata.json << EOF
{
  "name": "$PKG_NAME",
  "version": "$PKG_VERSION",
  "description": "$PKG_DESC",
  "dependencies": ["base-files"],
  "files": [
    "/usr/bin/mybinary",
    "/etc/myconfig"
  ]
}
EOF

# Create package
tar -czf "$OUTPUT_DIR/${PKG_NAME}-${PKG_VERSION}.mixpkg" metadata.json files/

echo "Package created: $OUTPUT_DIR/${PKG_NAME}-${PKG_VERSION}.mixpkg"
```

## Best Practices

### Naming Conventions

- Use lowercase letters, numbers, and hyphens
- Be descriptive but concise
- Follow upstream naming when possible

```
Good: nginx, openssh, python3, libssl
Bad: MyPackage, NGINX, open_ssh
```

### Version Numbers

Use semantic versioning (MAJOR.MINOR.PATCH):

- MAJOR: Breaking changes
- MINOR: New features, backward compatible
- PATCH: Bug fixes

### Dependencies

- List only direct dependencies
- Use version constraints when necessary
- Avoid circular dependencies

### File Placement

Follow the Filesystem Hierarchy Standard (FHS):

| Path | Contents |
|------|----------|
| `/usr/bin` | User commands |
| `/usr/sbin` | System admin commands |
| `/usr/lib` | Libraries |
| `/usr/share` | Architecture-independent data |
| `/etc` | Configuration files |
| `/var/lib` | Variable data |
| `/var/log` | Log files |

### Install Scripts

- Keep scripts simple and idempotent
- Handle errors gracefully
- Don't assume network access
- Use absolute paths

```bash
#!/bin/sh
# Good: Check before creating
[ -d /var/lib/myapp ] || mkdir -p /var/lib/myapp

# Good: Handle missing commands
command -v useradd >/dev/null && useradd -r myapp || true
```

### Security

- Don't include sensitive data in packages
- Set appropriate file permissions
- Validate inputs in scripts
- Use secure defaults in configs

## Example Packages

### Simple Binary Package

```bash
#!/bin/bash
set -e

PKG_NAME="hello"
PKG_VERSION="1.0.0"
BUILD_DIR="/tmp/build-hello"
OUTPUT_DIR="./artifacts/packages"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/files/usr/bin"
mkdir -p "$OUTPUT_DIR"

# Create simple binary
cat > "$BUILD_DIR/files/usr/bin/hello" << 'EOF'
#!/bin/sh
echo "Hello from MixOS-GO!"
EOF
chmod +x "$BUILD_DIR/files/usr/bin/hello"

# Create metadata
cat > "$BUILD_DIR/metadata.json" << EOF
{
  "name": "$PKG_NAME",
  "version": "$PKG_VERSION",
  "description": "Hello world program",
  "dependencies": [],
  "files": ["/usr/bin/hello"]
}
EOF

cd "$BUILD_DIR"
tar -czf "$OUTPUT_DIR/${PKG_NAME}-${PKG_VERSION}.mixpkg" metadata.json files/
```

### Service Package

```bash
#!/bin/bash
set -e

PKG_NAME="myservice"
PKG_VERSION="1.0.0"
BUILD_DIR="/tmp/build-myservice"
OUTPUT_DIR="./artifacts/packages"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/files"/{usr/sbin,etc/init.d,var/lib/myservice}
mkdir -p "$OUTPUT_DIR"

# Create service binary
cat > "$BUILD_DIR/files/usr/sbin/myserviced" << 'EOF'
#!/bin/sh
while true; do
    echo "$(date): Service running" >> /var/log/myservice.log
    sleep 60
done
EOF
chmod +x "$BUILD_DIR/files/usr/sbin/myserviced"

# Create init script
cat > "$BUILD_DIR/files/etc/init.d/myservice" << 'EOF'
#!/bin/sh
DAEMON=/usr/sbin/myserviced
PIDFILE=/var/run/myservice.pid

case "$1" in
    start)
        echo "Starting myservice..."
        start-stop-daemon -S -b -m -p $PIDFILE -x $DAEMON
        ;;
    stop)
        echo "Stopping myservice..."
        start-stop-daemon -K -p $PIDFILE
        rm -f $PIDFILE
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x "$BUILD_DIR/files/etc/init.d/myservice"

# Create metadata
cat > "$BUILD_DIR/metadata.json" << EOF
{
  "name": "$PKG_NAME",
  "version": "$PKG_VERSION",
  "description": "Example service daemon",
  "dependencies": ["base-files"],
  "files": [
    "/usr/sbin/myserviced",
    "/etc/init.d/myservice"
  ],
  "post_install": "#!/bin/sh\\nmkdir -p /var/lib/myservice\\ntouch /var/log/myservice.log"
}
EOF

cd "$BUILD_DIR"
tar -czf "$OUTPUT_DIR/${PKG_NAME}-${PKG_VERSION}.mixpkg" metadata.json files/
```

## Publishing Packages

### Local Repository

```bash
# Create repository directory
mkdir -p /var/www/repo/packages

# Copy packages
cp *.mixpkg /var/www/repo/packages/

# Generate index
cd /var/www/repo/packages
cat > ../index.json << EOF
[
  $(for pkg in *.mixpkg; do
    tar -xzf "$pkg" metadata.json -O
    echo ","
  done | sed '$ s/,$//')
]
EOF
```

### Configure mix to use repository

```bash
mix --repo http://myserver/repo install mypackage
```
