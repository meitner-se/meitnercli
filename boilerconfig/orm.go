package boilerconfig

import (
	"github.com/meitner-se/meitnercli/templates"

	"github.com/volatiletech/sqlboiler/v4/boilingcore"
	"github.com/volatiletech/sqlboiler/v4/importers"
)

func ORM(outFolder, pkgServiceModel, pkgAudit, pkgCache string) Wrapper {
	return func(cfg *boilingcore.Config) {
		cfg.PkgName = "orm"
		cfg.OutFolder = outFolder
		cfg.NoDriverTemplates = true
		cfg.NoTests = true
		cfg.Imports.All.Standard = importers.List{
			formatPkgImport("encoding/json"),
			formatPkgImport("sort"),
			formatPkgImport("strings"),
			formatPkgImport("time"),
		}
		cfg.Imports.All.ThirdParty = importers.List{
			formatPkgImportWithAlias(pkgServiceModel, "model"),
			formatPkgImportWithAlias(pkgAudit, "audit"),
			formatPkgImportWithAlias(pkgCache, "cache"),
			formatPkgImport("github.com/google/uuid"),
			formatPkgImport("github.com/friendsofgo/errors"),
			formatPkgImport("github.com/volatiletech/sqlboiler/v4/boil"),
			formatPkgImport("github.com/volatiletech/sqlboiler/v4/queries/qm"),
		}
		cfg.DefaultTemplates = templates.ORM
	}
}
