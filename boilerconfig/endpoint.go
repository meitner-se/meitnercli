package boilerconfig

import (
	"github.com/meitner-se/meitnercli/templates"

	"github.com/volatiletech/sqlboiler/v4/boilingcore"
	"github.com/volatiletech/sqlboiler/v4/importers"
)

func Endpoint(outFolder, serviceName, pkgServiceModel, pkgConversion, pkgAPI, pkgTypes, pkgErrors string) Wrapper {
	return func(cfg *boilingcore.Config) {
		singletonImportsCommand := importers.Set{
			Standard: importers.List{
				formatPkgImport("context"),
			},
			ThirdParty: importers.List{
				formatPkgImportWithAlias(pkgServiceModel, "model"),
				formatPkgImportWithAlias(pkgAPI, "api"),
				formatPkgImportWithAlias(pkgTypes, "types"),
			},
		}

		singletonImportsQuery := singletonImportsCommand
		singletonImportsQuery.ThirdParty = append(singletonImportsQuery.ThirdParty, formatPkgImportWithAlias(pkgErrors, "errors"))
		singletonImportsQuery.ThirdParty = append(singletonImportsQuery.ThirdParty, formatPkgImportWithAlias(pkgConversion, "conversion"))

		cfg.PkgName = "endpoint"
		cfg.OutFolder = outFolder
		cfg.NoDriverTemplates = true
		cfg.NoTests = true
		cfg.Imports.Singleton = importers.Map{
			"endpoint_command": singletonImportsCommand,
			"endpoint_query":   singletonImportsQuery,
		}
		cfg.DefaultTemplates = templates.EndpointStub
	}
}
