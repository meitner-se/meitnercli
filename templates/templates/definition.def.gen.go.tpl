{{- $alias := .Aliases.Table .Table.Name -}}

// {{$alias.UpSingular}} is the API model representation of the {{ .Table.Name }}-table
type {{$alias.UpSingular}} struct {
	{{- range $column := .Table.Columns -}}
	{{- $colAlias := $alias.Column $column.Name -}}
	{{- $orig_col_name := $column.Name -}}
	{{ range $column.Comment | splitLines }} // {{ . }} {{ end }}
    {{- if (isEnumDBType .DBType) -}}
        // options: [{{- parseEnumVals $column.DBType | stringMap $.StringFuncs.quoteWrap | join ", " -}}]
        // type: "types.String"
        {{$colAlias}} *string
    {{ else }}
    // type: "{{$column.Type}}"
	{{$colAlias}}
    
    {{- $stringTypes := "types.String, types.UUID, types.Timestamp, types.Date" -}}
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
    
    {{end}}
    {{end -}}

    {{- range $rel := .Table.ToManyRelationships -}}
		{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        // type: "types.UUID"
		{{ $relAlias.Local | singular }}IDs []string
	{{end -}}{{- /* range relationships */ -}}
}


type {{$alias.UpSingular}}QueryRequest struct {
    // Nested queries, if any. 
    // Use OrCondition-field to define if the nested query should be wrapped in an AND or OR-statement.
    Nested []{{$alias.UpSingular}}QueryNestedRequest

    // Params for the query
    Params {{$alias.UpSingular}}QueryParamsRequest

    // Selected fields for the query, leave nil for all fields.
    SelectedFields *{{$alias.UpSingular}}QuerySelectedFieldsRequest

    // Inner join with related tables
	Join *{{$alias.UpSingular}}QueryJoinRequest

	// Load the IDs of the relations
	Load *{{$alias.UpSingular}}QueryLoadRequest

    // To order by specific columns, by default we will always primary keys first as ascending
    OrderBy *{{$alias.UpSingular}}QueryOrderByRequest
	
    // OrCondition is used to define if the condition should use AND or OR between the params
    //
    // When true, the condition will have OR between the params, otherwise AND.
    //
    // type: "types.Bool"
	OrCondition bool

    // OrConditionNested is used to define if the nested query should be wrapped in an AND or OR clause.
    //
    // When true, the nested clause will be wrapped with OR, otherwise AND.
    //
    // type: "types.Bool"
	OrConditionNested bool

    // Offset into the results
    //
    // optional: true
    // type: "types.Int"
	Offset int

	// Limit the number of returned rows
    //
    // optional: true
    // type: "types.Int"
	Limit int
}

type {{$alias.UpSingular}}QuerySelectedFieldsRequest struct {
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
            // type: "types.Bool"
            {{$colAlias}} bool
    {{- end}}
}

type {{$alias.UpSingular}}QueryNestedRequest struct {
    // Nested queries, if any. 
    // Use OrCondition-field to define if the nested query should be wrapped in an AND or OR-statement.
    Nested *{{$alias.UpSingular}}QueryNestedRequest

    // Params for the query
    Params {{$alias.UpSingular}}QueryParamsRequest
	
    // OrCondition is used to define if the condition should use AND or OR between the params
    //
    // When true, the condition will have OR between the params, otherwise AND.
    //
    // type: "types.Bool"
	OrCondition bool

    // OrConditionNested is used to define if the nested query should be wrapped in an AND or OR clause.
    //
    // When true, the nested clause will be wrapped with OR, otherwise AND.
    //
    // optional: true
    // type: "types.Bool"
	OrConditionNested bool
}

type {{$alias.UpSingular}}QueryParamsRequest struct {
	Equals    *{{$alias.UpSingular}}QueryParamsFieldsRequest
	NotEquals *{{$alias.UpSingular}}QueryParamsFieldsRequest

	Empty    *{{$alias.UpSingular}}QueryParamsNullableFieldsRequest
	NotEmpty *{{$alias.UpSingular}}QueryParamsNullableFieldsRequest

	In    *{{$alias.UpSingular}}QueryParamsInFieldsRequest
	NotIn *{{$alias.UpSingular}}QueryParamsInFieldsRequest

	GreaterThan *{{$alias.UpSingular}}QueryParamsComparableFieldsRequest
	SmallerThan *{{$alias.UpSingular}}QueryParamsComparableFieldsRequest

	SmallerOrEqual *{{$alias.UpSingular}}QueryParamsComparableFieldsRequest
	GreaterOrEqual *{{$alias.UpSingular}}QueryParamsComparableFieldsRequest

	Like    *{{$alias.UpSingular}}QueryParamsLikeFieldsRequest
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
            {{$colAlias}} string
        {{ else }}
            // optional: true
            // type: "{{$column.Type}}"
            {{- $stringTypes := "types.String, types.UUID, types.Timestamp, types.Date" -}}
            {{- if contains $column.Type $stringTypes }}
                {{$colAlias}} string
            {{end -}}

            {{- if eq $column.Type "types.Bool" }}
                {{$colAlias}} bool
            {{end -}}

            {{- if contains "types.Int" $column.Type }}
                {{$colAlias}} int
            {{end -}}

            {{- if contains "JSON" $column.Type }}
                {{$colAlias}} interface{}
            {{end -}}

        {{end -}}
    {{- end}}
}

type {{$alias.UpSingular}}QueryParamsNullableFieldsRequest struct {
    {{- range $column := .Table.Columns}}
        {{- $colAlias := $alias.Column $column.Name}}
        
        {{if $column.Nullable -}}
            // optional: true
            // type: "types.Bool"
            {{$colAlias}} bool
        {{- end}}

    {{- end}}
}

type {{$alias.UpSingular}}QueryParamsInFieldsRequest struct {
    {{- range $column := .Table.Columns }}
        {{- $colAlias := $alias.Column $column.Name}}
        {{- $stringTypes := "types.String, types.UUID, types.Timestamp, types.Date" -}}
        
        {{- if or (contains $column.Type $stringTypes)  }}
            // optional: true
            // type: "{{$column.Type}}"
            {{$colAlias}} []string
        {{end -}}

        {{- if contains "types.Int" $column.Type }}
            // optional: true
            // type: "{{$column.Type}}"
            {{$colAlias}} []int
        {{end -}}

    {{- end}}
}

type {{$alias.UpSingular}}QueryParamsComparableFieldsRequest struct {
    {{- range $column := .Table.Columns}}
        {{- $colAlias := $alias.Column $column.Name}}
        
        {{- if hasSuffix "Int" $column.Type }}
            // optional: true
            // type: "{{$column.Type}}"
            {{$colAlias}} int
        {{ end -}}

        {{- if or (hasPrefix "date" $column.DBType) (hasPrefix "time" $column.DBType) }}
            // optional: true
            // type: "{{$column.Type}}"
            {{$colAlias}} string
        {{ end -}}

    {{- end }}
}

type {{$alias.UpSingular}}QueryParamsLikeFieldsRequest struct {
    {{- range $column := .Table.Columns}}
        
        {{- $colAlias := $alias.Column $column.Name}}
        
        {{- if hasSuffix "String" $column.Type }}
            // optional: true
            // type: "{{$column.Type}}"
            {{$colAlias}} string
        {{ end -}}

    {{- end}}
}

type {{$alias.UpSingular}}QueryLoadRequest struct {
	{{- range $rel := .Table.ToManyRelationships -}}
		{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName }}
		{{ $relAlias.Local | singular }} *{{$alias.UpSingular}}QueryLoad{{ $relAlias.Local | singular }}Request
	{{- end }}{{- /* range relationships */ -}}
}

{{ range $rel := .Table.ToManyRelationships }}
	{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
    type {{$alias.UpSingular}}QueryLoad{{ $relAlias.Local | singular }}Request struct {
        // Params for the load
        Params {{ $relAlias.Local | singular }}QueryParamsRequest

        // OrCondition is used to define if the condition should use AND or OR between the params
        //
        // When true, the condition will have OR between the params, otherwise AND.
        //
        // type: "types.Bool"
        OrCondition bool

        // Offset into the results
        //
        // type: "types.Int"
        Offset int

        // Limit the number of returned rows
        //
        // type: "types.Int"
        Limit int
    }
{{ end }}{{- /* range relationships */ -}}

type {{$alias.UpSingular}}QueryJoinRequest struct {
	{{- range $rel := .Table.ToManyRelationships -}}
		{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName }}
		{{ $relAlias.Local | singular }} *{{$alias.UpSingular}}QueryJoin{{ $relAlias.Local | singular }}Request
	{{- end }}{{- /* range relationships */ -}}
}

{{ range $rel := .Table.ToManyRelationships -}}
	{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
    type {{$alias.UpSingular}}QueryJoin{{ $relAlias.Local | singular }}Request struct {
            // Params for the query
            Params {{ $relAlias.Local | singular }}QueryParamsRequest

            // OrCondition is used to define if the condition should use AND or OR between the params
            //
            // When true, the condition will have OR between the params, otherwise AND.
            //
            // type: "types.Bool"
            OrCondition bool
    }
{{end -}}{{- /* range relationships */ -}}

type {{$alias.UpSingular}}QueryOrderByRequest struct {
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
            {{$colAlias}} *{{$alias.UpSingular}}QueryOrderByFieldRequest
    {{- end}}
}

type {{$alias.UpSingular}}QueryOrderByFieldRequest struct {
    Index int
    Desc bool
}

var _ types.Types // Init blank variable since types is imported automatically with boiler
