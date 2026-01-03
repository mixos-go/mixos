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

var updateCmd = &cobra.Command{
	Use:   "update",
	Short: "Update package database",
	Long:  `Synchronize the local package database with the remote repository.`,
	RunE:  runUpdate,
}

var upgradeCmd = &cobra.Command{
	Use:   "upgrade [packages...]",
	Short: "Upgrade packages",
	Long:  `Upgrade installed packages to their latest versions.`,
	RunE:  runUpgrade,
}

func init() {
	rootCmd.AddCommand(updateCmd)
	rootCmd.AddCommand(upgradeCmd)
	upgradeCmd.Flags().BoolP("yes", "y", false, "assume yes to all prompts")
}

func runUpdate(cmd *cobra.Command, args []string) error {
	mgr, err := manager.New(dbPath, repoURL, cacheDir)
	if err != nil {
		return fmt.Errorf("failed to initialize package manager: %w", err)
	}
	defer mgr.Close()

	fmt.Println("Updating package database...")
	if err := mgr.UpdateDatabase(); err != nil {
		return fmt.Errorf("failed to update database: %w", err)
	}

	fmt.Println("Package database updated successfully!")
	return nil
}

func runUpgrade(cmd *cobra.Command, args []string) error {
	yes, _ := cmd.Flags().GetBool("yes")

	mgr, err := manager.New(dbPath, repoURL, cacheDir)
	if err != nil {
		return fmt.Errorf("failed to initialize package manager: %w", err)
	}
	defer mgr.Close()

	// Get upgradable packages
	var toUpgrade []manager.PackageUpgrade
	var checkErr error

	if len(args) > 0 {
		// Upgrade specific packages
		for _, pkg := range args {
			upgrade, err := mgr.CheckUpgrade(pkg)
			if err != nil {
				fmt.Printf("Warning: %s: %v\n", pkg, err)
				continue
			}
			if upgrade != nil {
				toUpgrade = append(toUpgrade, *upgrade)
			}
		}
	} else {
		// Upgrade all packages
		toUpgrade, checkErr = mgr.GetUpgradablePackages()
		if checkErr != nil {
			return fmt.Errorf("failed to check for upgrades: %w", checkErr)
		}
	}

	if len(toUpgrade) == 0 {
		fmt.Println("All packages are up to date.")
		return nil
	}

	// Show what will be upgraded
	fmt.Printf("The following packages will be upgraded:\n")
	for _, pkg := range toUpgrade {
		fmt.Printf("  %s (%s -> %s)\n", pkg.Name, pkg.CurrentVersion, pkg.NewVersion)
	}
	fmt.Printf("\nTotal: %d package(s)\n", len(toUpgrade))

	// Confirm upgrade
	if !yes {
		fmt.Print("\nProceed with upgrade? [y/N] ")
		var response string
		fmt.Scanln(&response)
		if response != "y" && response != "Y" {
			fmt.Println("Upgrade cancelled.")
			return nil
		}
	}

	// Perform upgrades (TUI if terminal)
	if term.IsTerminal(int(os.Stdout.Fd())) {
		ch := make(chan manager.ProgressUpdate)
		errCh := make(chan error, 1)
		mgr.SetProgressChan(ch)

		go func() {
			for _, pkg := range toUpgrade {
				if err := mgr.Upgrade(pkg.Name); err != nil {
					errCh <- fmt.Errorf("failed to upgrade %s: %w", pkg.Name, err)
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
			for _, pkg := range toUpgrade {
				if err := mgr.Upgrade(pkg.Name); err != nil {
					return fmt.Errorf("failed to upgrade %s: %w", pkg.Name, err)
				}
				fmt.Printf("  ✓ %s upgraded to %s\n", pkg.Name, pkg.NewVersion)
			}
		}

		if err := <-errCh; err != nil {
			return err
		}

		fmt.Println("\nUpgrade complete!")
		return nil
	}

	// non-interactive upgrade
	for _, pkg := range toUpgrade {
		fmt.Printf("Upgrading %s...\n", pkg.Name)
		if err := mgr.Upgrade(pkg.Name); err != nil {
			return fmt.Errorf("failed to upgrade %s: %w", pkg.Name, err)
		}
		fmt.Printf("  ✓ %s upgraded to %s\n", pkg.Name, pkg.NewVersion)
	}

	fmt.Println("\nUpgrade complete!")
	return nil
}
