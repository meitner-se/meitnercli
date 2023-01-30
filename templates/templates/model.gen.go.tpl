{{- $alias := .Aliases.Table .Table.Name -}}

// {{$alias.UpSingular}} is the service model representation of the {{ .Table.Name }}-table
type {{$alias.UpSingular}} struct {
    {{- range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}
        {{- $orig_col_name := $column.Name -}}
        {{- range $column.Comment | splitLines -}}
        {{end -}}
        {{$colAlias}} {{$column.Type}}
    {{end -}}

    {{- range $rel := .Table.ToManyRelationships -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        {{ $relAlias.Local | singular }}IDs []types.UUID
    {{end -}}{{- /* range relationships */ -}}
}

// {{$alias.UpSingular}}ValidateBusinessFunc should be used to run business logic for the {{$alias.UpSingular}}-entity,
// it will be passed as an argument to the validate-method which is auto-generated from the database schema.
type {{$alias.UpSingular}}ValidateBusinessFunc func(o {{$alias.UpSingular}}, isUpdate bool) error

// Validate is auto-generated from the database schema and should be executed before any manipulation of the {{$alias.UpSingular}}-entity
func (o {{$alias.UpSingular}}) Validate(isUpdate bool, validateBusinessFunc {{$alias.UpSingular}}ValidateBusinessFunc) error {
    errFields := errors.NewErrFields()
    {{range $column := .Table.Columns -}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{- if ne "jsonb" $column.DBType}}
            {{- if or (eq $column.Name "created_at") (eq $column.Name "updated_at") (eq $column.Name "created_by") (eq $column.Name "updated_by") }}
                if o.{{$colAlias}}.IsDefined() {
                    errFields.Unknown(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}).WithValue(o.{{$colAlias}})) // {{$colAlias}} should not be defined by a user, will be set by repository
                }
            {{- else }}
            {{- if not $column.Nullable}}
                {{- if not (containsAny $.Table.PKey.Columns $column.Name) }}
                    // Non-nullable columns must be defined on Create
                    if !isUpdate && !o.{{$colAlias}}.IsDefined() {
                        errFields.CannotBeUndefined(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}))
                    }
                {{ end }}

                // If the column is defined, make sure it isn't nil
                if o.{{$colAlias}}.IsDefined() && o.{{$colAlias}}.IsNil() {
                    errFields.CannotBeNull(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}))
                }
            {{end}}

            {{- if (isEnumDBType .DBType) }}
                if !o.{{$colAlias}}.IsNil() && !o.{{$colAlias}}.IsValid() {
                    errFields.InvalidValue(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}).WithValue(o.{{$colAlias}}))
                }
            {{ end }}
            {{ end }}
        {{- end}}
    {{end -}}

	if err := validateBusinessFunc(o, isUpdate); err != nil {
        if !errors.IsErrFields(err) {
            return err
        }
        
        businessErrFields := errors.ErrFieldsFrom(err)
		for _, errField := range *businessErrFields {
			errFields.Add(errField)
		}
    }

	if errFields.NotEmpty() {
		return errors.NewBadRequest(errors.MessageValidationFailedForEntity("{{$alias.DownSingular}}"), *errFields...)
	}

	return nil
}

const (
    {{- range $column := .Table.Columns -}}
    {{- $colAlias := $alias.Column $column.Name -}}
        {{$alias.UpSingular}}Column{{$colAlias}} string = "{{$colAlias}}"
    {{end -}}
    {{- range $rel := .Table.ToManyRelationships -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        {{- if not (hasSuffix "Logs" $relAlias.Local) -}}
            {{$alias.UpSingular}}Column{{ $relAlias.Local | singular }}IDs string = "{{ $relAlias.Local | singular }}IDs"
        {{ end -}}
    {{end -}}{{- /* range relationships */ -}}
)

func {{$alias.UpSingular}}Columns() []string {
    return []string{
    {{- range $column := .Table.Columns -}}
    {{- $colAlias := $alias.Column $column.Name -}}
        {{$alias.UpSingular}}Column{{$colAlias}},
    {{end -}}
    {{- range $rel := .Table.ToManyRelationships -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        {{- if not (hasSuffix "Logs" $relAlias.Local) -}}
            {{$alias.UpSingular}}Column{{ $relAlias.Local | singular }}IDs,
        {{ end -}}
    {{end -}}{{- /* range relationships */ -}}
    }
}

// {{$alias.UpSingular}}FromStringsConversionFunc is a type definition for a conversion function that helps to convert a slice of strings into a {{$alias.UpSingular}}-struct.
//
// Is used as an input argument for the generated function: "{{$alias.UpSingular}}FromStrings" (which converts the default fields), but the conversion func should be used to convert the custom values.
// For example a slice that contains UserIdentityNumbers can be converted to UserIDs of the object, using human IDs instead of logic IDs.
//
// This function makes it easy to import the data from a CSV file or other similar format and convert it into a {{$alias.UpSingular}}-struct.
type {{$alias.UpSingular}}FromStringsConversionFunc func({{$alias.DownSingular}} *{{$alias.UpSingular}}, fields, values []string) error

// {{$alias.UpSingular}}FromStrings creates a new {{$alias.UpSingular}} struct and initializes its fields with values from the values slice, 
// using the fields slice to match the correct value to the correct field in the struct.
//
// It returns the created struct and errors that occur during parsing. It is assumed that fields and values slices have the same size.
func {{$alias.UpSingular}}FromStrings(fields, values []string, conversionFunc {{$alias.UpSingular}}FromStringsConversionFunc) (*{{$alias.UpSingular}}, error) {
    // Function to extract the field index by the field name,
    // index will be used to get the value to parse for the field.
    extractFieldIndexByName := func(name string) (int, bool) {
        for i := range fields {
            if fields[i] == name {
                return i, true
            }
        }
        return -1, false
    }

    // Store all of the errors gotten when parsing the values to its corresponding type
    errFields := errors.NewErrFields()

    // Initialize a variable for the {{$alias.UpSingular}}-object,
    // by default, all of the fields will be undefined.
    var {{$alias.DownSingular}} {{$alias.UpSingular}}

    {{ range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}

        // If we get an index of the field for this column, means that we need to set the value to the struct-field. 
        if index, ok := extractFieldIndexByName({{$alias.UpSingular}}Column{{$colAlias}}); ok {
            {{- if (isEnumDBType .DBType) -}}
                {{$alias.DownSingular}}.{{$colAlias}} = {{ parseEnumName $column.DBType | titleCase }}FromString(types.NewStringFromPtr(nil)) // Start by setting the value to nil before trying to parse the row value 
            {{- else }}
                {{$alias.DownSingular}}.{{$colAlias}} = types.New{{ strip_prefix $column.Type "types." }}FromPtr(nil)  // Start by setting the value to nil before trying to parse the row value 
            {{- end }}

            // If the string isn't empty, parse it and set the new value
            if values[index] != "" {
                {{- if (isEnumDBType .DBType) -}}
                    parsed, err := types.StringFromString(values[index])
                    if err != nil {
                        errFields.InvalidValue(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}).WithValue(values[index]))
                    }
                    {{$alias.DownSingular}}.{{$colAlias}} = {{ parseEnumName $column.DBType | titleCase }}FromString(parsed)
                {{- else }}
                    parsed, err := {{$column.Type}}FromString(values[index])
                    if err != nil {
                        errFields.InvalidValue(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}).WithValue(values[index]))
                    }
                    {{$alias.DownSingular}}.{{$colAlias}} = parsed
                {{- end }}
            }
        }
    {{end -}}

	if err := conversionFunc(&{{$alias.DownSingular}}, fields, values); err != nil {
        if !errors.IsErrFields(err) {
            return nil, err
        }
        
        conversionErrFields := errors.ErrFieldsFrom(err)
		for _, errField := range *conversionErrFields {
			errFields.Add(errField)
		}
    }

	if errFields.NotEmpty() {
		return nil, errors.NewBadRequest(errors.MessageValidationFailedForEntity("{{$alias.DownSingular}}"), *errFields...) // TODO : Change error message
	}

    return &{{$alias.DownSingular}}, nil
}

// {{$alias.UpPlural}}ToStringsConversionFunc helps to convert a slice of {{$alias.UpSingular}}-pointers into a export-friendly format of fields and rows. 
//
// Is used as an input argument for the generated function: "{{$alias.UpPlural}}ToStrings" (which maps the default values), but the conversion func should be used to map custom values.
// For example a struct that contains UserIDs can instead be mapped to UserIdentityNumbers, using human IDs instead of logic IDs.
//
// The function takes in a slice of strings representing the fields, and a 2D slice of strings representing the rows as input,
// returns the updated slices of fields and rows, and an error if one occurs during the conversion process. 
//
// This function makes it easy to export the {{$alias.UpSingular}} data to a CSV file or other similar format.
type {{$alias.UpPlural}}ToStringsConversionFunc func(fields []string, rows [][]string) ([]string, [][]string, error)

// {{$alias.UpPlural}}ToStrings converts a slice of {{$alias.UpSingular}} struct pointers into a slice of strings and a slice of slices of strings that can be used to export the data to a CSV file.
// The function then removes headers that aren't used in the structs and creates a 2D slice of strings with the data of each struct.
func {{$alias.UpPlural}}ToStrings({{$alias.DownPlural}} []*{{$alias.UpSingular}}, conversionFunc {{$alias.UpPlural}}ToStringsConversionFunc) ([]string, [][]string, error) {
    // initialize a slice of all columns as fields
    fields := []string{
        {{ range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}
            {{$alias.UpSingular}}Column{{$colAlias}},
        {{end -}}
    }

    // create a map to know which fields that are actually used
    fieldMap := make(map[string]struct{})
    for _, o := range {{$alias.DownPlural}} {
        {{ range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}
            if o.{{$colAlias}}.IsDefined() {
                fieldMap[{{$alias.UpSingular}}Column{{$colAlias}}] = struct{}{}
            }
        {{end -}}
    }

    // remove all of the unused fields
    for i := range fields {
        if _, ok := fieldMap[fields[i]]; !ok {
            fields = append(fields[:i], fields[i+1:]...)
        }
    }

    // Function to extract the index of a field, this will be used to set correct values of the rows
    extractIndexByField := func(field string) (int, bool) {
        for i := range fields {
            if fields[i] == field {
                return i, true
            }
        }
        return -1, false
    }

    rows := make([][]string, len({{$alias.DownPlural}}))
    for i, o := range {{$alias.DownPlural}} {
        values := make([]string, len(fields))
        
        {{ range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}
            if o.{{$colAlias}}.IsDefined() {
                index, ok := extractIndexByField({{$alias.UpSingular}}Column{{$colAlias}})
                if !ok {
                    return nil, nil, errors.New("cannot get index by field, should not happen: "+ {{$alias.UpSingular}}Column{{$colAlias}})
                }
                values[index] = o.{{$colAlias}}.{{- if (isEnumDBType .DBType) }}String.{{end}}String()
            }
        {{end -}}

        rows[i] = values
    }


    return conversionFunc(fields, rows)
}

{{$once := onceNew}}
{{$onceNull := onceNew}}
    {{- range $col := .Table.Columns | filterColumnsByEnum -}}
        {{- $name := parseEnumName $col.DBType -}}
        {{- $vals := parseEnumVals $col.DBType -}}
        {{- $isNamed := ne (len $name) 0}}
        {{- $enumName := "" -}}
        {{- if not (and
            $isNamed
            (and
                ($once.Has $name)
                ($onceNull.Has $name)
            )
        ) -}}
            {{- if gt (len $vals) 0}}
                {{- if $isNamed -}}
                    {{ $enumName = titleCase $name}}
                {{- else -}}
                    {{ $enumName = printf "%s%s" (titleCase .Table.Name) (titleCase $col.Name)}}
                {{- end -}}
                {{/* First iteration for enum type $name (nullable or not) */}}
                {{- $enumFirstIter := and
                    (not ($once.Has $name))
                    (not ($onceNull.Has $name))
                -}}

                {{- if $enumFirstIter -}}
                    {{$enumType := "string" }}
                    {{$allvals := "\n"}}

                    {{if $.AddEnumTypes}}
                        {{- $enumType = $enumName -}}
                        type {{$enumName}} struct { types.String }
                    {{end}}

                    // Enum values for {{$enumName}}
                    {{range $val := $vals -}}
                        {{- $enumValue := titleCase $val -}}
                        func {{$enumName}}{{$enumValue}}() {{$enumType}} { return {{$enumType}}{types.NewString({{printf "%q" $val}})} }
                    {{end }}
                    
                    func {{$enumName}}FromString(s types.String) {{$enumType}} { return {{$enumType}}{String: s} }

                    {{range $val := $vals -}}
                        {{- $enumValue := titleCase $val -}}
                        func (e {{$enumName}}) Is{{ $val }}() bool { return e.String.String() == {{printf "%q" $val}} }
                    {{end -}}

                {{- end -}}

                {{if $.AddEnumTypes}}
                    {{ if $enumFirstIter }}
                        func (e {{$enumName}}) IsValid() bool {
                            {{- /* $first is being used to add a comma to all enumValues, but the first one.*/ -}}
                            {{- $first := true -}}
                            {{- /* $enumValues will contain a comma separated string holding all enum consts */ -}}
                            {{- $enumValues := "" -}}
                            {{ range $val := $vals -}}
                                {{- if $first -}}
                                    {{- $first = false -}}
                                {{- else -}}
                                    {{- $enumValues = printf "%s%s" $enumValues ", " -}}
                                {{- end -}}

                                {{- $enumValue := titleCase $val -}}
                                {{- $enumValues = printf "%s%s%s()" $enumValues $enumName $enumValue -}}
                            {{- end}}
                            switch e {
                            case {{$enumValues}}:
                                return true
                            default:
                                return false
                            }
                        }
                    {{- end -}}

                    {{ if and
                        $col.Nullable
                        (not ($onceNull.Has $name))
                    }}
                        {{$enumType := ""}}
                        {{- if $isNamed -}}
                            {{- $enumType = (print $.EnumNullPrefix $enumName) }}
                        {{- else -}}
                            {{- $enumType = printf "%s%s" (titleCase .Table.Name) (print $.EnumNullPrefix (titleCase $col.Name)) -}}
                        {{- end -}}
                        // {{$enumType}} is a nullable {{$enumName}} enum type. It supports SQL and JSON serialization.
                        type {{$enumType}} struct {
                            Val        {{$enumName}}
                            Valid    bool
                        }

                        // {{$enumType}}From creates a new {{$enumName}} that will never be blank.
                        func {{$enumType}}From(v {{$enumName}}) {{$enumType}} {
                            return New{{$enumType}}(v, true)
                        }

                        // {{$enumType}}FromPtr creates a new {{$enumType}} that be null if s is nil.
                        func {{$enumType}}FromPtr(v *{{$enumName}}) {{$enumType}} {
                            if v == nil {
                                return New{{$enumType}}("", false)
                            }
                            return New{{$enumType}}(*v, true)
                        }

                        // New{{$enumType}} creates a new {{$enumType}}
                        func New{{$enumType}}(v {{$enumName}}, valid bool) {{$enumType}} {
                            return {{$enumType}}{
                                Val:    v,
                                Valid:  valid,
                            }
                        }

                        // UnmarshalJSON implements json.Unmarshaler.
                        func (e *{{$enumType}}) UnmarshalJSON(data []byte) error {
                            if bytes.Equal(data, null.NullBytes) {
                                e.Val = ""
                                e.Valid = false
                                return nil
                            }

                            if err := json.Unmarshal(data, &e.Val); err != nil {
                                return err
                            }

                            e.Valid = true
                            return nil
                        }

                        // MarshalJSON implements json.Marshaler.
                        func (e {{$enumType}}) MarshalJSON() ([]byte, error) {
                            if !e.Valid {
                                return null.NullBytes, nil
                            }
                            return json.Marshal(e.Val)
                        }

                        // MarshalText implements encoding.TextMarshaler.
                        func (e {{$enumType}}) MarshalText() ([]byte, error) {
                            if !e.Valid {
                                return []byte{}, nil
                            }
                            return []byte(e.Val), nil
                        }

                        // UnmarshalText implements encoding.TextUnmarshaler.
                        func (e *{{$enumType}}) UnmarshalText(text []byte) error {
                            if text == nil || len(text) == 0 {
                                e.Valid = false
                                return nil
                            }

                            e.Val = {{$enumName}}(text)
                            e.Valid = true
                            return nil
                        }

                        // SetValid changes this {{$enumType}} value and also sets it to be non-null.
                        func (e *{{$enumType}}) SetValid(v {{$enumName}}) {
                            e.Val = v
                            e.Valid = true
                        }

                        // Ptr returns a pointer to this {{$enumType}} value, or a nil pointer if this {{$enumType}} is null.
                        func (e {{$enumType}}) Ptr() *{{$enumName}} {
                            if !e.Valid {
                                return nil
                            }
                            return &e.Val
                        }

                        // IsZero returns true for null types.
                        func (e {{$enumType}}) IsZero() bool {
                            return !e.Valid
                        }

                        // Scan implements the Scanner interface.
                        func (e *{{$enumType}}) Scan(value interface{}) error {
                            if value == nil {
                                e.Val, e.Valid = "", false
                                return nil
                            }
                            e.Valid = true
                            return convert.ConvertAssign((*string)(&e.Val), value)
                        }

                        // Value implements the driver Valuer interface.
                        func (e {{$enumType}}) Value() (driver.Value, error) {
                            if !e.Valid {
                                return nil, nil
                            }
                            return string(e.Val), nil
                        }
                    {{end -}}
                {{end -}}
            {{else}}
                // Enum values for {{.Table.Name}} {{$col.Name}} are not proper Go identifiers, cannot emit constants
            {{- end -}}
            {{/* Save column type name after generation.
             Needs to be at the bottom because we check for the first iteration
             inside the .Table.Columns loop. */}}
            {{- if $isNamed -}}
                {{- if $col.Nullable -}}
                    {{$_ := $onceNull.Put $name}}
                {{- else -}}
                    {{$_ := $once.Put $name}}
                {{- end -}}
            {{- end -}}
        {{- end -}}
    {{- end }}

func New{{$alias.UpSingular}}Query() {{$alias.UpSingular}}Query {
    return {{$alias.UpSingular}}Query{}
}

type {{$alias.UpSingular}}Query struct {
    // Nested queries, if any. 
    // Use OrCondition-field to define if the nested query should be wrapped in an AND or OR-statement.
    Nested []{{$alias.UpSingular}}QueryNested

    // Params for the query
    Params {{$alias.UpSingular}}QueryParams

    // Selected fields for the query, leave nil for all fields.
    SelectedFields *{{$alias.UpSingular}}QuerySelectedFields

    // Inner join with related tables
    Join *{{$alias.UpSingular}}QueryJoin

    // Load the IDs of the relations
    Load *{{$alias.UpSingular}}QueryLoad

    // To order by specific columns, by default we will always primary keys first as ascending
    OrderBy *{{$alias.UpSingular}}QueryOrderBy
    
    // OrCondition is used to define if the condition should use AND or OR between the params
    //
    // When true, the condition will have OR between the params, otherwise AND.
    OrCondition types.Bool

    // OrConditionNested is used to define if the nested query should be wrapped in an AND or OR clause.
    //
    // When true, the nested clause will be wrapped with OR, otherwise AND.
    OrConditionNested types.Bool

    // Offset into the results
    Offset types.Int

    // Limit the number of returned rows
    Limit types.Int
}

type {{$alias.UpSingular}}QuerySelectedFields struct {
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
            {{$colAlias}} types.Bool
    {{- end}}
}

type {{$alias.UpSingular}}QueryNested struct {
    // Nested queries, if any. 
    // Use OrCondition-field to define if the nested query should be wrapped in an AND or OR-statement.
    Nested *{{$alias.UpSingular}}QueryNested

    // Params for the query
    Params {{$alias.UpSingular}}QueryParams
    
    // OrCondition is used to define if the condition should use AND or OR between the params
    //
    // When true, the condition will have OR between the params, otherwise AND.
    OrCondition types.Bool

    // OrConditionNested is used to define if the nested query should be wrapped in an AND or OR clause.
    //
    // When true, the nested clause will be wrapped with OR, otherwise AND.
    OrConditionNested types.Bool
}

type {{$alias.UpSingular}}QueryParams struct {
    Equals    *{{$alias.UpSingular}}QueryParamsFields
    NotEquals *{{$alias.UpSingular}}QueryParamsFields

    Empty    *{{$alias.UpSingular}}QueryParamsNullableFields
    NotEmpty *{{$alias.UpSingular}}QueryParamsNullableFields

    In    *{{$alias.UpSingular}}QueryParamsInFields
    NotIn *{{$alias.UpSingular}}QueryParamsInFields

    GreaterThan *{{$alias.UpSingular}}QueryParamsComparableFields
    SmallerThan *{{$alias.UpSingular}}QueryParamsComparableFields

    SmallerOrEqual *{{$alias.UpSingular}}QueryParamsComparableFields
    GreaterOrEqual *{{$alias.UpSingular}}QueryParamsComparableFields

    Like    *{{$alias.UpSingular}}QueryParamsLikeFields
    NotLike *{{$alias.UpSingular}}QueryParamsLikeFields
}

func New{{$alias.UpSingular}}QueryParamsFields() *{{$alias.UpSingular}}QueryParamsFields {
    return &{{$alias.UpSingular}}QueryParamsFields{}
}

type {{$alias.UpSingular}}QueryParamsFields struct {
    {{- range $column := .Table.Columns}}
        {{- $colAlias := $alias.Column $column.Name}}
        {{$colAlias}} {{$column.Type}}
    {{- end}}
}

func New{{$alias.UpSingular}}QueryParamsNullableFields() *{{$alias.UpSingular}}QueryParamsNullableFields {
    return &{{$alias.UpSingular}}QueryParamsNullableFields{}
}

type {{$alias.UpSingular}}QueryParamsNullableFields struct {
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if $column.Nullable -}}
            {{$colAlias}} types.Bool
        {{- end}}
    {{- end}}
}

func New{{$alias.UpSingular}}QueryParamsInFields() *{{$alias.UpSingular}}QueryParamsInFields {
    return &{{$alias.UpSingular}}QueryParamsInFields{}
}

type {{$alias.UpSingular}}QueryParamsInFields struct {
    {{- range $column := .Table.Columns}}

        {{- $colAlias := $alias.Column $column.Name}}
        
        {{- $stringTypes := "types.String, types.UUID, types.Timestamp, types.Date" -}}
        
        {{- if or (contains $column.Type $stringTypes) (hasPrefix "types.Int" $column.Type) }}
            {{$colAlias}} []{{$column.Type}}
        {{end -}}

    {{- end}}
}

func New{{$alias.UpSingular}}QueryParamsComparableFields() *{{$alias.UpSingular}}QueryParamsComparableFields {
    return &{{$alias.UpSingular}}QueryParamsComparableFields{}
}

type {{$alias.UpSingular}}QueryParamsComparableFields struct {
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if or (hasPrefix "date" $column.DBType) (hasPrefix "int" $column.DBType) (hasPrefix "time" $column.DBType) -}}
            {{$colAlias}} {{$column.Type}}
        {{- end}}
    {{- end}}
}

func New{{$alias.UpSingular}}QueryParamsLikeFields() *{{$alias.UpSingular}}QueryParamsLikeFields {
    return &{{$alias.UpSingular}}QueryParamsLikeFields{}
}

type {{$alias.UpSingular}}QueryParamsLikeFields struct {
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{- if eq "types.String" $column.Type }}
            {{$colAlias}} {{$column.Type}}
        {{- end}}
    {{- end}}
}

type {{$alias.UpSingular}}QueryLoad struct {
    {{- range $rel := .Table.ToManyRelationships -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName }}
        {{ $relAlias.Local | singular }} *{{$alias.UpSingular}}QueryLoad{{ $relAlias.Local | singular }}
    {{- end }}{{- /* range relationships */ -}}
}

{{ range $rel := .Table.ToManyRelationships }}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
    type {{$alias.UpSingular}}QueryLoad{{ $relAlias.Local | singular }} struct {
            // Params for the load
            Params {{ $relAlias.Local | singular }}QueryParams

            // OrCondition is used to define if the condition should use AND or OR between the params
            //
            // When true, the condition will have OR between the params, otherwise AND.
            OrCondition types.Bool

            // Offset into the results
            Offset types.Int

            // Limit the number of returned rows
            Limit types.Int
    }
{{ end }}{{- /* range relationships */ -}}

type {{$alias.UpSingular}}QueryJoin struct {
    {{- range $rel := .Table.ToManyRelationships -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName }}
        {{ $relAlias.Local | singular }} *{{$alias.UpSingular}}QueryJoin{{ $relAlias.Local | singular }}
    {{- end }}{{- /* range relationships */ -}}
}

{{ range $rel := .Table.ToManyRelationships -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
    type {{$alias.UpSingular}}QueryJoin{{ $relAlias.Local | singular }} struct {
            // Params for the query
            Params {{ $relAlias.Local | singular }}QueryParams

            // OrCondition is used to define if the condition should use AND or OR between the params
            //
            // When true, the condition will have OR between the params, otherwise AND.
            OrCondition types.Bool
    }
{{end -}}{{- /* range relationships */ -}}

type {{$alias.UpSingular}}QueryOrderBy struct {
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
            {{$colAlias}} *{{$alias.UpSingular}}QueryOrderByField
    {{- end}}
}

type {{$alias.UpSingular}}QueryOrderByField struct {
    Index int
    Desc bool
}
