package cmd

import (
	"fmt"

	"github.com/mixos-go/src/mix-cli/pkg/manager"
	"github.com/spf13/cobra"
)

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List installed packages",
	Long:  `List all installed packages with their versions.`,
	RunE:  runList,
}

func init() {
	rootCmd.AddCommand(listCmd)
	listCmd.Flags().BoolP("all", "a", false, "list all available packages")
}

func runList(cmd *cobra.Command, args []string) error {
	all, _ := cmd.Flags().GetBool("all")

	mgr, err := manager.New(dbPath, repoURL, cacheDir)
	if err != nil {
		return fmt.Errorf("failed to initialize package manager: %w", err)
	}
	defer mgr.Close()

	var packages []manager.PackageInfo
	if all {
		packages, err = mgr.ListAvailable()
	} else {
		packages, err = mgr.ListInstalled()
	}

	if err != nil {
		return fmt.Errorf("failed to list packages: %w", err)
	}

	if len(packages) == 0 {
		if all {
			fmt.Println("No packages available. Run 'mix update' to refresh the package database.")
		} else {
			fmt.Println("No packages installed.")
		}
		return nil
	}

	if all {
		fmt.Printf("Available packages (%d):\n\n", len(packages))
	} else {
		fmt.Printf("Installed packages (%d):\n\n", len(packages))
	}

	for _, pkg := range packages {
		status := ""
		if all && pkg.Installed {
			status = " [installed]"
		}
		fmt.Printf("  %-30s %s%s\n", pkg.Name, pkg.Version, status)
	}

	return nil
}
