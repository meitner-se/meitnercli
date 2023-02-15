package boilerconfig

import (
	"github.com/meitner-se/meitnercli/templates"

	"github.com/volatiletech/sqlboiler/v4/boilingcore"
	"github.com/volatiletech/sqlboiler/v4/importers"
)

func Model(outFolder, pkgTypes, pkgErrors string) Wrapper {
	return func(cfg *boilingcore.Config) {
		cfg.PkgName = "model"
		cfg.OutFolder = outFolder
		cfg.AddEnumTypes = true
		cfg.NoContext = true
		cfg.NoDriverTemplates = true
		cfg.NoTests = true
		cfg.Imports.All.Standard = nil
		cfg.Imports.All.ThirdParty = importers.List{
			formatPkgImportWithAlias(pkgTypes, "types"),
			formatPkgImportWithAlias(pkgErrors, "errors"),
		}
		cfg.DefaultTemplates = templates.Model
	}
}
