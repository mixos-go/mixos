package manager

import (
	"os"
	"path/filepath"
	"testing"
)

func TestNewManager(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "mix-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	dbPath := filepath.Join(tmpDir, "test.db")
	cacheDir := filepath.Join(tmpDir, "cache")

	mgr, err := New(dbPath, "http://localhost:8080", cacheDir)
	if err != nil {
		t.Fatalf("Failed to create manager: %v", err)
	}
	defer mgr.Close()

	if mgr == nil {
		t.Fatal("Manager is nil")
	}
}

func TestCompareVersions(t *testing.T) {
	tests := []struct {
		v1       string
		v2       string
		expected int
	}{
		{"1.0.0", "1.0.0", 0},
		{"1.0.1", "1.0.0", 1},
		{"1.0.0", "1.0.1", -1},
		{"2.0.0", "1.9.9", 1},
		{"1.10.0", "1.9.0", 1},
		{"1.0", "1.0.0", 0},
		{"1", "1.0.0", 0},
	}

	for _, tt := range tests {
		result := compareVersions(tt.v1, tt.v2)
		if result != tt.expected {
			t.Errorf("compareVersions(%s, %s) = %d, expected %d", tt.v1, tt.v2, result, tt.expected)
		}
	}
}

func TestIsInstalled(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "mix-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	dbPath := filepath.Join(tmpDir, "test.db")
	cacheDir := filepath.Join(tmpDir, "cache")

	mgr, err := New(dbPath, "http://localhost:8080", cacheDir)
	if err != nil {
		t.Fatalf("Failed to create manager: %v", err)
	}
	defer mgr.Close()

	// Test non-existent package
	installed, err := mgr.IsInstalled("nonexistent")
	if err != nil {
		t.Fatalf("IsInstalled failed: %v", err)
	}
	if installed {
		t.Error("Expected package to not be installed")
	}
}

func TestListInstalled(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "mix-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	dbPath := filepath.Join(tmpDir, "test.db")
	cacheDir := filepath.Join(tmpDir, "cache")

	mgr, err := New(dbPath, "http://localhost:8080", cacheDir)
	if err != nil {
		t.Fatalf("Failed to create manager: %v", err)
	}
	defer mgr.Close()

	packages, err := mgr.ListInstalled()
	if err != nil {
		t.Fatalf("ListInstalled failed: %v", err)
	}

	// Should be empty initially
	if len(packages) != 0 {
		t.Errorf("Expected 0 packages, got %d", len(packages))
	}
}

func TestSearch(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "mix-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	dbPath := filepath.Join(tmpDir, "test.db")
	cacheDir := filepath.Join(tmpDir, "cache")

	mgr, err := New(dbPath, "http://localhost:8080", cacheDir)
	if err != nil {
		t.Fatalf("Failed to create manager: %v", err)
	}
	defer mgr.Close()

	// Add a test package
	pkg := &PackageInfo{
		Name:        "test-package",
		Version:     "1.0.0",
		Description: "A test package for searching",
	}
	mgr.db.AddPackage(pkg)

	// Search for it
	results, err := mgr.Search("test", false)
	if err != nil {
		t.Fatalf("Search failed: %v", err)
	}

	if len(results) != 1 {
		t.Errorf("Expected 1 result, got %d", len(results))
	}

	if len(results) > 0 && results[0].Name != "test-package" {
		t.Errorf("Expected test-package, got %s", results[0].Name)
	}
}
