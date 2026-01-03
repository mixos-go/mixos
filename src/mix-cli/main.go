package main

import (
	"os"

	"github.com/mixos-go/src/mix-cli/cmd"
)

func main() {
	if err := cmd.Execute(); err != nil {
		os.Exit(1)
	}
}
