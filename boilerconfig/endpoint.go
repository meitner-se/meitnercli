package boilerconfig

import (
	"github.com/meitner-se/meitnercli/templates"

	"github.com/volatiletech/sqlboiler/v4/boilingcore"
	"github.com/volatiletech/sqlboiler/v4/importers"
)

func Endpoint(outFolder, serviceName, pkgServiceModel, pkgConversion, pkgAPI, pkgTypes string) Wrapper {
	return func(cfg *boilingcore.Config) {
		singletonImports := importers.Set{
			Standard: importers.List{
				formatPkgImport("context"),
			},
			ThirdParty: importers.List{
				formatPkgImportWithAlias(pkgServiceModel, "model"),
				formatPkgImportWithAlias(pkgConversion, "conversion"),
				formatPkgImportWithAlias(pkgAPI, "api"),
				formatPkgImportWithAlias(pkgTypes, "types"),
			},
		}

		cfg.PkgName = "endpoint"
		cfg.OutFolder = outFolder
		cfg.NoDriverTemplates = true
		cfg.NoTests = true
		cfg.Imports.Singleton = importers.Map{
			"endpoint_command": singletonImports,
			"endpoint_query":   singletonImports,
		}
		cfg.DefaultTemplates = templates.EndpointStub
	}
}
