package manager

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"

	_ "github.com/mattn/go-sqlite3"
)

type Database struct {
	db *sql.DB
}

func NewDatabase(path string) (*Database, error) {
	db, err := sql.Open("sqlite3", path)
	if err != nil {
		return nil, err
	}

	d := &Database{db: db}
	if err := d.init(); err != nil {
		db.Close()
		return nil, err
	}

	return d, nil
}

func (d *Database) init() error {
	schema := `
	CREATE TABLE IF NOT EXISTS packages (
		name TEXT PRIMARY KEY,
		version TEXT NOT NULL,
		description TEXT,
		dependencies TEXT,
		files TEXT,
		checksum TEXT,
		size INTEGER DEFAULT 0
	);

	CREATE TABLE IF NOT EXISTS installed (
		name TEXT PRIMARY KEY,
		version TEXT NOT NULL,
		install_time DATETIME DEFAULT CURRENT_TIMESTAMP,
		files TEXT
	);

	CREATE TABLE IF NOT EXISTS files (
		path TEXT PRIMARY KEY,
		package TEXT NOT NULL,
		FOREIGN KEY (package) REFERENCES installed(name)
	);

	CREATE INDEX IF NOT EXISTS idx_files_package ON files(package);
	CREATE INDEX IF NOT EXISTS idx_packages_name ON packages(name);
	`

	_, err := d.db.Exec(schema)
	return err
}

func (d *Database) Close() error {
	return d.db.Close()
}

func (d *Database) AddPackage(pkg *PackageInfo) error {
	deps, _ := json.Marshal(pkg.Dependencies)
	files, _ := json.Marshal(pkg.Files)

	_, err := d.db.Exec(`
		INSERT OR REPLACE INTO packages (name, version, description, dependencies, files, checksum, size)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	`, pkg.Name, pkg.Version, pkg.Description, string(deps), string(files), pkg.Checksum, pkg.Size)

	return err
}

func (d *Database) GetPackage(name string) (*PackageInfo, error) {
	var pkg PackageInfo
	var deps, files string

	err := d.db.QueryRow(`
		SELECT name, version, description, dependencies, files, checksum, size
		FROM packages WHERE name = ?
	`, name).Scan(&pkg.Name, &pkg.Version, &pkg.Description, &deps, &files, &pkg.Checksum, &pkg.Size)

	if err != nil {
		return nil, err
	}

	json.Unmarshal([]byte(deps), &pkg.Dependencies)
	json.Unmarshal([]byte(files), &pkg.Files)

	return &pkg, nil
}

func (d *Database) RecordInstallation(name, version string, files []string) error {
	tx, err := d.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	filesJSON, _ := json.Marshal(files)

	_, err = tx.Exec(`
		INSERT OR REPLACE INTO installed (name, version, files)
		VALUES (?, ?, ?)
	`, name, version, string(filesJSON))
	if err != nil {
		return err
	}

	// Record individual files
	for _, file := range files {
		_, err = tx.Exec(`
			INSERT OR REPLACE INTO files (path, package)
			VALUES (?, ?)
		`, file, name)
		if err != nil {
			return err
		}
	}

	return tx.Commit()
}

func (d *Database) RemoveInstallation(name string) error {
	tx, err := d.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.Exec(`DELETE FROM files WHERE package = ?`, name)
	if err != nil {
		return err
	}

	_, err = tx.Exec(`DELETE FROM installed WHERE name = ?`, name)
	if err != nil {
		return err
	}

	return tx.Commit()
}

func (d *Database) IsInstalled(name string) (bool, error) {
	var count int
	err := d.db.QueryRow(`SELECT COUNT(*) FROM installed WHERE name = ?`, name).Scan(&count)
	return count > 0, err
}

func (d *Database) GetInstalledPackage(name string) (*PackageInfo, error) {
	var pkg PackageInfo
	var filesJSON string

	err := d.db.QueryRow(`
		SELECT i.name, i.version, COALESCE(p.description, ''), COALESCE(p.dependencies, '[]'), i.files, COALESCE(p.checksum, ''), COALESCE(p.size, 0)
		FROM installed i
		LEFT JOIN packages p ON i.name = p.name
		WHERE i.name = ?
	`, name).Scan(&pkg.Name, &pkg.Version, &pkg.Description, &pkg.Dependencies, &filesJSON, &pkg.Checksum, &pkg.Size)

	if err != nil {
		return nil, err
	}

	json.Unmarshal([]byte(filesJSON), &pkg.Files)
	pkg.Installed = true

	return &pkg, nil
}

func (d *Database) GetInstalledFiles(name string) ([]string, error) {
	var filesJSON string
	err := d.db.QueryRow(`SELECT files FROM installed WHERE name = ?`, name).Scan(&filesJSON)
	if err != nil {
		return nil, err
	}

	var files []string
	json.Unmarshal([]byte(filesJSON), &files)
	return files, nil
}

func (d *Database) GetReverseDependencies(name string) ([]string, error) {
	rows, err := d.db.Query(`
		SELECT i.name, p.dependencies
		FROM installed i
		JOIN packages p ON i.name = p.name
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []string
	for rows.Next() {
		var pkgName, depsJSON string
		if err := rows.Scan(&pkgName, &depsJSON); err != nil {
			continue
		}

		var deps []string
		json.Unmarshal([]byte(depsJSON), &deps)

		for _, dep := range deps {
			// Handle version constraints (e.g., "pkg>=1.0")
			depName := strings.Split(dep, ">=")[0]
			depName = strings.Split(depName, "<=")[0]
			depName = strings.Split(depName, "=")[0]
			depName = strings.TrimSpace(depName)

			if depName == name {
				result = append(result, pkgName)
				break
			}
		}
	}

	return result, nil
}

func (d *Database) ListInstalled() ([]PackageInfo, error) {
	rows, err := d.db.Query(`
		SELECT i.name, i.version, COALESCE(p.description, '')
		FROM installed i
		LEFT JOIN packages p ON i.name = p.name
		ORDER BY i.name
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var packages []PackageInfo
	for rows.Next() {
		var pkg PackageInfo
		if err := rows.Scan(&pkg.Name, &pkg.Version, &pkg.Description); err != nil {
			continue
		}
		pkg.Installed = true
		packages = append(packages, pkg)
	}

	return packages, nil
}

func (d *Database) ListAvailable() ([]PackageInfo, error) {
	rows, err := d.db.Query(`
		SELECT p.name, p.version, p.description,
			   CASE WHEN i.name IS NOT NULL THEN 1 ELSE 0 END as installed
		FROM packages p
		LEFT JOIN installed i ON p.name = i.name
		ORDER BY p.name
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var packages []PackageInfo
	for rows.Next() {
		var pkg PackageInfo
		var installed int
		if err := rows.Scan(&pkg.Name, &pkg.Version, &pkg.Description, &installed); err != nil {
			continue
		}
		pkg.Installed = installed == 1
		packages = append(packages, pkg)
	}

	return packages, nil
}

func (d *Database) Search(query string, installedOnly bool) ([]SearchResult, error) {
	query = "%" + strings.ToLower(query) + "%"

	var sql string
	if installedOnly {
		sql = `
			SELECT i.name, i.version, COALESCE(p.description, ''), 1
			FROM installed i
			LEFT JOIN packages p ON i.name = p.name
			WHERE LOWER(i.name) LIKE ? OR LOWER(COALESCE(p.description, '')) LIKE ?
			ORDER BY i.name
		`
	} else {
		sql = `
			SELECT p.name, p.version, p.description,
				   CASE WHEN i.name IS NOT NULL THEN 1 ELSE 0 END
			FROM packages p
			LEFT JOIN installed i ON p.name = i.name
			WHERE LOWER(p.name) LIKE ? OR LOWER(p.description) LIKE ?
			ORDER BY p.name
		`
	}

	rows, err := d.db.Query(sql, query, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []SearchResult
	for rows.Next() {
		var r SearchResult
		var installed int
		if err := rows.Scan(&r.Name, &r.Version, &r.Description, &installed); err != nil {
			continue
		}
		r.Installed = installed == 1
		results = append(results, r)
	}

	return results, nil
}

func (d *Database) GetAllPackages() ([]PackageInfo, error) {
	rows, err := d.db.Query(`
		SELECT name, version, description, dependencies, checksum
		FROM packages
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var packages []PackageInfo
	for rows.Next() {
		var pkg PackageInfo
		var depsJSON string
		if err := rows.Scan(&pkg.Name, &pkg.Version, &pkg.Description, &depsJSON, &pkg.Checksum); err != nil {
			continue
		}
		json.Unmarshal([]byte(depsJSON), &pkg.Dependencies)
		packages = append(packages, pkg)
	}

	return packages, nil
}

func (d *Database) GetDependencies(name string) ([]string, error) {
	var depsJSON string
	err := d.db.QueryRow(`SELECT dependencies FROM packages WHERE name = ?`, name).Scan(&depsJSON)
	if err != nil {
		return nil, fmt.Errorf("package %s not found", name)
	}

	var deps []string
	json.Unmarshal([]byte(depsJSON), &deps)
	return deps, nil
}
