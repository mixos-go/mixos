package cmd

import (
	"fmt"
	"os"

	"github.com/mixos-go/src/mix-cli/pkg/manager"
	"github.com/spf13/cobra"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"golang.org/x/term"
)

var removeCmd = &cobra.Command{
	Use:     "remove [packages...]",
	Aliases: []string{"uninstall", "rm"},
	Short:   "Remove packages",
	Long:    `Remove one or more installed packages.`,
	Args:    cobra.MinimumNArgs(1),
	RunE:    runRemove,
}

func init() {
	rootCmd.AddCommand(removeCmd)
	removeCmd.Flags().BoolP("yes", "y", false, "assume yes to all prompts")
	removeCmd.Flags().Bool("purge", false, "also remove configuration files")
}

func runRemove(cmd *cobra.Command, args []string) error {
	yes, _ := cmd.Flags().GetBool("yes")
	purge, _ := cmd.Flags().GetBool("purge")

	mgr, err := manager.New(dbPath, repoURL, cacheDir)
	if err != nil {
		return fmt.Errorf("failed to initialize package manager: %w", err)
	}
	defer mgr.Close()

	// Check which packages are installed
	var toRemove []string
	for _, pkg := range args {
		installed, err := mgr.IsInstalled(pkg)
		if err != nil {
			return fmt.Errorf("failed to check package status: %w", err)
		}
		if installed {
			toRemove = append(toRemove, pkg)
		} else {
			fmt.Printf("Package %s is not installed, skipping.\n", pkg)
		}
	}

	if len(toRemove) == 0 {
		fmt.Println("No packages to remove.")
		return nil
	}

	// Check for reverse dependencies
	for _, pkg := range toRemove {
		deps, err := mgr.GetReverseDependencies(pkg)
		if err != nil {
			return fmt.Errorf("failed to check reverse dependencies: %w", err)
		}
		if len(deps) > 0 {
			fmt.Printf("Warning: %s is required by: %v\n", pkg, deps)
		}
	}

	// Show what will be removed
	fmt.Printf("The following packages will be removed:\n")
	for _, pkg := range toRemove {
		fmt.Printf("  %s\n", pkg)
	}
	if purge {
		fmt.Println("  (configuration files will also be removed)")
	}
	fmt.Printf("\nTotal: %d package(s)\n", len(toRemove))

	// Confirm removal
	if !yes {
		fmt.Print("\nProceed with removal? [y/N] ")
		var response string
		fmt.Scanln(&response)
		if response != "y" && response != "Y" {
			fmt.Println("Removal cancelled.")
			return nil
		}
	}

	// If stdout is a terminal, run TUI remover; otherwise run headless
	if term.IsTerminal(int(os.Stdout.Fd())) {
		ch := make(chan manager.ProgressUpdate)
		errCh := make(chan error, 1)
		mgr.SetProgressChan(ch)

		go func() {
			for _, pkg := range toRemove {
				if err := mgr.Remove(pkg, purge); err != nil {
					errCh <- fmt.Errorf("failed to remove %s: %w", pkg, err)
					close(ch)
					return
				}
			}
			close(ch)
			errCh <- nil
		}()

		s := spinner.New()
		s.Spinner = spinner.Line
		pmod := progress.New(progress.WithDefaultGradient())
		pmod.Width = 40

		model := tuiModel{sp: s, prog: pmod, msg: "Starting...", ch: ch}
		prg := tea.NewProgram(model)

		if err := prg.Start(); err != nil {
			// fallback to headless if UI fails
			for _, pkg := range toRemove {
				if err := mgr.Remove(pkg, purge); err != nil {
					return fmt.Errorf("failed to remove %s: %w", pkg, err)
				}
			}
		}

		if err := <-errCh; err != nil {
			return err
		}

		fmt.Println("\nRemoval complete!")
		return nil
	}

	// non-interactive removal
	for _, pkg := range toRemove {
		fmt.Printf("Removing %s...\n", pkg)
		if err := mgr.Remove(pkg, purge); err != nil {
			return fmt.Errorf("failed to remove %s: %w", pkg, err)
		}
		fmt.Printf("  ✓ %s removed successfully\n", pkg)
	}

	fmt.Println("\nRemoval complete!")
	return nil
}
