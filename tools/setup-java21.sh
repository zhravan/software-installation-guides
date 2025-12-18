#!/bin/bash

################################################################################
# Java 21 LTS Setup Script
# Cross-platform script to uninstall Java 11 and install Java 21 LTS
# Supports: macOS (Homebrew), Linux (apt/yum/dnf), Windows (WSL)
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Detect OS and architecture
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            OS="macos"
            ARCH=$(uname -m)
            ;;
        Linux*)
            OS="linux"
            ARCH=$(uname -m)
            # Check if WSL
            if grep -qi microsoft /proc/version 2>/dev/null; then
                OS="wsl"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            OS="windows"
            ARCH=$(uname -m)
            ;;
        *)
            OS="unknown"
            ;;
    esac
}

# Detect Linux distribution
detect_linux_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    else
        DISTRO="unknown"
    fi
}

# Print banner
print_banner() {
    echo ""
    echo "=========================================="
    echo "  Java 21 LTS Setup Script"
    echo "=========================================="
    echo -e "${BLUE}OS: $OS ($ARCH)${NC}"
    [ "$OS" = "linux" ] || [ "$OS" = "wsl" ] && echo -e "${BLUE}Distro: $DISTRO${NC}"
    echo "=========================================="
    echo ""
}

# Determine shell config file
get_shell_config() {
    if [ -n "$BASH_VERSION" ]; then
        if [ -f "$HOME/.bashrc" ]; then
            echo "$HOME/.bashrc"
        elif [ -f "$HOME/.bash_profile" ]; then
            echo "$HOME/.bash_profile"
        else
            echo "$HOME/.profile"
        fi
    elif [ -n "$ZSH_VERSION" ] || [ "$SHELL" = "/bin/zsh" ] || [ "$SHELL" = "/usr/bin/zsh" ]; then
        echo "$HOME/.zshrc"
    else
        # Default fallback
        if [ -f "$HOME/.zshrc" ]; then
            echo "$HOME/.zshrc"
        elif [ -f "$HOME/.bashrc" ]; then
            echo "$HOME/.bashrc"
        elif [ -f "$HOME/.bash_profile" ]; then
            echo "$HOME/.bash_profile"
        else
            echo "$HOME/.profile"
        fi
    fi
}

# macOS installation
install_macos() {
    echo -e "${YELLOW}Step 1: Checking Homebrew...${NC}"
    if ! command -v brew &> /dev/null; then
        echo -e "${YELLOW}Homebrew not found. Installing Homebrew...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add Homebrew to PATH for Apple Silicon
        if [ "$ARCH" = "arm64" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi
    echo -e "${GREEN}✓ Homebrew is ready${NC}"
    echo ""

    echo -e "${YELLOW}Step 2: Checking current Java installation...${NC}"
    java -version 2>&1 || echo "No Java currently in PATH"
    echo ""

    echo -e "${YELLOW}Step 3: Removing Java 11...${NC}"
    # Remove OpenJDK 11
    if brew list openjdk@11 &> /dev/null; then
        echo "Uninstalling openjdk@11..."
        brew uninstall --ignore-dependencies openjdk@11 || true
        echo -e "${GREEN}✓ openjdk@11 removed${NC}"
    fi

    # Check generic openjdk
    if brew list openjdk &> /dev/null; then
        OPENJDK_VERSION=$(brew info openjdk --json 2>/dev/null | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
        if [[ $OPENJDK_VERSION == 11.* ]]; then
            echo "Uninstalling generic openjdk (version 11)..."
            brew uninstall --ignore-dependencies openjdk || true
            echo -e "${GREEN}✓ openjdk removed${NC}"
        fi
    fi
    echo ""

    echo -e "${YELLOW}Step 4: Installing Java 21 LTS...${NC}"
    brew install openjdk@21
    echo -e "${GREEN}✓ OpenJDK 21 installed${NC}"
    echo ""

    echo -e "${YELLOW}Step 5: Configuring system Java...${NC}"
    # Create symlink for system Java wrappers
    sudo ln -sfn /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-21.jdk 2>/dev/null || \
    sudo ln -sfn /usr/local/opt/openjdk@21/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-21.jdk
    echo -e "${GREEN}✓ System symlink created${NC}"
    echo ""

    # Set Java paths based on architecture
    if [ "$ARCH" = "arm64" ]; then
        JAVA_HOME_PATH="/opt/homebrew/opt/openjdk@21"
    else
        JAVA_HOME_PATH="/usr/local/opt/openjdk@21"
    fi

    export JAVA_HOME="$JAVA_HOME_PATH"
    export PATH="$JAVA_HOME_PATH/bin:$PATH"
}

# Debian/Ubuntu installation
install_debian() {
    echo -e "${YELLOW}Step 1: Updating package list...${NC}"
    sudo apt-get update -qq
    echo ""

    echo -e "${YELLOW}Step 2: Removing Java 11...${NC}"
    sudo apt-get remove -y openjdk-11-* 2>/dev/null || true
    sudo apt-get autoremove -y 2>/dev/null || true
    echo -e "${GREEN}✓ Java 11 removed${NC}"
    echo ""

    echo -e "${YELLOW}Step 3: Installing Java 21 LTS...${NC}"
    sudo apt-get install -y openjdk-21-jdk
    echo -e "${GREEN}✓ OpenJDK 21 installed${NC}"
    echo ""

    # Set Java 21 as default
    sudo update-alternatives --set java /usr/lib/jvm/java-21-openjdk-*/bin/java 2>/dev/null || true
    sudo update-alternatives --set javac /usr/lib/jvm/java-21-openjdk-*/bin/javac 2>/dev/null || true

    export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
    export PATH="$JAVA_HOME/bin:$PATH"
}

# RHEL/CentOS/Fedora installation
install_redhat() {
    local PKG_MGR="yum"
    command -v dnf &> /dev/null && PKG_MGR="dnf"

    echo -e "${YELLOW}Step 1: Checking package manager...${NC}"
    echo "Using: $PKG_MGR"
    echo ""

    echo -e "${YELLOW}Step 2: Removing Java 11...${NC}"
    sudo $PKG_MGR remove -y java-11-openjdk* 2>/dev/null || true
    echo -e "${GREEN}✓ Java 11 removed${NC}"
    echo ""

    echo -e "${YELLOW}Step 3: Installing Java 21 LTS...${NC}"
    sudo $PKG_MGR install -y java-21-openjdk java-21-openjdk-devel
    echo -e "${GREEN}✓ OpenJDK 21 installed${NC}"
    echo ""

    # Set Java 21 as default
    sudo alternatives --set java /usr/lib/jvm/java-21-openjdk-*/bin/java 2>/dev/null || true
    sudo alternatives --set javac /usr/lib/jvm/java-21-openjdk-*/bin/javac 2>/dev/null || true

    export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
    export PATH="$JAVA_HOME/bin:$PATH"
}

# Update shell configuration
update_shell_config() {
    echo -e "${YELLOW}Step 6: Updating shell configuration...${NC}"

    SHELL_CONFIG=$(get_shell_config)

    if [ -f "$SHELL_CONFIG" ]; then
        # Create backup
        cp "$SHELL_CONFIG" "${SHELL_CONFIG}.backup_$(date +%Y%m%d_%H%M%S)"

        # Remove all old Java configurations
        sed -i.tmp '/openjdk@11/d' "$SHELL_CONFIG" 2>/dev/null || sed -i '' '/openjdk@11/d' "$SHELL_CONFIG" 2>/dev/null || true
        sed -i.tmp '/export JAVA_HOME.*openjdk/d' "$SHELL_CONFIG" 2>/dev/null || sed -i '' '/export JAVA_HOME.*openjdk/d' "$SHELL_CONFIG" 2>/dev/null || true
        sed -i.tmp '/export JAVA_HOME.*java-.*-openjdk/d' "$SHELL_CONFIG" 2>/dev/null || sed -i '' '/export JAVA_HOME.*java-.*-openjdk/d' "$SHELL_CONFIG" 2>/dev/null || true
        sed -i.tmp '/export PATH.*openjdk.*bin/d' "$SHELL_CONFIG" 2>/dev/null || sed -i '' '/export PATH.*openjdk.*bin/d' "$SHELL_CONFIG" 2>/dev/null || true
        sed -i.tmp '/# Java.*LTS/d' "$SHELL_CONFIG" 2>/dev/null || sed -i '' '/# Java.*LTS/d' "$SHELL_CONFIG" 2>/dev/null || true

        # Remove temporary files
        rm -f "${SHELL_CONFIG}.tmp" 2>/dev/null || true

        # Add new Java 21 configuration
        cat >> "$SHELL_CONFIG" << EOF

# Java 21 LTS
export JAVA_HOME="$JAVA_HOME"
export PATH="\$JAVA_HOME/bin:\$PATH"
EOF

        echo -e "${GREEN}✓ Updated $SHELL_CONFIG${NC}"
    else
        echo -e "${YELLOW}Creating $SHELL_CONFIG...${NC}"
        cat > "$SHELL_CONFIG" << EOF
# Java 21 LTS
export JAVA_HOME="$JAVA_HOME"
export PATH="\$JAVA_HOME/bin:\$PATH"
EOF
        echo -e "${GREEN}✓ Created $SHELL_CONFIG${NC}"
    fi
    echo ""
}

# Verify installation
verify_installation() {
    echo -e "${YELLOW}Step 7: Verifying installation...${NC}"
    echo ""

    echo -e "${BLUE}Java Version:${NC}"
    java -version 2>&1 | head -n 3
    echo ""

    echo -e "${BLUE}JAVA_HOME:${NC} $JAVA_HOME"
    echo ""

    # Check Maven if available
    if command -v mvn &> /dev/null; then
        echo -e "${BLUE}Maven Version:${NC}"
        mvn --version 2>&1 | head -n 3
        echo ""
    fi

    # Check Gradle if available
    if command -v gradle &> /dev/null; then
        echo -e "${BLUE}Gradle Version:${NC}"
        gradle --version 2>&1 | grep -E "Gradle|JVM" | head -n 2
        echo ""
    fi
}

# Print completion message
print_completion() {
    SHELL_CONFIG=$(get_shell_config)

    echo "=========================================="
    echo -e "${GREEN}✓ Installation Complete!${NC}"
    echo "=========================================="
    echo ""
    echo -e "${YELLOW}To apply changes immediately in your CURRENT terminal:${NC}"
    echo ""
    echo -e "${BLUE}export JAVA_HOME=\"$JAVA_HOME\"${NC}"
    echo -e "${BLUE}export PATH=\"\$JAVA_HOME/bin:\$PATH\"${NC}"
    echo ""
    echo -e "${YELLOW}OR simply open a new terminal window.${NC}"
    echo ""
    echo -e "Shell config updated: ${BLUE}$SHELL_CONFIG${NC}"
    echo ""
    echo "Verify with:"
    echo "  java -version"
    echo "  mvn --version"
    echo ""
}

################################################################################
# Main execution
################################################################################

main() {
    detect_os

    if [ "$OS" = "linux" ] || [ "$OS" = "wsl" ]; then
        detect_linux_distro
    fi

    print_banner

    case "$OS" in
        macos)
            install_macos
            ;;
        linux|wsl)
            case "$DISTRO" in
                ubuntu|debian|pop|linuxmint)
                    install_debian
                    ;;
                fedora|rhel|centos|rocky|alma)
                    install_redhat
                    ;;
                *)
                    echo -e "${RED}Unsupported Linux distribution: $DISTRO${NC}"
                    echo "Please install Java 21 manually from: https://adoptium.net/"
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo -e "${RED}Unsupported OS: $OS${NC}"
            echo "Please install Java 21 manually from: https://adoptium.net/"
            exit 1
            ;;
    esac

    update_shell_config
    verify_installation
    print_completion
}

# Run main function
main
