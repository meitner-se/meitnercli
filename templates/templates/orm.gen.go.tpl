{{- if .Table.IsView -}}
{{- else -}}
{{- $alias := .Aliases.Table .Table.Name -}}
{{- $colDefs := sqlColDefinitions .Table.Columns .Table.PKey.Columns -}}
{{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap .StringFuncs.camelCase | stringMap .StringFuncs.replaceReserved -}}
{{- $pkArgs := joinSlices " " $pkNames $colDefs.Types | join ", " -}}
{{- $schemaTable := .Table.Name | .SchemaTable}}

// InsertDefined inserts {{$alias.UpSingular}} with the defined values only.
func (o *{{$alias.UpSingular}}) InsertDefined({{if .NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, auditLog audit.Log) error {
    auditLogValues := []audit.LogValue{}
    whitelist := boil.Whitelist() // whitelist each column that has a defined value

    {{range $column := .Table.Columns}}
    {{$colAlias := $alias.Column $column.Name}}
        {
            {{- if not $column.Nullable -}}
                if o.{{$colAlias}}.IsNil() {
                    return errors.New("{{$column.Name}} cannot be null")
                }
            {{- end}}
            if o.{{$colAlias}}.IsDefined() {
                auditLogValues = append(auditLogValues, audit.LogValue{Column: {{$alias.UpSingular}}Columns.{{$colAlias}}, New: o.{{$colAlias}}, Old: nil})
                whitelist.Cols = append(whitelist.Cols, {{$alias.UpSingular}}Columns.{{$colAlias}})
            }
        }
    {{- end}}

    if o.R != nil {
    {{range $rel := .Table.ToManyRelationships -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if o.R.{{$relAlias.Local | plural }} != nil {
            auditLogValues = append(auditLogValues, audit.LogValue{Column: model.{{$alias.UpSingular}}Column{{$relAlias.Local | singular}}IDs, New: o.Get{{$relAlias.Local | singular}}IDs(), Old: nil})
            err := o.Add{{$relAlias.Local | plural}}(ctx, exec, false, o.R.{{$relAlias.Local | plural }}...)
            if err != nil {
                return err
            }
        }
    {{end -}}{{- /* range relationships */ -}}
    }

    err := o.Insert(ctx, exec, whitelist)
	if err != nil {
		return err
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
        {
            if newValues.{{$colAlias}}.IsDefined() {{ if ne $column.Type "types.JSON" }}&& newValues.{{$colAlias}} != o.{{$colAlias}} {{end}} {
                {{- if not $column.Nullable -}}
                    if newValues.{{$colAlias}}.IsNil() {
                        return errors.New("{{$column.Name}} cannot be null")
                    }
                {{- end}}
                auditLogValues = append(auditLogValues, audit.LogValue{Column: {{$alias.UpSingular}}Columns.{{$colAlias}}, New: newValues.{{$colAlias}}, Old: o.{{$colAlias}}})
                whitelist.Cols = append(whitelist.Cols, {{$alias.UpSingular}}Columns.{{$colAlias}})
                o.{{$colAlias}} = newValues.{{$colAlias}}
            }
        }
    {{- end}}

    // Check if any join tables should be updated and load the existing values before updating if we have an operating audit log
    if newValues.R != nil {
        {{range $rel := .Table.ToManyRelationships -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if newValues.R.{{$relAlias.Local | plural }} != nil {
            if !audit.IsNoop(auditLog) {
                {{$relAlias.Local | singular | camelCase }}Slice, err := o.{{$relAlias.Local | plural }}(qm.Select({{$relAlias.Local | singular }}Columns.ID)).All(ctx, exec)
                if err != nil {
                    return err
                }

                if o.R == nil {
                    o.R = o.R.NewStruct()
                }
                
                o.R.{{$relAlias.Local}} = {{$relAlias.Local | singular | camelCase }}Slice
            }
        }

        auditLogValues = append(auditLogValues, audit.LogValue{Column: model.{{$alias.UpSingular}}Column{{$relAlias.Local | singular}}IDs, New: newValues.Get{{$relAlias.Local | singular}}IDs(), Old: o.Get{{$relAlias.Local | singular}}IDs()})
        err := o.Add{{$relAlias.Local | plural}}(ctx, exec, false, newValues.R.{{$relAlias.Local | plural }}...)
        if err != nil {
            return err
        }
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

{{ range $rel := .Table.ToManyRelationships -}}
{{ $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
func (o *{{$alias.UpSingular}}) Get{{ $relAlias.Local | singular }}IDs() []types.UUID {
    if o.R == nil {
		return nil
	}
	if o.R.{{ $relAlias.Local | plural }} == nil {
		return nil
	}

	ids := make([]types.UUID, len(o.R.{{ $relAlias.Local | plural }}))
	for i := range o.R.{{ $relAlias.Local | plural }} {
		ids[i] = o.R.{{ $relAlias.Local | plural }}[i].ID
	}

	return ids
}

func (o *{{$alias.UpSingular}}) Set{{ $relAlias.Local | singular }}IDs(ids []types.UUID) {
    if ids == nil {
        return
    }

    if o.R == nil {
		o.R = &{{$alias.DownSingular}}R{}
	}

	o.R.{{ $relAlias.Local | plural }} =  make({{ $relAlias.Local | singular }}Slice, len(ids))
	for i := range ids {
        o.R.{{ $relAlias.Local | plural }}[i].ID = ids[i]
	}
}
{{end}}

func Get{{$alias.UpSingular}}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, {{ $pkArgs }}) (*model.{{$alias.UpSingular}}, error) {        
    {{$alias.DownSingular}}, err := Find{{$alias.UpSingular}}({{if not $.NoContext}}ctx,{{end}} exec, {{ $pkNames | join ", " }})
    if err != nil {
        return nil, err
    }
    
    return {{$alias.UpSingular}}ToModel({{$alias.DownSingular}}), nil
}

{{- range $column := .Table.Columns -}}
	{{- $colAlias := $alias.Column $column.Name -}}
    {{- if and (not (containsAny $.Table.PKey.Columns $column.Name)) ($column.Unique) }}
	    func Get{{$alias.UpSingular}}By{{$colAlias}}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, {{ camelCase $colAlias }} {{ $column.Type }}) (*model.{{$alias.UpSingular}}, error) {
                {{$alias.DownSingular}}, err := {{$alias.UpPlural}}({{$alias.UpSingular}}Where.{{ $colAlias }}.EQ({{ camelCase $colAlias }})).One({{if not $.NoContext}}ctx,{{end}} exec)
                if err != nil {
                    return nil, err
                }
                
                return {{$alias.UpSingular}}ToModel({{$alias.DownSingular}}), nil
        }
    {{ end }}
{{end -}}

func List{{$alias.UpPlural}}({{if .NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, query model.{{$alias.UpSingular}}Query) ([]*model.{{$alias.UpSingular}}, *types.Int64, error) {
	queryModsForCount, queryModsWithPagination := getQueryModsFrom{{$alias.UpSingular}}Query(query)

	{{$alias.DownPlural}}, err := {{$alias.UpPlural}}(queryModsWithPagination...).All({{if not .NoContext}}ctx,{{end}} exec)
	if err != nil {
		return nil, nil, err
	}

    // If offset and limit is nil, pagination is not used.
    // So if this happens we do not have to call the DB to get the total count without pagination.
    if query.Offset.IsNil() && query.Limit.IsNil() {
        return {{$alias.UpSingular}}ToModels({{$alias.DownPlural}}), types.NewInt64(int64(len({{$alias.DownPlural}}))).Ptr(), nil
    }

    // Get the total count without pagination
	{{$alias.DownPlural}}Count, err := {{$alias.UpPlural}}(queryModsForCount...).Count({{if not .NoContext}}ctx,{{end}}  exec)
	if err != nil {
		return nil, nil, err
	}

	return {{$alias.UpSingular}}ToModels({{$alias.DownPlural}}), types.NewInt64({{$alias.DownPlural}}Count).Ptr(), nil
}

{{ range $fKey := .Table.FKeys -}}
func List{{$alias.UpPlural}}By{{ titleCase $fKey.Column }}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, {{ camelCase $fKey.Column }} types.UUID) ([]*model.{{$alias.UpSingular}}, error) {
    {{$alias.DownPlural}}, err := {{$alias.UpPlural}}({{$alias.UpSingular}}Where.{{ titleCase $fKey.Column }}.EQ({{ camelCase $fKey.Column }})).All({{if not $.NoContext}}ctx,{{end}} exec)
	if err != nil {
		return nil, err
	}
    
    return {{$alias.UpSingular}}ToModels({{$alias.DownPlural}}), nil
}
{{ end }}

func {{$alias.UpSingular}}FromModel(model *model.{{$alias.UpSingular}}) *{{$alias.UpSingular}} {
    {{$alias.DownSingular}} := &{{$alias.UpSingular}}{
        {{ range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}
            {{$colAlias}}: model.{{$colAlias}}{{ if (isEnumDBType .DBType) }}.String{{ end }},
        {{ end -}}
    }
    {{range $rel := .Table.ToManyRelationships -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        {{$alias.DownSingular}}.Set{{$relAlias.Local | singular}}IDs(model.{{$relAlias.Local | singular}}IDs)
    {{end -}}{{- /* range relationships */ -}}
    return  {{$alias.DownSingular}}
}

func {{$alias.UpSingular}}ToModel(toModel *{{$alias.UpSingular}}) *model.{{$alias.UpSingular}} {
    return &model.{{$alias.UpSingular}}{
        {{- range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name}}
            {{$colAlias}}: {{ if (isEnumDBType .DBType) }}{{- $enumName := parseEnumName .DBType -}} model.{{ titleCase $enumName }}FromString(toModel.{{$colAlias}}) {{ else }} toModel.{{$colAlias}} {{ end }},
        {{- end}}
        {{range $rel := .Table.ToManyRelationships -}}
            {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            {{$relAlias.Local | singular}}IDs: toModel.Get{{$relAlias.Local | singular}}IDs(),
        {{end -}}{{- /* range relationships */ -}}
    }
}

func {{$alias.UpSingular}}ToModels(toModels []*{{$alias.UpSingular}}) []*model.{{$alias.UpSingular}} {
    models := make([]*model.{{$alias.UpSingular}}, len(toModels))
    for i := range toModels {
        models[i] = {{$alias.UpSingular}}ToModel(toModels[i])
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

    queryForCount := []qm.QueryMod{}
    queryWithPagination := []qm.QueryMod{}

    queryForCount = append(queryForCount, getQueryModsFrom{{$alias.UpSingular}}QueryParams(q.Params, queryWrapperFunc)...)
    queryWithPagination = queryForCount
    queryWithPagination = append(queryWithPagination, getQueryModsFrom{{$alias.UpSingular}}QuerySelectedFields(q.SelectedFields)...)
    queryWithPagination = append(queryWithPagination, getQueryModsFrom{{$alias.UpSingular}}QueryJoin(q.Join)...)
    queryWithPagination = append(queryWithPagination, getQueryModsFrom{{$alias.UpSingular}}QueryLoad(q.Load)...)
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
    if q == nil {
        return nil
    }

    query := []qm.QueryMod{}

    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        if q.{{$colAlias}}.Bool() {
            query = append(query, qm.Select({{$alias.UpSingular}}TableColumns.{{$colAlias}}))
        }
    {{- end}}

    return query
}

func getQueryModsFrom{{$alias.UpSingular}}QueryParams(q model.{{$alias.UpSingular}}QueryParams, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}

    {
        if q.Equals != nil {
            query = append(query, getQueryModsFrom{{$alias.UpSingular}}EQ(q.Equals, queryWrapperFunc)...)
        }
        if q.NotEquals != nil {
            query = append(query, getQueryModsFrom{{$alias.UpSingular}}NEQ(q.NotEquals, queryWrapperFunc)...)
        }
    }
  
    {
        if q.Empty != nil {
            query = append(query, getQueryModsFrom{{$alias.UpSingular}}Empty(q.Empty, queryWrapperFunc)...)
        }
        if q.NotEmpty != nil {
            query = append(query, getQueryModsFrom{{$alias.UpSingular}}NotEmpty(q.NotEmpty, queryWrapperFunc)...)
        }
    }

    {
        if q.GreaterThan != nil {
            query = append(query, getQueryModsFrom{{$alias.UpSingular}}GreaterThan(q.GreaterThan, queryWrapperFunc)...)
        }
        if q.SmallerThan != nil {
            query = append(query, getQueryModsFrom{{$alias.UpSingular}}SmallerThan(q.SmallerThan, queryWrapperFunc)...)
        }
    }

    {
        if q.GreaterOrEqual != nil {
            query = append(query, getQueryModsFrom{{$alias.UpSingular}}GreaterOrEqual(q.GreaterOrEqual, queryWrapperFunc)...)
        }
        if q.SmallerOrEqual != nil {
            query = append(query, getQueryModsFrom{{$alias.UpSingular}}SmallerOrEqual(q.SmallerOrEqual, queryWrapperFunc)...)
        }
    }

    {
        if q.Like != nil {
            query = append(query, getQueryModsFrom{{$alias.UpSingular}}Like(q.Like, queryWrapperFunc)...)
        }
        if q.NotLike != nil {
            query = append(query, getQueryModsFrom{{$alias.UpSingular}}NotLike(q.NotLike, queryWrapperFunc)...)
        }
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
        {{- if and (not (isEnumDBType .DBType)) (or (eq "types.String" $column.Type) (eq "types.UUID" $column.Type)) }}
            if q.{{$colAlias}} != nil {
                query = append(query, queryWrapperFunc(qm.WhereIn({{$alias.UpSingular}}Where.{{$colAlias}}.field, q.{{$colAlias}})))
            }
        {{- end}}
    {{- end}}
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}NotIn(q *model.{{$alias.UpSingular}}QueryParamsInFields, queryWrapperFunc func(qm.QueryMod) qm.QueryMod) []qm.QueryMod {
    query := []qm.QueryMod{}
    {{- range $column := .Table.Columns}}
    {{- $colAlias := $alias.Column $column.Name}}
        {{- if and (not (isEnumDBType .DBType)) (or (eq "types.String" $column.Type) (eq "types.UUID" $column.Type)) }}
            if q.{{$colAlias}} != nil {
                query = append(query, queryWrapperFunc(qm.WhereNotIn({{$alias.UpSingular}}Where.{{$colAlias}}.field, q.{{$colAlias}})))
            }
        {{- end}}
    {{- end}}
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

func getQueryModsFrom{{$alias.UpSingular}}QueryJoin(q *model.{{$alias.UpSingular}}QueryJoin) []qm.QueryMod {
    if nil == q {
        return nil
    }

    query := []qm.QueryMod{}
    {{ range $rel := .Table.ToManyRelationships -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if q.{{ $relAlias.Local | singular }} != nil {
            query{{ $relAlias.Local | singular }}WrapperFunc := func(queryMod qm.QueryMod) qm.QueryMod {
                if q.{{ $relAlias.Local | singular }}.OrCondition.Bool() {
                    return qm.Or2(queryMod)
                }
                return queryMod
            }

            query = append(query, qm.InnerJoin("{{ $rel.ForeignTable }} ON {{ $rel.ForeignTable }}.{{ $rel.ForeignColumn }} = {{ $rel.Table }}.id"))
            query = append(query, getQueryModsFrom{{ $relAlias.Local | singular }}QueryParams(q.{{ $relAlias.Local | singular }}.Params, query{{ $relAlias.Local | singular }}WrapperFunc)...)
        }
    {{ end }}{{- /* range relationships */ -}}
    
    return query
}

func getQueryModsFrom{{$alias.UpSingular}}QueryLoad(q *model.{{$alias.UpSingular}}QueryLoad) []qm.QueryMod {
    if nil == q {
        return nil
    }

    query := []qm.QueryMod{}
    {{ range $rel := .Table.ToManyRelationships -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
        if q.{{ $relAlias.Local | singular }} != nil {
            query{{ $relAlias.Local | singular }}WrapperFunc := func(queryMod qm.QueryMod) qm.QueryMod {
                if q.{{ $relAlias.Local | singular }}.OrCondition.Bool() {
                    return qm.Or2(queryMod)
                }
                return queryMod
            }
            query{{ $relAlias.Local | singular }} := getQueryModsFrom{{ $relAlias.Local | singular }}QueryParams(q.{{ $relAlias.Local | singular }}.Params, query{{ $relAlias.Local | singular }}WrapperFunc)
            if !q.{{ $relAlias.Local | singular }}.Offset.IsNil() {
                    query{{ $relAlias.Local | singular }} = append(query{{ $relAlias.Local | singular }}, qm.Offset(q.{{ $relAlias.Local | singular }}.Offset.Int()))
            }
            if !q.{{ $relAlias.Local | singular }}.Limit.IsNil() {
                    query{{ $relAlias.Local | singular }} = append(query{{ $relAlias.Local | singular }}, qm.Limit(q.{{ $relAlias.Local | singular }}.Limit.Int()))
            }

            query = append(query, qm.Load({{$alias.UpSingular}}Rels.{{ $relAlias.Local | plural }}, query{{ $relAlias.Local | singular }}...))
        }
    {{ end }}{{- /* range relationships */ -}}
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
    {{- range $pkName := $pkNames }}
        orderByStrings = append(orderByStrings, {{$alias.UpSingular}}TableColumns.{{$pkName | titleCase}} + " asc") // Always order by primary key first as ascending to keep consistency
    {{- end}}
    for _, o := range orderByFields {
        orderByStrings = append(orderByStrings, "%s %s", o.field, o.order)
    }

    query := []qm.QueryMod{}
	query = append(query, qm.OrderBy(strings.Join(orderByStrings, ",")))
	return query
}

{{end -}}

// Init blank variables since these packages might not be needed
var (
	_ = strconv.IntSize
    _ = time.Now // For setting timestamps to entities
    _ = uuid.Nil // For generation UUIDs to entities
)
