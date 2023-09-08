package boilerconfig

import (
	"github.com/meitner-se/meitnercli/templates"

	"github.com/volatiletech/sqlboiler/v4/boilingcore"
	"github.com/volatiletech/sqlboiler/v4/importers"
)

func ORM(outFolder, pkgServiceModel, pkgAudit, pkgCache, pkgErrors, pkgSlices string) Wrapper {
	return func(cfg *boilingcore.Config) {
		cfg.PkgName = "orm"
		cfg.OutFolder = outFolder
		cfg.NoDriverTemplates = true
		cfg.NoTests = true
		cfg.Imports.All.Standard = importers.List{
			formatPkgImport("fmt"),
			formatPkgImport("time"),
		}
		cfg.Imports.All.ThirdParty = importers.List{
			formatPkgImportWithAlias(pkgServiceModel, "model"),
			formatPkgImportWithAlias(pkgAudit, "audit"),
			formatPkgImportWithAlias(pkgCache, "cache"),
			formatPkgImportWithAlias(pkgErrors, "errors"),
			formatPkgImportWithAlias(pkgSlices, "slices"),
			formatPkgImport("platform/backend/pkg/querybuilder"),
			formatPkgImport("github.com/google/uuid"),
			formatPkgImport("github.com/lib/pq"),
			formatPkgImport("github.com/volatiletech/sqlboiler/v4/boil"),
			formatPkgImport("github.com/volatiletech/sqlboiler/v4/queries/qm"),
		}
		cfg.DefaultTemplates = templates.ORM
	}
}
