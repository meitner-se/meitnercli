{{- $alias := .Aliases.Table .Table.Name -}}
{{- $colDefs := sqlColDefinitions .Table.Columns .Table.PKey.Columns -}}
{{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap $.StringFuncs.titleCase | stringMap $.StringFuncs.replaceReserved -}}

type {{$alias.UpSingular}}ValidationContext interface {
    {{ range $column := .Table.Columns -}}
    {{- $colAlias := $alias.Column $column.Name -}}
    {{- if not (or (containsAny $pkNames $colAlias) (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
        Get{{$colAlias}}() {{ if and (isEnumDBType .DBType) (.Nullable) }} {{ stripPrefix $column.Type "Null" }} {{ else }} {{$column.Type}} {{ end }}
    {{end -}}
    {{end -}}

    {{- range $rel := getLoadRelations $.Tables .Table -}}
        Get{{ getLoadRelationName $.Aliases $rel }}() []types.UUID
    {{end }}

    // Values returns the current values of the {{$alias.UpSingular}} object which is being validated
    Values() {{$alias.UpSingular}}

    // PreviousValues returns the previous values of the {{$alias.UpSingular}} object which is being updated,
    // IsUpdate needs to return true for the PreviousValues to return any actual values.
    PreviousValues() {{$alias.UpSingular}}

{{ range $column := .Table.Columns -}}
{{- $colAlias := $alias.Column $column.Name -}}
{{- if not (or (containsAny $pkNames $colAlias) (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}

    // {{$colAlias}}HasChangedNotNil returns true if the current value is not nil and has changed from previous value on isUpdate == true
    // or is not nil on isUpdate.
    // should be used to decide if you need to validate a method
    {{$colAlias}}HasChangedNotNil() bool
{{end -}}
{{end -}}
{{- range $rel := getLoadRelations $.Tables .Table -}}

    // {{ getLoadRelationName $.Aliases $rel }}HasChangedNotNil returns true if the current value is not nil and has changed from previous value on isUpdate == true
    // or is not nil on isUpdate.
    // should be used to decide if you need to validate a method
    {{ getLoadRelationName $.Aliases $rel }}HasChangedNotNil() bool
{{end -}}

    // IsUpdate should return true if the validation is made for an update, when false it is validation for insert.
    IsUpdate() bool
}

// {{$alias.UpSingular}} is the service model representation of the {{ .Table.Name }}-table
type {{$alias.UpSingular}} struct {
    {{- range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}
        {{- $orig_col_name := $column.Name -}}
        {{- range $column.Comment | splitLines -}}
        {{end -}}
        {{$colAlias}} {{ if and (isEnumDBType .DBType) (.Nullable) }} {{ stripPrefix $column.Type "Null" }} {{ else }} {{$column.Type}} {{ end }}
    {{end -}}

    {{- range $rel := getLoadRelations $.Tables .Table -}}
        {{ getLoadRelationName $.Aliases $rel }} []{{ getLoadRelationType $.Aliases $.Tables $rel "" }}
    {{end -}}{{- /* range relationships */ -}}
}

func (o *{{$alias.UpSingular}}) mergeUndefinedFields(from *{{$alias.UpSingular}}) {
    {{- range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}
        if !o.{{ $colAlias }}.IsDefined() {
            o.{{ $colAlias }} = from.{{ $colAlias }}
        }
    {{end -}}
    {{- range $rel := getLoadRelations $.Tables .Table -}}
        if o.{{ getLoadRelationName $.Aliases $rel }} == nil {
            o.{{ getLoadRelationName $.Aliases $rel }} = from.{{ getLoadRelationName $.Aliases $rel }}
        }
    {{end -}}{{- /* range relationships */ -}}
}

// {{$alias.UpSingular}}Normalizer is used to normalize the fields of {{$alias.UpSingular}} before validation
// to set custom normalizations, set each field on service initialization.
var {{$alias.UpSingular}}Normalizer = &{{ $alias.DownSingular }}Normalizer{}

// {{$alias.DownSingular}}Normalizer is used to normalize the fields of {{$alias.UpSingular}} before validation
type {{$alias.DownSingular}}Normalizer struct {
    {{ range $column := .Table.Columns -}}
    {{- $colAlias := $alias.Column $column.Name -}}
    {{- if not (or (containsAny $pkNames $colAlias) (eq $column.Type "types.UUID") (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
        {{$colAlias}} func(ctx context.Context, {{$colAlias }} *{{ if and (isEnumDBType .DBType) (.Nullable) }} {{ stripPrefix $column.Type "Null" }} {{ else }} {{$column.Type}} {{ end }}) error
    {{end -}}
    {{end -}}
}

func (v *{{$alias.DownSingular}}Normalizer) Normalize(ctx context.Context, o *{{$alias.UpSingular}}, isUpdate bool) error {
    errFields := errors.NewErrFields()

    // If the object is being created, we need to set the default values for the undefined fields
    if !isUpdate {
        {{- range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}
        {{- $columnMetadata := getColumnMetadata $column -}}
        {{- if not (or (containsAny $pkNames $colAlias) (eq $column.Type "types.UUID") (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
        {{- if not (eq $column.Default "") -}}
            if !o.{{$colAlias}}.IsDefined() {
                {{- if (eq $column.Default "NULL") }}
                    {{- if (isEnumDBType .DBType) }}
                        o.{{$colAlias}} = {{ parseEnumName $column.DBType | titleCase }}FromString(types.NewStringFromPtr(nil))
                    {{ else -}}
                        o.{{$colAlias}} = types.New{{ stripPrefix $column.Type "types." }}FromPtr(nil)
                    {{ end -}}
                {{- else if (eq $column.Default "CURRENT_TIMESTAMP") }}
                    o.{{$colAlias}} = types.New{{ stripPrefix $column.Type "types." }}(time.Now())
                {{- else if (eq $column.Type "types.Bool") }}
                    o.{{$colAlias}} = types.New{{ stripPrefix $column.Type "types." }}({{ $column.Default }})
                {{- else }}
                    "invalid default value for {{$column.Name}}" // should not compile
                {{ end -}}
            }
        {{ end -}}
        {{ end -}}
        {{ end -}}
    }

    {{ range $column := .Table.Columns -}}
    {{- $colAlias := $alias.Column $column.Name -}}
    {{- if not (or (containsAny $pkNames $colAlias) (eq $column.Type "types.UUID") (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
    {{ $columnMetadata := getColumnMetadata $column }}
    {{- if (or ($columnMetadata.Validate.CountryCode) ($columnMetadata.Validate.MunicipalityCode)) }}
        if !o.{{$colAlias}}.IsNil(){
            o.{{$colAlias}} = types.NewString(strings.ToUpper(o.{{$colAlias}}.String()))
        }
    {{ end }}
    {{- if contains "types.String" $column.Type -}}
        if !o.{{$colAlias}}.IsNil(){
            o.{{$colAlias}} = types.NewString(strings.TrimSpace(o.{{$colAlias}}.String()))
            {{- if ($columnMetadata.Validate.PhoneNumber) }}
            o.{{$colAlias}} = normalize.PhoneNumber(o.{{$colAlias}})
            {{ end }}
        }
    {{end -}}

    {{- if (isEnumDBType .DBType) }}
        if !o.{{$colAlias}}.IsNil() {
        {{- $vals := parseEnumVals $column.DBType -}}
        {{range $val := $vals -}}
        {{- $enumValue := titleCase $val -}}
            if strings.ToLower(strings.TrimSpace(o.{{$colAlias}}.String.String())) == strings.ToLower({{printf "%q" $val}}){
                o.{{$colAlias}} = {{stripPrefix $column.Type "Null"}}{types.NewString({{printf "%q" $val}})}
            }
        {{end -}}
        }
    {{ end }}

        if v.{{$colAlias}} != nil {
            err := v.{{$colAlias}}(ctx, &o.{{$colAlias}})
            if err != nil {
                switch v := err.(type){
                case errors.FieldValidationError:
                    if v.Name == ""{
                        v = v.WithName({{$alias.UpSingular}}Column{{$colAlias}})
                    }
                    if v.Value == nil{
                        v = v.WithValue(o.{{$colAlias}})
                    }
                    errFields.Add(v.FieldError())
                case *errors.ErrFields:
                    if v != nil {
                        for _, errField := range *v {
                            errFields.Add(errField)
                        }
                    }
                default:
                    return err
                }
            }
        }
    {{end -}}
    {{end -}}

    // return nil if no errors so it would not be concrete type under error interface.
	if !errFields.NotEmpty(){
		return nil
	}

	return errFields
}

// {{$alias.UpSingular}}Validator is used to validate the fields of {{$alias.UpSingular}}
type {{$alias.UpSingular}}Validator struct {
    // GetFunc is only used on update to get the {{$alias.UpSingular}} and merge all the undefined values for convenience on validation
    GetFunc func(ctx context.Context, id types.UUID) (*{{$alias.UpSingular}}, error)

    {{ range $column := .Table.Columns -}}
    {{- $colAlias := $alias.Column $column.Name -}}
    {{- if not (or (containsAny $pkNames $colAlias) (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
        {{$colAlias}} func(ctx context.Context, v {{$alias.UpSingular}}ValidationContext, {{$colAlias }} {{ if and (isEnumDBType .DBType) (.Nullable) }} {{ stripPrefix $column.Type "Null" }} {{ else }} {{$column.Type}} {{ end }}) error
    {{end -}}
    {{end -}}

    {{- range $rel := getLoadRelations $.Tables .Table -}}
        {{ getLoadRelationName $.Aliases $rel }} func(ctx context.Context, v {{$alias.UpSingular}}ValidationContext, {{ getLoadRelationName $.Aliases $rel | singular  }} types.UUID) error
    {{end }}

    // values of the {{$alias.UpSingular}} which is being validated
    values {{$alias.UpSingular}}

    // previousValues are set when IsUpdate is set true and GetFunc is implemented.
    previousValues {{$alias.UpSingular}}

    // isUpdate is set to true the validation is performed for an update, but false when it is insert.
    isUpdate bool
}

{{ range $column := .Table.Columns -}}
{{- $colAlias := $alias.Column $column.Name -}}
{{- if not (or (containsAny $pkNames $colAlias) (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
    func (v *{{$alias.UpSingular}}Validator) Get{{$colAlias}}() {{ if and (isEnumDBType .DBType) (.Nullable) }} {{ stripPrefix $column.Type "Null" }} {{ else }} {{$column.Type}} {{ end }} { return v.values.{{$colAlias}} }
{{end -}}
{{end -}}

{{- range $rel := getLoadRelations $.Tables .Table -}}
    func (v *{{$alias.UpSingular}}Validator) Get{{ getLoadRelationName $.Aliases $rel }}() []types.UUID { return v.values.{{ getLoadRelationName $.Aliases $rel }} }
{{end }}
func (v *{{$alias.UpSingular}}Validator) Values() {{$alias.UpSingular}} { return v.values }
func (v *{{$alias.UpSingular}}Validator) PreviousValues() {{$alias.UpSingular}} { return v.previousValues }
func (v *{{$alias.UpSingular}}Validator) IsUpdate() bool { return v.isUpdate }
{{ range $column := .Table.Columns -}}
{{- $colAlias := $alias.Column $column.Name -}}
{{- if not (or (containsAny $pkNames $colAlias) (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
func (v *{{$alias.UpSingular}}Validator) {{$colAlias}}HasChangedNotNil() bool {
    if v.values.{{$colAlias}}.IsDefined() && !v.values.{{$colAlias}}.IsNil() {
        return (v.isUpdate && v.previousValues.{{$colAlias}} != v.values.{{$colAlias}}) || !v.isUpdate
    }
    return false
 }
{{end -}}
{{end -}}
{{- range $rel := getLoadRelations $.Tables .Table -}}
func (v *{{$alias.UpSingular}}Validator) {{ getLoadRelationName $.Aliases $rel }}HasChangedNotNil() bool {
    if len(v.values.{{ getLoadRelationName $.Aliases $rel }}) > 0 {
        return (v.isUpdate && !slices.Match(v.previousValues.{{ getLoadRelationName $.Aliases $rel }}, v.values.{{ getLoadRelationName $.Aliases $rel }})) || (!v.isUpdate && len(v.values.{{ getLoadRelationName $.Aliases $rel }}) > 0)
    }
    return false
}
{{end -}}

func (v *{{$alias.UpSingular}}Validator) Validate(ctx context.Context, o {{$alias.UpSingular}}, isUpdate bool) error {
    // reset validator values to make unit tests a bit easier
    // otherwise if validator is reused old values might be reused
    v.values = {{$alias.UpSingular}}{}
    v.previousValues = {{$alias.UpSingular}}{}
    v.isUpdate = false

    if isUpdate {
        previousValues, err := v.GetFunc(ctx, o.ID)
        if err != nil {
            return err
        }

        o.mergeUndefinedFields(previousValues)

        v.previousValues = *previousValues
        v.isUpdate = isUpdate
    }
    v.values = o

    errFields := errors.NewErrFields()

    {{ range $column := .Table.Columns -}}
    {{- $colAlias := $alias.Column $column.Name -}}
    {{- if not (or (containsAny $pkNames $colAlias) (eq $column.Name "created_at") (eq $column.Name "created_by") (eq $column.Name "updated_at") (eq $column.Name "updated_by")) -}}
        if v.{{$colAlias}} != nil {
            err := v.{{$colAlias}}(ctx, v, o.{{$colAlias}})
            if err != nil {
                switch v := err.(type){
                case errors.FieldValidationError:
                    if v.Name == ""{
                        v = v.WithName({{$alias.UpSingular}}Column{{$colAlias}})
                    }
                    if v.Value == nil{
                        v = v.WithValue(o.{{$colAlias}})
                    }
                    errFields.Add(v.FieldError())
                case *errors.ErrFields:
                    if v != nil {
                        for _, errField := range *v {
                            errFields.Add(errField)
                        }
                    }
                default:
                    return err
                }
            }
        }
    {{end -}}
    {{end -}}

    {{- range $rel := getLoadRelations $.Tables .Table -}}
        if v.{{ getLoadRelationName $.Aliases $rel }} != nil {
            for _, id := range o.{{ getLoadRelationName $.Aliases $rel }} {
                err := v.{{ getLoadRelationName $.Aliases $rel }}(ctx, v, id)
                if err != nil {
                    switch v := err.(type) {
                    case errors.FieldValidationError:
                        if v.Name == ""{
                            v = v.WithName({{$alias.UpSingular}}Column{{ getLoadRelationName $.Aliases $rel }})
                        }
                        if v.Value == nil{
                            v = v.WithValue(id)
                        }
                        errFields.Add(v.FieldError())
                    case *errors.ErrFields:
                        if v != nil {
                            for _, errField := range *v {
                                errFields.Add(errField)
                            }
                        }
                    default:
                        return err
                    }
                }
            }
        }
    {{end -}}{{- /* range relationships */ -}}

    // return nil if no errors so it would not be concrete type under error interface.
	if !errFields.NotEmpty(){
		return nil
	}
	return errFields
}

// {{$alias.UpSingular}}ValidateBusinessFunc should be used to run business logic for the {{$alias.UpSingular}}-entity,
// it will be passed as an argument to the validate-method which is auto-generated from the database schema.
type {{$alias.UpSingular}}ValidateBusinessFunc func(o {{$alias.UpSingular}}, isUpdate bool) error

// NormalizeAndValidate is auto-generated from the database schema and should be executed before any manipulation of the {{$alias.UpSingular}}-entity
func (o *{{$alias.UpSingular}}) NormalizeAndValidate(ctx context.Context, isUpdate bool, validateBusinessFunc {{$alias.UpSingular}}ValidateBusinessFunc) error {
    // Normalize first to make sure that all of the fields are normalized and set to their default values before validation
    if err := {{$alias.UpSingular}}Normalizer.Normalize(ctx, o, isUpdate); err != nil {
        return err
    }

    errFields := errors.NewErrFields()
    {{range $column := .Table.Columns -}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{- if ne "jsonb" $column.DBType}}
            {{- if or (eq $column.Name "created_at") (eq $column.Name "updated_at") (eq $column.Name "created_by") (eq $column.Name "updated_by") }}
                if o.{{$colAlias}}.IsDefined() {
                    errFields.Unknown(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}).WithValue(o.{{$colAlias}})) // {{$colAlias}} should not be defined by a user, will be set by repository
                }
            {{- else }}
                {{- if containsAny $.Table.PKey.Columns $column.Name }}
                    if isUpdate && o.{{$colAlias}}.IsNil() {
                        errFields.CannotBeNull(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}})) // ID is needed on update
                    }
                {{- else if not $column.Nullable}}
                    // Non-nullable columns must be defined on Create
                    if !isUpdate && !o.{{$colAlias}}.IsDefined() {
                        errFields.CannotBeUndefined(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}))
                    }

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

            {{ $columnMetadata := getColumnMetadata $column }}

            {{- if ($columnMetadata.Validate.Color) }}
                if !o.{{$colAlias}}.IsNil() && !valid.Color(o.{{$colAlias}}.String()) {
                    errFields.InvalidValue(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}).WithValue(o.{{$colAlias}}))
                }
            {{ end }}

            {{- if ($columnMetadata.Validate.CountryCode) }}
                if !o.{{$colAlias}}.IsNil() && !valid.CountryCode(o.{{$colAlias}}.String()) {
                    errFields.InvalidValue(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}).WithValue(o.{{$colAlias}}))
                }
            {{ end }}

            {{- if ($columnMetadata.Validate.EmailAddress) }}
                if !o.{{$colAlias}}.IsNil() && !valid.EmailAddress(o.{{$colAlias}}.String()) {
                    errFields.InvalidValue(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}).WithValue(o.{{$colAlias}}))
                }
            {{ end }}

            {{- if ($columnMetadata.Validate.LanguageCode) }}
                if !o.{{$colAlias}}.IsNil() && !valid.LanguageCode(o.{{$colAlias}}.String()) {
                    errFields.InvalidValue(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}).WithValue(o.{{$colAlias}}))
                }
            {{ end }}

            {{- if ($columnMetadata.Validate.MunicipalityCode) }}
                if !o.{{$colAlias}}.IsNil() && !valid.MunicipalityCode(o.{{$colAlias}}.String()) {
                    errFields.InvalidValue(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}).WithValue(o.{{$colAlias}}))
                }
            {{ end }}

            {{- if ($columnMetadata.Validate.PhoneNumber) }}
                if !o.{{$colAlias}}.IsNil() && !valid.PhoneNumber(o.{{$colAlias}}.String()) {
                    errFields.InvalidValue(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}).WithValue(o.{{$colAlias}}))
                }
            {{ end }}

            {{- if ($columnMetadata.Validate.TimeZone) }}
                if !o.{{$colAlias}}.IsNil() && !valid.TimeZone(o.{{$colAlias}}.String()) {
                    errFields.InvalidValue(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}).WithValue(o.{{$colAlias}}))
                }
            {{ end }}

            {{- if ($columnMetadata.Validate.URL) }}
                if !o.{{$colAlias}}.IsNil() && !valid.URL(o.{{$colAlias}}.String()) {
                    errFields.InvalidValue(errors.FieldName({{$alias.UpSingular}}Column{{$colAlias}}).WithValue(o.{{$colAlias}}))
                }
            {{ end }}
        {{- end}}
    {{end -}}

    if errFields.NotEmpty() {
        return errors.NewBadRequest(errors.MessageValidationFailedForEntity("{{$alias.DownSingular}}"), *errFields...)
    }

    if err := errFields.Merge(validateBusinessFunc(*o, isUpdate)); err != nil {
        return err
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
    {{- range $rel := getLoadRelations $.Tables .Table -}}
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
    {{- range $rel := getLoadRelations $.Tables .Table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        {{- if not (hasSuffix "Logs" $relAlias.Local) -}}
            {{$alias.UpSingular}}Column{{ $relAlias.Local | singular }}IDs,
        {{ end -}}
    {{end -}}{{- /* range relationships */ -}}
    }
}

func {{$alias.UpSingular}}RequiredColumns() []string {
    return []string{
    {{- range $column := .Table.Columns -}}
    {{- if not $column.Nullable}}
        {{- $colAlias := $alias.Column $column.Name -}}
            {{$alias.UpSingular}}Column{{$colAlias}},
        {{end}}
    {{end -}}
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
                {{$alias.DownSingular}}.{{$colAlias}} = types.New{{ stripPrefix $column.Type "types." }}FromPtr(nil)  // Start by setting the value to nil before trying to parse the row value 
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

	err := conversionFunc(&{{$alias.DownSingular}}, fields, values)
    if mErr := errFields.Merge(err); mErr != nil {
        return nil, mErr
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
        {{- range $rel := getLoadRelations $.Tables .Table -}}
            {{$alias.UpSingular}}Column{{ getLoadRelationName $.Aliases $rel }},
        {{end -}}{{- /* range relationships */ -}}
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
        {{- range $rel := getLoadRelations $.Tables .Table -}}
            if o.{{ getLoadRelationName $.Aliases $rel }} != nil {
                fieldMap[{{$alias.UpSingular}}Column{{ getLoadRelationName $.Aliases $rel }}] = struct{}{}
            }
        {{end -}}{{- /* range relationships */ -}}
    }

    // remove all of the unused fields
    for i := len(fields) - 1; i >= 0; i-- {
        _, ok := fieldMap[fields[i]]
        if !ok {
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
        {{- range $rel := getLoadRelations $.Tables .Table -}}
            if o.{{ getLoadRelationName $.Aliases $rel }} != nil {
                index, ok := extractIndexByField({{$alias.UpSingular}}Column{{ getLoadRelationName $.Aliases $rel }})
                if !ok {
                    return nil, nil, errors.New("cannot get index by field, should not happen: "+ {{$alias.UpSingular}}Column{{ getLoadRelationName $.Aliases $rel }})
                }

                value := ""
                for i, v := range o.{{ getLoadRelationName $.Aliases $rel }} {
                    if i != 0 {
                        value += ","
                    }
                    value += v.String()
                }

                 values[index] = value
            }
        {{end -}}{{- /* range relationships */ -}}

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

                    // All possible values for {{$enumName}}
                    func {{$enumName}}Values() []string {
                        return []string{
                            {{range $val := $vals -}}
                            {{- $enumValue := titleCase $val -}}
                                {{printf "%q" $val}},
                            {{end -}}
                        }
                    }

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
                            {{- if $col.Nullable }}
                                if e.IsNil() {
                                    return true // This is a nullable enum
                                }
                            {{end}}
                            switch e {
                            case {{$enumValues}}:
                                return true
                            default:
                                return false
                            }
                        }
                    {{- end -}}
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
    {{- range $col := getLoadRelations_enum_columns $.Tables .Table -}}
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

                    func {{$enumName}}FromStrings(strings []types.String) []{{$enumName}} {
                        enums := make([]{{$enumName}}, len(strings))
                        for i := range strings {
                            enums[i] = {{$enumName}}{strings[i]}
                        }
                        return enums
                    }

                    func {{$enumName}}ToStrings(enums []{{$enumName}}) []types.String {
                        strings := make([]types.String, len(enums))
                        for i := range enums {
                            strings[i] = enums[i].String
                        }
                        return strings
                    }

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
                            {{- if $col.Nullable }}
                                if e.IsNil() {
                                    return true // This is a nullable enum
                                }
                            {{end}}
                            switch e {
                            case {{$enumValues}}:
                                return true
                            default:
                                return false
                            }
                        }
                    {{- end -}}
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
    // Wrapper is used to add restraints to the query when the query comes from the client,
    // will primarily be used to add organization_id and school_id to the queries.
    Wrapper *{{$alias.UpSingular}}QueryNested

    // Nested queries, if any. 
    // Use OrCondition-field to define if the nested query should be wrapped in an AND or OR-statement.
    Nested []{{$alias.UpSingular}}QueryNested

    // Params for the query
    Params {{$alias.UpSingular}}QueryParams

    // Selected fields for the query, leave nil for all fields.
    SelectedFields *{{$alias.UpSingular}}QuerySelectedFields

    // To order by specific columns, by default we will always primary keys first as ascending
    OrderBy *{{$alias.UpSingular}}QueryOrderBy
    
    // OrCondition is used to define if the condition should use AND or OR between the params
    //
    // When true, the condition will have OR between the params, otherwise AND.
    OrCondition types.Bool

    // Offset into the results
    Offset types.Int

    // Limit the number of returned rows
    Limit types.Int
}

func (q *{{$alias.UpSingular}}Query) Validate() error {
    // TODO :
    //  If any params are used, make sure the values are set
    //  if the values aren't set, return a bad request error.
    //
    // This method is used in the List method in ORM-layer waiting to be implemented
    //
    // Use Context with deadline here since we use recursive functions

    return nil
}

func (q *{{$alias.UpSingular}}Query) NewWrapper() *{{$alias.UpSingular}}QueryNested {
    if !q.HasWrapper() {
    	return new({{$alias.UpSingular}}QueryNested)
    }

    newWrapper := New{{$alias.UpSingular}}QueryNested()
    newWrapper.OrCondition = types.NewBool(false)
    newWrapper.Nested = []{{$alias.UpSingular}}QueryNested{*q.Wrapper}

    return &newWrapper
}

func (q *{{$alias.UpSingular}}Query) HasWrapper() bool {
    return q.Wrapper != nil
}

func (q *{{$alias.UpSingular}}Query) HasNested() bool {
    return len(q.Nested) > 0
}

func New{{$alias.UpSingular}}QuerySelectedFields() {{$alias.UpSingular}}QuerySelectedFields {
    return {{$alias.UpSingular}}QuerySelectedFields{}
}

type {{$alias.UpSingular}}QuerySelectedFields struct {
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
            {{$colAlias}} types.Bool
    {{- end}}

    {{ range $rel := getLoadRelations $.Tables .Table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        {{ $relAlias.Local | singular }}IDs types.Bool
    {{end -}}{{- /* range relationships */ -}}
}

func (hide {{$alias.UpSingular}}QuerySelectedFields) HideFields(o *{{$alias.UpSingular}}) {
        {{- range $column := .Table.Columns}}
        {{- $colAlias := $alias.Column $column.Name}}
                if hide.{{$colAlias}}.Bool() {
                    o.{{$colAlias}} = {{ if and (isEnumDBType .DBType) (.Nullable) }} {{ stripPrefix $column.Type "Null" }} {{ else }} {{$column.Type}} {{ end }}{}
                }
        {{- end}}

        {{ range $rel := getLoadRelations $.Tables .Table -}}
            {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            if hide.{{ $relAlias.Local | singular }}IDs.Bool() {
                o.{{ $relAlias.Local | singular }}IDs = nil
            }
        {{end -}}{{- /* range relationships */ -}}
}

func New{{$alias.UpSingular}}QueryNested() {{$alias.UpSingular}}QueryNested {
    return {{$alias.UpSingular}}QueryNested{}
}

type {{$alias.UpSingular}}QueryNested struct {
    // Nested queries, if any. 
    // Use OrCondition-field to define if the nested query should be wrapped in an AND or OR-statement.
    Nested []{{$alias.UpSingular}}QueryNested

    // Params for the query
    Params {{$alias.UpSingular}}QueryParams
    
    // OrCondition is used to define if the condition should use AND or OR between the params
    //
    // When true, the condition will have OR between the params, otherwise AND.
    OrCondition types.Bool
}

func New{{$alias.UpSingular}}QueryParams() {{$alias.UpSingular}}QueryParams {
    return {{$alias.UpSingular}}QueryParams{}
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

func (q *{{$alias.UpSingular}}QueryParams) IsSet() bool {
    switch {
        case q.Equals != nil,
            q.NotEquals != nil,
            q.Empty != nil,
            q.NotEmpty != nil,
            q.In != nil,
            q.NotIn != nil,
            q.GreaterThan != nil,
            q.SmallerThan != nil,
            q.SmallerOrEqual != nil,
            q.GreaterOrEqual != nil,
            q.Like != nil,
            q.NotLike != nil:
            return true
        default:
            return false
    }
}

func New{{$alias.UpSingular}}QueryParamsFields() *{{$alias.UpSingular}}QueryParamsFields {
    return &{{$alias.UpSingular}}QueryParamsFields{}
}

type {{$alias.UpSingular}}QueryParamsFields struct {
    {{- range $column := .Table.Columns}}
        {{- $colAlias := $alias.Column $column.Name}}
        {{$colAlias}} {{ if and (isEnumDBType .DBType) (.Nullable) }} {{ stripPrefix $column.Type "Null" }} {{ else }} {{$column.Type}} {{ end }}
    {{- end}}
    {{ range $rel := getLoadRelations $.Tables .Table -}}
        {{ getLoadRelationName $.Aliases $rel | singular }} {{ getLoadRelationType $.Aliases $.Tables $rel "" }}
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsFields
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        LeftJoin{{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsFields
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsFields
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        LeftJoin{{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsFields
    {{end -}}{{- /* range relationships */ -}}
    CaseInsensitive types.Bool
}

func New{{$alias.UpSingular}}QueryParamsNullableFields() *{{$alias.UpSingular}}QueryParamsNullableFields {
    return &{{$alias.UpSingular}}QueryParamsNullableFields{}
}

type {{$alias.UpSingular}}QueryParamsNullableFields struct {
    {{- range $colAlias := getQueryNullColumns .Aliases.Tables $.Tables .Table.Name}}
        {{ $colAlias }} types.Bool
    {{ end }}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsNullableFields
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        LeftJoin{{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsNullableFields
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsNullableFields
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        LeftJoin{{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsNullableFields
    {{end -}}{{- /* range relationships */ -}}
}

func New{{$alias.UpSingular}}QueryParamsInFields() *{{$alias.UpSingular}}QueryParamsInFields {
    return &{{$alias.UpSingular}}QueryParamsInFields{}
}

type {{$alias.UpSingular}}QueryParamsInFields struct {
    {{- $stringTypes := "types.String, types.UUID, types.Time, types.Date" -}}
    {{- range $column := .Table.Columns}}
        {{- $colAlias := $alias.Column $column.Name -}}
        {{- if or (contains $column.Type $stringTypes) (hasPrefix "types.Int" $column.Type) }}
            {{$colAlias}} []{{$column.Type}}
        {{ else if (isEnumDBType $column.DBType) }}
            {{$colAlias}} []types.String
        {{- end -}}

    {{- end}}
    {{ range $rel := getLoadRelations $.Tables .Table -}}
        {{ getLoadRelationName $.Aliases $rel | singular }} []{{ getLoadRelationType $.Aliases $.Tables $rel "" }}
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinRelations $.Tables .Table -}}
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsInFields
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinRelations $.Tables .Table -}}
        LeftJoin{{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsInFields
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsInFields
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        LeftJoin{{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsInFields
    {{end -}}{{- /* range relationships */ -}}
}

func New{{$alias.UpSingular}}QueryParamsComparableFields() *{{$alias.UpSingular}}QueryParamsComparableFields {
    return &{{$alias.UpSingular}}QueryParamsComparableFields{}
}

type {{$alias.UpSingular}}QueryParamsComparableFields struct {
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name -}}
        {{- if or (hasPrefix "date" $column.DBType) (hasPrefix "int" $column.DBType) (hasPrefix "time" $column.DBType) }}
            {{$colAlias}} {{$column.Type}}
        {{- end -}}
    {{- end}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsComparableFields
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinRelations $.Tables .Table -}}
        LeftJoin{{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsComparableFields
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsComparableFields
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        LeftJoin{{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsComparableFields
    {{end -}}{{- /* range relationships */ -}}
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
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsLikeFields
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        LeftJoin{{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsLikeFields
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsLikeFields
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        LeftJoin{{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsLikeFields
    {{end -}}{{- /* range relationships */ -}}
}

type {{$alias.UpSingular}}QueryOrderBy struct {
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
            {{$colAlias}} *{{$alias.UpSingular}}QueryOrderByField
    {{- end}}
    {{ range $rel := getJoinRelations $.Tables .Table -}}
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryOrderBy
    {{end -}}{{- /* range relationships */ -}}
    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryOrderBy
    {{end -}}{{- /* range relationships */ -}}
}

type {{$alias.UpSingular}}QueryOrderByField struct {
    Index int
    Desc bool
}

func Sort{{$alias.UpPlural}}(o []*{{$alias.UpSingular}}) []*{{$alias.UpSingular}} {
    sort.Sort({{$alias.UpPlural}}(o))
    return o
}

type {{$alias.UpPlural}} []*{{$alias.UpSingular}}
func (o {{$alias.UpPlural}}) Len() int      { return len(o) }
func (o {{$alias.UpPlural}}) Swap(i, j int) { o[i], o[j] = o[j], o[i] }
func (o {{$alias.UpPlural}}) Less(i, j int) bool {
    {{- range getTableColumnOrder .Table }}
    {{- $colAlias := $alias.Column .Column.Name -}}
    {{- $type := stripPrefix .Column.Type "types." }}
        if sort.{{ $type }}{{ if .Desc }}After{{else}}Before{{end}}(o[i].{{$colAlias}}.{{ $type }}(), o[j].{{$colAlias}}.{{ $type }}()) {
            return true
        }
    {{ end }}

	return false
}


// MarshalBinary returns the JSON encoding of {{$alias.UpSingular}}, implements cache.Value
func (o *{{$alias.UpSingular}}) MarshalBinary() ([]byte, error) { return json.Marshal(o) }

// UnmarshalBinary parse JSON encoded data and converts it to {{$alias.UpSingular}}, implements cache.Value
func (o *{{$alias.UpSingular}}) UnmarshalBinary(data []byte) (error) { return json.Unmarshal(data, o) }

// MarshalBinary returns the JSON encoding of {{$alias.UpSingular}}Slice, implements cache.Value
func (o *{{$alias.UpPlural}}) MarshalBinary() ([]byte, error) { return json.Marshal(o) }

// UnmarshalBinary parse JSON encoded data and converts it to {{$alias.UpPlural}}, implements cache.Value
func (o *{{$alias.UpPlural}}) UnmarshalBinary(data []byte) (error) { return json.Unmarshal(data, o) }

// Force package dependencies for the valid-package,
// since it might not be used by the generated code
var _ = valid.EmailAddress
var _ = strconv.AppendInt
var _ = slices.UUIDsToStringSlice
var _ = strings.TrimSpace
var _ = normalize.PhoneNumber
var _ time.Time
