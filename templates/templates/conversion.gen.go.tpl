{{- $alias := .Aliases.Table .Table.Name -}}

{{ if tableHasFile .Table }}
	type signFileURLFunc func(types.UUID) *types.String
{{ end }}

{{ range $fieldName, $structName := getTableRichTextContents .Table -}}
	type {{$structName | camelCase}}ConversionFunc func(*model.{{$alias.UpSingular}}) *api.{{$structName}}
{{end}}

func {{$alias.UpSingular}}FromModels(models []*model.{{$alias.UpSingular}} {{ if tableHasFile .Table }}, signFileURL signFileURLFunc {{ end }} {{ range $fieldName, $structName := getTableRichTextContents .Table -}}, convert{{$structName}} {{$structName | camelCase}}ConversionFunc {{end}}) *[]api.{{$alias.UpSingular}} {
	fromModels := make([]api.{{$alias.UpSingular}}, len(models))
	for i := range models {
		fromModels[i] = {{$alias.UpSingular}}FromModel(models[i]{{ if tableHasFile .Table }}, signFileURL {{ end }} {{ range $fieldName, $structName := getTableRichTextContents .Table -}}, convert{{$structName}} {{end}})
	}
	return &fromModels
}

func {{$alias.UpSingular}}FromModel(model *model.{{$alias.UpSingular}} {{ if tableHasFile .Table }}, signFileURL signFileURLFunc {{ end }} {{ range $fieldName, $structName := getTableRichTextContents .Table -}}, convert{{$structName}} {{$structName | camelCase}}ConversionFunc {{end}}) api.{{$alias.UpSingular}} {
   return api.{{$alias.UpSingular}}{
        {{ range $column := .Table.Columns -}}
		{{- $columnMetadata := getColumnMetadata $column -}}
        {{- $colAlias := $alias.Column $column.Name -}}
			{{ if not $columnMetadata.IsRichText -}} 
				{{$colAlias}}: model.{{$colAlias}}.Ptr(), 
				{{ if $columnMetadata.IsFile -}} 
					{{ getColumnNameFileURL $colAlias }}: signFileURL(model.{{$colAlias}}),
				{{ end -}}
			{{- end }}
        {{- end}}

		{{ range $fieldName, $structName := getTableRichTextContents .Table -}}
			{{ $fieldName }}: convert{{$structName}}(model),
		{{- end }}
        {{range $rel := getLoadRelations $.Tables .Table -}}
            {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            {{$relAlias.Local | singular}}IDs: slice.Pointer(model.{{$relAlias.Local | singular}}IDs),
        {{end -}}{{- /* range relationships */ -}}
    }
}

func {{$alias.UpSingular}}QueryToModel(toModel api.{{$alias.UpSingular}}QueryRequest, wrapper *model.{{$alias.UpSingular}}QueryNested) model.{{$alias.UpSingular}}Query {
	return model.{{$alias.UpSingular}}Query{
		Wrapper: wrapper,
		Nested: {{$alias.DownSingular}}QueryNestedToModels(toModel.Nested),
		Params: {{$alias.DownSingular}}QueryParamsToModel(toModel.Params),
		SelectedFields: (*model.{{$alias.UpSingular}}QuerySelectedFields)(toModel.SelectedFields),
		OrderBy: {{$alias.DownSingular}}QueryOrderByToModel(toModel.OrderBy),
		OrCondition: toModel.OrCondition,
		Offset: toModel.Offset,
		Limit: toModel.Limit,
	}
}

func {{$alias.DownSingular}}QueryNestedToModels(toModels []*api.{{$alias.UpSingular}}QueryNestedRequest) []model.{{$alias.UpSingular}}QueryNested {
	models := make([]model.{{$alias.UpSingular}}QueryNested, len(toModels))
	for i := range toModels {
		models[i] = *{{$alias.DownSingular}}QueryNestedToModel(toModels[i])
	}
	return models
}

func {{$alias.DownSingular}}QueryNestedToModel(toModel *api.{{$alias.UpSingular}}QueryNestedRequest) *model.{{$alias.UpSingular}}QueryNested {
	if nil == toModel {
		return nil
	}
	return &model.{{$alias.UpSingular}}QueryNested{
		Nested: {{$alias.DownSingular}}QueryNestedToModel(toModel.Nested),
		Params: {{$alias.DownSingular}}QueryParamsToModel(toModel.Params),
		OrCondition: toModel.OrCondition,
	}
}

func {{$alias.DownSingular}}QueryParamsToModel(toModel *api.{{$alias.UpSingular}}QueryParamsRequest) model.{{$alias.UpSingular}}QueryParams {
	if toModel == nil {
		return model.{{$alias.UpSingular}}QueryParams{}
	}
	return model.{{$alias.UpSingular}}QueryParams{
		Equals:    {{$alias.DownSingular}}QueryParamsFieldsToModel(toModel.Equals),
		NotEquals: {{$alias.DownSingular}}QueryParamsFieldsToModel(toModel.NotEquals),
		Empty:    {{$alias.DownSingular}}QueryParamsNullableFieldsToModel(toModel.Empty),
		NotEmpty: {{$alias.DownSingular}}QueryParamsNullableFieldsToModel(toModel.NotEmpty),
		In:    {{$alias.DownSingular}}QueryParamsInFieldsToModel(toModel.In),
		NotIn: {{$alias.DownSingular}}QueryParamsInFieldsToModel(toModel.NotIn),
		GreaterThan: {{$alias.DownSingular}}QueryParamsComparableFieldsToModel(toModel.GreaterThan),
		SmallerThan: {{$alias.DownSingular}}QueryParamsComparableFieldsToModel(toModel.SmallerThan),
		SmallerOrEqual: {{$alias.DownSingular}}QueryParamsComparableFieldsToModel(toModel.SmallerOrEqual),
		GreaterOrEqual: {{$alias.DownSingular}}QueryParamsComparableFieldsToModel(toModel.GreaterOrEqual),
		Like:    {{$alias.DownSingular}}QueryParamsLikeFieldsToModel(toModel.Like),
		NotLike: {{$alias.DownSingular}}QueryParamsLikeFieldsToModel(toModel.NotLike),
	}
}

func {{$alias.DownSingular}}QueryParamsFieldsToModel(toModel *api.{{$alias.UpSingular}}QueryParamsFieldsRequest) *model.{{$alias.UpSingular}}QueryParamsFields {
	if nil == toModel {
		return nil
	}

	return &model.{{$alias.UpSingular}}QueryParamsFields{
	    {{- range $column := .Table.Columns}}
		    {{- $colAlias := $alias.Column $column.Name}}
			{{$colAlias}}: {{ if (isEnumDBType .DBType) }}{{- $enumName := parseEnumName .DBType -}} model.{{ titleCase $enumName }}FromString(toModel.{{$colAlias}}) {{ else }} toModel.{{$colAlias}} {{ end }},
		{{- end}}

		{{- range $rel := getLoadRelations $.Tables .Table }}
        	{{ getLoadRelationName $.Aliases $rel | singular }}: toModel.{{ getLoadRelationName $.Aliases $rel | singular }},
    	{{- end }}

        {{- range $rel := getJoinRelations $.Tables .Table }}
            {{ $rel.ForeignTable | titleCase }}: {{ $rel.ForeignTable | camelCase }}QueryParamsFieldsToModel(toModel.{{ $rel.ForeignTable | titleCase }}),
        {{- end -}}
	}
}

func {{$alias.DownSingular}}QueryParamsNullableFieldsToModel(toModel *api.{{$alias.UpSingular}}QueryParamsNullableFieldsRequest) *model.{{$alias.UpSingular}}QueryParamsNullableFields {
    if nil == toModel {
        return nil
    }

    return &model.{{$alias.UpSingular}}QueryParamsNullableFields{
        {{- range $column := .Table.Columns }}
            {{- $colAlias := $alias.Column $column.Name -}}
            {{- if $column.Nullable }}
                {{$colAlias}}: toModel.{{ $colAlias }},
            {{- end -}}
        {{- end }}

        {{- range $rel := getJoinRelations $.Tables .Table }}
            {{ $rel.ForeignTable | titleCase }}: {{ $rel.ForeignTable | camelCase }}QueryParamsNullableFieldsToModel(toModel.{{ $rel.ForeignTable | titleCase }}),
        {{- end }}
    }
}

func {{$alias.DownSingular}}QueryParamsInFieldsToModel(toModel *api.{{$alias.UpSingular}}QueryParamsInFieldsRequest) *model.{{$alias.UpSingular}}QueryParamsInFields {
    if nil == toModel {
        return nil
    }

    return &model.{{$alias.UpSingular}}QueryParamsInFields{
        {{- range $column := .Table.Columns }}
            {{- $colAlias := $alias.Column $column.Name -}}
            {{- $stringTypes := "types.String, types.UUID, types.Time, types.Date" -}}

            {{- if or (contains $column.Type $stringTypes) }}
                {{$colAlias}}: toModel.{{$colAlias}},
            {{- end -}}

            {{- if contains "types.Int" $column.Type }}
                {{$colAlias}}: toModel.{{$colAlias}},
            {{- end -}}
        {{- end }}

        {{- range $rel := getLoadRelations $.Tables .Table }}
            {{ getLoadRelationName $.Aliases $rel | singular }}: toModel.{{ getLoadRelationName $.Aliases $rel | singular }},
        {{- end }}

        {{- range $rel := getJoinRelations $.Tables .Table }}
            {{ $rel.ForeignTable | titleCase }}: {{ $rel.ForeignTable | camelCase }}QueryParamsInFieldsToModel(toModel.{{ $rel.ForeignTable | titleCase }}),
        {{- end }}
    }
}

func {{$alias.DownSingular}}QueryParamsComparableFieldsToModel(toModel *api.{{$alias.UpSingular}}QueryParamsComparableFieldsRequest) *model.{{$alias.UpSingular}}QueryParamsComparableFields {
    if nil == toModel {
        return nil
    }

    return &model.{{$alias.UpSingular}}QueryParamsComparableFields{
        {{- range $column := .Table.Columns}}
            {{- $colAlias := $alias.Column $column.Name -}}

            {{- if hasSuffix "Int" $column.Type }}
                {{$colAlias}}: toModel.{{$colAlias}},
            {{- end -}}

            {{- if or (hasPrefix "date" $column.DBType) (hasPrefix "time" $column.DBType) }}
                {{$colAlias}}: toModel.{{$colAlias}},
            {{- end -}}

        {{- end }}

        {{- range $rel := getJoinRelations $.Tables .Table }}
            {{ $rel.ForeignTable | titleCase }}: {{ $rel.ForeignTable | camelCase }}QueryParamsComparableFieldsToModel(toModel.{{ $rel.ForeignTable | titleCase }}),
        {{- end }}
    }
}

func {{$alias.DownSingular}}QueryParamsLikeFieldsToModel(toModel *api.{{$alias.UpSingular}}QueryParamsLikeFieldsRequest) *model.{{$alias.UpSingular}}QueryParamsLikeFields {
    if nil == toModel {
        return nil
    }

    return &model.{{$alias.UpSingular}}QueryParamsLikeFields{
        {{- range $column := .Table.Columns}}
            {{- $colAlias := $alias.Column $column.Name}}

            {{- if hasSuffix "String" $column.Type }}
                {{$colAlias}}: toModel.{{$colAlias}},
            {{- end -}}

        {{- end }}

        {{- range $rel := getJoinRelations $.Tables .Table }}
            {{ $rel.ForeignTable | titleCase }}: {{ $rel.ForeignTable | camelCase }}QueryParamsLikeFieldsToModel(toModel.{{ $rel.ForeignTable | titleCase }}),
        {{- end }}
    }
}

func {{$alias.DownSingular}}QueryOrderByToModel(toModel *api.{{$alias.UpSingular}}QueryOrderByRequest) *model.{{$alias.UpSingular}}QueryOrderBy {
	if nil == toModel {
		return nil
	}

	return &model.{{$alias.UpSingular}}QueryOrderBy{
		{{- range $column := .Table.Columns}}
		{{- $colAlias := $alias.Column $column.Name}}
				{{$colAlias}}: (*model.{{$alias.UpSingular}}QueryOrderByField)(toModel.{{$colAlias}}),
		{{- end}}
	}
}

// Force package dependencies 
var _ types.Types 			// Init blank variable since types is imported automatically with boiler
var _ = slice.Pointer[any] // Init blank variable since slice is imported automatically with boiler