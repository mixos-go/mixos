package manager

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseDependency(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"package", "package"},
		{"package>=1.0", "package"},
		{"package<=2.0", "package"},
		{"package=1.5.0", "package"},
		{"package>1.0", "package"},
		{"package<2.0", "package"},
		{"  package  ", "package"},
		{"package>=1.0.0", "package"},
	}

	for _, tt := range tests {
		result := parseDependency(tt.input)
		if result != tt.expected {
			t.Errorf("parseDependency(%q) = %q, expected %q", tt.input, result, tt.expected)
		}
	}
}

func TestResolverSimple(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "mix-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	dbPath := filepath.Join(tmpDir, "test.db")
	db, err := NewDatabase(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer db.Close()

	// Add packages
	db.AddPackage(&PackageInfo{
		Name:         "base",
		Version:      "1.0.0",
		Dependencies: []string{},
	})
	db.AddPackage(&PackageInfo{
		Name:         "app",
		Version:      "1.0.0",
		Dependencies: []string{"base"},
	})

	resolver := NewResolver(db)
	order, err := resolver.Resolve([]string{"app"})
	if err != nil {
		t.Fatalf("Resolve failed: %v", err)
	}

	// Should install base before app
	if len(order) != 2 {
		t.Fatalf("Expected 2 packages, got %d", len(order))
	}

	if order[0] != "base" {
		t.Errorf("Expected base first, got %s", order[0])
	}
	if order[1] != "app" {
		t.Errorf("Expected app second, got %s", order[1])
	}
}

func TestResolverCircularDependency(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "mix-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	dbPath := filepath.Join(tmpDir, "test.db")
	db, err := NewDatabase(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer db.Close()

	// Add packages with circular dependency
	db.AddPackage(&PackageInfo{
		Name:         "a",
		Version:      "1.0.0",
		Dependencies: []string{"b"},
	})
	db.AddPackage(&PackageInfo{
		Name:         "b",
		Version:      "1.0.0",
		Dependencies: []string{"a"},
	})

	resolver := NewResolver(db)
	_, err = resolver.Resolve([]string{"a"})
	if err == nil {
		t.Error("Expected circular dependency error")
	}
}

func TestResolverAlreadyInstalled(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "mix-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	dbPath := filepath.Join(tmpDir, "test.db")
	db, err := NewDatabase(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer db.Close()

	// Add packages
	db.AddPackage(&PackageInfo{
		Name:         "base",
		Version:      "1.0.0",
		Dependencies: []string{},
	})
	db.AddPackage(&PackageInfo{
		Name:         "app",
		Version:      "1.0.0",
		Dependencies: []string{"base"},
	})

	// Mark base as installed
	db.RecordInstallation("base", "1.0.0", []string{})

	resolver := NewResolver(db)
	order, err := resolver.Resolve([]string{"app"})
	if err != nil {
		t.Fatalf("Resolve failed: %v", err)
	}

	// Should only install app (base already installed)
	if len(order) != 1 {
		t.Fatalf("Expected 1 package, got %d: %v", len(order), order)
	}

	if order[0] != "app" {
		t.Errorf("Expected app, got %s", order[0])
	}
}

func TestResolverDeepDependencies(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "mix-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	dbPath := filepath.Join(tmpDir, "test.db")
	db, err := NewDatabase(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer db.Close()

	// Add packages with deep dependency chain
	db.AddPackage(&PackageInfo{
		Name:         "level0",
		Version:      "1.0.0",
		Dependencies: []string{},
	})
	db.AddPackage(&PackageInfo{
		Name:         "level1",
		Version:      "1.0.0",
		Dependencies: []string{"level0"},
	})
	db.AddPackage(&PackageInfo{
		Name:         "level2",
		Version:      "1.0.0",
		Dependencies: []string{"level1"},
	})
	db.AddPackage(&PackageInfo{
		Name:         "level3",
		Version:      "1.0.0",
		Dependencies: []string{"level2"},
	})

	resolver := NewResolver(db)
	order, err := resolver.Resolve([]string{"level3"})
	if err != nil {
		t.Fatalf("Resolve failed: %v", err)
	}

	if len(order) != 4 {
		t.Fatalf("Expected 4 packages, got %d", len(order))
	}

	// Verify order
	expected := []string{"level0", "level1", "level2", "level3"}
	for i, pkg := range expected {
		if order[i] != pkg {
			t.Errorf("Position %d: expected %s, got %s", i, pkg, order[i])
		}
	}
}
