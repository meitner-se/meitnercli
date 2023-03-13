package boilerconfig

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
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
			"getColumnMetadata":             getColumnMetadata,
			"getColumnNameFileURL":          getColumnNameFileURL,
			"getTableColumnOrder":           getTableColumnOrder,
			"getTableOrderByColumns":        getTableOrderByColumns,
			"getTableRichTextContents":      getTableRichTextContents,
			"getServiceName":                func() string { return serviceName },
			"stripPrefix":                   strings.TrimPrefix,
			"tableHasCustomConversion":      tableHasCustomConversion,
			"tableHasFile":                  tableHasFile,
		},
	}

	return config, nil
}

// getTableRichTextContents reads all columns in the given table and check if there should be any rich text content.
//
// If a column should be rich text content, we will create "richTextContentNames", which will be used by the templates to generate structs in the API-layer.
//
// The comments should look something like this:
//
//	COMMENT ON COLUMN organization.description_content      IS 'rich_text_content:content'
//	COMMENT ON COLUMN organization.description_content_type IS 'rich_text_content:content_type'
//	COMMENT ON COLUMN organization.description_converter    IS 'rich_text_content:converter'
//	COMMENT ON COLUMN organization.description_text         IS 'rich_text_content:text'
//
// The naming will be the column name with the table name as prefix and RichTextContent as suffix.
// Example: OrganizationDescriptionRichTextContent
//
// The function also makes sure that all the values for rich text content are correct.
func getTableRichTextContents(t drivers.Table) map[string]string {
	richTextContentNames := map[string]string{}

	for _, c := range t.Columns {
		comments := strings.Split(c.Comment, " | ")

		for _, comment := range comments {
			if !strings.HasPrefix(comment, "rich_text_content:") {
				continue
			}

			richTextContentColumn := strings.TrimPrefix(comment, "rich_text_content:")

			switch richTextContentColumn {
			case "content", "content_type", "converter", "text":
				// OK
			default:
				panic("invalid rich text content column " + c.Name + " " + comment)
			}

			fieldName := strmangle.TitleCase(strings.TrimSuffix(c.Name, "_"+richTextContentColumn))

			structName := fmt.Sprintf("%s%sRichTextContent",
				strmangle.TitleCase(t.Name),
				fieldName,
			)

			richTextContentNames[fieldName] = structName
		}
	}

	return richTextContentNames
}

type ColumnMetadata struct {
	Comments   []string
	IsFile     bool
	IsRichText bool
	Sort       *ColumnMetadataForSort
	Validate   ColumnMetadataForValidation
}

func (c ColumnMetadata) CustomConversion() bool {
	return c.IsRichText
}

type ColumnMetadataForSort struct {
	Order int
	Desc  bool
}

func getColumnMetadata(c drivers.Column) ColumnMetadata {
	var columnMetadata ColumnMetadata

	for _, comment := range strings.Split(c.Comment, " | ") {
		if comment == "" {
			continue
		}

		if strings.HasPrefix(comment, "comment:") {
			columnMetadata.Comments = append(columnMetadata.Comments, strings.TrimPrefix(comment, "comment:"))
			continue
		}

		if strings.HasPrefix(comment, "rich_text_content:") {
			columnMetadata.IsRichText = true
			continue // Other stuff is handled in other functions
		}

		if comment == "file" {
			columnMetadata.IsFile = true
			continue
		}

		if strings.HasPrefix(comment, "validate:") {
			columnMetadata.Validate = getColumnMetadataForValidation(strings.TrimPrefix(comment, "validate:"))
			continue
		}

		if strings.HasPrefix(comment, "sort:") {
			sortString := strings.TrimPrefix(comment, "sort:")

			switch sortString {
			case "asc", "desc":
				// valid sort
			default:
				panic("invalid sort")
			}

			if columnMetadata.Sort != nil {
				columnMetadata.Sort.Desc = sortString == "desc"
				continue
			}

			columnMetadata.Sort = &ColumnMetadataForSort{
				Order: 0,
				Desc:  sortString == "desc",
			}

			continue
		}

		if strings.HasPrefix(comment, "order:") {
			orderIndex, err := strconv.Atoi(strings.TrimPrefix(comment, "order:"))
			if err != nil {
				panic("cannot convert order string to integer: " + err.Error())
			}

			if columnMetadata.Sort != nil {
				columnMetadata.Sort.Order = orderIndex
				continue
			}

			columnMetadata.Sort = &ColumnMetadataForSort{
				Order: orderIndex,
				Desc:  false,
			}

			continue
		}

		if comment == "load" {
			continue
		}

		panic("invalid comment for metadata: " + comment)
	}

	if c.Nullable {
		columnMetadata.Comments = append(columnMetadata.Comments, "nullable: true")
	}

	if columnMetadata.Validate.Color {
		columnMetadata.Comments = append(columnMetadata.Comments, "validate: \"color\"")
	}
	if columnMetadata.Validate.CountryCode {
		columnMetadata.Comments = append(columnMetadata.Comments, "validate: \"country_code\"")
	}
	if columnMetadata.Validate.EmailAddress {
		columnMetadata.Comments = append(columnMetadata.Comments, "validate: \"email_address\"")
	}
	if columnMetadata.Validate.LanguageCode {
		columnMetadata.Comments = append(columnMetadata.Comments, "validate: \"language_code\"")
	}
	if columnMetadata.Validate.MunicipalityCode {
		columnMetadata.Comments = append(columnMetadata.Comments, "validate: \"municipality_code\"")
	}
	if columnMetadata.Validate.PhoneNumber {
		columnMetadata.Comments = append(columnMetadata.Comments, "validate: \"phone_number\"")
	}
	if columnMetadata.Validate.TimeZone {
		columnMetadata.Comments = append(columnMetadata.Comments, "validate: \"time_zone\"")
	}
	if columnMetadata.Validate.URL {
		columnMetadata.Comments = append(columnMetadata.Comments, "validate: \"url\"")
	}

	if drivers.IsEnumDBType(c.DBType) {
		columnMetadata.Comments = append(columnMetadata.Comments, "type: \"types.String\"")
	} else {
		columnMetadata.Comments = append(columnMetadata.Comments, fmt.Sprintf("type: \"%s\"", c.Type))
	}

	return columnMetadata
}

// getColumnNameFileURL takes a column alias for a file,
// the alias should have ID as a suffix which will be replaced with URL.
//
// For example, BackgroundLogoFileID will be returned as BackgroundLogoFileURL.
func getColumnNameFileURL(columnAlias string) string {
	return strings.TrimSuffix(columnAlias, "ID") + "URL"
}

type ColumnOrder struct {
	Column drivers.Column
	Desc   bool
}

func getTableColumnOrder(t drivers.Table) []ColumnOrder {
	orderByMap := make(map[int]ColumnOrder)
	for _, c := range t.Columns {
		metadata := getColumnMetadata(c)

		if metadata.Sort != nil {
			orderByMap[metadata.Sort.Order] = ColumnOrder{
				Column: c,
				Desc:   metadata.Sort.Desc,
			}
		}
	}

	columnOrder := []ColumnOrder{}
	for i := range t.Columns {
		orderByColumn, ok := orderByMap[i]
		if !ok {
			continue
		}

		columnOrder = append(columnOrder, orderByColumn)
	}

	// Always order by created_at if it exists
	for _, c := range t.Columns {
		if c.Name == "created_at" {
			columnOrder = append(columnOrder, ColumnOrder{
				Column: c,
				Desc:   false,
			})
		}
	}

	return columnOrder
}

func getTableOrderByColumns(t drivers.Table) []string {
	columnOrder := getTableColumnOrder(t)

	orderByColumns := make([]string, len(columnOrder))
	for i := range columnOrder {
		sort := "asc"

		if columnOrder[i].Desc {
			sort = "desc"
		}

		orderByColumns[i] = fmt.Sprintf("%s.%s %s",
			t.Name,
			columnOrder[i].Column.Name,
			sort,
		)
	}

	return orderByColumns
}

type ColumnMetadataForValidation struct {
	Color            bool
	CountryCode      bool
	EmailAddress     bool
	LanguageCode     bool
	MunicipalityCode bool
	PhoneNumber      bool
	TimeZone         bool
	URL              bool
}

func getColumnMetadataForValidation(validate string) ColumnMetadataForValidation {
	var columnMetadataForValidation ColumnMetadataForValidation

	switch validate {
	case "color":
		columnMetadataForValidation.Color = true
	case "country_code":
		columnMetadataForValidation.CountryCode = true
	case "email_address":
		columnMetadataForValidation.EmailAddress = true
	case "language_code":
		columnMetadataForValidation.LanguageCode = true
	case "municipality_code":
		columnMetadataForValidation.MunicipalityCode = true
	case "phone_number":
		columnMetadataForValidation.PhoneNumber = true
	case "time_zone":
		columnMetadataForValidation.TimeZone = true
	case "url":
		columnMetadataForValidation.URL = true
	default:
		panic("invalid validation: " + validate)
	}

	return columnMetadataForValidation
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

func tableHasCustomConversion(t drivers.Table) bool {
	for _, c := range t.Columns {
		if getColumnMetadata(c).CustomConversion() {
			return true
		}
	}

	return false
}

func tableHasFile(t drivers.Table) bool {
	for _, c := range t.Columns {
		if getColumnMetadata(c).IsFile {
			return true
		}
	}

	return false
}
