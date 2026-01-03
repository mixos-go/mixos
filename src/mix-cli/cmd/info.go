package cmd

import (
	"fmt"
	"strings"

	"github.com/mixos-go/src/mix-cli/pkg/manager"
	"github.com/spf13/cobra"
)

var infoCmd = &cobra.Command{
	Use:   "info [package]",
	Short: "Show package information",
	Long:  `Display detailed information about a package.`,
	Args:  cobra.ExactArgs(1),
	RunE:  runInfo,
}

func init() {
	rootCmd.AddCommand(infoCmd)
	infoCmd.Flags().BoolP("files", "f", false, "list files installed by package")
}

func runInfo(cmd *cobra.Command, args []string) error {
	showFiles, _ := cmd.Flags().GetBool("files")
	pkgName := args[0]

	mgr, err := manager.New(dbPath, repoURL, cacheDir)
	if err != nil {
		return fmt.Errorf("failed to initialize package manager: %w", err)
	}
	defer mgr.Close()

	info, err := mgr.GetPackageInfo(pkgName)
	if err != nil {
		return fmt.Errorf("failed to get package info: %w", err)
	}

	fmt.Printf("Package: %s\n", info.Name)
	fmt.Printf("Version: %s\n", info.Version)
	fmt.Printf("Description: %s\n", info.Description)
	fmt.Printf("Size: %s\n", formatSize(info.Size))
	fmt.Printf("Installed: %v\n", info.Installed)

	if len(info.Dependencies) > 0 {
		fmt.Printf("Dependencies: %s\n", strings.Join(info.Dependencies, ", "))
	} else {
		fmt.Printf("Dependencies: none\n")
	}

	if info.Checksum != "" {
		fmt.Printf("Checksum: %s\n", info.Checksum)
	}

	if showFiles && info.Installed {
		files, err := mgr.GetPackageFiles(pkgName)
		if err != nil {
			return fmt.Errorf("failed to get package files: %w", err)
		}
		fmt.Printf("\nInstalled files (%d):\n", len(files))
		for _, f := range files {
			fmt.Printf("  %s\n", f)
		}
	}

	return nil
}

func formatSize(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}
