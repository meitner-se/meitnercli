{{- if .Table.IsView -}}
{{- else -}}
{{- $alias := .Aliases.Table .Table.Name -}}
{{- $colDefs := sqlColDefinitions .Table.Columns .Table.PKey.Columns -}}
{{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap .StringFuncs.camelCase | stringMap .StringFuncs.replaceReserved -}}
{{- $pkArgs := joinSlices " " $pkNames $colDefs.Types | join ", " -}}
{{- $schemaTable := .Table.Name | .SchemaTable}}
 {{- $stringTypes := "types.String, types.UUID, types.Time, types.Date" -}}

// InsertDefined inserts {{$alias.UpSingular}} with the defined values only.
func (o *{{$alias.UpSingular}}) InsertDefined({{if .NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, auditLog audit.Log) error {
    auditLogValues := []audit.LogValue{}
    whitelist := boil.Whitelist() // whitelist each column that has a defined value

    {{range $column := .Table.Columns}}
    {{$colAlias := $alias.Column $column.Name}}
        {{- if not $column.Nullable -}}
            if o.{{$colAlias}}.IsNil() {
                return errors.New("{{$column.Name}} cannot be null")
            }
        {{- end}}
        if o.{{$colAlias}}.IsDefined() {
            auditLogValues = append(auditLogValues, audit.NewLogValue({{$alias.UpSingular}}Columns.{{$colAlias}}, "{{ strip_prefix $column.Type "types." }}", o.{{$colAlias}}, nil))
            whitelist.Cols = append(whitelist.Cols, {{$alias.UpSingular}}Columns.{{$colAlias}})
        }
    {{- end}}

    err := o.Insert(ctx, exec, whitelist)
	if err != nil {
		return err
	}

    if o.R != nil {
    {{- range $rel := get_load_relations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if o.R.{{$relAlias.Local | plural }} != nil {
            auditLogValues = append(auditLogValues, audit.NewLogValue(model.{{$alias.UpSingular}}Column{{$relAlias.Local | singular}}IDs, "UUID", o.Get{{ get_load_relation_name $.Aliases $rel }}(true), nil))
            err := o.Add{{$relAlias.Local | plural}}(ctx, exec, false, o.R.{{$relAlias.Local | plural }}...)
            if err != nil {
                return err
            }
        }
    {{end -}}{{- /* range relationships */ -}}
    }

    err = auditLog.Add(ctx, audit.OperationCreate, TableNames.{{titleCase .Table.Name}}, o.ID.String(), auditLogValues...)
    if err != nil {
        return err
    }

    return nil
}

// UpdateDefined updates {{$alias.UpSingular}} with the defined values only.
func (o *{{$alias.UpSingular}}) UpdateDefined({{if .NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, auditLog audit.Log, newValues *{{$alias.UpSingular}}) error {
    auditLogValues := []audit.LogValue{} // Collect all values that have been changed
    whitelist := boil.Whitelist() // whitelist each column that has a defined value and should be updated

    {{range $column := .Table.Columns}}
    {{$colAlias := $alias.Column $column.Name}}
        if newValues.{{$colAlias}}.IsDefined() {{ if ne $column.Type "types.JSON" }}&& newValues.{{$colAlias}} != o.{{$colAlias}} {{end}} {
            {{- if not $column.Nullable -}}
                if newValues.{{$colAlias}}.IsNil() {
                    return errors.New("{{$column.Name}} cannot be null")
                }
            {{- end}}
            auditLogValues = append(auditLogValues, audit.NewLogValue({{$alias.UpSingular}}Columns.{{$colAlias}}, "{{ strip_prefix $column.Type "types." }}", newValues.{{$colAlias}}, o.{{$colAlias}}))
            whitelist.Cols = append(whitelist.Cols, {{$alias.UpSingular}}Columns.{{$colAlias}})
            o.{{$colAlias}} = newValues.{{$colAlias}}
        }
    {{- end}}

    // Check if any join tables should be updated and load the existing values before updating if we have an operating audit log
    if newValues.R != nil {
        {{- range $rel := get_load_relations $.Tables .Table -}}
        {{- if $rel.ToJoinTable -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            if newValues.R.{{$relAlias.Local | plural }} != nil {
                if !audit.IsNoop(auditLog) {
                    {{$relAlias.Local | singular | camelCase }}Slice, err := o.{{$relAlias.Local | plural }}(qm.Select({{$rel.ForeignTable | titleCase }}Columns.ID)).All(ctx, exec)
                    if err != nil {
                        return err
                    }

                    if o.R == nil {
                        o.R = o.R.NewStruct()
                    }
                    
                    o.R.{{$relAlias.Local}} = {{$relAlias.Local | singular | camelCase }}Slice
                }

                auditLogValues = append(auditLogValues, audit.NewLogValue(model.{{$alias.UpSingular}}Column{{$relAlias.Local | singular}}IDs, "UUID", newValues.Get{{$relAlias.Local | singular}}IDs(true), o.Get{{$relAlias.Local | singular}}IDs(true)))
                err := o.Set{{$relAlias.Local | plural}}(ctx, exec, false, newValues.R.{{$relAlias.Local | plural }}...)
                if err != nil {
                    return err
                }
            }
        {{end -}}
        {{end -}}{{- /* range relationships */ -}}
    }

    {{if not .NoRowsAffected}}_,{{end -}} err := o.Update(ctx, exec, whitelist)
	if err != nil {
		return err
	}

    err = auditLog.Add(ctx, audit.OperationUpdate, TableNames.{{titleCase .Table.Name}}, o.ID.String(), auditLogValues...)
    if err != nil {
        return err
    }

    return nil
}

// DeleteDefined deletes {{$alias.UpSingular}} with the defined values only.
func (o *{{$alias.UpSingular}}) DeleteDefined({{if .NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, auditLog audit.Log) error {
    {{if not .NoRowsAffected}}_,{{end -}}err := o.Delete(ctx, exec)
	if err != nil {
		return err
	}

    err = auditLog.Add(ctx, audit.OperationDelete, TableNames.{{titleCase .Table.Name}}, o.ID.String())
    if err != nil {
        return err
    }

    return nil
}

{{ range $rel := get_load_relations $.Tables .Table -}}
{{- $ftable := $.Aliases.Table .ForeignTable -}}
{{ $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
{{ $loadCol := get_load_relation_column $.Aliases $.Tables $rel }}
{{ $loadType := get_load_relation_type $.Aliases $.Tables $rel "model." }}
func (o *{{$alias.UpSingular}}) Get{{ get_load_relation_name $.Aliases $rel }}(load bool) []{{ $loadType }} {
    if o.R == nil || o.R.{{ $relAlias.Local | plural }} == nil {
        if load {
            return []{{ $loadType }}{}
        }
		return nil
	}

	{{ $relAlias.Local | plural | camelCase }} := make([]{{ $loadType }}, len(o.R.{{ $relAlias.Local | plural }}))
	for i := range o.R.{{ $relAlias.Local | plural }} {
		{{ $relAlias.Local | plural | camelCase }}[i] = o.R.{{ $relAlias.Local | plural }}[i].{{ $rel.ForeignColumn | titleCase }}
	}

	return {{ $relAlias.Local | plural | camelCase }}
}

func (o *{{$alias.UpSingular}}) Set{{ get_load_relation_name $.Aliases $rel }}({{ $relAlias.Local | plural | camelCase }} []{{ $loadType }}) {
    if {{ $relAlias.Local | plural | camelCase }} == nil {
        return
    }

    if o.R == nil {
		o.R = &{{$alias.DownSingular}}R{}
	}

	o.R.{{ $relAlias.Local | plural }} =  make({{$ftable.UpSingular}}Slice, len({{ $relAlias.Local | plural | camelCase }}))
	for i := range {{ $relAlias.Local | plural | camelCase }} {
        o.R.{{ $relAlias.Local | plural }}[i] = &{{$ftable.UpSingular}}{
            {{ $rel.ForeignColumn | titleCase }}: {{ $relAlias.Local | plural | camelCase }}[i],
        }
	}
}
{{end}}

func Get{{$alias.UpSingular}}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, {{ $pkArgs }}) (*model.{{$alias.UpSingular}}, error) {
    // Create queryMods from SelectedFields as nil, which will load all relations by default,
    // which is expected when using the Get-method
    queryMods := getQueryModsFrom{{$alias.UpSingular}}QuerySelectedFields(nil)

    // Add the primary keys to the query
    {{- range $pkName := $pkNames }}
        queryMods = append(queryMods, {{$alias.UpSingular}}Where.{{ $pkName | titleCase }}.EQ({{ $pkName }}))
    {{ end }}

    {{$alias.DownSingular}}, err := {{$alias.UpPlural}}(queryMods...).One({{if not $.NoContext}}ctx,{{end}} exec)
    if err != nil {
        return nil, err
    }
    
    return {{$alias.UpSingular}}ToModel({{$alias.DownSingular}}{{- range get_load_relations $.Tables .Table -}}, true {{ end }}), nil
}

{{- range $column := .Table.Columns -}}
	{{- $colAlias := $alias.Column $column.Name -}}
    {{- if and (not (containsAny $.Table.PKey.Columns $column.Name)) ($column.Unique) }}
	    func Get{{$alias.UpSingular}}By{{$colAlias}}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, {{ camelCase $colAlias }} {{ $column.Type }}) (*model.{{$alias.UpSingular}}, error) {
                {{$alias.DownSingular}}, err := {{$alias.UpPlural}}({{$alias.UpSingular}}Where.{{ $colAlias }}.EQ({{ camelCase $colAlias }})).One({{if not $.NoContext}}ctx,{{end}} exec)
                if err != nil {
                    return nil, err
                }
                
                return {{$alias.UpSingular}}ToModel({{$alias.DownSingular}}{{- range get_load_relations $.Tables .Table -}}, true {{ end }}), nil
        }
    {{ end }}
{{end -}}

func List{{$alias.UpPlural}}({{if .NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, query model.{{$alias.UpSingular}}Query) ([]*model.{{$alias.UpSingular}}, *types.Int64, error) {
	queryModsForCount, queryModsWithPagination := getQueryModsFrom{{$alias.UpSingular}}Query(query)

	{{$alias.DownPlural}}, err := {{$alias.UpPlural}}(queryModsWithPagination...).All({{if not .NoContext}}ctx,{{end}} exec)
	if err != nil {
		return nil, nil, err
	}

    var (
        {{- range $rel := get_load_relations $.Tables .Table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            load{{$relAlias.Local | singular}} bool = true
        {{ end }}
    )

    if query.SelectedFields != nil {
        {{- range $rel := get_load_relations $.Tables .Table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            load{{$relAlias.Local | singular}} = query.SelectedFields.{{$relAlias.Local | singular }}IDs.Bool()
        {{ end -}}
    }

    // If offset and limit is nil, pagination is not used.
    // So if this happens we do not have to call the DB to get the total count without pagination.
    if query.Offset.IsNil() && query.Limit.IsNil() {
        return {{$alias.UpSingular}}ToModels({{$alias.DownPlural}}{{- range $rel := get_load_relations $.Tables .Table -}}{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}, load{{$relAlias.Local | singular }} {{ end }}), types.NewInt64(int64(len({{$alias.DownPlural}}))).Ptr(), nil
    }

    // Get the total count without pagination
	{{$alias.DownPlural}}Count, err := {{$alias.UpPlural}}(queryModsForCount...).Count({{if not .NoContext}}ctx,{{end}}  exec)
	if err != nil {
		return nil, nil, err
	}

	return {{$alias.UpSingular}}ToModels({{$alias.DownPlural}}{{- range $rel := get_load_relations $.Tables .Table -}}{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}, load{{$relAlias.Local | singular }} {{ end }}), types.NewInt64({{$alias.DownPlural}}Count).Ptr(), nil
}

{{ range $fKey := .Table.FKeys -}}
func List{{$alias.UpPlural}}By{{ titleCase $fKey.Column }}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, {{ camelCase $fKey.Column }} types.UUID) ([]*model.{{$alias.UpSingular}}, error) {
    {{$alias.DownPlural}}, err := {{$alias.UpPlural}}({{$alias.UpSingular}}Where.{{ titleCase $fKey.Column }}.EQ({{ camelCase $fKey.Column }})).All({{if not $.NoContext}}ctx,{{end}} exec)
	if err != nil {
		return nil, err
	}
    
    return {{$alias.UpSingular}}ToModels({{$alias.DownPlural}}{{- range get_load_relations $.Tables $.Table -}}, true {{ end }}), nil
}
{{ end }}

func {{$alias.UpSingular}}FromModel(model *model.{{$alias.UpSingular}}) *{{$alias.UpSingular}} {
    {{$alias.DownSingular}} := &{{$alias.UpSingular}}{
        {{ range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}
            {{$colAlias}}: model.{{$colAlias}}{{ if (isEnumDBType .DBType) }}.String{{ end }},
        {{ end -}}
    }
    {{ range $rel := get_load_relations $.Tables .Table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        {{$alias.DownSingular}}.Set{{ get_load_relation_name $.Aliases $rel }}(model.{{ get_load_relation_name $.Aliases $rel }})
    {{end -}}{{- /* range relationships */ -}}
    return  {{$alias.DownSingular}}
}

func {{$alias.UpSingular}}ToModel(toModel *{{$alias.UpSingular}}{{ range $rel := get_load_relations $.Tables .Table -}}{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}, load{{$relAlias.Local | singular}} bool{{ end }}) *model.{{$alias.UpSingular}} {
    return &model.{{$alias.UpSingular}}{
        {{- range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name}}
            {{$colAlias}}: {{ if (isEnumDBType .DBType) }}{{- $enumName := parseEnumName .DBType -}} model.{{ titleCase $enumName }}FromString(toModel.{{$colAlias}}) {{ else }} toModel.{{$colAlias}} {{ end }},
        {{- end}}
        {{ range $rel := get_load_relations $.Tables .Table -}}
            {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            {{ get_load_relation_name $.Aliases $rel }}: toModel.Get{{ get_load_relation_name $.Aliases $rel }}(load{{$relAlias.Local | singular}}),
        {{end -}}{{- /* range relationships */ -}}
    }
}

func {{$alias.UpSingular}}ToModels(toModels []*{{$alias.UpSingular}}{{ range $rel := get_load_relations $.Tables .Table -}}{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}, load{{$relAlias.Local | singular}} bool{{ end }}) []*model.{{$alias.UpSingular}} {
    models := make([]*model.{{$alias.UpSingular}}, len(toModels))
    for i := range toModels {
        models[i] = {{$alias.UpSingular}}ToModel(toModels[i]{{ range $rel := get_load_relations $.Tables .Table -}}{{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}, load{{$relAlias.Local | singular}}{{ end }})
    }
    return models
}

func getQueryModsFrom{{$alias.UpSingular}}Query(q model.{{$alias.UpSingular}}Query) ([]qm.QueryMod, []qm.QueryMod) {
    queryWrapperFunc := func(queryMod qm.QueryMod) qm.QueryMod {
        if q.OrCondition.Bool() {
            return qm.Or2(queryMod)
        }
        return queryMod
    }

    queryForCount := getQueryModsFrom{{$alias.UpSingular}}QueryParams(q.Params, queryWrapperFunc)
    queryForCount = append(queryForCount, getQueryModsFrom{{$alias.UpSingular}}QueryForJoin(q)...)

    queryWithPagination := queryForCount
    queryWithPagination = append(queryWithPagination, getQueryModsFrom{{$alias.UpSingular}}QuerySelectedFields(q.SelectedFields)...)
    queryWithPagination = append(queryWithPagination, getQueryModsFrom{{$alias.UpSingular}}QueryOrderBy(q.OrderBy)...)

    for i := range q.Nested {
        queryWithPagination = append(queryWithPagination, getQueryModsFrom{{$alias.UpSingular}}QueryNested(&q.Nested[i], q.OrConditionNested.Bool())...)
    }

    // If offset and limit is nil, do not append them to the query
    if q.Offset.IsNil() && q.Limit.IsNil() {
        return queryForCount, queryWithPagination
    }

    queryWithPagination = append(queryWithPagination, []qm.QueryMod{
		qm.Offset(q.Offset.Int()),
		qm.Limit(q.Limit.Int()),
	}...)

    return queryForCount, queryWithPagination
}

func getQueryModsFrom{{$alias.UpSingular}}QueryNested(q *model.{{$alias.UpSingular}}QueryNested, orConditionNested bool) []qm.QueryMod {
	queryWrapperFunc := func(queryMod qm.QueryMod) qm.QueryMod {
		if q.OrCondition.Bool() {
			return qm.Or2(queryMod)
		}
		return queryMod
	}

	query := []qm.QueryMod{}
	query = append(query, getQueryModsFrom{{$alias.UpSingular}}QueryParams(q.Params, queryWrapperFunc)...)

	if orConditionNested {
		query = []qm.QueryMod{qm.Or2(qm.Expr(query...))}
	}

    if q.Nested != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}QueryNested(q.Nested, q.OrConditionNested.Bool())...)
    }

	return query
}

func getQueryModsFrom{{$alias.UpSingular}}QuerySelectedFields(q *model.{{$alias.UpSingular}}QuerySelectedFields) []qm.QueryMod {
    query := []qm.QueryMod{}
    selectedFields := []string{}

    {{ if ne (len $pkNames) 0 }}
    // Always select primary keys as distinct (required when joining on many2many relationships)
    primaryKeys := []string{}
    {{- range $pkName := $pkNames }}
        primaryKeys = append(primaryKeys, {{$alias.UpSingular}}TableColumns.{{$pkName | titleCase}})
    {{- end}}
        selectedFields = append(selectedFields, "DISTINCT ("+ strings.Join(primaryKeys, ", ") + ")")
    {{end}}

    // If there are no selected fields, all fields will be selected by default,
    // therefore we to load the relations as well, to get the expected result.
    if q == nil {
        selectedFields = append(selectedFields, strmangle.PrefixStringSlice(TableNames.{{$alias.UpSingular}} + ".", {{$alias.DownSingular}}AllColumns)...)
        query = append(query, qm.Select(strings.Join(selectedFields, ", ")))
        {{ range $rel := get_load_relations $.Tables .Table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            query = append(query, qm.Load({{$alias.UpSingular}}Rels.{{ $relAlias.Local | plural }}))
        {{ end -}}

        return query
    }

    {{ range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        if q.{{$colAlias}}.Bool() {
            selectedFields = append(selectedFields, {{$alias.UpSingular}}TableColumns.{{$colAlias}})
        }
    {{- end}}

    query = append(query, qm.Select(strings.Join(selectedFields, ", ")))

    {{ range $rel := get_load_relations $.Tables .Table -}}
    {{ $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if q.{{$relAlias.Local | singular }}IDs.Bool() {
            query = append(query, qm.Load({{$alias.UpSingular}}Rels.{{ $relAlias.Local | plural }}))
        }
    {{ end }}

    return query
}

func getQueryModsFrom{{$alias.UpSingular}}QueryParams(q model.{{$alias.UpSingular}}QueryParams, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}

    if q.Equals != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}EQ(q.Equals, queryWrapperFunc)...)
    }
    if q.NotEquals != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}NEQ(q.NotEquals, queryWrapperFunc)...)
    }

    if q.Empty != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}Empty(q.Empty, queryWrapperFunc)...)
    }
    if q.NotEmpty != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}NotEmpty(q.NotEmpty, queryWrapperFunc)...)
    }

    if q.In != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}In(q.In, queryWrapperFunc)...)
    }
    if q.NotIn != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}NotIn(q.NotIn, queryWrapperFunc)...)
    }

    if q.GreaterThan != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}GreaterThan(q.GreaterThan, queryWrapperFunc)...)
    }
    if q.SmallerThan != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}SmallerThan(q.SmallerThan, queryWrapperFunc)...)
    }

    if q.GreaterOrEqual != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}GreaterOrEqual(q.GreaterOrEqual, queryWrapperFunc)...)
    }
    if q.SmallerOrEqual != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}SmallerOrEqual(q.SmallerOrEqual, queryWrapperFunc)...)
    }

    if q.Like != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}Like(q.Like, queryWrapperFunc)...)
    }
    if q.NotLike != nil {
        query = append(query, getQueryModsFrom{{$alias.UpSingular}}NotLike(q.NotLike, queryWrapperFunc)...)
    }

    return query
}

func getQueryModsFrom{{$alias.UpSingular}}EQ(q *model.{{$alias.UpSingular}}QueryParamsFields, queryWrapperFunc func(q qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if not (hasSuffix "JSON" $column.Type) -}}
            if q.{{$colAlias}}.IsDefined() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.EQ(q.{{$colAlias}}{{ if (isEnumDBType .DBType) }}.String{{ end }})))
            }
        {{- end}}
    {{- end}}
    {{ range $rel := get_join_relations $.Tables .Table -}}
        {{$schemaJoinTable := $rel.JoinTable | $.SchemaTable -}}

        if q.{{ get_load_relation_name $.Aliases $rel | singular }}.IsDefined() {
            query = append(query, queryWrapperFunc(qm.Where("{{ $schemaJoinTable }}.{{$rel.JoinForeignColumn | $.Quotes}} = ?", q.{{ get_load_relation_name $.Aliases $rel | singular }})))
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}NEQ(q *model.{{$alias.UpSingular}}QueryParamsFields, queryWrapperFunc func(q qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if not (hasSuffix "JSON" $column.Type) -}}
            if q.{{$colAlias}}.IsDefined() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.NEQ(q.{{$colAlias}}{{ if (isEnumDBType .DBType) }}.String{{ end }})))
            }
        {{- end}}
    {{- end}}
    {{ range $rel := get_join_relations $.Tables .Table -}}
        {{$schemaJoinTable := $rel.JoinTable | $.SchemaTable -}}

        if q.{{ get_load_relation_name $.Aliases $rel | singular }}.IsDefined() {
            query = append(query, queryWrapperFunc(qm.Where("{{ $schemaJoinTable }}.{{$rel.JoinForeignColumn | $.Quotes}} != ?", q.{{ get_load_relation_name $.Aliases $rel | singular }})))
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}Empty(q *model.{{$alias.UpSingular}}QueryParamsNullableFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{if $column.Nullable -}}
        {{- $colAlias := $alias.Column $column.Name}}
            if q.{{$colAlias}}.Bool() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.IsNull()))
            }
        {{- end}}
    {{- end}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}NotEmpty(q *model.{{$alias.UpSingular}}QueryParamsNullableFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{if $column.Nullable -}}
        {{- $colAlias := $alias.Column $column.Name}}
            if q.{{$colAlias}}.Bool() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.IsNotNull()))
            }
        {{- end}}
    {{- end}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}In(q *model.{{$alias.UpSingular}}QueryParamsInFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{- if not (isEnumDBType .DBType) }}
        {{- if or (contains $column.Type $stringTypes) (hasPrefix "types.Int" $column.Type) }}
            if q.{{$colAlias}} != nil {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.IN(q.{{$colAlias}})))
            }
        {{- end}}
        {{- end}}
    {{- end}}

    {{ range $rel := get_join_relations $.Tables .Table -}}
        {{$schemaJoinTable := $rel.JoinTable | $.SchemaTable -}}
        {{$loadCol := get_load_relation_column $.Aliases $.Tables $rel -}}
        {{$whereHelper := printf "whereHelper%s" (goVarname $loadCol.Type) -}}

        if q.{{ get_load_relation_name $.Aliases $rel | singular }} != nil {
            query = append(query, queryWrapperFunc({{ $whereHelper }}{"{{ $schemaJoinTable }}.{{$rel.JoinForeignColumn | $.Quotes}}"}.IN(q.{{ get_load_relation_name $.Aliases $rel | singular }})))
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}NotIn(q *model.{{$alias.UpSingular}}QueryParamsInFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{- if and (not (isEnumDBType .DBType)) (or (eq "types.String" $column.Type) (eq "types.UUID" $column.Type)) }}
            if q.{{$colAlias}} != nil {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.NIN(q.{{$colAlias}})))
            }
        {{- end}}
    {{- end}}

    {{ range $rel := get_join_relations $.Tables .Table -}}
        {{$schemaJoinTable := $rel.JoinTable | $.SchemaTable -}}
        {{$loadCol := get_load_relation_column $.Aliases $.Tables $rel -}}
        {{$whereHelper := printf "whereHelper%s" (goVarname $loadCol.Type) -}}

        if q.{{ get_load_relation_name $.Aliases $rel | singular }} != nil {
            query = append(query, queryWrapperFunc({{ $whereHelper }}{"{{ $schemaJoinTable }}.{{$rel.JoinForeignColumn | $.Quotes}}"}.NIN(q.{{ get_load_relation_name $.Aliases $rel | singular }})))
        }
    {{end -}}{{- /* range relationships */ -}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}GreaterThan(q *model.{{$alias.UpSingular}}QueryParamsComparableFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if or (hasPrefix "date" $column.DBType) (hasPrefix "int" $column.DBType) (hasPrefix "time" $column.DBType) -}}
            if q.{{$colAlias}}.IsDefined() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.GT(q.{{$colAlias}})))
            }
        {{- end}}
    {{- end}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}SmallerThan(q *model.{{$alias.UpSingular}}QueryParamsComparableFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if or (hasPrefix "date" $column.DBType) (hasPrefix "int" $column.DBType) (hasPrefix "time" $column.DBType) -}}
            if q.{{$colAlias}}.IsDefined() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.LT(q.{{$colAlias}})))
            }
        {{- end}}
    {{- end}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}GreaterOrEqual(q *model.{{$alias.UpSingular}}QueryParamsComparableFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if or (hasPrefix "date" $column.DBType) (hasPrefix "int" $column.DBType) (hasPrefix "time" $column.DBType) -}}
            if q.{{$colAlias}}.IsDefined() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.GTE(q.{{$colAlias}})))
            }
        {{- end}}
    {{- end}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}SmallerOrEqual(q *model.{{$alias.UpSingular}}QueryParamsComparableFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if or (hasPrefix "date" $column.DBType) (hasPrefix "int" $column.DBType) (hasPrefix "time" $column.DBType) -}}
            if q.{{$colAlias}}.IsDefined() {
                query = append(query, queryWrapperFunc({{$alias.UpSingular}}Where.{{$colAlias}}.LTE(q.{{$colAlias}})))
            }
        {{- end}}
    {{- end}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}Like(q *model.{{$alias.UpSingular}}QueryParamsLikeFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if and (hasSuffix "String" $column.Type) (not (isEnumDBType .DBType)) -}}
            if q.{{$colAlias}}.IsDefined() {
                query = append(query, queryWrapperFunc(qm.Where("%s LIKE ?", {{$alias.UpSingular}}Where.{{$colAlias}}.field, "%"+q.{{$colAlias}}.String()+"%s")))
            }
        {{- end}}
    {{- end}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}NotLike(q *model.{{$alias.UpSingular}}QueryParamsLikeFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{if and (hasSuffix "String" $column.Type) (not (isEnumDBType .DBType)) -}}
            if q.{{$colAlias}}.IsDefined() {
                query = append(query, queryWrapperFunc(qm.Where("%s NOT LIKE ?", {{$alias.UpSingular}}Where.{{$colAlias}}.field, "%"+q.{{$colAlias}}.String()+"%s")))
            }
        {{- end}}
    {{- end}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}QueryForJoin(q model.{{$alias.UpSingular}}Query) []qm.QueryMod {
    {{ range $rel := get_join_relations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        join{{$relAlias.Local | singular }} := false
    {{end }}

    checkParams := func(p model.{{$alias.UpSingular}}QueryParams) {
    {{ range $rel := get_join_relations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if p.Equals != nil {
            if p.Equals.{{ get_load_relation_name $.Aliases $rel | singular }}.IsDefined() {
                join{{$relAlias.Local | singular }} = true
            }
        }
        if p.NotEquals != nil {
            if p.NotEquals.{{ get_load_relation_name $.Aliases $rel | singular }}.IsDefined() {
                join{{$relAlias.Local | singular }} = true
            }
        }
        if p.In != nil {
            if p.In.{{ get_load_relation_name $.Aliases $rel | singular }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
        }
        if p.NotIn != nil {
            if p.NotIn.{{ get_load_relation_name $.Aliases $rel | singular }} != nil {
                join{{$relAlias.Local | singular }} = true
            }
        }
    {{end -}}{{- /* range relationships */ -}}
    }

    checkParams(q.Params)
	for _, nested := range q.Nested {
		check{{$alias.UpSingular}}QueryParamsRecursive(checkParams, nested)
	}

    query := []qm.QueryMod{}
    {{ range $rel := get_join_relations $.Tables .Table -}}
    {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
    {{- $schemaJoinTable := $rel.JoinTable | $.SchemaTable -}}
        if join{{$relAlias.Local | singular }} {
            query = append(query, qm.InnerJoin("{{$schemaJoinTable}} on {{ $rel.Table | $.Quotes}}.{{$rel.ForeignColumn | $.Quotes}} = {{$schemaJoinTable}}.{{$rel.JoinLocalColumn | $.Quotes}}"))
        }
    {{end }}

    return query
}

func getQueryModsFrom{{$alias.UpSingular}}QueryOrderBy(q *model.{{$alias.UpSingular}}QueryOrderBy) []qm.QueryMod {
    getOrder := func(desc bool) string {
        if desc {
            return "desc"
        }
        return "asc"
    }

    type orderByField struct {
        field string
        order  string
        index  int
    }

    var orderByFields []orderByField
    if q != nil {
        {{- range $column := .Table.Columns}}
        {{- $colAlias := $alias.Column $column.Name}}
                if q.{{$colAlias}} != nil {
                    orderByFields = append(orderByFields, orderByField{
                        field: {{$alias.UpSingular}}TableColumns.{{$colAlias}},
                        order: getOrder(q.{{$colAlias}}.Desc),
                        index: q.{{$colAlias}}.Index,
                    })
                }
        {{- end}}
    }

    sort.Slice(orderByFields, func(i, j int) bool {
        return orderByFields[i].index < orderByFields[j].index
    })

    orderByStrings := []string{}
    for _, o := range orderByFields {
        orderByStrings = append(orderByStrings, o.field + " " + o.order)
    }

    {{- range $pkName := $pkNames }}
        orderByStrings = append(orderByStrings, {{$alias.UpSingular}}TableColumns.{{$pkName | titleCase}} + " asc") // Always order by primary key first as ascending to keep consistency
    {{- end}}

	return []qm.QueryMod{
        qm.OrderBy(strings.Join(orderByStrings, ",")),
    }
}

func check{{$alias.UpSingular}}QueryParamsRecursive(checkParamsFunc func(model.{{$alias.UpSingular}}QueryParams), nested model.{{$alias.UpSingular}}QueryNested) {
	checkParamsFunc(nested.Params)

	if nested.Nested != nil {
		check{{$alias.UpSingular}}QueryParamsRecursive(checkParamsFunc, *nested.Nested)
	}
}

{{- range .Table.Columns -}}
{{- if (oncePut $.DBTypes .Type)}}
{{- if not (or (isPrimitive .Type) (isNullPrimitive .Type) (isEnumDBType .DBType)) -}}
{{- if or (contains .Type $stringTypes) (hasPrefix "types.Int" .Type) }}

{{$name := printf "whereHelper%s" (goVarname .Type)}}

func (w {{$name}}) IN(slice []{{.Type}}) qm.QueryMod {
	values := make([]interface{}, 0, len(slice))
	for _, value := range slice {
		values = append(values, value)
	}
	return qm.WhereIn(w.field + " IN ?", values...)
}
func (w {{$name}}) NIN(slice []{{.Type}}) qm.QueryMod {
	values := make([]interface{}, 0, len(slice))
	for _, value := range slice {
	  values = append(values, value)
	}
	return qm.WhereNotIn(w.field + " NOT IN ?", values...)
}

{{end}}
{{end}}
{{end}}
{{end}}

{{end -}}

// Init blank variables since these packages might not be needed
var (
	_ = strconv.IntSize
    _ = time.Now // For setting timestamps to entities
    _ = uuid.Nil // For generation UUIDs to entities
)
