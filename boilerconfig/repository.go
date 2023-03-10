package boilerconfig

import (
	"github.com/meitner-se/meitnercli/templates"

	"github.com/volatiletech/sqlboiler/v4/boilingcore"
	"github.com/volatiletech/sqlboiler/v4/importers"
)

func Repository(outFolder, pkgServiceModel, pkgTypes string, withStub bool, stubLayer string) Wrapper {
	return func(cfg *boilingcore.Config) {
		cfg.PkgName = "repository"
		cfg.OutFolder = outFolder
		cfg.AddEnumTypes = true
		cfg.NoDriverTemplates = true
		cfg.NoTests = true
		cfg.Imports.All.Standard = nil
		cfg.Imports.All.ThirdParty = importers.List{
			formatPkgImportWithAlias(pkgServiceModel, "model"),
			formatPkgImportWithAlias(pkgTypes, "types"),
		}
		cfg.DefaultTemplates = templates.Repository

		if (withStub || stubLayer != "") && (stubLayer == "" || stubLayer == "repository") {
			singletonImports := importers.Map{
				"repository": importers.Set{
					Standard: importers.List{
						formatPkgImport("context"),
					},
				},
			}
			cfg.Imports.Singleton = singletonImports
			cfg.DefaultTemplates = templates.RepositoryWithStub
		}
	}
}
