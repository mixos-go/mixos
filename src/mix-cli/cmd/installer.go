package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/spf13/cobra"
)

var installerCmd = &cobra.Command{
	Use:   "installer",
	Short: "Run the interactive MixOS installer",
	Long:  "Launch the system installer UI (if available in /usr/bin or PATH).",
	RunE: func(cmd *cobra.Command, args []string) error {
		// Prefer /usr/bin/mixos-install then look in PATH
		candidates := []string{"/usr/bin/mixos-install", "mixos-install"}
		var bin string
		for _, p := range candidates {
			if filepath.IsAbs(p) {
				if _, err := os.Stat(p); err == nil {
					bin = p
					break
				}
			} else {
				if fp, err := exec.LookPath(p); err == nil {
					bin = fp
					break
				}
			}
		}

		if bin == "" {
			return fmt.Errorf("installer binary not found; build and install 'mixos-installer' into /usr/bin or ensure it's in PATH")
		}

		// Execute installer, connecting stdio
		execCmd := exec.Command(bin)
		execCmd.Stdin = os.Stdin
		execCmd.Stdout = os.Stdout
		execCmd.Stderr = os.Stderr
		if err := execCmd.Run(); err != nil {
			return fmt.Errorf("failed to run installer: %w", err)
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(installerCmd)
}
