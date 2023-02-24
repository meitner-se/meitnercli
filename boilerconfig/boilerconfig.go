package boilerconfig

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/friendsofgo/errors"
	"github.com/spf13/viper"
	"github.com/volatiletech/sqlboiler/v4/boilingcore"
	"github.com/volatiletech/sqlboiler/v4/drivers"
	"github.com/volatiletech/sqlboiler/v4/importers"
	"github.com/volatiletech/strmangle"
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

func GetConfig(driverName, configFile, serviceName, typesPackage string) (*boilingcore.Config, error) {
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
		CustomTemplateFuncs: template.FuncMap{
			"getLoadRelations":              getLoadRelations,
			"getLoadRelationStatement":      getLoadRelationStatement,
			"getLoadRelationName":           getLoadRelationName,
			"getLoadRelationColumn":         getLoadRelationColumn,
			"getLoadRelationTableColumn":    getLoadRelationTableColumn,
			"getLoadRelationType":           getLoadRelationType,
			"getLoadRelations_enum_columns": getLoadRelationsEnumColumns,
			"getServiceName":                func() string { return serviceName },
			"stripPrefix":                   strings.TrimPrefix,
			"columnIsColor":                 func(c drivers.Column) bool { return strings.Contains(c.Comment, "color") },
			"columnIsCountryCode":           func(c drivers.Column) bool { return strings.Contains(c.Comment, "country_code") },
			"columnIsEmailAddress":          func(c drivers.Column) bool { return strings.Contains(c.Comment, "email_address") },
			"columnIsMunicipalityCode":      func(c drivers.Column) bool { return strings.Contains(c.Comment, "municipality_code") },
			"columnIsPhoneNumber":           func(c drivers.Column) bool { return strings.Contains(c.Comment, "phone_number") },
			"columnIsTimeZone":              func(c drivers.Column) bool { return strings.Contains(c.Comment, "time_zone") },
			"columnIsURL":                   func(c drivers.Column) bool { return strings.Contains(c.Comment, "url") },
		},
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
		"time without time zone":      "types.Time",
		"time with time zone":         "types.Time",
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
			Match:   drivers.Column{Type: "string", Nullable: false},
			Replace: drivers.Column{Type: "types.String"},
			Imports: importers.Set{ThirdParty: importers.List{formatPkgImportWithAlias(typesPackage, "types")}},
		},
		{
			Match:   drivers.Column{Type: "null.String", Nullable: true},
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

func getLoadRelationName(aliases boilingcore.Aliases, rel drivers.ToManyRelationship) string {
	tableAlias := aliases.ManyRelationship(rel.ForeignTable, rel.Name, rel.JoinTable, rel.JoinLocalFKeyName)
	tableAliasLocal := strmangle.TitleCase(tableAlias.Local)

	return strmangle.Singular(tableAliasLocal) + "IDs"
}

func getLoadRelationType(aliases boilingcore.Aliases, tables []drivers.Table, rel drivers.ToManyRelationship, prefix string) string {
	for _, t := range tables {
		if t.Name != rel.ForeignTable {
			continue
		}

		if rel.ToJoinTable {
			return t.GetColumn(rel.ForeignColumn).Type
		}

		for _, column := range t.Columns {
			if column.Name == rel.ForeignColumn {
				continue
			}

			if drivers.IsEnumDBType(column.DBType) {
				return strmangle.TitleCase(column.FullDBType)
			}

			return column.Type
		}
	}

	panic("relation table not found")
}

func getLoadRelationColumn(aliases boilingcore.Aliases, tables []drivers.Table, rel drivers.ToManyRelationship) drivers.Column {
	for _, t := range tables {
		if t.Name != rel.ForeignTable {
			continue
		}

		if rel.ToJoinTable {
			return t.GetColumn(rel.ForeignColumn)
		}

		for _, column := range t.Columns {
			if column.Name == rel.ForeignColumn {
				continue
			}

			return column
		}
	}

	panic("load relation column not found")
}

func getLoadRelationTableColumn(aliases boilingcore.Aliases, tables []drivers.Table, rel drivers.ToManyRelationship) string {
	quoteFunc := func(s string) string { return fmt.Sprintf(`\"%s\"`, s) }

	for _, t := range tables {
		if t.Name != rel.ForeignTable {
			continue
		}

		if rel.ToJoinTable {
			return fmt.Sprintf("%s.%s",
				quoteFunc(rel.JoinTable),
				quoteFunc(rel.JoinForeignColumn),
			)
		}

		for _, column := range t.Columns {
			if column.Name == rel.ForeignColumn {
				continue
			}

			return fmt.Sprintf("%s.%s",
				quoteFunc(rel.ForeignTable),
				quoteFunc(column.Name),
			)
		}
	}

	panic("load relation column not found")
}

func getLoadRelationStatement(aliases boilingcore.Aliases, tables []drivers.Table, rel drivers.ToManyRelationship) string {
	quoteFunc := func(s string) string { return fmt.Sprintf(`\"%s\"`, s) }

	for _, t := range tables {
		if t.Name != rel.ForeignTable {
			continue
		}

		if rel.ToJoinTable {
			return fmt.Sprintf("%s ON %s.%s = %s.%s",
				quoteFunc(rel.JoinTable),
				quoteFunc(rel.Table),
				quoteFunc(rel.ForeignColumn),
				quoteFunc(rel.JoinTable),
				quoteFunc(rel.JoinLocalColumn),
			)
		}

		for _, column := range t.Columns {
			if column.Name == rel.ForeignColumn {
				continue
			}

			return fmt.Sprintf("%s ON %s.%s = %s.%s",
				quoteFunc(t.Name),
				quoteFunc(t.Name),
				quoteFunc(rel.ForeignColumn),
				quoteFunc(rel.Table),
				quoteFunc(rel.Column),
			)
		}
	}

	panic("load relation column not found")
}

func isLoadTable(table drivers.Table, rel drivers.ToManyRelationship) bool {
	if table.Name == rel.JoinTable {
		return strings.Contains(table.GetColumn(rel.JoinForeignColumn).Comment, "load")
	}

	if table.Name == rel.ForeignTable {
		for _, c := range table.Columns {
			if c.Name == rel.ForeignColumn {
				continue
			}

			return strings.Contains(c.Comment, "load")
		}
	}

	return false
}

func getLoadRelations(tables []drivers.Table, fromTable drivers.Table) []drivers.ToManyRelationship {
	var toManyRelationships []drivers.ToManyRelationship

	for _, toManyRelationship := range fromTable.ToManyRelationships {
		for _, t := range tables {
			if !isLoadTable(t, toManyRelationship) {
				continue
			}

			toManyRelationships = append(toManyRelationships, toManyRelationship)
		}
	}

	return toManyRelationships
}

func getLoadRelationsEnumColumns(tables []drivers.Table, fromTable drivers.Table) []drivers.Column {
	var columns []drivers.Column

	for _, toManyRelationship := range fromTable.ToManyRelationships {
		for _, t := range tables {
			if !isLoadTable(t, toManyRelationship) {
				continue
			}

			for _, c := range t.Columns {
				if !strings.Contains(c.Comment, "load") {
					continue
				}

				if !drivers.IsEnumDBType(c.DBType) {
					continue
				}

				columns = append(columns, c)
			}
		}
	}

	return columns
}
