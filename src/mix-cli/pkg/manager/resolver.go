package manager

import (
	"fmt"
	"strings"
)

// Resolver handles dependency resolution using topological sort
type Resolver struct {
	db        *Database
	resolved  map[string]bool
	unresolved map[string]bool
	order     []string
}

func NewResolver(db *Database) *Resolver {
	return &Resolver{
		db:         db,
		resolved:   make(map[string]bool),
		unresolved: make(map[string]bool),
	}
}

// Resolve returns packages in installation order (dependencies first)
func (r *Resolver) Resolve(packages []string) ([]string, error) {
	r.resolved = make(map[string]bool)
	r.unresolved = make(map[string]bool)
	r.order = nil

	// Mark already installed packages as resolved
	for _, pkg := range packages {
		installed, _ := r.db.IsInstalled(pkg)
		if installed {
			r.resolved[pkg] = true
		}
	}

	// Resolve each requested package
	for _, pkg := range packages {
		if r.resolved[pkg] {
			continue
		}
		if err := r.resolve(pkg); err != nil {
			return nil, err
		}
	}

	// Filter out already installed packages
	var toInstall []string
	for _, pkg := range r.order {
		installed, _ := r.db.IsInstalled(pkg)
		if !installed {
			toInstall = append(toInstall, pkg)
		}
	}

	return toInstall, nil
}

func (r *Resolver) resolve(pkg string) error {
	// Check for circular dependency
	if r.unresolved[pkg] {
		return fmt.Errorf("circular dependency detected: %s", pkg)
	}

	// Already resolved
	if r.resolved[pkg] {
		return nil
	}

	r.unresolved[pkg] = true

	// Get dependencies
	deps, err := r.db.GetDependencies(pkg)
	if err != nil {
		// Package not in database, might be a virtual package or error
		// For now, just add it without dependencies
		r.resolved[pkg] = true
		delete(r.unresolved, pkg)
		r.order = append(r.order, pkg)
		return nil
	}

	// Resolve each dependency
	for _, dep := range deps {
		depName := parseDependency(dep)
		
		// Check if already installed
		installed, _ := r.db.IsInstalled(depName)
		if installed {
			r.resolved[depName] = true
			continue
		}

		if err := r.resolve(depName); err != nil {
			return err
		}
	}

	r.resolved[pkg] = true
	delete(r.unresolved, pkg)
	r.order = append(r.order, pkg)

	return nil
}

// parseDependency extracts package name from dependency string
// Handles formats like: "pkg", "pkg>=1.0", "pkg<=2.0", "pkg=1.0"
func parseDependency(dep string) string {
	dep = strings.TrimSpace(dep)
	
	// Handle version constraints
	for _, sep := range []string{">=", "<=", "=", ">", "<"} {
		if idx := strings.Index(dep, sep); idx != -1 {
			return strings.TrimSpace(dep[:idx])
		}
	}
	
	return dep
}

// CheckDependencies verifies all dependencies are satisfied
func (r *Resolver) CheckDependencies(pkg string) ([]string, error) {
	deps, err := r.db.GetDependencies(pkg)
	if err != nil {
		return nil, err
	}

	var missing []string
	for _, dep := range deps {
		depName := parseDependency(dep)
		installed, _ := r.db.IsInstalled(depName)
		if !installed {
			missing = append(missing, depName)
		}
	}

	return missing, nil
}

// GetInstallOrder returns packages in the order they should be installed
func (r *Resolver) GetInstallOrder(packages []string) ([]string, error) {
	return r.Resolve(packages)
}

// GetRemoveOrder returns packages in the order they should be removed
// (reverse of install order, respecting reverse dependencies)
func (r *Resolver) GetRemoveOrder(packages []string) ([]string, error) {
	var order []string
	visited := make(map[string]bool)

	for _, pkg := range packages {
		if err := r.getRemoveOrder(pkg, visited, &order); err != nil {
			return nil, err
		}
	}

	return order, nil
}

func (r *Resolver) getRemoveOrder(pkg string, visited map[string]bool, order *[]string) error {
	if visited[pkg] {
		return nil
	}
	visited[pkg] = true

	// Get reverse dependencies (packages that depend on this one)
	revDeps, err := r.db.GetReverseDependencies(pkg)
	if err != nil {
		return err
	}

	// Remove reverse dependencies first
	for _, dep := range revDeps {
		if err := r.getRemoveOrder(dep, visited, order); err != nil {
			return err
		}
	}

	*order = append(*order, pkg)
	return nil
}
