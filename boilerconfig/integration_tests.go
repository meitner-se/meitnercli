package boilerconfig

import (
	"github.com/volatiletech/sqlboiler/v4/importers"

	"github.com/meitner-se/meitnercli/templates"

	"github.com/volatiletech/sqlboiler/v4/boilingcore"
)

func IntegrationTest(outFolder string, pkgTypes, pkgTestHelpers, pkgClient string) Wrapper {
	return func(cfg *boilingcore.Config) {
		cfg.PkgName = "tests"
		cfg.OutFolder = outFolder
		cfg.NoDriverTemplates = true
		singletonImports := importers.Map{
			"base_setup_test": importers.Set{
				Standard: importers.List{
					formatPkgImport("testing"),
				},
				ThirdParty: importers.List{
					formatPkgImport(pkgTestHelpers),
					formatPkgImport(pkgClient),
				},
			},
		}
		cfg.Imports.Singleton = singletonImports
		cfg.Imports.All.Standard = importers.List{
			formatPkgImport("testing"),
			formatPkgImport("context"),
		}
		cfg.Imports.All.ThirdParty = importers.List{
			formatPkgImport(pkgTypes),
			formatPkgImport(pkgTestHelpers),
			formatPkgImport(pkgClient),
			formatPkgImport("github.com/stretchr/testify/assert"),
			formatPkgImport("github.com/stretchr/testify/require"),
		}

		cfg.NoTests = false
		cfg.NoContext = true
		cfg.DefaultTemplates = templates.IntegrationTestStub
	}
}
