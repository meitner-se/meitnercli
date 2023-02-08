package boilerconfig

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/friendsofgo/errors"
	"github.com/spf13/viper"
	"github.com/volatiletech/sqlboiler/v4/boilingcore"
	"github.com/volatiletech/sqlboiler/v4/drivers"
	"github.com/volatiletech/sqlboiler/v4/importers"
)

const sqlBoilerVersion string = "v4.14.0"

type Wrapper func(*boilingcore.Config)

func GetState(cfg *boilingcore.Config, dbName, dbUser, dbPassword, dbHost string, dbPort int, dbSSLMode string) (*boilingcore.State, error) {
	// Configure the driver
	cfg.DriverConfig = map[string]interface{}{
		"whitelist":        viper.GetStringSlice(cfg.DriverName + ".whitelist"),
		"blacklist":        viper.GetStringSlice(cfg.DriverName + ".blacklist"),
		"add-enum-types":   cfg.AddEnumTypes,
		"enum-null-prefix": cfg.EnumNullPrefix,
	}

	cfg.DriverConfig["host"] = dbHost
	cfg.DriverConfig["sslmode"] = dbSSLMode
	cfg.DriverConfig["dbname"] = dbName
	cfg.DriverConfig["user"] = dbUser
	cfg.DriverConfig["pass"] = dbPassword
	cfg.DriverConfig["port"] = dbPort

	keys := allKeys(cfg.DriverName)
	for _, key := range keys {
		if key != "blacklist" && key != "whitelist" {
			prefixedKey := fmt.Sprintf("%s.%s", cfg.DriverName, key)
			cfg.DriverConfig[key] = viper.Get(prefixedKey)
		}
	}

	// Create a flag to check if the standard imports should be nilled,
	// since they get overwritten when getting the State from boilingcore.
	nilStandardImports := nil == cfg.Imports.All.Standard

	state, err := boilingcore.New(cfg)
	if err != nil {
		return nil, errors.Wrap(err, "cannot get boilingcore.State")
	}

	if nilStandardImports {
		state.Config.Imports.All.Standard = nil

		// Always use context except unless NoContext is specified
		if !cfg.NoContext {
			state.Config.Imports.All.Standard = importers.List{formatPkgImport("context")}
		}
	}

	return state, nil
}

func GetConfig(driverName, configFile, typesPackage string) (*boilingcore.Config, error) {
	err := initConfig(configFile)
	if err != nil {
		return nil, errors.Wrap(err, "cannot initialize config")
	}

	config := &boilingcore.Config{
		DriverName:        driverName,
		OutFolder:         viper.GetString("output"),
		PkgName:           viper.GetString("pkgname"),
		Debug:             viper.GetBool("debug"),
		AddGlobal:         viper.GetBool("add-global-variants"),
		AddPanic:          viper.GetBool("add-panic-variants"),
		AddSoftDeletes:    viper.GetBool("add-soft-deletes"),
		AddEnumTypes:      viper.GetBool("add-enum-types"),
		EnumNullPrefix:    viper.GetString("enum-null-prefix"),
		NoContext:         viper.GetBool("no-context"),
		NoTests:           viper.GetBool("no-tests"),
		NoHooks:           viper.GetBool("no-hooks"),
		NoRowsAffected:    viper.GetBool("no-rows-affected"),
		NoAutoTimestamps:  viper.GetBool("no-auto-timestamps"),
		NoDriverTemplates: viper.GetBool("no-driver-templates"),
		NoBackReferencing: viper.GetBool("no-back-referencing"),
		AlwaysWrapErrors:  viper.GetBool("always-wrap-errors"),
		Wipe:              viper.GetBool("wipe"),
		StructTagCasing:   strings.ToLower(viper.GetString("struct-tag-casing")), // camel | snake | title
		TagIgnore:         viper.GetStringSlice("tag-ignore"),
		RelationTag:       viper.GetString("relation-tag"),
		TemplateDirs:      viper.GetStringSlice("templates"),
		Tags:              viper.GetStringSlice("tag"),
		Replacements:      viper.GetStringSlice("replace"),
		Aliases:           boilingcore.ConvertAliases(viper.Get("aliases")),
		TypeReplaces:      append(boilingcore.ConvertTypeReplace(viper.Get("types")), getBoilerTypeReplacements(typesPackage)...),
		AutoColumns: boilingcore.AutoColumns{
			Created: viper.GetString("auto-columns.created"),
			Updated: viper.GetString("auto-columns.updated"),
			Deleted: viper.GetString("auto-columns.deleted"),
		},
		Inflections: boilingcore.Inflections{
			Plural:        viper.GetStringMapString("inflections.plural"),
			PluralExact:   viper.GetStringMapString("inflections.plural_exact"),
			Singular:      viper.GetStringMapString("inflections.singular"),
			SingularExact: viper.GetStringMapString("inflections.singular_exact"),
			Irregular:     viper.GetStringMapString("inflections.irregular"),
		},

		Version: sqlBoilerVersion,
	}

	return config, nil
}

func initConfig(configFile string) error {
	if len(configFile) != 0 {
		viper.SetConfigFile(configFile)

		err := viper.ReadInConfig()
		if err != nil {
			return errors.Wrap(err, "cannot read in config")
		}

		return nil
	}

	viper.SetConfigName("sqlboiler")

	configHome := os.Getenv("XDG_CONFIG_HOME")
	homePath := os.Getenv("HOME")
	wd, err := os.Getwd()
	if err != nil {
		wd = "."
	}

	configPaths := []string{wd}
	if len(configHome) > 0 {
		configPaths = append(configPaths, filepath.Join(configHome, "sqlboiler"))
	} else {
		configPaths = append(configPaths, filepath.Join(homePath, ".config/sqlboiler"))
	}

	for _, p := range configPaths {
		viper.AddConfigPath(p)
	}

	// Ignore errors here, fallback to other validation methods.
	// Users can use environment variables if a config is not found.
	_ = viper.ReadInConfig()

	return nil
}

func allKeys(prefix string) []string {
	keys := make(map[string]bool)

	prefix += "."

	for _, e := range os.Environ() {
		splits := strings.SplitN(e, "=", 2)
		key := strings.ReplaceAll(strings.ToLower(splits[0]), "_", ".")

		if strings.HasPrefix(key, prefix) {
			keys[strings.ReplaceAll(key, prefix, "")] = true
		}
	}

	for _, key := range viper.AllKeys() {
		if strings.HasPrefix(key, prefix) {
			keys[strings.ReplaceAll(key, prefix, "")] = true
		}
	}

	keySlice := make([]string, 0, len(keys))
	for k := range keys {
		keySlice = append(keySlice, k)
	}
	return keySlice
}

func getBoilerTypeReplacements(typesPackage string) []boilingcore.TypeReplace {
	dbTypeMappedToCustomGoType := map[string]string{
		"text":                        "types.String",
		"boolean":                     "types.Bool",
		"date":                        "types.Date",
		"timestamp without time zone": "types.Timestamp",
		"timestamp with time zone":    "types.Timestamp",
		"time":                        "types.Time",
		"uuid":                        "types.UUID",
		"integer":                     "types.Int",
		"smallint":                    "types.Int16",
		"bigint":                      "types.Int64",
		"jsonb":                       "types.JSON",
		"json":                        "types.JSON",
		"character varying":           "types.String",
	}

	// Init an array of type replacements with Type.string to Type.types.String,
	// since enums are generated as Type.string and a custom DBType which we do not know of.
	boilerTypeReplacements := []boilingcore.TypeReplace{
		{
			Match:   drivers.Column{Type: "string", Nullable: true},
			Replace: drivers.Column{Type: "types.String"},
			Imports: importers.Set{ThirdParty: importers.List{formatPkgImportWithAlias(typesPackage, "types")}},
		},
		{
			Match:   drivers.Column{Type: "string", Nullable: false},
			Replace: drivers.Column{Type: "types.String"},
			Imports: importers.Set{ThirdParty: importers.List{formatPkgImportWithAlias(typesPackage, "types")}},
		},
	}

	// Append all known db types to our custom go types
	for dbType, customGoType := range dbTypeMappedToCustomGoType {
		boilerTypeReplacements = append(boilerTypeReplacements, boilingcore.TypeReplace{
			Match:   drivers.Column{DBType: dbType, Nullable: true},
			Replace: drivers.Column{Type: customGoType},
			Imports: importers.Set{ThirdParty: importers.List{formatPkgImportWithAlias(typesPackage, "types")}},
		})

		boilerTypeReplacements = append(boilerTypeReplacements, boilingcore.TypeReplace{
			Match:   drivers.Column{DBType: dbType, Nullable: false},
			Replace: drivers.Column{Type: customGoType},
			Imports: importers.Set{ThirdParty: importers.List{formatPkgImportWithAlias(typesPackage, "types")}},
		})
	}

	return boilerTypeReplacements
}

func formatPkgImport(pkg string) string {
	return fmt.Sprintf("\"%s\"", pkg)
}

func formatPkgImportWithAlias(pkg, expectedAlias string) string {
	if strings.HasSuffix(pkg, "/"+expectedAlias) {
		return fmt.Sprintf("\"%s\"", pkg)
	}
	return fmt.Sprintf("%s \"%s\"", expectedAlias, pkg)
}
