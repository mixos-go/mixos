package manager

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type Manager struct {
	db       *Database
	repoURL  string
	cacheDir string
	// optional progress channel for UI consumers
	progressChan chan<- ProgressUpdate
}

// ProgressUpdate represents a status update emitted by Manager operations.
type ProgressUpdate struct {
	Stage   string  // e.g. download, verify, extract, install
	Percent float64 // 0.0 - 1.0
	Message string  // human readable message
}

type PackageInfo struct {
	Name         string   `json:"name"`
	Version      string   `json:"version"`
	Description  string   `json:"description"`
	Dependencies []string `json:"dependencies"`
	Files        []string `json:"files"`
	Checksum     string   `json:"checksum"`
	Size         int64    `json:"size"`
	Installed    bool     `json:"-"`
	PreRemove    string   `json:"pre_remove,omitempty"`
	PostRemove   string   `json:"post_remove,omitempty"`
}

type PackageUpgrade struct {
	Name           string
	CurrentVersion string
	NewVersion     string
}

type SearchResult struct {
	Name        string
	Version     string
	Description string
	Installed   bool
}

type PackageMetadata struct {
	Name         string   `json:"name"`
	Version      string   `json:"version"`
	Description  string   `json:"description"`
	Dependencies []string `json:"dependencies"`
	Files        []string `json:"files"`
	Checksum     string   `json:"checksum"`
	PreInstall   string   `json:"pre_install,omitempty"`
	PostInstall  string   `json:"post_install,omitempty"`
	PreRemove    string   `json:"pre_remove,omitempty"`
	PostRemove   string   `json:"post_remove,omitempty"`
}

func New(dbPath, repoURL, cacheDir string) (*Manager, error) {
	db, err := NewDatabase(dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	return &Manager{
		db:       db,
		repoURL:  repoURL,
		cacheDir: cacheDir,
	}, nil
}

// SetProgressChan registers a channel to receive ProgressUpdate events.
// Pass nil to disable progress reporting.
func (m *Manager) SetProgressChan(ch chan<- ProgressUpdate) {
	m.progressChan = ch
}

func (m *Manager) Close() error {
	return m.db.Close()
}

func (m *Manager) Install(pkgName string) error {
	// Check if already installed
	installed, err := m.IsInstalled(pkgName)
	if err != nil {
		return err
	}
	if installed {
		return fmt.Errorf("package %s is already installed", pkgName)
	}

	// Get package info from database
	info, err := m.db.GetPackage(pkgName)
	if err != nil {
		return fmt.Errorf("package %s not found in database", pkgName)
	}

	// Download package
	if m.progressChan != nil {
		m.progressChan <- ProgressUpdate{Stage: "start", Percent: 0.0, Message: "Starting installation"}
	}
	pkgPath, err := m.downloadPackage(pkgName, info.Version)
	if err != nil {
		return fmt.Errorf("failed to download package: %w", err)
	}

	// Verify checksum
	if info.Checksum != "" {
		if m.progressChan != nil {
			m.progressChan <- ProgressUpdate{Stage: "verify", Percent: 0.25, Message: "Verifying checksum"}
		}
		if err := m.verifyChecksum(pkgPath, info.Checksum); err != nil {
			os.Remove(pkgPath)
			return fmt.Errorf("checksum verification failed: %w", err)
		}
	}

	// Extract and install package
	if m.progressChan != nil {
		m.progressChan <- ProgressUpdate{Stage: "extract", Percent: 0.5, Message: "Extracting package"}
	}
	metadata, err := m.extractPackage(pkgPath)
	if err != nil {
		return fmt.Errorf("failed to extract package: %w", err)
	}

	// Run pre-install script
	if metadata.PreInstall != "" {
		if err := m.runScript(metadata.PreInstall, "pre-install"); err != nil {
			return fmt.Errorf("pre-install script failed: %w", err)
		}
	}

	// Install files
	if m.progressChan != nil {
		m.progressChan <- ProgressUpdate{Stage: "install", Percent: 0.75, Message: "Installing files"}
	}
	installedFiles, err := m.installFiles(pkgPath)
	if err != nil {
		return fmt.Errorf("failed to install files: %w", err)
	}

	// Run post-install script
	if metadata.PostInstall != "" {
		if err := m.runScript(metadata.PostInstall, "post-install"); err != nil {
			// Rollback on failure
			m.removeFiles(installedFiles)
			return fmt.Errorf("post-install script failed: %w", err)
		}
	}

	// Record installation in database
	if err := m.db.RecordInstallation(pkgName, info.Version, installedFiles); err != nil {
		return fmt.Errorf("failed to record installation: %w", err)
	}

	if m.progressChan != nil {
		m.progressChan <- ProgressUpdate{Stage: "done", Percent: 1.0, Message: "Installation complete"}
	}

	return nil
}

func (m *Manager) Remove(pkgName string, purge bool) error {
	// Check if installed
	installed, err := m.IsInstalled(pkgName)
	if err != nil {
		return err
	}
	if !installed {
		return fmt.Errorf("package %s is not installed", pkgName)
	}

	// Get installed files
	files, err := m.db.GetInstalledFiles(pkgName)
	if err != nil {
		return fmt.Errorf("failed to get installed files: %w", err)
	}

	// Get package metadata for scripts
	info, _ := m.db.GetInstalledPackage(pkgName)

	// Emit start
	if m.progressChan != nil {
		m.progressChan <- ProgressUpdate{Stage: "start", Percent: 0.0, Message: "Starting removal"}
	}

	// Run pre-remove script if available
	if info != nil && info.PreRemove != "" {
		if m.progressChan != nil {
			m.progressChan <- ProgressUpdate{Stage: "pre-remove", Percent: 0.1, Message: "Running pre-remove script"}
		}
		if err := m.runScript(info.PreRemove, "pre-remove"); err != nil {
			return fmt.Errorf("pre-remove script failed: %w", err)
		}
	}

	// Remove files
	if m.progressChan != nil {
		m.progressChan <- ProgressUpdate{Stage: "remove-files", Percent: 0.5, Message: "Removing files"}
	}
	if err := m.removeFiles(files); err != nil {
		return fmt.Errorf("failed to remove files: %w", err)
	}

	// Run post-remove script if available
	if info != nil && info.PostRemove != "" {
		if m.progressChan != nil {
			m.progressChan <- ProgressUpdate{Stage: "post-remove", Percent: 0.8, Message: "Running post-remove script"}
		}
		if err := m.runScript(info.PostRemove, "post-remove"); err != nil {
			return fmt.Errorf("post-remove script failed: %w", err)
		}
	}

	// Remove from database
	if err := m.db.RemoveInstallation(pkgName); err != nil {
		return fmt.Errorf("failed to update database: %w", err)
	}

	if m.progressChan != nil {
		m.progressChan <- ProgressUpdate{Stage: "done", Percent: 1.0, Message: "Removal complete"}
	}

	return nil
}

func (m *Manager) Upgrade(pkgName string) error {
	// Remove old version
	if err := m.Remove(pkgName, false); err != nil {
		return err
	}

	// Install new version
	return m.Install(pkgName)
}

func (m *Manager) IsInstalled(pkgName string) (bool, error) {
	return m.db.IsInstalled(pkgName)
}

func (m *Manager) ResolveDependencies(packages []string) ([]string, error) {
	resolver := NewResolver(m.db)
	return resolver.Resolve(packages)
}

func (m *Manager) GetReverseDependencies(pkgName string) ([]string, error) {
	return m.db.GetReverseDependencies(pkgName)
}

func (m *Manager) UpdateDatabase() error {
	// Download package index from repository
	indexURL := m.repoURL + "/index.json"
	resp, err := http.Get(indexURL)
	if err != nil {
		// If network fails, try to use local packages
		return m.scanLocalPackages()
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return m.scanLocalPackages()
	}

	var packages []PackageInfo
	if err := json.NewDecoder(resp.Body).Decode(&packages); err != nil {
		return fmt.Errorf("failed to parse package index: %w", err)
	}

	// Update database
	for _, pkg := range packages {
		if err := m.db.AddPackage(&pkg); err != nil {
			return fmt.Errorf("failed to add package %s: %w", pkg.Name, err)
		}
	}

	return nil
}

func (m *Manager) scanLocalPackages() error {
	// Scan cache directory for local packages
	pattern := filepath.Join(m.cacheDir, "*.mixpkg")
	files, err := filepath.Glob(pattern)
	if err != nil {
		return err
	}

	for _, file := range files {
		metadata, err := m.readPackageMetadata(file)
		if err != nil {
			continue
		}

		info := &PackageInfo{
			Name:         metadata.Name,
			Version:      metadata.Version,
			Description:  metadata.Description,
			Dependencies: metadata.Dependencies,
			Files:        metadata.Files,
			Checksum:     metadata.Checksum,
		}

		m.db.AddPackage(info)
	}

	return nil
}

func (m *Manager) CheckUpgrade(pkgName string) (*PackageUpgrade, error) {
	installed, err := m.db.GetInstalledPackage(pkgName)
	if err != nil {
		return nil, fmt.Errorf("package not installed")
	}

	available, err := m.db.GetPackage(pkgName)
	if err != nil {
		return nil, fmt.Errorf("package not in repository")
	}

	if compareVersions(available.Version, installed.Version) > 0 {
		return &PackageUpgrade{
			Name:           pkgName,
			CurrentVersion: installed.Version,
			NewVersion:     available.Version,
		}, nil
	}

	return nil, nil
}

func (m *Manager) GetUpgradablePackages() ([]PackageUpgrade, error) {
	installed, err := m.ListInstalled()
	if err != nil {
		return nil, err
	}

	var upgrades []PackageUpgrade
	for _, pkg := range installed {
		upgrade, err := m.CheckUpgrade(pkg.Name)
		if err == nil && upgrade != nil {
			upgrades = append(upgrades, *upgrade)
		}
	}

	return upgrades, nil
}

func (m *Manager) Search(query string, installedOnly bool) ([]SearchResult, error) {
	return m.db.Search(query, installedOnly)
}

func (m *Manager) ListInstalled() ([]PackageInfo, error) {
	return m.db.ListInstalled()
}

func (m *Manager) ListAvailable() ([]PackageInfo, error) {
	return m.db.ListAvailable()
}

func (m *Manager) GetPackageInfo(pkgName string) (*PackageInfo, error) {
	// Try installed first
	info, err := m.db.GetInstalledPackage(pkgName)
	if err == nil {
		info.Installed = true
		return info, nil
	}

	// Try available packages
	info, err = m.db.GetPackage(pkgName)
	if err != nil {
		return nil, fmt.Errorf("package %s not found", pkgName)
	}

	return info, nil
}

func (m *Manager) GetPackageFiles(pkgName string) ([]string, error) {
	return m.db.GetInstalledFiles(pkgName)
}

func (m *Manager) downloadPackage(name, version string) (string, error) {
	pkgFile := fmt.Sprintf("%s-%s.mixpkg", name, version)
	pkgPath := filepath.Join(m.cacheDir, pkgFile)

	// Check if already cached
	if _, err := os.Stat(pkgPath); err == nil {
		return pkgPath, nil
	}

	// Download from repository
	url := fmt.Sprintf("%s/%s", m.repoURL, pkgFile)
	resp, err := http.Get(url)
	if err != nil {
		// Try local package
		localPath := filepath.Join(m.cacheDir, pkgFile)
		if _, err := os.Stat(localPath); err == nil {
			return localPath, nil
		}
		return "", fmt.Errorf("failed to download package: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("package not found in repository (HTTP %d)", resp.StatusCode)
	}

	// Create cache directory
	os.MkdirAll(m.cacheDir, 0755)

	// Save to cache
	out, err := os.Create(pkgPath)
	if err != nil {
		return "", err
	}
	defer out.Close()

	_, err = io.Copy(out, resp.Body)
	if err != nil {
		os.Remove(pkgPath)
		return "", err
	}

	return pkgPath, nil
}

func (m *Manager) verifyChecksum(path, expected string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return err
	}

	actual := hex.EncodeToString(h.Sum(nil))
	if actual != expected {
		return fmt.Errorf("checksum mismatch: expected %s, got %s", expected, actual)
	}

	return nil
}

func (m *Manager) extractPackage(pkgPath string) (*PackageMetadata, error) {
	return m.readPackageMetadata(pkgPath)
}

func (m *Manager) readPackageMetadata(pkgPath string) (*PackageMetadata, error) {
	f, err := os.Open(pkgPath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	gzr, err := gzip.NewReader(f)
	if err != nil {
		return nil, err
	}
	defer gzr.Close()

	tr := tar.NewReader(gzr)

	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}

		if header.Name == "metadata.json" || header.Name == "./metadata.json" {
			var metadata PackageMetadata
			if err := json.NewDecoder(tr).Decode(&metadata); err != nil {
				return nil, err
			}
			return &metadata, nil
		}
	}

	return nil, fmt.Errorf("metadata.json not found in package")
}

func (m *Manager) installFiles(pkgPath string) ([]string, error) {
	f, err := os.Open(pkgPath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	gzr, err := gzip.NewReader(f)
	if err != nil {
		return nil, err
	}
	defer gzr.Close()

	tr := tar.NewReader(gzr)
	var installedFiles []string

	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return installedFiles, err
		}

		// Skip metadata and scripts
		if header.Name == "metadata.json" || strings.HasPrefix(header.Name, "scripts/") {
			continue
		}

		// Handle files/ prefix
		name := header.Name
		if strings.HasPrefix(name, "files/") {
			name = strings.TrimPrefix(name, "files/")
		}
		if strings.HasPrefix(name, "./files/") {
			name = strings.TrimPrefix(name, "./files/")
		}

		if name == "" || name == "." {
			continue
		}

		target := "/" + name

		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, os.FileMode(header.Mode)); err != nil {
				return installedFiles, err
			}
		case tar.TypeReg:
			dir := filepath.Dir(target)
			if err := os.MkdirAll(dir, 0755); err != nil {
				return installedFiles, err
			}

			outFile, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, os.FileMode(header.Mode))
			if err != nil {
				return installedFiles, err
			}

			if _, err := io.Copy(outFile, tr); err != nil {
				outFile.Close()
				return installedFiles, err
			}
			outFile.Close()
			installedFiles = append(installedFiles, target)

		case tar.TypeSymlink:
			os.Remove(target)
			if err := os.Symlink(header.Linkname, target); err != nil {
				return installedFiles, err
			}
			installedFiles = append(installedFiles, target)
		}
	}

	return installedFiles, nil
}

func (m *Manager) removeFiles(files []string) error {
	// Remove files in reverse order (deepest first)
	for i := len(files) - 1; i >= 0; i-- {
		path := files[i]
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			// Try to remove directory if empty
			os.Remove(filepath.Dir(path))
		}
	}
	return nil
}

func (m *Manager) runScript(script, name string) error {
	// include name in temp filename pattern to avoid unused param warnings
	pattern := "mix-script-"
	if name != "" {
		pattern += name + "-"
	}
	tmpFile, err := os.CreateTemp("", pattern+"*")
	if err != nil {
		return err
	}
	defer os.Remove(tmpFile.Name())

	if _, err := tmpFile.WriteString(script); err != nil {
		return err
	}
	tmpFile.Close()

	os.Chmod(tmpFile.Name(), 0755)

	cmd := exec.Command("/bin/sh", tmpFile.Name())
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	return cmd.Run()
}

func compareVersions(v1, v2 string) int {
	parts1 := strings.Split(v1, ".")
	parts2 := strings.Split(v2, ".")

	maxLen := len(parts1)
	if len(parts2) > maxLen {
		maxLen = len(parts2)
	}

	for i := 0; i < maxLen; i++ {
		var n1, n2 int
		if i < len(parts1) {
			fmt.Sscanf(parts1[i], "%d", &n1)
		}
		if i < len(parts2) {
			fmt.Sscanf(parts2[i], "%d", &n2)
		}

		if n1 < n2 {
			return -1
		}
		if n1 > n2 {
			return 1
		}
	}

	return 0
}

// CreatePackage creates a .mixpkg file from a directory
func CreatePackage(srcDir, outputPath string, metadata *PackageMetadata) error {
	f, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer f.Close()

	gzw := gzip.NewWriter(f)
	defer gzw.Close()

	tw := tar.NewWriter(gzw)
	defer tw.Close()

	// Write metadata.json
	metadataJSON, err := json.MarshalIndent(metadata, "", "  ")
	if err != nil {
		return err
	}

	if err := tw.WriteHeader(&tar.Header{
		Name:    "metadata.json",
		Size:    int64(len(metadataJSON)),
		Mode:    0644,
		ModTime: time.Now(),
	}); err != nil {
		return err
	}

	if _, err := tw.Write(metadataJSON); err != nil {
		return err
	}

	// Write files
	filesDir := filepath.Join(srcDir, "files")
	if _, err := os.Stat(filesDir); err == nil {
		err = filepath.Walk(filesDir, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}

			relPath, err := filepath.Rel(srcDir, path)
			if err != nil {
				return err
			}

			header, err := tar.FileInfoHeader(info, "")
			if err != nil {
				return err
			}
			header.Name = relPath

			if err := tw.WriteHeader(header); err != nil {
				return err
			}

			if !info.IsDir() {
				file, err := os.Open(path)
				if err != nil {
					return err
				}
				defer file.Close()

				_, err = io.Copy(tw, file)
				return err
			}

			return nil
		})
		if err != nil {
			return err
		}
	}

	return nil
}
