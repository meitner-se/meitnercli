package boilerconfig

import (
	"meitnercli/templates"

	"github.com/volatiletech/sqlboiler/v4/boilingcore"
	"github.com/volatiletech/sqlboiler/v4/importers"
)

func Service(outFolder, serviceName, pkgRepository, pkgServiceModel string) Wrapper {
	return func(cfg *boilingcore.Config) {
		singletonImports := importers.Map{
			"service": importers.Set{
				Standard: nil,
				ThirdParty: importers.List{
					formatPkgImportWithAlias(pkgRepository, "repository"),
				},
			},
		}

		cfg.PkgName = serviceName
		cfg.OutFolder = outFolder
		cfg.NoDriverTemplates = true
		cfg.NoTests = true
		cfg.Imports.Singleton = singletonImports
		cfg.Imports.All.Standard = nil
		cfg.Imports.All.ThirdParty = importers.List{
			formatPkgImportWithAlias(pkgServiceModel, "model"),
		}
		cfg.DefaultTemplates = templates.ServiceStub
	}
}
