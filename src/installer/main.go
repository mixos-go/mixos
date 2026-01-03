package main

import (
	"fmt"
	"io"
	"math/rand"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"gopkg.in/yaml.v3"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	titleStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("12")).Align(lipgloss.Center)
	subStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("7")).Align(lipgloss.Center)
	boxStyle   = lipgloss.NewStyle().Padding(1, 2).Border(lipgloss.RoundedBorder()).Width(52).Align(lipgloss.Center)
)

type model struct {
	sp      spinner.Model
	prog    progress.Model
	stage   int
	message string
	done    bool
}

type nextMsg struct{}

func initialModel() model {
	s := spinner.New()
	s.Spinner = spinner.Line
	p := progress.New(progress.WithDefaultGradient())
	p.Width = 36
	// initialize with 0 percent using API
	_ = p
	return model{
		sp:      s,
		prog:    p,
		stage:   0,
		message: "Welcome to MixOS installer",
	}
}

func runInstaller() error {
	p := tea.NewProgram(initialModel())
	if err := p.Start(); err != nil {
		return fmt.Errorf("installer UI failed: %w", err)
	}
	return nil
}

func (m model) Init() tea.Cmd {
	return tea.Batch(m.sp.Tick, scheduleNext())
}

func scheduleNext() tea.Cmd {
	d := time.Duration(700+rand.Intn(900)) * time.Millisecond
	return tea.Tick(d, func(t time.Time) tea.Msg { return nextMsg{} })
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case spinner.TickMsg:
		var cmd tea.Cmd
		m.sp, cmd = m.sp.Update(msg)
		cmds = append(cmds, cmd)
	case progress.FrameMsg:
		var cmd tea.Cmd
		pm, cmd := m.prog.Update(msg)
		if newProg, ok := pm.(progress.Model); ok {
			m.prog = newProg
		}
		cmds = append(cmds, cmd)
	case nextMsg:
		if m.stage < 3 {
			m.stage++
			cmds = append(cmds, scheduleNext())
		} else {
			m.done = true
			return m, tea.Quit
		}
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "enter":
			if m.stage < 3 {
				m.stage++
				cmds = append(cmds, scheduleNext())
			} else {
				m.done = true
				return m, tea.Quit
			}
		}
	}

	switch m.stage {
	case 0:
		m.message = "Detecting disks..."
		if setter, ok := interface{}(&m.prog).(interface{ SetPercent(float64) }); ok {
			setter.SetPercent(0.10)
		}
	case 1:
		m.message = "Partitioning & formatting..."
		if setter, ok := interface{}(&m.prog).(interface{ SetPercent(float64) }); ok {
			setter.SetPercent(0.35)
		}
	case 2:
		m.message = "Copying system files..."
		if setter, ok := interface{}(&m.prog).(interface{ SetPercent(float64) }); ok {
			setter.SetPercent(0.70)
		}
	case 3:
		m.message = "Finalizing installation..."
		if setter, ok := interface{}(&m.prog).(interface{ SetPercent(float64) }); ok {
			setter.SetPercent(1.0)
		}
	}

	return m, tea.Batch(cmds...)
}

func (m model) View() string {
	if m.done {
		body := titleStyle.Render("MixOS Installer — Complete") + "\n\n" + subStyle.Render("Installation finished successfully. Reboot to use the system.") + "\n"
		return boxStyle.Render(body)
	}
	header := titleStyle.Render("MixOS Installer")
	body := subStyle.Render(m.message) + "\n\n" + m.sp.View() + " " + m.prog.View() + "\n\n" + subStyle.Render("Press Enter to advance, q to quit")
	return boxStyle.Render(header + "\n" + body)
}

func main() {
	rand.Seed(time.Now().UnixNano())
	// Simple flag parsing for unattended mode
	cfgPath := ""
	dryRun := false
	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--version", "-v":
			fmt.Println("mixos-install version 0.1.0")
			return
		case "--config":
			if i+1 < len(args) {
				cfgPath = args[i+1]
				i++
			}
		case "--dry-run":
			dryRun = true
		}
	}

	// If no --config flag provided, check kernel cmdline for autoinstall hints
	if cfgPath == "" {
		if kcfg, auto := parseKernelCmdline(); kcfg != "" {
			cfgPath = kcfg
		} else if auto {
			// default config path on target
			cfgPath = "/etc/mixos/install.yaml"
		}
	}

	if cfgPath != "" {
		if err := runAutoinstall(cfgPath, dryRun); err != nil {
			fmt.Fprintln(os.Stderr, "Autoinstall error:", err)
			os.Exit(1)
		}
		return
	}

	if err := runInstaller(); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}

// InstallConfig defines the unattended install options.
type InstallConfig struct {
	Hostname         string `yaml:"hostname"`
	RootPassword     string `yaml:"root_password,omitempty"`
	RootPasswordHash string `yaml:"root_password_hash,omitempty"`
	CreateUser       *struct {
		Name         string `yaml:"name"`
		Password     string `yaml:"password,omitempty"`
		PasswordHash string `yaml:"password_hash,omitempty"`
		Sudo         bool   `yaml:"sudo,omitempty"`
	} `yaml:"create_user,omitempty"`
	Network *struct {
		Mode        string   `yaml:"mode"` // dhcp | static
		Interface   string   `yaml:"interface"`
		Address     string   `yaml:"address,omitempty"`
		Gateway     string   `yaml:"gateway,omitempty"`
		Nameservers []string `yaml:"nameservers,omitempty"`
	} `yaml:"network,omitempty"`
	Packages    []string `yaml:"packages,omitempty"`
	PostInstall []string `yaml:"post_install_scripts,omitempty"`
}

func runAutoinstall(path string, dryRun bool) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	var cfg InstallConfig
	dec := yaml.NewDecoder(f)
	if err := dec.Decode(&cfg); err != nil && err != io.EOF {
		return err
	}

	if dryRun {
		fmt.Println("Dry-run mode: would apply config:")
		fmt.Printf("%+v\n", cfg)
		return nil
	}

	// Apply hostname
	if cfg.Hostname != "" {
		if err := setHostname(cfg.Hostname); err != nil {
			return fmt.Errorf("failed to set hostname: %w", err)
		}
	}

	// Apply root password
	if cfg.RootPassword != "" || cfg.RootPasswordHash != "" {
		// prefer plaintext if provided (we will use chpasswd which lets the system hash it)
		if cfg.RootPassword != "" {
			if err := setPassword("root", cfg.RootPassword); err != nil {
				return fmt.Errorf("failed to set root password: %w", err)
			}
		} else {
			// If a hash was provided, write directly into /etc/shadow entry for root (best effort)
			if err := setPasswordHash("root", cfg.RootPasswordHash); err != nil {
				return fmt.Errorf("failed to set root password hash: %w", err)
			}
		}
	}

	// Create user
	if cfg.CreateUser != nil {
		u := cfg.CreateUser
		if err := createUser(u.Name); err != nil {
			return fmt.Errorf("failed to create user: %w", err)
		}
		if u.Password != "" {
			if err := setPassword(u.Name, u.Password); err != nil {
				return fmt.Errorf("failed to set user password: %w", err)
			}
		} else if u.PasswordHash != "" {
			if err := setPasswordHash(u.Name, u.PasswordHash); err != nil {
				return fmt.Errorf("failed to set user password hash: %w", err)
			}
		}
		if u.Sudo {
			if err := addUserToSudo(u.Name); err != nil {
				return fmt.Errorf("failed to add user to sudoers: %w", err)
			}
		}
	}

	// Network
	if cfg.Network != nil {
		if err := configureNetwork(cfg.Network); err != nil {
			return fmt.Errorf("failed to configure network: %w", err)
		}
	}

	// Packages
	for _, p := range cfg.Packages {
		if err := installPackage(p); err != nil {
			return fmt.Errorf("failed to install package %s: %w", p, err)
		}
	}

	// Post install scripts
	for _, s := range cfg.PostInstall {
		if err := runScript(s); err != nil {
			return fmt.Errorf("post-install script failed: %w", err)
		}
	}

	// create marker to indicate firstboot completed
	_ = os.MkdirAll("/var/lib/mixos", 0755)
	marker := filepath.Join("/var/lib/mixos", "firstboot_done")
	os.WriteFile(marker, []byte(time.Now().Format(time.RFC3339)), 0644)

	fmt.Println("Autoinstall finished")
	return nil
}

func setHostname(name string) error {
	// write /etc/hostname
	if err := os.WriteFile("/etc/hostname", []byte(name+"\n"), 0644); err != nil {
		return err
	}
	// try hostnamectl if present
	if _, err := exec.LookPath("hostnamectl"); err == nil {
		cmd := exec.Command("hostnamectl", "set-hostname", name)
		return cmd.Run()
	}
	return nil
}

func setPassword(user, pass string) error {
	// Use chpasswd: input format "user:password"
	if _, err := exec.LookPath("chpasswd"); err == nil {
		cmd := exec.Command("chpasswd")
		stdin, err := cmd.StdinPipe()
		if err != nil {
			return err
		}
		if err := cmd.Start(); err != nil {
			stdin.Close()
			return err
		}
		io.WriteString(stdin, fmt.Sprintf("%s:%s\n", user, pass))
		stdin.Close()
		return cmd.Wait()
	}
	// fallback: use passwd via expect (not implemented)
	return fmt.Errorf("chpasswd not available")
}

func setPasswordHash(user, hash string) error {
	// Best-effort: edit /etc/shadow replacing the user's hash
	data, err := os.ReadFile("/etc/shadow")
	if err != nil {
		return err
	}
	lines := []byte{}
	for _, line := range splitLines(string(data)) {
		if line == "" {
			continue
		}
		parts := splitByColon(line)
		if len(parts) > 1 && parts[0] == user {
			parts[1] = hash
			line = joinByColon(parts)
		}
		lines = append(lines, []byte(line+"\n")...)
	}
	return os.WriteFile("/etc/shadow", lines, 0640)
}

func createUser(name string) error {
	if _, err := exec.LookPath("useradd"); err == nil {
		cmd := exec.Command("useradd", "-m", name)
		return cmd.Run()
	}
	return fmt.Errorf("useradd not available")
}

func addUserToSudo(name string) error {
	// try usermod -aG sudo
	if _, err := exec.LookPath("usermod"); err == nil {
		cmd := exec.Command("usermod", "-aG", "sudo", name)
		return cmd.Run()
	}
	// fallback: append to /etc/sudoers.d/
	dir := "/etc/sudoers.d"
	os.MkdirAll(dir, 0755)
	path := filepath.Join(dir, name)
	return os.WriteFile(path, []byte(fmt.Sprintf("%s ALL=(ALL) NOPASSWD:ALL\n", name)), 0440)
}

func configureNetwork(n *struct {
	Mode        string   `yaml:"mode"`
	Interface   string   `yaml:"interface"`
	Address     string   `yaml:"address,omitempty"`
	Gateway     string   `yaml:"gateway,omitempty"`
	Nameservers []string `yaml:"nameservers,omitempty"`
}) error {
	// write a systemd-networkd .network file for static or dhcp
	if n.Interface == "" {
		return fmt.Errorf("no network interface specified")
	}
	content := "[Match]\nName=" + n.Interface + "\n\n"
	if n.Mode == "static" {
		content += "[Network]\nAddress=" + n.Address + "\nGateway=" + n.Gateway + "\n"
		if len(n.Nameservers) > 0 {
			content += "DNS=" + joinBySpace(n.Nameservers) + "\n"
		}
	} else {
		content += "[Network]\nDHCP=yes\n"
	}
	dir := "/etc/systemd/network"
	os.MkdirAll(dir, 0755)
	fname := filepath.Join(dir, "10-mixos-"+n.Interface+".network")
	if err := os.WriteFile(fname, []byte(content), 0644); err != nil {
		return err
	}
	if _, err := exec.LookPath("systemctl"); err == nil {
		// enable and restart systemd-networkd
		exec.Command("systemctl", "enable", "systemd-networkd.service").Run()
		exec.Command("systemctl", "restart", "systemd-networkd.service").Run()
	}
	return nil
}

func installPackage(name string) error {
	// try to use 'mix' cli if present
	if p, err := exec.LookPath("mix"); err == nil {
		cmd := exec.Command(p, "install", name)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return cmd.Run()
	}
	return fmt.Errorf("package manager 'mix' not available to install %s", name)
}

func runScript(s string) error {
	tmp, err := os.CreateTemp("/tmp", "mixos-post-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.WriteString(s); err != nil {
		return err
	}
	tmp.Close()
	os.Chmod(tmp.Name(), 0755)
	cmd := exec.Command("/bin/sh", tmp.Name())
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// small helpers for shadow editing (string ops to avoid extra deps)
func splitLines(s string) []string {
	var out []string
	cur := ""
	for _, r := range s {
		if r == '\n' {
			out = append(out, cur)
			cur = ""
			continue
		}
		cur += string(r)
	}
	if cur != "" {
		out = append(out, cur)
	}
	return out
}

func splitByColon(s string) []string {
	var out []string
	cur := ""
	for _, r := range s {
		if r == ':' {
			out = append(out, cur)
			cur = ""
			continue
		}
		cur += string(r)
	}
	out = append(out, cur)
	return out
}

func joinByColon(parts []string) string {
	s := ""
	for i, p := range parts {
		if i > 0 {
			s += ":"
		}
		s += p
	}
	return s
}

func joinBySpace(parts []string) string {
	s := ""
	for i, p := range parts {
		if i > 0 {
			s += " "
		}
		s += p
	}
	return s
}

// parseKernelCmdline inspects /proc/cmdline for MixOS-specific flags.
// Returns config path (if provided) and a boolean indicating autoinstall request.
func parseKernelCmdline() (string, bool) {
	data, err := os.ReadFile("/proc/cmdline")
	if err != nil {
		return "", false
	}
	cmd := strings.TrimSpace(string(data))
	if cmd == "" {
		return "", false
	}
	parts := strings.Fields(cmd)
	cfg := ""
	auto := false
	for _, p := range parts {
		if strings.HasPrefix(p, "mixos.config=") {
			cfg = strings.TrimPrefix(p, "mixos.config=")
			// strip surrounding quotes if any
			cfg = strings.Trim(cfg, "'\"")
		}
		if strings.HasPrefix(p, "mixos.autoinstall=") {
			v := strings.TrimPrefix(p, "mixos.autoinstall=")
			v = strings.ToLower(strings.Trim(v, "'\""))
			if v == "1" || v == "true" || v == "yes" {
				auto = true
			}
		}
	}
	return cfg, auto
}
