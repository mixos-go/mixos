package cmd

import (
	"fmt"

	"github.com/mixos-go/mix-cli/pkg/manager"
	"github.com/spf13/cobra"
)

var installCmd = &cobra.Command{
	Use:   "install [packages...]",
	Short: "Install packages",
	Long:  `Install one or more packages with automatic dependency resolution.`,
	Args:  cobra.MinimumNArgs(1),
	RunE:  runInstall,
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

	// Install packages
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
