package cmd

import (
	"fmt"
	"strings"

	"github.com/mixos-go/src/mix-cli/pkg/manager"
	"github.com/spf13/cobra"
)

var searchCmd = &cobra.Command{
	Use:   "search [query]",
	Short: "Search for packages",
	Long:  `Search for packages by name or description.`,
	Args:  cobra.MinimumNArgs(1),
	RunE:  runSearch,
}

func init() {
	rootCmd.AddCommand(searchCmd)
	searchCmd.Flags().BoolP("installed", "i", false, "search only installed packages")
}

func runSearch(cmd *cobra.Command, args []string) error {
	installedOnly, _ := cmd.Flags().GetBool("installed")
	query := strings.Join(args, " ")

	mgr, err := manager.New(dbPath, repoURL, cacheDir)
	if err != nil {
		return fmt.Errorf("failed to initialize package manager: %w", err)
	}
	defer mgr.Close()

	results, err := mgr.Search(query, installedOnly)
	if err != nil {
		return fmt.Errorf("search failed: %w", err)
	}

	if len(results) == 0 {
		fmt.Printf("No packages found matching '%s'\n", query)
		return nil
	}

	fmt.Printf("Found %d package(s):\n\n", len(results))
	for _, pkg := range results {
		status := " "
		if pkg.Installed {
			status = "*"
		}
		fmt.Printf("[%s] %s (%s)\n", status, pkg.Name, pkg.Version)
		if pkg.Description != "" {
			fmt.Printf("    %s\n", pkg.Description)
		}
	}
	fmt.Println("\n[*] = installed")

	return nil
}
