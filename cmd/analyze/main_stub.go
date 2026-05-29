//go:build !darwin

package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintln(os.Stderr, "磁盘分析仅支持 macOS")
	os.Exit(1)
}
