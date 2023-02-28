package boilerconfig

import (
	"github.com/meitner-se/meitnercli/templates"

	"github.com/volatiletech/sqlboiler/v4/boilingcore"
	"github.com/volatiletech/sqlboiler/v4/importers"
)

func Boiler(outFolder, pkgORM, pkgServiceModel, pkgRepository, pkgErrors, pkgAudit, pkgAuth, pkgDatabase, pkgLogger, pkgTypes string, withStub bool, stubLayer string) Wrapper {
	return func(cfg *boilingcore.Config) {
		cfg.PkgName = "boiler"
		cfg.OutFolder = outFolder
		cfg.NoDriverTemplates = true
		cfg.NoTests = true
		cfg.Imports.All.Standard = importers.List{
			formatPkgImport("database/sql"),
			formatPkgImport("time"),
		}
		cfg.Imports.All.ThirdParty = importers.List{
			formatPkgImport("github.com/google/uuid"),
			formatPkgImportWithAlias(pkgORM, "orm"),
			formatPkgImportWithAlias(pkgServiceModel, "model"),
			formatPkgImportWithAlias(pkgAuth, "auth"),
			formatPkgImportWithAlias(pkgErrors, "errors"),
			formatPkgImportWithAlias(pkgDatabase, "database"),
		}
		cfg.DefaultTemplates = templates.Boiler

		if (withStub || stubLayer != "") && (stubLayer == "" || stubLayer == "boiler") {
			singletonImports := importers.Map{
				"boiler": importers.Set{
					Standard: importers.List{
						formatPkgImport("context"),
						formatPkgImport("database/sql"),
						formatPkgImport("embed"),
					},
					ThirdParty: importers.List{
						formatPkgImportWithAlias(pkgRepository, "repository"),
						formatPkgImportWithAlias(pkgAudit, "audit"),
						formatPkgImportWithAlias(pkgDatabase, "database"),
						formatPkgImportWithAlias(pkgLogger, "logger"),
						formatPkgImportWithAlias(pkgTypes, "types"),
						formatPkgImport("github.com/pressly/goose/v3"),
					},
				},
			}
			cfg.Imports.Singleton = singletonImports
			cfg.DefaultTemplates = templates.BoilerWithStub
		}
	}
}
