package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var (
	version   = "1.0.0"
	dbPath    = "/var/lib/mix/packages.db"
	repoURL   = "https://repo.mixos-go.org/packages"
	cacheDir  = "/var/cache/mix"
	verbose   bool
)

var rootCmd = &cobra.Command{
	Use:   "mix",
	Short: "MixOS-GO Package Manager",
	Long: `mix is the package manager for MixOS-GO.

It provides commands to install, remove, update, and search for packages.
Packages are distributed in the .mixpkg format with dependency resolution.`,
	Version: version,
}

func Execute() error {
	return rootCmd.Execute()
}

func init() {
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false, "verbose output")
	rootCmd.PersistentFlags().StringVar(&dbPath, "db", dbPath, "path to package database")
	rootCmd.PersistentFlags().StringVar(&repoURL, "repo", repoURL, "package repository URL")
	rootCmd.PersistentFlags().StringVar(&cacheDir, "cache", cacheDir, "package cache directory")

	// Ensure directories exist
	os.MkdirAll(cacheDir, 0755)
	os.MkdirAll("/var/lib/mix", 0755)
}

func printVerbose(format string, args ...interface{}) {
	if verbose {
		fmt.Printf(format, args...)
	}
}
