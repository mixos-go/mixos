package cmd

import (
	"fmt"
	"os"

	"github.com/mixos-go/src/mix-cli/pkg/manager"
	"github.com/spf13/cobra"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"golang.org/x/term"
)

var installCmd = &cobra.Command{
	Use:   "install [packages...]",
	Short: "Install packages",
	Long:  `Install one or more packages with automatic dependency resolution.`,
	Args:  cobra.MinimumNArgs(1),
	RunE:  runInstall,
}

// tuiModel is a Bubble Tea model used to render install progress.
type tuiModel struct {
	sp   spinner.Model
	prog progress.Model
	msg  string
	ch   <-chan manager.ProgressUpdate
}

func (m tuiModel) Init() tea.Cmd {
	return tea.Batch(m.sp.Tick, func() tea.Msg {
		for u := range m.ch {
			return u
		}
		return nil
	})
}

func (m tuiModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	switch msg := msg.(type) {
	case spinner.TickMsg:
		var c tea.Cmd
		m.sp, c = m.sp.Update(msg)
		cmd = c
	case progress.FrameMsg:
		var c tea.Cmd
		pm, c := m.prog.Update(msg)
		if newProg, ok := pm.(progress.Model); ok {
			m.prog = newProg
		}
		cmd = c
	case manager.ProgressUpdate:
		m.msg = msg.Message
		if setter, ok := interface{}(&m.prog).(interface{ SetPercent(float64) }); ok {
			setter.SetPercent(msg.Percent)
		}
		// schedule listening for next update
		return m, func() tea.Msg {
			for u := range m.ch {
				return u
			}
			return nil
		}
	case nil:
		// channel closed
		return m, tea.Quit
	}
	return m, cmd
}

func (m tuiModel) View() string {
	title := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("12")).Render("Mix Installer")
	body := lipgloss.NewStyle().Align(lipgloss.Center).Render(m.msg)
	return title + "\n\n" + m.sp.View() + " " + m.prog.View() + "\n\n" + body
}

func init() {
	rootCmd.AddCommand(installCmd)
	installCmd.Flags().BoolP("yes", "y", false, "assume yes to all prompts")
	installCmd.Flags().Bool("no-deps", false, "skip dependency resolution")
}

func runInstall(cmd *cobra.Command, args []string) error {
	yes, _ := cmd.Flags().GetBool("yes")
	noDeps, _ := cmd.Flags().GetBool("no-deps")

	mgr, err := manager.New(dbPath, repoURL, cacheDir)
	if err != nil {
		return fmt.Errorf("failed to initialize package manager: %w", err)
	}
	defer mgr.Close()

	// Resolve dependencies
	var toInstall []string
	if noDeps {
		toInstall = args
	} else {
		printVerbose("Resolving dependencies...\n")
		toInstall, err = mgr.ResolveDependencies(args)
		if err != nil {
			return fmt.Errorf("dependency resolution failed: %w", err)
		}
	}

	if len(toInstall) == 0 {
		fmt.Println("All packages are already installed.")
		return nil
	}

	// Show what will be installed
	fmt.Printf("The following packages will be installed:\n")
	for _, pkg := range toInstall {
		fmt.Printf("  %s\n", pkg)
	}
	fmt.Printf("\nTotal: %d package(s)\n", len(toInstall))

	// Confirm installation
	if !yes {
		fmt.Print("\nProceed with installation? [y/N] ")
		var response string
		fmt.Scanln(&response)
		if response != "y" && response != "Y" {
			fmt.Println("Installation cancelled.")
			return nil
		}
	}

	// If stdout is a terminal, run a TUI installer; otherwise run headless
	if term.IsTerminal(int(os.Stdout.Fd())) {
		// create progress channel
		ch := make(chan manager.ProgressUpdate)
		errCh := make(chan error, 1)
		mgr.SetProgressChan(ch)

		// start installation in goroutine
		go func() {
			for _, pkg := range toInstall {
				if err := mgr.Install(pkg); err != nil {
					errCh <- fmt.Errorf("failed to install %s: %w", pkg, err)
					close(ch)
					return
				}
			}
			close(ch)
			errCh <- nil
		}()

		// prepare spinner and progress and start tuiModel
		s := spinner.New()
		s.Spinner = spinner.Line
		pmod := progress.New(progress.WithDefaultGradient())
		pmod.Width = 40

		model := tuiModel{sp: s, prog: pmod, msg: "Starting...", ch: ch}
		prg := tea.NewProgram(model)

		// run TUI (blocking) while installations happen in goroutine
		if err := prg.Start(); err != nil {
			// fallback to headless if UI fails
			for _, pkg := range toInstall {
				if err := mgr.Install(pkg); err != nil {
					return fmt.Errorf("failed to install %s: %w", pkg, err)
				}
			}
		}

		// wait for install result
		if err := <-errCh; err != nil {
			return err
		}

		fmt.Println("\nInstallation complete!")
		return nil
	}

	// non-interactive install
	for _, pkg := range toInstall {
		fmt.Printf("Installing %s...\n", pkg)
		if err := mgr.Install(pkg); err != nil {
			return fmt.Errorf("failed to install %s: %w", pkg, err)
		}
		fmt.Printf("  ✓ %s installed successfully\n", pkg)
	}

	fmt.Println("\nInstallation complete!")
	return nil
}
