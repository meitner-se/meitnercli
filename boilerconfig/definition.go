package boilerconfig

import (
	"meitnercli/templates"

	"github.com/volatiletech/sqlboiler/v4/boilingcore"
	"github.com/volatiletech/sqlboiler/v4/importers"
)

func Definition(outFolder, serviceName string, withStub bool) Wrapper {
	return func(cfg *boilingcore.Config) {
		cfg.PkgName = serviceName
		cfg.OutFolder = outFolder
		cfg.AddEnumTypes = true
		cfg.NoContext = true
		cfg.NoDriverTemplates = true
		cfg.NoTests = true
		cfg.Imports.All.Standard = nil
		cfg.Imports.All.ThirdParty = importers.List{}
		cfg.DefaultTemplates = templates.Definition

		if withStub {
			cfg.DefaultTemplates = templates.DefinitionWithStub
		}
	}
}
