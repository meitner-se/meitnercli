{{- $alias := .Aliases.Table .Table.Name -}}

// {{$alias.UpSingular}} is the API model representation of the {{ .Table.Name }}-table
type {{$alias.UpSingular}} struct {
	{{- range $column := .Table.Columns -}}
	{{- $colAlias := $alias.Column $column.Name -}}
	{{- $orig_col_name := $column.Name -}}
    {{ $columnMetadata := getColumnMetadata $column }}

    {{if not $columnMetadata.IsRichText}}
	{{- range $columnMetadata.Comments }}
    // {{ . }}
    {{- end }}

    {{- if (isEnumDBType .DBType) }}
        // options: [{{- parseEnumVals $column.DBType | stringMap $.StringFuncs.quoteWrap | join ", " -}}]
        {{$colAlias}} *string
    {{ else }}
	{{$colAlias}}

    {{- $stringTypes := "types.String, types.UUID, types.Timestamp, types.Time, types.Date" -}}
    {{- if contains $column.Type $stringTypes -}}
        *string
	{{end -}}

    {{- if eq $column.Type "types.Bool" -}}
        *bool
	{{end -}}

    {{- if contains "types.Int" $column.Type -}}
        *int
	{{end -}}

    {{- if contains "JSON" $column.Type -}}
        *interface{}
	{{end -}}

    {{- if $columnMetadata.IsFile -}}
        // type: "types.String"
        {{ getColumnNameFileURL $colAlias }} *string
    {{ end }}

    {{end}}
    {{end -}}
    {{end -}}

    {{ range $fieldName, $structName := getTableRichTextContents .Table }}
        // nullable: true
        {{ $fieldName }} *{{ $structName }}
    {{end}}

    {{- range $rel := getLoadRelations $.Tables .Table -}}
	{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        // type: "types.UUID"
		{{ $relAlias.Local | singular }}IDs []string
	{{end -}}{{- /* range relationships */ -}}
}

{{ range getTableRichTextContents .Table }}
    // rich_text_content: {}
    type {{ . }} struct {
        // type: "types.String"
        Content string
        // type: "types.String"
        ContentType string
        // type: "types.String"
        Converter string
        // type: "types.String"
        Text string
    }
{{ end }}

type {{$alias.UpSingular}}QueryRequest struct {
    // Nested queries, if any. 
    // Use OrCondition-field to define if the nested query should be wrapped in an AND or OR-statement.
    //
    // optional: true
    Nested []*{{$alias.UpSingular}}QueryNestedRequest

    // Params for the query
    //
    // optional: true
    Params *{{$alias.UpSingular}}QueryParamsRequest

    // Selected fields for the query, leave nil for all fields.
    //
    // optional: true
    SelectedFields *{{$alias.UpSingular}}QuerySelectedFieldsRequest

    // To order by specific columns, by default we will always primary keys first as ascending
    //
    // optional: true
    OrderBy *{{$alias.UpSingular}}QueryOrderByRequest
	
    // OrCondition is used to define if the condition should use AND or OR between the params
    //
    // When true, the condition will have OR between the params, otherwise AND.
    //
    // optional: true
    // type: "types.Bool"
	OrCondition *bool

    // Offset into the results
    //
    // optional: true
    // type: "types.Int"
	Offset *int

	// Limit the number of returned rows
    //
    // optional: true
    // type: "types.Int"
	Limit *int
}

type {{$alias.UpSingular}}QuerySelectedFieldsRequest struct {
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
            // optional: true
            // type: "types.Bool"
            {{$colAlias}} *bool
    {{- end}}

    {{- range $rel := getLoadRelations $.Tables .Table -}}
	{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        // optional: true
        // type: "types.Bool"
		{{ $relAlias.Local | singular }}IDs *bool
	{{end -}}{{- /* range relationships */ -}}
}

type {{$alias.UpSingular}}QueryNestedRequest struct {
    // Nested queries, if any. 
    // Use OrCondition-field to define if the nested query should be wrapped in an AND or OR-statement.
    //
    // optional: true
    Nested []*{{$alias.UpSingular}}QueryNestedRequest

    // Params for the query
    //
    // optional: true
    Params *{{$alias.UpSingular}}QueryParamsRequest
	
    // OrCondition is used to define if the condition should use AND or OR between the params
    //
    // When true, the condition will have OR between the params, otherwise AND.
    //
    // optional: true
    // type: "types.Bool"
	OrCondition *bool
}

type {{$alias.UpSingular}}QueryParamsRequest struct {
    // optional: true
	Equals    *{{$alias.UpSingular}}QueryParamsFieldsRequest
    // optional: true
	NotEquals *{{$alias.UpSingular}}QueryParamsFieldsRequest

    // optional: true
	Empty    *{{$alias.UpSingular}}QueryParamsNullableFieldsRequest
    // optional: true
	NotEmpty *{{$alias.UpSingular}}QueryParamsNullableFieldsRequest

    // optional: true
	In    *{{$alias.UpSingular}}QueryParamsInFieldsRequest
    // optional: true
	NotIn *{{$alias.UpSingular}}QueryParamsInFieldsRequest

    // optional: true
	GreaterThan *{{$alias.UpSingular}}QueryParamsComparableFieldsRequest
    // optional: true
	SmallerThan *{{$alias.UpSingular}}QueryParamsComparableFieldsRequest

    // optional: true
	SmallerOrEqual *{{$alias.UpSingular}}QueryParamsComparableFieldsRequest
    // optional: true
	GreaterOrEqual *{{$alias.UpSingular}}QueryParamsComparableFieldsRequest

    // optional: true
	Like    *{{$alias.UpSingular}}QueryParamsLikeFieldsRequest
    // optional: true
	NotLike *{{$alias.UpSingular}}QueryParamsLikeFieldsRequest
}

type {{$alias.UpSingular}}QueryParamsFieldsRequest struct {
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{- if (isEnumDBType .DBType) }}
            {{- $first := true -}}
            {{- $enumValues := "" -}}
            {{ range $val := parseEnumVals $column.DBType -}}
                {{- if $first -}}
                    {{- $first = false -}}
                {{- else -}}
                    {{- $enumValues = printf "%s%s" $enumValues ", " -}}
                {{- end -}}

                {{- $enumValue := titleCase $val -}}
                {{- $enumValues = printf "%s\"%s\"" $enumValues $enumValue -}}
            {{- end}}
            // options: [{{ $enumValues }}]
            // optional: true
            // type: "types.String"
            {{$colAlias}} *string
        {{ else }}
            // optional: true
            // type: "{{$column.Type}}"
            {{- $stringTypes := "types.String, types.UUID, types.Timestamp, types.Time, types.Date" -}}
            {{- if contains $column.Type $stringTypes }}
                {{$colAlias}} *string
            {{end -}}

            {{- if eq $column.Type "types.Bool" }}
                {{$colAlias}} *bool
            {{end -}}

            {{- if contains "types.Int" $column.Type }}
                {{$colAlias}} *int
            {{end -}}

            {{- if contains "JSON" $column.Type }}
                {{$colAlias}} *interface{}
            {{end -}}

        {{end -}}
    {{- end}}

    {{ range $rel := getLoadRelations $.Tables .Table -}}
        // optional: true
        // type: "{{ getLoadRelationType $.Aliases $.Tables $rel "" }}"
        {{ getLoadRelationName $.Aliases $rel | singular }} *string
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinRelations $.Tables .Table -}}
        // optional: true
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsFieldsRequest
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        // optional: true
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsFieldsRequest
    {{end -}}{{- /* range relationships */ -}}

    // Set to true to use case insensitive query for strings
    //
    // optional: true
    // type: "types.Bool"
    CaseInsensitive *bool
}

type {{$alias.UpSingular}}QueryParamsNullableFieldsRequest struct {
    {{- range $column := .Table.Columns}}
        {{- $colAlias := $alias.Column $column.Name}}
        
        {{if $column.Nullable -}}
            // optional: true
            // type: "types.Bool"
            {{$colAlias}} *bool
        {{- end}}
    {{- end}}

    {{ range $rel := getLoadRelations $.Tables .Table -}}
        // optional: true
        // type: "types.Bool"
        {{ getLoadRelationName $.Aliases $rel | singular }} *bool
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinRelations $.Tables .Table -}}
        // optional: true
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsNullableFieldsRequest
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        // optional: true
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsNullableFieldsRequest
    {{end -}}{{- /* range relationships */ -}}
}

type {{$alias.UpSingular}}QueryParamsInFieldsRequest struct {
    {{- range $column := .Table.Columns }}
        {{- $colAlias := $alias.Column $column.Name}}
        {{- $stringTypes := "types.String, types.UUID, types.Time, types.Date" -}}
        
        {{- if or (contains $column.Type $stringTypes)  }}
            // optional: true
            // type: "{{$column.Type}}"
            {{$colAlias}} []*string
        {{end -}}

        {{- if contains "types.Int" $column.Type }}
            // optional: true
            // type: "{{$column.Type}}"
            {{$colAlias}} []*int
        {{end -}}
    {{- end}}

    {{ range $rel := getLoadRelations $.Tables .Table -}}
        // optional: true
        // type: "{{ getLoadRelationType $.Aliases $.Tables $rel "" }}"
        {{ getLoadRelationName $.Aliases $rel | singular }} []*string
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinRelations $.Tables .Table -}}
        // optional: true
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsInFieldsRequest
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        // optional: true
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsInFieldsRequest
    {{end -}}{{- /* range relationships */ -}}
}

type {{$alias.UpSingular}}QueryParamsComparableFieldsRequest struct {
    {{- range $column := .Table.Columns}}
        {{- $colAlias := $alias.Column $column.Name}}
        
        {{- if hasSuffix "Int" $column.Type }}
            // optional: true
            // type: "{{$column.Type}}"
            {{$colAlias}} *int
        {{ end -}}

        {{- if or (hasPrefix "date" $column.DBType) (hasPrefix "time" $column.DBType) }}
            // optional: true
            // type: "{{$column.Type}}"
            {{$colAlias}} *string
        {{ end -}}

    {{- end }}

    {{ range $rel := getJoinRelations $.Tables .Table -}}
        // optional: true
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsComparableFieldsRequest
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        // optional: true
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsComparableFieldsRequest
    {{end -}}{{- /* range relationships */ -}}
}

type {{$alias.UpSingular}}QueryParamsLikeFieldsRequest struct {
    {{- range $column := .Table.Columns}}
        
        {{- $colAlias := $alias.Column $column.Name}}
        
        {{- if hasSuffix "String" $column.Type }}
            // optional: true
            // type: "{{$column.Type}}"
            {{$colAlias}} *string
        {{ end -}}

    {{- end}}

    {{ range $rel := getJoinRelations $.Tables .Table -}}
        // optional: true
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsLikeFieldsRequest
    {{end -}}{{- /* range relationships */ -}}

    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        // optional: true
        {{ $rel.ForeignTable | titleCase }} *{{ $rel.ForeignTable | titleCase }}QueryParamsLikeFieldsRequest
    {{end -}}{{- /* range relationships */ -}}
}

type {{$alias.UpSingular}}QueryOrderByRequest struct {
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        // optional: true
        {{$colAlias}} *{{$alias.UpSingular}}QueryOrderByFieldRequest
    {{- end}}

    {{ range $rel := getJoinRelations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        // optional: true
        {{$relAlias.Local | singular }} *{{$relAlias.Local | singular }}QueryOrderByRequest
    {{ end -}}

    {{ range $rel := getJoinFromChildForeignKeys .Table -}}
        // optional: true
        {{$rel.ForeignTable | titleCase }} *{{$rel.ForeignTable | titleCase }}QueryOrderByRequest
    {{ end -}}
}

type {{$alias.UpSingular}}QueryOrderByFieldRequest struct {
    // optional: true
    Index int
    // optional: true
    Desc bool
}

var _ types.Types // Init blank variable since types is imported automatically with boiler
