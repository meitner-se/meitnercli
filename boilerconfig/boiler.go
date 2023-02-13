package boilerconfig

import (
	"github.com/meitner-se/meitnercli/templates"

	"github.com/volatiletech/sqlboiler/v4/boilingcore"
	"github.com/volatiletech/sqlboiler/v4/importers"
)

func Boiler(outFolder, pkgORM, pkgServiceModel, pkgErrors, pkgAudit, pkgCache string, withStub bool, stubLayer string) Wrapper {
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
			formatPkgImportWithAlias(pkgErrors, "errors"),
		}
		cfg.DefaultTemplates = templates.Boiler

		if (withStub || stubLayer != "") && (stubLayer == "" || stubLayer == "boiler") {
			singletonImports := importers.Map{
				"boiler": importers.Set{
					Standard: importers.List{
						formatPkgImport("database/sql"),
						formatPkgImport("os"),
						formatPkgImport("embed"),
					},
					ThirdParty: importers.List{
						formatPkgImportWithAlias(pkgAudit, "audit"),
						formatPkgImport("github.com/pressly/goose/v3"),
					},
				},
			}
			cfg.Imports.Singleton = singletonImports
			cfg.DefaultTemplates = templates.BoilerWithStub
		}
	}
}
