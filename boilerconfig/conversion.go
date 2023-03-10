package boilerconfig

import (
	"github.com/meitner-se/meitnercli/templates"

	"github.com/volatiletech/sqlboiler/v4/boilingcore"
	"github.com/volatiletech/sqlboiler/v4/importers"
)

func Conversion(outFolder, pkgServiceModel, pkgAPI, pkgSlice string) Wrapper {
	return func(cfg *boilingcore.Config) {
		cfg.PkgName = "conversion"
		cfg.OutFolder = outFolder
		cfg.AddEnumTypes = true
		cfg.NoContext = true
		cfg.NoDriverTemplates = true
		cfg.NoTests = true
		cfg.Imports.All.Standard = nil
		cfg.Imports.All.ThirdParty = importers.List{
			formatPkgImportWithAlias(pkgServiceModel, "model"),
			formatPkgImportWithAlias(pkgAPI, "api"),
			formatPkgImportWithAlias(pkgSlice, "slice"),
		}
		cfg.DefaultTemplates = templates.Conversion
	}
}
